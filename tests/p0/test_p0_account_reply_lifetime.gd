extends GdUnitTestSuite
## Exercise the production HTTP completion -> Identity -> Session -> Runtime order. Only HTTP completion
## signals are controlled; do not replace Identity.send or mistake a dropped UI callback for no Session effect.
const Identity := preload("res://modules/p0/p0_identity.gd")
const Room := preload("res://modules/p0/p0_voice_room.gd")
const DIR := "user://test_reply_lifetime_identity/"
const RECORD := "user://test_reply_lifetime_record.json"
const STORE := "user://test_reply_lifetime_quick.json"
var rt: P0Runtime
var states: Array = []
var outcomes: Array = []
var old_env := ""
var old_force: Array
var old_handler: Callable

func before_test() -> void:
	old_env = OS.get_environment("P0_ACCOUNTS")
	old_force = P0SignIn.force.duplicate()
	old_handler = AppRouter.foreground_back_action
	OS.set_environment("P0_ACCOUNTS", "1")
	P0SignIn.force = ["google"]
	states = []
	outcomes = []
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.identity = Identity.new(DIR)
	rt.session.transport = func(_m, path, _body, _cmd): states.append([path, rt.session.request_context()])
	add_child(rt)
	# Suppress only the fixture's deferred startup hello. Every operation under test restores real _account_request.
	rt.session.identity.send = func(_m, _p, _b, _done): pass
	await get_tree().process_frame
	rt.set_process(false)
	rt.session.set_process(false)
	rt.session.base_url = "http://127.0.0.1:1"   # no listener/server; complete signals synchronously before polling
	rt.session.identity.send = rt.session._account_request
	rt.session.identity.player = "p0-context-original"
	rt.session.player_id = rt.session.identity.player
	rt.session.identity.token = "ab".repeat(32)
	rt.session.identity.terms_version = "2026-11-13"
	rt.session.identity.privacy_version = "2026-11-13"
	rt.session.identity_ready = false
	rt.session._ui_events.clear()
	_open("old_signin")

func after_test() -> void:
	rt.free()
	AppRouter.foreground_back_action = old_handler
	P0SignIn.force = old_force
	OS.set_environment("P0_ACCOUNTS", old_env)
	await get_tree().process_frame
	var dir := DirAccess.open(DIR)
	if dir:
		for file in dir.get_files(): dir.remove(file)
	for path in [RECORD, STORE]: DirAccess.remove_absolute(path)

func _open(kind: String) -> void:
	rt.session.identity.kind = kind
	rt._open_acc_flow(kind)
	rt._acc_flow.record_path = RECORD

func _last_http(parent: Node) -> P0HttpRequest:
	var found: P0HttpRequest
	for child in parent.get_children():
		if child is P0HttpRequest and not child.is_queued_for_deletion(): found = child
	assert_object(found).is_not_null()
	return found

func _complete(http: P0HttpRequest, status: int, body: Dictionary) -> void:
	http.request_completed.emit(HTTPRequest.RESULT_SUCCESS, status, PackedStringArray(), JSON.stringify(body).to_utf8_buffer())

func _consent(done := Callable()) -> P0HttpRequest:
	var callback := done if done.is_valid() else rt._acc_reply(func(r): outcomes.append(r))
	rt.session.consent({"age_ok": true, "terms": "2026-11-13", "privacy": "2026-11-13"}, callback)
	return _last_http(rt.session)

func _assert_not_released() -> void:
	assert_bool(rt.session.identity_ready).is_false()
	assert_int(states.size()).is_equal(0)   # contexts contain tokens: never dump them in a failing assertion
	assert_array(rt.session._ui_events).is_empty()   # not even session_start queued by _identity_ready
	assert_array(outcomes).is_empty()

func test_terminal_refusal_while_already_false_expires_older_consent_success() -> void:
	for code in ["session_replaced", "account_deleted", "suspended", "unauthenticated"]:
		_open("old_signin")
		rt.ui.hide_screen()
		rt.session.identity.token = "ab".repeat(32)
		rt.session.identity_ready = false
		states.clear()
		outcomes.clear()   # each refusal variant is independent, including the unfixed negative control
		rt.session._ui_events.clear()
		var consent := _consent()
		var room: Room = auto_free(Room.new())
		room.session = rt.session
		add_child(room)
		room.set_process(false)
		room.fetch_status()   # current-identity refusal through real VoiceRoom -> Session refusal entry
		var before := rt.session.request_context()
		_complete(_last_http(room), 403 if code == "suspended" else 401, {"ok": false, "code": code, "until": null})
		var retired := not rt.session.request_is_current(before)
		_complete(consent, 200, {"ok": true})
		_assert_not_released()
		assert_bool(retired).override_failure_message(code).is_true()
		if code != "unauthenticated":
			assert_bool(rt.ui.screen_kind() in [P0SysScreen.Kind.SESSION, P0SysScreen.Kind.DELETED, P0SysScreen.Kind.SUSPENDED]).is_true()

func test_replacing_flow_without_a_new_login_expires_consent_before_session_success() -> void:
	var old := _consent()
	var token := rt.session.identity.token
	_open("new")
	var new_flow: Node = rt._acc_flow
	_complete(old, 200, {"ok": true})
	_assert_not_released()
	assert_object(rt._acc_flow).is_same(new_flow)
	assert_str(rt.session.identity.kind).is_equal("new")
	assert_str(rt.session.identity.token).is_equal(token)   # closing a page is not deleting adopted identity

func test_closing_flow_without_replacement_still_expires_older_consent() -> void:
	var old := _consent()
	rt._close_acc_flow()
	_complete(old, 200, {"ok": true})
	_assert_not_released()
	assert_object(rt._acc_flow).is_null()

func test_normal_success_closes_flow_without_retiring_the_fresh_world_request() -> void:
	var old := _consent(rt._acc_reply(func(r):
		outcomes.append(r)
		if bool(r.get("ok", false)): rt._acc_done()))
	_complete(old, 200, {"ok": true})
	assert_bool(rt.session.identity_ready).is_true()
	assert_object(rt._acc_flow).is_null()
	assert_int(outcomes.size()).is_equal(1)
	assert_int(states.size()).is_equal(1)
	assert_str(states[0][0]).is_equal("/p0/state")
	assert_bool(rt.session.request_is_current(states[0][1])).is_true()
	assert_bool(rt.session.busy).is_true()   # it is still the live state request, not cancelled by closing the flow
	assert_bool(rt.session._ui_events.any(func(e): return e.get("kind") == "session_start")).is_true()

func test_old_consent_after_new_account_or_same_player_relogin_cannot_release_session() -> void:
	for same_player in [false, true]:
		_open("old_signin")
		rt.session.identity_ready = false
		states.clear()
		outcomes.clear()
		rt.session._ui_events.clear()
		var old := _consent()
		var player := rt.session.identity.player
		var token := rt.session.identity.token
		rt.session._begin_login()   # public sign_in/claim/code entry all do this, even while already false
		rt.session.identity._keep(player if same_player else "p0-context-next", token, ["google"])
		_complete(old, 200, {"ok": true})
		_assert_not_released()

func test_old_401_and_403_are_dropped_before_runtime_can_refuse_new_context() -> void:
	for status in [401, 403]:
		_open("old_signin")
		var gates := []
		var old := _consent(rt._acc_reply(func(r):
			gates.append(r)
			rt.session._refused(r)))
		rt.session._begin_login()   # same player and token text; new login epoch is the boundary
		_complete(old, status, {"ok": false, "code": "suspended" if status == 403 else "account_deleted", "until": null})
		assert_array(gates).is_empty()
		assert_str(rt.session.identity.token).is_equal("ab".repeat(32))

func test_old_code_success_after_new_authorization_cannot_persist_identity() -> void:
	rt.session.sign_in_code("0123-4567-89AB", func(r): outcomes.append(r))
	var old := _last_http(rt.session)
	rt.session.sign_in("google", {"id_token": "unit-only", "nonce": "unit-only"}, func(_r): pass)
	_complete(old, 200, {"ok": true, "player": "p0-old-code", "next_step": "continue"})
	assert_array(outcomes).is_empty()
	assert_str(rt.session.identity.player).is_equal("p0-context-original")
	assert_str(rt.session.identity.token).is_equal("ab".repeat(32))
	assert_bool(FileAccess.file_exists(DIR + "p0_session.json")).is_false()
