extends GdUnitTestSuite
## The first launch's glue in P0Runtime (SGODOT-488 A2; contract v1.4–v1.6.3): first_run_needed opens the pages in place
## of the launch cover; a sign-in key opens the phone's sheet, then session/apple | google, or claim for an old account
## (with what AGE took); no_farm is NAME and guest with the ticket; a conflict is the card, its keys session/pending or
## the ticket dropped; a test code reports this phone's AGE answer; then the launch cover comes up and the world's first
## read goes. unauthenticated is the Sign in page again; an account refusal is its page.
const STORE := "user://test_p0_first_launch_glue.json"
var rt: P0Runtime
var sent: Array = []
var replies := {}
const SHEET_OK := {"result": "ok", "id_token": "eyJ.tok", "nonce": "n0nce", "auth_code": "c0de"}
var sheet := {}   # what the phone's sheet answers

func before_test() -> void:
	sent = []
	replies = {}
	sheet = SHEET_OK.duplicate()
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, path, _b, _c): sent.append(path)
	rt.acc_flow_path = "res://tests/p0/fakes/fake_acc_flow.gd"
	rt.native_sign_in = func(provider: String) -> Dictionary: return sheet.merged({"provider": provider})
	add_child(rt)
	await get_tree().process_frame
	rt.session.accounts = true
	rt.session.identity_ready = false
	rt.session.identity = P0Identity.new("user://test_p0_first_launch_glue_id/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://test_p0_first_launch_glue_id/"))
	rt.session.identity.terms_version = "2026-11-13"
	rt.session.identity.privacy_version = "2026-11-13"
	rt.session.identity.send = func(_m: int, path: String, body: Dictionary, done: Callable):
		sent.append([path, body])
		done.call(replies.get(path, {"ok": false, "code": "network"}))
	rt.session.busy = false
	sent.clear()

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	var d := DirAccess.open("user://test_p0_first_launch_glue_id/")
	if d:
		for n in d.get_files(): d.remove(n)

func _sent(path: String) -> Array: return sent.filter(func(x): return x is Array and x[0] == path)

func test_a_new_install_signs_in_names_its_farm_and_the_world_comes_up() -> void:
	rt.cover_launch()
	rt.session.identity.kind = "new"
	rt.session.first_run_needed.emit("new")
	assert_object(rt._acc_flow).is_not_null()
	assert_int(rt.ui.screen_kind()).is_equal(-1)   # the pages in place of the launch cover
	var flow = rt._acc_flow
	rt._acc_flow.agreed.emit(true)
	assert_array(sent).is_empty()   # a new install's AGE goes with guest
	replies["/p0/session/google"] = {"ok": false, "code": "no_farm", "pending": "pend-1"}
	await rt._on_acc_sign_in("google")
	assert_dict(_sent("/p0/session/google")[0][1]).contains_key_value("id_token", "eyJ.tok").contains_key_value("nonce", "n0nce")
	assert_array(flow.calls).contains_exactly([["no_farm", true]])   # NAME, Try another account under it
	replies["/p0/session/guest"] = {"ok": true, "player": "p0-bbbbbbbbbbbbbbbbbbbb", "linked": "google"}
	flow.named.emit("Mia", false)
	var guest: Array = _sent("/p0/session/guest")
	assert_int(guest.size()).is_equal(1)
	assert_dict(guest[0][1]).contains_key_value("name", "Mia").contains_key_value("terms", "2026-11-13") \
		.contains_key_value("age_ok", true).contains_key_value("pending", "pend-1")
	assert_bool(rt.session.identity_ready).is_true()
	assert_object(rt._acc_flow).is_null()
	assert_int(rt.ui.screen_kind()).is_equal(P0SysScreen.Kind.LAUNCH)
	assert_array(sent).contains(["/p0/state"])   # the world's first read went out

func test_a_sign_in_with_a_farm_goes_straight_in() -> void:
	rt.session.identity.kind = "new"
	rt.session.first_run_needed.emit("new")
	replies["/p0/session/apple"] = {"ok": true, "player": "p0-cccccccccccccccccccc", "linked": ["apple"]}
	await rt._on_acc_sign_in("apple")
	assert_dict(_sent("/p0/session/apple")[0][1]).contains_key_value("auth_code", "c0de")
	assert_bool(rt.session.identity_ready).is_true()
	assert_object(rt._acc_flow).is_null()

func test_a_closed_or_failed_sheet_sends_nothing() -> void:
	rt.session.identity.kind = "new"
	rt.session.first_run_needed.emit("new")
	sheet = {"result": "cancelled"}
	await rt._on_acc_sign_in("apple")
	assert_array(sent).is_empty()
	assert_array(rt._acc_flow.calls).is_empty()
	sheet = {"result": "failed", "reason": "APPLE_UNKNOWN"}
	await rt._on_acc_sign_in("apple")
	assert_array(sent).is_empty()   # never read as "no farm here"
	assert_array(rt._acc_flow.calls).is_empty()

func test_an_old_account_claims_with_its_age_then_keeps_its_name() -> void:
	rt.session.identity.player = "p0-old0000000000000001"
	rt.session.identity.kind = "old_age"
	rt.session.first_run_needed.emit("old_age")
	var flow = rt._acc_flow
	flow.agreed.emit(true)
	assert_array(sent).is_empty()   # nothing until the claim: no token yet
	replies["/p0/session/claim"] = {"ok": true, "player": "p0-old0000000000000001", "age": true, "consent": {}}
	await rt._on_acc_sign_in("apple")
	assert_dict(_sent("/p0/session/claim")[0][1]).contains_key_value("provider", "apple").contains_key_value("age_ok", true) \
		.contains_key_value("consent", {"terms": "2026-11-13", "privacy": "2026-11-13"})
	assert_bool(rt.session.identity_ready).is_true()
	assert_array(flow.calls).contains_exactly([["no_farm", false]])   # NAME, no Try another account
	flow.named.emit("", true)   # Skip: its name stays, nothing sent
	assert_array(_sent("/p0/account/name")).is_empty()
	assert_array(_sent("/p0/session/guest")).is_empty()
	assert_object(rt._acc_flow).is_null()

func test_a_conflict_is_the_card_and_its_keys() -> void:
	rt.session.identity.player = "p0-old0000000000000001"
	rt.session.identity.kind = "old_signin"
	rt.session.first_run_needed.emit("old_signin")
	var flow = rt._acc_flow
	var farm := {"name": "Mia", "home_level": 7, "last_played_at": 1}
	replies["/p0/session/claim"] = {"ok": false, "code": "conflict", "pending": "pend-c", "has_farm": true, "farm": farm}
	await rt._on_acc_sign_in("google")
	assert_array(flow.calls).contains_exactly([["conflict", farm, "google"]])
	flow.sign_in_again.emit()   # Try another account: the ticket dropped
	assert_str(rt.session.identity.pending).is_empty()
	replies["/p0/session/claim"]["pending"] = "pend-d"
	await rt._on_acc_sign_in("google")
	replies["/p0/session/pending"] = {"ok": true, "player": "p0-dddddddddddddddddddd", "linked": ["google"]}
	flow.switch_farm.emit()   # Switch to that farm: no second sheet
	assert_dict(_sent("/p0/session/pending")[0][1]).contains_key_value("pending", "pend-d")
	assert_bool(rt.session.identity_ready).is_true()
	assert_object(rt._acc_flow).is_null()

func test_a_guest_race_is_the_same_card_from_name() -> void:
	rt.session.identity.kind = "new"
	rt.session.first_run_needed.emit("new")
	var flow = rt._acc_flow
	replies["/p0/session/google"] = {"ok": false, "code": "no_farm", "pending": "pend-1"}
	await rt._on_acc_sign_in("google")
	var farm := {"name": "Ann", "home_level": 1, "last_played_at": 2}
	replies["/p0/session/guest"] = {"ok": false, "code": "conflict", "pending": "pend-2", "has_farm": true, "farm": farm}
	flow.named.emit("Mia", false)
	assert_array(flow.calls[-1]).is_equal(["conflict", farm, "google"])
	assert_str(rt.session.identity.pending).is_equal("pend-2")
	assert_bool(rt.session.identity_ready).is_false()

func test_a_refused_name_goes_back_to_the_page() -> void:
	rt.session.identity.kind = "new"
	rt.session.first_run_needed.emit("new")
	var flow = rt._acc_flow
	replies["/p0/session/guest"] = {"ok": false, "code": "name_rejected", "reason": "blocked"}
	flow.named.emit("Admin", false)
	assert_array(flow.calls).contains_exactly([["name_refused", {"ok": false, "code": "name_rejected", "reason": "blocked"}]])
	assert_bool(rt.session.identity_ready).is_false()

func test_a_test_code_reports_this_phone_s_age_then_name() -> void:
	rt.session.identity.kind = "new"
	rt.session.first_run_needed.emit("new")
	var flow = rt._acc_flow
	flow.record = {"age_ok": true, "terms": "2026-11-13", "privacy": "2026-11-13"}
	replies["/p0/session/code"] = {"ok": false, "code": "bad_code"}
	flow.code_entered.emit("ABCD-EFGH-JKMN")
	assert_array(flow.calls).contains_exactly([["code_refused", {"ok": false, "code": "bad_code"}]])
	replies["/p0/session/code"] = {"ok": true, "player": "p0-eeeeeeeeeeeeeeeeeeee"}
	replies["/p0/account/consent"] = {"ok": true}
	flow.code_entered.emit("ABCD-EFGH-JKMN")
	assert_dict(_sent("/p0/account/consent")[0][1]).contains_key_value("age_ok", true).contains_key_value("terms", "2026-11-13")
	assert_bool(rt.session.identity_ready).is_true()
	assert_array(flow.calls[-1]).is_equal(["no_farm", false])
	assert_array(_sent("/p0/session/guest")).is_empty()   # a code's account never takes guest

func test_unauthenticated_is_the_sign_in_page_again() -> void:
	rt.session.identity.player = "p0-ffffffffffffffffffff"
	rt.session.identity.token = "cd".repeat(32)
	rt.session.identity.linked = ["apple"]
	rt.session.identity_ready = true
	rt.session._refused({"ok": false, "code": "unauthenticated"})
	assert_bool(rt.session.identity_ready).is_false()
	assert_bool(rt.session.identity.has_token()).is_false()
	assert_str(rt.session.identity.player).is_equal("p0-ffffffffffffffffffff")   # kept: the support code
	assert_object(rt._acc_flow).is_not_null()
	assert_str(rt._acc_flow.kind).is_equal("signed_out")
	assert_dict(rt._acc_flow.hints).is_equal({"line": "last_time", "with": "apple"})

func test_no_on_the_age_page_sends_nothing() -> void:
	rt.session.identity.kind = "old_age"
	rt.session.first_run_needed.emit("old_age")
	rt._acc_flow.agreed.emit(false)
	assert_array(sent).is_empty()

func test_offline_keeps_the_launch_cover_and_asks_hello_again() -> void:
	rt.cover_launch()
	rt.session.first_run_needed.emit("offline")
	assert_object(rt._acc_flow).is_null()
	assert_int(rt.ui.screen_kind()).is_equal(P0SysScreen.Kind.LAUNCH)
	rt._tick_screens(rt.LAUNCH_RETRY_S + 0.1)
	assert_array(sent.filter(func(x): return x is Array and x[0] == "/p0/hello")).has_size(1)
	assert_array(sent).not_contains(["/p0/state"])
