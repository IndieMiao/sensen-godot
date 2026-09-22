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
    guard let command else { return }
    let text = String(cString: command)
    Task { @MainActor in await VoiceBridge.shared.command(text) }
}

@MainActor
private final class VoiceBridge: NSObject, RoomDelegate, @unchecked Sendable {
    static let shared = VoiceBridge()
    private var intent = ""
    private var generation = 0
    private var desiredMic = false
    private var microphoneTask: Task<Void, Never>?
    private var current: Room?
    private var session = ""
    private var listening = true
    private var expires = 0.0
    private var watchdog: Timer?
    private var foreground = true
    private var observers: [NSObjectProtocol] = []
    override init() {
        super.init()
        #if os(iOS)
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.foreground = false; await self?.finish("BACKGROUND") }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.foreground = true }
        })
        #endif
    }
    private func emit(_ kind: String, id: String? = nil, values: [String: Any] = [:]) {
        var data = values; data["event"] = kind; data["session"] = id ?? session
        guard let bytes = try? JSONSerialization.data(withJSONObject: data), let text = String(data: bytes, encoding: .utf8) else { return }
        CallbackRegistry.shared.emit(text)
    }
    func command(_ text: String) async {
        guard let bytes = text.data(using: .utf8), let body = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any],
              let op = body["op"] as? String, let id = body["session"] as? String else { return }
        if op == "request_permission" {
            #if os(iOS)
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                Task { @MainActor in self?.emit("permission", id: id, values: ["granted": granted]) }
            }
            #else
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in self?.emit("permission", id: id, values: ["granted": granted]) }
            }
            #endif
            return
        }
        if op == "connect_voice" {
            generation += 1
            let turn = generation
            intent = id
            await finish("REPLACED", send: false, cancelIntent: false)
            guard generation == turn, intent == id else { return }
            guard foreground, let url = body["url"] as? String, let token = body["token"] as? String else {
                emit("disconnected", id: id, values: ["reason": "BACKGROUND"]); return
            }
            session = id; listening = true
            let room = Room(delegate: self)
            current = room
            expires = ProcessInfo.processInfo.systemUptime + 20
            watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.current != nil else { return }
                    if ProcessInfo.processInfo.systemUptime >= self.expires { await self.finish("VOICE_EXPIRED") }
                }
            }
            do {
                try await room.connect(url: url, token: token)
                guard current === room, session == id else { await room.disconnect(); return }
                snapshot("connected")
            } catch {
                if current === room { await finish("VOICE_CONNECT_FAILED") }
            }
            return
        }
        if op == "disconnect_voice" {
            if intent == id || session == id { await finish("LEFT") }
            return
        }
        guard session == id, let room = current else { return }
        switch op {
        case "renew_lease":
            expires = ProcessInfo.processInfo.systemUptime + Double(min(20000, max(0, body["milliseconds"] as? Int ?? 0))) / 1000
        case "disconnect_voice": await finish("LEFT")
        case "set_microphone":
            desiredMic = body["enabled"] as? Bool ?? false
            guard microphoneTask == nil else { return }
            microphoneTask = Task { @MainActor in
                while current === room, session == id, !Task.isCancelled {
                    let enabled = desiredMic
                    do { try await room.localParticipant.setMicrophone(enabled: enabled) }
                    catch { if current === room { emit("error", values: ["code": "MICROPHONE_FAILED"]) }; break }
                    if current === room { snapshot("microphone") }
                    if desiredMic == enabled { break }
                }
                if current === room { microphoneTask = nil }
            }
        case "set_listening":
            listening = body["enabled"] as? Bool ?? true
            setVolumes(room); snapshot("listening")
        case "set_speaker":
            #if os(iOS)
            do { try AVAudioSession.sharedInstance().overrideOutputAudioPort((body["enabled"] as? Bool ?? false) ? .speaker : .none) }
            catch { emit("error", values: ["code": "AUDIO_ROUTE_FAILED"]) }
            #endif
        default: break
        }
    }
    private func setVolumes(_ room: Room) {
        for participant in room.remoteParticipants.values {
            for publication in participant.trackPublications.values {
                (publication.track as? RemoteAudioTrack)?.volume = listening ? 1 : 0
            }
        }
    }
    private func snapshot(_ kind: String) {
        guard let room = current else { return }
        let all: [Participant] = [room.localParticipant] + Array(room.remoteParticipants.values)
        let rows: [[String: Any]] = all.compactMap { participant in
            guard let identity = participant.identity?.stringValue else { return nil }
            return ["id": identity, "name": participant.name ?? String(identity.prefix(8)), "speaking": participant.isSpeaking,
                    "microphone": participant.isMicrophoneEnabled(), "local": participant === room.localParticipant]
        }
        emit(kind, values: ["participants": rows, "microphone": room.localParticipant.isMicrophoneEnabled(), "listening": listening])
    }
    private func finish(_ reason: String, send: Bool = true, cancelIntent: Bool = true) async {
        if cancelIntent { generation += 1; intent = "" }
        desiredMic = false
        microphoneTask?.cancel(); microphoneTask = nil
        let room = current, id = session
        current = nil; session = ""
        watchdog?.invalidate(); watchdog = nil
        if let room { try? await room.localParticipant.setMicrophone(enabled: false); await room.disconnect() }
        if send && !id.isEmpty { emit("disconnected", id: id, values: ["reason": reason]) }
    }
    nonisolated func roomDidConnect(_ room: Room) { update(room, "connected") }
    nonisolated func roomDidReconnect(_ room: Room) { update(room, "connected") }
    nonisolated func roomIsReconnecting(_ room: Room) { update(room, "reconnecting") }
    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) { update(room, "participants") }
    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) { update(room, "participants") }
    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) { update(room, "participants") }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) { update(room, "participants") }
    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor in if current === room { await finish("DISCONNECTED") } }
    }
    nonisolated private func update(_ room: Room, _ kind: String) {
        Task { @MainActor in
            guard current === room else { return }
            setVolumes(room)
            if kind == "reconnecting" { emit(kind) } else { snapshot(kind) }
        }
    }
}
