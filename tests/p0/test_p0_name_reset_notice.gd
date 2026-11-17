extends GdUnitTestSuite
## Real account HTTP, synthetic world/identity and response ordering; no game server or device/provider claim.
const Identity := preload("res://modules/p0/p0_identity.gd")
const Api := preload("res://modules/p0/p0_account_notices.gd")
const Flow := preload("res://scenes/p0/account/p0_name_reset_flow.gd")
const Back := preload("res://tests/p0/test_p0_account_back_routing.gd")
const Lifetime := preload("res://tests/p0/test_p0_account_reply_lifetime.gd")
const DIR := "user://test_name_notice/"
const PENDING := DIR + "pending.json"
var rt: P0Runtime
var flow: Node
var wire: Node
var world: Node
var old_env := ""
var old_force: Array
var old_back: Callable

func before_test() -> void:
	old_env = OS.get_environment("P0_ACCOUNTS")
	old_force = P0SignIn.force.duplicate()
	old_back = AppRouter.foreground_back_action
	OS.set_environment("P0_ACCOUNTS", "1")
	P0SignIn.force = ["google"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	rt = auto_free(P0Runtime.new())
	rt.session.identity = Identity.new(DIR)
	rt.ui.quick_store = DIR + "quick.json"
	rt.ui.tips_path = DIR + "tips.json"
	rt.name_notices.pending_path = PENDING
	add_child(rt)
	rt.session.identity.send = func(_m, _p, _b, _done): pass   # startup hello only; notices use the production HTTP helper
	await get_tree().process_frame
	rt.set_process(false)
	rt.session.set_process(false)
	rt.session.identity.send = rt.session._account_request
	rt.session.transport = func(_m, _p, _b, _cmd): pass
	rt.session.identity.player = "p0-notice-one"
	rt.session.player_id = rt.session.identity.player
	rt.session.identity.token = "ab".repeat(32)
	rt.session.identity_ready = true
	rt.ui.hide_screen()
	rt.ui.set_surface("farm")
	world = auto_free(Node.new())
	add_child(world)
	rt.world = world
	flow = rt.name_notices
	flow.set_process(false)
	wire = auto_free(Lifetime.Loopback.new())
	add_child(wire)
	assert_int(wire.start()).is_equal(OK)
	rt.session.base_url = "http://127.0.0.1:%d" % wire.server.get_local_port()

func after_test() -> void:
	rt.free()
	wire.close()
	assert_bool(wire.server.is_listening()).is_false()
	AppRouter.foreground_back_action = old_back
	P0SignIn.force = old_force
	OS.set_environment("P0_ACCOUNTS", old_env)
	await get_tree().process_frame
	var dir := DirAccess.open(DIR)
	if dir:
		for file in dir.get_files(): dir.remove(file)

func _pump() -> void:
	for i in range(8): await get_tree().process_frame

func _request(path := Api.PATH) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		for row in wire.requests:
			if row.path == path and not row.claimed:
				row.claimed = true
				return row
		await get_tree().process_frame
	assert_bool(false).override_failure_message("Missing HTTP " + path).is_true()
	return {}

func _http() -> P0HttpRequest:
	var last: P0HttpRequest
	for child in flow.api.get_children():
		if child is P0HttpRequest and not child.is_queued_for_deletion(): last = child
	assert_object(last).is_not_null()
	return last

func _answer(row: Dictionary, http: P0HttpRequest, code: int, body: Dictionary) -> void:
	var done := []
	http.request_completed.connect(func(result, status, _h, _b): done.append([result, status]))
	assert_int(wire.respond(row, code, body)).is_equal(OK)
	var deadline := Time.get_ticks_msec() + 3000
	while done.is_empty() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	assert_array(done).contains_exactly([[HTTPRequest.RESULT_SUCCESS, code]])

func _show(version := 1) -> void:
	flow.tick()
	var http := _http()
	await _answer(await _request(), http, 200, {"ok": true, "name_reset": {"version": version}})
	assert_bool(flow.showing()).is_true()

func _ok() -> void: flow.card.get("move").activated.emit()

func _reload() -> void:
	flow.free()
	flow = Flow.new()
	flow.pending_path = PENDING
	flow.setup(rt)
	rt.name_notices = flow
	rt.add_child(flow)
	flow.set_process(false)
	flow.tick()

func test_strict_version_and_unknown_are_not_null() -> void:
	assert_int(Api.unread({"ok": true, "name_reset": null})).is_equal(0)
	for bad in [{}, {"ok": true}, {"ok": 1, "name_reset": null}, {"ok": false, "name_reset": null}]:
		assert_int(Api.unread(bad)).is_equal(-1)
	for bad in [null, true, false, "1", 0, -1, 1.5, 9007199254740992, INF, NAN, {}]:
		assert_int(Api.version(bad)).is_equal(-1)
	for valid in [1, 1.0, 9007199254740991]: assert_int(Api.version(valid)).is_equal(int(valid))

func test_waits_for_ready_world_and_all_account_gates() -> void:
	rt.world = null
	flow.tick()
	await _pump()
	assert_int(wire.requests.size()).is_equal(0)
	rt.world = world
	rt.session.identity_ready = false
	flow.tick()
	await _pump()
	assert_int(wire.requests.size()).is_equal(0)
	rt.session.identity_ready = true
	rt._open_acc_flow("new")
	flow.tick()
	await _pump()
	assert_int(wire.requests.size()).is_equal(0)
	rt._close_acc_flow()
	rt.ui.show_screen(P0SysScreen.Kind.LAUNCH)
	flow.tick()
	await _pump()
	assert_int(wire.requests.size()).is_equal(0)
	rt.ui.hide_screen()
	await _show()

func test_back_and_scrim_never_ack_or_pass_to_world() -> void:
	await _show()
	var router: Node = auto_free(Back.RouterProbe.new())
	add_child(router)
	router.foreground_back_action = rt._account_back_action
	for i in range(3):
		router.handle_back()
		assert_int(router.maps + router.pops + router.homes).is_equal(0)
		assert_int(rt._account_back_action()).is_equal(AppRouter.BACK_IGNORE)
		assert_bool(rt.ui.close_top_layer()).is_true()
		flow.card.emit_signal("cancelled")
		assert_bool(flow.showing()).is_true()
	await _pump()
	assert_int(wire.requests.size()).is_equal(1)
	assert_bool(flow._pending.is_empty()).is_true()
	assert_bool(FileAccess.file_exists(PENDING)).is_false()

func test_ok_closes_immediately_and_write_failure_is_not_a_game_gate() -> void:
	await _show(3)
	var shown: Control = flow.card
	_ok()
	assert_bool(flow.showing()).is_false()
	assert_int(flow._pending[flow._owner]).is_equal(3)
	assert_bool(FileAccess.file_exists(PENDING)).is_true()
	shown.emit_signal("move_pressed")   # duplicate input before queue_free cannot send a second ACK
	var http := _http()
	await _answer(await _request(Api.PATH + "/ack"), http, 500, {"ok": false, "code": "notice_failed"})
	flow.tick()
	assert_bool(flow.showing()).is_false()
	assert_object(rt.ui.screen()).is_null()
	assert_bool(rt.session.identity_ready).is_true()
	assert_str(rt.ui.sys_text()).is_empty()
	assert_int(rt._account_back_action()).is_equal(AppRouter.BACK_PASS)
	assert_int(flow._pending[flow._owner]).is_equal(3)
	assert_int(wire.requests.size()).is_equal(2)

func test_200_only_confirms_its_version_and_does_not_read_as_new_game_state() -> void:
	await _show(2)
	_ok()
	var http := _http()
	await _answer(await _request(Api.PATH + "/ack"), http, 200, {"ok": true})
	assert_bool(flow._pending.has(flow._owner)).is_false()
	assert_bool(rt.session.view.is_empty()).is_true()
	assert_bool(rt.session.identity_ready).is_true()
	assert_bool(flow.showing()).is_false()

func test_next_launch_retries_pending_then_gets_authoritative_new_version() -> void:
	await _show(2)
	_ok()
	await _answer(await _request(Api.PATH + "/ack"), _http(), 500, {"ok": false, "code": "notice_failed"})
	_reload()
	var retry := _http()
	await _answer(await _request(Api.PATH + "/ack"), retry, 200, {"ok": true})
	var get_http := _http()
	await _answer(await _request(), get_http, 200, {"ok": true, "name_reset": {"version": 3}})
	assert_bool(flow.showing()).is_true()
	assert_int(flow._unread).is_equal(3)
	assert_bool(flow._pending.is_empty()).is_true()

func test_retry_failure_still_queries_and_may_show_again_next_launch() -> void:
	await _show(1)
	_ok()
	await _answer(await _request(Api.PATH + "/ack"), _http(), 500, {"ok": false, "code": "notice_failed"})
	_reload()
	await _answer(await _request(Api.PATH + "/ack"), _http(), 500, {"ok": false, "code": "notice_failed"})
	await _answer(await _request(), _http(), 200, {"ok": true, "name_reset": {"version": 1}})
	assert_bool(flow.showing()).is_true()
	assert_int(flow._pending[flow._owner]).is_equal(1)

func test_old_ack_cannot_close_higher_version_or_erase_its_pending() -> void:
	await _show(1)
	_ok()
	var ack_one := _http()
	var old := await _request(Api.PATH + "/ack")
	flow._read()   # explicit later query, old ACK stays on the wire
	await _answer(await _request(), _http(), 200, {"ok": true, "name_reset": {"version": 2}})
	assert_bool(flow.showing()).is_true()
	var newer: Control = flow.card
	await _answer(old, ack_one, 200, {"ok": true})
	assert_object(flow.card).is_same(newer)
	_ok()
	assert_int(flow._pending[flow._owner]).is_equal(2)
	await _answer(await _request(Api.PATH + "/ack"), _http(), 200, {"ok": true})
	assert_bool(flow._pending.is_empty()).is_true()

func test_old_null_and_401_403_are_dropped_before_identity_side_effects() -> void:
	for code in [200, 401, 403]:
		flow._loaded = false
		flow.tick()
		var old_http := _http()
		var old := await _request()
		rt.session._begin_login()
		rt.session.identity._keep("p0-notice-one", "ab".repeat(32), ["code"])   # same text, new login generation
		rt.session.identity_ready = true
		flow.tick()
		await _answer(await _request(), _http(), 200, {"ok": true, "name_reset": {"version": 5}})
		var shown: Control = flow.card
		await _answer(old, old_http, code, {"ok": true, "name_reset": null} if code == 200 else
			{"ok": false, "code": "suspended" if code == 403 else "account_deleted", "until": null})
		assert_bool(rt.session.identity_ready).is_true()
		assert_object(rt.ui.screen()).is_null()
		assert_object(flow.card).is_same(shown)
		assert_int(flow._unread).is_equal(5)

func test_switch_player_does_not_send_old_pending_with_new_token() -> void:
	await _show(1)
	_ok()
	await _answer(await _request(Api.PATH + "/ack"), _http(), 500, {"ok": false, "code": "notice_failed"})
	var owner: String = flow._owner
	rt.session._begin_login()
	rt.session.identity._keep("p0-notice-two", "cd".repeat(32), ["code"])
	rt.session.player_id = "p0-notice-two"
	rt.session.identity_ready = true
	flow.tick()
	await _answer(await _request(), _http(), 200, {"ok": true, "name_reset": null})
	assert_int(wire.requests.size()).is_equal(3)   # GET1, ACK1, GET2; no ACK1 under player2
	assert_int(flow._pending[owner]).is_equal(1)
	assert_bool(flow.showing()).is_false()

func test_background_or_world_interruption_reopens_unread_without_ack() -> void:
	await _show()
	flow.set_background(true)
	assert_bool(flow.showing()).is_false()
	flow.set_background(false)
	flow.tick()
	assert_bool(flow.showing()).is_true()
	rt.detach(world)
	flow.tick()
	assert_bool(flow.showing()).is_false()
	rt.world = world
	flow.tick()
	assert_bool(flow.showing()).is_true()
	assert_int(wire.requests.size()).is_equal(1)
	assert_bool(flow._pending.is_empty()).is_true()

func test_current_refusal_still_retires_login_and_suppresses_notice() -> void:
	flow.tick()
	await _answer(await _request(), _http(), 403, {"ok": false, "code": "suspended", "until": null})
	flow.tick()
	assert_bool(rt.session.identity_ready).is_false()
	assert_int(rt.ui.screen_kind()).is_equal(P0SysScreen.Kind.SUSPENDED)
	assert_bool(flow.showing()).is_false()

func test_non_200_even_with_ok_true_is_not_server_confirmation() -> void:
	for code in [201, 202, 204, 500]:
		flow._loaded = false
		await _show(code)
		_ok()
		await _answer(await _request(Api.PATH + "/ack"), _http(), code, {"ok": true})
		assert_int(flow._pending[flow._owner]).is_equal(code)
		assert_bool(flow.showing()).is_false()
		assert_str(rt.ui.sys_text()).is_empty()

func test_non_200_get_cannot_claim_authoritative_null_or_version() -> void:
	for code in [201, 202, 204]:
		var received := []
		flow.api.read(func(r): received.append(r))
		await _answer(await _request(), _http(), code, {"ok": true, "name_reset": null})
		assert_int(received.size()).is_equal(1)
		assert_bool(received[0].get("ok", true)).is_false()
		assert_int(Api.unread(received[0])).is_equal(-1)

func test_conflict_requeries_without_acknowledging_unseen_version() -> void:
	await _show(1)
	_ok()
	await _answer(await _request(Api.PATH + "/ack"), _http(), 409, {"ok": false, "code": "notice_version_conflict"})
	await _answer(await _request(), _http(), 200, {"ok": true, "name_reset": {"version": 2}})
	assert_bool(flow.showing()).is_true()
	assert_int(flow._unread).is_equal(2)
	assert_int(wire.requests.size()).is_equal(3)

func test_local_pending_write_failure_does_not_block_or_fake_ack() -> void:
	flow.pending_path = DIR + "absent/pending.json"
	await _show()
	_ok()
	assert_bool(flow.showing()).is_false()
	assert_bool(FileAccess.file_exists(flow.pending_path)).is_false()
	await _answer(await _request(Api.PATH + "/ack"), _http(), 500, {"ok": false, "code": "notice_failed"})
	assert_int(flow._pending[flow._owner]).is_equal(1)
	assert_bool(rt.session.identity_ready).is_true()

func test_unknown_get_does_not_fabricate_notice_or_retry_every_frame() -> void:
	flow.tick()
	await _answer(await _request(), _http(), 200, {"ok": true})
	for i in range(5): flow.tick()
	assert_bool(flow.showing()).is_false()
	assert_int(wire.requests.size()).is_equal(1)
	assert_bool(flow._pending.is_empty()).is_true()

func test_confirmed_on_server_does_not_reappear_after_reload() -> void:
	await _show()
	_ok()
	await _answer(await _request(Api.PATH + "/ack"), _http(), 200, {"ok": true})
	_reload()
	await _answer(await _request(), _http(), 200, {"ok": true, "name_reset": null})
	assert_bool(flow.showing()).is_false()
	assert_int(wire.requests.size()).is_equal(3)
	assert_bool(flow._pending.is_empty()).is_true()

func test_ack_timeout_keeps_intent_and_does_not_reopen_card() -> void:
	await _show()
	_ok()
	var http := _http()
	http.wait_s = 0.2   # real P0HttpRequest timer on a silent real TCP connection; not the production 8-second duration
	await _request(Api.PATH + "/ack")
	var deadline := Time.get_ticks_msec() + 3000
	while flow._busy and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	assert_bool(flow._busy).is_false()
	assert_bool(flow.showing()).is_false()
	assert_int(flow._pending[flow._owner]).is_equal(1)
	assert_str(rt.ui.sys_text()).is_empty()

func test_pending_is_partitioned_by_service_environment() -> void:
	await _show()
	_ok()
	await _answer(await _request(Api.PATH + "/ack"), _http(), 500, {"ok": false, "code": "notice_failed"})
	var owner: String = flow._owner
	rt.session.base_url += "/another-environment"
	flow.tick()
	await _answer(await _request("/another-environment" + Api.PATH), _http(), 200, {"ok": true, "name_reset": null})
	assert_int(wire.requests.size()).is_equal(3)
	assert_int(flow._pending[owner]).is_equal(1)
	assert_bool(flow.showing()).is_false()

func test_refresh_updates_the_version_captured_by_ok() -> void:
	await _show(1)
	flow._read()
	await _answer(await _request(), _http(), 200, {"ok": true, "name_reset": {"version": 2}})
	_ok()
	assert_bool(flow.showing()).is_false()
	assert_int(flow._pending[flow._owner]).is_equal(2)
	await _answer(await _request(Api.PATH + "/ack"), _http(), 200, {"ok": true})
	assert_bool(flow._pending.is_empty()).is_true()
