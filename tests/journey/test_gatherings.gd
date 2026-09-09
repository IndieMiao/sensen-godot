extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0}, "wallet": 200, "xp": {"first_harvest_crops": ["R"]}, "cells": {},
		"inventory": {"produce": {}, "dishes": {}, "seeds": {}}, "engineering": {"reserved": {}},
		"journey": {"version": 1, "facts": JourneyProgress.data().gatherings.requires + ["workbench", "side_path", "shared_meal", "planter_crafted"],
			"unlocks": ["bistro", "crafting", "crop_C", "crop_H", "tea", "kitchen"], "wood": 0, "materials": {}, "completed": [],
			"gathering": {"sequence": 1, "planned": "lantern", "memories": []},
			"workshop": {"sequence": 0, "stock": {}, "displays": {}}, "exploration": {"round": 3, "collected": []}}}

func test_venues_are_stable_reachable_and_clear_of_other_activities() -> void:
	for id in ["sh_a", "sh_b", "sh_c", "la_a", "la_b", "la_c", "safe_grid"]:
		var source := FarmBlueprint.load_file(FarmBlueprint.asset_path(id, 2))
		var closed := JourneyStreets.new(source)
		var opened := JourneyStreets.new(source, true)
		assert_dict(opened.gatherings).is_equal(closed.gatherings)
		for layout in [closed, opened]:
			for venue in layout.gatherings.values():
				assert_bool(layout.nav.is_walkable(layout.nav.world_to_cell(venue.position))).is_false()
				for point in [venue.approach] + venue.guests:
					assert_array(layout.grid.point_path(layout.entrances.farm, point)).is_not_empty()
					for other in venue.guests:
						if point != other: assert_float(point.distance_to(other)).is_greater(1.5)
				for pair in layout.all_caches():
					for point in pair: assert_float(point.distance_to(venue.position)).is_greater_equal(3.6)
				for common in layout.commons.values(): assert_float(common.position.distance_to(venue.position)).is_greater_equal(6)
				for point in layout.buildings.values(): assert_float(point.distance_to(venue.position)).is_greater_equal(5.4)

func test_preparation_follows_material_piece_dish_and_exact_street_target() -> void:
	var st := _state()
	assert_str(JourneyProgress.tracked_goal(st).hint).contains("Wood")
	st.journey.wood = 20
	st.journey.materials = {"stone": 20, "fiber": 20}
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("workbench")
	st.journey.workshop.displays.terrace = ["", "lantern", ""]
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("display:terrace:1")
	st.journey.workshop.stock.lantern = 1
	assert_str(JourneyProgress.tracked_goal(st).action).is_equal("stall")
	st.inventory.produce = {"C": 1, "L": 1}
	assert_str(JourneyProgress.tracked_goal(st).target).is_equal("counter")
	st.inventory.dishes.salad = 1
	var goal := JourneyProgress.tracked_goal(st)
	assert_str(goal.target).is_equal("gathering:lantern")
	assert_str(goal.surface).is_equal("street")
	assert_str(JourneyProgress.goal_label(goal)).not_contains("Stone walk")
	var action := NextStep.bulk({}, 1000, st, "R", CropInfo.ORDER)
	assert_str(action.surface).is_equal("street")
	assert_str(action.target).is_equal("gathering:lantern")

func test_hosted_piece_is_reused_and_a_crop_goal_respects_reservations() -> void:
	var st := _state()
	st.journey.gathering.current = "lantern"
	st.inventory.produce = {"C": 1, "L": 1}
	st.engineering.reserved.L = 1
	assert_str(JourneyGatherings.goal(st).crop).is_equal("L")
	st.engineering.reserved = {}
	assert_str(JourneyGatherings.goal(st).target).is_equal("counter")
	assert_int(int(JourneyGatherings.crop_needs(st).C)).is_equal(1)
	assert_int(int(JourneyGatherings.crop_needs(st).L)).is_equal(1)
	st.inventory.dishes.salad = 1
	assert_dict(JourneyGatherings.crop_needs(st)).is_empty()

func test_switching_gatherings_keeps_actor_identity_and_returns_home_after_packing() -> void:
	var st := _state()
	var residents := auto_free(StreetResidents.new()) as StreetResidents
	add_child(residents)
	residents.setup(JourneyStreets.new(FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_b", 2)), true), st)
	var actors := residents.moments.values().map(func(m): return m.actor.get_instance_id())
	residents.set_gathering("garden")
	for slot in residents.moments:
		assert_str(residents.moments[slot].phase).is_equal("approaching")
		assert_array(residents.layout.gatherings.garden.guests).contains([residents.moments[slot].destination])
	residents.set_gathering("lantern")
	assert_array(residents.moments.values().map(func(m): return m.actor.get_instance_id())).is_equal(actors)
	residents.set_gathering("")
	for moment in residents.moments.values(): assert_str(moment.phase).is_equal("returning")

func test_nearby_actor_cannot_trap_the_departure_cell() -> void:
	var residents := auto_free(StreetResidents.new()) as StreetResidents
	residents.layout = JourneyStreets.new(FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_b", 2)), true)
	var origin := Vector3(12.84991, 0, -19.5)
	var blocker := Vector3(12.29896, 0, -19.88266)
	var grid := residents.navigation([blocker], origin)
	assert_bool(grid.bp.is_walkable(grid.bp.world_to_cell(origin))).is_true()
	assert_bool(grid.bp.is_walkable(grid.bp.world_to_cell(blocker))).is_false()
	assert_array(grid.point_path(origin, residents.layout.entrances.farm)).is_not_empty()

func test_bulk_sales_keep_gathering_ingredients_then_one_prepared_meal() -> void:
	var st := _state()
	st.journey.facts.append("planter_planted")
	st.inventory.produce = {"C": 2, "L": 1, "H": 1}
	var sheet := auto_free(StallSheet.new()) as StallSheet
	add_child(sheet)
	sheet.refresh(st, CropInfo.ORDER)
	assert_that(sheet._sell_items).is_equal([{"kind": "produce", "id": "C", "qty": 1}, {"kind": "produce", "id": "H", "qty": 1}])
	st.inventory.dishes.salad = 2
	sheet.refresh(st, CropInfo.ORDER)
	assert_that(sheet._sell_items).is_equal([{"kind": "produce", "id": "L", "qty": 1}, {"kind": "produce", "id": "C", "qty": 2},
		{"kind": "produce", "id": "H", "qty": 1}, {"kind": "dish", "id": "salad", "qty": 1}])
	st.journey.gathering.erase("planned")
	sheet.refresh(st, CropInfo.ORDER)
	assert_int(sheet._sell_items[-1].qty).is_equal(2)

func test_exhausted_kitchen_trail_offers_an_active_recovery_without_seeds() -> void:
	var st := _state()
	st.journey.gathering.planned = "garden"
	st.journey.workshop.stock.planter = 1
	st.journey.facts.append_array(["discovery_kitchen_garden", "crafted_lantern"])
	st.journey.exploration.collected = ["bistro_west", "bistro_east", "discovery_kitchen_garden", "seedbeds"]
	assert_str(JourneyGatherings.goal(st).target).is_equal("trail")
	assert_str(JourneyGatherings.goal(st).place).is_equal("bistro")
	st.journey.exploration.collected.erase("bistro_east")
	assert_str(JourneyGatherings.goal(st).target).is_equal("bistro_east")
	st.journey.exploration.routes_by_place = {"bistro": "stone_walk"}
	assert_str(JourneyGatherings.goal(st).surface).is_equal("street")
	st.journey.exploration.collected.append("bistro_east")
	st.journey.exploration.collected.erase("discovery_kitchen_garden")
	assert_str(JourneyGatherings.goal(st).target).is_equal("harvest:kitchen_garden:flowers")
	st.journey.exploration.collected.append("discovery_kitchen_garden")
	st.cells = {"1,1": {"crop": "H", "state": "growing", "ready_at": 1000}}
	assert_str(JourneyGatherings.goal(st, 1000).action).is_equal("harvest")
