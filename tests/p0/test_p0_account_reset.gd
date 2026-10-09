extends GdUnitTestSuite
## SGODOT-270: a server-side reset starts a new account under the same player id (Joey's account starts over in San
## Francisco). The device's teaching tips, "seen" lists and quick-bar pins belonged to the old account: they go, so the
## first session teaches again. The same account, or a fresh install, keeps or starts them as before.

const STORE := "user://test_p0_account_reset_quick.json"
const TIPS := "user://test_p0_account_reset_tips.json"

var ui: P0Ui

func _view(since_ms: int) -> Dictionary:
	return {"energy": {"value": 150, "max": 200}, "coins": 40, "skills": {"farming": {"level": 1, "xp": 0}},
		"bag": {"capacity": 25, "slots": []}, "profile": {"name": "Farmer", "city": "San Francisco", "since_ms": since_ms}}

func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

## The stored file, with JSON's float numbers back as ints (the account time is whole milliseconds).
func _read(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not d is Dictionary: return {}
	for k in d: if d[k] is float: d[k] = int(d[k])
	return d

func _ui() -> P0Ui:
	ui = P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	add_child(auto_free(ui))
	await await_idle_frame()
	return ui

func before_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func after_test() -> void:
	for f in [STORE, TIPS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func test_a_new_account_under_the_same_id_clears_the_tips_and_the_quick_bar() -> void:
	var old := int(Time.get_unix_time_from_system() * 1000) - 86_400_000
	_write(TIPS, {"sow": true, "cast": true, "stall_seen": ["seed_radish"], "account_since": old})
	_write(STORE, {"fish": {"pins": ["bait_worm"], "removed": []}})
	await _ui()
	ui.set_view(_view(old + 86_000_000))   # the server reset the account: a later creation time
	assert_dict(_read(TIPS)).is_equal({"account_since": old + 86_000_000})
	assert_dict(_read(STORE)).is_empty()
	assert_bool(ui.first_time("sow")).is_true()   # the first session teaches again

func test_the_same_account_keeps_everything() -> void:
	var since := 1_791_539_492_778
	_write(TIPS, {"sow": true, "account_since": since})
	_write(STORE, {"fish": {"pins": ["bait_worm"], "removed": []}})
	await _ui()
	ui.set_view(_view(since))
	assert_dict(_read(TIPS)).is_equal({"sow": true, "account_since": since})
	assert_dict(_read(STORE)).is_equal({"fish": {"pins": ["bait_worm"], "removed": []}})

func test_tips_written_before_this_build_go_when_the_account_is_newer_than_the_file() -> void:
	_write(TIPS, {"sow": true, "cast": true})   # 0.1.0's file: no account_since
	var newer := (FileAccess.get_modified_time(TIPS) + 3600) * 1000   # the account made an hour after the file
	await _ui()
	ui.set_view(_view(newer))
	assert_dict(_read(TIPS)).is_equal({"account_since": newer})

func test_tips_written_after_the_account_was_made_are_kept_on_upgrade() -> void:
	_write(TIPS, {"sow": true})
	var older := (FileAccess.get_modified_time(TIPS) - 86_400) * 1000   # an account from yesterday, still playing
	await _ui()
	ui.set_view(_view(older))
	assert_dict(_read(TIPS)).is_equal({"sow": true, "account_since": older})

func test_a_fresh_install_records_the_account_and_a_view_without_profile_changes_nothing() -> void:
	await _ui()
	ui.set_view({"energy": {"value": 150, "max": 200}, "bag": {"capacity": 25, "slots": []}})
	assert_bool(FileAccess.file_exists(TIPS)).is_false()
	ui.set_view(_view(1_791_550_000_000))
	assert_dict(_read(TIPS)).is_equal({"account_since": 1_791_550_000_000})
