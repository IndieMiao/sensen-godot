extends GdUnitTestSuite
## SGODOT-356: P0Notify's iOS phone, the lines it sends tools/ios/LocalNotify.swift and the state it keeps from the
## answers — asks nothing before the phone has said, then as on Android 13+ (the system asks once).

const H := 3_600_000.0
const NOON_UTC := 1_793_102_400_000.0
const PREFS := "user://test_p0_notify_ios.json"
const NEVER := 'NOTIFY_STATE|{"needs_grant":true,"allowed":false,"asked":false,"app":"Gensen"}'
const ALLOWED := 'NOTIFY_STATE|{"needs_grant":true,"allowed":true,"asked":true,"app":"Gensen"}'
const DENIED := 'NOTIFY_STATE|{"needs_grant":true,"allowed":false,"asked":true,"app":"Gensen"}'

var sent: Array = []

func _phone() -> P0NotifyIOS:
	sent.clear()
	return P0NotifyIOS.new(func(line: String): sent.append(line))

func _notify(phone: P0NotifyIOS) -> P0Notify:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	return P0Notify.new(PREFS, phone)

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

func _radishes() -> Dictionary:
	return {"plots": [{"crop": "crop_radish", "state": "growing", "ready_in": 2 * H}], "names": {"crop_radish": "Radish"}}

func test_it_asks_for_the_state_and_waits_for_it() -> void:
	var phone := _phone()
	assert_array(sent).contains_exactly(["NOTIFY_STATE"])
	var n := _notify(phone)
	assert_bool(n.available()).is_true()
	assert_str(phone.state()).is_empty()
	assert_bool(n.may_ask()).is_false()   # no soft prompt before the phone has said whether it was ever asked
	assert_bool(n.switch_on()).is_false()
	assert_bool(n.system_refused()).is_false()

func test_never_asked_asks_and_allow_brings_the_system_dialog() -> void:
	var phone := _phone()
	var n := _notify(phone)
	var got := []
	phone.permission.connect(func(granted: bool): got.append(granted))
	phone.receive(NEVER)
	assert_array(got).contains_exactly([false])   # the first state refreshes the screen too
	assert_bool(n.may_ask()).is_true()
	assert_str(n.system().get("app", "")).is_equal("Gensen")
	sent.clear()
	n.answer(true)
	assert_array(sent).contains_exactly(["NOTIFY_AUTH"])
	phone.receive(ALLOWED)   # the player allowed it in the system dialog
	assert_array(got).contains_exactly([false, true])
	assert_bool(n.switch_on()).is_true()
	assert_bool(n.may_ask()).is_false()

func test_the_dialog_answered_no_still_answers() -> void:
	var phone := _phone()
	phone.receive(DENIED)
	var got := []
	phone.permission.connect(func(granted: bool): got.append(granted))
	phone.request_permission()
	phone.receive(DENIED)   # the same state, but it answers the dialog
	assert_array(got).contains_exactly([false])
	phone.receive(DENIED)   # nothing new, nothing asked: quiet
	assert_array(got).contains_exactly([false])

func test_a_no_shows_the_notice_and_the_switch_opens_the_settings() -> void:
	var phone := _phone()
	phone.receive(DENIED)
	var n := _notify(phone)
	assert_bool(n.may_ask()).is_false()
	assert_bool(n.system_refused()).is_true()
	sent.clear()
	n.set_switch(true)
	assert_array(sent).contains_exactly(["NOTIFY_SETTINGS"])

func test_going_away_sets_one_and_coming_back_cancels() -> void:
	var phone := _phone()
	phone.receive(ALLOWED)
	var n := _notify(phone)
	sent.clear()
	n.went_away(_radishes(), NOON_UTC, 0)
	assert_array(sent).contains_exactly(["NOTIFY_CANCEL_ALL", "NOTIFY_AT|%d|Radish ready to harvest|Your farm is waiting." % int(NOON_UTC + 2 * H)])
	sent.clear()
	n.came_back()
	assert_array(sent).contains_exactly(["NOTIFY_CANCEL_ALL"])

func test_a_bar_in_the_words_cannot_split_the_line() -> void:
	var phone := _phone()
	sent.clear()
	phone.schedule(1000.0, "A|B", "C|D", "Crops ready")
	assert_array(sent).contains_exactly(["NOTIFY_AT|1000|A B|C D"])

func test_other_packets_and_bad_json_are_ignored() -> void:
	var phone := _phone()
	phone.receive("POIS|1|0|1|{}")
	phone.receive("NOTIFY_STATE|not json")
	assert_str(phone.state()).is_empty()
