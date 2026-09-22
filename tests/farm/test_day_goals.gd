extends GdUnitTestSuite
const CHAPTERS := "res://assets/farm/data/chapters.json"

func _state(index := 0, flags: Dictionary = {}) -> Dictionary:
	var chapters := []
	for chapter in 7:
		chapters.append({"status": "active" if chapter == index else "locked", "step_flags": flags.duplicate() if chapter == index else {}})
	return {"clock": {"chapter_index": index, "field_condition": "sunny"}, "chapters": chapters,
		"xp": {"tilled_total": 0, "first_harvest_crops": []}, "sales_facts": {}}

func _goal(goals: Array, id: String) -> Dictionary:
	for goal in goals:
		if str(goal.id) == id:
			return goal
	assert_bool(false).override_failure_message("Missing goal %s" % id).is_true()
	return {"id": id, "label": "", "done": false}




func test_d1_to_d6_use_their_own_exact_minimum_facts_and_ignore_other_chapters() -> void:
	var definitions: Array = (JSON.parse_string(FileAccess.get_file_as_string(CHAPTERS)) as Dictionary).chapters
	for index in range(1, definitions.size()):
		var facts: Array = definitions[index].min_facts
		var state := _state(index, {str(facts[0]): true})
		state.chapters[0] = {"status": "done", "step_flags": {"farm_created": true, "first_harvest": true}}
		var goals := DayGoals.evaluate(state, {"old": {"state": "growing"}})
		assert_int(goals.size()).is_equal(facts.size())
		for fact in facts:
			assert_bool(_goal(goals, str(fact)).done).is_equal(fact == facts[0])
		assert_int(DayGoals.done_count(goals)).is_equal(1)

func test_missing_or_non_boolean_fact_is_not_an_authoritative_completion() -> void:
	var legacy := {"clock": {"chapter_index": 0}, "xp": {"first_harvest_crops": ["R"]}}
	assert_bool(_goal(DayGoals.evaluate(legacy, {"old": {"state": "growing"}}), "first_harvest").done).is_false()
	for value in [false, "true", 1, null]:
		var state := _state(0, {"first_harvest": value})
		state.chapters[0].status = "done"
		assert_bool(_goal(DayGoals.evaluate(state, {}), "first_harvest").done).is_false()

func test_unknown_chapter_does_not_fall_back_to_the_first_day_checklist() -> void:
	assert_array(DayGoals.evaluate({"clock": {"chapter_index": 12}}, {})).is_empty()


func test_completion_requires_both_server_status_and_all_minimum_facts() -> void:
	var state := _state(0, {"farm_created": true, "first_harvest": true})
	assert_bool(DayGoals.progress(state).complete).is_false()
	state.chapters[0].status = "done"
	assert_bool(DayGoals.progress(state).complete).is_true()
	state.chapters[0].step_flags.erase("first_harvest")
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
