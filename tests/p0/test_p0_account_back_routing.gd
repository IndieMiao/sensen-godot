extends GdUnitTestSuite
## Regression: QA93 Claim loaded a farm behind AccRenew; hardware Back navigated that farm to the map.
## Drive the real Router notification/handle_back -> runtime -> real AccFlow, not only flow.back().
const Router := preload("res://modules/ui/app_router.gd")
const Identity := preload("res://modules/p0/p0_identity.gd")
const Farm := preload("res://scenes/p0/p0_farm.gd")
const RECORD := "user://test_account_back_record.json"
const STORE := "user://test_account_back_quick.json"
const ID_DIR := "user://test_account_back_identity/"

class RouterProbe extends Router:
	var homes := 0
	var maps := 0
	var pops := 0
	var transitions_closed := 0
	func _leave_app() -> void: homes += 1
	func go_to_map() -> void: maps += 1
	func pop_instance() -> void: pops += 1
	func _clear_transition() -> void: transitions_closed += 1

class FarmProbe extends Farm:
	# Preserve the actual farm's Back method; skip 3D art/network startup in this routing regression.
	func _init() -> void:
		var camera := Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
		var floor_mesh := MeshInstance3D.new()
		floor_mesh.name = "Ground"
		add_child(floor_mesh)
		var environment := WorldEnvironment.new()
		environment.name = "WorldEnvironment"
		add_child(environment)
	func _ready() -> void: pass
	func _process(_dt: float) -> void: pass
	func _exit_tree() -> void: pass

class SceneProbe extends Node:
	var back_calls := 0
	func is_back_navigation_locked() -> bool:
		back_calls += 1
		return false

class LoadingProbe extends CanvasLayer:
	var close_button := Button.new()
	func _init() -> void: add_child(close_button)

var rt: P0Runtime
var router: RouterProbe
var farm: FarmProbe
var old_scene: Node
var old_handler: Callable
var old_force: Array
var old_env := ""
var swaps := 0
var requests: Array = []
var replies: Array[Callable] = []
var silent_server: TCPServer
var silent_peer: StreamPeerTCP

func before_test() -> void:
	old_scene = get_tree().current_scene
	old_handler = AppRouter.foreground_back_action
	old_force = P0SignIn.force.duplicate()
	old_env = OS.get_environment("P0_ACCOUNTS")
	OS.set_environment("P0_ACCOUNTS", "1")
	P0SignIn.force = ["google"]
	swaps = 0
	requests = []
	replies = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ID_DIR))
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.identity = Identity.new(ID_DIR)
	rt.session.transport = func(_m, path, _body, _done): requests.append(path)
	add_child(rt)
	# Replace the identity's network in this UNIT fixture before its deferred hello, not in production/QA93.
	rt.session.identity.send = func(_m, path, _body, _done): requests.append(path)
	await get_tree().process_frame
	rt.set_process(false)
	rt.session.set_process(false)
	rt.session.identity.terms_version = "2026-11-13"
	rt.session.identity.privacy_version = "2026-11-13"
	rt.swap_root = func(): swaps += 1
	router = auto_free(RouterProbe.new())
	add_child(router)
	# Use the callback actually registered by this runtime's _enter_tree.
	router.foreground_back_action = AppRouter.foreground_back_action
	farm = FarmProbe.new()
	farm.rt = rt
	get_tree().root.add_child(farm)
	get_tree().current_scene = farm
	rt.ui.hide_screen()
	requests.clear()

func after_test() -> void:
	if silent_peer != null:
		silent_peer.disconnect_from_host()
		silent_peer = null
	if silent_server != null:
		silent_server.stop()
		silent_server = null
	get_tree().current_scene = old_scene
	farm.free()
	router._stack.clear()
	router._loading = null
	rt._close_acc_flow()
	rt.free()
	await get_tree().process_frame
	AppRouter.foreground_back_action = old_handler
	P0SignIn.force = old_force
	OS.set_environment("P0_ACCOUNTS", old_env)
	for path in [RECORD, STORE]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var dir := DirAccess.open(ID_DIR)
	if dir:
		for file in dir.get_files(): dir.remove(file)

func _open(kind := "old_signin") -> P0AccFlow:
	rt.session.identity.kind = kind
	rt.session.first_run_needed.emit(kind)
	var flow: P0AccFlow = rt._acc_flow
	flow.record_path = RECORD
	flow.size = Vector2(360, 800)
	return flow

func _renew(flow: P0AccFlow) -> void:
	flow.consent_outdated({"terms_version": "2099-11-14", "privacy_version": "2099-11-14"})

func _no_background_action() -> void:
	assert_int(swaps).is_equal(0)
	assert_int(router.maps).is_equal(0)
	assert_int(router.pops).is_equal(0)
	assert_int(router.homes).is_equal(0)

func _hold_requests() -> void:
	rt.session.identity.send = func(_method, path, _body, done: Callable):
		requests.append(path)
		replies.append(done)

func test_android_notification_with_real_card_does_not_call_the_farms_back() -> void:
	# QA93 reproduced both Claim's Keep your farm and Login's Sign in to play (Back-only).
	for kind in ["old_signin", "new"]:
		var flow := _open(kind)
		flow._open_sign_in()
		_renew(flow)
		var card := flow.renew
		router._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		_no_background_action()
		assert_object(flow.renew).is_same(card)
		assert_object(get_tree().current_scene).is_same(farm)
		assert_array(requests).is_empty()
		assert_dict(flow.kept()).is_empty()   # Back is not consent, never writes age/versions.

func test_card_blocks_stack_pop_and_pending_transition_close_too() -> void:
	var flow := _open()
	_renew(flow)
	var below: SceneProbe = auto_free(SceneProbe.new())
	router._stack.append(below)
	router.handle_back()
	_no_background_action()
	assert_int(below.back_calls).is_equal(0)
	var loading: LoadingProbe = auto_free(LoadingProbe.new())
	add_child(loading)
	loading.close_button.visible = true
	router._loading = loading
	router._navigation_pending = true
	router.handle_back()
	assert_int(router.transitions_closed).is_equal(0)
	assert_bool(router._navigation_pending).is_true()
	assert_object(flow.renew).is_not_null()

func test_card_does_not_depend_on_a_background_world_being_ready() -> void:
	var flow := _open()
	_renew(flow)
	for path in ["res://scenes/p0/p0_map.tscn", "res://scenes/p0/p0_boot.tscn"]:
		var background: SceneProbe = auto_free(SceneProbe.new())
		background.scene_file_path = path
		get_tree().root.add_child(background)
		get_tree().current_scene = background
		router.handle_back()
		_no_background_action()
		assert_object(flow.renew).is_not_null()
		assert_int(background.back_calls).is_equal(0)

func test_card_stays_for_unchecked_pending_and_failed_retry_states() -> void:
	var flow := _open()
	_renew(flow)
	var card := flow.renew
	for phase in [CommandLifecycle.State.IDLE, CommandLifecycle.State.PENDING]:
		card.go.phase = phase
		router.handle_back()
		assert_object(flow.renew).is_same(card)
	flow.consent_settled(false)
	router.handle_back()
	_no_background_action()
	assert_object(flow.renew).is_same(card)
	assert_array(requests).is_empty()

func test_new_name_returns_to_sign_in_and_drops_pending_without_world_back() -> void:
	var flow := _open("new")
	flow.no_farm(true)
	flow.name_page.prefill("Mira")
	rt.session.identity.pending = "unit-pending"
	router.handle_back()
	_no_background_action()
	assert_object(flow.page).is_same(flow.sign_in_page)
	assert_object(flow.name_page).is_null()
	assert_str(rt.session.identity.pending).is_empty()

func test_name_check_in_flight_consumes_back_without_dropping_input() -> void:
	var flow := _open("new")
	flow.no_farm(true)
	flow.name_page.prefill("Mira")
	flow.name_page._checking = true
	rt.session.identity.pending = "unit-pending"
	router.handle_back()
	_no_background_action()
	assert_object(flow.page).is_same(flow.name_page)
	assert_str(flow.name_page.field.text).is_equal("Mira")
	assert_str(rt.session.identity.pending).is_equal("unit-pending")

func test_age_confirmation_back_changes_the_year_instead_of_leaving() -> void:
	var flow := _open("new")
	var age := flow.page as P0AccAge
	age.wheel.animate = false
	age.wheel.pick(2000)
	age.consent.checked = true
	age.consent.toggled.emit(true)
	age._on_go()
	assert_object(age.confirm).is_not_null()
	router.handle_back()
	_no_background_action()
	assert_object(age.confirm).is_null()
	assert_object(flow.page).is_same(age)
	assert_dict(flow.kept()).is_empty()

func test_conflict_back_takes_try_another_account_without_navigation() -> void:
	var flow := _open()
	rt.session.identity.pending = "unit-pending"
	flow.conflict({"name": "Mira", "home_level": 1, "last_played_at": 0}, "google")
	router.handle_back()
	_no_background_action()
	assert_object(flow.choose).is_null()
	assert_object(flow.page).is_same(flow.sign_in_page)
	assert_str(rt.session.identity.pending).is_empty()
	flow.no_farm(true)
	flow.name_page.prefill("Mira")
	rt.session.identity.pending = "unit-race-pending"
	flow.conflict({"name": "Mira", "home_level": 1, "last_played_at": 0}, "google")
	router.handle_back()
	_no_background_action()
	assert_object(flow.choose).is_null()
	assert_object(flow.name_page).is_null()
	assert_object(flow.page).is_same(flow.sign_in_page)
	assert_str(rt.session.identity.pending).is_empty()

func test_known_root_pages_leave_to_android_home_never_the_world() -> void:
	for kind in ["new", "old_signin", "no_google"]:
		_open(kind)
		var count := router.homes
		router.handle_back()
		assert_int(router.homes).is_equal(count + 1)
		assert_int(swaps).is_equal(0)
		assert_int(router.maps).is_equal(0)
		assert_object(rt._acc_flow).is_not_null()

func test_blocked_age_old_consent_and_claimed_name_have_no_hidden_back_exit() -> void:
	for kind in ["blocked", "old_blocked", "old_consent"]:
		var flow := _open(kind)
		var page := flow.page
		router.handle_back()
		_no_background_action()
		assert_object(flow.page).is_same(page)
	var old := _open()
	old.no_farm(false)
	var name_page := old.name_page
	router.handle_back()
	_no_background_action()
	assert_object(old.page).is_same(name_page)
	assert_array(requests).is_empty()

func test_guest_and_skip_http_still_block_after_the_name_check_has_finished() -> void:
	for skip in [false, true]:
		var flow := _open("new")
		flow.no_farm(true)
		flow.name_page.prefill("Mira")
		rt.session.identity.pending = "unit-pending"
		_hold_requests()
		requests.clear()
		replies.clear()
		rt._on_acc_named("Mira", skip)
		assert_bool(flow.name_page._checking).is_false()   # the gap that a _checking-only guard misses
		assert_int(rt._acc_requests).is_equal(1)
		router.handle_back()
		_no_background_action()
		assert_object(flow.page).is_same(flow.name_page)
		assert_str(rt.session.identity.pending).is_equal("unit-pending")
		assert_array(requests).is_equal(["/p0/session/guest"])
		replies[0].call({"ok": false, "code": "network"})
		assert_int(rt._acc_requests).is_equal(0)
		router.handle_back()
		assert_object(flow.page).is_same(flow.sign_in_page)   # failure restores its usual Try another Back

func test_sign_in_and_claim_http_block_home_until_their_error_answer() -> void:
	for kind in ["new", "old_signin"]:
		var flow := _open(kind)
		flow._open_sign_in()
		flow.sign_in_page.busy = true
		_hold_requests()
		replies.clear()
		requests.clear()
		rt.native_sign_in = func(_provider): return {"result": "ok", "id_token": "unit-token", "nonce": "unit-nonce"}
		await rt._on_acc_sign_in("google")
		assert_bool(rt._signing).is_false()   # native sheet is done, HTTP isn't
		var homes := router.homes
		router.handle_back()
		assert_int(router.homes).is_equal(homes)
		assert_int(rt._acc_requests).is_equal(1)
		assert_int(swaps).is_equal(0)
		replies[0].call({"ok": false, "code": "network"})
		assert_int(rt._acc_requests).is_equal(0)
		assert_bool(flow.sign_in_page.busy).is_false()
		router.handle_back()
		assert_int(router.homes).is_equal(homes + 1)

func test_switch_http_is_guarded_even_after_choose_has_closed() -> void:
	var flow := _open()
	flow.conflict({"name": "Mira", "home_level": 1}, "google")
	rt.session.identity.pending = "unit-pending"
	_hold_requests()
	flow.choose.emit_signal("move_pressed")
	assert_object(flow.choose).is_null()
	assert_int(rt._acc_requests).is_equal(1)
	router.handle_back()
	_no_background_action()
	assert_array(requests).is_equal(["/p0/session/pending"])
	replies[0].call({"ok": false, "code": "network"})
	assert_int(rt._acc_requests).is_equal(0)
	router.handle_back()
	assert_int(router.homes).is_equal(1)

func test_rename_http_and_native_sheet_are_both_guards_and_release_on_answer() -> void:
	var flow := _open()
	rt._signing = true
	router.handle_back()
	_no_background_action()
	rt._signing = false
	flow.no_farm(false)
	rt._naming = "rename"
	_hold_requests()
	rt._on_acc_named("Mira", false)
	assert_int(rt._acc_requests).is_equal(1)
	router.handle_back()
	_no_background_action()
	assert_array(requests).is_equal(["/p0/account/name"])
	replies[0].call({"ok": false, "code": "network"})
	assert_int(rt._acc_requests).is_equal(0)
	assert_object(flow.page).is_same(flow.name_page)

func test_a_late_old_flow_reply_cannot_unlock_a_new_flow_request() -> void:
	_open()
	var old_calls := []
	var old_reply := rt._acc_reply(func(_r): old_calls.append(true))
	_open()
	var new_reply := rt._acc_reply(func(_r): pass)
	old_reply.call({"ok": false, "code": "network"})
	assert_array(old_calls).is_empty()   # retired UI callbacks cannot alter the new flow either
	assert_int(rt._acc_requests).is_equal(1)
	new_reply.call({"ok": false, "code": "network"})
	assert_int(rt._acc_requests).is_equal(0)

func test_success_releases_host_wait_and_keeps_back_on_the_resulting_account_page() -> void:
	var flow := _open("new")
	flow._open_sign_in()
	_hold_requests()
	rt.native_sign_in = func(_provider): return {"result": "ok", "id_token": "unit-token", "nonce": "unit-nonce"}
	await rt._on_acc_sign_in("google")
	replies[0].call({"ok": false, "code": "no_farm", "pending": "unit-pending"})
	assert_int(rt._acc_requests).is_equal(0)
	assert_object(flow.page).is_same(flow.name_page)
	router.handle_back()
	_no_background_action()
	assert_object(flow.page).is_same(flow.sign_in_page)
	assert_str(rt.session.identity.pending).is_empty()

func test_real_http_timeout_releases_back_after_the_native_sheet_has_finished() -> void:
	# One ephemeral loopback socket in this test process, no game server or synthetic HTTP answer.
	silent_server = TCPServer.new()
	assert_int(silent_server.listen(0, "127.0.0.1")).is_equal(OK)
	var port := silent_server.get_local_port()
	assert_bool(port > 0).is_true()
	var flow := _open("old_signin")
	flow.sign_in_page.busy = true
	rt.session.base_url = "http://127.0.0.1:%d" % port
	rt.session.identity.send = rt.session._account_request
	rt.native_sign_in = func(_provider): return {"result": "ok", "id_token": "unit-token", "nonce": "unit-nonce"}
	await rt._on_acc_sign_in("google")
	var results: Array = []
	var request: P0HttpRequest
	for node in rt.session.get_children():
		if node is P0HttpRequest: request = node
	assert_object(request).is_not_null()
	assert_float(request.wait_s).is_equal(8.0)
	request.request_completed.connect(func(result, _code, _headers, _body): results.append(result))
	var start := Time.get_ticks_msec()
	while not silent_server.is_connection_available() and Time.get_ticks_msec() - start < 2000:
		await get_tree().process_frame
	assert_bool(silent_server.is_connection_available()).is_true()
	silent_peer = silent_server.take_connection()
	router.handle_back()
	_no_background_action()
	assert_int(rt._acc_requests).is_equal(1)
	while results.is_empty() and Time.get_ticks_msec() - start < 15000:
		await get_tree().process_frame
	assert_array(results).is_equal([HTTPRequest.RESULT_TIMEOUT])
	assert_int(rt._acc_requests).is_equal(0)
	assert_bool(flow.sign_in_page.busy).is_false()
	router.handle_back()
	assert_int(router.homes).is_equal(1)
	assert_int(swaps).is_equal(0)
	silent_peer.disconnect_from_host()
	silent_peer = null
	silent_server.stop()
	assert_bool(silent_server.is_listening()).is_false()
	print("ACCOUNT_BACK_REAL_TIMEOUT result=TIMEOUT wait_s=8 released=true loopback_closed=true")

func test_account_system_screens_block_back_even_during_scene_navigation() -> void:
	for kind in [P0SysScreen.Kind.SESSION, P0SysScreen.Kind.DELETED, P0SysScreen.Kind.SUSPENDED,
			P0SysScreen.Kind.MAINT, P0SysScreen.Kind.UPDATE]:
		rt.ui.hide_screen()
		rt.ui.show_screen(kind)
		router._navigation_pending = true
		router.handle_back()
		_no_background_action()
		assert_int(rt.ui.screen_kind()).is_equal(kind)
		assert_bool(router._navigation_pending).is_true()
	_open("old_signin")
	rt.ui.show_screen(P0SysScreen.Kind.UPDATE)
	router.handle_back()
	_no_background_action()   # higher-priority system block, not the idle Sign in's home action

func test_no_account_layer_preserves_the_farms_existing_back_and_stack_pop() -> void:
	router.handle_back()
	assert_int(swaps).is_equal(1)  # Actual P0Farm back method -> runtime.root_back.
	var below: SceneProbe = auto_free(SceneProbe.new())
	router._stack.append(below)
	router.handle_back()
	assert_int(below.back_calls).is_equal(1)
	assert_int(router.pops).is_equal(1)

func test_runtime_unregisters_its_handler_without_clearing_a_new_owner() -> void:
	assert_bool(AppRouter.foreground_back_action == rt._account_back_action).is_true()
	remove_child(rt)
	assert_bool(AppRouter.foreground_back_action.is_valid()).is_false()
	add_child(rt)
	var other := func(): return Router.BACK_IGNORE
	AppRouter.foreground_back_action = other
	remove_child(rt)
	assert_bool(AppRouter.foreground_back_action == other).is_true()
