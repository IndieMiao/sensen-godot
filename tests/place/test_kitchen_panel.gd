extends GdUnitTestSuite

func _farm(chapter := 3) -> Dictionary:
	return {"clock": {"chapter_index": chapter, "player_day_id": "2026-09-05"}, "wallet": 180,
		"inventory": {"produce": {"R": 1, "L": 3, "C": 3, "H": 2}, "dishes": {"salad": 0, "tea": 0}},
		"engineering": {"reserved": {}}, "requests_done": [], "handbook": [],
		"xp": {"total": 119, "first_recipes": [], "first_harvest_crops": []},
		"residents": {"bistro_owner": {"points": 20, "first_met_day": "2026-09-03", "shared_event_done": false}}}

func _reply(state: Dictionary, version := 2) -> Dictionary:
	return {"status": 200, "json": {"farm_id": "kitchen-test", "version": version, "state": state}}

func _session(state: Dictionary, responses: Array) -> Array:
	var transport := FakeTransport.new(responses)
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = state.duplicate(true)
	session.version = 1
	session.farm_id = "kitchen-test"
	return [session, transport]

func _panel(session: FarmSession, section := "kitchen") -> KitchenPanel:
	var panel := KitchenPanel.new()
	panel.section = section
	panel.setup(session)
	panel.theme = GameUi.theme()
	panel.custom_minimum_size.x = 296
	add_child(auto_free(panel))
	return panel

func _frames() -> void:
	for i in 3: await get_tree().process_frame

func _button(panel: KitchenPanel, name: String) -> Button:
	return panel.find_child(name, true, false) as Button

func _cooked(before: Dictionary, recipe: String) -> Dictionary:
	var after := before.duplicate(true)
	if recipe == "salad":
		after.inventory.produce.C -= 1
		after.inventory.produce.L -= 1
	else:
		after.inventory.produce.H -= 1
	after.inventory.dishes[recipe] += 1
	if not after.xp.first_recipes.has(recipe):
		after.xp.first_recipes.append(recipe)
		after.xp.total += 10
		after.handbook.append({"kind": "first_recipe", "key": recipe, "day": "2026-09-05"})
	return after

func _journal_rows(panel: KitchenPanel) -> Array:
	var rows := []
	for child in panel.content.get_children():
		if child.has_meta("journal_kind"): rows.append(child)
	return rows

func _labels(node: Node) -> String:
	var texts := []
	if node is Label: texts.append(node.text)
	for child in node.get_children(): texts.append(_labels(child))
	return "\n".join(texts)

func test_kitchen_unlock_and_engineering_reservations_control_real_recipe_buttons() -> void:
	var before := _farm(2)
	var pair := _session(before, [])
	var panel := _panel(pair[0])
	await _frames()
	assert_object(_button(panel, "Cook_salad")).is_null()
	pair[0].state.clock.chapter_index = 3
	pair[0].state.engineering.reserved = {"L": 3}
	pair[0].state_changed.emit(pair[0].state, 1)
	await _frames()
	assert_bool(_button(panel, "Cook_salad").disabled).is_true()
	assert_bool(_button(panel, "Cook_tea").disabled).is_false()
	assert_object(_button(panel, "SharedCooking")).is_null()
	assert_int(pair[1].requests.size()).is_equal(0)

func test_first_recipe_uses_command_reply_for_ingredients_xp_and_level_feedback() -> void:
	var before := _farm()
	var pair := _session(before, [_reply(_cooked(before, "salad"))])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Cook_salad").pressed.emit()
	await _frames()
	assert_str(pair[1].last_body().type).is_equal("cook_dish")
	assert_that(pair[1].last_body().payload).is_equal({"recipe": "salad"})
	assert_int(pair[0].state.inventory.produce.C).is_equal(2)
	assert_int(pair[0].state.inventory.produce.L).is_equal(2)
	assert_int(pair[0].state.inventory.dishes.salad).is_equal(1)
	assert_str(panel.message.text).contains("+10 XP")
	assert_str(panel.message.text).contains("Level 4")
	assert_object(_button(panel, "SharedCooking")).is_not_null()
	assert_bool(pair[0].has_meta(KitchenPanel.PENDING_META)).is_false()

func test_repeated_tea_does_not_invent_another_first_recipe_reward() -> void:
	var before := _cooked(_farm(), "tea")
	var pair := _session(before, [_reply(_cooked(before, "tea"))])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Cook_tea").pressed.emit()
	await _frames()
	assert_that(pair[1].last_body().payload).is_equal({"recipe": "tea"})
	assert_int(pair[0].state.inventory.dishes.tea).is_equal(2)
	assert_int(pair[0].state.inventory.produce.H).is_equal(0)
	assert_bool(panel.message.text.contains("XP")).is_false()
	assert_int(pair[0].state.handbook.size()).is_equal(1)

func test_rejected_cooking_keeps_ingredients_and_clears_pending_metadata() -> void:
	var before := _farm()
	var pair := _session(before, [{"status": 422, "json": {"code": "INSUFFICIENT_ITEMS"}}])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Cook_salad").pressed.emit()
	await _frames()
	assert_that(pair[0].state.inventory).is_equal(before.inventory)
	assert_int(pair[0].state.xp.total).is_equal(119)
	assert_bool(pair[0].has_meta(KitchenPanel.PENDING_META)).is_false()
	assert_str(panel.message.text).contains("Not enough")
	assert_object(_button(panel, "Cook_salad")).is_not_null()

func test_lost_repeat_cooking_reply_recovers_after_reopening_without_another_portion() -> void:
	var before := _cooked(_farm(), "salad")
	var after := _cooked(before, "salad")
	var pair := _session(before, [{"error": "timeout"}, {"error": "timeout"}, _reply(after), _reply(after)])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Cook_salad").pressed.emit()
	await _frames()
	assert_object(_button(panel, "RetryKitchen")).is_not_null()
	assert_str(pair[1].requests[0].body.idempotency_key).is_equal(pair[1].requests[1].body.idempotency_key)
	remove_child(panel)
	var reopened := _panel(pair[0])
	await _frames()
	_button(reopened, "RetryKitchen").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(4)
	assert_that(pair[1].requests[2].body).is_equal(pair[1].requests[0].body)
	assert_str(pair[1].requests[3].method).is_equal("GET")
	assert_int(pair[0].state.inventory.dishes.salad).is_equal(2)
	assert_int(pair[0].state.inventory.produce.C).is_equal(1)
	assert_bool(pair[0].has_meta(KitchenPanel.PENDING_META)).is_false()
	assert_bool(reopened.message.text.contains("XP")).is_false()

func test_uncommitted_cooking_retries_the_original_envelope_before_get() -> void:
	var before := _farm()
	var after := _cooked(before, "tea")
	var pair := _session(before, [{"error": "timeout"}, {"error": "timeout"}, _reply(after), _reply(after)])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Cook_tea").pressed.emit()
	await _frames()
	_button(panel, "RetryKitchen").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(4)
	assert_that(pair[1].requests[2].body).is_equal(pair[1].requests[0].body)
	assert_str(pair[1].requests[3].method).is_equal("GET")
	assert_int(pair[0].state.inventory.dishes.tea).is_equal(1)

func test_changed_farm_with_missing_result_never_automatically_recooks() -> void:
	var before := _cooked(_farm(), "salad")
	var changed := _cooked(before, "salad")
	changed.inventory.dishes.salad = 0
	var pair := _session(before, [{"error": "timeout"}, {"error": "timeout"},
		_reply(_cooked(before, "salad")), _reply(changed, 4)])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Cook_salad").pressed.emit()
	await _frames()
	_button(panel, "RetryKitchen").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(4)
	assert_object(_button(panel, "KeepBasket")).is_not_null()
	_button(panel, "KeepBasket").pressed.emit()
	await _frames()
	assert_bool(pair[0].has_meta(KitchenPanel.PENDING_META)).is_false()
	assert_int(pair[0].state.inventory.produce.C).is_equal(1)
	assert_int(pair[1].requests.size()).is_equal(4)

func test_shared_meal_requires_real_salad_and_explicit_final_scene_action() -> void:
	var before := _cooked(_farm(), "salad")
	var after := before.duplicate(true)
	after.residents.bistro_owner.shared_event_done = true
	after.residents.bistro_owner.points = 45
	var pair := _session(before, [_reply(after)])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "SharedCooking").pressed.emit()
	await _frames()
	assert_object(_button(panel, "CompleteShared")).is_null()
	_button(panel, "ContinueShared").pressed.emit()
	await _frames()
	_button(panel, "ContinueShared").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(0)
	_button(panel, "CompleteShared").pressed.emit()
	await _frames()
	assert_str(pair[1].last_body().type).is_equal("attend_shared_event")
	assert_that(pair[1].last_body().payload).is_equal({"event_id": "cooking_together"})
	assert_str(panel.message.text).contains("+25 friendship")
	assert_str(panel.message.text).contains("Familiar")
	assert_object(_button(panel, "SharedCooking")).is_null()
	assert_int(pair[0].state.inventory.dishes.salad).is_equal(1)
	await panel._complete_shared()
	assert_int(pair[1].requests.size()).is_equal(1)

func test_leaving_unfinished_shared_scene_does_not_claim_the_event() -> void:
	var pair := _session(_cooked(_farm(), "salad"), [])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "SharedCooking").pressed.emit()
	await _frames()
	_button(panel, "BackToRecipes").pressed.emit()
	await _frames()
	assert_bool(pair[0].state.residents.bistro_owner.shared_event_done).is_false()
	assert_int(pair[1].requests.size()).is_equal(0)
	assert_object(_button(panel, "SharedCooking")).is_not_null()
	_button(panel, "SharedCooking").pressed.emit()
	await _frames()
	assert_bool(panel.consume_back()).is_true()
	await _frames()
	assert_bool(panel.consume_back()).is_false()
	assert_bool(pair[0].state.residents.bistro_owner.shared_event_done).is_false()
	assert_int(pair[1].requests.size()).is_equal(0)

func test_lost_shared_event_reply_reconciles_the_existing_relationship_reward() -> void:
	var before := _cooked(_farm(), "salad")
	var after := before.duplicate(true)
	after.residents.bistro_owner.shared_event_done = true
	after.residents.bistro_owner.points = 45
	var pair := _session(before, [{"error": "timeout"}, {"error": "timeout"}, _reply(after), _reply(after)])
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "SharedCooking").pressed.emit()
	await _frames()
	_button(panel, "ContinueShared").pressed.emit()
	await _frames()
	_button(panel, "ContinueShared").pressed.emit()
	await _frames()
	_button(panel, "CompleteShared").pressed.emit()
	await _frames()
	_button(panel, "RetryKitchen").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(4)
	assert_that(pair[1].requests[2].body).is_equal(pair[1].requests[0].body)
	assert_str(pair[1].requests[3].method).is_equal("GET")
	assert_int(pair[0].state.residents.bistro_owner.points).is_equal(45)
	assert_str(panel.message.text).contains("+25 friendship")

func test_journal_restores_firsts_chapters_summary_and_level_from_saved_state() -> void:
	var before := _farm(6)
	before.xp = {"total": 301, "first_harvest_crops": ["R", "L"], "first_recipes": ["salad", "tea"]}
	before.handbook = [
		{"kind": "first_harvest", "key": "R", "day": "2026-09-01", "careful": true},
		{"kind": "first_harvest", "key": "L", "day": "2026-09-02"},
		{"kind": "first_recipe", "key": "salad", "day": "2026-09-03"},
		{"kind": "first_recipe", "key": "tea", "day": "2026-09-04"},
		{"kind": "chapter_done", "key": "6", "day": "2026-09-05"},
		{"kind": "week_summary", "key": "first_week", "day": "2026-09-05", "life_priority": true}]
	before.week_summary = {"life_priority": true, "journal_pages": ["shared_harvest", "familiar_faces"]}
	var pair := _session(before, [])
	var panel := _panel(pair[0], "journal")
	await _frames()
	assert_str((panel.find_child("GardenLevel", true, false) as Label).text).is_equal("Level 7 / 301 XP")
	assert_int(_journal_rows(panel).size()).is_equal(6)
	assert_str(_labels(panel)).contains("A little kept for someone")
	assert_str(_labels(panel)).contains("Names beside the gate")
	assert_bool(_labels(panel).contains("shared_harvest")).is_false()
	_button(panel, "Journal_first_recipe").pressed.emit()
	await _frames()
	assert_int(_journal_rows(panel).size()).is_equal(2)
	for row in _journal_rows(panel): assert_str(row.get_meta("journal_kind")).is_equal("first_recipe")
	remove_child(panel)
	var reopened := _panel(pair[0], "journal")
	await _frames()
	assert_int(_journal_rows(reopened).size()).is_equal(6)
	_button(reopened, "Journal_week").pressed.emit()
	await _frames()
	assert_int(_journal_rows(reopened).size()).is_equal(2)
	assert_int(pair[1].requests.size()).is_equal(0)

func test_garden_level_uses_all_seven_thresholds_without_gating_kitchen() -> void:
	var thresholds := [0, 40, 80, 120, 160, 220, 290]
	for index in thresholds.size():
		assert_int(KitchenPanel.level_of(thresholds[index], thresholds)).is_equal(index + 1)
		if index > 0: assert_int(KitchenPanel.level_of(thresholds[index] - 1, thresholds)).is_equal(index)
	var before := _farm()
	before.xp.total = 0
	var pair := _session(before, [])
	var panel := _panel(pair[0])
	await _frames()
	assert_bool(_button(panel, "Cook_salad").disabled).is_false()

func test_unconfirmed_resident_delivery_blocks_new_cooking() -> void:
	var pair := _session(_farm(), [])
	pair[0].set_meta("pending_resident_command", {"type": "give_gift"})
	var panel := _panel(pair[0])
	await _frames()
	_button(panel, "Cook_salad").pressed.emit()
	await _frames()
	assert_int(pair[1].requests.size()).is_equal(0)
	assert_str(panel.message.text).contains("previous visit")
