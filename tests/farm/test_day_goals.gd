extends GdUnitTestSuite
const CHAPTERS := "res://assets/farm/data/chapters.json"

func _state(index := 0, flags: Dictionary = {}) -> Dictionary:
	var chapters := []
	for chapter in 7:
		chapters.append({"status": "active" if chapter == index else "locked", "step_flags": flags.duplicate() if chapter == index else {}})
	return {"clock": {"chapter_index": index, "field_condition": "sunny"}, "chapters": chapters,
		"xp": {"first_clear_cells": [], "first_harvest_crops": []}, "sales_facts": {}}

func _goal(goals: Array, id: String) -> Dictionary:
	for goal in goals:
		if str(goal.id) == id:
			return goal
	assert_bool(false).override_failure_message("Missing goal %s" % id).is_true()
	return {"id": id, "label": "", "done": false}

func test_d0_shows_three_required_facts_and_four_farming_steps_without_a_sale_gate() -> void:
	var goals := DayGoals.evaluate(_state(0, {"farm_created": true}), {"a": {"state": "wild"}})
	assert_int(goals.size()).is_equal(7)
	assert_bool(_goal(goals, "farm_created").done).is_true()
	assert_bool(_goal(goals, "first_harvest").done).is_false()
	assert_bool(_goal(goals, "next_batch_sown_and_cared").done).is_false()
	assert_int(DayGoals.done_count(goals)).is_equal(1)
	for goal in goals:
		assert_bool(str(goal.id) in ["sell", "next", "harvest"]).is_false()

func test_d0_micro_steps_follow_plot_states_but_do_not_confirm_required_facts() -> void:
	var state := _state(0, {"farm_created": true})
	for stage in ["cleared", "tilled", "sown", "growing"]:
		var goals := DayGoals.evaluate(state, {"a": {"state": stage}})
		assert_bool(_goal(goals, "clear").done).is_true()
		assert_bool(_goal(goals, "till").done).is_equal(stage in ["tilled", "sown", "growing"])
		assert_bool(_goal(goals, "sow").done).is_equal(stage in ["sown", "growing"])
		assert_bool(_goal(goals, "care").done).is_equal(stage == "growing")
		assert_bool(_goal(goals, "first_harvest").done).is_false()
		assert_bool(_goal(goals, "next_batch_sown_and_cared").done).is_false()

func test_old_growing_crop_after_first_harvest_cannot_complete_the_next_batch() -> void:
	var state := _state(0, {"farm_created": true, "first_harvest": true})
	state.xp.first_harvest_crops = ["R"]
	state.sales_facts = {"0": {"R": 1}}
	var cells := {"harvested": {"state": "tilled"}, "old": {"state": "growing", "sown_at": 1}}
	var goals := DayGoals.evaluate(state, cells)
	assert_bool(_goal(goals, "first_harvest").done).is_true()
	assert_bool(_goal(goals, "next_batch_sown_and_cared").done).is_false()
	state.chapters[0].step_flags.next_batch_sown_and_cared = true
	assert_bool(_goal(DayGoals.evaluate(state, {}), "next_batch_sown_and_cared").done).is_true()

func test_d1_to_d6_use_their_own_exact_minimum_facts_and_ignore_other_chapters() -> void:
	var definitions: Array = (JSON.parse_string(FileAccess.get_file_as_string(CHAPTERS)) as Dictionary).chapters
	for index in range(1, definitions.size()):
		var facts: Array = definitions[index].min_facts
		var state := _state(index, {str(facts[0]): true})
		state.chapters[0] = {"status": "done", "step_flags": {"farm_created": true, "first_harvest": true, "next_batch_sown_and_cared": true}}
		var goals := DayGoals.evaluate(state, {"old": {"state": "growing"}})
		assert_int(goals.size()).is_equal(facts.size())
		for fact in facts:
			assert_bool(_goal(goals, str(fact)).done).is_equal(fact == facts[0])
		assert_int(DayGoals.done_count(goals)).is_equal(1)

func test_missing_or_non_boolean_fact_is_not_an_authoritative_completion() -> void:
	var legacy := {"clock": {"chapter_index": 0}, "xp": {"first_harvest_crops": ["R"]}}
	assert_bool(_goal(DayGoals.evaluate(legacy, {"old": {"state": "growing"}}), "next_batch_sown_and_cared").done).is_false()
	for value in [false, "true", 1, null]:
		var state := _state(0, {"next_batch_sown_and_cared": value})
		state.chapters[0].status = "done"
		assert_bool(_goal(DayGoals.evaluate(state, {}), "next_batch_sown_and_cared").done).is_false()

func test_unknown_chapter_does_not_fall_back_to_the_first_day_checklist() -> void:
	assert_array(DayGoals.evaluate({"clock": {"chapter_index": 12}}, {})).is_empty()

func test_care_label_follows_weather() -> void:
	var state := _state()
	state.clock.field_condition = "rain"
	assert_str(_goal(DayGoals.evaluate(state, {}), "care").label).is_equal("Drain it")

func test_completion_requires_both_server_status_and_all_minimum_facts() -> void:
	var state := _state(0, {"farm_created": true, "first_harvest": true, "next_batch_sown_and_cared": true})
	assert_bool(DayGoals.progress(state).complete).is_false()
	state.chapters[0].status = "done"
	assert_bool(DayGoals.progress(state).complete).is_true()
	state.chapters[0].step_flags.erase("next_batch_sown_and_cared")
	assert_bool(DayGoals.progress(state).complete).is_false()
	assert_bool(DayGoals.progress(state).pending).is_true()

func test_next_open_countdown_uses_authoritative_time_and_not_a_fixed_day_length() -> void:
	var state := _state(1, {"rain_care_done": true, "request_d1_bistro_lettuce_done": true})
	state.chapters[1].status = "done"
	var derived := {"chapter_index": 1, "next_chapter_opens_at": 187_000}
	assert_int(DayGoals.progress(state, derived, 1_000).next_open_in_ms).is_equal(186_000)
	assert_int(DayGoals.progress(state, derived, 200_000).next_open_in_ms).is_equal(0)
	assert_int(DayGoals.progress(state, {}, 1_000).next_open_in_ms).is_equal(-1)
	derived.chapter_index = 2
	assert_int(DayGoals.progress(state, derived, 1_000).next_open_in_ms).is_equal(-1)

func test_final_chapter_is_complete_without_a_fictitious_eighth_chapter() -> void:
	var state := _state(6, {"engineering_quota_complete": true, "shared_scene_done": true})
	state.chapters[6].status = "done"
	var progress := DayGoals.progress(state, {"next_chapter_opens_at": 10000}, 1000)
	assert_bool(progress.complete).is_true()
	assert_bool(progress.last_chapter).is_true()
	assert_int(progress.next_open_in_ms).is_equal(-1)
