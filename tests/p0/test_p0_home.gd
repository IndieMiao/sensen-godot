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
	v.homestead.next.unlocks = ["spice_rack", "clay_bank"]
	var p := P0Logic.home_panel(v)
	assert_str(str(p.look)).is_equal("")
	assert_str(str(p.changes[1].text)).is_equal("Spice Rack")
	assert_str("%s · %s" % [p.changes[2].text, p.changes[2].note]).is_equal("Clay Bank · Clay next to the Reed Bank")   # q(45)
	var m := P0Logic.home_moment(v, {"level": 2, "unlocks": ["spice_rack", "clay_bank"]})
	assert_str(str(m.detail)).is_equal("Spice Rack · seasonings off your bag\nClay Bank opened")

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
	await get_tree().process_frame
	var sheet: Control = ui.find_children("*", "PanelContainer", true, false).filter(func(p): return (p as Control).theme != null)[0]
	assert_float(sheet.size.y).is_less(300.0)   # a short sheet, not the 606-high upgrade sheet

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

func test_material_sources_name_the_spots_and_the_mine() -> void:
	var v := _view()
	v["gather"] = {"spots": [
		{"id": "spot_grove", "name": "Timber Grove", "open": true, "homestead": 1, "yield": [["wood", 6]]},
		{"id": "spot_rock_pile", "name": "Rock Pile", "open": true, "homestead": 1, "yield": [["stone", 4]]},
		{"id": "spot_reed_bank", "name": "Reed Bank", "open": true, "homestead": 1, "yield": [["fiber", 3], ["bait_worm", 2]]},
		{"id": "spot_clay_bank", "name": "Clay Bank", "open": false, "homestead": 2, "yield": [["clay", 2]]}]}
	v["names"] = {"wood": "Timber", "stone": "Stone", "fiber": "Reeds", "clay": "Clay", "rock_salt": "Rock Salt", "bait_worm": "Worm Bait"}
	assert_str(str(P0Logic.home_source(v, "wood").text)).is_equal("Timber · Timber Grove")
	assert_str(str(P0Logic.home_source(v, "stone").text)).is_equal("Stone · Rock Pile or the Mine")
	assert_str(str(P0Logic.home_source(v, "clay").text)).is_equal("Clay · Clay Bank (Homestead Lv2) or the Mine")
	assert_str(str(P0Logic.home_source(v, "rock_salt").text)).is_equal("Rock Salt · the Mine")
	assert_str(str(P0Logic.home_source(v, "bait_worm").text)).is_equal("Worm Bait")   # a side yield is not the spot's material

func test_plaque_lines_date_each_upgrade() -> void:
	var v := _view(3)
	v.homestead["plaque"] = [{"level": 2, "at": 1791158400000.0}, {"level": 3, "at": 1791504000000.0}]   # 2026-10-05 / 10-09 00:00 UTC
	assert_array(P0Logic.plaque_lines(v, 0)).is_equal([{"label": "Lv2", "value": "Oct 5"}, {"label": "Lv3", "value": "Oct 9"}])
	assert_array(P0Logic.plaque_lines(v, 8 * 60).map(func(l): return l.value)).is_equal(["Oct 5", "Oct 9"])   # Shanghai
	assert_array(P0Logic.plaque_lines(_view(1))).is_empty()

func test_plaque_read_is_a_read_only_sheet_with_only_close() -> void:
	var v := _view(3)
	v.homestead["plaque"] = [{"level": 2, "at": 1791158400000.0}, {"level": 3, "at": 1791504000000.0}]
	var ui := _ui(v)
	HomePanel.plaque(ui)
	assert_str(ui.modal_kind).is_equal("plaque")
	assert_array(ui.find_children("*", "UiFactRow", true, false).map(func(f): return (f as UiFactRow).label)).is_equal(["Lv2", "Lv3"])
	assert_array(ui.find_children("*", "UiCommandButton", true, false)).is_empty()
	(ui.find_children("*", "UiCloseButton", true, false)[0] as Button).pressed.emit()
	assert_bool(ui.has_modal()).is_false()

func test_the_plaque_stands_left_of_the_door_apart_from_the_sign() -> void:
	var bp := P0Garden.blueprint()
	var door := bp.cell_to_world(P0Garden.ANCHORS.house)
	var plaque := P0Garden.plaque_point(bp)
	assert_float(door.x - plaque.x).is_between(0.8, 2.0)
	assert_float(plaque.distance_to(P0Garden.sign_point(bp))).is_greater(2.0)   # two tap targets that never overlap

func test_need_material_from_a_shop_or_the_workbench_names_its_own_gap() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.view = _view()
	rt.session.view["names"] = {"copper_ore": "Copper Ore"}
	rt._on_refused("need_material", {"item": "copper_ore", "need": 4, "have": 2}, {"type": "craft", "recipe": "pick_copper"})
	assert_str(rt.ui.toast_text()).is_equal("Need 2 more Copper Ore")
	rt._on_refused("need_material", {"item": "wood", "need": 16, "have": 10}, {"type": "homestead_upgrade"})
	assert_str(rt.ui.toast_text()).is_equal("Need 6 more Timber")   # HOME-1's gap, in tile order

func test_the_sign_card_stays_on_screen_and_its_tap_is_the_sign() -> void:
	# #12's finger cards clamp themselves inside (Pointer flips inward); a tap on the card goes to the sign.
	var ui := _ui(_view())
	await get_tree().process_frame
	var sign := Vector2(ui.root.size.x - 30, 320)
	ui.tag("homestead", "Homestead Lv3 · Tap to upgrade", Vector2(ui.root.size.x - 4, 300), true, sign)
	var c: UiTapCard = ui._cards["homestead"]
	assert_float(c.position.x + c.size.x).is_less_equal(ui._kit.size.x)
	ui.tag("homestead", "Homestead Lv3 · Tap to upgrade", Vector2(2, 300), true, sign)
	assert_float(c.position.x).is_greater_equal(0.0)
	var hits := []
	ui.tapped.connect(func(p): hits.append(p))
	assert_bool(ui._tap_at(c.hit_rect().get_center(), false)).is_true()
	assert_array(hits).is_equal([sign])

func test_the_sign_mark_shows_its_level_and_folds_near() -> void:
	# WorldBadges · Farm (不知火舞 on SGODOT-228): home mark + "Homestead LvN", Ready when the Needs are met; near, the
	# caption folds so the finger card can sit right above the mark.
	var ui := _ui(_view())
	await get_tree().process_frame
	ui.badge("homestead", UiStatusBadge.State.AVAILABLE, Vector2(180, 300), true, "Homestead Lv2", P0Logic.icon("home"))
	var b: UiStatusBadge = ui._badges["homestead"]
	assert_str(b.caption).is_equal("Homestead Lv2")
	var tall := ui.badge_height("homestead")
	ui.badge("homestead", UiStatusBadge.State.READY, Vector2(180, 300), true, "", P0Logic.icon("home"))
	assert_int(b.state).is_equal(UiStatusBadge.State.READY)
	assert_float(ui.badge_height("homestead")).is_less(tall)
func test_a_tap_on_the_sign_mark_or_its_caption_is_the_sign() -> void:
	# The mark sits above its anchor point and ignores the mouse; the farm asks badge_hit so the tap opens HOME-1
	# instead of falling through to the farmhouse's 80 px circle.
	var ui := _ui(_view())
	await get_tree().process_frame
	ui.badge("homestead", UiStatusBadge.State.AVAILABLE, Vector2(240, 320), true, "Homestead Lv2", P0Logic.icon("home"))
	await get_tree().process_frame
	var b: UiStatusBadge = ui._badges["homestead"]
	var r := Rect2(b.global_position - ui.root.global_position, b.size)
	assert_bool(ui.badge_hit("homestead", r.position + Vector2(r.size.x * 0.5, 6))).is_true()        # the round mark
	assert_bool(ui.badge_hit("homestead", r.end - Vector2(r.size.x * 0.5, 4))).is_true()               # the caption
	assert_bool(ui.badge_hit("homestead", r.position - Vector2(0, 30))).is_false()

func test_one_finger_card_the_nearest_in_reach_and_it_does_not_flicker() -> void:
	# LOCK-07: near both the sign and the stall only one card shows; the showing card keeps it inside CARD_KEEP.
	var cands := [["stall", Vector3(9.4, 0, -10.1), 3.2], ["home", Vector3(6.2, 0, -10.7), 4.2], ["sign", Vector3(7.5, 0, -9.4), 2.6]]
	assert_str(P0Garden.pick_card(cands, Vector3(7.6, 0, -8.6), "")).is_equal("sign")
	assert_str(P0Garden.pick_card(cands, Vector3(8.5, 0, -9.7), "sign")).is_equal("sign")    # stall barely nearer: keep
	assert_str(P0Garden.pick_card(cands, Vector3(9.3, 0, -9.9), "sign")).is_equal("stall")   # clearly nearer: switch
	assert_str(P0Garden.pick_card(cands, Vector3(20, 0, 0), "stall")).is_equal("")           # out of every reach

func test_a_card_slides_off_another_mark_and_keeps_pointing_at_its_facility() -> void:
	# 不知火舞 on SGODOT-228 (293b4190): the plaque's card never covers the sign's mark; it moves sideways, ≥ 8 px clear,
	# and its pointer stays on the plaque.
	var ui := _ui(_view())
	await get_tree().process_frame
	var plaque := Vector2(160, 330)
	ui.tag("plaque", "Upgrade Plaque · Tap to read", plaque - Vector2(0, 30), true, plaque)
	var c: UiTapCard = ui._cards["plaque"]
	var mark := Rect2(Vector2(c.position.x + c.size.x - 30, c.position.y + 10), Vector2(28, 28))   # under the card's right end
	assert_bool(ui.slide_card_off("plaque", mark)).is_true()
	assert_float(mark.position.x - (c.position.x + c.size.x)).is_greater_equal(8.0 - 0.01)
	assert_float(c.position.x + c.pointer_tip_x()).is_equal_approx(plaque.x, 1.0)
	assert_bool(ui.slide_card_off("plaque", Rect2(Vector2(340, 700), Vector2(10, 10)))).is_false()   # nothing to clear

func test_a_card_tap_names_its_card_while_the_world_handles_it() -> void:
	# PR #21 review: the farmhouse card's point can sit under the sign's caption, so the world dispatches card taps by
	# id (P0Ui.tapped_card), not by re-testing the point.
	var ui := _ui(_view())
	await get_tree().process_frame
	ui.tag("home", "Farmhouse · Tap to go in", Vector2(180, 300), true, Vector2(180, 330))
	var seen := []
	ui.tapped.connect(func(p): seen.append([ui.tapped_card, p]))
	var c: UiTapCard = ui._cards["home"]
	assert_bool(ui._tap_at(ui.root.global_position + Rect2(c.position, c.size).get_center(), false)).is_true()
	assert_array(seen).is_equal([["home", Vector2(180, 330)]])
	assert_str(ui.tapped_card).is_equal("")                       # only while the tap is handled
	ui._tap_at(ui.root.global_position + Vector2(20, 700), false)  # a scene tap carries no card
	assert_str(str(seen[-1][0])).is_equal("")
