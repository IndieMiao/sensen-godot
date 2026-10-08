extends GdUnitTestSuite
## Result moments (SGODOT-233; q(49), §4.8.6): the catch card and the gate cards are RewardMoments without buttons,
## one at a time, folding away after 1.5 s or on a tap; the guide's tips wait while one is up.

const STORE := "user://test_p0_moments_tips.json"

var ui: P0Ui

func _view() -> Dictionary:
	return {
		"energy": {"value": 150, "max": 200}, "coins": 40,
		"skills": {"fishing": {"level": 3, "xp": 100, "floor": 75, "next": 130}, "farming": {"level": 1, "xp": 0, "floor": 0, "next": 40},
			"cooking": {"level": 1, "xp": 0, "floor": 0, "next": 40}},
		"names": {"fish_crucian": "Pond Crucian", "fish_golden_koi": "Golden Koi"},
		"fishing": {"cast_energy": 5, "dex": [{"id": "fish_crucian", "caught": 1}, {"id": "fish_perch", "caught": 0},
			{"id": "fish_golden_koi", "caught": 0}]},
		"gear": {"rods": [{"id": "rod_reed", "name": "Reed Rod", "reach": 3, "level": 3, "price": 80, "owned": false}]},
		"bag": {"capacity": 25, "slots": []},
	}

func before_test() -> void:
	ui = P0Ui.new()
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())

func _moment() -> UiRewardMoment:
	var found := ui.find_children("*", "UiRewardMoment", true, false).filter(func(m): return not m.is_queued_for_deletion())
	return found[0] if not found.is_empty() else null

func test_the_first_catch_is_a_moment_without_buttons() -> void:
	ui.show_catch("fish_crucian", 1, 15, {"city_xp": 10, "energy": 20})
	await await_idle_frame()
	var m := _moment()
	assert_object(m).is_not_null()
	assert_that([m.event, m.item_name, m.rarity_word]).is_equal(["Caught!", "Pond Crucian", "Common"])
	assert_str(m.strip).is_equal("First catch! +15 XP · New city! +10 XP")
	assert_str(m.note).is_equal("Fish-dex 1/3")
	assert_int(m.rewards.size()).is_equal(1)
	assert_str(m.primary).is_equal("")   # no buttons
	assert_str(ui.modal_kind).is_equal("card")

func test_a_level_gate_says_what_it_needs_and_the_real_refund() -> void:
	ui.show_got_away({"fish": "fish_golden_koi", "rarity": 3, "need_level": 4, "refund": 5, "protected_left": 8})
	await await_idle_frame()
	var m := _moment()
	assert_that([m.event, m.item_name, m.tone]).is_equal(["Too strong", "Golden Koi", UiRewardMoment.Tone.NEUTRAL])
	assert_str(m.note).is_equal("Fishing Lv4 needed · You: Lv3 · %d XP to go" % _to_lv4())
	assert_str(P0Logic.refund_line(_view(), {"refund": 5, "protected_left": 8})).is_equal("Energy refunded (8 left today)")
	assert_str(P0Logic.refund_line(_view(), {"refund": 3, "protected_left": 0})).is_equal("+3 Energy back")
	assert_str(P0Logic.refund_line(_view(), {"refund": 3})).is_equal("+3 Energy back")

func _to_lv4() -> int:
	var th: Array = P0Logic.content().get("skills", {}).get("fishing", [])
	return maxi(0, int(th[3]) - 100)

func test_a_rod_gate_names_the_rod_and_its_price() -> void:
	ui.show_got_away({"fish": "fish_golden_koi", "rarity": 3, "refund": 3})
	await await_idle_frame()
	var m := _moment()
	assert_str(m.event).is_equal("Too heavy for your rod")
	assert_str(m.note).is_equal("Reed Rod · Fishing Lv3 · 80 coins")

func test_a_moment_folds_away_after_its_time_or_on_a_tap() -> void:
	ui.show_catch("fish_crucian", 1, 15)
	await await_idle_frame()
	await get_tree().create_timer(P0Ui.MOMENT_AUTO_S + 0.2).timeout
	assert_str(ui.modal_kind).is_equal("")
	ui.show_catch("fish_crucian", 1, 15)
	await await_idle_frame()
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true   # P0Ui.is_tap: the press, as the veil
	_moment().gui_input.emit(tap)
	assert_str(ui.modal_kind).is_equal("")

func test_moments_queue_and_tips_wait_for_them() -> void:
	ui.tips = P0Guide.TipQueue.new({})
	ui.queue_card(func(): ui.show_catch("fish_crucian", 1, 15))
	ui.queue_card(func(): ui.show_got_away({"fish": "fish_golden_koi", "rarity": 3, "refund": 3}))
	await await_idle_frame()
	assert_str(_moment().event).is_equal("Caught!")   # one at a time, in order
	assert_int(ui.tips.moments).is_equal(1)
	assert_bool(ui.tips.request("cast")).is_true()
	assert_str(ui.tips.next()).is_equal("")   # waits while a moment is up (q(49) ⑥)
	ui.close_modal()
	await await_idle_frame()
	await await_idle_frame()
	assert_str(_moment().event).is_equal("Too heavy for your rod")   # the next one comes after
	ui.close_modal()
	await await_idle_frame()
	assert_int(ui.tips.moments).is_equal(0)
	await await_idle_frame()
	assert_str(ui.tips.showing).is_equal("cast")   # P0Ui puts the waiting tip up once the moment is gone
