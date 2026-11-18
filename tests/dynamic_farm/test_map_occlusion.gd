extends SceneTree
const Android := preload("res://scenes/map_poc/map_bridge_android.gd")
class Plugin extends Node:
	var supported := true
	var surface_supported := true
	var calls: Array = []
	var shown := true
	var opaque := false
	func has_java_method(method: String) -> bool:
		if method == "setGodotSurfaceOpaque": return supported and surface_supported
		return supported and method in ["setMapOcclusionColor", "getMapVisibilityState", "setMapVisible"]
	func setMapOcclusionColor(rgb: String) -> void: calls.append(["color", rgb])
	func setGodotSurfaceOpaque(value: bool) -> void:
		opaque = value; calls.append(["surface", value])
	func setMapVisible(value: bool) -> void:
		shown = value; calls.append(["visible", value])
	func getMapVisibilityState() -> String:
		return JSON.stringify({"scene_visible": shown, "sample_uptime_ms": 123})
class Selector extends Node:
	var bridge: MapBridge
	var activations := 0
	func pause() -> void: bridge.set_map_visible(false)
	func activate() -> void: activations += 1
class TestCamera extends Control:
	var center := [-122.45, 37.73]
	var zoom := 17.5
	var updates := 0
	func _changed() -> void: updates += 1
class MapPage extends "res://scenes/dynamic_farm/dynamic_farm_map.gd":
	func _ready() -> void:
		_hud = Control.new(); add_child(_hud)
		_message = Label.new(); _hud.add_child(_message)
		_camera = TestCamera.new(); add_child(_camera)
	func _render() -> void: pass
class Router extends Node:
	var bridge: MapBridge
	var top: Node
	var opened := 0
	var received: Dictionary = {}
	func top_instance() -> Node: return top
	func open_instance(_path: String, args: Dictionary) -> void:
		opened += 1; received = args
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func verify(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)
func _run() -> void:
	var plugin := Plugin.new(); root.add_child(plugin)
	var bridge := Android.new(); bridge._plugin = plugin
	var selector := Selector.new(); selector.bridge = bridge
	var page := MapPage.new(); root.add_child(page); page.add_child(selector)
	page._bridge = bridge; page._selector = selector
	var router := Router.new(); router.name = "AppRouter"; root.add_child(router)
	var farm := {"dataset_version":"sf-dynamic-farm-20261118-r4", "block_id":"p-A"}
	await page._open_host(farm)
	verify(plugin.calls == [["color", "#E7F0DF"]] and router.opened == 1, "opaque scene color is supplied before Router may suspend the map")
	verify(router.received.preview_only and router.received.farm == farm, "preview payload keeps identity and presentation-only semantics")
	verify(not plugin.opaque, "cancelled loading before Router suspension never makes the still-visible map opaque")
	plugin.calls.clear(); root.transparent_bg = true
	page._opening = true # Router is now committing the 3D transition.
	page.suspend()
	page._opening = false
	verify(plugin.calls == [["color", "#E7F0DF"], ["surface", true], ["visible", false]], "3D suspension sets scene color and opaque Surface before native hide")
	verify(not root.transparent_bg and page._suspended, "Godot viewport becomes opaque while map is covered")
	verify(plugin.opaque and page._surface_opaque_requested, "3D transition explicitly requests the no-alpha Surface mode")
	verify(not plugin.shown, "native hide request reaches the existing visibility API")
	router.top = Node3D.new(); root.add_child(router.top)
	page._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	verify(not plugin.shown and selector.activations == 0, "foreground while 3D is top cannot reactivate the map")
	verify(plugin.opaque, "3D foreground preserves the explicit opaque mode")
	await create_timer(0.25).timeout
	verify(not plugin.shown, "diagnostic cache polling never changes presentation state")
	router.top.queue_free(); router.top = null
	page._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	verify(plugin.shown and root.transparent_bg and selector.activations == 1, "foreground root map restores native visibility and transparent viewport")
	verify(not plugin.opaque and not page._surface_opaque_requested, "returning map restores the transparent native Surface mode")
	verify(page._camera.updates == 1, "restored map reapplies its saved camera")
	var snapshot: Dictionary = JSON.parse_string(bridge.map_visibility_state())
	verify(snapshot.scene_visible and snapshot.sample_uptime_ms == 123, "bridge preserves snapshot freshness fields without treating cache as an ACK")
	plugin.calls.clear()
	page.suspend()
	verify(not plugin.opaque and not plugin.calls.any(func(call: Array): return call[0] == "surface"), "ordinary map Activity pause does not request a 3D Surface format")
	page.resume()
	plugin.surface_supported = false
	var before_missing := router.opened
	await page._open_host(farm)
	verify(router.opened == before_missing and not plugin.opaque, "a native build without the Surface-mode API cannot enter 3D")
	plugin.surface_supported = true
	plugin.supported = false
	var calls := plugin.calls.size()
	await page._open_host(farm)
	verify(router.opened == 1 and plugin.calls.size() == calls, "old native capability cannot enter 3D with unsupported hiding")
	verify(page._message.text.contains("latest"), "missing native capability gives actionable update feedback")
	verify(bridge.map_visibility_state() == "{}", "unsupported diagnostics returns empty data")
	var host = load("res://scenes/dynamic_farm/dynamic_farm_host.tscn").instantiate(); root.add_child(host)
	host._view = Node3D.new(); host.add_child(host._view)
	var environment := WorldEnvironment.new(); environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.906, 0.941, 0.875, 1.0)
	host._view.add_child(environment)
	var actual: Dictionary = host.presentation_state()
	verify(actual.environment_mode == Environment.BG_COLOR and actual.background_rgba == "e7f0dfff", "host diagnostics reads actual environment mode and opaque scene color")
	verify(not actual.viewport_transparent, "host readiness enforces opaque viewport")
	host.queue_free(); page.queue_free(); router.queue_free(); plugin.queue_free()
	await process_frame
	print("DYNAMIC MAP OCCLUSION ", checks - failures, "/", checks)
	quit(1 if failures else 0)
