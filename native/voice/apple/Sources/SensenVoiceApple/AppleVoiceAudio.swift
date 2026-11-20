import Foundation
import AVFoundation
import LiveKit
#if os(iOS)
import UIKit
#endif

@MainActor
final class AppleVoiceAudio: VoicePlatformAudio {
    private var owned = false
    private var priorAutomatic = true

    var permissionGranted: Bool {
        #if os(iOS)
        if #available(iOS 17.0, *) { return AVAudioApplication.shared.recordPermission == .granted }
        return AVAudioSession.sharedInstance().recordPermission == .granted
        #else
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        #endif
    }

    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
        let reply: @Sendable (Bool) -> Void = { granted in Task { @MainActor in completion(granted) } }
        #if os(iOS)
        if #available(iOS 17.0, *) { AVAudioApplication.requestRecordPermission(completionHandler: reply) }
        else { AVAudioSession.sharedInstance().requestRecordPermission(reply) }
        #else
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: reply)
        #endif
    }

    func activate() throws {
        #if os(iOS)
        if !owned {
            priorAutomatic = AudioManager.shared.audioSession.isAutomaticConfigurationEnabled
            owned = true
        }
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        let session = AVAudioSession.sharedInstance()
        // Stay PlayAndRecord while joined, even muted, so route/category do not churn with every mic toggle.
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        #endif
    }

    func deactivate() throws {
        #if os(iOS)
        guard owned else { return }
        defer {
            owned = false
            AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = priorAutomatic
        }
        let session = AVAudioSession.sharedInstance()
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
        try session.setCategory(.ambient, mode: .default, options: [])
        try session.setActive(true) // Godot game audio remains usable, with the normal silent-switch behavior.
        #endif
    }

    func openSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
