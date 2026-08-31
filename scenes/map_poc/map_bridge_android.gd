class_name MapBridgeAndroid
extends MapBridge
## Android 实现：包装 GodotMap 插件 singleton（GodotMapPlugin.kt）。

var _plugin: Object

func _init() -> void:
	_plugin = Engine.get_singleton("GodotMap")
	# 插件在 Android UI 线程 emitSignal，必须 deferred 回主循环再碰场景树
	_plugin.connect("map_ready", func(): map_ready.emit(), CONNECT_DEFERRED)

func create_map(token: String, lat: float, lng: float, zoom: float) -> void:
	_plugin.createMap(token, lat, lng, zoom)

func set_camera(lat: float, lng: float, zoom: float, bearing: float, pitch: float) -> void:
	_plugin.setCamera(lat, lng, zoom, bearing, pitch)

func set_map_visible(visible: bool) -> void:
	_plugin.setMapVisible(visible)

func get_pixel_ratio() -> float:
	return maxf(float(_plugin.getPixelRatio()), 0.5)

func camera_info() -> String:
	return _plugin.getCameraInfo()
