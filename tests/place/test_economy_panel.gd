extends GdUnitTestSuite

func _state(chapter := 5) -> Dictionary:
	return {"clock": {"chapter_index": chapter, "player_day_id": "2026-09-05"},
		"wallet": 483, "inventory": {"seeds": {}, "produce": {"R": 3, "L": 2, "C": 2, "H": 4}, "dishes": {"tea": 1}},
		"engineering": {"reserved": {}, "submitted": {}}, "nursery": {"stage": "cleared", "appearance": null},
		"growth_choice": {"intent": "field", "purchase": null}, "stall": {"settled": 0},
		"life_choices": {}, "sales_facts": {}, "requests_done": [], "subsidies_claimed": [], "cells": {}}

func _panel(initial: Dictionary, section: String, responses: Array = []) -> Array:
	var transport := FakeTransport.new(responses)
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = initial
	session.version = 1
	var panel := EconomyPanel.new()
	panel.setup(session)
	panel.section = section
	add_child(auto_free(panel))
	return [panel, session, transport]

func _reply(state: Dictionary, version := 2) -> Dictionary:
	return {"status": 200, "json": {"version": version, "state": state}}

func _button(panel: EconomyPanel, id: String) -> Button:
	return panel.find_child(id, true, false) as Button

func test_growth_total_includes_the_seed_basket_and_requires_the_full_balance() -> void:
	var pair := _panel(_state(), "growth")
	var panel: EconomyPanel = pair[0]
	await get_tree().process_frame
	assert_int(panel.growth_cost("field")).is_equal(484)
	assert_int(panel.growth_cost("tool")).is_equal(240)
	assert_bool(_button(panel, "Purchase_field").disabled).is_true()
	pair[1].state.wallet = 484
	panel.refresh()
	await get_tree().process_frame
	assert_bool(_button(panel, "Purchase_field").disabled).is_false()
	pair[1].state.growth_choice.purchase = "field"
	panel.refresh()
	await get_tree().process_frame
	assert_bool(_button(panel, "Growth_tool").disabled).is_true()
	assert_bool(_button(panel, "Purchase_field") == null).is_true()

func test_failed_purchase_keeps_the_saved_intent_and_all_assets() -> void:
	var initial := _state()
	initial.wallet = 484
	var pair := _panel(initial, "growth", [{"status": 422, "json": {"code": "INSUFFICIENT_FUNDS"}}])
	var panel: EconomyPanel = pair[0]
	await get_tree().process_frame
	await panel._purchase("field")
	assert_int(pair[1].state.wallet).is_equal(484)
	assert_str(pair[1].state.growth_choice.intent).is_equal("field")
	assert_bool(pair[1].state.growth_choice.purchase == null).is_true()
	assert_str(panel.message.text).is_equal("Not enough coins.")
	assert_str(pair[2].last_body().type).is_equal("purchase_growth_choice")
	assert_str(pair[2].last_body().payload.transaction_id).is_not_empty()

func test_choices_reserve_produce_and_recover_a_successful_sale_without_selling_again() -> void:
	var initial := _state(2)
	var sold := initial.duplicate(true)
	sold.inventory.produce.L -= 1
	sold.wallet += 12
	sold.sales_facts = {"2": {"L": 1}}
	var resolved := sold.duplicate(true)
	resolved.life_choices = {"2": "sold"}
	var pair := _panel(initial, "choices", [_reply(sold),
		{"status": 422, "json": {"code": "REQUEST_MISMATCH"}}, _reply(resolved, 3)])
	var panel: EconomyPanel = pair[0]
	await get_tree().process_frame
	await panel._sell_choice(2, "L")
	assert_int(pair[1].state.inventory.produce.L).is_equal(1)
	assert_bool(pair[1].state.life_choices.is_empty()).is_true()
	await panel._sell_choice(2, "L")
	assert_that(pair[2].bodies().map(func(body): return body.type)).is_equal([
		"sell_at_stall", "resolve_life_choice", "resolve_life_choice"])
	assert_str(pair[1].state.life_choices["2"]).is_equal("sold")
	assert_int(pair[1].state.inventory.produce.L).is_equal(1)

func test_confirming_an_existing_gift_does_not_send_a_second_gift() -> void:
	var initial := _state(1)
	initial.sales_facts = {"-2": {"R": 1}}
	var resolved := initial.duplicate(true)
	resolved.life_choices = {"1": "gift"}
	var pair := _panel(initial, "choices", [_reply(resolved)])
	var panel: EconomyPanel = pair[0]
	await get_tree().process_frame
	assert_str(_button(panel, "ChoiceGift").text).is_equal("Remember my gift")
	await panel._resolve(1, "gift")
	assert_int(pair[2].requests.size()).is_equal(1)
	assert_str(pair[2].last_body().type).is_equal("resolve_life_choice")

func test_lost_sale_reply_requires_reload_before_another_sale_can_be_sent() -> void:
	var initial := _state(2)
	var sold := initial.duplicate(true)
	sold.inventory.produce.L -= 1
	sold.sales_facts = {"2": {"L": 1}}
	var resolved := sold.duplicate(true)
	resolved.life_choices = {"2": "sold"}
	var pair := _panel(initial, "choices", [{"error": "timeout"}, {"error": "timeout"},
		_reply(sold), _reply(sold), _reply(resolved, 3)])
	var panel: EconomyPanel = pair[0]
	await get_tree().process_frame
	await panel._sell_choice(2, "L")
	await get_tree().process_frame
	assert_bool(pair[1].has_meta("pending_economy_command")).is_true()
	assert_bool(_button(panel, "ChoiceSell") == null).is_true()
	assert_bool(_button(panel, "CheckSavedAction") != null).is_true()
	await panel._check_saved()
	await panel._sell_choice(2, "L")
	assert_that(pair[2].requests.map(func(request): return request.method)).is_equal(["POST", "POST", "POST", "GET", "POST"])
	assert_str(pair[2].requests[0].body.idempotency_key).is_equal(pair[2].requests[1].body.idempotency_key)
	assert_that(pair[2].requests[2].body).is_equal(pair[2].requests[0].body)
	assert_str(pair[2].requests[4].body.type).is_equal("resolve_life_choice")
	assert_int(pair[1].state.inventory.produce.L).is_equal(1)

func test_pending_resident_interaction_cannot_be_bypassed_from_economy_tab() -> void:
	var pair := _panel(_state(2), "choices")
	var panel: EconomyPanel = pair[0]
	pair[1].set_meta("pending_resident_command", {"resident_id": "bistro_owner"})
	await get_tree().process_frame
	assert_bool(_button(panel, "ChoiceSell") == null).is_true()
	assert_bool(await panel._resolve(2, "keep")).is_false()
	assert_int(pair[2].requests.size()).is_equal(0)

func test_choice_sale_is_disabled_at_daily_budget_and_keep_excludes_project_reservations() -> void:
	var initial := _state(5)
	initial.stall.settled = 100
	initial.engineering.reserved = {"H": 4}
	var pair := _panel(initial, "choices")
	var panel: EconomyPanel = pair[0]
	await get_tree().process_frame
	assert_bool(_button(panel, "ChoiceSell").disabled).is_true()
	assert_bool(_button(panel, "ChoiceKeep").disabled).is_true()
	assert_bool(_button(panel, "ChoiceGift").disabled).is_true()

func test_project_reserves_only_available_remaining_quota() -> void:
	var initial := _state()
	initial.engineering = {"reserved": {"H": 1}, "submitted": {"C": 1, "H": 1}}
	var reserved := initial.duplicate(true)
	reserved.engineering.reserved = {"C": 1, "H": 3}
	var pair := _panel(initial, "project", [_reply(reserved)])
	var panel: EconomyPanel = pair[0]
	await get_tree().process_frame
	_button(panel, "ReserveAll").pressed.emit()
	await get_tree().process_frame
	assert_int(int(pair[2].last_body().payload.items.C)).is_equal(1)
	assert_int(int(pair[2].last_body().payload.items.H)).is_equal(2)
	assert_int(pair[1].state.inventory.produce.H).is_equal(4)
	assert_bool(_button(panel, "ReserveAll").disabled).is_true()
	assert_bool(_button(panel, "SubmitAll").disabled).is_false()

func test_project_opens_in_chapter_three_and_appearance_in_chapter_five() -> void:
	var pair := _panel(_state(2), "project")
	var panel: EconomyPanel = pair[0]
	await get_tree().process_frame
	assert_bool(_button(panel, "ReserveAll").disabled).is_true()
	assert_bool(_button(panel, "Appearance_a") == null).is_true()
	pair[1].state.clock.chapter_index = 5
	panel.refresh()
	await get_tree().process_frame
	assert_bool(_button(panel, "ReserveAll").disabled).is_false()
	assert_bool(_button(panel, "Appearance_a").disabled).is_false()

func test_seedling_support_requires_an_empty_farm_and_tracks_daily_and_weekly_caps() -> void:
	var initial := _state(0)
	initial.wallet = 3
	initial.inventory = {"seeds": {}, "produce": {}, "dishes": {}}
	initial.seedling_packs = {"days": []}
	var pair := _panel(initial, "supplies")
	var panel: EconomyPanel = pair[0]
	await get_tree().process_frame
	assert_bool(_button(panel, "SeedlingPack").disabled).is_false()
	pair[1].state.inventory.seeds = {"R": {"bound": 1}}
	assert_bool(panel.can_claim_pack()).is_false()
	pair[1].state.inventory.seeds = {}
	pair[1].state.cells = {"1,1": {"state": "growing"}}
	assert_bool(panel.can_claim_pack()).is_false()
	pair[1].state.cells = {}
	pair[1].state.seedling_packs.days = ["2026-09-05"]
	assert_bool(panel.can_claim_pack()).is_false()
	pair[1].state.seedling_packs.days = ["2026-09-03", "2026-09-04"]
	assert_bool(panel.can_claim_pack()).is_false()

func test_tutorial_buyback_uses_the_request_command_and_claims_only_once() -> void:
	var initial := _state(0)
	var after := initial.duplicate(true)
	after.requests_done = ["d0_tutorial_buyback"]
	after.inventory.produce.R = 0
	after.wallet += 30
	var pair := _panel(initial, "supplies", [_reply(after)])
	var panel: EconomyPanel = pair[0]
	await get_tree().process_frame
	_button(panel, "TutorialBuyback").pressed.emit()
	await get_tree().process_frame
	assert_str(pair[2].last_body().type).is_equal("submit_request")
	assert_str(pair[2].last_body().payload.request_id).is_equal("d0_tutorial_buyback")
	assert_bool(_button(panel, "TutorialBuyback").disabled).is_true()

func test_offline_commands_cannot_change_wallet_or_inventory() -> void:
	var pair := _panel(_state(), "project")
	var panel: EconomyPanel = pair[0]
	pair[1].offline = true
	await get_tree().process_frame
	assert_bool(_button(panel, "ReserveAll").disabled).is_true()
	assert_bool(await panel.command("reserve_engineering", {"items": {"C": 1}})).is_false()
	assert_int(pair[2].requests.size()).is_equal(0)
	assert_that(pair[1].state.engineering.reserved).is_equal({})
