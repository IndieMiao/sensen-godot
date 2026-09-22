extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0, "last_effective_now": 1000}, "wallet": 0, "cells": {},
		"xp": {"first_harvest_crops": ["R"]}, "engineering": {"reserved": {}},
		"inventory": {"produce": {}, "seeds": {}, "dishes": {}}, "journey": {"version": 1, "wood": 0, "materials": {},
			"facts": ["workbench", "planter_crafted", "planter_placed", "met_nursery", "met_bistro", "shared_meal", "side_path", "crafted_lantern",
				"discovery_stone_hollow", "discovery_reed_garden", "discovery_kitchen_garden"],
			"unlocks": ["bistro", "crop_C", "crop_H", "kitchen", "tea"], "opportunities": {"bistro": {"sequence": 0, "variant": 0}, "restorer": {"sequence": 0, "variant": 0}},
			"tracked_opportunity": {"slot": "bistro", "sequence": 0}, "exploration": {"round": 4,
				"collected": ["bistro_west", "bistro_east", "discovery_kitchen_garden", "discovery_reed_garden", "discovery_stone_hollow"]}}}

func test_empty_wallet_request_uses_a_complete_trail_then_its_exact_harvest() -> void:
	var st := _state()
	var before := st.duplicate(true)
	var goal := JourneyProgress.tracked_goal(st)
	assert_str(goal.place).is_equal("bistro")
	assert_str(goal.target).is_equal("trail")
	assert_str(goal.action).is_equal("gather")
	assert_str(NextStep.bulk({}, 1000, st, "R", CropInfo.ORDER).target).is_equal("trail")
	assert_dict(st).is_equal(before)
	st.journey.exploration.collected.erase("bistro_east")
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("bistro_east")
	st.journey.exploration.routes_by_place = {"bistro": "stone_walk"}
	assert_str(JourneyProgress.tracked_goal(st).surface).is_equal("street")
	st.journey.exploration.collected.erase("discovery_kitchen_garden")
	goal = JourneyProgress.tracked_goal(st)
	assert_str(goal.target).is_equal("harvest:kitchen_garden:salad")
	assert_bool(goal.has("surface")).is_false()
	st.inventory.produce = {"L": 1, "C": 1}
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("counter")
	st.inventory.produce.clear()
	st.inventory.dishes.salad = 1
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("table")

func test_completed_seed_source_keeps_a_nursery_request_recoverable() -> void:
	var st := _state()
	st.journey.facts.erase("discovery_kitchen_garden")
	st.journey.opportunities = {"nursery": {"sequence": 2, "variant": 0}}
	st.journey.tracked_opportunity = {"slot": "nursery", "sequence": 2}
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("courtyard_west")
	st.journey.exploration.collected.append_array(["courtyard_west", "courtyard_east"])
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("trail")
	assert_str(JourneyProgress.tracked_goal(st).place).is_equal("courtyard")
	st.journey.exploration.collected.erase("discovery_reed_garden")
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("harvest:reed_garden:seeds")
	st.inventory.seeds.L = {"bound": 2}
	assert_str(JourneyProgress.tracked_goal(st).action).is_equal("sow")
	assert_str(JourneyProgress.needed_crop(st, {})).is_equal("L")

func test_project_and_gathering_use_the_same_restored_food_source() -> void:
	var st := _state()
	st.journey.erase("tracked_opportunity")
	st.journey.tracked_project = "terrace"
	st.journey.facts.append("project_terrace_0")
	st.inventory.dishes.salad = 1
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("trail")
	assert_str(JourneyProgress.tracked_goal(st).place).is_equal("bistro")
	st.journey.erase("tracked_project")
	st.journey.facts.append_array(JourneyProgress.data().gatherings.requires)
	st.journey.gathering = {"sequence": 0, "planned": "garden"}
	st.journey.workshop = {"stock": {"planter": 1}, "displays": {}}
	st.journey.exploration.collected.append("seedbeds")
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("trail")
	assert_str(JourneyProgress.tracked_goal(st).place).is_equal("bistro")

func test_growing_and_owned_seeds_keep_the_existing_plan_before_refreshing_supplies() -> void:
	var st := _state()
	st.inventory.seeds = {"C": {"bound": 1}, "L": {"bound": 1}}
	assert_str(JourneyProgress.tracked_goal(st).action).is_equal("sow")
	st.inventory.seeds.clear()
	st.cells = {"a": {"state": "growing", "crop": "C", "ready_at": 2000}, "b": {"state": "growing", "crop": "L", "ready_at": 2000}}
	assert_str(JourneyProgress.tracked_goal(st, 1000).action).is_equal("wait")
	assert_str(JourneyProgress.tracked_goal(st, 2000).action).is_equal("harvest")
	st.cells.a.state = "sown"
	assert_str(JourneyProgress.tracked_goal(st, 1000).action).is_equal("water")

func test_supply_guidance_never_invents_an_unrestored_or_locked_reward() -> void:
	var st := _state()
	st.wallet = 80
	st.journey.facts.erase("discovery_kitchen_garden")
	st.journey.facts.erase("discovery_reed_garden")
	assert_str(JourneyProgress.tracked_goal(st).action).is_equal("stall")
	assert_dict(JourneyProgress.discovery_supply_goal(st, "produce", "C", true)).is_empty()
	st.journey.facts.append("discovery_kitchen_garden")
	st.journey.unlocks.erase("crop_H")
	assert_dict(JourneyProgress.discovery_supply_goal(st, "produce", "H", true)).is_empty()
	st.journey.unlocks.erase("bistro")
	assert_dict(JourneyProgress.discovery_supply_goal(st, "produce", "C", true)).is_empty()

func test_material_and_seed_goals_identify_the_corresponding_world_choice() -> void:
	var st := _state()
	st.journey.exploration.collected.clear()
	var before := st.duplicate(true)
	for spec in [["wood", "harvest:stone_hollow:timber"], ["stone", "harvest:stone_hollow:stone"], ["fiber", "harvest:reed_garden:reeds"]]:
		assert_str(JourneyProgress._material_goal(st, str(spec[0])).target).is_equal(spec[1])
	assert_str(JourneyProgress.discovery_supply_goal(st, "seeds", "L").target).is_equal("harvest:reed_garden:seeds")
	assert_dict(st).is_equal(before)

func _without_facilities() -> Dictionary:
	var st := _state()
	st.journey.facts = ["met_nursery", "first_harvest", "met_bistro", "shared_meal"]
	st.cells = {"a": {"state": "tilled"}}
	return st

func test_seed_money_guidance_keeps_the_original_request_and_returns_to_buying() -> void:
	var st := _without_facilities()
	var before := st.duplicate(true)
	var goal := JourneyProgress.tracked_goal(st)
	assert_str(goal.action).is_equal("gather")
	assert_str(goal.target).is_equal("nursery_west")
	assert_bool(goal.hint.contains("seed money")).is_true()
	assert_dict(st).is_equal(before)
	st.journey.wood = 3
	goal = JourneyProgress.tracked_goal(st)
	assert_str(goal.resident).is_equal("restorer")
	assert_bool(goal.hint.contains("+9")).is_true()
	var bulk := NextStep.bulk(st.cells, 1000, st, "R", CropInfo.ORDER)
	assert_str(bulk.action).is_equal("explore")
	assert_str(bulk.place).is_equal("courtyard")
	assert_str(bulk.target).is_equal("resident")
	st.wallet = 9
	assert_str(JourneyProgress.tracked_goal(st).action).is_equal("stall")
	assert_dict(st.journey.tracked_opportunity).is_equal(before.journey.tracked_opportunity)
	assert_dict(st.journey.opportunities).is_equal(before.journey.opportunities)

func test_seed_money_recovery_finishes_remaining_routes_before_refreshing() -> void:
	var st := _without_facilities()
	st.journey.exploration.collected.clear()
	for node in JourneyProgress.nodes(st): st.journey.exploration.collected.append(node.id)
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("trail")
	assert_bool(JourneyProgress.route_ready(st, "woodland")).is_true()
	st.journey.exploration.collected.erase("bistro_east")
	st.journey.exploration.routes_by_place = {"bistro": "stone_walk"}
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("bistro_east")
	assert_str(JourneyProgress.tracked_goal(st).surface).is_equal("street")

func test_mixed_restorer_offer_requires_an_explicit_change_without_recursive_guidance() -> void:
	var st := _without_facilities()
	st.journey.opportunities.restorer = {"sequence": 1, "variant": 1}
	st.journey.wood = 2
	var before := st.duplicate(true)
	var goal := JourneyProgress.tracked_goal(st)
	assert_str(goal.change_request).is_equal("restorer")
	assert_str(goal.target).is_equal("resident")
	assert_dict(st).is_equal(before)
	st.journey.tracked_opportunity = {"slot": "restorer", "sequence": 1}
	assert_str(JourneyProgress.tracked_goal(st).change_request).is_equal("restorer")
	st.inventory.produce.R = 1
	assert_str(JourneyProgress.tracked_goal(st).hint).is_equal("Ready to deliver")
	st.engineering.reserved.R = 1
	assert_str(JourneyProgress.tracked_goal(st).change_request).is_equal("restorer")

func test_untracked_empty_seed_basket_can_recover_without_a_finished_facility() -> void:
	var st := _without_facilities()
	st.journey.erase("tracked_opportunity")
	var bulk := NextStep.bulk(st.cells, 1000, st, "L", CropInfo.ORDER)
	assert_str(bulk.action).is_equal("explore")
	assert_bool(bulk.label.contains("seed money")).is_true()
	st.wallet = CropInfo.seed_price("H")
	bulk = NextStep.bulk(st.cells, 1000, st, "L", CropInfo.ORDER)
	assert_str(bulk.action).is_equal("stall")
	assert_str(bulk.crop).is_equal("H")

func test_recovery_offer_button_sends_nothing_until_the_player_chooses() -> void:
	var st := _without_facilities()
	st.journey.wood = 2
	st.journey.opportunities.restorer = {"sequence": 1, "variant": 1}
	var reply := st.duplicate(true)
	reply.journey.opportunities.restorer = {"sequence": 2, "variant": 0}
	var transport := FakeTransport.new([{ "status": 200, "json": {"version": 2, "state": reply}}])
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "courtyard"
	panel.target = "street_offer:restorer"
	panel.setup(FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable())))
	panel.session.state = st
	panel.session.version = 1
	add_child(panel)
	for frame in 3: await get_tree().process_frame
	var change := panel.content.find_child("ChangeRequest_restorer", true, false) as Button
	assert_str(change.text).is_equal("Request timber-only work")
	assert_array(transport.requests).is_empty()
	change.pressed.emit()
	for frame in 5: await get_tree().process_frame
	assert_str(transport.last_body().type).is_equal("decline_opportunity")
	assert_dict(transport.last_body().payload).is_equal({"slot": "restorer", "sequence": 1.0, "timber_only": true})
	assert_dict(panel.session.state.journey.tracked_opportunity).is_equal(st.journey.tracked_opportunity)
	assert_int(panel.session.state.wallet).is_equal(0)
