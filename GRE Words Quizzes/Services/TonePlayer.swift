//
//  TonePlayer.swift
//  GRE Words Quizzes
//
//  Synthesizes the three short "beep-beep-beep" ready tones that signal the
//  start of a listening window. The PCM waveform is generated in memory as a
//  WAV file and played with AVAudioPlayer so no audio assets are required.
//

import AVFoundation

@MainActor
final class TonePlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    /// Plays three short beeps and returns when finished.
    func playReadyTones() async {
        let data = Self.makeThreeBeepWAV()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            do {
                let p = try AVAudioPlayer(data: data)
                p.delegate = self
                self.player = p
                p.prepareToPlay()
                p.play()
            } catch {
                resume()
            }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        resume()
    }

    private func resume() {
        let cont = continuation
        continuation = nil
        cont?.resume()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.resume() }
    }

    // MARK: - Waveform synthesis

    /// Builds a mono 16-bit PCM WAV containing three 0.14s beeps at 880 Hz
    /// separated by short silences.
    static func makeThreeBeepWAV(sampleRate: Double = 44_100,
                                 frequency: Double = 880,
                                 beepDuration: Double = 0.14,
                                 gapDuration: Double = 0.11,
                                 beepCount: Int = 3) -> Data {
        let beepSamples = Int(sampleRate * beepDuration)
        let gapSamples = Int(sampleRate * gapDuration)
        let fadeSamples = min(beepSamples / 4, Int(sampleRate * 0.01))

        var samples: [Int16] = []
        samples.reserveCapacity((beepSamples + gapSamples) * beepCount)

        for index in 0..<beepCount {
            for n in 0..<beepSamples {
                let t = Double(n) / sampleRate
                var amplitude = sin(2.0 * Double.pi * frequency * t)
                // Apply a short fade in/out to remove clicks.
                if n < fadeSamples {
                    amplitude *= Double(n) / Double(fadeSamples)
                } else if n > beepSamples - fadeSamples {
                    amplitude *= Double(beepSamples - n) / Double(fadeSamples)
                }
                let value = Int16(max(-1.0, min(1.0, amplitude * 0.6)) * Double(Int16.max))
                samples.append(value)
            }
            if index < beepCount - 1 {
                samples.append(contentsOf: repeatElement(0, count: gapSamples))
            }
        }

        return encodeWAV(samples: samples, sampleRate: Int(sampleRate))
    }

    /// Wraps raw 16-bit mono PCM samples in a minimal WAV container.
    private static func encodeWAV(samples: [Int16], sampleRate: Int) -> Data {
        let channels = 1
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = samples.count * bitsPerSample / 8

        var data = Data()
        func appendString(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func appendUInt32(_ v: UInt32) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        func appendUInt16(_ v: UInt16) { var le = v.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }

        appendString("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(UInt16(channels))
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(byteRate))
        appendUInt16(UInt16(blockAlign))
        appendUInt16(UInt16(bitsPerSample))
        appendString("data")
        appendUInt32(UInt32(dataSize))
        for sample in samples {
            var le = sample.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        return data
    }
}
