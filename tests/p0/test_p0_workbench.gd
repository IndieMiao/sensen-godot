extends GdUnitTestSuite
## SGODOT-231 workbench drawer (B2-06, seven states): the drawer over P0MaterialLogic.workbench_model, where each
## material comes from (NeedSource), the P0 UI's entry, and what a craft shows afterwards.

const STORE := "user://test_p0_workbench_quickbar.json"

var ui: P0Ui

static func _cost(id: String, name: String, have: int, need: int) -> Dictionary:
	return {"id": id, "name": name, "have": have, "need": need, "storage": have, "bag": 0}

static func _recipe(id: String, tab: String, item: String, name: String, to: String, cost: Array, block = null,
		owned := false, equipped := false, have := 6) -> Dictionary:
	return {"id": id, "tab": tab, "item": item, "name": name, "qty": 2 if to == "bag" else 1, "to": to,
		"have": have if to == "bag" else null, "cost": cost, "gate": null, "owned": owned, "equipped": equipped,
		"can_craft": block == null and not owned, "block": block}

## TOOLS (1434:126236): the pickaxe 1 Copper Ore short (the Gather Gloves left with 丁11); SUPPLIES: Torch craftable,
## Compost Lv3.
static func _view(ore := 4, torches := 6) -> Dictionary:
	var ore_cost := _cost("copper_ore", "Copper Ore", ore, 5)
	var wood := _cost("wood", "Timber", 17, 4)
	var pick_block = null if ore >= 5 else {"code": "need_material", "detail": {"item": "copper_ore", "need": 5, "have": ore}}
	return {
		"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000},
		"names": {"torch": "Torch", "copper_ore": "Copper Ore", "wood": "Timber", "fiber": "Reeds", "clay": "Clay",
			"pick_copper": "Copper Pickaxe", "rock_salt": "Rock Salt"},
		"bag": {"capacity": 25, "free": 20, "slots": []}, "plots": [], "coins": 40, "skills": {},
		"rest": {"used": 0, "limit": 1, "resets_in": 3600000},
		"workbench": {"tabs": ["tools", "supplies"], "recipes": [
			_recipe("craft_copper_pickaxe", "tools", "pick_copper", "Copper Pickaxe", "gear", [ore_cost, wood], pick_block),
			_recipe("craft_torch", "supplies", "torch", "Torch", "bag", [_cost("wood", "Timber", 17, 1), _cost("fiber", "Reeds", 8, 1)],
				null, false, false, torches),
			_recipe("craft_compost", "supplies", "fert_compost", "Compost", "bag", [_cost("fiber", "Reeds", 8, 2), _cost("wood", "Timber", 17, 1)],
				{"code": "locked", "detail": {"skill": "farming", "level": 3}}, false, false, 0),
		]},
	}

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	ui = P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	ui.layer = 128
	await await_idle_frame()
	ui.set_view(_view())

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

# --- Material sources ---

## Readable form of a source line: it keeps no-break spaces and U+2060 so it only breaks before ` · or ` (228).
func _plain(src: Dictionary) -> Dictionary:
	return {"text": str(src.get("text", "")).replace("\u00a0", " ").replace("\u2060", ""), "go": src.get("go", "")}

func test_material_sources_name_the_mine_type() -> void:
	var v := _view()
	# 355 3b2c6a43: the city's spots and the mines; Show where Today points (none in this view: no free sites read)
	assert_that(_plain(P0MaterialLogic.material_source(v, "copper_ore"))).is_equal({"text": "Copper Ore · Quarries", "go": ""})
	assert_str(_plain(P0MaterialLogic.material_source(v, "wood")).text).ends_with(" · Groves in town")
	assert_that(_plain(P0MaterialLogic.material_source(v, "clay"))).is_equal({"text": "Clay · Clay Pits in town · or Quarries", "go": ""})
	assert_that(_plain(P0MaterialLogic.material_source(v, "rock_salt"))).is_equal({"text": "Rock Salt · Quarries", "go": ""})
	# Not materials: bait also comes from the tackle shop, seeds from the stall; the other rules say those.
	assert_that(P0MaterialLogic.material_source(v, "bait_worm")).is_empty()
	assert_that(P0MaterialLogic.material_source(v, "seed_radish")).is_empty()
	assert_that(_plain(P0Logic.need_source(v, "copper_ore"))).is_equal({"text": "Copper Ore · Quarries", "go": ""})

# --- The drawer ---

func _drawer(tab := "tools") -> P0WorkbenchDrawer:
	var d := ui.open_workbench(tab)
	await await_idle_frame()
	return d

func test_drawer_shows_the_tab_and_follows_the_view_in_place() -> void:
	var d: P0WorkbenchDrawer = await _drawer("tools")
	assert_str(ui.modal_kind).is_equal("workbench")
	assert_object(ui.workbench()).is_same(d)
	assert_float(d.height).is_equal(P0WorkbenchDrawer.HEIGHT)
	var pick := d.card("craft_copper_pickaxe")
	assert_object(pick).is_not_null()
	assert_str(pick.button.label).is_equal("Need 1 more Copper Ore")
	assert_int(pick.tiles().size()).is_equal(2)
	assert_int(pick.tiles()[0].have).is_equal(4)   # Copper Ore 4/5: the tile shows the gap (amber, LOCK-10)
	assert_int(pick.tiles()[0].need).is_equal(5)
	# A fifth ore arrives: the same card turns to Craft (no rebuild, so a float can sit on it in that frame).
	ui.set_view(_view(5))
	assert_object(d.card("craft_copper_pickaxe")).is_same(pick)
	assert_str(pick.button.label).is_equal("Craft")
	# Supplies: Torch with You get 2 / You have 6; Compost behind Farming Lv3.
	d._tabs.selected = 1
	d._tabs.changed.emit(1)
	assert_str(ui.workbench_tab).is_equal("supplies")
	assert_object(d.card("craft_copper_pickaxe")).is_null()
	assert_str(d.card("craft_torch")._yield.text).is_equal("You get 2")
	assert_str(d.card("craft_torch")._have.text).is_equal("You have 6")
	assert_str(d.card("craft_compost").button.label).is_equal("Farming Lv3")

func test_drawer_sends_craft_and_toasts_reasons() -> void:
	var sent: Array = []
	ui.command.connect(func(cmd): sent.append(cmd))
	var d: P0WorkbenchDrawer = await _drawer("tools")
	ui.set_view(_view(5))
	d.card("craft_copper_pickaxe").pressed.emit()
	assert_that(sent).is_equal([{"type": "craft", "recipe": "craft_copper_pickaxe"}])
	ui.set_view(_view())
	# LOCK-10: the grey button still takes the tap and says why.
	d.card("craft_copper_pickaxe").button.unavailable_pressed.emit("Need 1 more Copper Ore")
	assert_str(ui.toast_text()).is_equal("Need 1 more Copper Ore")
	assert_int(sent.size()).is_equal(1)

func test_a_cost_tile_shows_where_the_material_comes_from() -> void:
	var asked: Array = []
	var d: P0WorkbenchDrawer = await _drawer("tools")
	d.source_requested.connect(func(tile, id): asked.append(id))
	var pick := d.card("craft_copper_pickaxe")
	pick.tiles()[0].pressed.emit()
	pick.tiles()[1].pressed.emit()
	assert_that(asked).is_equal(["copper_ore", "wood"])

func test_owned_tools_have_no_materials_and_a_done_button() -> void:
	var v := _view(5)
	v.workbench.recipes[0].owned = true
	v.workbench.recipes[0].equipped = true
	v.workbench.recipes[0].block = {"code": "owned"}
	ui.set_view(v)
	var d: P0WorkbenchDrawer = await _drawer("tools")
	assert_bool(d.card("craft_copper_pickaxe")._materials.visible).is_false()
	assert_str(d.card("craft_copper_pickaxe").button.label).is_equal("Equipped")

func test_a_supply_floats_on_its_card_and_the_drawer_stays() -> void:
	var d: P0WorkbenchDrawer = await _drawer("supplies")
	await await_idle_frame()
	var ft := d.float_on("craft_torch", "+2 Torch", P0Logic.icon("torch"))
	assert_object(ft).is_not_null()
	assert_int(ft.tone).is_equal(UiFloatText.Tone.ITEM)
	var row := d.card("craft_torch").materials_rect()
	assert_bool(ft.get_global_rect().get_center().x > row.get_center().x).is_true()   # right end of the materials row
	assert_object(d.float_on("craft_copper_pickaxe", "+1", null)).is_null()   # not on this tab
	assert_str(ui.modal_kind).is_equal("workbench")

# --- Craft results ---

func test_the_pickaxe_moment_offers_only_equip() -> void:
	var sent: Array = []
	var card := P0MaterialCards.open_crafted(ui, _view(), "pick_copper", func(cmd): sent.append(cmd))
	await await_idle_frame()
	assert_str(card.event).is_equal("Crafted!")
	assert_str(card.item_name).is_equal("Copper Pickaxe")
	assert_str(card.rarity_word).is_equal("2 Stone per rock")
	assert_str(card.primary).is_equal("Equip")
	assert_str(card.secondary).is_empty()
	card.primary_pressed.emit()
	assert_that(sent).is_equal([{"type": "equip", "item": "pick_copper"}])
	assert_bool(ui.has_modal()).is_false()

# --- The item's InfoSheet (不知火舞 on 231: CRAFT-1/2/4 are the shared InfoSheet) ---

func test_workbench_info_is_read_only_with_what_the_item_does() -> void:
	var v := _view(5)
	var pick := P0ItemInfo.spec(v, "pick_copper", &"workbench")
	assert_bool(pick.card).is_true()
	assert_str(pick.title).is_equal("Copper Pickaxe")
	assert_that(pick.facts).is_equal(["2 Stone per rock"])
	assert_array(pick.buttons).is_empty()   # Craft / Equip live on the blueprint card
	assert_bool(pick.info).is_false()       # no item page behind it in P0: no ›
	v.workbench.recipes[0].owned = true
	assert_that(P0ItemInfo.spec(v, "pick_copper", &"workbench").facts).is_equal(["2 Stone per rock", "In Gear"])
	assert_that(P0ItemInfo.spec(v, "torch", &"workbench").facts).is_equal(["See what rocks hold"])

func test_an_icon_opens_the_items_info_and_folds_it_again() -> void:
	var d: P0WorkbenchDrawer = await _drawer("supplies")
	assert_bool(d.sheet.is_open()).is_false()
	d.card("craft_torch").icon_pressed.emit()
	assert_bool(d.sheet.is_open()).is_true()
	assert_str(d.sheet.item_id()).is_equal("torch")
	assert_str(d.sheet.context()).is_equal("workbench")
	d.card("craft_compost").icon_pressed.emit()            # another item switches the card
	assert_str(d.sheet.item_id()).is_equal("fert_compost")
	d.card("craft_compost").icon_pressed.emit()            # the same one folds it
	assert_bool(d.sheet.is_open()).is_false()
	d.card("craft_torch").icon_pressed.emit()
	d._tabs.selected = 0
	d._tabs.changed.emit(0)                                # another tab folds it
	assert_bool(d.sheet.is_open()).is_false()
