import Foundation
import UIKit
import SensenVoiceApple

/// GENSEN_VOICE_MEDIA_QA_V1 — explicit one-shot human start, never an automatic startup media enable.
@objc(VoiceIOS)
final class VoiceIOS: NSObject {
    @MainActor private static var controls: VoiceQAControls?
    @objc static func setup() {
        Task { @MainActor in
            guard controls == nil, Bundle.main.bundleIdentifier == VoiceQAScope.bundleID,
                  let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows }).first(where: { $0.isKeyWindow }),
                  let config = Bundle.main.object(forInfoDictionaryKey: "SensenVoiceQAScope") as? [String: Any],
                  let bytes = try? JSONSerialization.data(withJSONObject: config) else { return }
            controls = VoiceQAControls(window: window, scope: bytes)
        }
    }
}

@MainActor
private final class VoiceQAControls: NSObject {
    private let scope: Data
    private let label = UILabel()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private var observers: [NSObjectProtocol] = []
    init(window: UIWindow, scope: Data) {
        self.scope = scope
        super.init()
        let stack = UIStackView(arrangedSubviews: [label, startButton, stopButton])
        stack.axis = .vertical; stack.backgroundColor = .systemYellow; stack.spacing = 4
        stack.isLayoutMarginsRelativeArrangement = true; stack.directionalLayoutMargins = .init(top: 6, leading: 12, bottom: 6, trailing: 12)
        label.numberOfLines = 0; label.textColor = .black; label.font = .systemFont(ofSize: 12)
        label.text = VoiceQAScope.marker + "\nIsolated media QA. Microphone is not started."
        startButton.setTitle("Start media QA", for: .normal)
        stopButton.setTitle("Stop QA", for: .normal); stopButton.isEnabled = false
        startButton.addTarget(self, action: #selector(start), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stop), for: .touchUpInside)
        stack.translatesAutoresizingMaskIntoConstraints = false; window.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: window.safeAreaLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor)
        ])
        observers.append(NotificationCenter.default.addObserver(forName: Notification.Name(VoiceQAScope.marker), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopped() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in VoiceBridge.shared.stop() }
        })
    }
    @objc private func start() {
        startButton.isEnabled = false // One arm per launch; a new run requires a new launch key and backend cache.
        guard VoiceBridge.shared.startMediaQA(launchKey: NativeBridgeKey.value, scopeData: scope) else {
            label.text = VoiceQAScope.marker + "\nQA scope rejected. Restart after correcting the QA configuration."
            return
        }
        label.text = VoiceQAScope.marker + "\nQA armed for up to 10 minutes. Use the approved QA harness."
        stopButton.isEnabled = true
    }
    @objc private func stop() { VoiceBridge.shared.stop(); stopped() }
    private func stopped() {
        startButton.isEnabled = false; stopButton.isEnabled = false
        label.text = VoiceQAScope.marker + "\nQA stopped. Restart the app for another run."
    }
}
