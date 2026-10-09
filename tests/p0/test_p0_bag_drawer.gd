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
	d.set_sort("Recent")
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

## int10c 256 ②: River Perch → Lettuce → Radish left the card tall (its new lines measure tall before they have a
## width, its minimum ended where it was, so the drawer never fitted it again): medallion centred out of sight, the
## bottom edge under the grid. The card fits its content after every switch.
func test_switching_items_keeps_the_card_fitted_to_its_content() -> void:
	var v := {"bag": {"capacity": 25, "slots": [{"id": "fish_perch", "qty": 2}, {"id": "crop_lettuce", "qty": 2},
		{"id": "crop_radish", "qty": 2}]},
		"items": {"fish_perch": {"rarity": 2, "sell": 9}, "crop_lettuce": {"sell": 4}, "crop_radish": {"sell": 5}},
		"names": {"fish_perch": "River Perch", "crop_lettuce": "Lettuce", "crop_radish": "Radish"}}
	var d := P0BagDrawer.new(v, "bag")
	d.animate = false
	d.persist = false
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	host.add_child(d)
	for i in 3: await get_tree().process_frame
	for id in ["fish_perch", "crop_lettuce", "crop_radish"]:
		d.grid.select(id)
		for i in 4: await get_tree().process_frame
		assert_float(d.sheet.size.y).override_failure_message(id).is_equal(d.sheet.get_combined_minimum_size().y)
		assert_float(d.sheet.get_rect().end.y).is_less_equal(d.grid.position.y)
		assert_float(d.sheet._medallion.get_global_rect().end.y).is_less_equal(d.sheet.get_global_rect().end.y)

## int10c 256 ③ (不知火舞): the Bag side's header on both sides; switching back and forth moves neither the switch
## nor where the content starts.
func test_switching_bag_and_gear_moves_nothing() -> void:
	var d := _drawer()
	for i in 3: await get_tree().process_frame
	var tabs_y := d.header.tabs().global_position.y
	var content_y := d._bag_box.global_position.y
	var strip := d._chips.get_parent() as Control
	var chips_mid := strip.get_global_rect().get_center().y
	for i in 10:
		var seg: BaseButton = d.header.tabs().tabs()[(i + 1) % 2]
		seg.pressed.emit()
		seg.button_pressed = true
		for f in 2: await get_tree().process_frame
		var box: Control = d._gear_box if d.side == "gear" else d._bag_box
		assert_str(d.side).is_equal("gear" if i % 2 == 0 else "bag")
		assert_float(d.header.tabs().global_position.y).is_equal(tabs_y)
		assert_float(box.global_position.y).is_equal(content_y)
		if d.side == "gear":   # the first lines share a centre line: the chips' row and `✓ Equipped`
			var badge := d._gear_box.find_children("*", "PanelContainer", true, false)[0] as Control
			assert_float(badge.get_global_rect().get_center().y).is_equal(chips_mid)

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
	d.set_category("Fish")         # each Tab keeps its own Sort (BagHeader main)
	assert_str(d.sort).is_equal("Type")
	assert_str(d.header.sort_button().label).is_equal("Sort · Type")
	d.set_category("All")
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

func test_refresh_skips_a_view_that_changes_nothing_shown_and_follows_a_new_count() -> void:
	var d := _drawer()
	await get_tree().process_frame
	var cell := d.grid.cell_for("fish_crucian")
	var v := _view()
	v["coins"] = 999            # not shown in the drawer
	d.refresh(v)
	assert_object(d.grid.cell_for("fish_crucian")).is_same(cell)
	v.bag.slots[0].qty = 4      # shown: the count follows
	d.refresh(v)
	assert_str(d.grid.cell_for("fish_crucian").quantity).is_equal("×4")
	assert_str(d.header._tabs.tabs()[0].find_child("Title", true, false).text).is_equal("Bag 5/25")

func test_gear_slot_change_is_reported_for_the_next_open() -> void:
	var d := _drawer("gear")
	await get_tree().process_frame
	var got := []
	d.gear_slot_changed.connect(func(k: String): got.append(k))
	var cells := d._gear_box.find_children("*", "UiItemCell", true, false)
	(cells[0] as UiItemCell).tapped.emit()   # Farming
	assert_array(got).is_equal(["farming"])
	await get_tree().process_frame   # the fishing rows leave at the end of the frame
	assert_int(d._gear_box.find_children("*", "UiGearRow", true, false).size()).is_equal(1)

# ---------------------------------------------------------------- profile (PROFILE-1-P0)

func test_profile_data_reads_the_view_and_hides_what_is_missing() -> void:
	var v := _view()
	v["skills"] = {"farming": {"level": 2, "xp": 70, "floor": 50, "next": 100}, "fishing": {"level": 1, "xp": 0, "floor": 0, "next": 40},
		"cooking": {"level": 10, "xp": 999, "floor": 900, "next": null}}
	v["profile"] = {"name": "Farmer", "city": "Shanghai", "climate": "Subtropical", "since_ms": 1791000000000.0,
		"farm": {"name": "Farmer's Homestead", "level": 1}}
	v["plots"] = [{"state": "growing", "crop": "crop_radish", "ready_in": 12720000}, {"state": "tilled"}]
	v["fishing"] = {"dex": [{"id": "fish_crucian", "caught": 2}, {"id": "fish_perch", "caught": 0}, {"id": "fish_bass", "caught": 1}]}
	v["cooking"] = {"cookbook": [{"id": "a", "name": "Grilled Crucian"}, {"id": "b", "name": null}]}
	var d := P0ProfilePage.profile_data(v)
	assert_str(str(d.name)).is_equal("Farmer")
	assert_str(str(d.home_line)).starts_with("Shanghai · Subtropical · Since ")
	assert_that(d.skills.map(func(s): return [s.key, s.level])).is_equal([["farming", 2], ["fishing", 1], ["cooking", 10]])
	assert_float(float(d.skills[0].progress)).is_equal_approx(0.4, 0.0001)
	assert_float(float(d.skills[2].progress)).is_equal(1.0)   # top level: full ring
	assert_str(str(d.farm.name)).is_equal("Farmer's Homestead")
	assert_str(str(d.farm.level_line)).is_equal("Level 1")
	assert_str(str(d.farm.status)).is_equal("Radishes ready 3h 32m")
	assert_that(d.collections.map(func(c): return [c.name, c.have, c.need])).is_equal([["Fish", 2, 3], ["Pages", 1, 2]])
	var bare := P0ProfilePage.profile_data({})
	assert_str(str(bare.name)).is_equal("You")
	assert_str(str(bare.home_line)).is_equal("")
	assert_str(str(bare.farm.level_line)).is_equal("")

func test_since_reads_month_day_and_the_year_when_not_this_one() -> void:
	var oct2 := Time.get_unix_time_from_datetime_dict({year = 2026, month = 10, day = 2, hour = 12}) * 1000.0
	var now := Time.get_unix_time_from_datetime_dict({year = 2026, month = 10, day = 8, hour = 12}) * 1000.0
	assert_str(P0ProfilePage.since_text(oct2, now)).is_equal("Oct 2")
	var later := Time.get_unix_time_from_datetime_dict({year = 2027, month = 1, day = 3, hour = 12}) * 1000.0
	assert_str(P0ProfilePage.since_text(oct2, later)).is_equal("Oct 2, 2026")

func test_profile_page_emits_back_edit_look_and_skill() -> void:
	var page := P0ProfilePage.new(_view())
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	host.add_child(page)
	await get_tree().process_frame
	var got := []
	page.back_pressed.connect(func(): got.append("back"))
	page.edit_look_pressed.connect(func(): got.append("look"))
	page.skill_pressed.connect(func(k: String): got.append(k))
	page.top_bar.back_pressed.emit()
	(page.find_children("*", "UiNavButton", true, false)[0] as UiNavButton).pressed.emit()
	(page.find_children("*", "UiSkillCard", true, false)[1] as UiSkillCard).pressed.emit()
	assert_array(got).is_equal(["back", "look", "fishing"])
	assert_float(page.top_bar.right_button().modulate.a).is_equal(0.0)   # no Settings page in P0 yet

func _mouse(down: bool) -> InputEventMouseButton:
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = down
	return m

func _motion(rel: Vector2) -> InputEventMouseMotion:
	var m := InputEventMouseMotion.new()
	m.relative = rel
	return m

## int10c 256 ⑦: a sideways drag over the outfit turns the figure (0.01 rad a pixel, as in the dressing room) once it
## is past the tap slop; an upward drag is left to the page's scroll; nothing turns before the press.
func test_a_sideways_drag_on_the_outfit_turns_the_figure() -> void:
	var page := P0ProfilePage.new(_view())
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	host.add_child(page)
	await get_tree().process_frame
	var spin := page.spin
	spin._gui_input(_motion(Vector2(40, 0)))   # no press: no turn
	assert_float(page.preview.yaw()).is_equal(0.0)
	spin._gui_input(_mouse(true))
	spin._gui_input(_motion(Vector2(10, 0)))   # within the tap slop: not yet
	assert_bool(spin.turning()).is_false()
	spin._gui_input(_motion(Vector2(10, 2)))   # past it, sideways: turning from here
	assert_bool(spin.turning()).is_true()
	spin._gui_input(_motion(Vector2(20, 0)))
	assert_float(page.preview.yaw()).is_equal_approx(-0.3, 0.0001)
	spin._gui_input(_mouse(false))
	assert_bool(spin.turning()).is_false()
	var before := page.preview.yaw()
	spin._gui_input(_mouse(true))
	for i in 4: spin._gui_input(_motion(Vector2(2, -12)))   # mostly upward: the page scrolls, the figure stays
	spin._gui_input(_mouse(false))
	assert_float(page.preview.yaw()).is_equal(before)

# ---------------------------------------------------------------- Farm Storage (§10.4.8)

func test_storage_stacks_follow_the_bag_on_their_tabs_at_home_only() -> void:
	var v := _view()
	v["storage"] = {"items": [{"id": "wood", "qty": 99}, {"id": "seed_radish", "qty": 40}]}
	v.items["wood"] = {"kind": "material"}
	var ready := &"storage" in P0ItemInfo.CONTEXTS
	var mats := P0BagDrawer.storage_items(v, "Materials")
	if ready:
		assert_that(mats.map(func(it): return [it.id, it.item, it.qty, it.stored])).is_equal([["storage:wood", "wood", 99, true]])
		assert_str(P0BagDrawer.hint_for("Materials", true)).is_equal("Materials · Bag first, then Farm Storage")
	else:
		assert_array(mats).is_empty()   # no storage card in the rules yet: no dead cells
	assert_array(P0BagDrawer.storage_items(v, "All")).is_empty()
	assert_array(P0BagDrawer.storage_items(v, "Materials", "pond")).is_empty()
	v.storage.items.append({"id": "fert_compost", "qty": 6})   # §10.4.2: compost sits on the Seeds tab
	if ready:
		assert_that(P0BagDrawer.storage_items(v, "Seeds").map(func(it): return it.item)).is_equal(["seed_radish", "fert_compost"])
	v.erase("storage")
	assert_array(P0BagDrawer.storage_items(v, "Seeds")).is_empty()
	assert_str(P0BagDrawer.hint_for("Seeds", false)).is_equal("Select an item to see its details.")

func test_mining_slot_lists_the_picks_with_equip() -> void:
	var v := _view()
	v.gear.slots.mining = "pick_starter"
	v.gear["picks"] = [{"id": "pick_starter", "name": "Starter Pickaxe", "owned": true, "equipped": true, "stone": 1, "level": 0, "price": 0, "source": "start"},
		{"id": "pick_copper", "name": "Copper Pickaxe", "owned": true, "equipped": false, "stone": 2, "level": 0, "price": 0, "source": "workbench"}]
	v.names["pick_copper"] = "Copper Pickaxe"
	v.names["pick_starter"] = "Starter Pickaxe"
	var rows := P0BagDrawer.gear_rows(v, "mining")
	assert_that(rows.map(func(r): return r.state)).is_equal([&"equipped", &"owned"])
	assert_str(str(rows[1].effect)).is_equal("2 Stone per rock")
	assert_str(str(rows[1].action.label)).is_equal("Equip")
	assert_bool((rows[0].action as Dictionary).is_empty()).is_true()

func test_full_bag_shows_where_more_room_comes_from() -> void:
	var v := _view()
	v.bag.capacity = 2
	v.bag.slots = [{"id": "seed_radish", "qty": 5}, {"id": "fish_crucian", "qty": 1}]
	v["homestead"] = {"unlocks": {"bag_upgrade_1": "locked"}}
	var up: Dictionary = P0Logic.content().bag_upgrades[0]
	assert_str(P0BagDrawer.bag_full_text(v)).is_equal("Bag full · +%d slots at Homestead Lv%d" % [int(up.capacity) - 2, int(up.homestead)])
	v.homestead.unlocks.bag_upgrade_1 = "for_sale"
	assert_str(P0BagDrawer.bag_full_text(v)).is_equal("Bag full · +%d slots · %s" % [int(up.capacity) - 2, str(up.name)])
	v.homestead.unlocks.bag_upgrade_1 = "owned"
	assert_str(P0BagDrawer.bag_full_text(v)).is_equal("")
	v.homestead.unlocks.bag_upgrade_1 = "locked"
	v.bag.capacity = 25
	assert_str(P0BagDrawer.bag_full_text(v)).is_equal("")   # room left: no row
