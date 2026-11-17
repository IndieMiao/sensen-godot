import Foundation
import CryptoKit

@main
struct PolicyChecks {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            if !condition { fatalError("FAILED: \(name)") }
            print("PASS: \(name)")
        }
        let now = 100000.0
        let issuer = "isolated-fixture-issuer"
        let digest = SHA256.hash(data: Data(issuer.utf8)).map { String(format: "%02x", $0) }.joined()
        let origin = "wss://qa387.devserver.test:17887"
        let room = VoiceQAScope.roomNamespace + "-0123456789ab-1"
        func config(_ extra: [String: Any] = [:]) throws -> Data {
            var object: [String: Any] = ["schema": 1, "environment": VoiceQAScope.environmentID,
                "namespace": VoiceQAScope.roomNamespace, "media_origin": origin, "issuer_digest": digest,
                "not_before": now - 1, "expires_at": now + 3600]
            object.merge(extra) { _, new in new }
            return try JSONSerialization.data(withJSONObject: object)
        }
        func load(_ extra: [String: Any] = [:], bundle: String = VoiceQAScope.bundleID) throws -> VoiceQAScope? {
            VoiceQAScope.decode(try config(extra), bundleID: bundle, now: now)
        }
        func encoded(_ object: [String: Any]) throws -> String {
            try JSONSerialization.data(withJSONObject: object).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        func token(_ extra: [String: Any] = [:], algorithm: String = "HS256") throws -> String {
            var body: [String: Any] = ["iss": issuer, "sub": "1", "iat": now, "exp": now + 60,
                                      "video": ["roomJoin": true, "room": room]]
            body.merge(extra) { _, new in new }
            // Deliberately not a real signature. Only the live SFU can establish signature validity.
            return try encoded(["alg": algorithm]) + "." + encoded(body) + ".fixture-not-a-real-signature"
        }
        let goodToken = try token()
        let scope = try load()!
        check(try load() != nil, "valid named isolated scope")
        check(try load(bundle: "app.gensen.maps") == nil, "production bundle rejected")
        check(try load(["expires_at": now]) == nil, "expired scope rejected")
        check(try load(["not_before": now + 1]) == nil, "future scope rejected")
        check(try load(["expires_at": now + 90000]) == nil, "scope over 24 hours rejected")
        check(try load(["namespace": "p0-prod"]) == nil, "production namespace rejected")
        check(try load(["environment": "production"]) == nil, "production environment rejected")
        for bad in ["wss://livekit.cloud", "wss://livekit.cloud.", "wss://Tenant.LIVEKIT.CLOUD", "wss://Tenant.LIVEKIT.CLOUD.", "wss://prod.livekit.cloud", "wss://prod.livekit.cloud.", "wss://prod.livekit。cloud", "ws://devserver:17887", "wss://user:pass@devserver", "wss://devserver/path", "wss://devserver?next=prod", "wss://devserver#fragment", "wss://devserver:0", "wss://qa-\nallowed.test"] {
            check(try load(["media_origin": bad]) == nil, "invalid or non-isolated origin rejected")
        }
        check(try load(["issuer_digest": String(repeating: "0", count: 64)]) == nil, "placeholder issuer rejected")
        check(try load(["override": true]) == nil, "unknown scope override rejected")
        check(scope.permits(url: origin, token: goodToken, now: now), "scoped short grant passes restrictions only")
        check(scope.permits(url: "wss://QA387.DEVSERVER.TEST:17887", token: goodToken, now: now), "approved host case is equivalent")
        check(scope.permits(url: origin + "/", token: goodToken, now: now), "equivalent origin slash accepted")
        check(!scope.permits(url: "wss://other.devserver.test:17887", token: goodToken, now: now), "other origin rejected")
        check(!scope.permits(url: origin, token: try token(["iss": "production-issuer"]), now: now), "other issuer rejected")
        check(!scope.permits(url: origin, token: try token(["video": ["roomJoin": true, "room": "p0-prod-0123456789ab-1"]]), now: now), "other room namespace rejected")
        check(!scope.permits(url: origin, token: try token(["video": ["roomJoin": true, "room": VoiceQAScope.roomNamespace + "evil-0123456789ab-1"]]), now: now), "namespace-prefix spoof rejected")
        check(!scope.permits(url: origin, token: try token(["video": ["roomJoin": true, "room": room + "\n"]]), now: now), "room trailing newline rejected")
        check(!scope.permits(url: origin, token: try token(["exp": now - 1]), now: now), "expired grant rejected")
        check(!scope.permits(url: origin, token: try token(["exp": now + 600]), now: now), "long-lived grant rejected")
        check(!scope.permits(url: origin, token: try token(["iat": now + 60]), now: now), "future issued grant rejected")
        check(!scope.permits(url: origin, token: try token(["nbf": now + 60]), now: now), "not-yet-valid grant rejected")
        check(!scope.permits(url: origin, token: try token(algorithm: "none"), now: now), "unsigned-algorithm grant rejected")
        check(!scope.permits(url: origin, token: try token(["video": ["roomJoin": false, "room": room]]), now: now), "non-join grant rejected")
        check(!scope.permits(url: origin, token: "bad.json", now: now), "malformed token rejected")
        var monotonic = 100.0
        let permit = VoiceQAPermit(scope: scope, clock: { monotonic }, wall: { now })
        check(permit.active, "explicitly created permit active")
        monotonic += 601
        check(!permit.active, "monotonic ten-minute limit closes permit")
        monotonic = 100
        let second = VoiceQAPermit(scope: scope, clock: { monotonic }, wall: { now })
        second.disarm()
        check(!second.active && !second.permits(url: origin, token: goodToken), "disarm permanently closes this permit")
        print("\(checks) QA scope checks passed; no socket, SDK, permission or audio used")
    }
}
