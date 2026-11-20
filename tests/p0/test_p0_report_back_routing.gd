extends GdUnitTestSuite
## #1073 integration: actual Router notification -> registered Runtime handler -> report, before a world/stack.
const Fixture := preload("res://tests/p0/test_p0_account_back_routing.gd")
const Identity := preload("res://modules/p0/p0_identity.gd")
const Reply := preload("res://tests/p0/test_p0_report.gd").Reply
const FakeVoice := preload("res://tests/p0/test_p0_voice_room.gd").FakeVoice
const ID_DIR := "user://test_report_router_identity/"
const STORE := "user://test_report_router_quick.json"
var rt: P0Runtime
var router: Fixture.RouterProbe
var farm: Fixture.FarmProbe
var room: P0VoiceRoom
var http: Reply
var old_scene: Node
var old_handler: Callable
var old_env := ""
var swaps := 0

func before_test() -> void:
	old_scene = get_tree().current_scene
	old_handler = AppRouter.foreground_back_action
	old_env = OS.get_environment("P0_ACCOUNTS")
	OS.set_environment("P0_ACCOUNTS", "1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ID_DIR))
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.identity = Identity.new(ID_DIR)
	rt.session.transport = func(_m, _p, _b, _done): pass
	add_child(rt)
	rt.session.identity.send = func(_m, _p, _b, _done): pass
	await get_tree().process_frame
	rt.set_process(false)
	rt.session.set_process(false)
	rt.session.player_id = "report-router-A"
	rt.session.identity_ready = true
	rt.ui.hide_screen()
	rt.swap_root = func(): swaps += 1
	swaps = 0
	router = auto_free(Fixture.RouterProbe.new())
	add_child(router)
	router.foreground_back_action = AppRouter.foreground_back_action
	farm = Fixture.FarmProbe.new()
	farm.rt = rt
	get_tree().root.add_child(farm)
	get_tree().current_scene = farm
	var online: P0Online = auto_free(P0Online.new())
	online.transport = func(_m): pass
	online.outpost = "report-pond"
	online.room = 1
	online.epoch = 1
	online.self_id = 1
	online.members = {1: {"player": "self"}, 4: {"player": "target", "name": "Traveller 53b5"}}
	room = auto_free(P0VoiceRoom.new())
	room.voice = auto_free(FakeVoice.new())
	room.setup(rt.session, online, "pond")
	room.available = true
	http = auto_free(Reply.new())
	room.request = http.request
	rt.ui.set_voice_room(room)

func after_test() -> void:
	get_tree().current_scene = old_scene
	farm.free()
	router._stack.clear()
	router._loading = null
	rt._close_acc_flow()
	rt.free()
	await get_tree().process_frame
	AppRouter.foreground_back_action = old_handler
	OS.set_environment("P0_ACCOUNTS", old_env)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	var dir := DirAccess.open(ID_DIR)
	if dir:
		for file in dir.get_files(): dir.remove(file)

func _open():
	rt.ui.open_people()
	rt.ui._people.report_pressed.emit(4)
	return rt.ui._report_flow.drawer

func _no_world_back() -> void:
	assert_int(swaps).is_equal(0)
	assert_int(router.maps).is_equal(0)
	assert_int(router.pops).is_equal(0)
	assert_int(router.homes).is_equal(0)
	assert_int(router.transitions_closed).is_equal(0)
	assert_object(get_tree().current_scene).is_same(farm)

func test_android_notification_closes_unsubmitted_report_without_background_navigation() -> void:
	var d = _open()
	d.choose("harassment")
	router._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_str(rt.ui.modal_kind).is_empty()
	assert_array(http.calls).is_empty()
	_no_world_back()
	# The next independent Back, after the drawer is gone, retains the real farm's navigation behavior.
	router.handle_back()
	assert_int(swaps).is_equal(1)

func test_pending_consumes_repeated_router_notifications_and_failure_restores_close() -> void:
	var d = _open()
	d.choose("harassment")
	d.submit.activated.emit()
	for i in 3: router._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_no_world_back()
	assert_str(rt.ui.modal_kind).is_equal("report")
	assert_int(http.calls.size()).is_equal(1)
	http.finish("failed")
	assert_str(d.selected).is_equal("harassment")
	router.handle_back()
	assert_str(rt.ui.modal_kind).is_empty()
	_no_world_back()

func test_report_is_a_foreground_gate_even_above_stack_and_pending_navigation() -> void:
	var below: Fixture.SceneProbe = auto_free(Fixture.SceneProbe.new())
	router._stack.append(below)
	var loading: Fixture.LoadingProbe = auto_free(Fixture.LoadingProbe.new())
	add_child(loading)
	loading.close_button.visible = true
	router._loading = loading
	router._navigation_pending = true
	var d = _open()
	d.choose("other")
	d.submit.activated.emit()
	router.handle_back()
	_no_world_back()
	assert_int(below.back_calls).is_equal(0)
	assert_bool(router._navigation_pending).is_true()
	http.finish("failed")
	router.handle_back()
	assert_str(rt.ui.modal_kind).is_empty()
	assert_bool(router._navigation_pending).is_true()
	_no_world_back()

func test_account_and_update_gates_keep_priority_over_an_open_report() -> void:
	_open()
	rt._open_acc_flow("new")
	rt._acc_requests = 1
	router.handle_back()
	assert_str(rt.ui.modal_kind).is_equal("report")   # the higher account layer consumes first
	_no_world_back()
	rt._close_acc_flow()
	rt.ui.show_screen(P0SysScreen.Kind.UPDATE)
	router.handle_back()
	assert_int(rt.ui.screen_kind()).is_equal(P0SysScreen.Kind.UPDATE)
	_no_world_back()

func test_report_does_not_replace_the_runtime_handler_or_add_another_notification_owner() -> void:
	var registered := AppRouter.foreground_back_action
	_open()
	assert_bool(AppRouter.foreground_back_action == registered).is_true()
	router.handle_back()
	assert_bool(AppRouter.foreground_back_action == registered).is_true()
	_no_world_back()
