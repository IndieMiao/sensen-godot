extends GdUnitTestSuite
## P1 step 1 (q(59) §1.2 / §1.6, SGODOT-240): Farming Lv5 and Lv6 — what their banners say, Lv6 as the day-changing
## banner with Show Workbench, and the Homestead Stall's three new seeds behind their gates.

func _view(xp := 600) -> Dictionary:
	return {"skills": {"farming": {"level": 5 if xp >= 500 else 4, "xp": xp}},
		"names": {"seed_cabbage": "Cabbage Seeds", "seed_corn": "Corn Seeds", "seed_cucumber": "Cucumber Seeds"},
		"stall": {"buy": []}, "bag": {"capacity": 25, "slots": []}}

## Lv5: `New for you · Cabbage, Corn, Regional seeds`, the tip says what Lv6 brings (the regional crops as one item,
## 李白 on #214); 1.5 s.
func test_farming_lv5_names_its_crops_and_points_at_lv6() -> void:
	var b := P0Logic.level_banner(_view(500), {"skill": "farming", "level": 5, "gifts": []})
	assert_str(str(b.title)).is_equal("Farming Lv5")
	assert_str(str(b.subtitle)).is_equal("New for you · Cabbage, Corn, Regional seeds")
	assert_str(str(b.tip)).is_equal("Next Lv6 · Cucumber, Sprinkler · 250\u00a0XP")
	assert_float(float(b.seconds)).is_equal(1.5)
	assert_str(str(b.action)).is_empty()

## Lv6 changes the day (q(59) §1.6): full banner ≤ 3 s, `Today changes: no more watering`, and Show Workbench.
func test_farming_lv6_is_the_day_changing_banner_with_show_workbench() -> void:
	var b := P0Logic.level_banner(_view(750), {"skill": "farming", "level": 6, "gifts": []})
	assert_str(str(b.subtitle)).is_equal("New for you · Cucumber, Sprinkler")
	assert_str(str(b.tip)).is_equal("Today changes: no more watering")
	assert_float(float(b.seconds)).is_equal(3.0)
	assert_that([b.action, b.action_id]).is_equal(["Show Workbench", "show_workbench"])

## Show Workbench only moves the camera to the workbench (LOCK-08): show_spot("workbench"), nothing opens.
func test_show_workbench_moves_the_camera_only() -> void:
	var ui := P0Ui.new()
	ui.quick_store = "user://test_p1_farming_levels_bar_%d.json" % OS.get_process_id()
	ui.tips_path = "user://test_p1_farming_levels_tips_%d.json" % OS.get_process_id()
	add_child(auto_free(ui))
	await await_idle_frame()
	var spots := []
	ui.show_spot.connect(func(w): spots.append(w))
	ui._banner_action("show_workbench")
	assert_array(spots).is_equal(["workbench"])
	assert_bool(ui.has_modal()).is_false()
	for f in [ui.quick_store, ui.tips_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

## The Homestead Stall lists the step-1 seeds after the Tomato, in gate order; the regional and tree seeds are the
## Market's (sold_at), not the stall's.
func test_the_stall_sells_the_new_seeds_in_gate_order() -> void:
	var buy: Array = P0Logic.content().stall.buy
	var at := buy.find("seed_tomato")
	assert_array(buy.slice(at + 1, at + 6)).is_equal(["seed_cabbage", "seed_corn", "seed_cucumber", "seed_strawberry", "seed_melon"])
	for c in P0Logic.content().crops:
		if str(c.get("sold_at", "stall")) != "stall": assert_bool(buy.has(str(c.seed))).override_failure_message(str(c.seed)).is_false()

## Seed Saver (Farming Lv10, §4.6.1): the level lists it after its crops, and a harvest that saves a seed floats it
## (seeds bought or harvested otherwise float nothing).
func test_seed_saver_is_lv10_and_floats_the_seed_it_gives_back() -> void:
	assert_array(P0Logic.level_unlocks(_view(2800), "farming", 10)).contains(["Seed Saver"])
	assert_array(P0Logic.level_unlocks(_view(2050), "farming", 9)).not_contains(["Seed Saver"])
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var v := {"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": []},
		"skills": {"farming": {"level": 10, "xp": 3000}}, "names": {"crop_radish": "Radish", "seed_radish": "Radish Seeds"}}
	rt.session.view = v
	rt._on_state(v, [{"kind": "xp", "skill": "farming", "amount": 1, "percent": 50},
		{"kind": "item", "id": "crop_radish", "delta": 1},
		{"kind": "item", "id": "seed_radish", "delta": 1}, {"kind": "seed_saved", "id": "seed_radish", "plot": 0}])
	await get_tree().process_frame
	var texts: Array = rt.ui.root.get_children().filter(func(c): return c is UiFloatText and not c.is_queued_for_deletion()).map(func(f): return f.text)
	# its own line after the harvest's items (李白 q(118)): `Seed Saver · +1 Radish Seeds`, not joined to `+1 Radish`
	assert_array(texts).contains(["+1 Radish", "Seed Saver · +1 Radish Seeds"])
	var many := P0Runtime.seed_saver_line(v, [{"kind": "seed_saved", "id": "seed_radish"}, {"kind": "seed_saved", "id": "seed_radish"}])
	assert_str(str(many.text)).is_equal("Seed Saver · +2 Radish Seeds")
	var mixed := P0Runtime.seed_saver_line(v, [{"kind": "seed_saved", "id": "seed_radish"}, {"kind": "seed_saved", "id": "seed_carrot"}])
	assert_str(str(mixed.text)).is_equal("Seed Saver · +2 seeds")

## Harvest All (Farming Lv9, q(118) ④): the key takes the ripe annuals of the row underfoot, `Harvest ×3`, this plot
## first; one ripe plot is still `Harvest`; below Lv9 always one.
func test_harvest_all_takes_the_row_underfoot_from_lv9() -> void:
	var v := {"skills": {"farming": {"level": 9}}, "garden": {"plots": 30}, "energy": {"value": 100}, "plots": [
		{"id": 6, "state": "ready", "crop": "crop_radish"}, {"id": 8, "state": "ready", "crop": "crop_carrot"},
		{"id": 9, "state": "growing", "crop": "crop_radish"}, {"id": 11, "state": "ready", "crop": "crop_radish"},
		{"id": 12, "state": "ready", "crop": "crop_radish"}]}   # 6–11 are row 1; 12 is row 2
	var a := P0Logic.main_action(v, v.plots[1], "")
	assert_that([a.verb, a.cmd]).is_equal(["Harvest ×3", {"type": "harvest", "plot": 8, "plots": [8, 6, 11]}])
	var one := P0Logic.main_action(v, v.plots[4], "")
	assert_that([one.verb, one.cmd]).is_equal(["Harvest", {"type": "harvest", "plot": 12}])
	v.skills.farming.level = 8
	assert_str(str(P0Logic.main_action(v, v.plots[1], "").verb)).is_equal("Harvest")
	assert_array(P0Logic.level_unlocks({"stall": {"buy": []}}, "farming", 9)).contains(["Harvest All"])

## q(123): the row goes near to far from the plot in front, so a bag that fills keeps what is nearest; equally near on
## both sides, the left one first.
func test_harvest_all_goes_near_to_far_from_the_plot_in_front() -> void:
	var v := {"skills": {"farming": {"level": 9}}, "garden": {"plots": 30}, "energy": {"value": 100}, "plots": []}
	for id in [6, 7, 8, 9, 10, 11]: v.plots.append({"id": id, "state": "ready", "crop": "crop_radish"})
	assert_array(P0Logic.harvest_row(v, v.plots[5])).is_equal([11, 10, 9, 8, 7, 6])   # from the right end
	assert_array(P0Logic.harvest_row(v, v.plots[0])).is_equal([6, 7, 8, 9, 10, 11])   # from the left end
	assert_array(P0Logic.harvest_row(v, v.plots[2])).is_equal([8, 7, 9, 6, 10, 11])   # from the middle: 7 before 9

## A fertiliser's bag card and buy row say what it does, NPC-2's words (不知火舞), not just how many.
func test_fertiliser_cards_say_what_they_do() -> void:
	assert_str(P0ItemInfo.fert_use("fert_orchard")).is_equal("Next regrow time −50%")
	assert_str(P0ItemInfo.fert_use("fert_compost")).is_equal("Crops ready 20% sooner")
	var v := {"bag": {"capacity": 25, "slots": [{"id": "fert_orchard", "qty": 2}]}, "names": {"fert_orchard": "Orchard Feed"}}
	assert_array(P0ItemInfo.spec(v, "fert_orchard", &"bag").facts).is_equal(["Next regrow time −50%", "2"])
	assert_str(str(P0ItemInfo.tokens(v, "fert_compost", &"counter_buy").use)).is_equal("Crops ready 20% sooner")

## The Growing key's second line fits its 80 px (不知火舞 on 241): two units drop `Ready in`, one keeps it.
func test_growing_key_drops_ready_in_for_two_units() -> void:
	assert_str(P0Logic.key_ready(48 * 3600000.0)).is_equal("Ready in 48h")
	assert_str(P0Logic.key_ready(42 * 60000.0)).is_equal("Ready in 42m")
	assert_str(P0Logic.key_ready((19 * 60 + 58) * 60000.0)).is_equal("19h 58m")
	var v := {"skills": {"farming": {"level": 1}}, "plots": []}
	var a := P0Logic.main_action(v, {"id": 3, "state": "growing", "crop": "crop_radish", "ready_in": (3 * 60 + 5) * 60000}, "")
	assert_that([a.verb, a.sub]).is_equal(["Growing", "3h 5m"])
