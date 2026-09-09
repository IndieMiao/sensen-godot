extends GdUnitTestSuite

func _session(layout := "sh_a") -> FarmSession:
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", FakeTransport.new().callable()))
	session.layout_patch_id = layout
	session.blueprint_revision = 2
	session.state = {"wallet": 80, "beds_unlocked": 3, "cells": {}, "clock": {"chapter_index": 0, "last_effective_now": 1000},
		"xp": {"first_harvest_crops": ["R"]}, "inventory": {"seeds": {}, "produce": {}, "dishes": {}},
		"journey": {"version": 1, "wood": 0, "facts": ["met_nursery", "workbench", "shared_meal"], "unlocks": ["bistro"],
			"tracked_opportunity": {"slot": "nursery", "sequence": 0}, "opportunities": {"nursery": {"sequence": 0, "variant": 0}},
			"exploration": {"round": 0, "collected": []}}}
	var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path(layout, 2))
	for bed in bp.beds():
		for cell in bed.cells: session.state.cells[FarmBlueprint._cs(cell)] = {"state": "growing", "crop": "R", "ready_at": 2000}
	for cell in bp.reserved_bed().cells: session.state.cells[FarmBlueprint._cs(cell)] = {"state": "tilled"}
	return session

func test_locked_beds_do_not_offer_sowing_or_buying_across_actual_layouts() -> void:
	for layout in ["sh_a", "sh_b", "sh_c", "safe_grid"]:
		var session := _session(layout)
		var before := session.state.duplicate(true)
		var view := JourneyProgress.goal_state(session)
		assert_int(view.cells.size()).is_equal(9)
		var goal := JourneyProgress.tracked_goal(view, 1000)
		assert_str(goal.action).is_equal("wait")
		assert_str(goal.hint).is_equal("Beds full; crops growing")
		assert_str(NextStep.bulk(view.cells, 1000, session.state, "R", CropInfo.ORDER).action).is_equal("explore")
		assert_dict(session.state).is_equal(before)
		session.state.beds_unlocked = 4
		view = JourneyProgress.goal_state(session)
		assert_int(view.cells.size()).is_equal(12)
		assert_str(JourneyProgress.tracked_goal(view, 1000).action).is_equal("stall")
		session.state.inventory.seeds.L = {"bound": 2}
		assert_str(JourneyProgress.tracked_goal(JourneyProgress.goal_state(session), 1000).action).is_equal("sow")

func test_full_beds_return_to_harvest_or_care_before_preparing_a_different_crop() -> void:
	var session := _session()
	var view := JourneyProgress.goal_state(session)
	assert_str(JourneyProgress.tracked_goal(view, 2000).action).is_equal("harvest")
	assert_bool(JourneyProgress.tracked_goal(view, 2000).hint.contains("make room")).is_true()
	var id: String = view.cells.keys()[0]
	session.state.cells[id].state = "sown"
	assert_str(JourneyProgress.tracked_goal(JourneyProgress.goal_state(session), 1000).action).is_equal("care")
	session.state.cells[id] = {"state": "tilled"}
	assert_str(JourneyProgress.tracked_goal(JourneyProgress.goal_state(session), 1000).action).is_equal("stall")

func test_locked_crops_do_not_count_as_supplies_or_farm_notifications() -> void:
	var session := _session()
	var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2))
	for cell in bp.reserved_bed().cells:
		session.state.cells[FarmBlueprint._cs(cell)] = {"state": "growing", "crop": "L", "ready_at": 500}
	var view := JourneyProgress.goal_state(session)
	assert_str(JourneyProgress.farm_hint(view, 1000)).is_equal("Growing")
	assert_str(JourneyProgress.needed_crop(view, view.cells)).is_equal("L")
	assert_str(JourneyProgress.tracked_goal(view, 1000).action).is_equal("wait")
	session.state.beds_unlocked = 4
	assert_str(JourneyProgress.farm_hint(JourneyProgress.goal_state(session), 1000)).is_equal("3 ready")

func test_local_prediction_controls_the_cta_without_modifying_authoritative_cells() -> void:
	var session := _session()
	var interior := FarmInterior.new(FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2)))
	var farm = auto_free(load("res://scenes/farm/farm.gd").new())
	var local := interior.local_cells(session.state.cells)
	var id: String = FarmBlueprint._cs(interior.blueprint.beds()[0].cells[0])
	local[id] = {"state": "tilled"}
	farm.predictor = CellPredictor.from_blueprint(interior.blueprint, local)
	var before := session.state.duplicate(true)
	assert_str(NextStep.bulk(farm._actionable_view(), 1000, session.state, "R", CropInfo.ORDER).action).is_equal("stall")
	assert_bool(farm.predictor.predict("sow_cells", {"cell_ids": [id], "crop": "R"}, 1000).ok).is_true()
	assert_str(NextStep.bulk(farm._actionable_view(), 1000, session.state, "R", CropInfo.ORDER).action).is_equal("care")
	assert_bool(farm.predictor.predict("apply_care", {"cell_ids": [id], "kind": "water"}, 1000).ok).is_true()
	assert_str(NextStep.bulk(farm._actionable_view(), 1000, session.state, "R", CropInfo.ORDER).action).is_equal("explore")
	assert_dict(session.state).is_equal(before)

func test_clearable_beds_and_world_food_remain_available() -> void:
	var session := _session()
	var id: String = JourneyProgress.goal_state(session).cells.keys()[0]
	for state in ["wild", "cleared", "tilled"]:
		session.state.cells[id] = {"state": state}
		session.state.inventory.seeds.L = {"bound": 1}
		assert_str(JourneyProgress.tracked_goal(JourneyProgress.goal_state(session), 1000).action).is_equal("sow")
	session.state.cells[id] = {"state": "growing", "crop": "R", "ready_at": 2000}
	session.state.journey.facts.append_array(["crafted_lantern", "discovery_kitchen_garden"])
	assert_str(JourneyProgress.tracked_goal(JourneyProgress.goal_state(session), 1000).target).is_equal("harvest:kitchen_garden:salad")
	session.state.journey.exploration.collected = ["discovery_kitchen_garden"]
	assert_str(JourneyProgress.tracked_goal(JourneyProgress.goal_state(session), 1000).target).is_equal("bistro_west")
	session.state.journey.exploration.collected.append_array(["bistro_west", "bistro_east"])
	assert_str(JourneyProgress.tracked_goal(JourneyProgress.goal_state(session), 1000).target).is_equal("trail")

func test_street_goal_reads_the_same_unlocked_farm_view() -> void:
	var session := _session()
	session._server_time_ms = 1000
	session._server_sample_ticks_ms = Time.get_ticks_msec()
	var street := auto_free(JourneyStreet.new()) as JourneyStreet
	street.session = session
	assert_str(street._current_goal().action).is_equal("wait")
	assert_str(street._current_goal().hint).is_equal("Beds full; crops growing")
	session.state.beds_unlocked = 4
	assert_str(street._current_goal().action).is_equal("stall")
