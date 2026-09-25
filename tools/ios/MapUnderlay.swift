// iOS 地图垫底层：Android GodotMapPlugin 的孪生（PoC 形态）。
// 职责：Mapbox MapView 垫在 Godot 透明视图之下 + UIKit 链透明化（G3 已验证）+
//      本机 UDP(46464) 接收 GDScript 指令（Mapbox v11 纯 Swift API，PoC 用回环桥，
//      正式化时迁 GDExtension/插件）。
// 协议（UTF-8 文本，'|' 分隔）：
//   Godot → 本层：CREATE|token|lat|lng|zoom ／ CAM|lat|lng|zoom|bearing|pitch ／ VIS|0/1 ／ LANG|locale
//   本层 → Godot：READY|pixelRatio（样式加载完成后，答复 CREATE 的来源端口）
import UIKit
import Network
import MapboxMaps

@objc(MapUnderlay)
class MapUnderlay: NSObject {
    @objc static let shared = MapUnderlay()

    private var mapView: MapView?
    private var listener: NWListener?
    private var listenerReady = false
    private var listenerRetry: DispatchWorkItem?
    private var listenerRetryAttempt = 0
    private var started = false
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var replyConn: NWConnection?
    private var cancelables = Set<AnyCancelable>()
    private var mapLocale = Locale(identifier: "zh-Hans")
    private var styleLoaded = false

    @objc class func setup() {
        shared.start()
    }

    private func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
                name: UIApplication.didBecomeActiveNotification, object: nil)
        applyTransparency()
        startListener()
    }

    @objc private func becameActive() {
        if !listenerReady { restartListener() }
        applyTransparency()
    }

    // MARK: - UDP 桥

    private func startListener() {
        guard listener == nil else { return }
        do {
            let parameters = NWParameters.udp
            // This is an in-process bridge. It does not need a LAN listener.
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 46464)
            let l = try NWListener(using: parameters)
            listener = l
            listenerReady = false
            l.stateUpdateHandler = { [weak self, weak l] state in
                guard let self, let l, self.listener === l else { return }
                switch state {
                case .ready:
                    self.listenerReady = true
                    self.listenerRetryAttempt = 0
                    self.listenerRetry?.cancel()
                    self.listenerRetry = nil
                    NSLog("[MapUnderlay] listener ready on loopback udp/46464")
                case .failed(let error):
                    NSLog("[MapUnderlay] listener failed: \(error); will retry")
                    self.listener = nil
                    self.listenerReady = false
                    l.cancel()
                    self.scheduleListenerRetry()
                case .waiting(let error):
                    self.listenerReady = false
                    NSLog("[MapUnderlay] listener waiting: \(error)")
                    self.scheduleListenerRetry()
                case .cancelled:
                    self.listener = nil
                    self.listenerReady = false
                    self.scheduleListenerRetry()
                default:
                    break
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                guard let self else { conn.cancel(); return }
                self.connections[ObjectIdentifier(conn)] = conn
                conn.stateUpdateHandler = { [weak self, weak conn] state in
                    guard let self, let conn else { return }
                    switch state {
                    case .failed, .cancelled:
                        self.connections.removeValue(forKey: ObjectIdentifier(conn))
                        if self.replyConn === conn { self.replyConn = nil }
                    default:
                        break
                    }
                }
                conn.start(queue: .main)
                self.receiveLoop(conn)
            }
            l.start(queue: .main)
        } catch {
            NSLog("[MapUnderlay] listener error: \(error)")
            scheduleListenerRetry()
        }
    }

    private func scheduleListenerRetry() {
        guard listenerRetry == nil else { return }
        let delay = min(Double(listenerRetryAttempt + 1), 4.0)
        listenerRetryAttempt += 1
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.listenerRetry = nil
            guard !self.listenerReady,
                  UIApplication.shared.applicationState != .background else { return }
            self.restartListener()
        }
        listenerRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func restartListener() {
        listenerRetry?.cancel()
        listenerRetry = nil
        let previous = listener
        listener = nil
        listenerReady = false
        replyConn = nil
        let peers = Array(connections.values)
        connections.removeAll()
        peers.forEach { $0.cancel() }
        previous?.cancel()
        startListener()
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { conn.cancel(); return }
            if let error {
                // A closed Godot scene can retire a peer. Re-reading a failed
                // NWConnection would otherwise spin on the main queue.
                NSLog("[MapUnderlay] bridge peer closed: \(error)")
                if self.replyConn === conn { self.replyConn = nil }
                conn.cancel()
                return
            }
            if let d = data, let s = String(data: d, encoding: .utf8) {
                self.handle(s, from: conn)
            }
            self.receiveLoop(conn)
        }
    }

    private func handle(_ msg: String, from conn: NWConnection) {
        let p = msg.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        switch p.first {
        case "CREATE" where p.count >= 5:
            replyConn = conn
            ensureMap(token: p[1],
                    lat: Double(p[2]) ?? 0, lng: Double(p[3]) ?? 0,
                    zoom: Double(p[4]) ?? 15)
        case "CAM" where p.count >= 6:
            mapView?.mapboxMap.setCamera(to: CameraOptions(
                    center: CLLocationCoordinate2D(latitude: Double(p[1]) ?? 0,
                            longitude: Double(p[2]) ?? 0),
                    zoom: Double(p[3]) ?? 15,
                    bearing: Double(p[4]) ?? 0,
                    pitch: Double(p[5]) ?? 0))
        case "VIS" where p.count >= 2:
            mapView?.isHidden = (p[1] == "0")
            if p[1] != "0" { applyTransparency() }
        case "LANG" where p.count >= 2:
            let locale = Locale(identifier: p[1] == "en" ? "en" : "zh-Hans")
            if locale != mapLocale {
                mapLocale = locale
                localizeMap()
            }
        default:
            NSLog("[MapUnderlay] unknown command: \(p.first ?? "")")
        }
    }

    private func sendReady() {
        guard styleLoaded else { return }
        let s = "READY|\(Double(UIScreen.main.scale))"
        replyConn?.send(content: s.data(using: .utf8),
                completion: .contentProcessed { _ in })
        NSLog("[MapUnderlay] sent \(s)")
    }

    // MARK: - 地图

    private func ensureMap(token: String, lat: Double, lng: Double, zoom: Double) {
        guard let window = gameWindow() else { return }
        if mapView != nil {
            // 幂等重入（场景返回）：恢复可见并补发 READY
            mapView?.isHidden = false
            sendReady()
            return
        }
        MapboxOptions.accessToken = token
        let options = MapInitOptions(
                cameraOptions: CameraOptions(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                        zoom: zoom),
                styleURI: .streets)
        let mv = MapView(frame: window.bounds, mapInitOptions: options)
        mv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.insertSubview(mv, at: 0) // 垫底：Godot 透明视图之下
        mapView = mv
        mv.mapboxMap.onStyleLoaded.observe { [weak self] _ in
            NSLog("[MapUnderlay] style loaded")
            self?.styleLoaded = true
            self?.localizeMap()
            self?.sendReady()
        }.store(in: &cancelables)
        mv.mapboxMap.onMapLoadingError.observe { [weak self] event in
            guard let self, !self.styleLoaded else { return }
            // Do not log request URLs or the access token carried by CREATE.
            NSLog("[MapUnderlay] map loading error type: \(event.type)")
        }.store(in: &cancelables)
        // 地图挂上后再补一次透明化（防层级变动）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.applyTransparency()
        }
        NSLog("[MapUnderlay] MapView created @(\(lat),\(lng)) z=\(zoom)")
    }

    private func localizeMap() {
        guard styleLoaded, let map = mapView?.mapboxMap else { return }
        do {
            try map.localizeLabels(into: mapLocale)
        } catch {
            NSLog("[MapUnderlay] localization failed: \(error)")
        }
    }

    // MARK: - 透明化（G3 spike 已验证逻辑）

    private func gameWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive ||
                      $0.activationState == .foregroundInactive }
            .flatMap { $0.windows }
            .filter { !$0.isHidden && $0.windowLevel == .normal && $0.rootViewController != nil }
        if let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first {
            return window
        }
        // Godot's older app-delegate template can still use the legacy window.
        return UIApplication.shared.windows.first(where: {
            !$0.isHidden && $0.windowLevel == .normal && $0.rootViewController != nil
        })
    }

    private func applyTransparency() {
        guard let window = gameWindow(),
              let root = window.rootViewController?.view else { return }
        window.backgroundColor = .clear
        var stack: [UIView] = [root]
        while let v = stack.popLast() {
            v.isOpaque = false
            v.backgroundColor = .clear
            stack.append(contentsOf: v.subviews)
            var layers: [CALayer] = [v.layer]
            while let l = layers.popLast() {
                if let ml = l as? CAMetalLayer {
                    ml.isOpaque = false
                }
                layers.append(contentsOf: l.sublayers ?? [])
            }
        }
    }
}
