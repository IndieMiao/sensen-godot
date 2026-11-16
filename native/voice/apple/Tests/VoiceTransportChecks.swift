import Foundation

/// Standalone checks: compile only the transport sources, with no LiveKit fetch, microphone or network listener.
@main
struct VoiceTransportChecks {
    static var checks = 0
    static func check(_ passed: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !passed() { fatalError("FAIL: \(name)") }
    }
    static func rejects(_ body: () throws -> Void, _ name: String) {
        checks += 1
        do { try body(); fatalError("FAIL: \(name)") } catch { }
    }
    static func number(_ packet: Data) -> Int64 {
        Int64(String(decoding: packet, as: UTF8.self).components(separatedBy: "|")[1])!
    }
    static func main() throws {
        let key = String(repeating: "a", count: 64)
        func packet(_ line: String) -> Data { Data((line + "|key=" + key).utf8) }
        func decode(_ line: String) -> VoiceWireCommand? { VoiceWire.decode(packet(line), key: key) }
        check(decode("VOICE_CAPS") == .capabilities, "caps authenticated")
        check(decode("VOICE_SETTINGS") == .settings, "settings authenticated")
        check(decode("VOICE_PERMISSION|s1") == .permission("s1"), "permission session")
        check(decode("VOICE_CONNECT|s1|wss://voice.example.test|grant") ==
              .connect(session: "s1", url: "wss://voice.example.test", token: "grant"), "connect fields")
        check(decode("VOICE_CONNECT|s1|ws://127.0.0.1:7880|grant") != nil, "isolated ws grant accepted")
        check(decode("VOICE_LEASE|s1|25000") == .lease(session: "s1", milliseconds: 20000), "lease upper bound")
        check(decode("VOICE_LEASE|s1|-1") == .lease(session: "s1", milliseconds: 0), "lease lower bound")
        check(decode("VOICE_MIC|s1|1") == .microphone(session: "s1", enabled: true), "microphone on")
        check(decode("VOICE_LISTEN|s1|0") == .listening(session: "s1", enabled: false), "listening off")
        check(decode("VOICE_VOLUME|s1|peer1|0.25") == .volume(session: "s1", identity: "peer1", value: 0.25), "fractional volume preserved")
        check(decode("VOICE_VOLUME|s1|peer1|5.0") == .volume(session: "s1", identity: "peer1", value: 1), "volume upper bound")
        check(decode("VOICE_VOLUME|s1|peer1|-0.5") == .volume(session: "s1", identity: "peer1", value: 0), "volume lower bound")
        check(decode("VOICE_SUBSCRIBE|s1|peer1|0") == .subscribed(session: "s1", identity: "peer1", enabled: false), "receive block")
        check(decode("VOICE_PUBLISH|s1|peer1|0") == .publishAllowed(session: "s1", identity: "peer1", enabled: false), "publish block")
        check(decode("VOICE_DISCONNECT|s1") == .disconnect("s1"), "disconnect session")
        check(decode("VOICE_ACK|123") == .acknowledge(123), "ack number")

        for line in ["VOICE_CAPS", "VOICE_CAPS|key=", "VOICE_CAPS|key=wrong",
                     "VOICE_CAPS|key=\(key)|tail", "VOICE_CAPS|key=\(key)\n"] {
            check(VoiceWire.decode(Data(line.utf8), key: key) == nil, "unauthenticated or trailing bytes rejected")
        }
        check(VoiceWire.decode(packet("VOICE_CAPS"), key: "") == nil, "empty native key never authenticates")
        check(VoiceWire.decode(Data([0xff, 0xfe]), key: key) == nil, "invalid UTF8 rejected")
        check(VoiceWire.decode(Data(repeating: 65, count: VoiceWire.maximumDatagramBytes + 1), key: key) == nil, "oversized datagram rejected")
        for line in ["VOICE_CAPS|extra", "VOICE_UNKNOWN", "VOICE_PERMISSION|", "VOICE_PERMISSION|s|extra",
                     "VOICE_CONNECT|s|https://example.test|grant", "VOICE_CONNECT|s|wss://u:p@example.test|grant",
                     "VOICE_CONNECT|s|wss://example.test|", "VOICE_LEASE|s|1.5", "VOICE_LEASE|s|999999999999999999999999",
                     "VOICE_MIC|s|true", "VOICE_LISTEN|s|2", "VOICE_VOLUME|s|p|nan", "VOICE_VOLUME|s|p|inf",
                     "VOICE_VOLUME|s||0.5", "VOICE_SUBSCRIBE|s|p|yes", "VOICE_PUBLISH|s|p|", "VOICE_ACK|0",
                     "VOICE_ACK|-1", "VOICE_ACK|9223372036854775808", "VOICE_DISCONNECT|s\0"] {
            check(decode(line) == nil, "malformed command rejected: " + line.components(separatedBy: "|")[0])
        }
        let caps = String(decoding: VoiceWire.unavailable, as: UTF8.self)
        check(caps.contains(#""supported":false"#) && caps.contains(#""publish_permissions":false"#), "incomplete backend stays closed")

        var queue = VoiceEventDelivery()
        let one: [String: Any] = ["event": "connected", "session": "s1", "participants": []]
        let first = try queue.enqueue(one, now: 10)
        let id = number(first)
        check(id > 0 && queue.count == 1, "one-shot event retained")
        check(queue.poll(now: 10.249).packets.isEmpty, "no early retry")
        check(queue.poll(now: 10.25).packets == [first], "retry exact same bytes and ID")
        queue.acknowledge(id + 999)
        check(queue.count == 1, "unknown ack cannot clear others")
        queue.acknowledge(id)
        queue.acknowledge(id)
        check(queue.count == 0 && queue.poll(now: 100).packets.isEmpty, "ack stops retry, duplicate ack harmless")

        for kind in ["participants", "microphone", "listening"] {
            let snapshot = try queue.enqueue(["event": kind, "session": "s1", "participants": [["name": "Pip | friend"]]], now: 20)
            check(number(snapshot) == 0 && queue.count == 0, "snapshot never queued")
            let line = String(decoding: snapshot, as: UTF8.self)
            let json = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)[2]
            let body = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            check((body["participants"] as! [[String: String]])[0]["name"] == "Pip | friend", "pipe inside event JSON preserved")
        }
        for kind in ["permission", "reconnecting", "disconnected", "error"] {
            let event = try queue.enqueue(["event": kind, "session": "s1"], now: 30)
            check(number(event) > id && queue.count == 1, "reliable event gets new ID")
            queue.clear()
        }
        var replacement = VoiceEventDelivery()
        let next = try replacement.enqueue(one, now: 40)
        check(number(next) > id, "new bridge/outbox does not restart process numbering")
        for retry in 1...VoiceEventDelivery.maximumRetries {
            let result = replacement.poll(now: 40 + Double(retry) * 0.25)
            check(result.packets == [next] && !result.expired, "bounded reliable retry")
        }
        let exhausted = replacement.poll(now: 45.25)
        check(exhausted.expired && exhausted.packets.isEmpty && replacement.count == 0, "20 retries then fault, no unbounded queue")
        _ = try replacement.enqueue(one, now: 100)
        check(replacement.poll(now: 1000).packets.count == 1, "no catch-up burst after suspension")
        check(replacement.poll(now: 1000).packets.isEmpty, "next retry scheduled from actual time")

        var full = VoiceEventDelivery()
        for _ in 0..<VoiceEventDelivery.maximumPending { _ = try full.enqueue(one, now: 0) }
        rejects({ _ = try full.enqueue(one, now: 0) }, "bounded queue refuses overflow")
        check(full.count == VoiceEventDelivery.maximumPending, "overflow preserves existing terminal events")
        rejects({ _ = try queue.enqueue(["event": "connected", "session": "s", "token": "not-allowed"], now: 0) }, "event cannot contain token")
        rejects({ _ = try queue.enqueue(["event": "unknown", "session": "s"], now: 0) }, "unknown event rejected")
        rejects({ _ = try queue.enqueue(["event": "error", "session": "s", "reason": String(repeating: "x", count: 32768)], now: 0) }, "oversized event rejected")
        check(queue.count == 0, "bad event never enters retransmission queue")
        print("VOICE_TRANSPORT_CHECKS \(checks) passed=\(checks) failed=0; no sockets or audio opened")
    }
}
