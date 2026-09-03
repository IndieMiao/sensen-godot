class_name MapBridgeFactory
extends RefCounted
## 平台桥工厂（避免 MapBridge 基类反向引用子类的脚本环）。地图场景与城市选择页共用。

static func make() -> MapBridge:
	if Engine.has_singleton("GodotMap"):
		return MapBridgeAndroid.new()
	if OS.get_name() == "iOS":
		return MapBridgeIOS.new()
	return null
