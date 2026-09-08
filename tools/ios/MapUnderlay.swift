// iOS 地图垫底层：Android GodotMapPlugin 的孪生（PoC 形态）。
// 职责：Mapbox MapView 垫在 Godot 透明视图之下 + UIKit 链透明化（G3 已验证）+
//      本机 UDP(46464) 接收 GDScript 指令（Mapbox v11 纯 Swift API，PoC 用回环桥，
//      正式化时迁 GDExtension/插件）。
// 协议（UTF-8 文本，'|' 分隔）：
//   Godot → 本层：CREATE|token|lat|lng|zoom ／ CAM|lat|lng|zoom|bearing|pitch ／ VIS|0/1
//               LOC|1（开始定位，When-In-Use 授权）／ LOC|0（停止定位）
//   本层 → Godot：READY|pixelRatio（样式加载完成后，答复 CREATE 的来源端口）
//               LOC|lat|lng|accuracyM（每次定位更新；B5 好友位置由 Godot 侧节流上报）
import UIKit
import Network
import CoreLocation
import MapboxMaps

@objc(MapUnderlay)
class MapUnderlay: NSObject, CLLocationManagerDelegate {
    @objc static let shared = MapUnderlay()

    private var mapView: MapView?
    private var listener: NWListener?
    private var replyConn: NWConnection?
    private var cancelables = Set<AnyCancelable>()
    private var locationManager: CLLocationManager?
    private var wantLocation = false

    @objc class func setup() {
        shared.start()
    }

    private func start() {
        applyTransparency()
        startListener()
        NSLog("[MapUnderlay] started, listening on udp/46464")
    }

    // MARK: - UDP 桥

    private func startListener() {
        do {
            let l = try NWListener(using: .udp, on: 46464)
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .main)
                self?.receiveLoop(conn)
            }
            l.start(queue: .main)
            listener = l
        } catch {
            NSLog("[MapUnderlay] listener error: \(error)")
        }
    }

    private func receiveLoop(_ conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, _ in
            if let d = data, let s = String(data: d, encoding: .utf8) {
                self?.handle(s, from: conn)
            }
            self?.receiveLoop(conn)
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
            if p[1] != "0" {
                // 切 Tab 回来再显示：UIKit 层可能被引擎重设成不透明（键盘弹过一次之后尤其），补一遍透明化。
                applyTransparency()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.applyTransparency() }
            }
        case "LOC" where p.count >= 2:
            replyConn = conn
            if p[1] == "1" { startLocation() } else { stopLocation() }
        default:
            NSLog("[MapUnderlay] unknown msg: \(msg)")
        }
    }

    private func sendReady() {
        let s = "READY|\(Double(UIScreen.main.scale))"
        replyConn?.send(content: s.data(using: .utf8),
                completion: .contentProcessed { _ in })
        NSLog("[MapUnderlay] sent \(s)")
    }

    // MARK: - 定位（When-In-Use；只在地图页可见时开着，Godot 侧 suspend 时发 LOC|0）

    private func startLocation() {
        wantLocation = true
        if locationManager == nil {
            let m = CLLocationManager()
            m.delegate = self
            m.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            m.distanceFilter = 10
            locationManager = m
        }
        guard let m = locationManager else { return }
        switch m.authorizationStatus {
        case .notDetermined:
            m.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            m.startUpdatingLocation()
        default:
            NSLog("[MapUnderlay] location not authorized: \(m.authorizationStatus.rawValue)")
        }
    }

    private func stopLocation() {
        wantLocation = false
        locationManager?.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if wantLocation, manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let s = "LOC|\(l.coordinate.latitude)|\(l.coordinate.longitude)|\(max(l.horizontalAccuracy, 0))"
        replyConn?.send(content: s.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        NSLog("[MapUnderlay] location error: \(error)")
    }

    // MARK: - 地图

    private func ensureMap(token: String, lat: Double, lng: Double, zoom: Double) {
        guard let window = UIApplication.shared.windows.first else { return }
        if mapView != nil {
            // 幂等重入（场景返回）：恢复可见并补发 READY
            mapView?.isHidden = false
            applyTransparency()
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
        mv.mapboxMap.onStyleLoaded.observeNext { [weak self] _ in
            NSLog("[MapUnderlay] style loaded")
            self?.sendReady()
        }.store(in: &cancelables)
        // 地图挂上后再补一次透明化（防层级变动）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.applyTransparency()
        }
        NSLog("[MapUnderlay] MapView created @(\(lat),\(lng)) z=\(zoom)")
    }

    // MARK: - 透明化（G3 spike 已验证逻辑）

    private func applyTransparency() {
        guard let window = UIApplication.shared.windows.first,
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
