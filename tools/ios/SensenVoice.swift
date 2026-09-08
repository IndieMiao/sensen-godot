// C4 语音（iOS）：LiveKit client-sdk-swift 的门面。由 tools/ios/setup_ios_g3.sh 注入 Xcode 工程
// （和 MapUnderlay.swift 同一套路），GDExtension（native/voice）运行时用 NSClassFromString 找到
// 这个类，方法一一转过来。
//
// 跨语言只走两个方向：调用是 ObjC 选择器进来，状态靠 snapshot() 出去。不做 Swift → C++ 回调，
// 因为 VoiceBridge 本来就约定了每帧 poll()，取快照比注册函数指针好排查得多。
//
// 麦克风闸门在**服务端签的 token** 上（video.canPublish）：这里 setMic(true) 时如果没有发布权限，
// LiveKit 会拒绝，我们把错误记进快照，不去猜「应该能不能说」。
import AVFAudio
import Foundation
import LiveKit

@objc(SensenVoiceCore)
public final class SensenVoiceCore: NSObject {
    /// 与 VoiceBridge.State 一一对应：0=IDLE 1=CONNECTING 2=CONNECTED 3=RECONNECTING
    private enum Snapshot: Int {
        case idle = 0, connecting = 1, connected = 2, reconnecting = 3
    }

    @objc public static let shared = SensenVoiceCore()

    private let room = Room()
    private let lock = NSLock()
    private var state: Snapshot = .idle
    private var speakingIdentities: [String] = []
    /// 一次性的：被 snapshot() 取走就清掉，免得同一条错误每帧都报一遍。
    private var pendingError = ""
    private var lastReason = ""

    private override init() {
        super.init()
        room.add(delegate: self)
    }

    // MARK: - GDExtension 调过来的

    @objc public func connectRoom(_ url: String, token: String) {
        setState(.connecting)
        Task { [weak self] in
            guard let self else { return }
            do {
                // 语音房要外放而不是听筒，且要能与别的音频混（背景音乐、地图提示音）。
                try? AVAudioSession.sharedInstance().setCategory(
                    .playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
                try await self.room.connect(url: url, token: token)
                // 进房默认不开麦：上麦是显式动作（语音房页面的麦克风按钮）。
                _ = try? await self.room.localParticipant.setMicrophone(enabled: false)
            } catch {
                self.setState(.idle, reason: "connect_failed")
                self.report(error)
            }
        }
    }

    @objc public func disconnectRoom() {
        Task { [weak self] in
            await self?.room.disconnect()
        }
    }

    @objc public func setMic(_ enabled: Bool) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.room.localParticipant.setMicrophone(enabled: enabled)
            } catch {
                // 没有发布权限时就是走到这里：token 说了算，UI 保持静音。
                self.report(error)
            }
        }
    }

    /// 本地压低某个人的声音（举报后立刻静音，不等服务端处理）。
    @objc public func setVolumeFor(_ identity: String, volume: Double) {
        let target = Participant.Identity(from: identity)
        guard let participant = room.remoteParticipants[target] else { return }
        for publication in participant.audioTracks {
            // volume 是属性不是方法；0.0 静音，1.0 原样，SDK 自己夹在 0…10。
            (publication.track as? RemoteAudioTrack)?.volume = volume
        }
    }

    /// GDExtension 每帧取一次。错误取走即清。
    @objc public func snapshot() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        let snap: [String: Any] = [
            "state": state.rawValue,
            "speakers": speakingIdentities,
            "error": pendingError,
            "reason": lastReason,
        ]
        pendingError = ""
        return snap
    }

    // MARK: - 内部

    private func setState(_ next: Snapshot, reason: String = "") {
        lock.lock()
        state = next
        if !reason.isEmpty { lastReason = reason }
        if next == .connected { lastReason = "" }
        lock.unlock()
    }

    private func report(_ error: Error) {
        lock.lock()
        pendingError = String(describing: error)
        lock.unlock()
    }
}

extension SensenVoiceCore: RoomDelegate {
    public func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldState: ConnectionState) {
        switch connectionState {
        case .connected:
            setState(.connected)
        case .connecting:
            setState(.connecting)
        case .reconnecting:
            setState(.reconnecting)
        case .disconnected:
            setState(.idle, reason: lastReason.isEmpty ? "closed" : lastReason)
        case .disconnecting:
            break // 过渡态，等 .disconnected 再落地，免得 UI 闪一下「已断开」又变回来
        }
    }

    public func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        setState(.idle, reason: error == nil ? "closed" : "error")
        if let error { report(error) }
    }

    /// 谁在说话：身份就是我们自己的 user_id（服务端签 token 时写进 identity）。
    public func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        let names = participants.compactMap { $0.identity?.stringValue }
        lock.lock()
        speakingIdentities = names
        lock.unlock()
    }
}
