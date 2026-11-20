import Foundation

/// Process lifetime, not room/bridge lifetime. Godot remembers the last 64 IDs across room changes.
private final class VoiceEventSequence: @unchecked Sendable {
    static let shared = VoiceEventSequence()
    private let lock = NSLock()
    private var value: Int64 = 0
    func next() -> Int64? {
        lock.lock(); defer { lock.unlock() }
        guard value < Int64.max else { return nil } // Never wrap into a previously acknowledged ID.
        value += 1
        return value
    }
}

enum VoiceDeliveryError: Error { case invalidEvent, tooLarge, queueFull, sequenceExhausted }

/// Main-queue owner in production; explicit monotonic time makes ACK loss/retry tests deterministic.
struct VoiceEventDelivery {
    static let retryInterval: TimeInterval = 0.25
    static let maximumRetries = 20 // Initial send, then at most 20 resends (protocol v1.2).
    static let maximumPending = 64
    private static let snapshots: Set<String> = ["participants", "microphone", "listening"]
    private static let reliable: Set<String> = ["permission", "connected", "reconnecting", "disconnected", "error"]
    private struct Pending {
        let packet: Data
        var next: TimeInterval
        var retries = 0
    }
    private var pending: [Int64: Pending] = [:]
    var count: Int { pending.count }

    /// JSON uses the existing Android event shape; names may contain `|` and remain inside JSON.
    /// Credentials are never accepted as top-level event fields, and no payload is logged here.
    mutating func enqueue(_ event: [String: Any], now: TimeInterval) throws -> Data {
        guard let kind = event["event"] as? String,
              Self.snapshots.contains(kind) || Self.reliable.contains(kind),
              let session = event["session"] as? String, !session.isEmpty,
              Set(event.keys).isSubset(of: ["event", "session", "participants", "microphone", "listening", "granted", "code", "reason"]),
              JSONSerialization.isValidJSONObject(event),
              let json = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else {
            throw VoiceDeliveryError.invalidEvent
        }
        // Reserve room for the longest Int64 prefix, before consuming a sequence or queue slot.
        guard json.count + 32 <= VoiceWire.maximumDatagramBytes else { throw VoiceDeliveryError.tooLarge }
        let number: Int64
        if Self.snapshots.contains(kind) { number = 0 }
        else {
            guard pending.count < Self.maximumPending else { throw VoiceDeliveryError.queueFull }
            guard let next = VoiceEventSequence.shared.next() else { throw VoiceDeliveryError.sequenceExhausted }
            number = next
        }
        var packet = Data("VOICE_EVENT|\(number)|".utf8)
        packet.append(json)
        if number > 0 { pending[number] = Pending(packet: packet, next: now + Self.retryInterval) }
        return packet
    }

    mutating func acknowledge(_ number: Int64) { pending.removeValue(forKey: number) }
    mutating func clear() { pending.removeAll() } // Deliberately does not reset the process sequence.

    mutating func poll(now: TimeInterval) -> (packets: [Data], expired: Bool) {
        var packets: [Data] = []
        var expired = false
        for number in pending.keys.sorted() {
            guard var event = pending[number], now >= event.next else { continue }
            if event.retries >= Self.maximumRetries {
                pending.removeValue(forKey: number)
                expired = true
                continue
            }
            event.retries += 1
            event.next = now + Self.retryInterval // A suspended process never bursts all missed retries at once.
            pending[number] = event
            packets.append(event.packet)
        }
        return (packets, expired)
    }
}
