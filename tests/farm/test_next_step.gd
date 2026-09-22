extends GdUnitTestSuite
## 「点一块田它自己知道该做什么」的决策表，与服务端状态机一一对应。

func _slot(state: String, crop = null, ready = null) -> Dictionary:
	return {"state": state, "crop": crop, "ready_at": ready, "care_done_at": 0 if ready != null else null}

func _state(seeds := {"R": 6, "L": 3}, produce := {}, fc := "sunny") -> Dictionary:
	var s := {"R": {"bought": 0, "bound": 0}, "L": {"bought": 0, "bound": 0}, "C": {"bought": 0, "bound": 0}, "H": {"bought": 0, "bound": 0}}
	for c in seeds:
		s[c].bound = seeds[c]
	return {"inventory": {"seeds": s, "produce": produce}, "clock": {"field_condition": fc}, "wallet": 180}

func test_each_state_has_exactly_one_next_step() -> void:
	# 空字典 = 还没开垦的荒地，这是稀疏存储在客户端的全部体现。
	assert_str(NextStep.step_for({}, 0)).is_equal("till")
	assert_str(NextStep.step_for({"state": "tilled"}, 0)).is_equal("sow")
	assert_str(NextStep.step_for({"state": "sown"}, 0)).is_equal("water")
	assert_str(NextStep.step_for({"state": "growing", "ready_at": 100}, 50)).is_equal("")
	assert_str(NextStep.step_for({"state": "growing", "ready_at": 100}, 100)).is_equal("harvest")
	# ready_at 未知一律没事可做：客户端从不猜时长。
	assert_str(NextStep.step_for({"state": "growing", "ready_at": null}, 999)).is_equal("")


func test_bulk_prefers_harvest_then_water_then_sow() -> void:
	var cells := {"a": _slot("growing", "R", 100), "b": _slot("sown", "R"), "c": _slot("tilled")}
	var b := NextStep.bulk(cells, 100, _state(), "R", ["R", "L"])
	assert_str(b.action).is_equal("harvest")
	assert_array(b.cells).is_equal(["a"])
	assert_str(b.label).is_equal("Harvest 1 plot")
	cells.erase("a")
	b = NextStep.bulk(cells, 100, _state(), "R", ["R", "L"])
	assert_str(b.action).is_equal("water")
	assert_str(b.label).is_equal("Water 1 plot")
	cells.erase("b")
	b = NextStep.bulk(cells, 100, _state(), "R", ["R", "L"])
	assert_str(b.action).is_equal("sow")
	assert_str(b.label).is_equal("Sow 1 Radish")
	assert_str(b.crop).is_equal("R")

func test_sow_is_capped_by_seeds_and_falls_back_to_a_crop_that_has_some() -> void:
	var cells := {"a": _slot("tilled"), "b": _slot("tilled"), "c": _slot("tilled"), "d": _slot("tilled")}
	var b := NextStep.bulk(cells, 0, _state({"R": 2, "L": 3}), "R", ["R", "L"])
	assert_int(b.cells.size()).is_equal(2)
	assert_str(b.label).is_equal("Sow 2 Radish")
	b = NextStep.bulk(cells, 0, _state({"R": 0, "L": 3}), "R", ["R", "L"])
	assert_str(b.crop).is_equal("L")
	assert_str(b.label).is_equal("Sow 3 Lettuce")

func test_no_seeds_points_to_the_stall() -> void:
	var cells := {"a": _slot("tilled")}
	var b := NextStep.bulk(cells, 0, _state({}), "R", ["R", "L"])
	assert_str(b.action).is_equal("stall")
	assert_str(b.label).is_equal("Buy seeds at the stall")

func test_produce_in_hand_points_to_the_stall_before_waiting() -> void:
	var cells := {"a": _slot("growing", "R", 999)}
	var b := NextStep.bulk(cells, 0, _state({}, {"R": 2}), "R", ["R"])
	assert_str(b.action).is_equal("stall")
	assert_str(b.label).is_equal("Sell 2 at the stall")

func test_stall_budget_too_small_for_one_item_falls_back_to_growing() -> void:
	var state := _state({}, {"R": 2})
	state.stall = {"settled": 95}
	state.inventory.dishes = {"salad": 1}
	var bulk := NextStep.bulk({"a": _slot("growing", "R", 999)}, 0, state, "R", ["R"])
	assert_str(bulk.action).is_equal("")
	assert_str(bulk.label).is_equal("Crops are growing")
	assert_bool(bulk.enabled).is_false()

func test_stall_recommendation_counts_only_the_quantity_that_fits_the_budget() -> void:
	var state := _state({}, {"R": 3})
	state.stall = {"settled": 84}
	var bulk := NextStep.bulk({}, 0, state, "R", ["R"])
	assert_str(bulk.action).is_equal("stall")
	assert_str(bulk.label).is_equal("Sell 2 at the stall")
	assert_bool(bulk.enabled).is_true()
	state.stall.settled = 100
	bulk = NextStep.bulk({"a": _slot("tilled")}, 0, state, "R", ["R"])
	assert_str(bulk.label).is_equal("Buy seeds at the stall")

func test_stall_recommendation_shares_the_budget_in_stall_crop_order() -> void:
	var state := _state({}, {"L": 2, "R": 2})
	state.stall = {"settled": 76}
	var bulk := NextStep.bulk({}, 0, state, "R", ["R", "L"])
	assert_str(bulk.label).is_equal("Sell 2 at the stall")
	assert_dict(state.inventory.produce).is_equal({"L": 2, "R": 2})
	assert_int(state.stall.settled).is_equal(76)

func test_engineering_reservations_reduce_sale_count_and_preserve_other_next_steps() -> void:
	var state := _state({}, {"C": 3, "H": 4})
	state.engineering = {"reserved": {"C": 2, "H": 4}}
	var bulk := NextStep.bulk({}, 0, state, "C", CropInfo.ORDER)
	assert_str(bulk.label).is_equal("Sell 1 at the stall")
	state.inventory.produce.C = 2
	bulk = NextStep.bulk({"a": _slot("growing", "C", 999)}, 0, state, "C", CropInfo.ORDER)
	assert_str(bulk.label).is_equal("Crops are growing")
	assert_bool(bulk.enabled).is_false()
	bulk = NextStep.bulk({"a": _slot("tilled")}, 0, state, "C", CropInfo.ORDER)
	assert_str(bulk.label).is_equal("Buy seeds at the stall")

func test_waiting_and_done_are_disabled_states() -> void:
	var growing := NextStep.bulk({"a": _slot("growing", "R", 999)}, 0, _state({}), "R", ["R"])
	assert_bool(growing.enabled).is_false()
	assert_str(growing.label).is_equal("Crops are growing")
	var done := NextStep.bulk({}, 0, _state({}), "R", ["R"])
	assert_bool(done.enabled).is_false()
	assert_str(done.label).is_equal("All done for today")

func test_seed_lot_uses_bound_first() -> void:
	var inv := {"seeds": {"R": {"bought": 2, "bound": 1}}}
	assert_str(NextStep.seed_lot(inv, "R")).is_equal("bound")
	assert_int(NextStep.seeds_of(inv, "R")).is_equal(3)
	assert_str(NextStep.seed_lot({"seeds": {"R": {"bought": 2, "bound": 0}}}, "R")).is_equal("bought")

func test_doing_labels_are_english_and_name_the_crop() -> void:
	assert_str(NextStep.doing_label("clear")).is_equal("Clearing…")
	assert_str(NextStep.doing_label("sow", "L")).is_equal("Sowing Lettuce…")
	assert_str(NextStep.doing_label("harvest")).is_equal("Harvesting…")



func test_d0_after_confirmed_first_harvest_recommends_the_full_next_batch() -> void:
	var state := _state({"R": 6, "L": 3})
	state.clock.chapter_index = 0
	state.chapters = [{"step_flags": {"first_harvest": true}}]
	var cells := {}
	for index in 9: cells[str(index)] = _slot("tilled")
	var bulk := NextStep.bulk(cells, 0, state, "R", ["R", "L"])
	assert_str(bulk.crop).is_equal("R")
	assert_int(bulk.cells.size()).is_equal(6)
	for index in 6: cells[str(index)] = _slot("growing", "R", 999)
	state.inventory.seeds.R.bound = 0
	bulk = NextStep.bulk(cells, 0, state, "R", ["R", "L"])
	assert_str(bulk.crop).is_equal("L")
	assert_int(bulk.cells.size()).is_equal(3)

func test_legacy_harvest_fact_and_later_chapters_do_not_keep_the_tutorial_limit() -> void:
	var state := _state({"R": 0, "L": 3})
	state.clock.chapter_index = 0
	state.xp = {"first_harvest_crops": ["R"]}
	assert_str(NextStep.bulk({"a": _slot("tilled")}, 0, state, "L", ["R", "L"]).crop).is_equal("L")
	state.clock.chapter_index = 1
	state.xp = {}
	assert_str(NextStep.bulk({"a": _slot("tilled")}, 0, state, "L", ["R", "L"]).crop).is_equal("L")
