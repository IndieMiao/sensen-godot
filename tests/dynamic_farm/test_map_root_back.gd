extends SceneTree
const Android := preload("res://scenes/map_poc/map_bridge_android.gd")
class JavaWrapper extends Node:
	var supported := true
	var queries: Array = []
	var calls := 0
	func has_java_method(method: String) -> bool:
		queries.append(method)
		return supported and method == "moveTaskToBack"
	func moveTaskToBack() -> void: calls += 1
class Selector extends Node:
	var pauses := 0
	func pause() -> void: pauses += 1
class Preview extends "res://scenes/dynamic_farm/dynamic_farm_map.gd":
	var quits := 0
	var resumes := 0
	func _ready() -> void:
		_hud = Control.new(); add_child(_hud)
		_selector = Selector.new(); add_child(_selector)
	func _quit_preview() -> void: quits += 1
	func resume() -> void:
		resumes += 1; _suspended = false; process_mode = Node.PROCESS_MODE_INHERIT
class Router extends Node:
	var top: Node
	var pops := 0
	func top_instance() -> Node: return top
	func pop_instance() -> void: pops += 1; top = null
var checked := 0
var failed := 0
func _initialize() -> void: _run.call_deferred()
func verify(value: bool, label: String) -> void:
	checked += 1
	if not value: failed += 1
	print("PASS " if value else "FAIL ", label)
func _run() -> void:
	var wrapper := JavaWrapper.new(); root.add_child(wrapper)
	var bridge := Android.new(); bridge._plugin = wrapper
	var router := Router.new(); router.name = "AppRouter"; root.add_child(router)
	var page := Preview.new(); root.add_child(page); page._bridge = bridge
	page.is_back_navigation_locked(); page.is_back_navigation_locked(); await process_frame
	verify(wrapper.queries.count("moveTaskToBack") == 1, "root Back consults Java-wrapper capability once")
	verify(wrapper.calls == 1 and router.pops == 0 and page.quits == 0, "root Back dispatches native background exactly once")
	verify(page.resumes == 0 and page._suspended and page._selector.pauses == 1, "root Back stays paused instead of reloading map")
	page._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	verify(page.resumes == 1 and not page._suspended, "only foreground lifecycle resumes the root map")
	page.queue_free(); await process_frame
	wrapper.supported = false
	page = Preview.new(); root.add_child(page); page._bridge = bridge
	page._leave(); await process_frame
	verify(wrapper.calls == 1 and page.quits == 1 and page.resumes == 0, "missing Java capability uses exit fallback even if wrapper has a script method")
	page.queue_free(); await process_frame
	page = Preview.new(); root.add_child(page); page._bridge = MapBridge.new()
	page._leave(); await process_frame
	verify(page.quits == 1, "unsupported bridge has explicit root exit fallback")
	page.queue_free(); await process_frame
	page = Preview.new(); root.add_child(page); page._bridge = bridge; router.top = page
	page._leave(); page._leave(); await process_frame
	verify(router.pops == 1 and page.quits == 0 and wrapper.calls == 1, "stacked map returns through Router without backgrounding or exiting")
	page.queue_free(); router.queue_free(); wrapper.queue_free(); await process_frame
	print("DYNAMIC ROOT BACK ", checked - failed, "/", checked)
	quit(1 if failed else 0)
