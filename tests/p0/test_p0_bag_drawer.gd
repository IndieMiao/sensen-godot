extends GdUnitTestSuite
## SGODOT-225 Bag | Gear drawer: data from the view, the item card on tap, the Gear side.

func _view() -> Dictionary:
	return {
		"bag": {"capacity": 25, "slots": [
			{"id": "fish_crucian", "qty": 3}, {"id": "seed_radish", "qty": 20}, {"id": "dish_grilled_crucian", "qty": 1},
			{"id": "crop_radish", "qty": 12}, {"id": "bait_worm", "qty": 5}]},
		"items": {"fish_crucian": {"rarity": 1, "sell": 6}, "dish_grilled_crucian": {"rarity": 2, "full": 45, "base": "dish_grilled_fish"},
			"crop_radish": {"sell": 5}},
		"names": {"fish_crucian": "Pond Crucian", "seed_radish": "Radish Seeds", "crop_radish": "Radish",
			"dish_grilled_crucian": "Grilled Crucian", "bait_worm": "Worm Bait", "rod_starter": "Starter Rod",
			"rod_reed": "Reed Rod", "rod_carbon": "Carbon Rod", "hoe_starter": "Starter Hoe"},
		"gear": {"slots": {"farming": "hoe_starter", "fishing": "rod_starter", "mining": null, "combat": null},
			"rods": [
				{"id": "rod_starter", "name": "Starter Rod", "reach": 2, "level": 1, "price": 0, "owned": true, "equipped": true},
				{"id": "rod_reed", "name": "Reed Rod", "reach": 3, "level": 3, "price": 80, "owned": true, "equipped": false},
				{"id": "rod_carbon", "name": "Carbon Rod", "reach": 4, "level": 5, "price": 350, "owned": false, "equipped": false}]},
		"skills": {"fishing": {"level": 3}},
	}

func test_bag_items_sort_by_type_by_default_or_keep_the_server_order() -> void:
	var v := _view()
	var recent := P0BagDrawer.bag_items(v, "Recent").map(func(it): return it.id)
	assert_that(recent).is_equal(["fish_crucian", "seed_radish", "dish_grilled_crucian", "crop_radish", "bait_worm"])
	var by_type := P0BagDrawer.bag_items(v).map(func(it): return it.id)
	assert_that(by_type).is_equal(["seed_radish", "fish_crucian", "crop_radish", "dish_grilled_crucian", "bait_worm"])
	# inside one category: rarity high → low, then count high → low, then most recent first
	v.bag.slots = [{"id": "fish_crucian", "qty": 3}, {"id": "fish_perch", "qty": 1}, {"id": "fish_carp", "qty": 9}, {"id": "fish_bass", "qty": 9}]
	v.items.merge({"fish_perch": {"rarity": 2}, "fish_carp": {"rarity": 1}, "fish_bass": {"rarity": 1}})
	assert_that(P0BagDrawer.bag_items(v).map(func(it): return it.id)).is_equal(["fish_perch", "fish_carp", "fish_bass", "fish_crucian"])
	v = _view()
	var first: Dictionary = P0BagDrawer.bag_items(v, "Recent")[0]
	assert_int(int(first.qty)).is_equal(3)
	assert_int(int(first.rarity)).is_equal(1)
	assert_int(int(P0BagDrawer.bag_items(v, "Recent")[3].rarity)).is_equal(0)   # crops carry no rarity dot

func test_categories_map_onto_the_item_kinds() -> void:
	var v := _view()
	var counts := {}
	for cat in P0BagDrawer.CATEGORIES:
		counts[cat] = P0BagDrawer.bag_items(v).filter(func(it): return P0BagDrawer.in_category(it, cat)).size()
	assert_that(counts).is_equal({"All": 5, "Seeds": 1, "Fish": 1, "Produce": 1, "Dishes": 1, "Materials": 0, "Tackle": 1})

func test_gear_has_six_slots_and_rod_candidates_follow_the_rules() -> void:
	var v := _view()
	var slots := P0BagDrawer.gear_slots(v)
	assert_that(slots.map(func(s): return s.key)).is_equal(P0BagDrawer.GEAR_SLOTS)
	assert_that(slots.map(func(s): return s.empty)).is_equal([false, false, true, true, true, true])
	assert_str(str(slots[0].name)).is_equal("Starter Hoe")
	var rows := P0BagDrawer.gear_rows(v, "fishing")
	assert_that(rows.map(func(r): return r.state)).is_equal([&"equipped", &"owned", &"Fishing Lv5 · Tackle Shop"])
	assert_bool((rows[0].action as Dictionary).is_empty()).is_true()            # equipped: the badge, no button
	assert_str(str(rows[1].action.label)).is_equal("Equip")
	assert_bool((rows[2].action as Dictionary).is_empty()).is_true()            # not owned: no jump to the shop (LOCK-08)
	assert_str(str(rows[1].effect)).contains("Lands up to")
	assert_that(P0BagDrawer.gear_rows(v, "farming").map(func(r): return r.state)).is_equal([&"equipped"])
	assert_array(P0BagDrawer.gear_rows(v, "ring")).is_empty()

func _drawer(side := "bag") -> P0BagDrawer:
	var d := P0BagDrawer.new(_view(), side)
	d.animate = false
	d.persist = false
	d.sort = "Recent"
	d.refresh(d.view)
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	host.add_child(d)
	return d

func test_tapping_a_cell_opens_the_bag_card_and_a_blank_cell_folds_it() -> void:
	var d := _drawer()
	await get_tree().process_frame
	assert_bool(d.sheet.is_open()).is_false()
	assert_bool(d._hint.visible).is_true()
	d.grid.cells()[0].tapped.emit()
	assert_bool(d.sheet.is_open()).is_true()
	assert_str(d.sheet.item_id()).is_equal("fish_crucian")
	assert_str(String(d.sheet.context())).is_equal("bag")
	assert_bool(d._hint.visible).is_false()
	d.grid.cells()[20].tapped.emit()   # an empty cell
	assert_bool(d.sheet.is_open()).is_false()
	assert_bool(d._hint.visible).is_true()

func test_category_chip_and_sort_change_what_the_grid_lists() -> void:
	var d := _drawer()
	await get_tree().process_frame
	d.set_category("Fish")
	assert_that(d.grid.shown_items().map(func(it): return it.id)).is_equal(["fish_crucian"])
	d.set_category("All")
	d.header.sort_pressed.emit()   # Recent → Type
	assert_str(d.sort).is_equal("Type")
	assert_str(String(d.grid.shown_items()[0].id)).is_equal("seed_radish")
	assert_str(d.header.sort_button().label).is_equal("Sort · Type")
	d.header.sort_pressed.emit()   # and back
	assert_str(d.sort).is_equal("Recent")

func test_gear_side_lists_the_slot_and_forwards_equip() -> void:
	var d := _drawer("gear")
	await get_tree().process_frame
	assert_bool(d._gear_box.visible).is_true()
	assert_bool(d._bag_box.visible).is_false()
	var rows := d._gear_box.find_children("*", "UiGearRow", true, false)
	assert_int(rows.size()).is_equal(3)
	var got := []
	d.action_requested.connect(func(a: StringName, id: String, _p: Dictionary): got.append([String(a), id]))
	(rows[1] as UiGearRow).action_button().activated.emit()
	assert_array(got).is_equal([["equip", "rod_reed"]])
	d.set_side("bag")
	assert_bool(d._bag_box.visible).is_true()
	assert_bool(d._gear_box.visible).is_false()
