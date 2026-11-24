class_name MapBridgeAndroid
extends MapBridge
## Android 实现：包装 GodotMap 插件 singleton（GodotMapPlugin.kt）。

## Android 12+（本工程 targetSdk 取 Godot 默认 36）要求 FINE 与 COARSE 在同一次
## 运行时请求里提交，否则系统直接忽略。OS.request_permissions()（复数）一次提交
## manifest 中全部危险权限；单数版 OS.request_permission("...FINE_LOCATION")
## 会静默失败（无弹窗、无回调）——这是本模块最容易翻车的点。
const LOCATION_PERMS := [
	"android.permission.ACCESS_FINE_LOCATION",
	"android.permission.ACCESS_COARSE_LOCATION",
]
## 授权对话框的等待上限（poll 帧数）。用户点"拒绝"后不该无限轮询。
const PERMISSION_POLL_LIMIT := 600
const PERMISSION_POLL_EVERY := 15

var _plugin: Object
var _parcel_generation: int = -1
var _parcel_style: int = -1
var _parcel_request: int = -1
var _parcel_request_epoch: int = -1
var _parcel_active := false
var _awaiting_permission := false
var _poll_frames := 0

func _init() -> void:
	if not Engine.has_singleton("GodotMap"):
		return
	_plugin = Engine.get_singleton("GodotMap")
	if not is_instance_valid(_plugin):
		return
	_connect_parcel_signals()
	# 插件在 Android UI 线程 emitSignal，必须 deferred 回主循环再碰场景树
	_plugin.connect("map_ready", func(): map_ready.emit(), CONNECT_DEFERRED)
	if _plugin.has_signal("pois_received"):
		_plugin.connect("pois_received", func(id: int, json: String): pois_received.emit(id, json), CONNECT_DEFERRED)
	_plugin.connect("location_update",
		func(lat: float, lng: float, acc: float): location_update.emit(lat, lng, acc),
		CONNECT_DEFERRED)

func create_map(token: String, lat: float, lng: float, zoom: float) -> void:
	if not is_instance_valid(_plugin):
		return
	_plugin.createMap(token, lat, lng, zoom)

func set_camera(lat: float, lng: float, zoom: float, bearing: float, pitch: float) -> void:
	if not is_instance_valid(_plugin):
		return
	_plugin.setCamera(lat, lng, zoom, bearing, pitch)

func set_map_visible(visible: bool) -> void:
	if not visible and _parcel_active:
		clear_parcel_layers(_parcel_generation)
	# Android can dispose the native singleton before the scene's exit cleanup.
	if not is_instance_valid(_plugin):
		return
	_plugin.setMapVisible(visible)

func get_pixel_ratio() -> float:
	if not is_instance_valid(_plugin):
		return 1.0
	return maxf(float(_plugin.getPixelRatio()), 0.5)

func set_language(locale: String) -> void:
	if _supports("setLanguage"):
		_plugin.setLanguage(locale)

func has_mapbox() -> bool:
	return is_instance_valid(_plugin)

func _supports(method: String) -> bool:
	if not is_instance_valid(_plugin): return false
	# Android singletons are JavaObject wrappers; Object.has_method sees only the wrapper.
	if _plugin.has_method("has_java_method"): return _plugin.has_java_method(method)
	return _plugin.has_method(method)

func move_task_to_back() -> bool:
	if not _supports("moveTaskToBack"): return false
	_plugin.moveTaskToBack()
	return true

func set_map_occlusion_color(rgb: String) -> bool:
	if not _supports("setMapOcclusionColor") or not _supports("getMapVisibilityState"): return false
	_plugin.setMapOcclusionColor(rgb)
	return true

func map_visibility_state() -> String:
	return str(_plugin.getMapVisibilityState()) if _supports("getMapVisibilityState") else "{}"

func supports_surface_opacity() -> bool:
	return _supports("setGodotSurfaceOpaque")

func set_godot_surface_opaque(opaque: bool) -> bool:
	if not supports_surface_opacity(): return false
	_plugin.setGodotSurfaceOpaque(opaque)
	return true

func camera_info() -> String:
	if not is_instance_valid(_plugin):
		return ""
	return _plugin.getCameraInfo()

func request_pois(request_id: int) -> void:
	if _supports("queryCityPois"):
		_plugin.queryCityPois(request_id)
	else:
		super.request_pois(request_id)

func set_city_style(enabled: bool) -> void:
	if _supports("setCityStyle"):
		_plugin.setCityStyle(enabled)

func start_location() -> void:
	if not is_instance_valid(_plugin):
		_awaiting_permission = false
		return
	if _has_location_permission():
		_plugin.startLocation()
		return
	# Asks for every dangerous permission in the manifest, RECORD_AUDIO too, through GodotActivity: a microphone grant here
	# starts the engine's own audio input and nothing stops it (SGODOT-349). The P0 map never comes here; native/permission's
	# PermissionActivity is the way to ask for the microphone (周瑜 on #519).
	OS.request_permissions()
	_awaiting_permission = true
	_poll_frames = 0

## request_permissions() 是异步的（系统弹窗），授权结果没有 GDScript 信号，
## 只能轮询 get_granted_permissions()。授权到手就启动定位；拒绝或超时就放弃，
## 场景那边的 3 秒超时会接管回落。
func poll() -> void:
	if not is_instance_valid(_plugin):
		_awaiting_permission = false
		return
	if not _awaiting_permission:
		return
	_poll_frames += 1
	if _poll_frames > PERMISSION_POLL_LIMIT:
		_awaiting_permission = false
		push_warning("MapBridgeAndroid: 定位授权等待超时，放弃定位")
		return
	if _poll_frames % PERMISSION_POLL_EVERY != 0:
		return
	if _has_location_permission():
		_awaiting_permission = false
		_plugin.startLocation()

func _has_location_permission() -> bool:
	var granted := OS.get_granted_permissions()
	for p in LOCATION_PERMS:
		if granted.has(p):
			return true
	return false


func supports_parcels() -> bool:
	for method in ["setParcelSources", "queryParcelAt", "setParcelStates", "setParcelClaims",
			"setParcelBuildingHighlight", "clearParcelLayers", "getParcelLifecycleEpoch"]:
		if not _supports(method): return false
	for event in ["parcel_ready", "parcel_query_result", "parcel_error"]:
		if not _plugin.has_signal(event): return false
	return true

func _connect_parcel_signals() -> void:
	if not supports_parcels(): return
	_plugin.connect("parcel_ready", _on_parcel_ready, CONNECT_DEFERRED)
	_plugin.connect("parcel_query_result", _on_parcel_result, CONNECT_DEFERRED)
	_plugin.connect("parcel_error", _on_parcel_error, CONNECT_DEFERRED)

func set_parcel_sources(generation: int, config_json: String) -> void:
	if not supports_parcels():
		super.set_parcel_sources(generation, config_json)
		return
	# Every source/dataset/scene replacement gets a new generation, including retries.
	if generation <= _parcel_generation or generation <= 0:
		parcel_error.emit(generation, 0, "invalid_generation")
		return
	_parcel_generation = generation
	_parcel_style = -1
	_parcel_request = -1
	_parcel_active = true
	_plugin.setParcelSources(generation, config_json)

func query_parcel_at(request_id: int, generation: int, point: Vector2) -> void:
	if not supports_parcels():
		super.query_parcel_at(request_id, generation, point)
		return
	if not _parcel_active or generation != _parcel_generation: return
	if request_id <= _parcel_request:
		parcel_error.emit(generation, maxi(_parcel_style, 0), "invalid_request_id")
		return
	_parcel_request = request_id
	_parcel_request_epoch = int(_plugin.getParcelLifecycleEpoch())
	_plugin.queryParcelAt(request_id, generation, point.x, point.y)

func set_parcel_states(generation: int, batch_json: String) -> void:
	if not supports_parcels():
		super.set_parcel_states(generation, batch_json)
	elif _parcel_active and generation == _parcel_generation:
		_plugin.setParcelStates(generation, batch_json)

func set_parcel_claims(generation: int, claims_json: String) -> void:
	if not supports_parcels():
		super.set_parcel_claims(generation, claims_json)
	elif _parcel_active and generation == _parcel_generation:
		_plugin.setParcelClaims(generation, claims_json)

func set_parcel_building_highlight(generation: int, key: String, parcel_id := "") -> void:
	if not supports_parcels():
		super.set_parcel_building_highlight(generation, key, parcel_id)
	elif _parcel_active and generation == _parcel_generation:
		_plugin.setParcelBuildingHighlight(generation, key, parcel_id)

func clear_parcel_layers(generation: int) -> void:
	if not _parcel_active or generation != _parcel_generation: return
	# Invalidate before touching Java: queued deferred results must not revive the departed scene.
	_parcel_active = false
	_parcel_request = -1
	if _supports("clearParcelLayers"):
		_plugin.clearParcelLayers(generation)

func _accept_parcel_event(generation: int, style_generation: int) -> bool:
	if not _parcel_active or generation != _parcel_generation or style_generation < _parcel_style:
		return false
	_parcel_style = style_generation
	return true

func _on_parcel_ready(generation: int, style_generation: int, payload: String) -> void:
	if _accept_parcel_event(generation, style_generation):
		parcel_ready.emit(generation, style_generation, payload)

func _on_parcel_result(request_id: int, generation: int, style_generation: int, payload: String) -> void:
	# Native may already have emitted this result before Android paused. Reading its
	# atomic watermark here also rejects results already queued in Godot's deferred queue.
	if not _supports("getParcelLifecycleEpoch"): return
	if _parcel_request_epoch != int(_plugin.getParcelLifecycleEpoch()): return
	if request_id == _parcel_request and _accept_parcel_event(generation, style_generation):
		parcel_query_result.emit(request_id, generation, style_generation, payload)

func _on_parcel_error(generation: int, style_generation: int, code: String) -> void:
	if _accept_parcel_event(generation, style_generation):
		parcel_error.emit(generation, style_generation, code)
