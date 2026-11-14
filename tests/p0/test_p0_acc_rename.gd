extends GdUnitTestSuite
## The profile's Edit › and ACC-RENAME (SGODOT-491; 不知火舞's spec v1.1 §3; PROFILE-1-EDIT 643:197324, 644:197332).

const STORE := "user://test_p0_acc_rename.json"
const NOW := 100.0 * 86400000.0
const DAY := 86400000.0

var ui: P0Ui
var asked: Array = []

func before_test() -> void:
	asked = []
	ui = P0Ui.new()
	ui.quick_store = STORE
	ui.view = {"account": {"name": "Mira", "linked": ["google"], "rename_at": 0}, "profile": {"name": "Farmer"}}
	ui.rename_requested.connect(func(n): asked.append(n))
	add_child(auto_free(ui))
	await await_idle_frame()

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _drawer() -> UiDrawer:
	return ui._rename if is_instance_valid(ui._rename) else null

func test_edit_shows_only_with_accounts_and_the_chosen_name() -> void:
	var page: P0ProfilePage = auto_free(P0ProfilePage.new(ui.view))
	add_child(page)
	assert_str(page.name_row.name_label.text).is_equal("Mira")   # view.account's name over profile's
	assert_object(page.name_row.edit_label).is_not_null()
	assert_str(page.name_row.edit_label.text).is_equal("Edit ›")
	var got := []
	page.edit_name_pressed.connect(func(): got.append(true))
	page.name_row.edit_hit.pressed.emit()
	assert_array(got).is_equal([true])
	var before: P0ProfilePage = auto_free(P0ProfilePage.new({"profile": {"name": "Farmer"}}))
	add_child(before)
	assert_object(before.name_row.edit_label).is_null()

func test_edit_in_the_cooldown_only_says_when() -> void:
	ui.view.account.rename_at = NOW + 4.2 * DAY
	ui.open_rename(Callable(), NOW)
	assert_object(_drawer()).is_null()
	assert_str(ui.toast_text()).is_equal("You can change your name again in 5 days")
	assert_str(P0Ui.rename_wait_text(2 * 3600000.0)).is_equal("You can change your name again in 1 day")
	assert_str(P0Ui.rename_wait_text(DAY)).is_equal("You can change your name again in 1 day")
	assert_str(P0Ui.rename_wait_text(DAY + 1.0)).is_equal("You can change your name again in 2 days")

func test_save_greys_till_the_name_is_another_and_goes_to_the_host() -> void:
	ui.open_rename(Callable(), NOW)
	var d := _drawer()
	assert_object(d).is_not_null()
	await await_idle_frame()
	assert_float(d.height).is_greater(200.0)   # fitted to what is in it, not 0
	var field: UiTextField = d.field
	assert_str(field.text).is_equal("Mira")
	assert_str(field.helper).is_equal("2–16 letters or numbers · You can change it every 7 days")
	assert_bool(d.save.disabled).is_true()   # unchanged
	field.input.text = "M"
	field.input.text_changed.emit("M")
	assert_bool(d.save.disabled).is_true()   # too short
	field.input.text = "Mira Ray"
	field.input.text_changed.emit("Mira Ray")
	assert_bool(d.save.disabled).is_false()
	d.save.activated.emit()
	assert_array(asked).is_equal(["Mira Ray"])
	assert_int(d.save.phase).is_equal(CommandLifecycle.State.PENDING)
	ui.rename_answer({"ok": false, "code": "name_rejected", "reason": "blocked"})
	assert_str(field.error).is_equal("That name isn't allowed")
	assert_int(d.save.phase).is_equal(CommandLifecycle.State.IDLE)
	field.input.text = "Mira Sun"
	field.input.text_changed.emit("Mira Sun")
	d.save.activated.emit()
	ui.rename_answer({"ok": true, "name": "Mira Sun"})
	assert_str(ui.toast_text()).is_equal("Name saved")
	assert_str(ui.modal_kind).is_not_equal("rename")

func test_too_soon_and_a_failure() -> void:
	ui.open_rename(Callable(), NOW)
	var d := _drawer()
	d.field.input.text = "Mira Ray"
	d.field.input.text_changed.emit("Mira Ray")
	d.save.activated.emit()
	ui.rename_answer({"ok": false, "code": "network"})
	assert_int(d.save.phase).is_equal(CommandLifecycle.State.IDLE)   # Save back
	assert_str(ui.modal_kind).is_equal("rename")
	d.save.activated.emit()
	ui.rename_answer({"ok": false, "code": "rename_too_soon", "rename_at": NOW + 3 * DAY}, NOW)
	assert_str(ui.toast_text()).is_equal("You can change your name again in 3 days")
	assert_str(ui.modal_kind).is_not_equal("rename")

func test_cancel_closes() -> void:
	ui.open_rename(Callable(), NOW)
	_drawer().cancel.activated.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_not_equal("rename")
