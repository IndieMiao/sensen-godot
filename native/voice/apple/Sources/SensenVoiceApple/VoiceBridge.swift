import Foundation
import AVFoundation
import LiveKit
#if os(iOS)
import UIKit
#endif

public typealias SensenVoiceCallback = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void
// Unregistration waits for in-flight delivery before an engine adapter can unload.
private final class CallbackRegistry: @unchecked Sendable {
    static let shared = CallbackRegistry()
    private let lock = NSRecursiveLock()
    private var callback: SensenVoiceCallback?
    private var context: UnsafeMutableRawPointer?
    func set(_ callback: SensenVoiceCallback?, _ context: UnsafeMutableRawPointer?) {
        lock.lock(); defer { lock.unlock() }
        self.callback = callback; self.context = context
    }
    func emit(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        text.withCString { callback?($0, context) }
    }
}
@_cdecl("sensen_voice_set_event_callback")
public func setVoiceCallback(_ callback: SensenVoiceCallback?, _ context: UnsafeMutableRawPointer?) {
    CallbackRegistry.shared.set(callback, context)
}
@_cdecl("sensen_voice_command")
public func voiceCommand(_ command: UnsafePointer<CChar>?) {
    // Retain the old in-process ABI without exposing an unvalidated media backend.
    // The app adapter is moving to authenticated VoiceWire UDP; no package currently calls this entry.
    guard let command else { return }
    let text = String(cString: command)
    Task { @MainActor in VoiceBridge.shared.legacyCommand(text) }
}

/// App integration calls start with NativeBridgeKey.value; the package does not generate or read a second key.
/// G3Spike/SPM injection and release validation are a separate change. Until then CAPS stays unsupported.
@MainActor
public final class VoiceBridge: NSObject {
    public static let shared = VoiceBridge()
    private static let releaseValidated = false
    private var transport: VoiceDatagramServer?
    private var watchdog: Timer?
    private var lifecycle: UInt64 = 0
    private var observers: [NSObjectProtocol] = []
    private lazy var controller = VoiceMediaController(audio: AppleVoiceAudio(), makeRoom: { LiveKitVoiceRoom() },
        emit: { [weak self] data in self?.emit(data) }, resetEvents: { [weak self] in self?.transport?.discardPendingEvents() })

    private override init() { super.init() }

    public func start(launchKey: String) {
        guard transport == nil, VoiceWire.validKey(launchKey) else { return }
        lifecycle &+= 1
        let turn = lifecycle
        LiveKitSDK.disableLogging() // Before creating any SDK object; grants and participant metadata are never logged.
        let server = VoiceDatagramServer(key: launchKey, mediaReady: { Self.releaseValidated },
            command: { [weak self] command in
                guard let self, self.lifecycle == turn else { return }
                self.controller.command(command)
            },
            fault: { [weak self] _ in
                guard let self, self.lifecycle == turn else { return }
                self.controller.transportFailed()
            })
        transport = server
        server.start()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lifecycle == turn else { return }
                self.controller.tick()
            }
        }
        #if os(iOS)
        controllerStateForCurrentApplication()
        observe(UIApplication.didEnterBackgroundNotification) { bridge, _ in bridge.controller.background() }
        observe(UIApplication.didBecomeActiveNotification) { bridge, _ in bridge.controller.foregrounded() }
        observe(AVAudioSession.interruptionNotification) { bridge, notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let kind = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            bridge.controller.setInterrupted(kind == .began)
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { bridge, _ in bridge.controller.interrupted() }
        #endif
    }

    public func stop() {
        lifecycle &+= 1
        controller.shutdown()
        watchdog?.invalidate(); watchdog = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        transport?.stop(); transport = nil
    }

    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (VoiceBridge, Notification) -> Void) {
        let turn = lifecycle
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                guard let self, self.lifecycle == turn else { return }
                handler(self, notification)
            }
        })
    }

    #if os(iOS)
    private func controllerStateForCurrentApplication() {
        if UIApplication.shared.applicationState == .background { controller.background() }
        else { controller.foregrounded() }
    }
    #endif

    fileprivate func legacyCommand(_ text: String) {
        guard Self.releaseValidated, let bytes = text.data(using: .utf8), bytes.count <= VoiceWire.maximumDatagramBytes,
              let body = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let op = body["op"] as? String, let id = body["session"] as? String else { return }
        // Legacy callers are in-process. All externally reachable commands use VoiceWire's key and field validation.
        switch op {
        case "request_permission": controller.command(.permission(id))
        case "disconnect_voice": controller.command(.disconnect(id))
        default: break // Legacy media operations never silently bypass the authenticated adapter's release gate.
        }
    }

    private func emit(_ data: [String: Any]) {
        guard let bytes = try? JSONSerialization.data(withJSONObject: data),
              let text = String(data: bytes, encoding: .utf8) else { return }
        CallbackRegistry.shared.emit(text)
        transport?.publish(data)
    }
}
