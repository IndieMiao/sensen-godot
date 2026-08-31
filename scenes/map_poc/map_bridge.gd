class_name MapBridge
extends RefCounted
## 地图桥抽象（方案 spec §5.4 的供应商/平台抽象层）：场景代码只面向本接口，
## 不触碰任何平台 API。实现：MapBridgeAndroid（插件 singleton）、MapBridgeIOS
## （UDP 回环 → MapUnderlay.swift）；未来 MapLibre 逃生通道也从这里换实现。

signal map_ready

func create_map(_token: String, _lat: float, _lng: float, _zoom: float) -> void:
	pass

func set_camera(_lat: float, _lng: float, _zoom: float, _bearing: float, _pitch: float) -> void:
	pass

func set_map_visible(_visible: bool) -> void:
	pass

func get_pixel_ratio() -> float:
	return 1.0

func camera_info() -> String:
	return ""

## 每帧调用（收异步消息/重发）；无事可做的实现留空。
func poll() -> void:
	pass
