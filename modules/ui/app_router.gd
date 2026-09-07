extends Node
## 应用唯一的场景导航入口，也是在 Android 上唯一处理系统返回的节点。

const MAP := "res://scenes/map_poc/map_poc.tscn"
const DRESS := "res://scenes/dressing_room/dressing_room.tscn"
const STRESS := "res://scenes/stress_test/stress_test.tscn"
const FARM := "res://scenes/farm/farm.tscn"
const PLACE := "res://scenes/place/place.tscn"
const CITY_SELECT := "res://scenes/city_select/city_select.tscn"
## 海外社交主线（08-30 调研 §3.1）：启动决策页 → 登录页 → 四 Tab 壳。路径与 AppRoutes 同源。
const BOOT := "res://scenes/app/boot.tscn"
const AGE_GATE := "res://scenes/app/age_gate_page.tscn"
const CONSENT := "res://scenes/app/consent_page.tscn"
const LOGIN := "res://scenes/app/login_page.tscn"
const SHELL := "res://scenes/app/app_shell.tscn"

const BACK_IGNORE := 0
const BACK_TO_MAP := 1
const BACK_LEAVE_APP := 2

var _navigation_pending := false
## 实例栈（PRD §3.2 第二层空间）：地图常驻为底，农场/地点/换装房压在上面。
var _stack: Array[Node] = []


const NetScript := preload("res://modules/net/net_service.gd")


func _ready() -> void:
	# 项目设置是主配置；运行时再设一次，避免导出模板或测试环境覆盖它。
	get_tree().quit_on_go_back = false
	# 语言：读玩家选择或系统语言。测试进程固定 en——引擎启动会按系统语言选 locale，
	# 中文开发机上注册了 zh_CN 翻译后，所有英文断言都会变成中文而失败。
	if NetScript.is_test_process():
		TranslationServer.set_locale("en")
	else:
		AppLocale.boot_apply()
	var qa_scene := qa_scene_path(OS.get_cmdline_user_args())
	if not qa_scene.is_empty():
		call_deferred("_open_qa_scene", qa_scene)
	# QA 流程步行器（模拟器 / 真机无人值守）：非测试进程且明确要求时才挂。
	var flow := QaFlow.requested(OS.get_cmdline_user_args(), OS.get_environment("SENSEN_QA_FLOW"))
	if not flow.is_empty() and not NetScript.is_test_process():
		var walker := QaFlow.new()
		walker.name = "QaFlow"
		walker.flow = flow
		add_child(walker)


func go_to_map() -> void:
	_go_to(MAP)


func go_to_dressing() -> void:
	push_instance(DRESS)


func go_to_stress() -> void:
	_go_to(STRESS)


## 整场景切换前清空实例栈：登出时若还有设置页压在壳上，change_scene 只换 current_scene，
## 压栈的子页会继续挂在 root 下盖住登录页。
func go_to_login() -> void:
	_clear_stack()
	_go_to(LOGIN)


func go_to_shell() -> void:
	_clear_stack()
	_go_to(SHELL)


## 按路径跳整场景（boot / 首启合规流用）。
func go_to_route(scene_path: String) -> void:
	_clear_stack()
	_go_to(scene_path)


## 语言切换等需要整壳重建的场景：清栈后重载当前场景（_go_to 对同路径是 no-op）。
func reload_shell() -> void:
	_clear_stack()
	if _current_scene_path() == SHELL:
		get_tree().reload_current_scene()
	else:
		_go_to(SHELL)


func _clear_stack() -> void:
	while not _stack.is_empty():
		var top: Node = _stack.pop_back()
		var parent := top.get_parent()
		if parent:
			parent.remove_child(top)
		top.queue_free()


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
	# 先解除父子关系再 queue_free：queue_free 要等到本帧末才真正生效，
	# 不 remove_child 的话，弹出的场景在这一整帧里仍然挂在 root 下——仍可见、
	# 仍在 _process，HUD 仍在画，跟刚 resume 的下层场景同屏叠一帧。
	# Task 7/8 都单独修过这个坑（CandidateOverlay、SelectPanel 的 queue_free 时序），
	# 唯独 AppRouter 自己这处一直没补——I3（2026-09-04 终审）。
	var parent := top.get_parent()
	if parent:
		parent.remove_child(top)
	top.queue_free()
	_resume(top_instance() if not _stack.is_empty() else get_tree().current_scene)


func instance_depth() -> int:
	return _stack.size()


func top_instance() -> Node:
	return _stack.back() if not _stack.is_empty() else null


## 协议（2026-09-04 终审 C1 补上）：被压栈之下的场景实现 suspend()/resume() 时，
## 如果自己拥有 Camera3D / WorldEnvironment，必须在这两个方法里交出/收回相机与环境的
## 所有权——隐藏节点（visible=false、process_mode 关掉）并不会让 Godot 4 释放相机的
## "当前"身份，一台 Camera3D 只有 current==true 或者是视口里第一台相机时才会被选中；
## WorldEnvironment 同理，视口只认树里第一个生效的 Environment。没有这一步，压栈场景会
## 看见下层场景冻结的相机位姿和天空/环境光（参见 map_poc.gd::suspend()/resume() 的实现，
## tests/fixtures/scenes/stack_probe.gd 是复现这条协议的最小样例）。
## 故意不为此单独开 release_view()/acquire_view() 一对新方法：suspend()/resume() 已经是
## AppRouter 唯一的、经过测试的分发点，且 map_poc.gd 里这两个方法本来就在管一揽子"离场/
## 回场"副作用（HUD、地图桥可见性、transparent_bg）——相机与环境所有权是这份清单上很自然
## 的下一项，而不是一个概念上独立的生命周期。新增一对方法只会让"忘记实现另一半"这个正是
## 本次事故成因的失误多一个复现的地方；折叠进已有协议把这个面收窄到一个方法对。
## 新压入的场景（例如 farm.gd / dressing_room.gd）不走这条路径：它们是第一次进入树，
## 没有"之前的状态"要收回，直接在各自 _ready() 里 make_current() 即可（见 C1 fix 项 3）。
func _suspend(node: Node) -> void:
	if node and node.has_method("suspend"):
		node.call("suspend")


func _resume(node: Node) -> void:
	if node and node.has_method("resume"):
		node.call("resume")


func handle_back() -> void:
	if not _stack.is_empty():
		# 栈顶也要尊重返回锁：换装房保存中（_committing）被系统返回键弹栈会中断保存。
		# 与下方 current_scene 分支同一语义（2026-09-04 执行时补上，原计划漏了这一层）。
		if scene_locks_back_navigation(top_instance()):
			return
		pop_instance()
		return
	var current := get_tree().current_scene
	# 壳自己有 Tab 级返回语义（非首页 Tab → 回地图 Tab）；消费掉就不再往下走。
	if current and current.has_method("handle_back") and bool(current.call("handle_back")):
		return
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
			"login":
				return LOGIN
			"agegate", "age_gate":
				return AGE_GATE
			"consent":
				return CONSENT
			"shell", "home":
				return SHELL
			"week":
				var driver := "res://tools/dev/g3_week_ui.tscn"
				if OS.is_debug_build() and OS.has_feature("g3_device_qa") and ResourceLoader.exists(driver):
					return driver
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
		DRESS, STRESS, FARM, PLACE:
			return BACK_TO_MAP
		MAP, CITY_SELECT, BOOT, AGE_GATE, CONSENT, LOGIN, SHELL:
			return BACK_LEAVE_APP
		_:
			return BACK_IGNORE
