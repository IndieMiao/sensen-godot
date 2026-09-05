extends GdUnitTestSuite

func _farm(chapter := 1) -> Dictionary:
	var chapters := []
	for index in 7: chapters.append({"status": "active" if index == chapter else "locked", "step_flags": {}})
	return {"clock": {"chapter_index": chapter, "player_day_id": "2026-09-05", "field_condition": "rain"},
		"wallet": 305, "xp": {"total": 301, "first_recipes": []}, "chapters": chapters,
		"inventory": {"produce": {"R": 1, "L": 1, "C": 2, "H": 4}, "dishes": {"salad": 0, "tea": 0}},
		"engineering": {"reserved": {}, "submitted": {}}, "nursery": {"stage": "derelict", "appearance": "a"},
		"life_choices": {}, "requests_done": [], "growth_choice": {"intent": null},
		"residents": {"nursery_keeper": {"points": 31, "first_met_day": "2026-09-01", "shared_event_done": false},
			"bistro_owner": {"points": 62, "first_met_day": "2026-09-02", "shared_event_done": false},
			"restorer": {"points": 31, "first_met_day": "2026-09-04", "shared_event_done": false}}}

func _ready_finale() -> Dictionary:
	var state := _farm(6)
	state.engineering.submitted = {"C": 2, "H": 4}
	state.nursery.stage = "built"
	state.life_choices = {"1": "gift", "2": "gift", "3": "gift", "4": "keep", "5": "sold", "6": "keep"}
	return state

func _summary(life := true) -> Dictionary:
	return {"id": "first_week", "completed_day": "2026-09-05", "completed_at": 123000,
		"life_priority": life, "life_choice_count": 5 if life else 0, "choices": {},
		"photo_variant": "personalized" if life else "standard",
		"journal_pages": ["shared_harvest", "familiar_faces"] if life else [],
		"next_week_clue": "resident_seed_exchange" if life else "nursery_next_stage",
		"wallet": 305 if life else 376, "xp": 301, "level": 7, "growth_choice": "tool",
		"nursery": {"stage": "built", "appearance": "a"}, "relationships": {
			"nursery_keeper": {"points": 56, "stage": "familiar"},
			"bistro_owner": {"points": 62, "stage": "familiar"},
			"restorer": {"points": 31, "stage": "acquainted"}}}

func _finished(before: Dictionary, life := true) -> Dictionary:
	var state := before.duplicate(true)
	state.residents.nursery_keeper.shared_event_done = true
	state.residents.nursery_keeper.points = 56
	state.chapters[6].status = "done"
	state.chapters[6].step_flags.shared_scene_done = true
	state.week_summary = _summary(life)
	return state

func _reply(state: Dictionary, version := 2) -> Dictionary:
	return {"status": 200, "json": {"farm_id": "events-test", "version": version, "state": state}}

func _session(state: Dictionary, responses: Array) -> Array:
	var transport := FakeTransport.new(responses)
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = state.duplicate(true)
	session.version = 1
	session.farm_id = "events-test"
	return [session, transport]

func _panel(session: FarmSession, place := "courtyard") -> EventsPanel:
	var panel := EventsPanel.new()
	panel.place_id = place
	panel.setup(session)
	panel.theme = GameUi.theme()
	panel.custom_minimum_size.x = 296
	add_child(auto_free(panel))
	return panel

func _frames() -> void:
	for i in 3: await get_tree().process_frame

func _button(panel: EventsPanel, name: String) -> Button:
	return panel.find_child(name, true, false) as Button

func _labels(node: Node) -> String:
	var texts := []
	if node is Label: texts.append(node.text)
	for child in node.get_children(): texts.append(_labels(child))
	return "\n".join(texts)

func _read_gathering(panel: EventsPanel) -> void:
	_button(panel, "StartGathering").pressed.emit()
	await _frames()
	for index in 3:
		_button(panel, "ContinueEvent").pressed.emit()
		await _frames()

func test_exactly_five_authored_events_unlock_by_chapter() -> void:
	var pair := _session(_farm(0), [])
	var panel := _panel(pair[0])
	await _frames()
	assert_int(panel._data.events.size()).is_equal(5)
	for event in panel._data.events: assert_bool(_button(panel, "Event_%s" % event.id).disabled).is_true()
	panel.open_event("our_first_meal")
	await _frames()
	assert_str(panel._view).is_equal("home")
	assert_int(pair[1].requests.size()).is_equal(0)

func test_rain_event_routes_to_missing_real_facts_without_granting_progress() -> void:
	var pair := _session(_farm(1), [])
	var panel := _panel(pair[0], "nursery")
	var destinations := []
	panel.navigation_requested.connect(func(destination, tab): destinations.append([destination, tab]))
	await _frames()
	_button(panel, "Event_rain_at_the_nursery").pressed.emit()
	await _frames()
	assert_bool(panel.fact("rain_care")).is_false()
	_button(panel, "NextEventStep").pressed.emit()
	assert_that(destinations).is_equal([["farm", ""]])
	pair[0].state.chapters[1].step_flags.rain_care_done = true
	pair[0].state_changed.emit(pair[0].state, 1)
	await _frames()
	_button(panel, "NextEventStep").pressed.emit()
	assert_that(destinations[1]).is_equal(["bistro", "people"])
	assert_int(pair[1].requests.size()).is_equal(0)
	assert_bool(pair[0].state.requests_done.is_empty()).is_true()

func test_day_two_scene_only_remembers_the_acknowledged_choice() -> void:
	var before := _farm(2)
	before.life_choices = {"2": "sold"}
	var pair := _session(before, [])
	var panel := _panel(pair[0], "bistro")
	await _frames()
	panel.open_event("a_harvest_remembered")
	await _frames()
	assert_bool(panel.fact("harvest_choice")).is_true()
	assert_bool(panel.fact("choice_remembered")).is_false()
	pair[0].state.residents.bistro_owner.choice_memories = {"2": "gift"}
	assert_bool(panel.fact("choice_remembered")).is_false()
	pair[0].state.residents.bistro_owner.choice_memories = {"2": "sold"}
	pair[0].state_changed.emit(pair[0].state, 1)
	await _frames()
	_button(panel, "ReadScene").pressed.emit()
	await _frames()
	assert_str(_labels(panel)).contains("sold your lettuce")
	assert_int(pair[1].requests.size()).is_equal(0)

func test_first_salad_does_not_prove_shared_meal_or_nursery_request() -> void:
	var before := _farm(3)
	before.xp.first_recipes = ["salad"]
	var pair := _session(before, [])
	var panel := _panel(pair[0], "bistro")
	await _frames()
	assert_bool(panel.fact("first_salad")).is_true()
	assert_bool(panel.fact("shared_meal")).is_false()
	assert_bool(panel.fact("nursery_request")).is_false()
	panel.open_event("our_first_meal")
	await _frames()
	assert_str(_button(panel, "NextEventStep").text).is_equal("Set the table together")

func test_visit_story_uses_return_fact_and_never_awards_a_visit() -> void:
	var before := _farm(4)
	before.nursery.stage = "cleared"
	var pair := _session(before, [])
	var panel := _panel(pair[0], "nursery")
	var destinations := []
	panel.navigation_requested.connect(func(destination, tab): destinations.append([destination, tab]))
	await _frames()
	panel.open_event("beyond_the_gate")
	await _frames()
	_button(panel, "NextEventStep").pressed.emit()
	assert_that(destinations).is_equal([["map", "farms"]])
	assert_bool(panel.fact("visit_return")).is_false()
	assert_int(pair[0].state.wallet).is_equal(305)
	assert_int(pair[1].requests.size()).is_equal(0)
	pair[0].state.chapters[4].step_flags.visit_tutorial_completed = true
	pair[0].state_changed.emit(pair[0].state, 1)
	await _frames()
	assert_str(_button(panel, "NextEventStep").text).is_equal("Bring project materials")

func test_wind_event_continues_to_final_chapter_without_hidden_growth_purchase() -> void:
	var before := _farm(5)
	before.chapters[5].step_flags.wind_care_done = true
	before.growth_choice.intent = "field"
	var pair := _session(before, [])
	var panel := _panel(pair[0])
	await _frames()
	panel.open_event("wind_and_opening")
	await _frames()
	assert_str(panel._event_status(panel._event())).is_equal("Continues in Chapter 7")
	assert_object(_button(panel, "StartGathering")).is_null()
	assert_int(pair[1].requests.size()).is_equal(0)
	assert_int(pair[0].state.wallet).is_equal(305)

func test_finale_requires_both_exact_project_quota_and_built_entrance() -> void:
	var before := _ready_finale()
	before.engineering.submitted.H = 3
	var pair := _session(before, [])
	var panel := _panel(pair[0])
	await _frames()
	assert_object(_button(panel, "StartGathering")).is_null()
	assert_object(_button(panel, "FinishProject")).is_not_null()
	panel._start_gathering()
	assert_str(panel._view).is_equal("event")
	pair[0].state.engineering.submitted.H = 4
	pair[0].state.nursery.stage = "cleared"
	pair[0].state_changed.emit(pair[0].state, 1)
	await _frames()
	assert_object(_button(panel, "StartGathering")).is_null()
	assert_int(pair[1].requests.size()).is_equal(0)

func test_nursery_entrance_routes_gathering_to_actual_courtyard() -> void:
	var pair := _session(_ready_finale(), [])
	var panel := _panel(pair[0], "nursery")
	var destinations := []
	panel.navigation_requested.connect(func(destination, tab): destinations.append([destination, tab]))
	await _frames()
	_button(panel, "MeetInCourtyard").pressed.emit()
	assert_that(destinations).is_equal([["courtyard", "events"]])
	assert_object(_button(panel, "StartGathering")).is_null()
	assert_int(pair[1].requests.size()).is_equal(0)

func test_gathering_writes_only_after_final_dialogue_and_uses_real_summary() -> void:
	var before := _ready_finale()
	var pair := _session(before, [_reply(_finished(before))])
	var panel := _panel(pair[0])
	await _frames()
	await _read_gathering(panel)
	assert_int(pair[1].requests.size()).is_equal(0)
	_button(panel, "CompleteGathering").pressed.emit()
	await _frames()
	assert_str(pair[1].last_body().type).is_equal("attend_shared_event")
	assert_that(pair[1].last_body().payload).is_equal({"event_id": "nursery_activity"})
	assert_str(panel.message.text).contains("+25 friendship")
	assert_str(_labels(panel)).contains("A week of sharing")
	assert_str(_labels(panel)).contains("A little kept for someone")
	assert_str(_labels(panel)).contains("Names beside the gate")
	assert_bool(_labels(panel).contains("shared_harvest")).is_false()
	assert_object(_button(panel, "TakePhoto")).is_not_null()
	assert_bool(pair[0].has_meta(EventsPanel.PENDING_META)).is_false()

func test_completed_gathering_without_last_choice_does_not_fabricate_summary() -> void:
	var before := _ready_finale()
	before.residents.nursery_keeper.shared_event_done = true
	before.life_choices.erase("6")
	var pair := _session(before, [])
	var panel := _panel(pair[0])
	await _frames()
	assert_object(_button(panel, "LastHarvestChoice")).is_not_null()
	assert_object(_button(panel, "TakePhoto")).is_null()
	assert_bool(pair[0].state.has("week_summary")).is_false()
	assert_int(pair[1].requests.size()).is_equal(0)

func test_lost_gathering_reply_recovers_without_duplicate_relationship_reward() -> void:
	var before := _ready_finale()
	var pair := _session(before, [{"error": "timeout"}, {"error": "timeout"},
		_reply(_finished(before)), _reply(_finished(before))])
	var panel := _panel(pair[0])
	await _frames()
	await _read_gathering(panel)
	_button(panel, "CompleteGathering").pressed.emit()
	await _frames()
	assert_object(_button(panel, "RetryGathering")).is_not_null()
	remove_child(panel)
	var reopened := _panel(pair[0])
	await _frames()
	_button(reopened, "RetryGathering").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(4)
	assert_that(pair[1].requests[2].body).is_equal(pair[1].requests[0].body)
	assert_str(pair[1].requests[3].method).is_equal("GET")
	assert_int(pair[0].state.residents.nursery_keeper.points).is_equal(56)
	assert_object(_button(reopened, "TakePhoto")).is_not_null()

func test_selling_ending_is_valid_and_photo_signal_uses_frozen_server_branch() -> void:
	var before := _finished(_ready_finale(), false)
	var pair := _session(before, [])
	var panel := _panel(pair[0])
	var photos := []
	panel.photo_requested.connect(func(summary): photos.append(summary))
	await _frames()
	assert_str(_labels(panel)).contains("A week of growing")
	assert_bool(_labels(panel).contains("A little kept for someone")).is_false()
	assert_str(_labels(panel)).contains("376 coins")
	_button(panel, "TakePhoto").pressed.emit()
	assert_int(photos.size()).is_equal(1)
	assert_str(photos[0].photo_variant).is_equal("standard")
	photos[0].wallet = 0
	assert_int(pair[0].state.week_summary.wallet).is_equal(376)
	assert_int(pair[1].requests.size()).is_equal(0)

func test_back_leaves_dialogue_before_leaving_event_without_writing_facts() -> void:
	var pair := _session(_ready_finale(), [])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "StartGathering").pressed.emit()
	await _frames()
	assert_bool(panel.consume_back()).is_true()
	await _frames()
	assert_object(_button(panel, "StartGathering")).is_not_null()
	assert_bool(panel.consume_back()).is_true()
	await _frames()
	assert_bool(panel.consume_back()).is_false()
	assert_bool(pair[0].state.residents.nursery_keeper.shared_event_done).is_false()
	assert_int(pair[1].requests.size()).is_equal(0)

func test_another_uncertain_transaction_blocks_gathering_without_creating_a_pending_cycle() -> void:
	var pair := _session(_ready_finale(), [])
	pair[0].set_meta("pending_economy_command", {"type": "resolve_life_choice"})
	var panel := _panel(pair[0])
	await _frames()
	await _read_gathering(panel)
	_button(panel, "CompleteGathering").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(0)
	assert_bool(pair[0].has_meta(EventsPanel.PENDING_META)).is_false()
	assert_bool(pair[0].has_meta("pending_economy_command")).is_true()
	assert_bool(pair[0].state.residents.nursery_keeper.shared_event_done).is_false()
