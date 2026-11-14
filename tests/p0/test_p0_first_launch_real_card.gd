extends GdUnitTestSuite
## q(325) on the real pages (奕星 11-14): P0Runtime's glue with 哪吒's own P0AccFlow (#1063), not the stand-in — the card
## `We've updated our terms` over NAME's Save (guest's 409, the Save again), over an old farm's claim (in, account/consent,
## then NAME) and over a sign-in into a farm (in, account/consent, then the farm). Its Continue is the card's own agreed:
## the versions kept where the flow keeps them, read back by the glue.
const P0Identity := preload("res://modules/p0/p0_identity.gd")
const STORE := "user://test_p0_first_launch_real_card.json"
const ID_DIR := "user://test_p0_first_launch_real_card_id/"
const RECORD := "user://test_p0_first_launch_real_card_record.json"
const NEW := {"terms_version": "2026-12-01", "privacy_version": "2026-12-01"}
var rt: P0Runtime
var sent: Array = []
var replies := {}

func before_test() -> void:
	sent = []
	replies = {}
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, path, _b, _c): sent.append(path)
	rt.native_sign_in = func(provider: String) -> Dictionary:
		return {"result": "ok", "provider": provider, "id_token": "eyJ.tok", "nonce": "n0nce", "auth_code": "c0de"}
	add_child(rt)
	await get_tree().process_frame
	rt.session.accounts = true
	rt.session.identity_ready = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ID_DIR))
	rt.session.identity = P0Identity.new(ID_DIR)
	rt.session.identity.terms_version = "2026-11-13"
	rt.session.identity.privacy_version = "2026-11-13"
	rt.session.identity.send = func(_m: int, path: String, body: Dictionary, done: Callable):
		sent.append([path, body])
		done.call(replies.get(path, {"ok": false, "code": "network"}))
	rt.session.busy = false
	sent.clear()

func after_test() -> void:
	for p in [STORE, RECORD]: DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var d := DirAccess.open(ID_DIR)
	if d:
		for n in d.get_files(): d.remove(n)

func _sent(path: String) -> Array: return sent.filter(func(x): return x is Array and x[0] == path)

## The real flow up for `kind`, its record where the test can clear it, the AGE answer kept as the AGE page would.
func _open(kind: String) -> Node:
	rt.session.identity.kind = kind
	rt.session.first_run_needed.emit(kind)
	var flow = rt._acc_flow
	assert_str(flow.get_script().resource_path).is_equal("res://scenes/p0/account/p0_acc_flow.gd")   # the real one
	flow.record_path = RECORD
	flow.keep(true)
	return flow

## The card's Continue: its own agreed (P0AccConsent), as a tap on it after the tick.
func _continue(flow) -> void:
	assert_object(flow.renew).is_not_null()
	flow.renew.agreed.emit()

func test_name_s_save_refused_for_new_terms_is_the_card_then_the_same_save() -> void:
	var flow = _open("new")
	replies["/p0/session/google"] = {"ok": false, "code": "no_farm", "pending": "pend-1"}
	await rt._on_acc_sign_in("google")
	replies["/p0/session/guest"] = NEW.merged({"ok": false, "code": "consent_outdated"})
	rt._on_acc_named("Mia", false)
	assert_object(flow.renew).is_not_null()   # over NAME, nothing agreed yet
	assert_str(rt.session.identity.terms_version).is_equal("2026-11-13")
	replies["/p0/session/guest"] = {"ok": true, "player": "p0-real000000000000001", "linked": "google"}
	_continue(flow)
	assert_dict(flow.kept()).contains_key_value("terms", "2026-12-01")   # kept by the flow, read by the glue
	var saves := _sent("/p0/session/guest")
	assert_int(saves.size()).is_equal(2)
	assert_dict(saves[1][1]).contains_key_value("terms", "2026-12-01").contains_key_value("name", "Mia").contains_key_value("pending", "pend-1")
	assert_object(rt._acc_flow).is_null()   # in
	assert_bool(rt.session.identity_ready).is_true()

func test_an_old_farm_claimed_without_today_s_consent_is_the_card_then_name() -> void:
	rt.session.identity.player = "p0-real000000000000002"
	var flow = _open("old_signin")
	replies["/p0/session/claim"] = NEW.merged({"ok": true, "player": "p0-real000000000000002", "linked": ["apple"], "age": true,
		"consent": null, "consent_outdated": true})
	await rt._on_acc_sign_in("apple")
	assert_object(flow.renew).is_not_null()
	assert_bool(flow.page == flow.name_page).is_false()   # not NAME before the consent is kept (§9 补)
	replies["/p0/account/consent"] = {"ok": true}
	_continue(flow)
	assert_dict(_sent("/p0/account/consent")[0][1]).contains_key_value("terms", "2026-12-01").contains_key_value("age_ok", true)
	await get_tree().process_frame
	assert_bool(is_instance_valid(flow.renew)).is_false()   # the card down
	assert_bool(flow.page == flow.name_page).is_true()      # then NAME, Skip keeping its name

func test_a_sign_in_into_a_farm_without_today_s_consent_is_the_card_then_the_farm() -> void:
	var flow = _open("new")
	replies["/p0/session/apple"] = NEW.merged({"ok": true, "player": "p0-real000000000000003", "linked": ["apple"], "consent_outdated": true})
	await rt._on_acc_sign_in("apple")
	assert_object(flow.renew).is_not_null()
	assert_object(rt._acc_flow).is_not_null()   # not into the farm yet
	replies["/p0/account/consent"] = {"ok": false, "code": "network"}
	_continue(flow)
	assert_object(rt._acc_flow).is_not_null()   # not kept: the card stays, its key back
	replies["/p0/account/consent"] = {"ok": true}
	_continue(flow)
	assert_int(_sent("/p0/account/consent").size()).is_equal(2)
	assert_object(rt._acc_flow).is_null()   # kept: into the farm
