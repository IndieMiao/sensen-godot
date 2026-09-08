class_name VoiceBridgeFactory
extends RefCounted
## 平台桥工厂（与 MapBridgeFactory 同构，避免基类反向引用子类）。
## 原生插件（C4）到位前这里返回 null：语音房页面据此进只读模式，不假装能说话。

const SINGLETON := "SensenVoice"

static func make() -> VoiceBridge:
	if Engine.has_singleton(SINGLETON):
		return VoiceBridgeNative.new()
	return null
