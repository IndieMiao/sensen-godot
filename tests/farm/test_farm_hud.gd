extends GdUnitTestSuite
## HUD layout and English compatibility; bilingual flows live in tests/localization.

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

var _saved_navigation_pending: bool

func before_test() -> void:
	_saved_navigation_pending = AppRouter._navigation_pending

func after_test() -> void:
	AppRouter._navigation_pending = _saved_navigation_pending

func _farm_at_phone_size() -> Node:
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FIX)})
	add_child(auto_free(scene))
	var safe := scene.get_node("HUD/SafeArea") as SafeAreaMargin
	safe.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	safe.size = Vector2(360, 800)
	safe.apply_margins(Rect2i(), Vector2i(360, 800), Vector2(360, 800))
	scene.hud.set_goals(DayGoals.evaluate({}, {}), 0)
	scene.hud.set_seeds({"seeds": {"R": {"bound": 6}, "L": {"bound": 3}}}, ["R", "L"], true)
	scene.hud.set_cta({"action": "clear", "cells": [], "label": "Clear 9 plots", "enabled": true})
	await get_tree().process_frame
	await get_tree().process_frame
	return scene

func test_status_and_dock_leave_a_clear_playfield_without_a_joystick() -> void:
	var f := await _farm_at_phone_size()
	var top: Rect2 = (f.get_node("HUD/SafeArea/Root/TopBar") as Control).get_global_rect()
	assert_object(f.get_node_or_null("HUD/SafeArea/Root/Joystick")).is_null()
	for name in ["TopRight", "Overview", "BottomBar"]:
		var r: Rect2 = (f.hud.get_node(name) as Control).get_global_rect()
		assert_bool(r.intersects(top)).override_failure_message("%s 与顶栏重叠" % name).is_false()
	var goals: Rect2 = (f.hud.get_node("Overview") as Control).get_global_rect()
	var right: Rect2 = (f.hud.get_node("TopRight") as Control).get_global_rect()
	assert_bool(goals.intersects(right)).override_failure_message("目标卡与右上列重叠").is_false()
	assert_bool(f.hud._goals.visible).is_false()
	assert_float(f.hud._bottom.position.y).is_greater(550)

func test_unknown_command_has_a_visible_single_flight_recovery_control() -> void:
	var f := await _farm_at_phone_size()
	assert_bool(f.hud._reconnect.visible).is_false()
	f.hud.set_connection_recovery(true)
	assert_bool(f.hud._reconnect.visible).is_true()
	assert_bool(f.hud._reconnect.disabled).is_false()
	f.hud.set_connection_recovery(true, true)
	assert_bool(f.hud._reconnect.disabled).is_true()
	f.hud.set_connection_recovery(false)
	assert_bool(f.hud._reconnect.visible).is_false()

func test_buttons_meet_touch_targets_and_stay_on_screen() -> void:
	var f := await _farm_at_phone_size()
	var screen := Rect2(Vector2.ZERO, Vector2(360, 800))
	var buttons: Array = [f.hud._cta, f.hud._stall]
	for id in f.hud._seed_buttons:
		if (f.hud._seed_buttons[id] as Control).visible:
			buttons.append(f.hud._seed_buttons[id])
	for b in buttons:
		var r: Rect2 = (b as Control).get_global_rect()
		assert_bool(r.size.y >= 40.0).override_failure_message("%s 高度 %.1f 太矮" % [b.text, r.size.y]).is_true()
		assert_bool(screen.grow(0.5).encloses(r)).override_failure_message("%s 被挤出屏幕: %s" % [b.text, r]).is_true()
		for line in b.text.split("\n"):
			assert_bool(r.size.x >= b.get_theme_font(&"font").get_string_size(line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size(&"font_size")).x + 8.0
				).override_failure_message("%s 宽 %.1f 装不下自己的标签" % [b.text, r.size.x]).is_true()

func test_hud_retains_english_support() -> void:
	var f := await _farm_at_phone_size()
	var stack: Array = [f.hud]
	var seen := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var text := ""
		if n is Button:
			text = (n as Button).text
		elif n is Label:
			text = (n as Label).text
		if text.is_empty():
			continue
		seen += 1
		for ch in text:
			assert_bool(ch.unicode_at(0) < 0x2E80 or ch in "✓○·—…").override_failure_message(
				"HUD 文案含非英文字符: %s" % text).is_true()
	assert_bool(seen >= 12).is_true()

func test_cta_reflects_bulk_decision() -> void:
	var f := await _farm_at_phone_size()
	f.hud.set_cta({"action": "care", "cells": ["a"], "label": "Water 3 plots", "enabled": true})
	assert_str(f.hud._cta.text).is_equal("Water 3 plots")
	assert_bool(f.hud._cta.disabled).is_false()
	f.hud.set_cta({"action": "", "cells": [], "label": "Crops are growing", "enabled": false})
	assert_bool(f.hud._cta.disabled).is_true()
	var seen := []                       # lambda 按值捕获 int，只能用数组收
	f.hud.cta_pressed.connect(func(): seen.append(1))
	f.hud._cta.pressed.emit()
	assert_int(seen.size()).is_equal(1)

func test_seed_row_shows_counts_hides_locked_and_auto_selects_a_crop_with_seeds() -> void:
	var f := await _farm_at_phone_size()
	f.hud.selected_crop = "R"
	f.hud.set_seeds({"seeds": {"R": {"bound": 0}, "L": {"bound": 3}}}, ["R", "L"], true)
	assert_str((f.hud._seed_buttons["R"] as Button).text).is_equal("Radish\n×0")
	assert_bool((f.hud._seed_buttons["R"] as Button).disabled).is_true()
	assert_bool((f.hud._seed_buttons["C"] as Button).visible).is_false()
	assert_str(f.hud.selected_crop).is_equal("L")
	f.hud.set_seeds({"seeds": {}}, ["R", "L"], false)
	assert_bool(f.hud._seed_row.visible).is_false()

func test_goals_header_counts_and_highlights_the_next_open_goal() -> void:
	var f := await _farm_at_phone_size()
	f.hud.set_goals([{"id": "a", "label": "Clear a plot", "done": true}, {"id": "b", "label": "Till it", "done": false},
		{"id": "c", "label": "Sow", "done": false}], 0)
	assert_str(f.hud._goals_header.text).is_equal("Goals · 1/3")
	var labels: Array = f.hud.goal_labels()
	assert_str(labels[0]).is_equal("○ Till it")
	assert_str(labels[1]).is_equal("○ Sow")
	assert_str(labels[2]).is_equal("✓ Clear a plot")
	f.hud.set_goals([{"id": "a", "label": "x", "done": true}], 2)
	assert_bool(f.hud._goals_header.text.begins_with("Goals · 1/1")).is_true()
	assert_str(f.hud._goals_feedback.text).is_equal("Progress pending")
	assert_bool(f.hud.goal_labels().has("Day complete · see you tomorrow")).is_false()

func test_chapter_completion_and_next_open_feedback_do_not_depend_on_local_checkmarks() -> void:
	var f := await _farm_at_phone_size()
	var goals := [{"id": "rain_care_done", "label": "Care for crops in the rain", "done": true},
		{"id": "request_d1_bistro_lettuce_done", "label": "Complete the bistro's lettuce request", "done": true}]
	var progress := {"title": "A rainy day", "complete": true, "next_open_in_ms": 90_000}
	f.hud.set_goals(goals, 1, progress)
	assert_str(f.hud._goals_title.text).is_equal("Chapter 2 · A rainy day")
	assert_str(f.hud._goals_feedback.text).is_equal("Chapter complete · next in 01:30")
	progress.next_open_in_ms = 0
	f.hud.set_goals(goals, 1, progress)
	assert_str(f.hud._goals_feedback.text).is_equal("Checking next chapter...")
	progress.next_open_in_ms = -1
	f.hud.set_goals(goals, 1, progress)
	assert_str(f.hud._goals_feedback.text).is_equal("Chapter complete")
	progress.last_chapter = true
	f.hud.set_goals(goals, 6, progress)
	assert_str(f.hud._goals_feedback.text).is_equal("Week complete")
	progress.complete = false
	progress.pending = true
	f.hud.set_goals(goals, 6, progress)
	assert_str(f.hud._goals_feedback.text).is_equal("Progress pending")

func test_chapter_goals_replace_old_rows_and_fit_the_existing_exclusive_modal() -> void:
	var f := await _farm_at_phone_size()
	var state := {"clock": {"chapter_index": 3}, "chapters": [{}, {}, {}, {"status": "active", "step_flags": {}}]}
	f.hud.set_goals(DayGoals.evaluate(state, {}), 3, DayGoals.progress(state))
	f.hud.show_modal(f.hud._goals)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(f.hud.goal_labels().size()).is_equal(2)
	assert_str(f.hud.goal_labels()[0]).is_equal("○ Make your first salad together")
	assert_bool(f.hud._bottom.visible).is_false()
	var panel: Rect2 = f.hud._goals.get_global_rect()
	for label in [f.hud._goals_title, f.hud._goals_count, f.hud._goals_feedback]:
		assert_bool(panel.grow(1).encloses(label.get_global_rect())).is_true()
	for row in f.hud._goals_list.get_children():
		assert_bool(row is Button).is_false()
	f.hud.close_modal()
	assert_bool(f.hud._bottom.visible).is_true()

func test_first_open_seven_goal_modal_keeps_all_rows_and_feedback_inside_a_short_screen() -> void:
	var stage := Control.new()
	stage.position = Vector2(16, 16)
	stage.size = Vector2(328, 608)
	stage.theme = GameUi.theme()
	add_child(auto_free(stage))
	var hud := FarmHud.new()
	stage.add_child(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var state := {"clock": {"chapter_index": 0}, "chapters": [{"status": "active", "step_flags": {"farm_created": true}}]}
	hud.set_goals(DayGoals.evaluate(state, {}), 0, DayGoals.progress(state))
	hud.show_modal(hud._goals)
	for frame in 3: await get_tree().process_frame
	var screen := Rect2(Vector2.ZERO, Vector2(360, 640))
	var panel := hud._goals.get_global_rect()
	assert_bool(screen.encloses(panel)).is_true()
	for label in [hud._goals_title, hud._goals_count, hud._goals_feedback]:
		assert_bool(panel.encloses(label.get_global_rect())).is_true()
	var scroll := hud._goals_list.get_parent() as ScrollContainer
	assert_int(hud.goal_labels().size()).is_equal(7)
	for row in hud._goals_list.get_children():
		assert_bool(scroll.get_global_rect().grow(1).encloses(row.get_global_rect())).is_true()

func test_offline_disables_actions_and_shows_the_banner() -> void:
	var f := await _farm_at_phone_size()
	assert_bool((f.hud.get_node("OfflineBanner") as Control).visible).is_false()
	f.hud.set_offline(true)
	assert_bool((f.hud.get_node("OfflineBanner") as Control).visible).is_true()
	assert_bool(f.hud._cta.disabled).is_true()
	assert_bool(f.hud._stall.disabled).is_true()

func test_countdown_helpers() -> void:
	var cells := {"1,1": {"ready_at": 5_000}, "2,1": {"ready_at": 3_000}, "3,1": {"ready_at": null}, "1,2": {}}
	assert_int(FarmHud.next_ripe_ms(cells, 1_000)).is_equal(2_000)
	assert_int(FarmHud.next_ripe_ms(cells, 3_000)).is_equal(0)
	assert_int(FarmHud.next_ripe_ms({"1,1": {"ready_at": null}}, 0)).is_equal(-1)
	assert_str(FarmHud.format_countdown(-1)).is_equal("--:--")
	assert_str(FarmHud.format_countdown(0)).is_equal("ready")
	assert_str(FarmHud.format_countdown(90_000)).is_equal("01:30")
	assert_str(FarmHud.format_countdown(3 * 3600_000 + 25 * 60_000)).is_equal("3h25m")

func test_condition_chip_says_what_to_do_today() -> void:
	var f := await _farm_at_phone_size()
	f.hud.set_condition("rain")
	assert_str(f.hud._condition.text).is_equal("Rain · drain today")
	f.hud.set_condition("wind")
	assert_str(f.hud._condition.text).is_equal("Wind · shelter today")
