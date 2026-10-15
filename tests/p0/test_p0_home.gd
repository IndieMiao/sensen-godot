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
	assert_str(str(p.look)).is_equal("Lv3 look · Fence & Mailbox")   # q(115): the stage's name, never Look A / B
	assert_array(p.tiles.map(func(t): return str(t.name))).is_equal(["Timber", "Stone", "Reeds", "Clay", "Rock Salt", "Coins", "Skills"])
	assert_int(int(p.tiles[5].need)).is_equal(440)   # price + the 40-coin floor (q(10))
	assert_array(p.changes.map(func(c): return str(c.text))).is_equal(
		["Max Energy 220 · Meals 220 a day", "Warming Cabinet", "Bag Upgrade I · 150 coins", "Stall Board · 3rd slot",
		"Fence & Mailbox · Timber or Stone"])
	assert_array(p.changes.map(func(c): return str(c.note))).is_equal(["now 210", "keeps 6 dishes by the stove", "Bag 25 → 30", "now 2", "pick one"])
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
	# Away from home (the Profile farm card): grey `At home`, like the Energy card (q(6)), even with every Need met.
	var away := P0Logic.home_panel(v, false)
	assert_str(str(away.reason)).is_equal("At home")
	assert_str(str(away.tap)).is_equal("Upgrade at home · Going home is free")
	assert_str(str(ready.tap)).is_empty()                     # at home a tap says the gap itself
	assert_array(away.tiles).has_size(ready.tiles.size())     # the Needs still read away from home
	assert_array(away.changes).has_size(ready.changes.size())

## SGODOT-282: Lv4–10 kitchen and bag unlocks read as §8.7 copy; ids for other lines (travel, looks, rooms) add no row.
func test_p1_levels_list_the_kitchen_and_bag_unlocks() -> void:
	var v := _view(5)
	v.homestead.next.level = 6
	v.homestead.next.unlocks = ["big_pot", "bag_upgrade_2"]
	var p := P0Logic.home_panel(v)
	assert_str(str(p.title)).is_equal("Homestead Lv5 → Lv6")
	assert_array(p.changes.slice(1).map(func(c): return [c.text, c.note])).is_equal(
		[["Big Pot · 2 servings on any stove", ""], ["Bag Upgrade II · 400 coins", "Bag 35 · after Upgrade I"]])   # q(201)
	assert_str(str(p.changes[1].icon)).is_equal("big_pot")
	v.homestead.next.unlocks = ["second_stove", "long_haul_ticket"]
	assert_array(P0Logic.home_panel(v).changes.slice(1).map(func(c): return str(c.text))).is_equal(["Second Stove"])
	v.homestead.next.level = 5
	v.homestead.next.unlocks = ["notice_board", "trip_7", "porch", "standard_room"]
	assert_str(str(P0Logic.home_panel(v).look)).is_equal("Lv5 look · Porch")
	var m := P0Logic.home_moment(v, {"level": 10, "unlocks": ["chefs_sign", "master_farmhouse", "deluxe_room", "title_homestead_master"]})
	assert_str(str(m.detail)).is_equal("Chef's Sign\nHomestead Master")

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

## q(115) ②: Lv10 has no next level: `Max level · Homestead Master` under the title, no Upgrade, and the Looks rows.
func test_lv10_says_max_level_and_keeps_the_looks() -> void:
	var v := _view(10)
	v.homestead.next = null
	v.homestead["looks"] = [{"id": "fence", "level": 3, "look": "a"}, {"id": "porch", "level": 5, "look": "b"},
		{"id": "kitchen_extension", "level": 8, "look": "a"}, {"id": "master_farmhouse", "level": 10, "look": "b"}]
	var p := P0Logic.home_panel(v)
	assert_str(str(p.title)).is_equal("Homestead Lv10")
	assert_str(str(p.subtitle)).is_equal("Max level · Homestead Master")
	assert_bool(bool(p.button)).is_false()
	assert_array(p.looks.map(func(r): return "%s … %s" % [r.name, r.value])).is_equal(
		["Fence & Mailbox … Timber Fence ›", "Porch … Stone Porch ›", "Kitchen Wing … Timber Kitchen Wing ›", "Master Farmhouse … Stone Manor ›"])
	var ui := _ui(v)
	HomePanel.open(ui)
	assert_array(ui.find_children("*", "UiCommandButton", true, false)).is_empty()
	assert_int(ui.find_children("Look_*", "", true, false).size()).is_equal(4)

func test_home_moment_matches_the_page_14_banner() -> void:
	var m := P0Logic.home_moment({"energy": {"max": 220}}, {"kind": "homestead", "level": 3, "unlocks": ["warming_cabinet", "bag_upgrade_1", "board_slot_3", "fence"]})
	assert_str(str(m.title)).is_equal("Homestead Lv3")
	assert_str(str(m.subtitle)).is_equal("Max Energy 220 · Energy full")
	assert_str(str(m.detail)).is_equal("Warming Cabinet\nBag Upgrade I · 150 coins")

func test_material_icons_exist() -> void:
	for id in ["wood", "stone", "fiber", "clay", "rock_salt", "coin", "star", "energy", "kitchen", "bag", "board"]:
		assert_bool(ResourceLoader.exists("res://assets/p0/icons/%s.svg" % id)).is_true()
	# Lv4–10's materials have their own art on HOME-1's tiles, not the sprout (李元芳 on 286 5d27bd93; 安其拉 2bc8ed12)
	for id in ["copper_ore", "quartz", "hardwood"]:
		assert_str(P0Logic.icon(id).resource_path).override_failure_message(id).is_equal("res://assets/p0/icons/%s.svg" % id)

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
	button.unavailable_pressed.emit(button.reason)
	assert_str(ui.toast_text()).is_equal("Need 6 more Timber")   # at home a grey tap says the gap itself
	var sent: Array = []
	ui.command.connect(func(cmd): sent.append(cmd))
	button.activated.emit()   # the kit only emits activated when ready; here the host wiring is what's under test
	assert_array(sent).is_equal([{"type": "homestead_upgrade"}])
	(ui.find_children("*", "UiDismissButton", true, false)[0] as Button).pressed.emit()
	assert_bool(ui.has_modal()).is_false()

## From the Profile farm card away from home (§10.6.2; 不知火舞 and 李白): the same sheet, the button grey with `At home`;
## a tap says `Upgrade at home · Going home is free` and sends nothing, even with every Need met.
func test_home_1_away_from_home_greys_the_button_with_at_home() -> void:
	var v := _view()
	v.homestead.next.materials[0].have = 16   # every Need met: only the place stops it
	v.homestead.next.can_upgrade = true
	var ui := _ui(v)
	HomePanel.open(ui, false)
	assert_str(ui.modal_kind).is_equal("homestead")
	assert_array(ui.find_children("*", "UiNeedTile", true, false)).has_size(7)
	var button: UiCommandButton = ui.find_children("*", "UiCommandButton", true, false)[0]
	assert_str(button.reason).is_equal("At home")
	var sent: Array = []
	ui.command.connect(func(cmd): sent.append(cmd))
	await get_tree().process_frame   # laid out, as when a player taps it
	button.unavailable_pressed.emit(button.reason)
	assert_array(sent).is_empty()
	assert_str(ui.toast_text()).is_equal("Upgrade at home · Going home is free")
	# q(16) (不知火舞 on #150): over the sheet's fixed decision area — the toast's bottom 8 above the button, not under the HUD.
	var toast: Control = ui._toasts._panel
	assert_float(toast.get_global_rect().end.y).is_equal_approx(button.get_global_rect().position.y - UiTokens.SPACE_OVERLAY_BODY, 1.0)

func test_home_1_at_max_level_has_no_tiles_and_says_so() -> void:
	var v := _view(3)
	v.homestead.next = null
	var ui := _ui(v)
	HomePanel.open(ui)
	assert_array(ui.find_children("*", "UiNeedTile", true, false)).is_empty()
	assert_str((ui.find_children("*", "UiCommandButton", true, false)[0] as UiCommandButton).reason).is_equal("Highest level for now")
	await get_tree().process_frame
	var sheet: Control = ui.find_children("*", "PanelContainer", true, false).filter(func(p): return (p as Control).theme != null)[0]
	assert_float(sheet.size.y).is_less(400.0)   # a short sheet (title, Looks, button, Close), not the 606-high upgrade sheet

func test_home_2_banner_sits_under_the_hud_and_a_tap_skips_it() -> void:
	var ui := _ui(_view())
	var card := HomePanel.moment(ui, P0Logic.home_moment(_view(), {"level": 3, "energy": 78, "unlocks": ["warming_cabinet"]}))
	await get_tree().process_frame
	assert_float(card.position.y).is_equal(HomePanel.MOMENT_TOP)   # the HOME-2 spec's y …
	assert_float(card.position.y).is_equal(UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + 10.0 + ui.safe_top())   # … as show_moment works it out
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
	assert_bool(bp.is_walkable(c)).is_false()
	assert_bool(bp.is_walkable(Vector2i(P0Garden.ANCHORS.house.x, c.y))).is_true()   # the door path stays open

## The source label only breaks before ` · or ` (不知火舞 on 228): no-break spaces inside each part, U+2060 after a range's dash.
func _plain(src: Dictionary) -> Dictionary:
	return {"text": str(src.get("text", "")).replace("\u00a0", " ").replace("\u2060", ""), "go": src.get("go", "")}

func test_material_source_breaks_only_before_or() -> void:
	var v := _view()
	v.erase("gather")
	v["names"] = {"clay": "Clay", "rock_salt": "Rock Salt"}
	v["homestead"] = {"level": 1}
	var gated := str(P0MaterialLogic.material_source(v, "clay").text)
	assert_array(Array(gated.split(" "))).is_equal(["Clay\u00a0·\u00a0Mine\u00a0floor\u00a01", "·\u00a0or\u00a0Clay\u00a0Bank\u00a0from\u00a0Homestead\u00a0Lv2"])
	assert_str(str(P0MaterialLogic.material_source(v, "rock_salt").text)).is_equal("Rock\u00a0Salt\u00a0·\u00a0Mine\u00a0floors\u00a01–\u20604")

func test_material_sources_name_the_spots_and_the_mine() -> void:
	# HOME-1 uses the workbench's line (P0MaterialLogic.material_source, Li Bai q(65)): ` · or `, open sources first,
	# a spot not open yet last with "from Homestead LvN"; Show goes to the first open source.
	var v := _view()
	v["gather"] = {"spots": [
		{"id": "spot_grove", "name": "Timber Grove", "open": true, "homestead": 1, "yield": [["wood", 6]]},
		{"id": "spot_rock_pile", "name": "Rock Pile", "open": true, "homestead": 1, "yield": [["stone", 4]]},
		{"id": "spot_reed_bank", "name": "Reed Bank", "open": true, "homestead": 1, "yield": [["fiber", 3], ["bait_worm", 2]]},
		{"id": "spot_clay_bank", "name": "Clay Bank", "open": false, "homestead": 2, "yield": [["clay", 2]]}]}
	v["names"] = {"wood": "Timber", "stone": "Stone", "fiber": "Reeds", "clay": "Clay", "rock_salt": "Rock Salt", "bait_worm": "Worm Bait"}
	assert_that(_plain(P0Logic.home_source(v, "wood"))).is_equal({"text": "Timber · Timber Grove", "go": "spot_grove"})
	assert_that(_plain(P0Logic.home_source(v, "stone"))).is_equal({"text": "Stone · Rock Pile · or the mine", "go": "spot_rock_pile"})
	assert_that(_plain(P0Logic.home_source(v, "fiber"))).is_equal({"text": "Reeds · Reed Bank", "go": "spot_reed_bank"})
	assert_that(_plain(P0Logic.home_source(v, "clay"))).is_equal({"text": "Clay · Mine floor 1 · or Clay Bank from Homestead Lv2", "go": "mine"})
	assert_that(_plain(P0Logic.home_source(v, "rock_salt"))).is_equal({"text": "Rock Salt · Mine floors 1–4", "go": "mine"})
	assert_that(_plain(P0Logic.home_source(v, "bait_worm"))).is_equal({"text": "Worm Bait", "go": ""})   # a side yield, not a material
	# Lv2 opens the Clay Bank: the gate goes, the order stays (Li Bai's example).
	v.gather.spots[3].open = true
	assert_that(_plain(P0Logic.home_source(v, "clay"))).is_equal({"text": "Clay · Mine floor 1 · or Clay Bank", "go": "mine"})
	# Coins and skills keep their own lines.
	assert_str(str(P0Logic.home_source(v, "coins").go)).is_equal("stall")
	assert_str(str(P0Logic.home_source(v, "skills").go)).is_equal("")

func test_material_source_without_spot_states_reads_the_homestead_level() -> void:
	var v := _view()   # no view.gather (a view from before the spots): the content's gate against the Homestead level
	v.erase("gather")
	v["names"] = {"clay": "Clay"}
	v["homestead"] = {"level": 1}
	assert_str(str(_plain(P0MaterialLogic.material_source(v, "clay")).text)).is_equal("Clay · Mine floor 1 · or Clay Bank from Homestead Lv2")
	v.homestead.level = 2
	assert_str(str(_plain(P0MaterialLogic.material_source(v, "clay")).text)).is_equal("Clay · Mine floor 1 · or Clay Bank")

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
	# The × floats above the sheet's corner where the main key stands: the key and quick bar hide, as in the frame.
	assert_bool(ui._keys.visible).is_false()
	assert_bool(ui._bar.visible).is_false()
	(ui.find_children("*", "UiCloseButton", true, false)[0] as Button).pressed.emit()
	assert_bool(ui.has_modal()).is_false()
	assert_bool(ui._keys.visible).is_true()
	assert_bool(ui._bar.visible).is_true()

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

## A refused upgrade (后裔 on #150): away from home it says what HOME-1's grey button says; when the fresh view shows no gap
## any more (it changed under the tap) the server's detail names it instead of an empty toast.
func test_a_refused_upgrade_says_where_and_what_is_missing() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.view = _view()
	rt.session.view["names"] = {"wood": "Timber"}   # the server's names, as in a real view
	rt._on_refused("not_home", {}, {"type": "homestead_upgrade"})
	assert_str(rt.ui.toast_text()).is_equal("Upgrade at home · Going home is free")
	rt._on_refused("not_home", {}, {"type": "rest"})
	assert_str(rt.ui.toast_text()).is_equal("At home only")                     # other commands stay short
	rt.ui.space = "pond"                                                         # HOME-1's line from where the player is
	rt._on_refused("need_material", {"item": "wood", "need": 16, "have": 10}, {"type": "homestead_upgrade"})
	assert_str(rt.ui.toast_text()).is_equal("Upgrade at home · Going home is free")
	rt.ui.space = "home"
	rt.session.view.homestead.next.materials[0].have = 16                        # the view has no gap left
	rt._on_refused("need_material", {"item": "wood", "need": 16, "have": 15}, {"type": "homestead_upgrade"})
	assert_str(rt.ui.toast_text()).is_equal("Need 1 more Timber")
	rt._on_refused("skills_short", {"need": 5, "have": 4}, {"type": "homestead_upgrade"})
	assert_str(rt.ui.toast_text()).is_equal("Skills total 5 needed · now 4")   # never "Can't do that (skills_short)"
	rt._on_refused("max_level", {"level": 3}, {"type": "homestead_upgrade"})
	assert_str(rt.ui.toast_text()).is_equal("Highest level for now")

func test_the_sign_prompt_reads_its_level_and_lights_ready() -> void:
	# WORLD-HINT-5 (228 64c75e54, SGODOT-250): the house mark, Ready once the Needs are met; open: `Homestead LvN`.
	var p := P0WorldPrompts.sign(_view())
	assert_str(p.text).is_equal("Homestead Lv2")
	assert_str(p.fact).is_empty()
	assert_int(p.status).is_equal(-1)
	assert_object(p.icon).is_same(P0Logic.icon("level_up"))   # its own mark; the farmhouse keeps i-home
	var lit := _view()
	lit.homestead.next.can_upgrade = true
	assert_int(P0WorldPrompts.sign(lit).status).is_equal(UiStatusBadge.State.READY)
	assert_int(P0WorldPrompts.show("sign", "", 30.0, P0WorldPrompts.sign(lit))).is_equal(P0WorldPrompts.Show.ICON)   # Ready from afar
	assert_int(P0WorldPrompts.show("sign", "", 30.0, p)).is_equal(P0WorldPrompts.Show.NONE)
	assert_int(P0WorldPrompts.show("sign", "", 7.5, p)).is_equal(P0WorldPrompts.Show.ICON)
	assert_int(P0WorldPrompts.show("sign", "sign", 2.0, p)).is_equal(P0WorldPrompts.Show.BAR)

func test_the_sign_strip_flips_at_the_edge_and_its_tap_is_the_sign() -> void:
	# A tap on the strip or the button goes to the sign by id, never through the farmhouse's 80 px circle (PR #21 review).
	var ui := _ui(_view())
	await get_tree().process_frame
	var p := P0WorldPrompts.sign(_view())
	var a := ui._marker_area()
	var at := Vector2(a.end.x - 24, a.get_center().y)
	var sign := at + Vector2(0, 30)
	ui.name_bar("sign", p.icon, p.text, p.fact, at, true, UiWorldNameBar.Dir.RIGHT, false, p.status, sign)
	var bar: UiWorldNameBar = ui._name_bars["sign"]
	assert_int(bar.side).is_equal(UiWorldNameBar.Dir.LEFT)   # no room on the right
	var seen := []
	ui.tapped.connect(func(q): seen.append([ui.tapped_card, q]))
	assert_bool(ui._tap_at(bar.hit_rect().get_center(), false)).is_true()
	ui.world_icon("plaque", P0Logic.icon("board"), Vector2(120, a.get_center().y), true, false, -1, Vector2(120, 400))
	assert_bool(ui._tap_at(ui.prompt_rect("plaque").get_center() + Vector2(0, 19), false)).is_true()   # the 44 area, below the disc
	assert_array(seen).is_equal([["sign", sign], ["plaque", Vector2(120, 400)]])

func test_an_open_strip_folds_a_caption_it_covers() -> void:
	# 不知火舞 on SGODOT-228 (293b4190), now for every CaptionPill: under an open name strip a mark shows without its caption.
	var ui := _ui(_view())
	await get_tree().process_frame
	var a := ui._marker_area()
	var at := Vector2(a.position.x + 60, a.get_center().y)
	ui.badge("mine", UiStatusBadge.State.AVAILABLE, at + Vector2(40, 30), true, "Floor 1 · 2 runs left", P0Logic.icon("pickaxe"))
	var b: UiStatusBadge = ui._badges["mine"]
	assert_str(b.caption).is_equal("Floor 1 · 2 runs left")
	ui.name_bar("workbench", P0Logic.icon("workbench"), "Workbench", "", at, true)
	ui.badge("mine", UiStatusBadge.State.AVAILABLE, at + Vector2(40, 30), true, "Floor 1 · 2 runs left", P0Logic.icon("pickaxe"))
	assert_str(b.caption).is_empty()
	ui.world_icon("workbench", P0Logic.icon("workbench"), at, true)   # folds
	await get_tree().create_timer(0.3).timeout
	ui.badge("mine", UiStatusBadge.State.AVAILABLE, at + Vector2(40, 30), true, "Floor 1 · 2 runs left", P0Logic.icon("pickaxe"))
	assert_str(b.caption).is_equal("Floor 1 · 2 runs left")

func test_one_finger_card_the_nearest_in_reach_and_it_does_not_flicker() -> void:
	# LOCK-07: near both the sign and the stall only one card shows; the showing card keeps it inside CARD_KEEP.
	var cands := [["stall", Vector3(9.4, 0, -10.1), 3.2], ["home", Vector3(6.2, 0, -10.7), 4.2], ["sign", Vector3(7.5, 0, -9.4), 2.6]]
	assert_str(P0Garden.pick_card(cands, Vector3(7.6, 0, -8.6), "")).is_equal("sign")
	assert_str(P0Garden.pick_card(cands, Vector3(8.5, 0, -9.7), "sign")).is_equal("sign")    # stall barely nearer: keep
	assert_str(P0Garden.pick_card(cands, Vector3(9.3, 0, -9.9), "sign")).is_equal("stall")   # clearly nearer: switch
	assert_str(P0Garden.pick_card(cands, Vector3(20, 0, 0), "stall")).is_equal("")           # out of every reach

func test_a_prompt_tap_names_its_facility_while_the_world_handles_it() -> void:
	# PR #21 review: the farmhouse's point can sit under the sign's caption, so the world dispatches prompt taps by
	# id (P0Ui.tapped_card), not by re-testing the point (then the finger card, now the world prompt, SGODOT-250).
	var ui := _ui(_view())
	await get_tree().process_frame
	ui.world_icon("home", P0Logic.icon("home"), Vector2(180, 300), true, false, -1, Vector2(180, 330))
	var seen := []
	ui.tapped.connect(func(p): seen.append([ui.tapped_card, p]))
	var c: UiWorldIconButton = ui._icons["home"]
	assert_bool(ui._tap_at(c.hit_rect().get_center(), false)).is_true()
	assert_array(seen).is_equal([["home", Vector2(180, 330)]])
	assert_str(ui.tapped_card).is_equal("")                       # only while the tap is handled
	ui._tap_at(ui.root.global_position + Vector2(20, 700), false)  # a scene tap carries no card
	assert_str(str(seen[-1][0])).is_equal("")

## Bag Upgrade notes from content (不知火舞 on 282, 李元芳's c62a6ed9 ④): the tiers are fixed — I to 30, II to 35 after I,
## III to 40 after II — so `Bag 30 → 35` once the tier before is bought, else `Bag 35 · after Upgrade I`.
func test_bag_upgrade_notes_follow_the_tiers_the_player_has() -> void:
	var v := _view(5)
	assert_str(P0Logic.bag_tier_note(v, "bag_upgrade_1")).is_equal("Bag 25 → 30")
	assert_str(P0Logic.bag_tier_note(v, "bag_upgrade_2")).is_equal("Bag 35 · after Upgrade I")
	assert_str(P0Logic.bag_tier_note(v, "bag_upgrade_3")).is_equal("Bag 40 · after Upgrade II")
	v.homestead.unlocks["bag_upgrade_1"] = "owned"
	v.bag.capacity = 30
	assert_str(P0Logic.bag_tier_note(v, "bag_upgrade_2")).is_equal("Bag 30 → 35")
	assert_str(P0Logic.bag_tier_note(v, "bag_upgrade_3")).is_equal("Bag 40 · after Upgrade II")
	v.homestead.unlocks["bag_upgrade_2"] = "owned"
	v.bag.capacity = 35
	v.homestead.next.level = 9
	v.homestead.next.unlocks = ["bag_upgrade_3"]
	assert_array(P0Logic.home_panel(v).changes.slice(1).map(func(c): return "%s · %s" % [c.text, c.note])).is_equal(
		["Bag Upgrade III · 1,000 coins · Bag 35 → 40"])

## Lv8 promises no stall look until the stall has its model (不知火舞 on 282, 李元芳's c62a6ed9 ③): neither HOME-1 nor the banner.
func test_lv8_says_nothing_of_the_stall_yet() -> void:
	var v := _view(7)
	v.homestead.next.level = 8
	v.homestead.next.unlocks = ["third_stove", "warming_cabinet_12", "stall_upgrade", "kitchen_extension"]
	var texts: Array = P0Logic.home_panel(v).changes.map(func(c): return str(c.text))
	assert_array(texts).is_equal(["Max Energy 220 · Meals 220 a day", "Third Stove", "Warming Cabinet 12", "Kitchen Wing · Timber or Stone"])
	var m := P0Logic.home_moment(v, {"level": 8, "unlocks": ["third_stove", "warming_cabinet_12", "stall_upgrade", "kitchen_extension"]})
	assert_str(str(m.detail)).not_contains("Stall")

## HOME-1 scrolls as every other sheet (李元芳's c62a6ed9 ①): a drag from a need tile moves it; a fade over its bottom edge
## while more lies below, gone at the end; the last row 24 above the end.
func test_home_1_scrolls_from_a_tile_and_fades_where_more_lies_below() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var v := _view(5)
	v.homestead.next.level = 6
	v.homestead.next.unlocks = ["big_pot", "bag_upgrade_2"]
	var vp := SubViewport.new()   # the frame: 360 × 800
	vp.size = Vector2i(360, 800)
	add_child(auto_free(vp))
	var ui := P0Ui.new()
	vp.add_child(ui)
	ui.set_view(v)
	HomePanel.open(ui)
	for i in 4: await get_tree().process_frame
	var scroll: ScrollContainer = ui.find_child("Scroll", true, false)
	assert_object(scroll).is_instanceof(TouchScrollContainer)
	var fade: Control = ui.find_child("ScrollFade", true, false)
	var bar := scroll.get_v_scroll_bar()
	assert_bool(bar.max_value > bar.page).is_true()   # the frame: Lv6's rows run past the sheet
	assert_bool(fade.visible).is_true()
	assert_float(fade.size.y).is_equal(HomePanel.FADE_H)
	assert_float(fade.get_global_rect().end.y).is_equal_approx(scroll.get_global_rect().end.y, 0.5)
	# a drag that starts on a need tile scrolls the sheet
	var emulate := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var tile: Control = ui.find_children("*", "UiNeedTile", true, false)[0]
	var at := tile.get_global_rect().get_center()
	_press(vp, at, true)
	for step in 8:
		_move(vp, at - Vector2(0, 20.0 * (step + 1)), Vector2(0, -20))
		await get_tree().process_frame
	_press(vp, at - Vector2(0, 160), false)
	await get_tree().process_frame
	Input.emulate_touch_from_mouse = emulate
	assert_int(scroll.scroll_vertical).is_greater(0)
	# at the end: no fade, the last row 24 above the scroll's end
	scroll.scroll_vertical = int(bar.max_value)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(fade.visible).is_false()
	var body := scroll.get_child(0) as VBoxContainer
	var rows := body.get_children().filter(func(c): return (c as Control).visible and (c as Control).size.y > 0.0)
	var last := rows[rows.size() - 2] as Control   # before the end pad
	assert_float(body.size.y - last.get_rect().end.y).is_equal(HomePanel.END_PAD)

func _press(vp: Viewport, at: Vector2, down: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.position = at
	t.pressed = down
	vp.push_input(t, true)
	var m := InputEventMouseButton.new()
	m.position = at
	m.global_position = at
	m.button_index = MOUSE_BUTTON_LEFT
	m.pressed = down
	vp.push_input(m, true)

func _move(vp: Viewport, at: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.position = at
	d.relative = rel
	vp.push_input(d, true)
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(m, true)
