//
//  Narrator.swift
//  GRE Words Quizzes
//
//  Async text-to-speech wrapper around AVSpeechSynthesizer. `speak` suspends
//  until the utterance finishes (or is cancelled) so the quiz engine can drive
//  the interaction as a simple sequential async flow.
//

import AVFoundation

@MainActor
final class Narrator: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks the given text and returns once playback completes.
    func speak(_ text: String, rate: Float = 0.46, pitch: Float = 1.0) async {
        // Make sure any previous utterance is cleared.
        stop()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.preferredVoice()
            utterance.rate = rate
            utterance.pitchMultiplier = pitch
            utterance.postUtteranceDelay = 0.1
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        resume()
    }

    private func resume() {
        let cont = continuation
        continuation = nil
        cont?.resume()
    }

    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        // Prefer a high-quality enhanced US English voice when installed.
        if let enhanced = AVSpeechSynthesisVoice.speechVoices().first(where: {
            $0.language == "en-US" && $0.quality == .enhanced
        }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }
}
