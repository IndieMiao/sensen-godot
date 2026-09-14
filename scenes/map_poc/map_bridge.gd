class_name MapBridge
extends RefCounted
## 地图桥抽象（方案 spec §5.4 的供应商/平台抽象层）：场景代码只面向本接口，
## 不触碰任何平台 API。实现：MapBridgeAndroid（插件 singleton）、MapBridgeIOS
## （UDP 回环 → MapUnderlay.swift）；未来 MapLibre 逃生通道也从这里换实现。

signal map_ready

## 定位回传（Android 实现发出；无定位能力的平台不发）。accuracy 单位米，越小越准。
signal location_update(lat: float, lng: float, accuracy: float)

func create_map(_token: String, _lat: float, _lng: float, _zoom: float) -> void:
	pass

func set_camera(_lat: float, _lng: float, _zoom: float, _bearing: float, _pitch: float) -> void:
	pass

func set_map_visible(_visible: bool) -> void:
	pass

func set_language(_locale: String) -> void:
	pass

func get_pixel_ratio() -> float:
	return 1.0

func camera_info() -> String:
	return ""

## 启动定位订阅（含运行时权限）。默认空转——iOS/桌面无实现，
## 调用方（map_poc）靠 HOME_TIMEOUT_S 超时回落默认点。
func start_location() -> void:
	pass

## 每帧调用（收异步消息/重发）；无事可做的实现留空。
func poll() -> void:
	pass
