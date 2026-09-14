extends GdUnitTestSuite

class NativePlugin extends Node:
	signal map_ready
	signal location_update(lat: float, lng: float, accuracy: float)
	var calls: Array = []

	func createMap(token: String, lat: float, lng: float, zoom: float) -> void:
		calls.append(["create", token, lat, lng, zoom])

	func setCamera(lat: float, lng: float, zoom: float, bearing: float, pitch: float) -> void:
		calls.append(["camera", lat, lng, zoom, bearing, pitch])

	func setMapVisible(visible: bool) -> void:
		calls.append(["visible", visible])

	func getPixelRatio() -> float:
		return 2.0

	func getCameraInfo() -> String:
		return "native camera"

	func startLocation() -> void:
		calls.append(["location"])

	func setLanguage(locale: String) -> void:
		calls.append(["language", locale])

class GrantedBridge extends MapBridgeAndroid:
	func _has_location_permission() -> bool:
		return true

var _native: NativePlugin
var _registered := false

func after_test() -> void:
	if _registered:
		Engine.unregister_singleton("GodotMap")
		_registered = false
	if is_instance_valid(_native):
		_native.free()

func _register_native() -> void:
	_native = NativePlugin.new()
	Engine.register_singleton("GodotMap", _native)
	_registered = true

func test_live_plugin_receives_commands_and_forwards_deferred_signals() -> void:
	_register_native()
	var bridge := GrantedBridge.new()
	var received: Array = []
	bridge.map_ready.connect(func(): received.append(["ready"]))
	bridge.location_update.connect(func(lat, lng, accuracy): received.append([lat, lng, accuracy]))
	bridge.create_map("token", 31.0, 121.0, 16.0)
	bridge.set_camera(32.0, 122.0, 17.0, 20.0, 30.0)
	bridge.set_map_visible(false)
	bridge.set_language("zh_CN")
	bridge.set_language("en")
	bridge.start_location()
	bridge._awaiting_permission = true
	bridge._poll_frames = MapBridgeAndroid.PERMISSION_POLL_EVERY - 1
	bridge.poll()
	assert_that(_native.calls).is_equal([
		["create", "token", 31.0, 121.0, 16.0],
		["camera", 32.0, 122.0, 17.0, 20.0, 30.0],
		["visible", false], ["language", "zh_CN"], ["language", "en"], ["location"], ["location"],
	])
	assert_float(bridge.get_pixel_ratio()).is_equal(2.0)
	assert_str(bridge.camera_info()).is_equal("native camera")
	assert_bool(bridge._awaiting_permission).is_false()
	_native.map_ready.emit()
	_native.location_update.emit(31.0, 121.0, 5.0)
	await get_tree().process_frame
	assert_that(received).is_equal([["ready"], [31.0, 121.0, 5.0]])

func test_plugin_freed_before_scene_exit_leaves_every_entry_safe() -> void:
	_register_native()
	var bridge := GrantedBridge.new()
	Engine.unregister_singleton("GodotMap")
	_registered = false
	_native.free()
	assert_bool(is_instance_valid(bridge._plugin)).is_false()
	_assert_unavailable_bridge(bridge)

func test_missing_native_plugin_uses_safe_defaults() -> void:
	assert_bool(Engine.has_singleton("GodotMap")).is_false()
	_assert_unavailable_bridge(GrantedBridge.new())

func _assert_unavailable_bridge(bridge: MapBridgeAndroid) -> void:
	bridge.set_language("zh_CN")
	bridge.create_map("token", 31.0, 121.0, 16.0)
	bridge.set_camera(32.0, 122.0, 17.0, 20.0, 30.0)
	bridge.set_map_visible(false)
	assert_float(bridge.get_pixel_ratio()).is_equal(1.0)
	assert_str(bridge.camera_info()).is_empty()
	bridge._awaiting_permission = true
	bridge.start_location()
	assert_bool(bridge._awaiting_permission).is_false()
	bridge._awaiting_permission = true
	bridge._poll_frames = MapBridgeAndroid.PERMISSION_POLL_EVERY - 1
	bridge.poll()
	assert_bool(bridge._awaiting_permission).is_false()
