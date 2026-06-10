//
//  AudioSessionManager.swift
//  GRE Words Quizzes
//
//  Centralizes AVAudioSession configuration so that text-to-speech playback,
//  beep tones, and live speech recognition can share one session cleanly.
//

import AVFoundation

enum AudioSessionManager {
    /// Configures a play-and-record session suitable for narration + listening.
    static func activate() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal: the app can still display the transcript even if audio
            // routing fails to configure on a particular device.
            print("AudioSessionManager: failed to activate session — \(error)")
        }
    }

    static func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("AudioSessionManager: failed to deactivate session — \(error)")
        }
    }
}
