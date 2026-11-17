import Foundation
import CryptoKit

/// GENSEN_VOICE_MEDIA_QA_V1: copied into an isolated QA package only. Never ship this source.
public struct VoiceQAScope: Decodable {
    public static let marker = "GENSEN_VOICE_MEDIA_QA_V1"
    public static let bundleID = "app.gensen.voiceqa"
    public static let environmentID = "devserver-isolated-387"
    public static let roomNamespace = "p0-ios-voice-qa-1118"
    let schema: Int
    let environment: String
    let namespace: String
    let mediaOrigin: String
    let issuerDigest: String
    let notBefore: Double
    let expiresAt: Double
    enum CodingKeys: String, CodingKey {
        case schema, environment, namespace
        case mediaOrigin = "media_origin", issuerDigest = "issuer_digest"
        case notBefore = "not_before", expiresAt = "expires_at"
    }

    public static func decode(_ data: Data, bundleID: String?, now: TimeInterval) -> VoiceQAScope? {
        guard data.count <= 8192, bundleID == Self.bundleID,
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(dictionary.keys) == Set(["schema", "environment", "namespace", "media_origin", "issuer_digest", "not_before", "expires_at"]),
              let scope = try? JSONDecoder().decode(Self.self, from: data), scope.valid(at: now) else { return nil }
        return scope
    }
    func valid(at now: TimeInterval) -> Bool {
        schema == 1 && environment == Self.environmentID && namespace == Self.roomNamespace &&
        now.isFinite && notBefore.isFinite && expiresAt.isFinite &&
        notBefore <= now && now < expiresAt && expiresAt - notBefore <= 86400 &&
        issuerDigest.count == 64 && issuerDigest != String(repeating: "0", count: 64) &&
        issuerDigest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } &&
        Self.origin(mediaOrigin) != nil
    }
    static func origin(_ text: String) -> String? {
        guard let url = URLComponents(string: text), url.scheme == "wss", let host = url.host?.lowercased(),
              !host.isEmpty, !host.hasSuffix(".livekit.cloud"), host != "livekit.cloud",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", (1...65535).contains(url.port ?? 443) else { return nil }
        return "wss://\(host):\(url.port ?? 443)"
    }
    /// These are restriction checks, not JWT signature verification. The test SFU still verifies the signature.
    func permits(url: String, token: String, now: TimeInterval) -> Bool {
        guard valid(at: now), Self.origin(url) == Self.origin(mediaOrigin), token.utf8.count <= 16384 else { return false }
        let fields = token.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3, !fields[2].isEmpty,
              let header = Self.json(fields[0]), header["alg"] as? String == "HS256",
              let claims = Self.json(fields[1]), let issuer = claims["iss"] as? String,
              SHA256.hash(data: Data(issuer.utf8)).map({ String(format: "%02x", $0) }).joined() == issuerDigest,
              let identity = claims["sub"] as? String, !identity.isEmpty, identity.utf8.count <= 512,
              let issued = claims["iat"] as? Double, let expiry = claims["exp"] as? Double,
              issued.isFinite, expiry.isFinite, issued <= now + 5, now - issued <= 120,
              expiry > now, expiry > issued, expiry - issued <= 90,
              let video = claims["video"] as? [String: Any], video["roomJoin"] as? Bool == true,
              let room = video["room"] as? String,
              room.range(of: "^" + Self.roomNamespace + "-[0-9a-f]{12}-[0-9]+$", options: .regularExpression) != nil else { return false }
        if let notBefore = claims["nbf"] as? Double, !notBefore.isFinite || notBefore > now + 5 { return false }
        return true
    }
    private static func json(_ field: Substring) -> [String: Any]? {
        var text = String(field).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        guard let bytes = Data(base64Encoded: text) else { return nil }
        return (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
    }
}

final class VoiceQAPermit {
    let scope: VoiceQAScope
    private let clock: () -> TimeInterval
    private let wall: () -> TimeInterval
    private let deadline: TimeInterval
    private var armed = true
    init(scope: VoiceQAScope, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wall: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.scope = scope; self.clock = clock; self.wall = wall
        deadline = clock() + min(600, max(0, scope.expiresAt - wall()))
    }
    var active: Bool { armed && clock() < deadline && scope.valid(at: wall()) }
    func disarm() { armed = false }
    func permits(url: String, token: String) -> Bool { active && scope.permits(url: url, token: token, now: wall()) }
}
