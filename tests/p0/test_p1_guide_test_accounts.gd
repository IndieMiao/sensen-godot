extends GdUnitTestSuite
## Hidden B flow: isolated main/test identities, first-request feature flags, persistence and invisible gesture.
const Accounts := preload("res://modules/p0/p0_test_accounts.gd")
const Entry := preload("res://modules/p0/p0_test_entry.gd")
var dir: String
var accounts: RefCounted
const MAIN_BYTES := "isolated-main-341\n"

func before_test() -> void:
	dir = "user://test_341_accounts_%d/" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_write("p0_player.txt", MAIN_BYTES)
	_write("p0_tips.json", '{"main_seen":true}')
	_write("p0_quickbar.json", '{"main_pin":"seed_radish"}')
	accounts = Accounts.new(dir)

func _write(name: String, text: String) -> void:
	var f := FileAccess.open(dir + name, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null: return
	for name in d.get_files(): d.remove(name)
	for name in d.get_directories(): _remove_tree(path.path_join(name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func after_test() -> void:
	_remove_tree(dir)
	preload("res://modules/p0/p0_home_pick.gd").clear()

func _header(a: RefCounted) -> String:
	var session := P0Session.new()
	session.test_accounts = a
	var result := ""
	for h in session._headers():
		if h.begins_with("x-p0-features:"): result = h
	session.free()
	return result

func test_toggle_only_affects_new_test_id_and_main_stays_legacy() -> void:
	assert_bool(accounts.enabled()).is_false()
	assert_str(_header(accounts)).is_equal("x-p0-features: choose_home")
	assert_bool(accounts.set_enabled(true)).is_true()
	assert_bool(accounts.is_test()).is_false()
	assert_str(_header(accounts)).is_equal("x-p0-features: choose_home")
	assert_bool(accounts.start_test("main-avatar")).is_true()
	assert_bool(Accounts.valid_test_id(accounts.active_id())).is_true()
	assert_str(_header(accounts)).is_equal("x-p0-features: choose_home,guide_v3")
	accounts.set_enabled(false)
	assert_str(_header(accounts)).is_equal("x-p0-features: choose_home,guide_v3")   # existing guide is not rolled back
	assert_bool(accounts.start_test("test-avatar")).is_true()
	assert_str(_header(accounts)).is_equal("x-p0-features: choose_home")

func test_new_test_and_process_restart_preserve_main_and_isolate_preferences() -> void:
	accounts.set_enabled(true)
	assert_bool(accounts.start_test("main-avatar")).is_true()
	var test_id: String = accounts.active_id()
	assert_str(accounts.avatar_id()).is_equal(test_id)
	var path: String = accounts.profile_file("p0_tips.json")
	assert_bool(path.begins_with(dir + "p0_test_accounts/" + test_id + "/")).is_true()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"only_test":true}')
	f.close()
	# The same persistent directory loaded by a replacement client build: no process-only recovery state.
	var relaunched = Accounts.new(dir)
	assert_str(relaunched.active_id()).is_equal(test_id)
	assert_str(_header(relaunched)).is_equal("x-p0-features: choose_home,guide_v3")
	assert_bool(relaunched.return_main()).is_true()
	var returned = Accounts.new(dir)
	assert_bool(returned.is_test()).is_false()
	assert_str(returned.avatar_id()).is_equal("main-avatar")
	assert_str(returned.profile_file("p0_tips.json")).is_equal(dir + "p0_tips.json")
	assert_str(FileAccess.get_file_as_string(dir + "p0_player.txt")).is_equal(MAIN_BYTES)
	assert_str(FileAccess.get_file_as_string(dir + "p0_main_identity.backup")).is_equal(MAIN_BYTES)
	assert_str(FileAccess.get_file_as_string(dir + "p0_tips.json")).is_equal('{"main_seen":true}')
	assert_str(FileAccess.get_file_as_string(dir + "p0_quickbar.json")).is_equal('{"main_pin":"seed_radish"}')
	assert_str(_header(returned)).is_equal("x-p0-features: choose_home")

func test_each_explicit_start_uses_a_new_recognizable_id_and_keeps_first_main_backup() -> void:
	accounts.start_test("main-avatar")
	var first: String = accounts.active_id()
	accounts.start_test("test-avatar")
	assert_bool(Accounts.valid_test_id(accounts.active_id())).is_true()
	assert_bool(accounts.active_id() != first).is_true()
	assert_bool(accounts.return_main()).is_true()
	assert_str(accounts.avatar_id()).is_equal("main-avatar")
	assert_str(FileAccess.get_file_as_string(dir + "p0_player.txt")).is_equal(MAIN_BYTES)

func test_failed_backup_does_not_switch_and_conflicting_main_is_never_overwritten() -> void:
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(dir + "p0_main_identity.backup.tmp"))
	assert_bool(accounts.start_test()).is_false()
	assert_bool(accounts.is_test()).is_false()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "p0_main_identity.backup.tmp"))
	assert_bool(accounts.start_test()).is_true()
	_write("p0_player.txt", "another-isolated-main\n")
	assert_bool(accounts.return_main()).is_false()
	assert_bool(accounts.start_test()).is_false()
	assert_str(FileAccess.get_file_as_string(dir + "p0_player.txt")).is_equal("another-isolated-main\n")

func test_verified_backup_can_restore_a_missing_main_without_replacing_an_existing_one() -> void:
	accounts.start_test()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "p0_player.txt"))
	assert_bool(accounts.return_main()).is_true()
	assert_str(FileAccess.get_file_as_string(dir + "p0_player.txt")).is_equal(MAIN_BYTES)
	_write("p0_player.txt", "another-isolated-main\n")
	assert_bool(accounts.restore_missing_main()).is_true()
	assert_str(FileAccess.get_file_as_string(dir + "p0_player.txt")).is_equal("another-isolated-main\n")
	assert_bool(accounts.return_main()).is_false()

func test_empty_main_with_verified_backup_restores_original_bytes_and_returns_main() -> void:
	assert_bool(accounts.start_test()).is_true()
	_write("p0_player.txt", "")
	var relaunched = Accounts.new(dir)
	assert_bool(relaunched.restore_missing_main()).is_true()
	assert_str(FileAccess.get_file_as_string(dir + "p0_player.txt")).is_equal(MAIN_BYTES)
	assert_str(FileAccess.get_file_as_string(dir + "p0_main_identity.backup")).is_equal(MAIN_BYTES)
	assert_bool(relaunched.return_main()).is_true()
	assert_bool(Accounts.new(dir).is_test()).is_false()

func _seven(e: RefCounted, from_ms := 1000) -> void:
	for i in 7:
		e.press(Vector2(10, 10), from_ms + i * 300)
		e.release(Vector2(10, 10), from_ms + i * 300 + 50)

func test_hidden_entry_requires_all_seven_taps_then_a_full_hold() -> void:
	var e = Entry.new()
	_seven(e)
	assert_bool(e.tick(2900)).is_false()
	e.press(Vector2(10, 10), 3000)
	assert_bool(e.tick(4999)).is_false()
	assert_bool(e.tick(5000)).is_true()
	assert_bool(e.tick(6000)).is_false()

func test_hidden_entry_cancels_on_scroll_slow_taps_short_hold_or_lost_focus() -> void:
	var e = Entry.new()
	for i in 7:
		e.press(Vector2.ZERO, i * 700)
		e.release(Vector2.ZERO, i * 700 + 50)
	e.press(Vector2.ZERO, 5000)
	assert_bool(e.tick(8000)).is_false()
	e.reset()
	_seven(e)
	e.press(Vector2.ZERO, 3000)
	e.move(Vector2(0, 30))
	assert_bool(e.tick(6000)).is_false()
	_seven(e, 10000)
	e.press(Vector2.ZERO, 12000)
	e.release(Vector2.ZERO, 12500)
	assert_bool(e.tick(16000)).is_false()
	_seven(e, 20000)
	e.press(Vector2.ZERO, 22000)
	e.reset()   # background, return or scroll_started
	assert_bool(e.tick(26000)).is_false()

func test_b_page_reuses_settings_layout_and_only_test_has_return_action() -> void:
	for is_test in [false, true]:
		var page: P0SettingsPage = auto_free(P0SettingsPage.test_options(false, is_test))
		add_child(page)
		var labels := page.find_children("*", "Label", true, false).map(func(l): return l.text)
		assert_array(labels).contains(["Test options", "New-player guide", "For new test accounts", "Current account", "Test" if is_test else "Main",
			"Test accounts are separate. Your main farm is kept."])
		assert_bool(page.find_child("GuideTestToggle", true, false).on).is_false()
		assert_object(page.find_child("StartTestAccount", true, false)).is_not_null()
		assert_bool(page.find_child("ReturnMainAccount", true, false) != null).is_equal(is_test)
		assert_bool(labels.has("Done")).is_false()

class RefusalUi extends P0Ui:
	var errors: Array = []
	func toast_error(message: String, _key := "") -> void: errors.append(message)

func test_only_test_first_city_pick_can_return_directly_without_confirmation() -> void:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.test_accounts = accounts
	ui.tips_path = dir + "p0_tips.json"
	ui.quick_store = dir + "ui_quickbar.json"
	add_child(ui)
	var actions := []
	ui.test_account_requested.connect(func(action): actions.append(action))
	for test in [false, true]:
		if test: assert_bool(accounts.start_test()).is_true()
		var flow = preload("res://scenes/p0/panels/p0_home_flow.gd").new()
		ui.open_home_flow(flow)
		await await_idle_frame()
		var button := flow.cities.find_child("ReturnMainAccount", true, false) as Button
		assert_bool(button != null).is_equal(test)
		if test:
			assert_float(button.size.y).is_greater_equal(44.0)
			assert_float(button.position.y).is_greater_equal(flow.cities.key.position.y + flow.cities.key.size.y)
			button.pressed.emit()
			assert_array(actions).is_equal(["main"])
			assert_str(ui.modal_kind).is_equal("home_pick")   # no confirmation layer
		ui.close_modal()
		await await_idle_frame()
	var changed = preload("res://scenes/p0/panels/p0_home_flow.gd").new(null, 0.0, 0.0, "gn-5391959")
	ui.open_home_flow(changed)
	assert_object(changed.cities.find_child("ReturnMainAccount", true, false)).is_null()

func test_only_test_launch_failure_has_an_offline_local_return() -> void:
	var ui: P0Ui = auto_free(P0Ui.new())
	ui.test_accounts = accounts
	ui.tips_path = dir + "p0_tips.json"
	ui.quick_store = dir + "ui_quickbar.json"
	add_child(ui)
	ui.show_screen(P0SysScreen.Kind.FAIL)
	assert_object(ui.screen().find_child("ReturnMainAccount", true, false)).is_null()
	assert_bool(accounts.start_test()).is_true()
	ui.set_offline(true)
	ui.show_screen(P0SysScreen.Kind.FAIL)
	await await_idle_frame()
	var button := ui.screen().find_child("ReturnMainAccount", true, false) as Button
	assert_bool(button.is_visible_in_tree()).is_true()
	assert_float(button.size.y).is_greater_equal(44.0)
	assert_bool(button.disabled).is_false()
	var actions := []
	ui.test_account_requested.connect(func(action): actions.append(action))
	button.pressed.emit()
	assert_array(actions).is_equal(["main"])
	ui.show_screen(P0SysScreen.Kind.LAUNCH)
	assert_bool(button.is_visible_in_tree()).is_false()
	ui.show_screen(P0SysScreen.Kind.MAINT)
	assert_bool(button.is_visible_in_tree()).is_false()

func test_lost_ack_retry_is_silent_but_unrelated_errors_still_show() -> void:
	var runtime: P0Runtime = auto_free(P0Runtime.new())
	runtime.remove_child(runtime.ui)
	runtime.ui.free()
	runtime.ui = RefusalUi.new()
	runtime.add_child(runtime.ui)
	runtime._on_refused("guide_not_now", {}, {"type": "guide", "op": "ack", "step": "t_city"})
	assert_array(runtime.ui.errors).is_empty()
	runtime._on_refused("unknown_test_failure", {}, {"type": "guide"})
	assert_array(runtime.ui.errors).is_equal(["Can't do that (unknown_test_failure)"])
