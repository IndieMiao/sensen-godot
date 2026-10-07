extends GdUnitTestSuite
## HOME-1 / HOME-2 models (Figma 482:152 / 482:154, §8.6.1, LOCK-10) from the server's homestead facts.

func _view(level := 2) -> Dictionary:
	var next := {"level": 3, "coins": {"need": 440, "have": 830}, "skills": {"need": 5, "have": 13, "farming": 7, "fishing": 6},
		"materials": [
			{"id": "wood", "name": "Timber", "need": 16, "have": 10, "storage": 10, "bag": 0},
			{"id": "stone", "name": "Stone", "need": 12, "have": 12, "storage": 12, "bag": 0},
			{"id": "fiber", "name": "Reeds", "need": 10, "have": 10, "storage": 10, "bag": 0},
			{"id": "clay", "name": "Clay", "need": 4, "have": 4, "storage": 4, "bag": 0},
			{"id": "rock_salt", "name": "Rock Salt", "need": 4, "have": 5, "storage": 5, "bag": 0}],
		"energy": 220, "meals": 220, "unlocks": ["warming_cabinet", "bag_upgrade_1", "board_slot_3", "fence"],
		"can_upgrade": false, "block": {"code": "need_material"}}
	return {"energy": {"value": 142, "max": 210}, "bag": {"capacity": 25},
		"skills": {"farming": {"level": 7}, "fishing": {"level": 6}},
		"homestead": {"level": level, "next": next, "unlocks": {"board_slots": 2}}}

func test_home_panel_matches_the_page_14_sample() -> void:
	var p := P0Logic.home_panel(_view())
	assert_str(str(p.title)).is_equal("Homestead Lv2 → Lv3")
	assert_str(str(p.look)).is_equal("Lv3 look · Full fence")
	assert_array(p.tiles.map(func(t): return str(t.name))).is_equal(["Timber", "Stone", "Reeds", "Clay", "Rock Salt", "Coins", "Skills"])
	assert_int(int(p.tiles[5].need)).is_equal(440)   # price + the 40-coin floor (q(10))
	assert_array(p.changes.map(func(c): return str(c.text))).is_equal(
		["Max Energy 220 · Meals 220 a day", "Warming Cabinet", "Bag Upgrade I for sale · 150 coins", "Stall Board · 3rd slot"])
	assert_array(p.changes.map(func(c): return str(c.note))).is_equal(["now 210", "keeps 6 dishes by the stove", "Bag 25 → 30", "now 2"])
	assert_str(str(p.reason)).is_equal("Need 6 more Timber")
	assert_str(str(p.footer)).is_equal("Upgrading is free of Energy · fills Energy to the new max")

func test_the_button_carries_the_first_gap_in_tile_order() -> void:
	var v := _view()
	v.homestead.next.materials[0].have = 16
	v.homestead.next.coins.have = 400
	assert_str(str(P0Logic.home_panel(v).reason)).is_equal("Need 40 more coins")
	v.homestead.next.coins.have = 440
	v.homestead.next.skills.have = 4
	assert_str(str(P0Logic.home_panel(v).reason)).is_equal("Skills total 5 needed · now 4")
	v.homestead.next.skills.have = 5
	var ready := P0Logic.home_panel(v)
	assert_str(str(ready.reason)).is_equal("")
	assert_str(str(ready.label)).is_equal("Upgrade")
	assert_str(str(P0Logic.home_panel(v, false).reason)).is_equal("Go home to upgrade · Free")

func test_lv1_to_lv2_lists_the_spice_rack_and_no_look_line() -> void:
	var v := _view(1)
	v.homestead.next.level = 2
	v.homestead.next.unlocks = ["spice_rack"]
	var p := P0Logic.home_panel(v)
	assert_str(str(p.look)).is_equal("")
	assert_str(str(p.changes[1].text)).is_equal("Spice Rack")

func test_p0_stops_at_lv3() -> void:
	var v := _view(3)
	v.homestead.next = null
	var p := P0Logic.home_panel(v)
	assert_bool(bool(p.max)).is_true()
	assert_str(str(p.title)).is_equal("Homestead Lv3")
	assert_array(p.tiles).is_empty()

func test_home_moment_matches_the_page_14_banner() -> void:
	var m := P0Logic.home_moment({"energy": {"max": 220}}, {"kind": "homestead", "level": 3, "unlocks": ["warming_cabinet", "bag_upgrade_1", "board_slot_3", "fence"]})
	assert_str(str(m.title)).is_equal("Homestead Lv 3")
	assert_str(str(m.subtitle)).is_equal("Max Energy 220 · Energy full")
	assert_str(str(m.detail)).is_equal("Warming Cabinet\nBag Upgrade I for sale · 150 coins")

func test_material_icons_exist() -> void:
	for id in ["wood", "stone", "fiber", "clay", "rock_salt", "coin", "star", "energy", "kitchen", "bag", "board"]:
		assert_bool(ResourceLoader.exists("res://assets/p0/icons/%s.svg" % id)).is_true()

# ---------------------------------------------------------------- HOME-1 sheet, HOME-2 banner, the sign

const HomePanel = preload("res://scenes/p0/home/p0_home_panel.gd")

func _ui(v: Dictionary) -> P0Ui:
	var ui: P0Ui = auto_free(P0Ui.new())
	add_child(ui)
	ui.set_view(v)
	return ui

func test_home_1_lays_out_tiles_changes_and_the_gap_on_the_button() -> void:
	var ui := _ui(_view())
	HomePanel.open(ui)
	assert_str(ui.modal_kind).is_equal("homestead")
	var tiles := ui.find_children("*", "UiNeedTile", true, false)
	assert_array(tiles.map(func(t): return (t as UiNeedTile).item_name)).is_equal(["Timber", "Stone", "Reeds", "Clay", "Rock Salt", "Coins", "Skills"])
	var button: UiCommandButton = ui.find_children("*", "UiCommandButton", true, false)[0]
	assert_str(button.reason).is_equal("Need 6 more Timber")
	var sent: Array = []
	ui.command.connect(func(cmd): sent.append(cmd))
	button.activated.emit()   # the kit only emits activated when ready; here the host wiring is what's under test
	assert_array(sent).is_equal([{"type": "homestead_upgrade"}])
	(ui.find_children("*", "UiDismissButton", true, false)[0] as Button).pressed.emit()
	assert_bool(ui.has_modal()).is_false()

func test_home_1_at_max_level_has_no_tiles_and_says_so() -> void:
	var v := _view(3)
	v.homestead.next = null
	var ui := _ui(v)
	HomePanel.open(ui)
	assert_array(ui.find_children("*", "UiNeedTile", true, false)).is_empty()
	assert_str((ui.find_children("*", "UiCommandButton", true, false)[0] as UiCommandButton).reason).is_equal("Highest level for now")

func test_home_2_banner_sits_under_the_hud_and_a_tap_skips_it() -> void:
	var ui := _ui(_view())
	var card := HomePanel.moment(ui, P0Logic.home_moment(_view(), {"level": 3, "energy": 78, "unlocks": ["warming_cabinet"]}))
	await get_tree().process_frame
	assert_float(card.position.y).is_equal(HomePanel.MOMENT_TOP)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	card.gui_input.emit(tap)
	await get_tree().process_frame
	assert_bool(is_instance_valid(card)).is_false()

func test_the_sign_stands_beside_the_door_off_its_path_and_is_solid() -> void:
	var bp := P0Garden.blueprint()
	var sign := P0Garden.sign_point(bp)
	var door := bp.cell_to_world(P0Garden.ANCHORS.house)
	assert_float(sign.x - door.x).is_between(0.8, 2.0)          # right of the door
	assert_bool(bp.world_to_cell(sign).x != P0Garden.ANCHORS.house.x).is_true()
	P0Garden.block_points(bp, [sign])
	var c := bp.world_to_cell(sign)
	assert_str(str(bp.masks.walkable[c.y])[c.x]).is_equal("0")
	assert_str(str(bp.masks.walkable[c.y])[P0Garden.ANCHORS.house.x]).is_equal("1")   # the door path stays open
