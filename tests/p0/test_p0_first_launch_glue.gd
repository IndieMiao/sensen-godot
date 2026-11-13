extends GdUnitTestSuite
## The first launch's glue in P0Runtime (SGODOT-488 A2): first_run_needed opens the pages in place of the launch cover,
## NAME's answer makes the save (guest) or names an old account (rename), AGE's answer records an old account's consent,
## then the launch cover comes up and the world's first read goes; an account refusal becomes its page.
const STORE := "user://test_p0_first_launch_glue.json"
var rt: P0Runtime
var sent: Array = []
var replies := {}

func before_test() -> void:
	sent = []
	replies = {}
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, path, _b, _c): sent.append(path)
	rt.acc_flow_path = "res://tests/p0/fakes/fake_acc_flow.gd"
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

func test_a_new_install_names_its_farm_and_the_world_comes_up() -> void:
	rt.cover_launch()
	rt.session.first_run_needed.emit("new")
	assert_object(rt._acc_flow).is_not_null()
	assert_int(rt.ui.screen_kind()).is_equal(-1)   # the pages in place of the launch cover
	replies["/p0/session/guest"] = {"ok": true, "player": "p0-bbbbbbbbbbbbbbbbbbbb"}
	rt._acc_flow.named.emit("Mia", false)
	var guest: Array = sent.filter(func(x): return x is Array and x[0] == "/p0/session/guest")
	assert_int(guest.size()).is_equal(1)
	assert_dict(guest[0][1]).contains_key_value("name", "Mia").contains_key_value("terms", "2026-11-13").contains_key_value("age_ok", true)
	assert_bool(rt.session.identity_ready).is_true()
	assert_object(rt._acc_flow).is_null()
	assert_int(rt.ui.screen_kind()).is_equal(P0SysScreen.Kind.LAUNCH)
	assert_array(sent).contains(["/p0/state"])   # the world's first read went out

func test_a_refused_name_goes_back_to_the_page() -> void:
	rt.session.first_run_needed.emit("new")
	var flow = rt._acc_flow
	replies["/p0/session/guest"] = {"ok": false, "code": "name_rejected", "reason": "blocked"}
	flow.named.emit("Admin", false)
	assert_array(flow.refused).contains_exactly([{"ok": false, "code": "name_rejected", "reason": "blocked"}])
	assert_bool(rt.session.identity_ready).is_false()

func test_an_old_account_agrees_then_keeps_its_name() -> void:
	rt.session.identity.token = "cd".repeat(32)
	rt.session.identity.player = "p0-old0000000000000001"
	rt.session.first_run_needed.emit("old_consent")
	replies["/p0/account/consent"] = {"ok": true}
	rt._acc_flow.agreed.emit(true)
	assert_array(sent.filter(func(x): return x is Array and x[0] == "/p0/account/consent")).has_size(1)
	assert_bool(rt.session.identity_ready).is_true()
	rt._acc_flow.named.emit("", true)   # Skip: its name stays, nothing sent
	assert_array(sent.filter(func(x): return x is Array and x[0] == "/p0/account/name")).is_empty()
	assert_object(rt._acc_flow).is_null()

func test_no_on_the_age_page_sends_nothing() -> void:
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
