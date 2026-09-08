class_name PushBridgeFactory
extends RefCounted
## 平台桥工厂（与 VoiceBridgeFactory 同构）。拿不到能用的桥就返回 null——桌面没有推送通道，
## 上层据此什么也不做，而不是拿着空 token 去打服务端。
## 单例在不在 ≠ 能不能推：桌面装的是空实现（有单例、is_available() 恒 false）。

const SINGLETON := "SensenPush"

static func make() -> PushBridge:
	if not Engine.has_singleton(SINGLETON):
		return null
	var bridge := PushBridgeNative.new()
	return bridge if bridge.available() else null
