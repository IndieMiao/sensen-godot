extends GdUnitTestSuite
## SGODOT-228 client adapters: Row Hoe sowing, Compost and the resident dialogue bar (P0Logic, view facts only).

func _view() -> Dictionary:
	var plots := []
	for i in 12: plots.append({"id": i, "state": "tilled"})
	return {
		"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000},
		"crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2}],
		"names": {"seed_radish": "Radish Seeds"},
		"bag": {"capacity": 25, "slots": [{"id": "seed_radish", "qty": 20, "locked": false, "gifted": false}]},
		"plots": plots,
		"gear": {"hoes": [{"id": "hoe_starter", "equipped": false, "sow": 1}, {"id": "tool_row_hoe", "equipped": true, "sow": 3}]},
	}

func _plot(v: Dictionary, id: int) -> Dictionary:
	for p in v.plots:
		if int(p.id) == id: return p
	return {}

func test_row_hoe_sows_three_plots_of_the_row_walking_way_first() -> void:
	var v := _view()
	var row := P0Logic.row_plots(v, _plot(v, 1), 6, 1)
	assert_array(row.map(func(p): return int(p.id))).is_equal([1, 2, 3])
	var a := P0Logic.main_action(v, _plot(v, 1), "seed_radish", row)
	assert_str(str(a.verb)).is_equal("Sow ×3")
	assert_str(str(a.sub)).is_equal("6 Energy")
	assert_that(a.cmd).is_equal({"type": "sow", "plots": [1, 2, 3], "seed": "seed_radish"})
	# at the end of a row it turns back; rows never wrap (plot 6 starts the next row)
	assert_array(P0Logic.row_plots(v, _plot(v, 5), 6, 1).map(func(p): return int(p.id))).is_equal([5, 4, 3])
	assert_array(P0Logic.row_plots(v, _plot(v, 4), 6, -1).map(func(p): return int(p.id))).is_equal([4, 3, 2])

func test_row_hoe_skips_plots_that_are_not_tilled_and_trims_to_seeds_and_energy() -> void:
	var v := _view()
	_plot(v, 2).state = "sown"
	assert_array(P0Logic.row_plots(v, _plot(v, 1), 6, 1).map(func(p): return int(p.id))).is_equal([1, 0])
	var row := P0Logic.row_plots(v, _plot(v, 3), 6, 1)
	v.energy.value = 5   # covers two plots
	var a := P0Logic.main_action(v, _plot(v, 3), "seed_radish", row)
	assert_str(str(a.verb)).is_equal("Sow ×2")
	assert_that(a.cmd).is_equal({"type": "sow", "plots": [3, 4], "seed": "seed_radish"})
	v.energy.value = 1
	var short := P0Logic.main_action(v, _plot(v, 3), "seed_radish", row)
	assert_bool(bool(short.amber)).is_true()
	assert_str(str(short.sub)).is_equal("Need 6 Energy")
	v.energy.value = 200
	v.bag.slots = [{"id": "seed_radish", "qty": 1}]
	assert_that(P0Logic.main_action(v, _plot(v, 3), "seed_radish", row).cmd).is_equal({"type": "sow", "plot": 3, "seed": "seed_radish"})

func test_starter_hoe_sows_one() -> void:
	var v := _view()
	v.gear.hoes[0].equipped = true
	v.gear.hoes[1].equipped = false
	var row := P0Logic.row_plots(v, _plot(v, 1), 6, 1)
	assert_int(row.size()).is_equal(1)
	assert_str(str(P0Logic.main_action(v, _plot(v, 1), "seed_radish", row).verb)).is_equal("Sow ×1")

func test_compost_fertilizes_sown_and_growing_plots_once() -> void:
	var v := _view()
	var a := P0Logic.main_action(v, {"id": 2, "state": "sown"}, "fert_compost")
	assert_str(str(a.verb)).is_equal("Fertilize")
	assert_that(a.cmd).is_equal({"type": "fertilize", "plot": 2, "item": "fert_compost"})
	assert_str(str(P0Logic.main_action(v, {"id": 2, "state": "growing", "ready_in": 1000}, "fert_compost").verb)).is_equal("Fertilize")
	# already fertilized: back to the plot's own action; a tilled plot still needs a seed
	assert_str(str(P0Logic.main_action(v, {"id": 2, "state": "sown", "fert": true}, "fert_compost").verb)).is_equal("Water")
	assert_str(str(P0Logic.main_action(v, {"id": 2, "state": "tilled"}, "fert_compost").sub)).is_equal("Pick a seed")

func _res(over: Dictionary) -> Dictionary:
	var r := {"affinity": 28, "stage": "Acquainted", "stage_from": 15, "next_stage": "Familiar", "next_at": 45,
		"chatted_today": true, "gift_today": false, "meal": "none", "request": null, "request_state": "none",
		"need_stage": null, "next_in": null}
	r.merge(over, true)
	return {"residents": {"res_pip": r}, "bag": {"slots": [{"id": "dish_carrot_cake", "qty": 1}]}}

func test_resident_bar_reads_facts_and_the_content_table() -> void:
	var b := P0Logic.resident_bar(_res({}), "res_pip")
	assert_str(str(b.name)).is_equal("Pip")
	assert_str(str(b.role)).is_equal("Courier Kid")
	assert_str(str(b.portrait)).is_equal("pip")
	assert_str(str(b.line)).is_equal("You again! Got anything sweet?")
	assert_int(int(b.have)).is_equal(28)
	assert_int(int(b.need)).is_equal(45)
	assert_str(str(b.next)).is_equal("Familiar")
	assert_str(str(b.gift_reason)).is_equal("")
	assert_str(str(b.request_reason)).is_equal("No more requests")
	assert_bool(bool(b.lesson)).is_false()
	assert_dict(P0Logic.resident_bar(_res({}), "res_nobody")).is_empty()

func test_resident_bar_request_states() -> void:
	var req := {"id": "req_res_pip_1", "kind": "fish", "rarity": 1, "qty": 1, "coins": 20, "have": 0, "ready": false}
	var open := P0Logic.resident_bar(_res({"request": req, "request_state": "open"}), "res_pip")
	assert_str(str(open.request_label)).is_equal("Request")
	assert_that(open.request_cmd).is_equal({"type": "accept", "request": "req_res_pip_1"})
	var short := P0Logic.resident_bar(_res({"request": req, "request_state": "accepted"}), "res_pip")
	assert_str(str(short.request_label)).is_equal("Deliver")
	assert_str(str(short.request_reason)).is_equal("Need 1 more Common fish")
	var ready := req.duplicate()
	ready.have = 1
	ready.ready = true
	assert_that(P0Logic.resident_bar(_res({"request": ready, "request_state": "accepted"}), "res_pip").request_cmd) \
		.is_equal({"type": "deliver", "request": "req_res_pip_1"})
	var sow := {"id": "req_res_pip_2", "kind": "sow", "qty": 5, "have": 1, "ready": false}
	assert_str(str(P0Logic.resident_bar(_res({"request": sow, "request_state": "accepted"}), "res_pip").request_reason)).is_equal("Plant 4 more plots")
	assert_str(str(P0Logic.resident_bar(_res({"request_state": "wait", "next_in": 33120000}), "res_pip").request_reason)).is_equal("Next request in 9h 12m")
	assert_str(str(P0Logic.resident_bar(_res({"request_state": "stage", "need_stage": "Familiar"}), "res_pip").request_reason)).is_equal("Next request at Familiar")

func test_resident_bar_gift_and_meal() -> void:
	assert_str(str(P0Logic.resident_bar(_res({"gift_today": true}), "res_pip").gift_reason)).is_equal("Gift already given today")
	var empty := _res({})
	empty.bag.slots = []
	assert_str(str(P0Logic.resident_bar(empty, "res_pip").gift_reason)).is_equal("No dishes in your bag")
	# A full bag sends the meal to the Inbox (SGODOT-232 S1), so there is no "free a slot" note any more.
	assert_str(str(P0Logic.resident_bar(_res({"meal": "ready"}), "res_pip").meal_note)).is_equal("")
	assert_bool(bool(P0Logic.resident_bar(_res({"meal": "given"}), "res_pip").meal)).is_true()
	assert_str(P0Logic.resident_reply("res_old_kai", "not_a_fan")).is_equal("Hm. That's… a choice.")
	assert_str(P0Logic.resident_reply("res_pip", "loved")).is_equal("")
