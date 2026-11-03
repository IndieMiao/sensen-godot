// The crop-ready local notification on iOS (SGODOT-356; Android's is native/notify/android/GodotNotifyPlugin.kt).
//
// The same in-process loopback UDP as AppleSignIn, on a port of its own (46466). One line per packet, | between fields:
//   Godot → native  NOTIFY_STATE                         say the state back (sent again until it comes)
//                   NOTIFY_AUTH                          the system's dialog; NOTIFY_STATE answers when it is closed
//                   NOTIFY_AT|<unix ms>|<title>|<body>   one notification then, replacing any set before
//                   NOTIFY_CANCEL_ALL                    the one not shown yet and the one shown, both gone
//                   NOTIFY_SETTINGS                      the system's notification settings for this app
//   native → Godot  NOTIFY_STATE|<json>                  {needs_grant, allowed, asked, app}: as GodotNotify.state(),
//                                                        and again whenever the app comes back to the front
// Local notifications need no aps-environment entitlement and no change to signing. Bootstrapped by G3Spike.mm.
import Foundation
import Network
import UIKit
import UserNotifications

@objc(LocalNotify)
final class LocalNotify: NSObject, UNUserNotificationCenterDelegate {
    @objc static let shared = LocalNotify()

    /// One identifier: a new NOTIFY_AT replaces the one set before, as Android's single alarm does.
    private static let id = "p0.crops"
    private static let port: NWEndpoint.Port = 46466

    private var listener: NWListener?
    /// Godot's socket, the last one heard from: where NOTIFY_STATE goes when the app comes back.
    private var client: NWConnection?
    private var retryScheduled = false
    private var awayTask = UIBackgroundTaskIdentifier.invalid

    @objc class func setup() {
        UNUserNotificationCenter.current().delegate = shared
        shared.startListener()
        NotificationCenter.default.addObserver(shared, selector: #selector(becameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(shared, selector: #selector(wentAway),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc private func becameActive() {
        sendState()
    }

    /// Godot sends NOTIFY_AT from its own PAUSED notification, on the way out: keep the app up a moment so it arrives.
    @objc private func wentAway() {
        guard awayTask == .invalid else { return }
        awayTask = UIApplication.shared.beginBackgroundTask(withName: "LocalNotify") { [weak self] in self?.endAway() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.endAway() }
    }

    private func endAway() {
        guard awayTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(awayTask)
        awayTask = .invalid
    }

    private func startListener() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.udp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: LocalNotify.port)
            let l = try NWListener(using: parameters)
            listener = l
            l.stateUpdateHandler = { [weak self, weak l] state in
                guard let self, let l, self.listener === l else { return }
                switch state {
                case .ready:
                    NSLog("[LocalNotify] listener ready on loopback udp/46466")
                case .failed(let error):
                    NSLog("[LocalNotify] listener failed: \(error); will retry")
                    l.cancel()
                    self.listener = nil
                    self.scheduleRetry()
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { conn.cancel(); return }
                conn.stateUpdateHandler = { [weak self, weak conn] state in
                    guard let self, let conn else { return }
                    switch state {
                    case .failed, .cancelled:
                        if self.client === conn { self.client = nil }
                    default:
                        break
                    }
                }
                conn.start(queue: .main)
                self.receiveLoop(conn)
            }
            l.start(queue: .main)
        } catch {
            NSLog("[LocalNotify] listener error: \(error)")
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

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { conn.cancel(); return }
            if error != nil { conn.cancel(); return }
            if let d = data, let s = String(data: d, encoding: .utf8) {
                self.client = conn
                self.handle(s)
            }
            self.receiveLoop(conn)
        }
    }

    private func handle(_ msg: String) {
        let p = msg.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        let center = UNUserNotificationCenter.current()
        switch p.first {
        case "NOTIFY_STATE":
            sendState()
        case "NOTIFY_AUTH":
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
                if let error { NSLog("[LocalNotify] authorization error: \(error)") }
                DispatchQueue.main.async { self?.sendState() }
            }
        case "NOTIFY_AT" where p.count >= 4:
            guard let atMs = Double(p[1]) else { return }
            let content = UNMutableNotificationContent()
            content.title = p[2]
            content.body = p[3]
            content.sound = .default
            // A time already past goes out in a second (a trigger needs more than 0).
            let seconds = max(1.0, atMs / 1000.0 - Date().timeIntervalSince1970)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            center.add(UNNotificationRequest(identifier: LocalNotify.id, content: content, trigger: trigger)) { error in
                if let error { NSLog("[LocalNotify] schedule error: \(error)") }
            }
        case "NOTIFY_CANCEL_ALL":
            center.removePendingNotificationRequests(withIdentifiers: [LocalNotify.id])
            center.removeDeliveredNotifications(withIdentifiers: [LocalNotify.id])
        case "NOTIFY_SETTINGS":
            var url = UIApplication.openSettingsURLString
            if #available(iOS 16.0, *) { url = UIApplication.openNotificationSettingsURLString }
            if let u = URL(string: url) { UIApplication.shared.open(u) }
        default:
            break
        }
    }

    /// The state GodotNotify.state() gives on Android 13+: the system asks once, so needs_grant always holds; asked is
    /// whether it has (the system keeps that, not us); app is the name the phone shows (`Notifications are off for …`).
    private func sendState() {
        guard let conn = client else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            let allowed = status == .authorized || status == .provisional || status == .ephemeral
            let info = Bundle.main.infoDictionary
            let app = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? ""
            let state: [String: Any] = ["needs_grant": true, "allowed": allowed, "asked": status != .notDetermined, "app": app]
            guard let json = try? JSONSerialization.data(withJSONObject: state),
                  let s = String(data: json, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                conn.send(content: Data("NOTIFY_STATE|\(s)".utf8), completion: .contentProcessed { _ in })
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// In front the game is the news: nothing shows (the game cancels everything when it comes back anyway).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    /// A tap opens the app as its icon would, with no deep link (as on Android).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
