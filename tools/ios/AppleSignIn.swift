// Sign in with Apple 原生桥（SGODOT-135）。
//
// 与 MapUnderlay 相同的进程内 UDP 回环，但独立端口 46465，地图桥坏了也不影响登录。
// 协议（UTF-8，一行一条，字段以 | 分隔）：
//   Godot → 原生  APPLE|<nonce_sha256_hex>[|none]
//                 第三个字段 none：不要名字和邮箱（P0 只存账号编号，SGODOT-487 / q(312)）；没有它照旧要（Journey）
//   原生 → Godot  APPLE_OK|<identity_token>|<given_name>|<family_name>|<email>|<authorization_code>
//                 APPLE_ERR|<code>      code: canceled | failed | not_handled | unknown | no_token | busy
// nonce 由 Godot 生成原文、这边只收它的 SHA-256（Apple 要求 request.nonce 放哈希），原文随后发给服务端比对。
import AuthenticationServices
import Foundation
import Network
import UIKit

@objc(AppleSignIn)
final class AppleSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    @objc static let shared = AppleSignIn()

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var pending: NWConnection?
    private var controller: ASAuthorizationController?
    private var retryScheduled = false

    @objc class func setup() {
        shared.startListener()
    }

    private func startListener() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.udp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 46465)
            let l = try NWListener(using: parameters)
            listener = l
            l.stateUpdateHandler = { [weak self, weak l] state in
                guard let self, let l, self.listener === l else { return }
                switch state {
                case .ready:
                    NSLog("[AppleSignIn] listener ready on loopback udp/46465")
                case .failed(let error):
                    NSLog("[AppleSignIn] listener failed: \(error); will retry")
                    l.cancel()
                    self.listener = nil
                    self.scheduleRetry()
                default:
                    break
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
            NSLog("[AppleSignIn] listener error: \(error)")
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            self.startListener()
        }
    }

    private func drop(_ conn: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(conn))
        if pending === conn { pending = nil }
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { conn.cancel(); return }
            if error != nil { self.drop(conn); conn.cancel(); return }
            if let d = data, let s = String(data: d, encoding: .utf8) { self.handle(s, from: conn) }
            self.receiveLoop(conn)
        }
    }

    private func handle(_ msg: String, from conn: NWConnection) {
        let parts = msg.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.first == "APPLE", parts.count >= 2, !parts[1].isEmpty else { return }
        if controller != nil {
            send("APPLE_ERR|busy", to: conn)
            return
        }
        pending = conn
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = parts.count >= 3 && parts[2] == "none" ? [] : [.fullName, .email]
        request.nonce = parts[1]
        let c = ASAuthorizationController(authorizationRequests: [request])
        c.delegate = self
        c.presentationContextProvider = self
        controller = c
        c.performRequests()
    }

    private func send(_ line: String, to conn: NWConnection?) {
        conn?.send(content: line.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    /// Names and emails travel inside a |-separated line.
    private func clean(_ s: String?) -> String {
        (s ?? "").replacingOccurrences(of: "|", with: " ").replacingOccurrences(of: "\n", with: " ")
    }

    private func finish(_ line: String) {
        send(line, to: pending)
        pending = nil
        controller = nil
    }

    // MARK: - ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
            finish("APPLE_ERR|no_token")
            return
        }
        let name = credential.fullName
        // The one-time authorization code lets the server obtain a refresh token, which it revokes on account deletion.
        let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        finish("APPLE_OK|\(token)|\(clean(name?.givenName))|\(clean(name?.familyName))|\(clean(credential.email))|\(clean(code))")
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let code: String
        switch (error as? ASAuthorizationError)?.code {
        case .canceled?: code = "canceled"
        case .failed?: code = "failed"
        case .notHandled?: code = "not_handled"
        default: code = "unknown"
        }
        NSLog("[AppleSignIn] authorization error: \(error)")
        finish("APPLE_ERR|\(code)")
    }

    // MARK: - ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first ?? UIWindow()
    }
}
