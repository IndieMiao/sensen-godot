import Foundation
import UIKit
import SensenVoiceApple

/// Kept in the application target so it reads the exact launch key used by the Apple/Google login bridges.
/// SensenVoiceApple's release gate remains false; setup only exposes authenticated unsupported capabilities.
@objc(VoiceIOS)
final class VoiceIOS: NSObject {
    @MainActor private static var started = false
    @MainActor private static var terminationObserver: NSObjectProtocol?

    @objc static func setup() {
        Task { @MainActor in
            guard !started else { return }
            started = true
            VoiceBridge.shared.start(launchKey: NativeBridgeKey.value)
            terminationObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willTerminateNotification, object: nil, queue: .main
            ) { _ in
                Task { @MainActor in VoiceBridge.shared.stop() }
            }
        }
    }
}
