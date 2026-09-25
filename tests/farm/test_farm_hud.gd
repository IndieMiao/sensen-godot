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
	var farm := await _farm_at_phone_size()
	var top: Rect2 = farm.get_node("HUD/SafeArea/Root/TopBar").get_global_rect()
	assert_object(farm.get_node_or_null("HUD/SafeArea/Root/Joystick")).is_null()
	assert_float(top.size.y).is_less_equal(48.0)
	assert_bool(top.grow(1).encloses(farm.hud._top_right.get_global_rect())).is_true()
	assert_bool(farm.title.get_global_rect().intersects(farm.hud._top_right.get_global_rect())).is_false()
	var goals: Rect2 = farm.hud._overview.get_global_rect()
	assert_bool(goals.intersects(top)).is_false()
	assert_float(goals.size.y).is_less_equal(48.0)
	assert_float(goals.size.x).is_less_equal(farm.hud.size.x - 60.0)
	assert_bool(farm.hud._goals.visible).is_false()
	assert_bool(farm.hud._seed_scroll.visible).is_false()
	assert_bool(farm.hud._work_backing.visible).is_false()
	assert_float(farm.hud._bottom.size.y).is_less_equal(56.0)
	assert_float(farm.hud._bottom.position.y).is_greater(650)
	assert_float(farm._focus_button.get_global_rect().size.x).is_greater_equal(44.0)

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
	var buttons: Array = [f.hud._cta, f.hud._mode_toggle, f.hud._life_button, f._focus_button]
	for id in f.hud._seed_buttons:
		if (f.hud._seed_buttons[id] as Control).is_visible_in_tree():
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

## 天气只报天气。自由种植下浇水是播种后的一次性启动动作，不再随天气变，
## 「今天要排水/遮蔽」说的是一套已经不存在的规则——这条测试守的就是别把它写回来。
func test_condition_chip_reports_weather_without_a_care_instruction() -> void:
	var f := await _farm_at_phone_size()
	f.hud.set_condition("rain")
	assert_str(f.hud._condition.text).is_equal("Rain")
	f.hud.set_condition("wind")
	assert_str(f.hud._condition.text).is_equal("Wind")

func test_single_toggle_switches_both_modes_and_model_sync_does_not_emit_again() -> void:
	var farm := await _farm_at_phone_size()
	var events: Array = []
	farm.hud.work_mode_changed.connect(func(enabled): events.append(enabled))
	assert_int(farm.hud._mode_row.get_children().filter(func(child): return child is Button and child.toggle_mode).size()).is_equal(1)
	assert_bool(farm.hud._mode_toggle.button_pressed).is_false()
	assert_str(farm.hud._mode_toggle.text).is_equal(L10n.text("Walk"))
	farm.hud._mode_toggle.set_pressed(true)
	assert_bool(farm.work_mode).is_true()
	assert_bool(farm.camera_pan.hold_enabled).is_true()
	assert_str(farm.hud._mode_toggle.text).is_equal(L10n.text("Work"))
	farm.hud.set_work_mode(true)
	assert_array(events).is_equal([true])
	farm.hud._mode_toggle.set_pressed(false)
	assert_bool(farm.work_mode).is_false()
	assert_bool(farm.camera_pan.hold_enabled).is_false()
	assert_str(farm.hud._mode_toggle.text).is_equal(L10n.text("Walk"))
	assert_array(events).is_equal([true, false])

func test_mode_label_and_icon_stay_readable_without_growing_the_narrow_dock() -> void:
	var saved_locale := TranslationServer.get_locale()
	TranslationServer.set_locale("zh_CN")
	var farm := await _farm_at_phone_size()
	var safe := farm.get_node("HUD/SafeArea") as SafeAreaMargin
	safe.size = Vector2(328, 800)
	safe.apply_margins(Rect2i(), Vector2i(328, 800), Vector2(328, 800))
	for frame in 4: await get_tree().process_frame
	var toggle: Button = farm.hud._mode_toggle
	assert_str(toggle.text).is_equal("行走")
	assert_int(toggle.vertical_icon_alignment).is_equal(VERTICAL_ALIGNMENT_TOP)
	assert_int(toggle.icon_alignment).is_equal(HORIZONTAL_ALIGNMENT_CENTER)
	assert_int(toggle.get_theme_constant("icon_max_width")).is_equal(20)
	assert_int(toggle.get_theme_font_size("font_size")).is_equal(11)
	assert_vector(toggle.size).is_equal(Vector2(52, 52))
	assert_bool(farm.hud._seed_scroll.visible).is_false()
	assert_bool(farm.camera_pan.hold_enabled).is_false()
	var events: Array = []
	farm.hud.work_mode_changed.connect(func(enabled): events.append(enabled))
	toggle.set_pressed(true)
	for frame in 4: await get_tree().process_frame
	assert_str(toggle.text).is_equal("种地")
	assert_str(toggle.tooltip_text).is_equal("种地模式 · 点此切换行走")
	assert_str(str(toggle.theme_type_variation)).is_equal("ChoiceSelectedButton")
	assert_bool(farm.hud._seed_scroll.visible).is_true()
	assert_bool(farm.work_mode).is_true()
	assert_bool(farm.camera_pan.hold_enabled).is_true()
	assert_vector(toggle.size).is_equal(Vector2(52, 52))
	var screen := Rect2(0, 0, 328, 800)
	assert_bool(screen.encloses(farm.hud._bottom.get_global_rect())).is_true()
	assert_float(farm.hud._bottom.size.y).is_less_equal(122)
	for control in [toggle, farm.hud._cta, farm.hud._life_button]:
		assert_bool(screen.encloses(control.get_global_rect())).is_true()
	toggle.set_pressed(false)
	assert_str(toggle.text).is_equal("行走")
	assert_str(toggle.tooltip_text).is_equal("行走模式 · 点此切换种地")
	assert_str(str(toggle.theme_type_variation)).is_equal("ChoiceButton")
	assert_bool(farm.work_mode).is_false()
	assert_bool(farm.camera_pan.hold_enabled).is_false()
	assert_bool(farm.hud._seed_scroll.visible).is_false()
	assert_array(events).is_equal([true, false])
	TranslationServer.set_locale(saved_locale)
	# The English label is deliberately short enough for the same 52px control.
	TranslationServer.set_locale("en")
	farm.hud.set_work_mode(true)
	for frame in 4: await get_tree().process_frame
	assert_str(toggle.text).is_equal("Work")
	assert_vector(toggle.size).is_equal(Vector2(52, 52))
	assert_bool(screen.encloses(farm.hud._bottom.get_global_rect())).is_true()
	farm.hud.set_work_mode(false)
	for frame in 4: await get_tree().process_frame
	assert_str(toggle.text).is_equal("Walk")
	assert_vector(toggle.size).is_equal(Vector2(52, 52))
	TranslationServer.set_locale(saved_locale)

func test_seed_tray_only_appears_in_farming_mode_and_actions_are_aggregated() -> void:
	var farm := await _farm_at_phone_size()
	assert_bool(farm.hud._seed_scroll.visible).is_false()
	farm._set_work_mode(true)
	await get_tree().process_frame
	assert_bool(farm.hud._seed_scroll.visible).is_true()
	farm._set_work_mode(false)
	assert_bool(farm.hud._seed_scroll.visible).is_false()
	farm.title.pressed.emit()
	await get_tree().process_frame
	assert_bool(farm.hud._quick_actions.visible).is_true()
	assert_bool(GameUi.modal_is_open(farm)).is_true()
	assert_bool(farm.hud._stall.is_visible_in_tree()).is_true()
	assert_object(farm.hud._quick_actions.find_child("GoFishing", true, false)).is_null()
	assert_bool(farm.hud._bottom.visible).is_false()
	farm.hud.close_modal()
	await get_tree().process_frame
	assert_bool(GameUi.modal_is_open(farm)).is_false()
	assert_bool(farm.hud._bottom.visible).is_true()
