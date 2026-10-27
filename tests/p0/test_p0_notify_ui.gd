extends GdUnitTestSuite
## SGODOT-350 on screen: the soft prompt (q(235) ①, q(236) ④; 不知火舞 350 7bffafd7) comes under the HUD the first time
## the player is on their farm with crops growing, every finger up and nothing open; leaving, something opening or Back
## put it away unanswered; Allow / Not now answer it. Settings has `Notifications ›` with the switch's value, and its
## page the `Crops ready` switch and, when the system has said no, the notice.

const STORE := "user://test_p0_notify_ui.json"
const TIPS := "user://test_p0_notify_ui_tips.json"
const PREFS := "user://test_p0_notify_ui_prefs.json"
const Phone := preload("res://tests/p0/test_p0_notify.gd").FakePhone

var ui: P0Ui
var phone

func _view() -> Dictionary:
	return {
		"coins": 40, "energy": {"value": 150, "max": 200},
		"skills": {"fishing": {"level": 1, "xp": 0}, "farming": {"level": 1, "xp": 0}, "cooking": {"level": 1, "xp": 0}},
		"fishing": {"dex": []}, "bag": {"capacity": 25, "slots": []}, "profile": {"name": "Mia"},
		"plots": [{"id": 1, "crop": "crop_lettuce", "state": "growing", "ready_in": 3_600_000.0}],
		"names": {"crop_lettuce": "Lettuce"},
	}

func before_test() -> void:
	for f in [TIPS, PREFS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	phone = Phone.new()
	ui = P0Ui.new()
	ui.quick_store = STORE
	ui.tips_path = TIPS
	ui.notify = P0Notify.new(PREFS, phone)
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_surface("farm")
	ui.space = "home"

func after_test() -> void:
	for f in [STORE, TIPS, PREFS]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _tick() -> void:
	ui._ask_left = 0.0
	ui._tick_ask(0.1)
	await await_idle_frame()

func test_it_comes_under_the_hud_with_the_crops_question() -> void:
	await _tick()
	var ask := ui._ask
	assert_object(ask).is_not_null()
	assert_str(ask.question).is_equal("Get a ping when your crops are ready?")
	await await_millis(UiTokens.MOTION_DRAWER_MS + 60)
	assert_float(ask.position.x).is_equal(float(UiTokens.SPACE_PAGE))
	assert_float(ask.position.y).is_equal(108.0)   # NOTIF-ASK: x16 y108, under the HUD
	assert_float(ask.modulate.a).is_equal(1.0)
	assert_float(ask.size.x).is_equal(UiSoftPrompt.WIDTH)
	assert_float(ask.size.y).is_less(140.0)   # as tall as its content (130 in the main), not stretched

func test_not_while_a_finger_is_down_something_is_open_or_off_the_farm() -> void:
	ui._finger(0, true)
	await _tick()
	assert_object(ui._ask).is_null()
	ui._finger(0, false)
	ui.open_settings()
	await _tick()
	assert_object(ui._ask).is_null()
	ui.close_modal()
	ui.space = "map"
	await _tick()
	assert_object(ui._ask).is_null()
	ui.space = "home"
	await _tick()
	assert_object(ui._ask).is_not_null()

func test_back_puts_it_away_unanswered_for_the_rest_of_the_run() -> void:
	await _tick()
	assert_bool(ui.close_top_layer()).is_true()
	assert_object(ui._ask).is_null()
	assert_bool(ui.notify.asked()).is_false()
	await _tick()
	assert_object(ui._ask).is_null()   # not straight back
	ui.space = "map"
	await _tick()
	ui.space = "home"
	await _tick()
	assert_object(ui._ask).is_null()   # nor after the map: not again this run (q(237) ③)
	ui.ask_again()   # back from the background
	await _tick()
	assert_object(ui._ask).is_not_null()

func test_leaving_the_farm_or_the_background_puts_it_away() -> void:
	await _tick()
	ui.space = "map"
	await _tick()
	assert_object(ui._ask).is_null()
	assert_bool(ui.notify.asked()).is_false()
	ui.ask_again()
	ui.space = "home"
	await _tick()
	assert_object(ui._ask).is_not_null()
	ui.ask_away()   # the app went to the background
	assert_object(ui._ask).is_null()
	assert_bool(ui.notify.asked()).is_false()

func test_a_held_stick_does_not_put_it_away() -> void:
	await _tick()
	ui._finger(0, true)
	await _tick()
	assert_object(ui._ask).is_not_null()

func test_a_panel_opening_puts_it_away() -> void:
	await _tick()
	ui.open_settings()
	await _tick()
	assert_object(ui._ask).is_null()
	assert_bool(ui.notify.asked()).is_false()

func test_allow_asks_the_system_and_is_never_asked_again() -> void:
	await _tick()
	ui._ask.allow.pressed.emit()
	assert_array(phone.calls).contains_exactly(["request"])
	assert_bool(ui.notify.asked()).is_true()
	await _tick()
	assert_object(ui._ask).is_null()

func test_settings_has_the_row_and_its_page_the_switch() -> void:
	phone.s.allowed = true
	ui.open_settings()
	await await_idle_frame()
	var row := ui.find_child("Notifications", true, false) as UiSettingRow
	assert_object(row).is_not_null()
	assert_str((row.find_child("Value", true, false) as Label).text).is_equal("On")
	row.pressed.emit()
	await await_idle_frame()
	assert_str(ui.modal_kind).is_equal("notifications")
	var crops := ui.find_child("CropsReady", true, false) as UiSettingRow
	assert_bool(crops.on).is_true()
	assert_object(ui.find_child("SystemOff", true, false)).is_null()
	crops.find_child("Hit", true, false).pressed.emit()   # off
	await await_idle_frame()
	assert_bool(ui.notify.switch_on()).is_false()
	assert_bool((ui.find_child("CropsReady", true, false) as UiSettingRow).on).is_false()
	assert_bool(ui.close_top_layer()).is_true()   # ‹ back to Settings, which reads Off now
	await await_idle_frame()
	assert_str((ui.find_child("Notifications", true, false).find_child("Value", true, false) as Label).text).is_equal("Off")

func test_the_notice_when_the_system_said_no() -> void:
	phone.s.asked = true   # refused in the system dialog
	ui.open_notifications(Callable())
	await await_idle_frame()
	var notice := ui.find_child("SystemOff", true, false) as Control
	assert_object(notice).is_not_null()
	assert_str((notice.find_child("Text", true, false) as Label).text).is_equal(ToastLayer.keep_units("Notifications are off for P0 Demo"))   # P0\u00a0Demo, kept on one line
	assert_str((notice.find_child("Action", true, false) as Label).text).is_equal("Open system settings ›")
	assert_bool((ui.find_child("CropsReady", true, false) as UiSettingRow).on).is_false()

func test_no_phone_side_no_row_and_no_ask() -> void:
	ui.notify = P0Notify.new("", null)
	await _tick()
	assert_object(ui._ask).is_null()
	ui.open_settings()
	await await_idle_frame()
	assert_object(ui.find_child("Notifications", true, false)).is_null()
