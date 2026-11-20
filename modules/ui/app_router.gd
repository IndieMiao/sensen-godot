extends Node
## 应用唯一的场景导航入口，也是在 Android 上唯一处理系统返回的节点。

const MAP := "res://scenes/map_poc/map_poc.tscn"
const DRESS := "res://scenes/dressing_room/dressing_room.tscn"
const STRESS := "res://scenes/stress_test/stress_test.tscn"
const FARM := "res://scenes/farm/farm.tscn"
const MINE := "res://scenes/mine/mine.tscn"
const ONLINE_MINE := "res://scenes/mine/online_mine.tscn"
const PLACE := "res://scenes/place/place.tscn"
const STREET := "res://scenes/map/journey_street.tscn"
const CITY_SELECT := "res://scenes/city_select/city_select.tscn"
const P0_MAP := "res://scenes/p0/p0_map.tscn"   # P0 prototype map (feat/p0-core)

const BACK_IGNORE := 0
const BACK_TO_MAP := 1
const BACK_LEAVE_APP := 2
const BACK_PASS := -1

## A full-screen flow can own Back even while a world loads or is already behind it. Its host registers one
## synchronous action: BACK_IGNORE (consumed), BACK_LEAVE_APP (home), or BACK_PASS (normal scene routing).
## Ask before navigation/stack locks: a CanvasLayer's mouse_filter does not intercept Android's notification.
var foreground_back_action := Callable()

var _navigation_pending := false
var _loading: CanvasLayer
## A host's own loading layer for open_instance (P0: SYS-LOADING-SCENE, SGODOT-233): factory(scene_path, args)
## returns a CanvasLayer with failed() and close_button like loading_overlay.gd, or null to keep that overlay.
var loading_overlay_factory := Callable()
## A scene's threaded load: given up after this long, and tried this many times when it fails (not when it is slow).
const LOAD_TIMEOUT_MS := 30000
const LOAD_TRIES := 2
## _load_with_feedback loads on the main thread rather than threaded: under the Compatibility renderer (0.3.3 h1).
var sync_loads := RenderingServer.get_current_rendering_method() == "gl_compatibility"
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

func go_to_city_select() -> void:
	_go_to(CITY_SELECT)

## Old goal IDs still say street, but all playable surface routes now use the farm.
func _farm_destination_args(args: Dictionary) -> Dictionary:
	var result := args.duplicate()
	if not result.get("visitor_snapshot", {}).is_empty():
		result.visitor = true
		result.snapshot = result.visitor_snapshot
		result.erase("visitor_snapshot")
	return result

func _reuse_farm(args: Dictionary) -> bool:
	var current := top_instance()
	if current == null or current.scene_file_path != FARM or bool(args.get("visitor", false)): return false
	if bool(current.get("visitor")) or current.get("session") != args.get("session", Net.session): return false
	if current.has_method("focus_destination"): current.call("focus_destination", args)
	return true

## Resume the owner's existing farm below a place/bag scene, preserving camera and position.
func return_to_farm(session: FarmSession) -> void:
	while instance_depth() > 0:
		var current := top_instance()
		if current.scene_file_path == FARM and not bool(current.get("visitor")) and current.get("session") == session: return
		pop_instance()

func _discard_top() -> void:
	if _stack.is_empty(): return
	var node: Node = _stack.pop_back()
	_suspend(node)
	if node.get_parent(): node.get_parent().remove_child(node)
	node.queue_free()

## Whether replace_top_instance would take `source` now: on top, no other way in or out under way.
func can_replace(source: Node) -> bool: return not _navigation_pending and source == top_instance()

## The top world opened again in place, behind the loading cover — the farmhouse moving to its next room after an
## upgrade made inside it (SGODOT-282) — the world below staying suspended under it.
func replace_top_instance(source: Node, scene_path: String, args := {}) -> void:
	if not can_replace(source): return
	var packed := await _load_with_feedback(scene_path, args)
	if packed == null: return
	if not is_instance_valid(source) or source != top_instance():
		_clear_transition()
		return
	_discard_top()
	_push_packed(packed, args, false)
	await _end_transition()


func go_to_dressing() -> void:
	open_instance(DRESS)


func go_to_stress() -> void:
	_go_to(STRESS)

func mine_scene() -> String:
	return ONLINE_MINE if Net.online_available else MINE


func push_instance(scene_path: String, args := {}) -> Node:
	if scene_path == STREET:
		scene_path = FARM
		args = _farm_destination_args(args)
	if scene_path == FARM and _reuse_farm(args): return top_instance()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("AppRouter 无法加载实例场景 %s" % scene_path)
		return null
	return _push_packed(packed, args)


## A scene already loaded (a threaded preload, the home pick's map: 亚瑟 342 6418183a) pushed as push_instance does;
## null while a navigation is under way.
func push_packed(packed: PackedScene, args := {}) -> Node:
	if _navigation_pending or packed == null: return null
	return _push_packed(packed, args)


func _push_packed(packed: PackedScene, args: Dictionary, suspend_previous := true) -> Node:
	var inst := packed.instantiate()
	if inst.has_method("setup"):
		inst.call("setup", args)
	if suspend_previous: _suspend(top_instance() if not _stack.is_empty() else get_tree().current_scene)
	_stack.append(inst)
	get_tree().root.add_child(inst)
	return inst

func open_party_destination(manifest: Dictionary, session: FarmSession, source: Node) -> void:
	if _navigation_pending: return
	var path := PartyTravel.scene_path(manifest)
	var args := PartyTravel.scene_args(manifest, session)
	if path.is_empty() or args.is_empty(): return
	var packed := await _load_with_feedback(path)
	if packed == null: return
	if not is_instance_valid(source) or source != top_instance():
		_clear_transition()
		return
	# Discard prior visits/mines, keeping the suspended home scene as the return destination.
	var replace := source.has_meta("party_travel") or source.scene_file_path in [MINE, ONLINE_MINE]
	if replace:
		_stack.pop_back()
		_suspend(source)
		get_tree().root.remove_child(source)
		source.queue_free()
	var destination := _push_packed(packed, args, not replace)
	destination.set_meta("party_travel", true)
	await _end_transition()


func open_instance(scene_path: String, args := {}) -> void:
	if _navigation_pending: return
	if scene_path == STREET:
		scene_path = FARM
		args = _farm_destination_args(args)
	if scene_path == FARM and _reuse_farm(args): return
	var packed := await _load_with_feedback(scene_path, args)
	if packed == null: return
	_push_packed(packed, args)
	await _end_transition()


func _load_with_feedback(scene_path: String, args := {}) -> PackedScene:
	_navigation_pending = true
	_loading = loading_overlay_factory.call(scene_path, args) if loading_overlay_factory.is_valid() else null
	if _loading == null: _loading = preload("res://modules/ui/loading_overlay.gd").new()
	add_child(_loading)
	await _render_frame()
	# Compatibility (OpenGL ES: a phone or emulator without Vulkan): there 0.3.3's threaded loads never finished — every
	# place opened from the map or a door gave up after LOAD_TIMEOUT_MS, while push_instance's load opened the same
	# scenes at once (李元芳 on gs66, 11-09). Loaded on this thread instead, under the overlay already drawn.
	if sync_loads:
		var packed := load(scene_path) as PackedScene
		if packed != null:
			if _loading.has_method(&"progress"): _loading.call(&"progress", 1.0)
			return packed
		push_warning("AppRouter: loading %s failed" % scene_path)
		_loading.failed()
		_loading.close_button.pressed.connect(_clear_transition, CONNECT_ONE_SHOT)
		return null
	var started := Time.get_ticks_msec()
	# A load that failed stays in ResourceLoader until load_threaded_get takes it: left there, every later request of the
	# path fails at once (李元芳 on 0.3.0's farmhouse, 11-06: once, then again 3 s after Go back, until the app restarted).
	# So a failed one is taken, and asked once more before the place counts as not opening. One still loading after
	# LOAD_TIMEOUT_MS is left to finish (a get would block until it does).
	for attempt in LOAD_TRIES:
		if ResourceLoader.load_threaded_request(scene_path, "PackedScene") != OK: break
		var done := []   # the threaded load's own progress, for an overlay with a bar (P0LoadingLayer.progress)
		while ResourceLoader.load_threaded_get_status(scene_path, done) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if _loading.has_method(&"progress") and not done.is_empty(): _loading.call(&"progress", float(done[0]))
			if Time.get_ticks_msec() - started > LOAD_TIMEOUT_MS: break
			await get_tree().process_frame
		var status := ResourceLoader.load_threaded_get_status(scene_path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			if _loading.has_method(&"progress"): _loading.call(&"progress", 1.0)
			return ResourceLoader.load_threaded_get(scene_path) as PackedScene
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: break
		# The failed load, taken: once for each request still on it — an earlier try left at the time limit holds one too
		# (周瑜 on #805: two requests need two takes) — so the next request starts afresh.
		for take in 8:
			if ResourceLoader.load_threaded_get_status(scene_path) != ResourceLoader.THREAD_LOAD_FAILED: break
			ResourceLoader.load_threaded_get(scene_path)
		push_warning("AppRouter: loading %s failed (try %d of %d)" % [scene_path, attempt + 1, LOAD_TRIES])
	_loading.failed()
	_loading.close_button.pressed.connect(_clear_transition, CONNECT_ONE_SHOT)
	return null


func _render_frame() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw


func _end_transition() -> void:
	await _render_frame()
	await get_tree().create_timer(0.12).timeout
	_clear_transition()


func _clear_transition() -> void:
	# An overlay with finish() (P0LoadingLayer) fills its bar and fades itself out, taking no touch meanwhile; any
	# other goes at once. Either way the navigation is over now.
	if is_instance_valid(_loading) and _loading.has_method(&"finish") and not _loading.close_button.visible:
		_loading.call(&"finish")
	elif is_instance_valid(_loading):
		remove_child(_loading)
		_loading.queue_free()
	_loading = null
	_navigation_pending = false


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
	if foreground_back_action.is_valid():
		var action := int(foreground_back_action.call())
		if action != BACK_PASS:
			if action == BACK_LEAVE_APP: _leave_app()
			return
	if _navigation_pending:
		if _loading and _loading.close_button.visible: _clear_transition()
		return
	if not _stack.is_empty():
		# 栈顶也要尊重返回锁：换装房保存中（_committing）被系统返回键弹栈会中断保存。
		# 与下方 current_scene 分支同一语义（2026-09-04 执行时补上，原计划漏了这一层）。
		if scene_locks_back_navigation(top_instance()):
			return
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
	var packed := await _load_with_feedback(scene_path)
	if packed == null: return
	var error := get_tree().change_scene_to_packed(packed)
	if error != OK:
		push_error("AppRouter 无法打开场景 %s（错误 %d）" % [scene_path, error])
		_clear_transition()
	else:
		await get_tree().scene_changed
		await _end_transition()


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
			"mine":
				return MINE
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
		DRESS, STRESS, FARM, PLACE, MINE, LandmarkScenes.GRIFFITH, LandmarkScenes.ALCATRAZ:
			return BACK_TO_MAP
		MAP, CITY_SELECT, P0_MAP:
			return BACK_LEAVE_APP
		_:
			return BACK_IGNORE
