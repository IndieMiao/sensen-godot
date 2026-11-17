import Foundation

@MainActor
private final class FakeAudio: VoicePlatformAudio {
    var permissionGranted = true
    var permissionReplies: [(@MainActor (Bool) -> Void)] = []
    var activations = 0
    var deactivations = 0
    var settings = 0
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) { permissionReplies.append(completion) }
    func activate() throws { activations += 1 }
    func deactivate() throws { deactivations += 1 }
    func openSettings() { settings += 1 }
}

@MainActor
private final class FakeRoom: VoiceMediaRoom {
    enum Failure: Error { case refused }
    var event: ((VoiceRoomEvent) -> Void)?
    var participants: [VoiceParticipantState] = [
        VoiceParticipantState(identity: "self", name: "Me", local: true, speaking: false, microphone: false, subscribedAudio: false),
        VoiceParticipantState(identity: "blocked", name: String(repeating: "x", count: 40), local: false, speaking: true, microphone: true, subscribedAudio: true)]
    var operations: [String] = []
    var connectGate: CheckedContinuation<Void, Never>?
    var microphoneGate: CheckedContinuation<Void, Never>?
    var subscriptionGate: CheckedContinuation<Void, Never>?
    var holdConnect = false
    var holdMicrophone = false
    var failPermissions = false
    var permissionGate: CheckedContinuation<Void, Never>?
    var holdPermissions = false
    var holdSubscriptions = false
    var captureAvailable = false
    var outputAvailable = false
    var micRequested = false
    var stopFailures = false
    var retirements = 0
    var lateTransmitAttempts = 0
    let captureGate = VoiceCaptureGate()
    var sending: Bool {
        var syntheticFrame: Float = 1
        captureGate.filter { syntheticFrame = 0 }
        return micRequested && syntheticFrame != 0
    }
    lazy var transmit = VoiceTransmitFence { [unowned self] input, output in
        if !input && !output && self.stopFailures { throw Failure.refused }
        if output { try self.captureGate.setEnabled(input) } else { self.captureGate.retire() }
        self.captureAvailable = input; self.outputAvailable = output
    }
    var disconnects = 0
    var microphoneValues: [Bool] = []
    var permissionsDenied: [Set<String>] = []
    var subscriptionsBlocked: [Set<String>] = []
    var lastVolumes: [String: Double] = [:]
    var lastBlocked: Set<String> = []
    var lastListening = true
    func connect(url: String, token: String) async throws {
        try transmit.prepare()
        operations.append("connect")
        if holdConnect { await withCheckedContinuation { connectGate = $0 } }
        if transmit.retired { await disconnect() }
        try transmit.checkActive()
    }
    @discardableResult
    func retire() -> Bool { retirements += 1; event = nil; return transmit.retire() }
    func disconnect() async { disconnects += 1; micRequested = false; operations.append("disconnect") }
    func microphone(_ enabled: Bool) async throws {
        try transmit.microphone(enabled)
        operations.append("microphone:\(enabled)")
        if holdMicrophone { holdMicrophone = false; await withCheckedContinuation { microphoneGate = $0 } }
        // A badly-timed SDK completion still tries to publish; capture fence, not Task cancellation, prevents it.
        micRequested = enabled
        if transmit.retired && sending { lateTransmitAttempts += 1 }
        microphoneValues.append(enabled)
        participants[0] = VoiceParticipantState(identity: "self", name: "Me", local: true, speaking: false,
                                                microphone: enabled, subscribedAudio: false)
        if transmit.retired { await disconnect() }
        try transmit.checkActive()
    }
    func permissions(denied: Set<String>) async throws {
        try transmit.checkActive()
        operations.append("permissions"); permissionsDenied.append(denied)
        if holdPermissions { holdPermissions = false; await withCheckedContinuation { permissionGate = $0 } }
        try transmit.checkActive()
        if failPermissions { throw Failure.refused }
    }
    func subscriptions(blocked: Set<String>) async throws {
        try transmit.checkActive()
        operations.append("subscriptions"); subscriptionsBlocked.append(blocked)
        if holdSubscriptions { holdSubscriptions = false; await withCheckedContinuation { subscriptionGate = $0 } }
        try transmit.checkActive()
    }
    func volumes(listening: Bool, values: [String: Double], blocked: Set<String>) {
        lastListening = listening; lastVolumes = values; lastBlocked = blocked
    }
}

@main
struct VoiceMediaControllerChecks {
    @MainActor static var count = 0
    @MainActor static var failures = 0
    @MainActor static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        count += 1
        if !value() { failures += 1; print("FAIL: \(label)") }
    }
    @MainActor static func settle(_ condition: @escaping () -> Bool) async {
        for _ in 0..<2000 {
            if condition() { return }
            await Task.yield()
        }
        check(false, "asynchronous state did not settle")
    }
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--retirement-only") {
            await retirementOnly()
            return
        }
        if CommandLine.arguments.contains("--interruption-only") {
            await interruptionOnly()
            return
        }
        let audio = FakeAudio()
        var events: [[String: Any]] = []
        var rooms: [FakeRoom] = []
        var now: TimeInterval = 0
        var resets = 0
        let controller = VoiceMediaController(audio: audio, makeRoom: {
            let room = FakeRoom(); room.holdConnect = true; rooms.append(room); return room
        }, emit: { events.append($0) }, resetEvents: { resets += 1 }, clock: { now })

        controller.command(.permission("p1"))
        controller.command(.permission("p2"))
        audio.permissionReplies[0](true)
        check(events.isEmpty, "stale permission callback ignored")
        controller.background()
        audio.permissionReplies[1](false)
        check(events.isEmpty, "permission result waits for foreground")
        controller.foregrounded()
        check(events.count == 1 && events[0]["session"] as? String == "p2" && events[0]["granted"] as? Bool == false, "permission flushed once for current request")
        controller.foregrounded(); check(events.count == 1, "permission not duplicated on resume")
        controller.command(.permission("cancelled")); controller.command(.disconnect("cancelled"))
        audio.permissionReplies[2](true); check(events.count == 1, "disconnect cancels pending permission")
        controller.command(.settings); check(audio.settings == 1, "settings delegated without room")

        controller.command(.connect(session: "s1", url: "wss://example.test", token: "test-grant"))
        let first = rooms[0]
        controller.command(.subscribed(session: "s1", identity: "blocked", enabled: false))
        controller.command(.publishAllowed(session: "s1", identity: "blocked", enabled: false))
        controller.command(.volume(session: "s1", identity: "quiet", value: 0.25))
        controller.command(.microphone(session: "s1", enabled: true))
        check(first.lastBlocked.contains("blocked") && !first.lastListening, "pre-connect block recorded, playback stays silent")
        await settle { first.connectGate != nil }
        first.connectGate?.resume(); first.connectGate = nil
        await settle { events.contains(where: { $0["event"] as? String == "connected" && $0["session"] as? String == "s1" }) }
        check(first.permissionsDenied.last == ["blocked"] && first.subscriptionsBlocked.last == ["blocked"], "both block directions applied at first connect")
        check(first.operations.prefix(4) == ["connect", "permissions", "subscriptions", "microphone:true"], "permissions and subscribe decisions precede publishing microphone")
        check(first.lastVolumes["quiet"] == 0.25 && first.microphoneValues.last == true, "volume and pre-connect microphone intent preserved")
        let snap = events.last(where: { $0["session"] as? String == "s1" })!
        let people = snap["participants"] as! [[String: Any]]
        check(snap["microphone"] as? Bool == true, "microphone reports publication result")
        check((people[1]["name"] as! String).count == 32, "participant name bounded")
        check(people[1]["audible"] as? Bool == false && people[1]["speaking"] as? Bool == false && people[1]["microphone"] as? Bool == false, "blocked person's speaking/mic not exposed as audible")
        let micCount = first.microphoneValues.count
        controller.command(.microphone(session: "wrong", enabled: false))
        check(first.microphoneValues.count == micCount, "wrong session cannot change mic")
        controller.command(.listening(session: "s1", enabled: false))
        check(!first.lastListening, "listen-off silences locally before awaits")
        await settle { first.operations.count >= 7 }

        first.event?(.reconnecting)
        check(!first.lastListening, "reconnect silences playback")
        first.event?(.reconnected)
        await settle { events.filter { $0["event"] as? String == "connected" && $0["session"] as? String == "s1" }.count == 2 }
        check(first.permissionsDenied.last == ["blocked"] && first.subscriptionsBlocked.last == ["blocked"], "reconnect reapplies both block policies")

        now = 19; controller.command(.lease(session: "s1", milliseconds: 20_000))
        now = 21; controller.tick(); check(first.disconnects == 0, "renewed lease stays connected")
        now = 40; controller.tick()
        await settle { first.disconnects == 1 && audio.deactivations == 1 }
        check(events.last(where: { $0["event"] as? String == "disconnected" })?["reason"] as? String == "VOICE_EXPIRED", "lease expires with explicit reason")
        check(audio.deactivations == 1, "expired room restores audio")

        controller.command(.connect(session: "old", url: "wss://example.test", token: "old-grant"))
        let old = rooms[1]
        await settle { old.connectGate != nil }
        let lateEvent = old.event
        controller.command(.connect(session: "new", url: "wss://example.test", token: "new-grant"))
        let new = rooms[2]
        for _ in 0..<5 { await Task.yield() }
        check(new.connectGate == nil, "replacement waits for old media teardown")
        old.connectGate?.resume(); old.connectGate = nil
        await settle { new.connectGate != nil }
        check(old.disconnects >= 1 && !old.sending, "cancelled late connect stays retired and disconnected")
        lateEvent?(.disconnected)
        check(new.disconnects == 0, "retired room callback cannot disconnect replacement")
        controller.background()
        new.connectGate?.resume(); new.connectGate = nil
        await settle { new.disconnects >= 1 }
        check(!events.contains { $0["event"] as? String == "connected" && $0["session"] as? String == "new" }, "background ignores late connected event")
        check(events.last(where: { $0["event"] as? String == "disconnected" })?["reason"] as? String == "BACKGROUND", "background disconnect reason")
        controller.command(.connect(session: "away", url: "wss://example.test", token: "grant"))
        check(rooms.count == 3, "no SDK room created while backgrounded")
        controller.foregrounded(); check(rooms.count == 3, "foreground does not reuse old grant")

        var roomForRace: FakeRoom!
        var raceEvents: [[String: Any]] = []
        let race = VoiceMediaController(audio: audio, makeRoom: {
            let r = FakeRoom(); r.holdMicrophone = true; roomForRace = r; return r
        }, emit: { raceEvents.append($0) })
        race.command(.connect(session: "mic", url: "wss://example.test", token: "grant"))
        race.command(.microphone(session: "mic", enabled: true))
        await settle { roomForRace.microphoneGate != nil }
        race.command(.microphone(session: "mic", enabled: false))
        roomForRace.microphoneGate?.resume(); roomForRace.microphoneGate = nil
        await settle { roomForRace.microphoneValues.last == false }
        check(roomForRace.microphoneValues == [true, false], "serialized late mic-on converges to newest off intent")
        audio.permissionGranted = false
        race.command(.microphone(session: "mic", enabled: true))
        await settle { raceEvents.contains { $0["code"] as? String == "MICROPHONE_DENIED" } }
        check(roomForRace.microphoneValues.last == false, "revoked permission never enables mic")
        roomForRace.failPermissions = true
        race.command(.publishAllowed(session: "mic", identity: "blocked", enabled: false))
        await settle { roomForRace.disconnects == 1 }
        check(raceEvents.contains { $0["reason"] as? String == "VOICE_CONTROL_FAILED" }, "failed permissions fail closed instead of keeping media")

        let policyAudio = FakeAudio()
        var policyRoom: FakeRoom!
        var policyEvents: [[String: Any]] = []
        let policy = VoiceMediaController(audio: policyAudio, makeRoom: {
            let r = FakeRoom(); r.holdPermissions = true; policyRoom = r; return r
        }, emit: { policyEvents.append($0) })
        policy.command(.connect(session: "policy", url: "wss://example.test", token: "grant"))
        policy.command(.microphone(session: "policy", enabled: true))
        await settle { policyRoom.permissionGate != nil }
        policy.command(.publishAllowed(session: "policy", identity: "new-deny", enabled: false))
        policy.command(.subscribed(session: "policy", identity: "new-deny", enabled: false))
        check(policyRoom.lastBlocked == ["new-deny"], "block arriving during SDK await immediately updates local silence")
        policyRoom.permissionGate?.resume(); policyRoom.permissionGate = nil
        await settle { policyEvents.contains { $0["event"] as? String == "connected" } }
        check(policyRoom.permissionsDenied == [[], ["new-deny"]], "stale permissions completed before applying latest deny list")
        check(policyRoom.subscriptionsBlocked == [["new-deny"]], "no stale subscription batch after policy revision")
        check(policyRoom.operations == ["connect", "permissions", "permissions", "subscriptions", "microphone:true"], "latest permissions enforced before first mic")
        let oldPermissionCalls = policyRoom.permissionsDenied.count
        policyRoom.event?(.participantsChanged)
        await settle { policyRoom.permissionsDenied.count > oldPermissionCalls }
        check(policyRoom.permissionsDenied.last == ["new-deny"], "participant change reapplies identity policy for new SID")
        policy.command(.lease(session: "different", milliseconds: 0))
        check(policyRoom.disconnects == 0, "wrong session lease cannot stop active room")
        policy.transportFailed()
        await settle { policyRoom.disconnects == 1 }
        check(policyEvents.last(where: { $0["event"] as? String == "disconnected" })?["reason"] as? String == "TRANSPORT_FAILED", "lost control channel retires media")
        policy.foregrounded()
        check(policyAudio.activations == 1, "transport fault does not auto-reconnect with retained grant")

        var interruptedRoom: FakeRoom!
        let interrupt = VoiceMediaController(audio: policyAudio, makeRoom: {
            let r = FakeRoom(); interruptedRoom = r; return r
        }, emit: { policyEvents.append($0) })
        interrupt.command(.connect(session: "interrupt", url: "wss://example.test", token: "grant"))
        await settle { policyEvents.contains { $0["event"] as? String == "connected" && $0["session"] as? String == "interrupt" } }
        interrupt.setInterrupted(true)
        await settle { interruptedRoom.disconnects == 1 }
        check(policyEvents.last(where: { $0["event"] as? String == "disconnected" })?["reason"] as? String == "AUDIO_INTERRUPTED", "interruption retires room")
        let interruptedDriver = interruptedRoom
        interrupt.command(.connect(session: "still-interrupted", url: "wss://example.test", token: "grant"))
        check(interruptedRoom === interruptedDriver, "no new room during active system interruption")
        interrupt.setInterrupted(false)
        check(interruptedRoom === interruptedDriver, "interruption end does not reopen a room automatically")
        interrupt.setInterrupted(true); interrupt.shutdown()
        interrupt.command(.connect(session: "restart", url: "wss://example.test", token: "fresh-grant"))
        await settle { policyEvents.contains { $0["event"] as? String == "connected" && $0["session"] as? String == "restart" } }
        check(interruptedRoom !== interruptedDriver, "bridge restart cannot retain an interruption whose end observer was removed")
        interrupt.shutdown()

        race.shutdown(); controller.shutdown()
        check(resets >= 4, "session transitions discard obsolete transport events")
        print("VOICE_MEDIA_CHECKS \(count) passed=\(count-failures) failed=\(failures); fake audio/SDK, no sockets")
        if failures > 0 { exit(1) }
    }

    @MainActor static func interruptionOnly() async {
        let audio = FakeAudio()
        var room: FakeRoom!
        var events: [[String: Any]] = []
        let controller = VoiceMediaController(audio: audio, makeRoom: { let r = FakeRoom(); room = r; return r },
                                               emit: { events.append($0) })
        controller.command(.connect(session: "first", url: "wss://example.test", token: "grant"))
        await settle { events.contains { $0["event"] as? String == "connected" } }
        controller.setInterrupted(true)
        await settle { room.disconnects == 1 }
        let retired = room
        controller.command(.connect(session: "during-interruption", url: "wss://example.test", token: "grant"))
        check(room === retired && events.last?["reason"] as? String == "AUDIO_INTERRUPTED", "active interruption refuses a fresh connect")
        controller.setInterrupted(false)
        check(room === retired && audio.activations == 1, "interruption end never reuses previous grant")
        controller.setInterrupted(true); controller.shutdown()
        controller.command(.connect(session: "fresh", url: "wss://example.test", token: "fresh-grant"))
        await settle { events.contains { $0["event"] as? String == "connected" && $0["session"] as? String == "fresh" } }
        check(room !== retired, "new bridge lifetime does not inherit stale interruption")
        controller.shutdown()
        print("VOICE_INTERRUPTION_CHECKS \(count) passed=\(count-failures) failed=\(failures); fake audio/SDK, no sockets")
        if failures > 0 { exit(1) }
    }

    @MainActor static func retirementOnly() async {
        let capture = VoiceCaptureGate()
        var synthetic = [Float](repeating: 0.75, count: 8)
        capture.filter { synthetic = synthetic.map { _ in 0 } }
        check(synthetic.allSatisfy { $0 == 0 }, "capture processor starts closed")
        try! capture.setEnabled(true)
        synthetic = [Float](repeating: 0.75, count: 8)
        capture.filter { synthetic = synthetic.map { _ in 0 } }
        check(synthetic.allSatisfy { $0 == 0.75 }, "live capture processor preserves frame")
        capture.retire()
        capture.filter { synthetic = synthetic.map { _ in 0 } }
        check(synthetic.allSatisfy { $0 == 0 }, "retired capture processor zeros outgoing frame in place")
        var refused = false
        do { try capture.setEnabled(true) } catch { refused = true }
        check(refused && capture.retired, "retired processor cannot be reopened by late SDK completion")
        for trigger in ["lease", "background", "transport"] {
            let audio = FakeAudio()
            var room: FakeRoom!
            var events: [[String: Any]] = []
            var now: TimeInterval = 0
            let controller = VoiceMediaController(audio: audio, makeRoom: { let r = FakeRoom(); room = r; return r },
                                                   emit: { events.append($0) }, clock: { now })
            controller.command(.connect(session: trigger, url: "wss://example.test", token: "grant"))
            controller.command(.microphone(session: trigger, enabled: true))
            await settle { events.contains { $0["event"] as? String == "connected" } }
            check(room.sending, "precondition: microphone already sending before \(trigger)")
            let lateCallback = room.event
            if trigger == "background" {
                room.holdSubscriptions = true
                controller.command(.subscribed(session: trigger, identity: "p", enabled: false))
                await settle { room.subscriptionGate != nil }
            } else {
                room.holdPermissions = true
                controller.command(.publishAllowed(session: trigger, identity: "p", enabled: false))
                await settle { room.permissionGate != nil }
            }
            if trigger == "lease" { now = 21; controller.tick() }
            else if trigger == "background" { controller.background() }
            else { controller.transportFailed() }
            // No await and no gate.resume between termination and this stop assertion.
            check(room.retirements == 1 && room.transmit.retired && !room.captureAvailable && !room.sending,
                  "\(trigger) synchronously stops capture despite held SDK operation")
            check(room.permissionGate != nil || room.subscriptionGate != nil, "old SDK operation is still held at stop proof")
            await settle { room.disconnects >= 1 }
            check(room.permissionGate != nil || room.subscriptionGate != nil, "disconnect starts without waiting for held operation")
            let connectedBefore = events.filter { $0["event"] as? String == "connected" }.count
            lateCallback?(.reconnected)
            controller.command(.lease(session: trigger, milliseconds: 20_000))
            controller.command(.microphone(session: trigger, enabled: true))
            check(!room.sending && events.filter { $0["event"] as? String == "connected" }.count == connectedBefore,
                  "late callback/lease/mic cannot revive retired session")
            room.permissionGate?.resume(); room.permissionGate = nil
            room.subscriptionGate?.resume(); room.subscriptionGate = nil
            await settle { audio.deactivations == 1 }
            check(room.lateTransmitAttempts == 0 && !room.sending, "held SDK completion leaves capture shut")
            controller.shutdown()
        }

        // A mic-on await itself can finish AFTER retirement; the driver's shared fence must still suppress capture.
        let audio = FakeAudio()
        var rooms: [FakeRoom] = []
        var events: [[String: Any]] = []
        let controller = VoiceMediaController(audio: audio, makeRoom: { let r = FakeRoom(); rooms.append(r); return r },
                                               emit: { events.append($0) })
        controller.command(.connect(session: "old", url: "wss://example.test", token: "grant"))
        let old = rooms[0]
        await settle { events.contains { $0["event"] as? String == "connected" } }
        old.holdMicrophone = true
        controller.command(.microphone(session: "old", enabled: true))
        await settle { old.microphoneGate != nil }
        let late = old.event
        controller.command(.connect(session: "replacement", url: "wss://example.test", token: "grant"))
        controller.command(.microphone(session: "replacement", enabled: true))
        let replacement = rooms[1]
        check(old.transmit.retired && !old.sending, "replacement first closes old capture fence")
        for _ in 0..<5 { await Task.yield() }
        check(replacement.operations.isEmpty, "replacement waits for full old task cleanup before audio enable")
        old.microphoneGate?.resume(); old.microphoneGate = nil
        await settle { events.contains { $0["event"] as? String == "connected" && $0["session"] as? String == "replacement" } }
        check(old.lateTransmitAttempts == 0 && !old.sending, "late mic-on never transmitted after retirement")
        check(replacement.sending, "replacement begins normally after old cleanup")
        late?(.reconnected); old.retire()
        check(replacement.sending && replacement.retirements == 0, "old callback/second retirement cannot stop new room")
        controller.command(.disconnect("replacement"))
        check(!replacement.sending, "normal exit also stops synchronously")
        await settle { replacement.disconnects == 1 && audio.deactivations == 1 }
        check(replacement.disconnects == 1 && audio.deactivations == 1, "normal exit cleans room/audio exactly once")

        // Never turn an unconfirmed SDK stop into a successful disconnected claim or enable a replacement.
        controller.command(.connect(session: "stop-error", url: "wss://example.test", token: "grant"))
        let broken = rooms[2]
        await settle { events.contains { $0["event"] as? String == "connected" && $0["session"] as? String == "stop-error" } }
        broken.stopFailures = true
        controller.transportFailed()
        check(events.last?["code"] as? String == "VOICE_STOP_FAILED", "SDK stop failure reported explicitly")
        controller.command(.connect(session: "unsafe-replacement", url: "wss://example.test", token: "grant"))
        check(rooms.count == 3, "unconfirmed stop latches replacement refusal")
        check(!events.contains { $0["event"] as? String == "disconnected" && $0["session"] as? String == "stop-error" },
              "unconfirmed stop is not reported as disconnected success")
        await settle { broken.disconnects >= 1 }
        controller.shutdown()
        print("VOICE_RETIREMENT_CHECKS \(count) passed=\(count-failures) failed=\(failures); held SDK seams, no audio/sockets")
        if failures > 0 { exit(1) }
    }
}
