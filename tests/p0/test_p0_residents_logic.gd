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

## A plot by its [col, row] on the garden grid (content.garden.plots). _view()'s 12 beds (SGODOT-355 b1 order) are row 4,
## cols 0–7, and row 3, cols 2–5.
static func _at(col: int, row: int) -> int: return P0Garden.id_of(P0Garden.PLOT_ORIGIN + Vector2i(col, row) * 2)

func _ids(v: Dictionary, front: int, dir: int) -> Array:
	return P0Logic.row_plots(v, _plot(v, front), 6, dir).map(func(p): return int(p.id))

func test_row_hoe_sows_three_plots_of_the_row_walking_way_first() -> void:
	var v := _view()
	var row := P0Logic.row_plots(v, _plot(v, _at(2, 4)), 6, 1)
	var three := [_at(2, 4), _at(3, 4), _at(4, 4)]
	assert_array(row.map(func(p): return int(p.id))).is_equal(three)
	var a := P0Logic.main_action(v, _plot(v, _at(2, 4)), "seed_radish", row)
	assert_str(str(a.verb)).is_equal("Sow ×3")
	assert_str(str(a.sub)).is_equal("6 Energy")
	assert_that(a.cmd).is_equal({"type": "sow", "plots": three, "seed": "seed_radish"})
	# at the end of a row it turns back
	assert_array(_ids(v, _at(7, 4), 1)).is_equal([_at(7, 4), _at(6, 4), _at(5, 4)])
	assert_array(_ids(v, _at(4, 4), -1)).is_equal([_at(4, 4), _at(3, 4), _at(2, 4)])

## The row ends where the open beds end (a bed still to open is no bed) and never runs on into the next row.
func test_row_hoe_stops_at_the_open_beds_and_keeps_to_its_row() -> void:
	var v := _view()
	assert_array(_ids(v, _at(5, 3), 1)).is_equal([_at(5, 3), _at(4, 3), _at(3, 3)])    # (6, 3) is not open yet
	assert_array(_ids(v, _at(2, 3), -1)).is_equal([_at(2, 3), _at(3, 3), _at(4, 3)])   # nor (1, 3)
	assert_array(_ids(v, _at(0, 4), -1)).is_equal([_at(0, 4), _at(1, 4), _at(2, 4)])   # nor (−1, 4)

func test_row_hoe_skips_plots_that_are_not_tilled_and_trims_to_seeds_and_energy() -> void:
	var v := _view()
	_plot(v, _at(4, 4)).state = "sown"
	_plot(v, _at(1, 4)).state = "sown"
	assert_array(_ids(v, _at(3, 4), 1)).is_equal([_at(3, 4), _at(2, 4)])
	var row := P0Logic.row_plots(v, _plot(v, _at(5, 4)), 6, 1)
	v.energy.value = 5   # covers two plots
	var a := P0Logic.main_action(v, _plot(v, _at(5, 4)), "seed_radish", row)
	assert_str(str(a.verb)).is_equal("Sow ×2")
	assert_that(a.cmd).is_equal({"type": "sow", "plots": [_at(5, 4), _at(6, 4)], "seed": "seed_radish"})
	v.energy.value = 1
	var short := P0Logic.main_action(v, _plot(v, _at(5, 4)), "seed_radish", row)
	assert_bool(bool(short.amber)).is_true()
	assert_str(str(short.sub)).is_equal("Need 6 Energy")
	v.energy.value = 200
	v.bag.slots = [{"id": "seed_radish", "qty": 1}]
	assert_that(P0Logic.main_action(v, _plot(v, _at(5, 4)), "seed_radish", row).cmd).is_equal({"type": "sow", "plot": _at(5, 4), "seed": "seed_radish"})

## SGODOT-355 b1 (不知火舞 on the grid, as q(130)): annuals stand on at most the level's Plots. A full field greys the key
## with the count; its toast says what the next level adds (from the content ladder), only the count at the top; a Row
## Hoe sows only the Plots left.
func test_a_full_field_greys_sow_with_the_plots_count() -> void:
	var v := _view()
	v["homestead"] = {"level": 1}
	v["garden"] = {"plots": 12, "fields": {"used": 8, "cap": 8}}
	var a := P0Logic.main_action(v, _plot(v, _at(2, 4)), "seed_radish")
	assert_that([a.verb, a.sub, a.enabled, a.toast]).is_equal(["Sow", "Plots 8/8", false, "Plots 8/8 · Homestead Lv2 adds 2"])
	v.homestead.level = 15
	v.garden.fields = {"used": 36, "cap": 36}
	assert_str(str(P0Logic.main_action(v, _plot(v, _at(2, 4)), "seed_radish").toast)).is_equal("Plots 36/36 · Homestead Lv16 adds 3")
	v.homestead.level = 17
	v.garden.fields = {"used": 41, "cap": 41}
	var top := P0Logic.main_action(v, _plot(v, _at(2, 4)), "seed_radish")
	assert_that([top.sub, top.toast]).is_equal(["Plots 41/41", "Plots 41/41"])
	v.garden.fields = {"used": 39, "cap": 41}   # two left: the Row Hoe's three trims to two
	var row := P0Logic.row_plots(v, _plot(v, _at(2, 4)), 6, 1)
	assert_that(P0Logic.main_action(v, _plot(v, _at(2, 4)), "seed_radish", row).cmd).is_equal(
		{"type": "sow", "plots": [_at(2, 4), _at(3, 4)], "seed": "seed_radish"})

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

func test_the_stage_index_follows_the_content_table_and_reads_unknown_as_stranger() -> void:
	assert_int(int(P0Logic.resident_bar(_res({}), "res_pip").stage_index)).is_equal(1)   # Acquainted
	for i in 5:
		var name := str(["Stranger", "Acquainted", "Familiar", "Trusted", "Kindred"][i])
		assert_int(P0Logic.affinity_stage_index(name)).is_equal(i)
	assert_int(P0Logic.affinity_stage_index("")).is_equal(0)
	assert_int(P0Logic.affinity_stage_index("Soulmate")).is_equal(0)

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

## q(104): a taken request for a fish the player cannot land yet reads the level on its button — Old Kai's Rare fish is
## the Golden Koi, Fishing Lv4 — and the usual gap once they reach it.
func test_a_fish_request_above_the_players_level_asks_for_the_level() -> void:
	var koi := {"id": "req_res_kai_1", "kind": "fish", "rarity": 3, "qty": 1, "coins": 60, "have": 0, "ready": false}
	var v := _res({})
	v.residents["res_old_kai"] = (v.residents.res_pip as Dictionary).merged({"request": koi, "request_state": "accepted"}, true)
	v["skills"] = {"fishing": {"level": 2}}
	var b := P0Logic.resident_bar(v, "res_old_kai")
	assert_str(str(b.request_label)).is_equal("Deliver")
	assert_str(str(b.request_reason)).is_equal("Fishing Lv4 needed")
	assert_dict(b.request_cmd).is_empty()
	assert_str(str(P0Ui._request_card_data(v, "res_old_kai", b).reason)).is_equal("Fishing Lv4 needed")   # the card's button
	v.skills.fishing.level = 4
	assert_str(str(P0Logic.resident_bar(v, "res_old_kai").request_reason)).is_equal("Need 1 more Rare fish")
	# The level a request waits for: the lowest fish it can take that a pond or river holds.
	assert_int(P0Logic.fish_level_short({"skills": {"fishing": {"level": 1}}}, [], 2)).is_equal(2)   # perch, bass …
	assert_int(P0Logic.fish_level_short({"skills": {"fishing": {"level": 1}}}, ["fish_crucian"], null)).is_equal(0)
	assert_int(P0Logic.fish_level_short({"skills": {"fishing": {"level": 3}}}, ["fish_koi"], null)).is_equal(4)
	assert_int(P0Logic.fish_level_short({}, [], 1)).is_equal(0)   # no skills yet: Lv1, Common fish land

func test_resident_bar_gift_and_meal() -> void:
	assert_str(str(P0Logic.resident_bar(_res({"gift_today": true}), "res_pip").gift_reason)).is_equal("Gift already given today")
	var empty := _res({})
	empty.bag.slots = []
	assert_str(str(P0Logic.resident_bar(empty, "res_pip").gift_reason)).is_equal("No dishes in your bag")
	# A full bag sends the meal to the Inbox (SGODOT-232 S1), so there is no "free a slot" note any more.
	assert_str(str(P0Logic.resident_bar(_res({"meal": "ready"}), "res_pip").meal_note)).is_equal("")
	# Today's meal only while the meal is still there (in the bag from them, or as a parcel; 亚瑟 on #37).
	var given := _res({"meal": "given"})
	assert_bool(bool(P0Logic.resident_bar(given, "res_pip").meal)).is_false()   # eaten: no dead button
	given.bag.slots.append({"id": "dish_carrot_cake", "qty": 1, "gifted": true, "from": "res_pip"})
	assert_bool(bool(P0Logic.resident_bar(given, "res_pip").meal)).is_true()
	assert_str(P0Logic.resident_reply("res_old_kai", "not_a_fan")).is_equal("Hm. That's… a choice.")
	assert_str(P0Logic.resident_reply("res_pip", "loved")).is_equal("")

## SGODOT-284 P1: requests naming one item or a dish style write it on the button and the card (Granny Wu's Wood,
## her Soup; Theo's Carrots), and Recipe lesson shows only when the server says one is ready.
func test_p1_request_gaps_name_the_item_or_the_style() -> void:
	var v := _res({})
	var wu: Dictionary = (v.residents.res_pip as Dictionary).duplicate(true)
	wu.merge({"request": {"id": "req_res_wu_1", "kind": "material", "item": "wood", "qty": 6, "have": 2, "ready": false}, "request_state": "accepted"}, true)
	v.residents["res_granny_wu"] = wu
	var b := P0Logic.resident_bar(v, "res_granny_wu")
	assert_str(str(b.name)).is_equal("Granny Wu")
	assert_str(str(b.request_reason)).is_equal("Need 4 more %s" % P0Logic.plural(P0Logic.item_name(v, "wood")))
	var card := P0Ui._request_card_data(v, "res_granny_wu", b)
	assert_str(str(card.needs[0].name)).is_equal(P0Logic.item_name(v, "wood"))
	wu.request = {"id": "req_res_wu_2", "kind": "dish", "style": "Soup", "qty": 1, "have": 0, "ready": false}
	assert_str(str(P0Logic.resident_bar(v, "res_granny_wu").request_reason)).is_equal("Need 1 more Soup dish")
	assert_str(str(P0Ui._request_card_data(v, "res_granny_wu", P0Logic.resident_bar(v, "res_granny_wu")).needs[0].name)).is_equal("Soup dish")
	wu.request = {"id": "req_res_wu_2", "kind": "dish", "style": "Soup", "qty": 3, "have": 1, "ready": false}
	assert_str(str(P0Logic.resident_bar(v, "res_granny_wu").request_reason)).is_equal("Need 2 more Soup dishes")

func test_p1_recipe_lesson_and_likes_by_rarity() -> void:
	var v := _res({"lesson": {"state": "ready", "recipe": "dish_carrot_cake", "next_in": null, "need_stage": null}})
	assert_bool(bool(P0Logic.resident_bar(v, "res_pip").lesson)).is_true()
	v.residents.res_pip.lesson.state = "wait"
	assert_bool(bool(P0Logic.resident_bar(v, "res_pip").lesson)).is_false()
	assert_str(P0Logic.likes_text("Dessert")).is_equal("Dessert")
	assert_str(P0Logic.likes_text("Fine+")).is_equal("Fine dishes and up")
	assert_str(P0Logic.likes_text("Rare+")).is_equal("Rare dishes and up")
