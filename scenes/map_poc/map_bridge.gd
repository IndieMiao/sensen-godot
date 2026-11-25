class_name MapBridge
extends RefCounted
## 地图桥抽象（方案 spec §5.4 的供应商/平台抽象层）：场景代码只面向本接口，
## 不触碰任何平台 API。实现：MapBridgeAndroid（插件 singleton）、MapBridgeIOS
## （UDP 回环 → MapUnderlay.swift）；未来 MapLibre 逃生通道也从这里换实现。

signal map_ready
signal pois_received(request_id: int, payload: String)

func request_pois(request_id: int) -> void:
	pois_received.emit(request_id, '{"features":[],"error":"unsupported"}')

func set_city_style(_enabled: bool) -> void:
	pass

## 定位回传（Android 实现发出；无定位能力的平台不发）。accuracy 单位米，越小越准。
signal location_update(lat: float, lng: float, accuracy: float)

func create_map(_token: String, _lat: float, _lng: float, _zoom: float) -> void:
	pass

func set_camera(_lat: float, _lng: float, _zoom: float, _bearing: float, _pitch: float) -> void:
	pass

func set_map_visible(_visible: bool) -> void:
	pass

## Request the Android task to move to background; false means the host must use its exit fallback.
func move_task_to_back() -> bool:
	return false

## Opaque fallback behind the Godot surface when an independent 3D preview covers the map.
func set_map_occlusion_color(_rgb: String) -> bool:
	return false

## UI-thread cached diagnostics, never a render-completion acknowledgement.
func map_visibility_state() -> String:
	return "{}"

func supports_surface_opacity() -> bool:
	return false

## Explicit preview scene intent; ordinary Activity pause must not choose the format.
func set_godot_surface_opaque(_opaque: bool) -> bool:
	return false

func set_language(_locale: String) -> void:
	pass

func get_pixel_ratio() -> float:
	return 1.0

## Whether this platform has a Mapbox map, so the game draws its credit line (q(133) v3): not on the desktop.
func has_mapbox() -> bool:
	return false

func camera_info() -> String:
	return ""

## 启动定位订阅（含运行时权限）。默认空转——iOS/桌面无实现，
## 调用方（map_poc）靠 HOME_TIMEOUT_S 超时回落默认点。
func start_location() -> void:
	pass

## 每帧调用（收异步消息/重发）；无事可做的实现留空。
func poll() -> void:
	pass


# Dynamic-farm selection. All generations share one allocator across scene/bridge instances.
signal parcel_ready(generation: int, style_generation: int, payload: String)
signal parcel_query_result(request_id: int, generation: int, style_generation: int, payload: String)
signal parcel_error(generation: int, style_generation: int, code: String)
static var _next_parcel_generation: int = 0

static func next_parcel_generation() -> int:
	_next_parcel_generation += 1
	return _next_parcel_generation

func supports_parcels() -> bool:
	return false

func set_parcel_sources(generation: int, _config_json: String) -> void:
	parcel_error.emit(generation, 0, "unsupported")

func query_parcel_at(request_id: int, generation: int, _point: Vector2) -> void:
	parcel_query_result.emit(request_id, generation, 0,
		'{"parcel_ids":[],"properties":[],"kind":"none","building_key":"","building_source":"","error":"unsupported"}')

func set_parcel_states(generation: int, _batch_json: String) -> void:
	parcel_error.emit(generation, 0, "unsupported")

func set_parcel_claims(generation: int, _claims_json: String) -> void:
	parcel_error.emit(generation, 0, "unsupported")

func set_parcel_building_highlight(generation: int, _key: String, _parcel_id := "") -> void:
	parcel_error.emit(generation, 0, "unsupported")

## C-130 dynamic farm starter zone: its own native layer (boundary ring and style JSON; "" clears it). Bridges
## without it simply show no marker; the server still holds claims to the zone.
func set_starter_zone(_generation: int, _zone_json: String) -> void:
	pass

func clear_parcel_layers(_generation: int) -> void:
	pass
