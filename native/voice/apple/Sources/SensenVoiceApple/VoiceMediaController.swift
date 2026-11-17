import Foundation

struct VoiceParticipantState {
    let identity: String
    let name: String
    let local: Bool
    let speaking: Bool
    let microphone: Bool
    let subscribedAudio: Bool
}

enum VoiceRoomEvent { case reconnected, reconnecting, participantsChanged, snapshot, disconnected }

@MainActor
protocol VoiceMediaRoom: AnyObject {
    var event: ((VoiceRoomEvent) -> Void)? { get set }
    var participants: [VoiceParticipantState] { get }
    func connect(url: String, token: String) async throws
    func disconnect() async
    func microphone(_ enabled: Bool) async throws
    func permissions(denied: Set<String>) async throws
    func subscriptions(blocked: Set<String>) async throws
    /// Synchronous local silence is applied before any asynchronous subscription change.
    func volumes(listening: Bool, values: [String: Double], blocked: Set<String>)
}

@MainActor
protocol VoicePlatformAudio: AnyObject {
    var permissionGranted: Bool { get }
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void)
    func activate() throws
    func deactivate() throws
    func openSettings()
}

/// All state and intent mutation is synchronous on MainActor, before any SDK await.
/// SDK calls are serialized per room; old tasks can finish only their own retired room, never the replacement.
@MainActor
final class VoiceMediaController {
    private final class Session {
        let id: String
        let room: VoiceMediaRoom
        var expires: TimeInterval
        var connected = false
        var desiredMic = false
        var listening = true
        var volumes: [String: Double] = [:]
        var blocked: Set<String> = []
        var denied: Set<String> = []
        var revision: UInt64 = 0
        var announceConnected = false
        var connecting: Task<Void, Never>?
        var controlling: Task<Void, Never>?
        init(id: String, room: VoiceMediaRoom, now: TimeInterval) {
            self.id = id; self.room = room; expires = now + 20
        }
    }
    private let audio: VoicePlatformAudio
    private let makeRoom: () -> VoiceMediaRoom
    private let emit: ([String: Any]) -> Void
    private let resetEvents: () -> Void
    private let clock: () -> TimeInterval
    private var current: Session?
    private var retiring: Task<Void, Never>?
    private var retirementTurn: UInt64 = 0
    private var permissionTurn: UInt64 = 0
    private var permissionSession = ""
    private var permissionResult: Bool?
    private var foreground = true
    private var audioInterrupted = false

    init(audio: VoicePlatformAudio, makeRoom: @escaping () -> VoiceMediaRoom,
         emit: @escaping ([String: Any]) -> Void, resetEvents: @escaping () -> Void = {},
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.audio = audio; self.makeRoom = makeRoom; self.emit = emit
        self.resetEvents = resetEvents; self.clock = clock
    }

    func command(_ command: VoiceWireCommand) {
        switch command {
        case .capabilities, .acknowledge: return // Transport owns these.
        case .settings: audio.openSettings(); return
        case .permission(let id): requestPermission(id); return
        case .connect(let id, let url, let token): connect(id: id, url: url, token: token); return
        case .disconnect(let id):
            if permissionSession == id { cancelPermission() }
            if current?.id == id { finish("LEFT") }
            return
        default: break
        }
        guard let s = current else { return }
        switch command {
        case .lease(let id, let ms) where id == s.id:
            s.expires = clock() + Double(min(20_000, max(0, ms))) / 1000
            tick()
            return
        case .microphone(let id, let on) where id == s.id: s.desiredMic = on
        case .listening(let id, let on) where id == s.id: s.listening = on
        case .volume(let id, let who, let value) where id == s.id:
            guard value.isFinite, !who.isEmpty else { return }
            s.volumes[who] = min(1, max(0, value))
        case .subscribed(let id, let who, let on) where id == s.id:
            if on { s.blocked.remove(who) } else { s.blocked.insert(who) }
        case .publishAllowed(let id, let who, let on) where id == s.id:
            if on { s.denied.remove(who) } else { s.denied.insert(who) }
        default: return
        }
        s.revision &+= 1
        silence(s)
        reconcile(s)
    }

    func tick() {
        guard let s = current, clock() >= s.expires else { return }
        finish("VOICE_EXPIRED")
    }

    func background() {
        foreground = false
        finish("BACKGROUND") // Permission dialog resignActive is intentionally NOT wired to this method.
    }

    func foregrounded() {
        foreground = true
        flushPermission()
        // A retired room is never automatically reopened; Godot needs a fresh backend grant.
    }

    func interrupted() { cancelPermission(); finish("AUDIO_INTERRUPTED") }
    func setInterrupted(_ active: Bool) {
        audioInterrupted = active
        if active { interrupted() }
    }
    func transportFailed() { cancelPermission(); finish("TRANSPORT_FAILED") }
    func shutdown() {
        cancelPermission()
        audioInterrupted = false // Observer removal can otherwise miss the end event before a later bridge start.
        finish("DESTROYED", send: false)
    }

    private func requestPermission(_ id: String) {
        cancelPermission()
        permissionSession = id
        let turn = permissionTurn
        audio.requestPermission { [weak self] granted in
            guard let self, self.permissionTurn == turn, self.permissionSession == id else { return }
            self.permissionResult = granted
            self.flushPermission()
        }
    }

    private func flushPermission() {
        guard foreground, !permissionSession.isEmpty, let granted = permissionResult else { return }
        let id = permissionSession
        cancelPermission()
        send("permission", id: id, values: ["granted": granted])
    }

    private func cancelPermission() {
        permissionTurn &+= 1; permissionSession = ""; permissionResult = nil
    }

    private func connect(id: String, url: String, token: String) {
        cancelPermission()
        finish("REPLACED", send: false)
        resetEvents()
        guard foreground else { send("disconnected", id: id, values: ["reason": "BACKGROUND"]); return }
        guard !audioInterrupted else { send("disconnected", id: id, values: ["reason": "AUDIO_INTERRUPTED"]); return }
        let s = Session(id: id, room: makeRoom(), now: clock())
        current = s // Allow Block/Mute/lease commands immediately, while connect is still waiting.
        s.room.event = { [weak self, weak s] event in
            guard let self, let s, self.current === s else { return }
            self.received(event, session: s)
        }
        let previous = retiring
        s.connecting = Task { @MainActor [weak self, weak s] in
            guard let self, let s else { return }
            defer { s.connecting = nil }
            await previous?.value
            guard self.current === s, self.foreground, !Task.isCancelled else { return }
            do {
                try self.audio.activate()
                try await s.room.connect(url: url, token: token)
                guard self.current === s, self.foreground, !Task.isCancelled else { return }
                s.connected = true; s.announceConnected = true
                self.reconcile(s)
            } catch {
                if self.current === s { self.finish("VOICE_CONNECT_FAILED") }
            }
        }
    }

    private func received(_ event: VoiceRoomEvent, session s: Session) {
        switch event {
        case .disconnected: finish("DISCONNECTED")
        case .reconnecting:
            s.connected = false
            silence(s, all: true)
            send("reconnecting", id: s.id)
        case .reconnected:
            s.connected = true; s.announceConnected = true; s.revision &+= 1
            reconcile(s)
        case .participantsChanged:
            s.revision &+= 1
            silence(s)
            reconcile(s) // New SID/publication: recompute both directions of Block before enabling mic.
        case .snapshot:
            silence(s)
            snapshot("participants", session: s)
        }
    }

    private func silence(_ s: Session, all: Bool = false) {
        s.room.volumes(listening: !all && s.listening && s.connected, values: s.volumes, blocked: s.blocked)
    }

    private func reconcile(_ s: Session) {
        guard current === s, s.connected, s.controlling == nil else { return }
        s.controlling = Task { @MainActor [weak self, weak s] in
            guard let self, let s else { return }
            defer {
                s.controlling = nil
                // A reconnect may have completed while a previous SDK call was suspended/cancelled.
                if self.current === s, s.connected, s.announceConnected { self.reconcile(s) }
            }
            while self.current === s, s.connected, !Task.isCancelled {
                let revision = s.revision
                do {
                    // Permissions before microphone publication, also after full reconnect/member SID changes.
                    try await s.room.permissions(denied: s.denied)
                    guard self.current === s, s.connected, !Task.isCancelled else { return }
                    if revision != s.revision { continue }
                    try await s.room.subscriptions(blocked: s.blocked)
                    guard self.current === s, s.connected, !Task.isCancelled else { return }
                    if revision != s.revision { continue }
                    if s.desiredMic && !self.audio.permissionGranted {
                        s.desiredMic = false
                        self.send("error", id: s.id, values: ["code": "MICROPHONE_DENIED"])
                    }
                    let wanted = s.desiredMic
                    try await s.room.microphone(wanted)
                    guard self.current === s, s.connected, !Task.isCancelled else { return }
                    if revision != s.revision { continue }
                    self.silence(s)
                    if s.announceConnected { s.announceConnected = false; self.snapshot("connected", session: s) }
                    self.snapshot("microphone", session: s)
                    self.snapshot("listening", session: s)
                    return
                } catch {
                    // Never continue a room after a failed Block update or a failed microphone transition.
                    if self.current === s {
                        self.send("error", id: s.id, values: ["code": "VOICE_CONTROL_FAILED"])
                        self.finish("VOICE_CONTROL_FAILED")
                    }
                    return
                }
            }
        }
    }

    private func snapshot(_ kind: String, session s: Session) {
        guard current === s else { return }
        let people = s.room.participants.map { p -> [String: Any] in
            let blocked = s.blocked.contains(p.identity)
            let audible = p.local || (s.connected && !blocked && p.subscribedAudio)
            return ["id": p.identity, "name": String(p.name.prefix(32)), "local": p.local,
                    "speaking": audible && p.speaking, "microphone": audible && p.microphone,
                    "audible": audible, "muted": (s.volumes[p.identity] ?? 1) <= 0, "blocked": blocked]
        }
        send(kind, id: s.id, values: ["participants": people, "microphone": s.room.participants.first(where: { $0.local })?.microphone ?? false,
                                     "listening": s.listening])
    }

    private func finish(_ reason: String, send: Bool = true) {
        guard let old = current else { return }
        current = nil
        old.connected = false; old.desiredMic = false
        old.room.event = nil
        old.connecting?.cancel(); old.controlling?.cancel()
        silence(old, all: true)
        resetEvents()
        let prior = retiring
        retirementTurn &+= 1
        let turn = retirementTurn
        let connecting = old.connecting, controlling = old.controlling
        retiring = Task { @MainActor [weak self] in
            await prior?.value
            await connecting?.value
            await controlling?.value
            // SDK disconnect owns publication/track cleanup, even if a cancelled microphone await completed late.
            await old.room.disconnect()
            if let self, self.current == nil {
                do { try self.audio.deactivate() }
                catch { self.send("error", id: old.id, values: ["code": "AUDIO_SESSION_FAILED"]) }
            }
            if let self, self.retirementTurn == turn { self.retiring = nil }
        }
        if send { self.send("disconnected", id: old.id, values: ["reason": reason]) }
    }

    private func send(_ kind: String, id: String, values: [String: Any] = [:]) {
        var event = values; event["event"] = kind; event["session"] = id
        emit(event)
    }
}
