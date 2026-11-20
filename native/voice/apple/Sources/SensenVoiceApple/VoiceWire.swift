import Foundation

/// SGODOT-387, UDP protocol v1.2. No microphone, room, socket or SDK work happens while parsing.
/// In particular, a rejected packet must never become the destination for private room events.
enum VoiceWireCommand: Equatable {
    case capabilities, settings
    case acknowledge(Int64)
    case permission(String)
    case connect(session: String, url: String, token: String)
    case lease(session: String, milliseconds: Int)
    case microphone(session: String, enabled: Bool)
    case listening(session: String, enabled: Bool)
    case volume(session: String, identity: String, value: Double)
    case subscribed(session: String, identity: String, enabled: Bool)
    case publishAllowed(session: String, identity: String, enabled: Bool)
    case disconnect(String)
}

enum VoiceWire {
    static let port: UInt16 = 46467
    static let maximumDatagramBytes = 32_768
    // Stay closed until the media implementation AND both directions of Block are complete.
    static let unavailable = Data(#"VOICE_CAPS|{"protocol":1,"supported":false,"platform":"ios","per_participant":false,"publish_permissions":false}"#.utf8)
    static let available = Data(#"VOICE_CAPS|{"protocol":1,"supported":true,"platform":"ios","per_participant":true,"publish_permissions":true}"#.utf8)

    static func validKey(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func decode(_ data: Data, key: String) -> VoiceWireCommand? {
        guard validKey(key), data.count <= maximumDatagramBytes,
              let line = String(data: data, encoding: .utf8),
              !line.contains("\n"), !line.contains("\r"), !line.contains("\0") else { return nil }
        var fields = line.components(separatedBy: "|")
        guard let last = fields.popLast(), last.hasPrefix("key="),
              equalKey(String(last.dropFirst(4)), key), let op = fields.first else { return nil }
        func session() -> Bool { fields.count > 1 && field(fields[1], limit: 512) }
        func identity() -> Bool { fields.count > 2 && field(fields[2], limit: 512) }
        func bit(_ index: Int) -> Bool? {
            if fields[index] == "1" { return true }
            if fields[index] == "0" { return false }
            return nil
        }
        switch op {
        case "VOICE_CAPS" where fields.count == 1: return .capabilities
        case "VOICE_SETTINGS" where fields.count == 1: return .settings
        case "VOICE_ACK" where fields.count == 2:
            guard fields[1].utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int64(fields[1]), number > 0 else { return nil }
            return .acknowledge(number)
        case "VOICE_PERMISSION" where fields.count == 2 && session(): return .permission(fields[1])
        case "VOICE_DISCONNECT" where fields.count == 2 && session(): return .disconnect(fields[1])
        case "VOICE_CONNECT" where fields.count == 4 && session():
            guard field(fields[2], limit: 4096), field(fields[3], limit: 16_384),
                  let url = URLComponents(string: fields[2]), ["wss", "ws"].contains(url.scheme ?? ""),
                  let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
                  url.fragment == nil else { return nil }
            return .connect(session: fields[1], url: fields[2], token: fields[3])
        case "VOICE_LEASE" where fields.count == 3 && session():
            guard let ms = Int64(fields[2]) else { return nil }
            return .lease(session: fields[1], milliseconds: Int(min(20_000, max(0, ms))))
        case "VOICE_MIC" where fields.count == 3 && session():
            guard let on = bit(2) else { return nil }
            return .microphone(session: fields[1], enabled: on)
        case "VOICE_LISTEN" where fields.count == 3 && session():
            guard let on = bit(2) else { return nil }
            return .listening(session: fields[1], enabled: on)
        case "VOICE_VOLUME" where fields.count == 4 && session() && identity():
            guard let value = Double(fields[3]), value.isFinite else { return nil }
            return .volume(session: fields[1], identity: fields[2], value: min(1, max(0, value)))
        case "VOICE_SUBSCRIBE" where fields.count == 4 && session() && identity():
            guard let on = bit(3) else { return nil }
            return .subscribed(session: fields[1], identity: fields[2], enabled: on)
        case "VOICE_PUBLISH" where fields.count == 4 && session() && identity():
            guard let on = bit(3) else { return nil }
            return .publishAllowed(session: fields[1], identity: fields[2], enabled: on)
        default: return nil
        }
    }

    private static func field(_ value: String, limit: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= limit && !value.unicodeScalars.contains(where: { $0.value < 32 })
    }

    private static func equalKey(_ incoming: String, _ expected: String) -> Bool {
        let a = Array(incoming.utf8), b = Array(expected.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
