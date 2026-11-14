// Sign in with Google on iOS (SGODOT-487; tech-plan-yase §3.1). No GoogleSignIn SDK: the system's own web sheet
// (ASWebAuthenticationSession) runs Google's OAuth with PKCE, and the code is swapped for an ID token here — the app
// never sees the player's Google password, and asks for `openid` only: the account number, no email, no name (q(312)).
//
// The same in-process loopback UDP as AppleSignIn, on a port of its own (46468). One line per packet, | between fields:
//   Godot → native  GOOGLE|<iOS client id>|<nonce_sha256_hex>|key=<bridge key>
//                   GOOGLE_CANCEL|key=<bridge key>          Godot gave up waiting: the sheet goes
//   native → Godot  GOOGLE_OK|<id_token>
//                   GOOGLE_ERR|<code>     code: canceled | failed | no_token | busy | config | key
// The bridge key (NativeBridgeKey, below): another app on the phone could send to this loopback port and be handed a
// token the player signed in for; only a sender that read the key from this app's own container is served (周瑜 on
// #1014). AppleSignIn checks the same key.
// The nonce goes into the request as its SHA-256, as on Android (GodotGoogleSignInPlugin); Godot keeps the raw one
// and sends it to the server with the token (verifyGoogleIdToken, server/src/accounts/google_token.ts).
// The redirect is the client id reversed (`com.googleusercontent.apps.<…>:/oauthredirect`, Google's iOS client rule);
// ASWebAuthenticationSession catches its scheme itself, so Info.plist needs no URL type. Bootstrapped by G3Spike.mm.
import AuthenticationServices
import CryptoKit
import Foundation
import Network
import UIKit

/// A key made once per launch and written to the app's Documents (Godot's user://, `.native_bridge_key`): only this
/// app can read it there, so a loopback request carrying it comes from this app's Godot.
enum NativeBridgeKey {
    static let value: String = {
        var b = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        let key = b.map { String(format: "%02x", $0) }.joined()
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = dir.appendingPathComponent(".native_bridge_key")
            try? Data(key.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return key
    }()
    /// Whether a request line's last field is this launch's key.
    static func accepts(_ parts: [String]) -> Bool { parts.last == "key=" + value }
}

@objc(GoogleSignInIOS)
final class GoogleSignInIOS: NSObject, ASWebAuthenticationPresentationContextProviding {
    @objc static let shared = GoogleSignInIOS()
    private static let port: NWEndpoint.Port = 46468

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var pending: NWConnection?
    private var session: ASWebAuthenticationSession?
    private var retryScheduled = false

    @objc class func setup() {
        _ = NativeBridgeKey.value   // written before Godot can ask
        shared.startListener()
    }

    private func startListener() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.udp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: Self.port)
            let l = try NWListener(using: parameters)
            listener = l
            l.stateUpdateHandler = { [weak self, weak l] state in
                guard let self, let l, self.listener === l else { return }
                switch state {
                case .ready: NSLog("[GoogleSignInIOS] listener ready on loopback udp/46468")
                case .failed(let error):
                    NSLog("[GoogleSignInIOS] listener failed: \(error); will retry")
                    l.cancel()
                    self.listener = nil
                    self.scheduleRetry()
                default: break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { conn.cancel(); return }
                self.connections[ObjectIdentifier(conn)] = conn
                conn.stateUpdateHandler = { [weak self, weak conn] state in
                    guard let self, let conn else { return }
                    if case .failed = state { self.drop(conn) }
                    if case .cancelled = state { self.drop(conn) }
                }
                conn.start(queue: .main)
                self.receiveLoop(conn)
            }
            l.start(queue: .main)
        } catch {
            NSLog("[GoogleSignInIOS] listener error: \(error); will retry")
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.retryScheduled = false
            self?.startListener()
        }
    }

    private func drop(_ conn: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(conn))
        if pending === conn { pending = nil }
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if error != nil { self.drop(conn); conn.cancel(); return }
            if let d = data, let s = String(data: d, encoding: .utf8) { self.handle(s, from: conn) }
            self.receiveLoop(conn)
        }
    }

    private func send(_ line: String, to conn: NWConnection?) {
        conn?.send(content: line.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    /// The answer, then that sender's connection closed (one per sign-in otherwise stays open; 周瑜 on #1014).
    private func finish(_ line: String) {
        let conn = pending
        pending = nil
        session = nil
        guard let conn else { return }
        conn.send(content: line.data(using: .utf8), completion: .contentProcessed { [weak self] _ in
            conn.cancel()
            self?.drop(conn)
        })
    }

    private func handle(_ msg: String, from conn: NWConnection) {
        let parts = msg.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if parts.first == "GOOGLE_CANCEL" {
            if NativeBridgeKey.accepts(parts) { session?.cancel(); finish("GOOGLE_ERR|canceled") }
            return
        }
        guard parts.first == "GOOGLE" else { return }
        guard parts.count >= 4, !parts[2].isEmpty else { send("GOOGLE_ERR|failed", to: conn); return }   // no 300 s wait on a bad line
        guard NativeBridgeKey.accepts(parts) else { send("GOOGLE_ERR|key", to: conn); return }
        if session != nil { send("GOOGLE_ERR|busy", to: conn); return }
        let clientId = parts[1]
        guard clientId.hasSuffix(".apps.googleusercontent.com") else { send("GOOGLE_ERR|config", to: conn); return }
        let scheme = "com.googleusercontent.apps." + clientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let redirect = scheme + ":/oauthredirect"
        let verifier = Self.randomURLSafe(48)
        let state = Self.randomURLSafe(24)
        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "nonce", value: parts[2]),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        pending = conn
        let s = ASWebAuthenticationSession(url: auth.url!, callbackURLScheme: scheme) { [weak self] url, error in
            DispatchQueue.main.async { self?.completed(url: url, error: error, state: state, clientId: clientId, redirect: redirect, verifier: verifier) }
        }
        s.presentationContextProvider = self
        session = s
        if !s.start() { finish("GOOGLE_ERR|failed") }
    }

    /// The sheet's answer, on the main queue whatever queue the system called back on (周瑜 on #1014).
    private func completed(url: URL?, error: Error?, state: String, clientId: String, redirect: String, verifier: String) {
            guard session != nil else { return }   // cancelled meanwhile (GOOGLE_CANCEL): already answered
            // 取消 in the system's confirm box or the sheet, or Cancel / Deny on Google's own page (it comes back as
            // error=access_denied): all are the player backing out — the card again, nothing said (不知火舞 on 1.6)
            if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { finish("GOOGLE_ERR|canceled"); return }
            let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
            if items?.first(where: { $0.name == "error" })?.value == "access_denied" { finish("GOOGLE_ERR|canceled"); return }
            guard error == nil, let items,
                  items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else {
                finish("GOOGLE_ERR|failed")
                return
            }
            exchange(code: code, clientId: clientId, redirect: redirect, verifier: verifier)
    }

    /// The authorization code for the ID token at Google's token endpoint (an iOS client has no secret: PKCE stands in).
    private func exchange(code: String, clientId: String, redirect: String, verifier: String) {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "code", value: code), URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirect), URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code_verifier", value: verifier),
        ]
        req.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            let token = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["id_token"] as? String
            DispatchQueue.main.async { self?.finish(token.map { "GOOGLE_OK|\($0)" } ?? "GOOGLE_ERR|no_token") }
        }.resume()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return Data(b).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
