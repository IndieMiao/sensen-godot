extends Node
## 应用唯一的场景导航入口，也是在 Android 上唯一处理系统返回的节点。

const MAP := "res://scenes/map_poc/map_poc.tscn"
const DRESS := "res://scenes/dressing_room/dressing_room.tscn"
const STRESS := "res://scenes/stress_test/stress_test.tscn"

const BACK_IGNORE := 0
const BACK_TO_MAP := 1
const BACK_LEAVE_APP := 2

var _navigation_pending := false


func _ready() -> void:
	# 项目设置是主配置；运行时再设一次，避免导出模板或测试环境覆盖它。
	get_tree().quit_on_go_back = false
	var qa_scene := qa_scene_path(OS.get_cmdline_user_args())
	if not qa_scene.is_empty():
		call_deferred("_open_qa_scene", qa_scene)


func go_to_map() -> void:
	_go_to(MAP)


func go_to_dressing() -> void:
	_go_to(DRESS)


func go_to_stress() -> void:
	_go_to(STRESS)


func handle_back() -> void:
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
		DRESS, STRESS:
			return BACK_TO_MAP
		MAP:
			return BACK_LEAVE_APP
		_:
			return BACK_IGNORE
