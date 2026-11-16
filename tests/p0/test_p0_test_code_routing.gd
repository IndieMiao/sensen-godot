extends GdUnitTestSuite
## Actual code page -> host -> P0Identity/Session with controlled account replies; actual Router owns all Back.
const Fixture := preload("res://tests/p0/test_p0_account_back_routing.gd")
const Identity := preload("res://modules/p0/p0_identity.gd")
const Page := preload("res://scenes/p0/account/p0_acc_test_code.gd")
const ID_DIR := "user://test_code_routing_identity/"
const RECORD := "user://test_code_routing_age.json"
const STORE := "user://test_code_routing_quick.json"
var rt: P0Runtime
var router: Fixture.RouterProbe
var farm: Fixture.FarmProbe
var old_scene: Node
var old_handler: Callable
var old_env := ""
var old_force: Array
var swaps := 0
var requests: Array = []
var replies: Array[Callable] = []

func before_test() -> void:
	old_scene = get_tree().current_scene
	old_handler = AppRouter.foreground_back_action
	old_env = OS.get_environment("P0_ACCOUNTS")
	old_force = P0SignIn.force.duplicate()
	P0SignIn.force = ["google"]
	OS.set_environment("P0_ACCOUNTS", "1")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ID_DIR))
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.identity = Identity.new(ID_DIR)
	rt.session.transport = func(_m,_p,_b,_done): pass
	add_child(rt)
	rt.session.identity.send = func(_m,path,body,done):
		requests.append({"path":path,"body":body.duplicate()})
		replies.append(done)
	await get_tree().process_frame
	rt.set_process(false)
	rt.session.set_process(false)
	rt.session.identity.terms_version = "2026-11-13"
	rt.session.identity.privacy_version = "2026-11-13"
	rt.ui.hide_screen()
	swaps = 0
	requests.clear();replies.clear()
	rt.swap_root = func(): swaps += 1
	router = auto_free(Fixture.RouterProbe.new())
	add_child(router)
	router.foreground_back_action = AppRouter.foreground_back_action
	farm = Fixture.FarmProbe.new()
	farm.rt = rt
	get_tree().root.add_child(farm)
	get_tree().current_scene = farm

func after_test() -> void:
	get_tree().current_scene = old_scene
	farm.free()
	router._stack.clear();router._loading = null
	rt._close_acc_flow();rt.free()
	await get_tree().process_frame
	AppRouter.foreground_back_action = old_handler
	OS.set_environment("P0_ACCOUNTS",old_env)
	P0SignIn.force = old_force
	for p in [RECORD,STORE]: DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var dir := DirAccess.open(ID_DIR)
	if dir:
		for p in dir.get_files(): dir.remove(p)

func _open():
	rt._open_acc_flow("old_signin")
	var f = rt._acc_flow
	f.record_path = RECORD
	var file := FileAccess.open(RECORD,FileAccess.WRITE)
	file.store_string(JSON.stringify({"age_ok":true,"terms":"2026-11-13","privacy":"2026-11-13","agreed_at":1}));file.close()
	f.page.find_child("TestCode",true,false).pressed.emit()
	return f.code_page

func _submit(p) -> void:
	p.field.input.text = "ABCD-EFGH-JKMN"
	p.field.input.caret_column = 14
	p.field.input.text_changed.emit(p.field.input.text)
	p.go.activated.emit()

func _answer(r: Dictionary) -> void:
	var done: Callable = replies.pop_front()
	done.call(r)

func _no_nav() -> void:
	assert_int(swaps).is_equal(0)
	assert_int(router.maps).is_equal(0)
	assert_int(router.pops).is_equal(0)
	assert_int(router.homes).is_equal(0)
	assert_object(get_tree().current_scene).is_same(farm)

func _ok(step: String) -> Dictionary:
	return {"ok":true,"player":"p0-code-test-account","next_step":step}

func test_real_router_guards_code_http_and_failure_back_only_returns_to_signin() -> void:
	var p = _open()
	_submit(p)
	p.go.activated.emit()
	p.back_key.pressed.emit()
	for i in 3: router._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_no_nav()
	assert_int(requests.size()).is_equal(1)
	assert_str(requests[0].path).is_equal("/p0/session/code")
	assert_str(requests[0].body.code).is_equal("ABCDEFGHJKMN")
	assert_int(rt._acc_requests).is_equal(1)
	_answer({"ok":false,"code":"network"})
	assert_str(p.field.error).is_equal(Page.OFFLINE)
	assert_bool(p.go.disabled).is_false()
	assert_int(rt._acc_requests).is_equal(0)
	router.handle_back()
	assert_object(rt._acc_flow.page).is_instanceof(P0AccSignIn)
	_no_nav()

func test_code_continue_waits_for_consent_then_enters_without_name_or_guest() -> void:
	var p = _open()
	_submit(p)
	_answer(_ok("continue"))
	assert_str(requests[-1].path).is_equal("/p0/account/consent")
	assert_bool(rt.session.identity_ready).is_false()
	p.back_key.pressed.emit()
	router.handle_back()
	_no_nav()
	assert_object(rt._acc_flow.page).is_same(p)
	assert_int(rt._acc_requests).is_equal(1)
	_answer({"ok":true})
	assert_bool(rt.session.identity_ready).is_true()
	assert_object(rt._acc_flow).is_null()
	assert_bool(requests.any(func(r):return r.path=="/p0/session/guest")).is_false()

func test_code_name_waits_for_consent_then_name_without_try_another_skip_sends_no_guest() -> void:
	var p = _open()
	_submit(p)
	_answer(_ok("name"))
	_answer({"ok":true})
	var flow = rt._acc_flow
	assert_object(flow.page).is_instanceof(P0AccName)
	assert_bool(flow.name_page.another_row.visible).is_false()
	assert_str(rt._naming).is_equal("rename")
	router.handle_back()
	_no_nav()
	var count := requests.size()
	flow.named.emit("",true)
	assert_int(requests.size()).is_equal(count)
	assert_object(rt._acc_flow).is_null()

func test_missing_or_unknown_next_step_never_adopts_token_or_guesses_from_old_state() -> void:
	var p = _open()
	rt.session.view = {"home":{"pending":false},"homestead":{"level":20}}
	for reply in [{"ok":true,"player":"p0-code-test-account"},_ok("unknown")]:
		_submit(p)
		_answer(reply)
		assert_bool(rt.session.identity.has_token()).is_false()
		assert_bool(rt.session.identity_ready).is_false()
		assert_bool(FileAccess.file_exists(ID_DIR+"p0_session.json")).is_false()
		assert_str(p.field.error).is_equal(Page.FAILED)
		assert_object(rt._acc_flow.page).is_same(p)
	assert_bool(requests.any(func(r):return r.path=="/p0/account/consent")).is_false()

func test_all_plain_failures_are_red_on_code_page_not_toasts_or_legacy_fallback() -> void:
	var p = _open()
	for pair in [["bad_code",Page.BAD],["rate_limited",Page.RATE],["network",Page.OFFLINE],["not_found",Page.FAILED],["schema",Page.FAILED]]:
		p.set_busy(false)
		p._refused = false   # new attempt fixture; the page suite separately proves the edit requirement
		_submit(p)
		_answer({"ok":false,"code":pair[0]})
		assert_object(rt._acc_flow.page).is_same(p)
		assert_str(p.field.error).is_equal(pair[1])
		assert_bool(rt.session.identity_ready).is_false()
		assert_str(rt.ui.toast_text()).is_empty()

func test_consent_failure_and_outdated_keep_route_and_do_not_resubmit_code() -> void:
	var p = _open()
	_submit(p)
	_answer(_ok("continue"))
	_answer({"ok":false,"code":"consent_outdated","terms_version":"2099-11-14","privacy_version":"2099-11-14"})
	var flow = rt._acc_flow
	assert_object(flow.renew).is_not_null()
	router.handle_back()
	_no_nav()
	flow.renew.consent.checked = true
	flow.renew.go.activated.emit()
	assert_int(rt._acc_requests).is_equal(1)
	router.handle_back()
	_no_nav()
	_answer({"ok":false,"code":"network"})
	assert_object(flow.renew).is_not_null()
	flow.renew.go.activated.emit()
	_answer({"ok":true})
	assert_object(rt._acc_flow).is_null()
	assert_int(requests.filter(func(r):return r.path=="/p0/session/code").size()).is_equal(1)
	assert_str(requests[-1].body.terms).is_equal("2099-11-14")

func test_consent_network_failure_without_update_card_restores_code_page_error_and_close() -> void:
	var p = _open()
	_submit(p)
	_answer(_ok("name"))
	_answer({"ok":false,"code":"network"})
	assert_bool(p.busy).is_false()
	assert_str(p.field.error).is_equal(Page.OFFLINE)
	assert_object(rt._acc_flow.page).is_same(p)
	assert_bool(p.field.input.editable).is_false()   # code is already verified; retry the consent stage only
	p.go.activated.emit()
	assert_str(requests[-1].path).is_equal("/p0/account/consent")
	assert_int(requests.filter(func(r):return r.path=="/p0/session/code").size()).is_equal(1)
	_answer({"ok":false,"code":"network"})
	router.handle_back()
	assert_object(rt._acc_flow.page).is_instanceof(P0AccSignIn)
	_no_nav()

func test_old_consent_failure_does_not_mark_or_unlock_a_new_flow() -> void:
	var a = _open()
	_submit(a)
	_answer(_ok("continue"))   # consent remains outstanding
	var b = _open()
	_submit(b)
	assert_int(rt._acc_requests).is_equal(1)
	_answer({"ok":false,"code":"network"})   # the old consent answer
	assert_str(b.field.error).is_empty()
	assert_bool(b.busy).is_true()
	assert_int(rt._acc_requests).is_equal(1)
	_answer({"ok":false,"code":"bad_code"})
	assert_str(b.field.error).is_equal(Page.BAD)

func test_consent_retry_cannot_use_a_changed_account_token_or_stay_busy_forever() -> void:
	var p = _open()
	_submit(p)
	_answer(_ok("continue"))
	_answer({"ok":false,"code":"network"})
	rt.session.identity.token = "cd".repeat(32)
	var count := requests.size()
	p.go.activated.emit()
	assert_int(requests.size()).is_equal(count)
	assert_bool(p.busy).is_false()
	assert_str(p.field.error).is_equal(Page.FAILED)

func test_leaving_verified_code_then_using_another_provider_does_not_reuse_its_owned_token() -> void:
	var p = _open()
	_submit(p)
	var used: String = requests[0].body.token
	_answer(_ok("continue"))
	_answer({"ok":false,"code":"network"})
	p.back_key.pressed.emit()
	assert_object(rt._acc_flow.page).is_instanceof(P0AccSignIn)
	assert_bool(rt._code_retry.is_valid()).is_false()
	rt.session.identity.sign_in("google",{"id_token":"unit-only","nonce":"unit"},func(_r):pass)
	assert_str(requests[-1].body.token).is_not_equal(used)
	assert_str(rt.session.identity.player).is_equal("p0-code-test-account")   # no local identity deletion
	_answer({"ok":false,"code":"network"})

func test_a_late_code_success_after_flow_replacement_never_persists_old_identity() -> void:
	var a = _open()
	_submit(a)
	var b = _open()   # another account flow, even before it sends a credential
	_answer(_ok("name"))
	assert_bool(rt.session.identity.has_token()).is_false()
	assert_bool(FileAccess.file_exists(ID_DIR+"p0_session.json")).is_false()
	assert_object(rt._acc_flow.page).is_same(b)
	assert_str(b.field.error).is_empty()
	_submit(b)
	_answer(_ok("continue"))
	_answer({"ok":true})
	assert_object(rt._acc_flow).is_null()
