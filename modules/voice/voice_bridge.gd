class_name VoiceBridge
extends RefCounted
## C4 LiveKit 音频薄桥接的**抽象**：场景只面向这个接口，不碰任何平台 API
##（与 MapBridge 同一套路数）。实现：
##   - iOS / Android：原生插件包 LiveKit SDK（音频采集 / 3A / 编码全在原生层）
##   - 桌面：社区 godot-livekit GDExtension
##   - 都没有时：VoiceBridgeFactory.make() 返回 null，页面进只读模式（能看不能说）
##
## 状态机只有四档，够 UI 用：IDLE → CONNECTING → CONNECTED →（断了）RECONNECTING。

signal connected()
signal disconnected(reason: String)
signal speaking_changed(identity: String, speaking: bool)
signal error(message: String)

enum State { IDLE, CONNECTING, CONNECTED, RECONNECTING }

var state: State = State.IDLE

## 连房。token 决定能不能发布（服务端签，见 VoiceApi）。
func connect_room(_url: String, _token: String) -> void:
	pass

func disconnect_room() -> void:
	pass

## 开关自己的麦克风。token 不允许发布时实现层应直接忽略并保持静音。
func set_mic(_enabled: bool) -> void:
	pass

## 别人的音量（0.0–1.0），用于本地压低某个人的声音。
func set_volume(_identity: String, _volume: float) -> void:
	pass

## 正在说话的人（识别标识 = 我们的 user_id）。
func speakers() -> PackedStringArray:
	return PackedStringArray()

## 每帧调用（收异步消息）；无事可做的实现留空。
func poll() -> void:
	pass

## 平台是否具备语音能力——UI 据此决定显示「只读」提示还是麦克风按钮。
func available() -> bool:
	return false
