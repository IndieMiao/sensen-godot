extends GdUnitTestSuite
## P1 trees on the 40-plot farm (q(118) ①, SGODOT-240; keys 不知火舞 on 241): a sapling plants through the main key
## (`Plant` / `6 Energy`, one press one tree), a ripe tree is picked (`Pick` / `2 Energy`), Orchard Feed fertilizes a
## picked tree, and a regrowing tree stays grown.

func _view(used := 2, cap := 3, energy := 120) -> Dictionary:
	return {"energy": {"value": energy, "max": 200}, "orchard": {"used": used, "cap": cap, "homestead_next": 3},
		"bag": {"capacity": 25, "slots": [{"id": "seed_apple", "qty": 2}, {"id": "fert_orchard", "qty": 1}]},
		"crops": [{"id": "crop_apple", "seed": "seed_apple", "energy": 6, "grow_h": 48, "level": 7, "perennial": true,
			"regrow_h": 48, "pick_energy": 2}, {"id": "crop_radish", "seed": "seed_radish", "energy": 2, "grow_h": 4, "level": 1}]}

func test_a_sapling_plants_on_an_empty_plot_one_press_one_tree() -> void:
	var v := _view()
	for st in ["tilled", "wild"]:
		var a := P0Logic.main_action(v, {"id": 4, "state": st}, "seed_apple", [{"id": 4, "state": "tilled"}, {"id": 5, "state": "tilled"}])
		assert_that([a.verb, a.sub, a.enabled, a.need, a.get("once", false)]).is_equal(["Plant", "6 Energy", true, 6, true])
		assert_that(a.cmd).is_equal({"type": "sow", "plot": 4, "seed": "seed_apple"})   # no Row Hoe for trees
	var full := P0Logic.main_action(_view(3, 3), {"id": 4, "state": "tilled"}, "seed_apple")
	assert_that([full.verb, full.sub, full.enabled, full.toast]).is_equal(["Plant", "Orchard 3/3", false, "Orchard 3/3 · Homestead Lv3 adds 1"])
	var tired := P0Logic.main_action(_view(2, 3, 4), {"id": 4, "state": "tilled"}, "seed_apple")
	assert_that([tired.verb, tired.sub, tired.amber, tired.cmd]).is_equal(["Plant", "Need 6 Energy", true, {"type": "energy_card"}])

func test_a_tree_is_picked_and_waits_while_it_grows() -> void:
	var v := _view()
	var ripe := P0Logic.main_action(v, {"id": 9, "state": "ready", "crop": "crop_apple", "tree": true, "picks": 1}, "seed_radish")
	assert_that([ripe.verb, ripe.sub, ripe.need, ripe.cmd]).is_equal(["Pick", "2 Energy", 2, {"type": "harvest", "plot": 9}])
	var growing := P0Logic.main_action(v, {"id": 9, "state": "growing", "crop": "crop_apple", "tree": true, "picks": 1, "ready_in": 3600000}, "fert_compost")
	assert_that([growing.verb, growing.enabled]).is_equal(["Growing", false])   # Compost does nothing for a tree

func test_orchard_feed_only_feeds_a_picked_regrowing_tree() -> void:
	var v := _view()
	var tree := {"id": 9, "state": "growing", "crop": "crop_apple", "tree": true, "picks": 1, "ready_in": 3600000}
	var a := P0Logic.main_action(v, tree, "fert_orchard")
	assert_that([a.verb, a.sub, a.enabled, a.cmd]).is_equal(["Fertilize", "Free", true, {"type": "fertilize", "plot": 9, "item": "fert_orchard"}])
	for no in [{"id": 2, "state": "growing", "crop": "crop_radish"}, {"id": 3, "state": "tilled"}, {"id": 4, "state": "wild"}]:
		var b := P0Logic.main_action(v, no, "fert_orchard")
		assert_that([b.verb, b.sub, b.enabled]).is_equal(["Fertilize", "No tree here", false])
	# 哪吒 on #252: with Orchard Feed in hand a tree that can't take it goes by its state — ripe is picked, its first
	# ripening or already fed shows how long it has
	var ripe := P0Logic.main_action(v, tree.merged({"state": "ready"}, true), "fert_orchard")
	assert_that([ripe.verb, ripe.sub, ripe.enabled]).is_equal(["Pick", "2 Energy", true])
	for wait in [tree.merged({"picks": 0}, true), tree.merged({"fert": true}, true)]:
		var g := P0Logic.main_action(v, wait, "fert_orchard")
		assert_that([g.verb, g.enabled]).is_equal(["Growing", false])

func test_a_picked_tree_regrowing_stays_grown() -> void:
	var v := _view()
	v.plots = [{"id": 0, "state": "growing", "crop": "crop_apple", "tree": true, "picks": 1, "ready_in": 40 * 3600000},
		{"id": 1, "state": "growing", "crop": "crop_apple", "tree": true, "picks": 0, "ready_in": 40 * 3600000}]
	v.garden = {"plots": 30}
	var cells := P0Garden.cells(v, 1000)
	var regrow: Dictionary = cells[P0Garden.cell_id(P0Garden.cell_of(0))]
	var young: Dictionary = cells[P0Garden.cell_id(P0Garden.cell_of(1))]
	assert_int(CropField.stage_of(regrow, 1000)).is_equal(2)   # grown, no fruit yet
	assert_int(CropField.stage_of(young, 1000)).is_equal(0)    # its first ripening: a sapling
