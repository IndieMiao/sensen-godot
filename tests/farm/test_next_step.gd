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
	assert_str(NextStep.step_for(_slot("wild"), 0)).is_equal("clear")
	assert_str(NextStep.step_for(_slot("cleared"), 0)).is_equal("till")
	assert_str(NextStep.step_for(_slot("tilled"), 0)).is_equal("sow")
	assert_str(NextStep.step_for(_slot("sown", "R"), 0)).is_equal("care")
	assert_str(NextStep.step_for(_slot("growing", "R", 500), 499)).is_equal("")      # 没熟：没事可做
	assert_str(NextStep.step_for(_slot("growing", "R", 500), 500)).is_equal("harvest")

func test_bulk_prefers_harvest_then_care_then_sow() -> void:
	var cells := {"a": _slot("growing", "R", 100), "b": _slot("sown", "R"), "c": _slot("tilled"), "d": _slot("wild")}
	var b := NextStep.bulk(cells, 100, _state(), "R", ["R", "L"])
	assert_str(b.action).is_equal("harvest")
	assert_array(b.cells).is_equal(["a"])
	assert_str(b.label).is_equal("Harvest 1 plot")
	cells.erase("a")
	b = NextStep.bulk(cells, 100, _state(), "R", ["R", "L"])
	assert_str(b.action).is_equal("care")
	assert_str(b.label).is_equal("Water 1 plot")
	cells.erase("b")
	b = NextStep.bulk(cells, 100, _state(), "R", ["R", "L"])
	assert_str(b.action).is_equal("sow")
	assert_str(b.label).is_equal("Sow 1 Radish")
	assert_str(b.crop).is_equal("R")

func test_care_verb_follows_the_weather() -> void:
	var cells := {"b": _slot("sown", "R")}
	assert_str(NextStep.bulk(cells, 0, _state({}, {}, "rain"), "R", ["R"]).label).is_equal("Drain 1 plot")
	assert_str(NextStep.bulk(cells, 0, _state({}, {}, "wind"), "R", ["R"]).label).is_equal("Shelter 1 plot")

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
	assert_str(NextStep.doing_label("care", "", "rain")).is_equal("Draining…")
	assert_str(NextStep.doing_label("harvest")).is_equal("Harvesting…")
