//
//  SpeechListener.swift
//  GRE Words Quizzes
//
//  Live English speech-to-text built on the Speech framework. Each `listen`
//  call opens a bounded listening window:
//    * if no English speech is detected within `initialTimeout`, it returns nil
//    * once the user starts speaking, it keeps capturing until they pause for
//      `silenceTimeout`, then returns the recognized text
//  Partial results are streamed back through `onPartial` so the UI can show the
//  recognized words as they arrive.
//

import Foundation
import Speech
import AVFoundation

struct ListenResult {
    /// The recognized English text, or nil if nothing was heard.
    let transcript: String?
    /// True when actual speech (not just background noise) was detected.
    let didDetectSpeech: Bool
}

@MainActor
final class SpeechListener {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var monitor: Task<Void, Never>?

    private var continuation: CheckedContinuation<ListenResult, Never>?
    private var hasFinished = false
    private var transcript = ""
    private var speechDetected = false
    private var lastSpeechAt = Date()

    /// Streams partial recognitions to the caller (e.g. for live UI display).
    var onPartial: ((String) -> Void)?

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return speechOK && micOK
    }

    // MARK: - Listening

    func listen(initialTimeout: TimeInterval = 3.0,
                silenceTimeout: TimeInterval = 1.4,
                maxDuration: TimeInterval = 12.0) async -> ListenResult {
        guard let recognizer, recognizer.isAvailable else {
            return ListenResult(transcript: nil, didDetectSpeech: false)
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<ListenResult, Never>) in
            self.continuation = cont
            self.hasFinished = false
            self.transcript = ""
            self.speechDetected = false
            self.lastSpeechAt = Date()
            self.start(recognizer: recognizer,
                       initialTimeout: initialTimeout,
                       silenceTimeout: silenceTimeout,
                       maxDuration: maxDuration)
        }
    }

    private func start(recognizer: SFSpeechRecognizer,
                       initialTimeout: TimeInterval,
                       silenceTimeout: TimeInterval,
                       maxDuration: TimeInterval) {
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.audioEngine = engine
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            finish(transcript: nil, detected: false)
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            finish(transcript: nil, detected: false)
            return
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                        self.transcript = text
                        self.speechDetected = true
                        self.lastSpeechAt = Date()
                        self.onPartial?(text)
                    }
                    if result.isFinal {
                        self.finish(transcript: self.transcript, detected: self.speechDetected)
                        return
                    }
                }
                if error != nil {
                    self.finish(transcript: self.speechDetected ? self.transcript : nil,
                                detected: self.speechDetected)
                }
            }
        }

        monitor = Task { [weak self] in
            let startTime = Date()
            while true {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, !self.hasFinished else { return }
                let now = Date()
                if !self.speechDetected {
                    if now.timeIntervalSince(startTime) >= initialTimeout {
                        self.finish(transcript: nil, detected: false)
                        return
                    }
                } else {
                    if now.timeIntervalSince(self.lastSpeechAt) >= silenceTimeout {
                        self.finish(transcript: self.transcript, detected: true)
                        return
                    }
                    if now.timeIntervalSince(startTime) >= maxDuration {
                        self.finish(transcript: self.transcript, detected: true)
                        return
                    }
                }
            }
        }
    }

    func cancel() {
        finish(transcript: speechDetected ? transcript : nil, detected: speechDetected)
    }

    private func finish(transcript: String?, detected: Bool) {
        guard !hasFinished else { return }
        hasFinished = true

        monitor?.cancel()
        monitor = nil

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        request?.endAudio()
        task?.cancel()
        audioEngine = nil
        request = nil
        task = nil

        let cleaned = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = ListenResult(transcript: (cleaned?.isEmpty == false) ? cleaned : nil,
                                  didDetectSpeech: detected)
        let cont = continuation
        continuation = nil
        cont?.resume(returning: result)
    }
}
