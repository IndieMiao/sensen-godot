extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0, "last_effective_now": 1000}, "wallet": 80, "tools": {"row_tool": false},
		"inventory": {"produce": {}, "dishes": {}, "seeds": {"R": {"bound": 2}, "L": {"bound": 2}}},
		"engineering": {"reserved": {}}, "cells": {}, "residents": {}, "nursery": {}, "character": {"version": 1, "buffs": []},
		"bag": {"version": 2, "sequence": 8, "capacity": 24, "slots": [], "overflow": [], "equipped": {"main_hand": null, "fishing_rod": null, "ring_1": null, "ring_2": null, "necklace": null, "gloves": null}},
		"journey": {"version": 1, "facts": ["met_nursery", "met_bistro", "shared_meal", "workbench", "planter_crafted", "side_path"],
			"unlocks": ["bistro", "kitchen", "tea", "crafting", "crop_C", "crop_H"], "wood": 0, "materials": {}, "completed": [],
			"workshop": {"sequence": 0, "stock": {}, "displays": {}}, "exploration": {"round": 0, "collected": []},
			"opportunities": {"nursery": {"sequence": 3, "variant": 0, "accepted": false},
				"bistro": {"sequence": 5, "variant": 2, "accepted": false}, "restorer": {"sequence": 7, "variant": 2, "accepted": false}}}}

func _reply(state: Dictionary, version := 2) -> Dictionary:
	return {"status": 200, "json": {"outcome": "applied", "version": version, "state": state, "events": []}}

func _settle(frames := 4) -> void:
	for frame in frames: await get_tree().process_frame

func after_test() -> void:
	await _settle()

func _board(state: Dictionary, responses: Array = []) -> Array:
	var transport := FakeTransport.new(responses)
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = state
	session.version = 1
	var stage := Control.new()
	stage.size = Vector2(360, 640)
	add_child(auto_free(stage))
	var sheet := BagSheet.new()
	sheet.setup(session)
	stage.add_child(sheet)
	# These tests assert emitted destinations; AppRouter navigation is covered separately.
	for connection in sheet.active.goal_requested.get_connections():
		sheet.active.goal_requested.disconnect(connection.callable)
	sheet.open("requests")
	return [sheet.active, session, transport, sheet]

func _button(panel: Node, id: String) -> Button:
	return panel.find_child(id, true, false) as Button

func test_board_compares_three_requests_and_accepting_preserves_the_page_and_other_acceptances() -> void:
	var initial := _state()
	var first := initial.duplicate(true)
	first.journey.opportunities.nursery.accepted = true
	first.journey.tracked_opportunity = {"slot": "nursery", "sequence": 3}
	var second := first.duplicate(true)
	second.journey.opportunities.bistro.accepted = true
	second.journey.tracked_opportunity = {"slot": "bistro", "sequence": 5}
	var pair := _board(initial, [_reply(first), _reply(second, 3)])
	var panel: BagPanel = pair[0]
	var goals := []
	panel.goal_requested.connect(func(goal): goals.append(goal))
	await _settle()
	for slot in JourneyRequests.SLOTS: assert_object(_button(panel, "AcceptRequest_" + slot)).is_not_null()
	_button(panel, "AcceptRequest_nursery").pressed.emit()
	await _settle()
	_button(panel, "AcceptRequest_bistro").pressed.emit()
	await _settle()
	assert_str(panel.page).is_equal("requests")
	assert_array(goals).is_empty()
	assert_bool(JourneyRequests.accepted(pair[1].state, "nursery")).is_true()
	assert_bool(JourneyRequests.accepted(pair[1].state, "bistro")).is_true()
	assert_str(JourneyRequests.tracked(pair[1].state).slot).is_equal("bistro")
	assert_int(int(pair[2].requests[0].body.payload.sequence)).is_equal(3)
	assert_int(int(pair[2].requests[1].body.payload.sequence)).is_equal(5)
	assert_str(pair[2].last_body().type).is_equal("accept_opportunity")

func test_two_ready_requests_keep_the_current_tracking_visible_and_untracking_preserves_acceptance() -> void:
	var initial := _state()
	initial.inventory.produce.L = 2
	initial.inventory.dishes.vegetable_soup = 1
	initial.journey.opportunities.nursery.accepted = true
	initial.journey.opportunities.bistro.accepted = true
	initial.journey.tracked_opportunity = {"slot": "nursery", "sequence": 3}
	var after := initial.duplicate(true)
	after.journey.erase("tracked_opportunity")
	var pair := _board(initial, [_reply(after)])
	await _settle()
	assert_str(JourneyRequests.status(initial, "nursery")).contains("Tracked")
	assert_str(JourneyRequests.status(initial, "bistro")).is_equal("Ready to deliver")
	assert_str(_button(pair[0], "BoardTrackRequest_nursery").theme_type_variation).is_equal("ChoiceSelectedButton")
	_button(pair[0], "BoardTrackRequest_nursery").pressed.emit()
	await _settle()
	assert_bool(JourneyRequests.accepted(pair[1].state, "nursery")).is_true()
	assert_dict(JourneyRequests.tracked(pair[1].state)).is_empty()
	assert_bool(pair[2].last_body().payload.tracking).is_false()

func test_abandon_needs_confirmation_and_preserves_the_sequence_seen_by_the_player() -> void:
	var initial := _state()
	initial.journey.opportunities.restorer.accepted = true
	var pair := _board(initial, [{"status": 422, "json": {"code": "REQUEST_DONE"}}, _reply(initial)])
	var panel: BagPanel = pair[0]
	await _settle()
	_button(panel, "AbandonRequest_restorer").pressed.emit()
	await _settle()
	assert_str(panel.mode).is_equal("request_confirm")
	assert_int(pair[2].requests.size()).is_zero()
	pair[1].state.journey.opportunities.restorer.sequence = 9
	_button(panel, "ConfirmRequestChange").pressed.emit()
	await _settle()
	assert_str(pair[2].requests[0].body.type).is_equal("abandon_opportunity")
	assert_int(int(pair[2].requests[0].body.payload.sequence)).is_equal(7)
	assert_str(pair[2].requests[1].method).is_equal("GET")
	assert_str(panel.message.text).contains("changed")
	assert_str(panel.mode).is_equal("grid")
	assert_int(panel.request_sequence).is_equal(-1)
	assert_object(_button(panel, "ConfirmRequestChange")).is_null()
	assert_int(pair[2].requests.size()).is_equal(2)

func test_details_primary_accepts_without_navigation_then_offers_the_real_destination() -> void:
	var state := _state()
	var after := state.duplicate(true)
	after.journey.opportunities.bistro.accepted = true
	after.journey.tracked_opportunity = {"slot": "bistro", "sequence": 5}
	var pair := _board(state, [_reply(after)])
	var panel: BagPanel = pair[0]
	var goals := []
	panel.goal_requested.connect(func(goal): goals.append(goal))
	await _settle()
	_button(panel, "RequestDetails_bistro").pressed.emit()
	await _settle()
	_button(panel, "DetailsAcceptRequest_bistro").pressed.emit()
	await _settle()
	assert_str(panel.mode).is_equal("grid")
	assert_array(goals).is_empty()
	_button(panel, "RequestDetails_bistro").pressed.emit()
	await _settle()
	_button(panel, "DetailsGoToRequest_bistro").pressed.emit()
	assert_int(goals.size()).is_equal(1)
	assert_str(goals[0].target).is_equal("mine")
	assert_int(pair[2].requests.size()).is_equal(1)

func test_stale_npc_confirmation_tracking_and_delivery_refresh_without_resubmitting() -> void:
	for operation in ["decline_opportunity", "track_journey_opportunity", "fulfill_opportunity"]:
		var state := _state()
		state.journey.opportunities.restorer.accepted = true
		var refreshed := state.duplicate(true)
		refreshed.journey.opportunities.restorer = {"sequence": 8, "variant": 3, "accepted": false}
		var transport := FakeTransport.new([{"status": 422, "json": {"code": "REQUEST_DONE"}}, _reply(refreshed)])
		var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
		session.state = state
		session.version = 1
		var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
		panel.place_id = "courtyard"
		panel.target = "street_offer:restorer"
		panel.setup(session)
		panel._request_confirmation = {"type": "decline_opportunity", "slot": "restorer", "sequence": 7}
		add_child(panel)
		await _settle()
		if operation == "track_journey_opportunity": await panel._track_offer("restorer", 7, true)
		elif operation == "fulfill_opportunity": await panel._deliver_offer("restorer", JourneyProgress.offer(state, "restorer"), 7)
		else: await panel._request_action(operation, "restorer", 7)
		await _settle()
		assert_dict(panel._request_confirmation).is_empty()
		assert_object(_button(panel, "ConfirmNpcRequestChange")).is_null()
		assert_int(transport.requests.size()).is_equal(2)
		assert_str(transport.requests[0].body.type).is_equal(operation)
		assert_int(int(transport.requests[0].body.payload.sequence)).is_equal(7)
		assert_str(transport.requests[1].method).is_equal("GET")
		assert_str(panel.message.text).contains("changed")

func test_request_command_holds_shared_bag_busy_lock_until_confirmation() -> void:
	var initial := _state()
	var pair := _board(initial, [_reply(initial)])
	var panel: BagPanel = pair[0]
	var transport_call: Callable = pair[1].client.transport
	pair[1].client.transport = func(method, url, headers, body):
		await _settle(8)
		return transport_call.call(method, url, headers, body)
	await _settle()
	_button(panel, "AcceptRequest_nursery").pressed.emit()
	assert_bool(panel.busy).is_true()
	panel.select_page("bag")
	pair[3].close()
	assert_str(panel.page).is_equal("requests")
	assert_bool(pair[3].visible).is_true()
	await _settle(12)
	assert_bool(panel.busy).is_false()
	assert_int(pair[2].requests.size()).is_equal(1)

func test_new_mining_and_cooking_requests_keep_real_shortfalls_until_delivery() -> void:
	var state := _state()
	state.journey.opportunities.bistro.accepted = true
	state.journey.tracked_opportunity = {"slot": "bistro", "sequence": 5}
	state.inventory.produce = {"R": 1, "L": 1}
	assert_str(JourneyRequests.goal(state).target).is_equal("mine")
	assert_str(JourneyRequests.goal(state).hint).contains("Rock salt")
	state.journey.materials.rock_salt = 1
	assert_str(JourneyRequests.goal(state).target).is_equal("counter")
	state.inventory.dishes.vegetable_soup = 1
	assert_str(JourneyRequests.goal(state).target).is_equal("table")
	assert_dict(JourneyRequests.crop_needs(state)).is_equal({"R": 0, "L": 0})
	state.journey.tracked_opportunity = {"slot": "restorer", "sequence": 7}
	state.journey.opportunities.restorer.accepted = true
	assert_str(JourneyRequests.goal(state).target).is_equal("mine")
	state.journey.materials.copper_ore = 3
	assert_str(JourneyRequests.goal(state).resident).is_equal("restorer")

func test_handmade_request_uses_effective_recipe_and_recovers_a_displayed_piece() -> void:
	var state := _state()
	state.journey.opportunities.restorer = {"sequence": 7, "variant": 3, "accepted": true}
	state.journey.tracked_opportunity = {"slot": "restorer", "sequence": 7}
	state.bag.equipped.gloves = {"id": "bag_10", "item_id": "artisan_apron", "quantity": 1, "instance_id": "item_10"}
	state.journey.wood = 1
	state.journey.materials.stone = 1
	assert_int(int(JourneyRequests.material_needs(state, "restorer").wood)).is_equal(1)
	assert_str(JourneyRequests.goal(state).target).is_equal("mine")
	state.journey.materials.copper_ore = 3
	assert_str(JourneyRequests.goal(state).target).is_equal("workbench")
	state.journey.workshop.displays.terrace = ["crate", "", ""]
	assert_str(JourneyRequests.goal(state).target).is_equal("display:terrace:0")
	state.journey.workshop.stock.crate = 1
	assert_bool(JourneyProgress.offer_ready(state, "restorer")).is_true()
	assert_str(JourneyRequests.goal(state).resident).is_equal("restorer")

func test_unaccepted_or_locked_requests_never_enable_delivery() -> void:
	var state := _state()
	state.inventory.dishes.vegetable_soup = 1
	assert_bool(JourneyRequests.supplies_ready(state, "bistro")).is_true()
	assert_bool(JourneyProgress.offer_ready(state, "bistro")).is_false()
	state.journey.opportunities.bistro.accepted = true
	assert_bool(JourneyProgress.offer_ready(state, "bistro")).is_true()
	state.journey.facts.erase("shared_meal")
	assert_bool(JourneyRequests.available(state, "bistro")).is_false()
	assert_bool(JourneyProgress.offer_ready(state, "bistro")).is_false()

func test_direct_and_recipe_requirements_accumulate_without_reusing_the_same_material() -> void:
	var catalog := JourneyProgress.data()
	JourneyProgress._data = catalog.duplicate(true)
	var offer: Dictionary = JourneyProgress._data.opportunities.restorer[3]
	offer.materials = {"wood": 2, "rock_salt": 1}
	offer.produce = {"R": 1}
	offer.dishes = {"vegetable_soup": 1}
	var state := _state()
	state.journey.opportunities.restorer = {"sequence": 7, "variant": 3, "accepted": true}
	state.journey.tracked_opportunity = {"slot": "restorer", "sequence": 7}
	state.journey.wood = 2
	state.journey.materials = {"stone": 1, "copper_ore": 3, "rock_salt": 1}
	state.inventory.produce = {"R": 1, "L": 1}
	var needs := JourneyRequests.material_needs(state, "restorer")
	assert_int(int(needs.wood)).is_equal(4)
	assert_int(int(needs.rock_salt)).is_equal(2)
	assert_int(int(JourneyRequests.crop_needs(state).R)).is_equal(2)
	assert_bool(JourneyRequests.supplies_ready(state, "restorer")).is_false()
	state.journey.wood = 4
	state.journey.materials.rock_salt = 2
	state.inventory.produce.R = 2
	assert_str(JourneyRequests.goal(state).target).is_equal("workbench")
	state.journey.workshop.stock.crate = 1
	state.journey.wood = 2
	assert_str(JourneyRequests.goal(state).target).is_equal("counter")
	state.inventory.dishes.vegetable_soup = 1
	state.inventory.produce.R = 1
	state.inventory.produce.L = 0
	state.journey.materials.rock_salt = 1
	assert_bool(JourneyRequests.supplies_ready(state, "restorer")).is_true()
	JourneyProgress._data = catalog

func test_history_uses_persisted_receipt_without_sending_or_replaying_reward() -> void:
	var state := _state()
	state.journey.opportunities.restorer.last_completed = {"offer_id": "copper_for_repairs", "resident_id": "restorer", "sequence": 6,
		"consumed": {"copper_ore": 3}, "coins": 18, "effect": "benches", "contribution": 2}
	var pair := _board(state)
	await _settle()
	_button(pair[0], "LastRequest_restorer").pressed.emit()
	await _settle()
	assert_str(pair[0].mode).is_equal("request_history")
	assert_str(JourneyRequests.last_reply(state, "restorer")).contains("strengthen")
	assert_int(pair[2].requests.size()).is_zero()
	assert_int(state.wallet).is_equal(80)

func test_timber_only_request_from_copper_uses_explicit_variant_and_confirmation() -> void:
	var state := _state()
	state.wallet = 0
	state.journey.opportunities.restorer.accepted = true
	var after := state.duplicate(true)
	after.journey.opportunities.restorer = {"sequence": 8, "variant": 0, "accepted": false}
	var pair := _board(state, [_reply(after)])
	var panel: BagPanel = pair[0]
	await _settle()
	assert_str(JourneyProgress.seed_money_goal(state, "R").change_request).is_equal("restorer")
	_button(panel, "RequestDetails_restorer").pressed.emit()
	await _settle()
	_button(panel, "BoardTimberOnlyRequest").pressed.emit()
	await _settle()
	assert_int(pair[2].requests.size()).is_zero()
	_button(panel, "ConfirmRequestChange").pressed.emit()
	await _settle()
	assert_str(pair[2].last_body().type).is_equal("decline_opportunity")
	assert_bool(pair[2].last_body().payload.timber_only).is_true()
	assert_int(int(pair[2].last_body().payload.sequence)).is_equal(7)
	assert_str(JourneyProgress.offer(pair[1].state, "restorer").id).is_equal("timber_for_repairs")
	state.journey.materials.copper_ore = 3
	assert_str(JourneyProgress.seed_money_goal(state, "R").hint).contains("Deliver supplies")

func test_chinese_request_metadata_and_profiles_are_complete() -> void:
	var old := TranslationServer.get_locale()
	Localization.select_language("zh_CN")
	for slot in JourneyRequests.SLOTS:
		for offer in JourneyProgress.data().opportunities[slot]:
			for field in ["name", "description", "reply"]:
				assert_str(L10n.text(str(offer[field]))).is_not_equal(str(offer[field]))
	for id in ResidentCast.ORDER:
		var profile := str(ResidentCast.definition(id).profile)
		assert_str(L10n.text(profile)).is_not_equal(profile)
	Localization.select_language(old)
