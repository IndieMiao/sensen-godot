extends GdUnitTestSuite
## 今日目标：按状态自动打勾，顺序就是新手该走的路。

func _fresh() -> Dictionary:
	return {"xp": {"first_clear_cells": [], "first_harvest_crops": []}, "inventory": {"produce": {"R": 0}},
		"stall": {"settled": 0}, "sales_facts": {}, "clock": {"field_condition": "sunny"}}

func test_fresh_farm_has_all_seven_open_and_first_is_clear() -> void:
	var g := DayGoals.evaluate(_fresh(), {"a": {"state": "wild"}})
	assert_int(g.size()).is_equal(7)
	assert_int(DayGoals.done_count(g)).is_equal(0)
	assert_str(g[0].label).is_equal("Clear a plot")
	assert_str(g[3].label).is_equal("Water it")

func test_goals_follow_the_plot_states() -> void:
	var s := _fresh()
	assert_int(DayGoals.done_count(DayGoals.evaluate(s, {"a": {"state": "cleared"}}))).is_equal(1)
	assert_int(DayGoals.done_count(DayGoals.evaluate(s, {"a": {"state": "tilled"}}))).is_equal(2)
	assert_int(DayGoals.done_count(DayGoals.evaluate(s, {"a": {"state": "sown"}}))).is_equal(3)
	assert_int(DayGoals.done_count(DayGoals.evaluate(s, {"a": {"state": "growing"}}))).is_equal(4)

func test_harvest_sale_and_next_batch_come_from_server_facts() -> void:
	var s := _fresh()
	s.xp.first_harvest_crops = ["R"]
	var g := DayGoals.evaluate(s, {"a": {"state": "tilled"}})
	assert_int(DayGoals.done_count(g)).is_equal(5)          # 收过就意味着前面四步都做过
	s.sales_facts = {"0": {"R": 1}}
	assert_int(DayGoals.done_count(DayGoals.evaluate(s, {"a": {"state": "tilled"}}))).is_equal(6)
	assert_int(DayGoals.done_count(DayGoals.evaluate(s, {"a": {"state": "growing"}}))).is_equal(7)

func test_care_label_follows_weather() -> void:
	var s := _fresh()
	s.clock.field_condition = "rain"
	assert_str(DayGoals.evaluate(s, {})[3].label).is_equal("Drain it")
