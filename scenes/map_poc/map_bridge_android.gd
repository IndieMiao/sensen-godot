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
var _awaiting_permission := false
var _poll_frames := 0

func _init() -> void:
	if not Engine.has_singleton("GodotMap"):
		return
	_plugin = Engine.get_singleton("GodotMap")
	if not is_instance_valid(_plugin):
		return
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
