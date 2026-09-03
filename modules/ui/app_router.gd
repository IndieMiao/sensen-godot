extends Node
## 应用唯一的场景导航入口，也是在 Android 上唯一处理系统返回的节点。

const MAP := "res://scenes/map_poc/map_poc.tscn"
const DRESS := "res://scenes/dressing_room/dressing_room.tscn"
const STRESS := "res://scenes/stress_test/stress_test.tscn"
const FARM := "res://scenes/farm/farm.tscn"
const CITY_SELECT := "res://scenes/city_select/city_select.tscn"

const BACK_IGNORE := 0
const BACK_TO_MAP := 1
const BACK_LEAVE_APP := 2

var _navigation_pending := false
## 实例栈（PRD §3.2 第二层空间）：地图常驻为底，农场/地点/换装房压在上面。
var _stack: Array[Node] = []


func _ready() -> void:
	# 项目设置是主配置；运行时再设一次，避免导出模板或测试环境覆盖它。
	get_tree().quit_on_go_back = false
	var qa_scene := qa_scene_path(OS.get_cmdline_user_args())
	if not qa_scene.is_empty():
		call_deferred("_open_qa_scene", qa_scene)


func go_to_map() -> void:
	_go_to(MAP)


func go_to_dressing() -> void:
	push_instance(DRESS)


func go_to_stress() -> void:
	_go_to(STRESS)


func push_instance(scene_path: String, args := {}) -> Node:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("AppRouter 无法加载实例场景 %s" % scene_path)
		return null
	var inst := packed.instantiate()
	if inst.has_method("setup"):
		inst.call("setup", args)
	_suspend(top_instance() if not _stack.is_empty() else get_tree().current_scene)
	_stack.append(inst)
	get_tree().root.add_child(inst)
	return inst


func pop_instance() -> void:
	if _stack.is_empty():
		go_to_map() # 兼容 --qa-scene=dressing 直接以换装房为当前场景的情况
		return
	var top: Node = _stack.pop_back()
	top.queue_free()
	_resume(top_instance() if not _stack.is_empty() else get_tree().current_scene)


func instance_depth() -> int:
	return _stack.size()


func top_instance() -> Node:
	return _stack.back() if not _stack.is_empty() else null


func _suspend(node: Node) -> void:
	if node and node.has_method("suspend"):
		node.call("suspend")


func _resume(node: Node) -> void:
	if node and node.has_method("resume"):
		node.call("resume")


func handle_back() -> void:
	if not _stack.is_empty():
		pop_instance()
		return
	var current := get_tree().current_scene
	match back_action_for_scene(
			_current_scene_path(), scene_locks_back_navigation(current)):
		BACK_TO_MAP:
			go_to_map()
		BACK_LEAVE_APP:
			_leave_app()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		handle_back()


func _go_to(scene_path: String) -> void:
	if _navigation_pending or _current_scene_path() == scene_path:
		return
	_navigation_pending = true
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("AppRouter 无法打开场景 %s（错误 %d）" % [scene_path, error])
		_navigation_pending = false
	else:
		call_deferred("_finish_navigation")


func _finish_navigation() -> void:
	_navigation_pending = false


func _leave_app() -> void:
	if OS.get_name() == "Android":
		if Engine.has_singleton("GodotMap"):
			var host := Engine.get_singleton("GodotMap")
			if host.has_method("moveTaskToBack"):
				host.moveTaskToBack()
		return
	# 桌面调试仍按窗口应用习惯退出；iOS 不会产生 Android 的系统返回通知。
	get_tree().quit()


func _open_qa_scene(scene_path: String) -> void:
	print("AppRouter: QA scene -> %s" % scene_path)
	_go_to(scene_path)


func _current_scene_path() -> String:
	var current := get_tree().current_scene
	return current.scene_file_path if current else ""


static func qa_scene_path(args: PackedStringArray) -> String:
	for arg in args:
		if not arg.begins_with("--qa-scene="):
			continue
		match arg.trim_prefix("--qa-scene=").to_lower():
			"map":
				return MAP
			"dressing":
				return DRESS
			"stress":
				return STRESS
			"city":
				return CITY_SELECT
			"farm":
				return FARM
	return ""


static func scene_locks_back_navigation(scene: Node) -> bool:
	return (
		scene != null
		and scene.has_method("is_back_navigation_locked")
		and bool(scene.call("is_back_navigation_locked"))
	)


static func back_action_for_scene(scene_path: String, back_locked := false) -> int:
	if back_locked:
		return BACK_IGNORE
	match scene_path:
		DRESS, STRESS, FARM:
			return BACK_TO_MAP
		MAP, CITY_SELECT:
			return BACK_LEAVE_APP
		_:
			return BACK_IGNORE
