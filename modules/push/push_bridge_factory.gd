class_name PushBridgeFactory
extends RefCounted
## 平台桥工厂（与 VoiceBridgeFactory 同构）。插件不在就返回 null——桌面没有推送通道，
## 上层据此什么也不做，而不是拿着空 token 去打服务端。

const SINGLETON := "SensenPush"

static func make() -> PushBridge:
	if Engine.has_singleton(SINGLETON):
		return PushBridgeNative.new()
	return null
