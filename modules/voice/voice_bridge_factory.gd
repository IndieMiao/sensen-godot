class_name VoiceBridgeFactory
extends RefCounted
## 平台桥工厂（与 MapBridgeFactory 同构，避免基类反向引用子类）。
## 拿不到能说话的桥就返回 null：语音房页面据此进只读模式，不假装能说话。
##
## 单例在不在 ≠ 能不能说话：桌面装的是空实现（有单例、is_available() 恒 false），
## iOS 上没注入 LiveKit 那层 Swift 时同理。所以这里要问一句再决定。

const SINGLETON := "SensenVoice"

static func make() -> VoiceBridge:
	if not Engine.has_singleton(SINGLETON):
		return null
	var bridge := VoiceBridgeNative.new()
	return bridge if bridge.available() else null
