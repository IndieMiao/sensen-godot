extends GdUnitTestSuite
## SGODOT-350 / q(236): the crop-ready notification's time and words — the soonest growing plot, a teaching seed left
## out, two kinds within a minute say `Crops`, one plot says it in the singular, 22:00–08:00 phone time moved to 08:00.

const H := 3_600_000.0
## 2026-10-27 12:00:00 UTC.
const NOON_UTC := 1_793_102_400_000.0

func _view(plots: Array) -> Dictionary:
	return {
		"plots": plots,
		"names": {"crop_radish": "Radish", "crop_lettuce": "Lettuce", "crop_apple": "Apple", "crop_quick_radish": "Quick Radish"},
		"quick_seeds": [{"id": "crop_quick_radish", "seed": "seed_quick_radish", "harvest": "crop_radish"}],
	}

func _plot(crop: String, state: String, ready_in = null) -> Dictionary:
	return {"crop": crop, "state": state, "ready_in": ready_in}

func test_nothing_growing_plans_nothing() -> void:
	assert_dict(P0Notify.plan(_view([]), NOON_UTC, 0)).is_empty()
	# sown but not watered, or ripe: not growing (q(236) ⑦)
	assert_dict(P0Notify.plan(_view([_plot("crop_radish", "sown"), _plot("crop_radish", "ready", 0.0)]), NOON_UTC, 0)).is_empty()

func test_the_soonest_plot_and_the_plural() -> void:
	var p := P0Notify.plan(_view([_plot("crop_radish", "growing", 3 * H), _plot("crop_radish", "growing", 2 * H)]), NOON_UTC, 0)
	assert_float(float(p.at)).is_equal(NOON_UTC + 2 * H)
	assert_str(p.title).is_equal("Radishes ready to harvest")
	assert_str(p.body).is_equal("Your farm is waiting.")

func test_one_plot_says_it_in_the_singular_and_uncountable_stays() -> void:
	assert_str(P0Notify.plan(_view([_plot("crop_radish", "growing", H)]), NOON_UTC, 0).title).is_equal("Radish ready to harvest")
	var lettuce := _view([_plot("crop_lettuce", "growing", H), _plot("crop_lettuce", "growing", H)])
	assert_str(P0Notify.plan(lettuce, NOON_UTC, 0).title).is_equal("Lettuce ready to harvest")

func test_two_kinds_within_a_minute_say_crops() -> void:
	var near := _view([_plot("crop_radish", "growing", H), _plot("crop_apple", "growing", H + 50_000.0)])
	assert_str(P0Notify.plan(near, NOON_UTC, 0).title).is_equal("Crops ready to harvest")
	var apart := _view([_plot("crop_radish", "growing", H), _plot("crop_apple", "growing", H + 120_000.0)])
	assert_str(P0Notify.plan(apart, NOON_UTC, 0).title).is_equal("Radish ready to harvest")

func test_the_quick_radish_takes_no_part() -> void:
	assert_dict(P0Notify.plan(_view([_plot("crop_quick_radish", "growing", 60_000.0)]), NOON_UTC, 0)).is_empty()
	var p := P0Notify.plan(_view([_plot("crop_quick_radish", "growing", 60_000.0), _plot("crop_apple", "growing", 5 * H)]), NOON_UTC, 0)
	assert_float(float(p.at)).is_equal(NOON_UTC + 5 * H)
	assert_str(p.title).is_equal("Apple ready to harvest")

func test_quiet_hours_move_to_eight() -> void:
	# UTC−7 (San Francisco summer time): 12:00 UTC is 05:00 there; ripe at 06:00 local goes out at 08:00 local.
	var p := P0Notify.plan(_view([_plot("crop_radish", "growing", H)]), NOON_UTC, -420)
	assert_float(float(p.at)).is_equal(NOON_UTC + 3 * H)
	# Ripe at 23:00 local (UTC+0) goes out at 08:00 the next morning.
	var late := P0Notify.plan(_view([_plot("crop_radish", "growing", 11 * H)]), NOON_UTC, 0)
	assert_float(float(late.at)).is_equal(NOON_UTC + 20 * H)
	# 21:59 is outside; 08:00 itself is outside.
	assert_float(P0Notify.after_quiet(NOON_UTC + 9 * H + 59 * 60_000.0, 0)).is_equal(NOON_UTC + 9 * H + 59 * 60_000.0)
	assert_float(P0Notify.after_quiet(NOON_UTC - 4 * H, 0)).is_equal(NOON_UTC - 4 * H)

func test_put_off_to_eight_names_what_is_ripe_by_then() -> void:
	# Radishes at 23:00, Apples at 07:00, both before 08:00: two kinds, though seven hours apart.
	var both := _view([_plot("crop_radish", "growing", 11 * H), _plot("crop_apple", "growing", 19 * H)])
	assert_str(P0Notify.plan(both, NOON_UTC, 0).title).is_equal("Crops ready to harvest")
	# Apples after 08:00 are not ripe when it goes out.
	var one := _view([_plot("crop_radish", "growing", 11 * H), _plot("crop_apple", "growing", 21 * H)])
	assert_str(P0Notify.plan(one, NOON_UTC, 0).title).is_equal("Radish ready to harvest")

# ---------------------------------------------------------------- the switch and the ask (q(236) ④ ⑤)
const PREFS := "user://test_p0_notify.json"

## GodotNotify's stand-in: the phone's state and every call made to it.
class FakePhone extends RefCounted:
	signal permission(granted: bool)
	var s := {"sdk": 34, "needs_grant": true, "allowed": false, "asked": false, "app": "P0 Demo"}
	var calls: Array = []
	func state() -> String: return JSON.stringify(s)
	func request_permission() -> void: calls.append("request"); s.asked = true
	func open_settings() -> void: calls.append("settings")
	func schedule(at: float, t: String, b: String, ch: String) -> void: calls.append(["schedule", at, t, b, ch])
	func cancel_all() -> void: calls.append("cancel")

func _notify(phone: FakePhone) -> P0Notify:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	return P0Notify.new(PREFS, phone)

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

func test_no_phone_side_no_switch_and_no_ask() -> void:
	var n := P0Notify.new("", null)
	assert_bool(n.available()).is_false()
	assert_bool(n.may_ask()).is_false()
	assert_bool(n.switch_on()).is_false()
	n.went_away(_view([_plot("crop_radish", "growing", H)]), NOON_UTC, 0)   # nothing to call: no error

func test_android_13_never_asked_asks_and_allow_brings_the_system_dialog() -> void:
	var phone := FakePhone.new()
	var n := _notify(phone)
	assert_bool(n.may_ask()).is_true()
	assert_bool(n.switch_on()).is_false()
	assert_bool(n.system_refused()).is_false()   # never asked is not a no: no notice
	n.answer(true)
	assert_array(phone.calls).contains_exactly(["request"])
	assert_bool(n.asked()).is_true()
	phone.s.allowed = true   # the player allowed it in the system dialog
	assert_bool(n.switch_on()).is_true()
	assert_bool(n.may_ask()).is_false()

func test_already_allowed_on_13_skips_the_ask_and_is_on() -> void:
	var phone := FakePhone.new()
	phone.s.allowed = true
	var n := _notify(phone)
	assert_bool(n.may_ask()).is_false()
	assert_bool(n.switch_on()).is_true()   # never chosen: the system's yes counts

func test_a_no_in_the_system_dialog_never_asks_again_and_shows_the_notice() -> void:
	var phone := FakePhone.new()
	phone.s.asked = true
	var n := _notify(phone)
	assert_bool(n.may_ask()).is_false()
	assert_bool(n.system_refused()).is_true()
	n.set_switch(true)   # the switch now opens the system's page, not the dialog again
	assert_array(phone.calls).contains_exactly(["settings"])
	assert_bool(n.switch_on()).is_false()   # off while the system says no, whatever the frame drew (dbd8d596)

func test_android_12_asks_and_allow_turns_it_on_without_a_dialog() -> void:
	var phone := FakePhone.new()
	phone.s = {"sdk": 31, "needs_grant": false, "allowed": true, "asked": false, "app": "P0 Demo"}
	var n := _notify(phone)
	assert_bool(n.may_ask()).is_true()
	assert_bool(n.switch_on()).is_false()   # never chosen on 12: not received by default
	n.answer(true)
	assert_array(phone.calls).is_empty()
	assert_bool(n.switch_on()).is_true()
	# its notifications off in the system: Allow opens the system's page; the notice shows
	var off := FakePhone.new()
	off.s = {"sdk": 31, "needs_grant": false, "allowed": false, "asked": false, "app": "P0 Demo"}
	var m := _notify(off)
	assert_bool(m.system_refused()).is_true()
	m.answer(true)
	assert_array(off.calls).contains_exactly(["settings"])

func test_not_now_is_asked_and_off_and_kept_per_account() -> void:
	var phone := FakePhone.new()
	phone.s.allowed = true
	var n := _notify(phone)
	n.answer(false)
	assert_bool(n.switch_on()).is_false()   # the player's off wins over the system's on
	var again := P0Notify.new(PREFS, phone)   # the next launch reads the account's file
	assert_bool(again.asked()).is_true()
	assert_str(again.choice()).is_equal("off")

func test_switching_off_cancels_and_going_away_sets_only_when_on() -> void:
	var phone := FakePhone.new()
	phone.s.allowed = true
	var n := _notify(phone)
	var view := _view([_plot("crop_radish", "growing", 2 * H)])
	n.went_away(view, NOON_UTC, 0)
	assert_array(phone.calls).contains_exactly(["cancel", ["schedule", NOON_UTC + 2 * H, "Radish ready to harvest", "Your farm is waiting.", "Crops ready"]])
	phone.calls.clear()
	assert_bool(n.asked()).is_false()
	n.set_switch(false)
	assert_array(phone.calls).contains_exactly(["cancel"])
	assert_bool(n.asked()).is_true()   # the switch touched in Settings counts as asked (q(237) ③)
	phone.calls.clear()
	n.went_away(view, NOON_UTC, 0)
	assert_array(phone.calls).contains_exactly(["cancel"])
	phone.calls.clear()
	n.came_back()
	assert_array(phone.calls).contains_exactly(["cancel"])

func test_the_question_by_the_guide_and_the_crops() -> void:
	var plots := [_plot("crop_lettuce", "growing", H)]
	assert_str(P0Notify.ask_question(_view(plots))).is_equal(P0Notify.ASK_CROPS)   # legacy / plain: any crop
	assert_str(P0Notify.ask_question(_view([_plot("crop_quick_radish", "growing", H)]))).is_empty()
	assert_str(P0Notify.ask_question(_view([_plot("crop_radish", "sown")]))).is_empty()   # sown, not watered
	var guided := _view(plots)
	guided.guide = {"step": null, "end": "done"}
	assert_str(P0Notify.ask_question(guided)).is_empty()   # through the guide: a Radish must be growing
	guided.plots.append(_plot("crop_radish", "growing", H))
	assert_str(P0Notify.ask_question(guided)).is_equal(P0Notify.ASK_RADISHES)
	guided.guide = {"step": "s4", "end": null}
	assert_str(P0Notify.ask_question(guided)).is_empty()   # still in the guide
	var legacy := _view(plots)
	legacy.guide = {"step": null, "end": "legacy"}
	assert_str(P0Notify.ask_question(legacy)).is_equal(P0Notify.ASK_CROPS)
