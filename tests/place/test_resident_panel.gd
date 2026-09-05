extends GdUnitTestSuite

func _farm(chapter := 1) -> Dictionary:
	var residents := {}
	for id in ResidentCast.ORDER:
		residents[id] = {"points": 0, "first_met_day": null, "talked_day": null,
			"gifts_given": 0, "request_done": false, "shared_event_done": false}
	return {"clock": {"chapter_index": chapter, "player_day_id": "2026-09-05"},
		"wallet": 180, "inventory": {"produce": {"R": 3, "L": 3, "C": 2, "H": 1}, "dishes": {"salad": 2, "tea": 0}},
		"engineering": {"reserved": {}}, "residents": residents, "requests_done": [], "life_choices": {}}

func _reply(state: Dictionary, version := 2) -> Dictionary:
	return {"status": 200, "json": {"farm_id": "resident-test", "version": version, "state": state}}

func _session(state: Dictionary, responses: Array) -> Array:
	var transport := FakeTransport.new(responses)
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = state.duplicate(true)
	session.version = 1
	session.farm_id = "resident-test"
	return [session, transport]

func _panel(session: FarmSession, place := "bistro") -> ResidentPanel:
	var panel := ResidentPanel.new()
	panel.place_id = place
	panel.setup(session)
	panel.theme = GameUi.theme()
	panel.custom_minimum_size.x = 296
	add_child(auto_free(panel))
	return panel

func _frames() -> void:
	for i in 3: await get_tree().process_frame

func _button(panel: ResidentPanel, name: String) -> Button:
	return panel.find_child(name, true, false) as Button

func test_resident_presence_and_fixed_outfits() -> void:
	assert_that(ResidentCast.present("nursery", _farm(0))).is_equal(["nursery_keeper"])
	assert_that(ResidentCast.present("bistro", _farm(0))).is_equal([])
	assert_that(ResidentCast.present("bistro", _farm(3))).is_equal(["nursery_keeper", "bistro_owner"])
	assert_that(ResidentCast.present("courtyard", _farm(4))).is_equal([])
	assert_that(ResidentCast.present("courtyard", _farm(5))).is_equal(["restorer"])
	assert_that(ResidentCast.present("courtyard", _farm(6))).is_equal(ResidentCast.ORDER)
	assert_that(ResidentCast.present("nursery", _farm(6))).is_equal(["nursery_keeper"])
	var outfit := ResidentCast.outfit("nursery_keeper")
	assert_str(outfit.slots[&"cloth"]).is_equal("cloth11")
	assert_bool(outfit.to_json_text() == ResidentCast.outfit("restorer").to_json_text()).is_false()
	for id in ResidentCast.ORDER:
		for part in ResidentCast.outfit(id).slots.values():
			if not str(part).is_empty(): assert_bool(Avatar.catalog.has_part(str(part))).is_true()

func test_dialogue_buttons_send_one_real_talk_and_keep_navigation_local() -> void:
	var before := _farm()
	var after := before.duplicate(true)
	after.residents.bistro_owner.points = 2
	after.residents.bistro_owner.first_met_day = "2026-09-05"
	after.residents.bistro_owner.talked_day = "2026-09-05"
	var pair := _session(before, [_reply(after)])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Talk").pressed.emit()
	await _frames()
	assert_str(pair[1].last_body().type).is_equal("talk_to_resident")
	assert_that(pair[1].last_body().payload).is_equal({"resident_id": "bistro_owner"})
	assert_str(panel.message.text).contains("+2 friendship")
	var first := str((panel.find_child("DialogueLine", true, false) as Label).text)
	_button(panel, "Continue").pressed.emit()
	await _frames()
	assert_str((panel.find_child("DialogueLine", true, false) as Label).text).is_not_equal(first)
	_button(panel, "Previous").pressed.emit()
	await _frames()
	assert_str((panel.find_child("DialogueLine", true, false) as Label).text).is_equal(first)
	_button(panel, "Back").pressed.emit()
	await _frames()
	assert_object(_button(panel, "Talk")).is_not_null()
	assert_int(pair[1].requests.size()).is_equal(1)

func test_day_two_choice_is_discussed_again_without_fabricating_daily_points() -> void:
	var before := _farm(2)
	before.life_choices = {"2": "keep"}
	before.residents.bistro_owner.points = 17
	before.residents.bistro_owner.first_met_day = "2026-09-04"
	before.residents.bistro_owner.talked_day = "2026-09-05"
	var after := before.duplicate(true)
	after.residents.bistro_owner.choice_memories = {"2": "keep"}
	var pair := _session(before, [_reply(after)])
	var panel := _panel(pair[0])
	await _frames()
	assert_str(_button(panel, "Talk").text).contains("harvest")
	_button(panel, "Talk").pressed.emit()
	await _frames()
	assert_str(pair[1].last_body().type).is_equal("talk_to_resident")
	assert_str((panel.find_child("DialogueLine", true, false) as Label).text).contains("kept a lettuce")
	assert_bool(panel.message.text.contains("+2")).is_false()
	assert_str(pair[0].state.residents.bistro_owner.choice_memories["2"]).is_equal("keep")

func test_delivery_excludes_engineering_reservations_and_uses_server_reward() -> void:
	var before := _farm()
	before.engineering.reserved = {"L": 1}
	var after := before.duplicate(true)
	after.engineering.reserved = {}
	after.inventory.produce.L = 0
	after.wallet = 225
	after.requests_done = ["d1_bistro_lettuce"]
	after.residents.bistro_owner.points = 15
	after.residents.bistro_owner.first_met_day = "2026-09-05"
	var pair := _session(before, [_reply(after)])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Request_d1_bistro_lettuce").pressed.emit()
	await _frames()
	assert_bool(_button(panel, "Deliver").disabled).is_true()
	pair[0].state.engineering.reserved = {}
	pair[0].state_changed.emit(pair[0].state, 1)
	await _frames()
	assert_bool(_button(panel, "Deliver").disabled).is_false()
	_button(panel, "Deliver").pressed.emit()
	await _frames()
	assert_that(pair[1].last_body().payload).is_equal({"request_id": "d1_bistro_lettuce"})
	assert_str(panel.message.text).contains("+45 coins")
	assert_str(panel.message.text).contains("+15 friendship")
	await panel._deliver()
	assert_int(pair[1].requests.size()).is_equal(1)

func test_lost_gift_reply_is_reconciled_after_panel_reentry_without_gifting_twice() -> void:
	var before := _farm()
	var after := before.duplicate(true)
	after.inventory.produce.L = 2
	after.residents.bistro_owner.gifts_given = 1
	after.residents.bistro_owner.points = 6
	after.residents.bistro_owner.first_met_day = "2026-09-05"
	var pair := _session(before, [{"error": "timeout"}, {"error": "timeout"}, _reply(after), _reply(after)])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Gifts").pressed.emit()
	await _frames()
	_button(panel, "Give_L").pressed.emit()
	await _frames()
	assert_object(_button(panel, "Retry")).is_not_null()
	assert_int(pair[1].requests.size()).is_equal(2)
	assert_str(pair[1].requests[0].body.idempotency_key).is_equal(pair[1].requests[1].body.idempotency_key)
	remove_child(panel)
	var reopened := _panel(pair[0])
	await _frames()
	_button(reopened, "Retry").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(4)
	assert_that(pair[1].requests[2].body).is_equal(pair[1].requests[0].body)
	assert_str(pair[1].requests[3].method).is_equal("GET")
	assert_int(pair[0].state.inventory.produce.L).is_equal(2)
	assert_bool(pair[0].has_meta(ResidentPanel.PENDING_META)).is_false()
	assert_str((reopened.find_child("DialogueLine", true, false) as Label).text).contains("leaves")

func test_uncommitted_gift_retries_the_original_envelope_before_get() -> void:
	var before := _farm()
	var after := before.duplicate(true)
	after.inventory.produce.L = 2
	after.residents.bistro_owner.gifts_given = 1
	after.residents.bistro_owner.points = 6
	var pair := _session(before, [{"error": "timeout"}, {"error": "timeout"}, _reply(after), _reply(after)])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Gifts").pressed.emit()
	await _frames()
	_button(panel, "Give_L").pressed.emit()
	await _frames()
	_button(panel, "Retry").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(4)
	assert_that(pair[1].requests[2].body).is_equal(pair[1].requests[0].body)
	assert_str(pair[1].requests[3].method).is_equal("GET")
	assert_int(pair[0].state.residents.bistro_owner.gifts_given).is_equal(1)

func test_lost_request_reply_recovers_completed_delivery_without_resubmitting() -> void:
	var before := _farm()
	var after := before.duplicate(true)
	after.inventory.produce.L = 0
	after.wallet = 225
	after.requests_done = ["d1_bistro_lettuce"]
	after.residents.bistro_owner.points = 15
	var pair := _session(before, [{"error": "timeout"}, {"error": "timeout"}, _reply(after), _reply(after)])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Request_d1_bistro_lettuce").pressed.emit()
	await _frames()
	_button(panel, "Deliver").pressed.emit()
	await _frames()
	_button(panel, "Retry").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(4)
	assert_that(pair[1].requests[2].body).is_equal(pair[1].requests[0].body)
	assert_str(pair[1].requests[3].method).is_equal("GET")
	assert_int(pair[0].state.wallet).is_equal(225)
	assert_that(pair[0].state.requests_done).is_equal(["d1_bistro_lettuce"])
	assert_str(panel.message.text).contains("+45 coins")
	_button(panel, "Back").pressed.emit()
	await _frames()
	assert_object(_button(panel, "Request_d1_bistro_lettuce")).is_null()

func test_gift_rejection_keeps_inventory_and_returns_to_the_gift_options() -> void:
	var before := _farm()
	var pair := _session(before, [{"status": 422, "json": {"code": "INSUFFICIENT_ITEMS"}}])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Gifts").pressed.emit()
	await _frames()
	_button(panel, "Give_L").pressed.emit()
	await _frames()
	assert_int(pair[0].state.inventory.produce.L).is_equal(3)
	assert_int(pair[0].state.residents.bistro_owner.gifts_given).is_equal(0)
	assert_object(_button(panel, "Give_L")).is_not_null()
	assert_bool(pair[0].has_meta(ResidentPanel.PENDING_META)).is_false()
	assert_str(panel.message.text).contains("Not enough")

func test_gift_limit_and_familiarity_require_authoritative_facts() -> void:
	var before := _farm()
	before.residents.bistro_owner.gifts_given = 2
	before.residents.bistro_owner.points = 89
	before.residents.bistro_owner.first_met_day = "2026-09-05"
	var pair := _session(before, [])
	var panel := _panel(pair[0])
	await _frames()
	assert_bool(_button(panel, "Gifts").disabled).is_true()
	assert_str(ResidentCast.relationship_stage(before.residents.bistro_owner)).is_equal("Acquainted")
	before.residents.bistro_owner.shared_event_done = true
	assert_str(ResidentCast.relationship_stage(before.residents.bistro_owner)).is_equal("Familiar")
	assert_int(pair[1].requests.size()).is_equal(0)

func test_restorer_request_consumes_two_prepared_dishes() -> void:
	var before := _farm(5)
	var after := before.duplicate(true)
	after.inventory.dishes.salad = 0
	after.wallet = 250
	after.requests_done = ["d5_restorer_salads"]
	var pair := _session(before, [_reply(after)])
	var panel := _panel(pair[0], "courtyard")
	await _frames()
	_button(panel, "Request_d5_restorer_salads").pressed.emit()
	await _frames()
	_button(panel, "Deliver").pressed.emit()
	await _frames()
	assert_str(pair[1].last_body().type).is_equal("submit_request")
	assert_str(pair[1].last_body().payload.request_id).is_equal("d5_restorer_salads")
	assert_int(pair[0].state.inventory.dishes.salad).is_equal(0)
