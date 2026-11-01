extends GdUnitTestSuite

const Gear := preload("res://modules/p0/p0_gear_logic.gd")
const Art := preload("res://modules/mining/combat_art.gd")
const WOOD := "weapon_wooden_sword"
const COPPER := "weapon_copper_sword"
const IRON := "weapon_iron_sword"
const POTION := "potion_heal"
var _content: Dictionary

func before_test() -> void:
	_content = P0Logic.content()
	P0Logic._content = _content.duplicate(true)
	P0Logic._content.mine.combat.weapons = {
		WOOD: {name = "Wooden Sword", attack = 4, tier = 1},
		COPPER: {name = "Copper Sword", attack = 7, tier = 1},
		IRON: {name = "Iron Sword", attack = 12, tier = 2}}
	P0Logic._content.mine.potions = {POTION: {name = "Healing Potion", heal = "full", floors = "any", cooldown_ms = 1700}}
	P0Logic._content.mine.first_dig = {giver = "res_pip", floor = 6, gate = {homestead = 4}, reward = {weapon = COPPER, affinity = 9}}
	P0Logic._content.workbench.recipes.append({id = "craft_test", out = IRON, to = "weapon", coins = 137, gate = {homestead = 9}})

func after_test() -> void:
	P0Logic._content = _content
	for suffix in ["tips", "bar"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_355_g_%d_%s.json" % [OS.get_process_id(), suffix]))

func _view() -> Dictionary:
	return {gear = {weapons = [WOOD, COPPER], weapon = WOOD, slots = {farming = "hoe_starter"}},
		bag = {capacity = 25, slots = [{id = POTION, qty = 2}, {id = POTION, qty = 3}, {id = "seed_radish", qty = 5}]},
		mine = {hp_max = 120, at = {mine = "wd-dev-quarry", day = "2026-11-02", floor = 1, hp = 47}},
		first_dig = {giver = "res_pip", floor = 6, have = 2, done = false}}

func test_weapon_reuses_the_combat_slot_and_shows_the_unowned_recipe_gate() -> void:
	var v := _view()
	var slots := P0BagDrawer.gear_slots(v)
	assert_int(slots.size()).is_equal(6)
	assert_str(slots[3].key).is_equal("combat")
	assert_str(slots[3].role).is_equal("Weapon")
	assert_str(slots[3].item).is_equal(WOOD)
	var rows := P0BagDrawer.gear_rows(v, "combat")
	assert_array(rows.map(func(r): return r.id)).is_equal([WOOD, COPPER, IRON])
	assert_array(rows.map(func(r): return r.state)).is_equal([&"equipped", &"owned", &"Workbench"])
	assert_str(rows[1].effect).is_equal("Attack 7")
	assert_str(rows[1].action.id).is_equal("equip")
	assert_str(rows[2].action.label).is_equal("Homestead Lv9")
	assert_str(rows[2].action.kind).is_equal("unavailable")
	v.homestead = {level = 9}
	assert_str(P0BagDrawer.gear_rows(v, "combat")[2].action.label).is_equal("Craft at Workbench")
	v.gear.weapon = COPPER
	assert_str(P0BagDrawer.gear_slots(v)[3].item).is_equal(COPPER)
	assert_str(P0BagDrawer.gear_rows(v, "combat")[1].state).is_equal("equipped")

func test_weapon_item_specs_read_content_attack_and_tier() -> void:
	var s := P0ItemInfo.spec(_view(), COPPER, &"gear")
	assert_bool(s.card).is_true()
	assert_array(s.facts).is_equal(["Attack 7", "T1"])
	assert_str(s.title).is_equal("Copper Sword")
	assert_str(P0ItemInfo.spec(_view(), IRON, &"gear").buttons[0].kind).is_equal("unavailable")
	assert_array(P0ItemInfo.spec(_view(), IRON, &"workbench").facts).is_equal(["Attack 12", "T2"])
	for id in [COPPER, IRON, POTION]:
		assert_that(P0Logic.icon(id)).is_same(load("res://assets/p0/icons/%s.svg" % id))

func test_potion_is_in_materials_but_never_uses_material_gift_rules() -> void:
	var v := _view()
	v.items = {POTION: {kind = "consumable"}}
	assert_str(P0ItemInfo.kind_of(v, POTION)).is_equal("potion")
	assert_str(P0ItemInfo.tab_of(v, POTION)).is_equal("materials")
	assert_array(P0ItemInfo.spec(v, POTION, &"bag").facts).is_equal(["Restores full HP"])
	assert_array(P0ItemInfo.spec(v, POTION, &"gift").buttons).is_empty()
	P0Logic._content.mine.potions[POTION].heal = 37
	assert_str(Gear.potion_effect(POTION)).is_equal("+37 HP")

func test_potion_counter_uses_the_offer_price_stock_and_effect() -> void:
	var v := _view()
	v.coins = 400
	v.shops = {homestead = {buy = [{id = POTION, price = 31, left = 2, daily = 6, homestead = 7, homestead_ok = true}]}}
	var s := P0ItemInfo.spec(v, POTION, &"counter_buy")
	assert_bool(s.card).is_true()
	assert_int(s.price.each).is_equal(31)
	assert_array(s.facts).is_equal(["Restores full HP", "Stock 2/6 · Bag ×5"])
	assert_str(s.buttons[0].label).is_equal("Buy")

func test_potion_bar_keeps_pins_and_drag_gaps_without_seeds() -> void:
	var v := _view()
	assert_array(P0Logic.quick_bar(v, [], "combat")).is_equal([POTION])
	assert_array(P0Logic.quick_bar(v, [], "farm")).is_equal(["seed_radish"])
	assert_array(P0Logic.quick_bar(v, ["", POTION], "combat")).is_equal(["", POTION])
	v.bag.slots = []
	assert_array(P0Logic.quick_bar(v, [POTION], "combat", [POTION])).is_equal([POTION])

func test_drink_uses_the_current_mine_and_day_without_local_settlement() -> void:
	var v := _view()
	var before := v.duplicate(true)
	var k := Gear.drink_action(v, POTION, 0)
	assert_bool(k.enabled).is_true()
	assert_bool(k.once).is_true()
	assert_str(k.verb).is_equal("Drink")
	assert_str(k.sub).is_empty()
	assert_dict(k.cmd).is_equal({type = "mine_drink", item = POTION, day = "2026-11-02", place = "wd-dev-quarry"})
	assert_dict(v).is_equal(before)
	v.mine.at.floor = 39
	assert_bool(Gear.drink_action(v, POTION, 0).enabled).is_true()

func test_drink_full_empty_unknown_cooldown_and_outside_mine_stay_disabled() -> void:
	var v := _view()
	assert_str(Gear.drink_action(v, POTION, 1700).sub).is_equal("0:02")
	assert_bool(Gear.drink_action(v, POTION, -1).enabled).is_false()
	v.mine.at.hp = 120
	assert_str(Gear.drink_action(v, POTION, 0).sub).is_equal("HP full")
	v.mine.at.hp = 47
	v.bag.slots = []
	assert_bool(Gear.drink_action(v, POTION, 0).enabled).is_false()
	v = _view()
	v.mine.at = null
	assert_bool(Gear.drink_action(v, POTION, 0).enabled).is_false()
	v = _view()
	v.mine.at.erase("day")
	assert_dict(Gear.drink_action(v, POTION, 0).cmd).is_empty()

func test_workbench_weapon_uses_craft_equip_and_equipped_states() -> void:
	var v := _view()
	var r := {id = "craft_test", item = IRON, name = "Iron Sword", tab = "tools", to = "weapon", cost = [], owned = false}
	v.workbench = {recipes = [r]}
	assert_str(P0MaterialLogic.workbench_model(v, "tools")[0].effect).is_equal("Attack 12")
	assert_str(P0MaterialLogic.workbench_model(v, "tools")[0].button.cmd.type).is_equal("craft")
	assert_str(P0MaterialLogic.workbench_model(v, "tools")[0].button.label).is_equal("Craft · 137 coins")
	r.coins_need = 177
	assert_array(P0MaterialLogic.workbench_model(v, "tools")[0].cost).is_empty()
	r.owned = true
	assert_str(P0MaterialLogic.workbench_model(v, "tools")[0].button.cmd.type).is_equal("equip")
	r.equipped = true
	assert_str(P0MaterialLogic.workbench_model(v, "tools")[0].button.label).is_equal("Equipped")
	r.owned = false
	r.block = {code = "homestead_level", detail = {level = 9}}
	assert_str(P0MaterialLogic.workbench_model(v, "tools")[0].button.label).is_equal("Homestead Lv9")
	r.block = {code = "no_coins", detail = {need = 23}}
	assert_str(P0MaterialLogic.workbench_model(v, "tools")[0].button.label).is_equal("Need 23 more coins")
	r.block = {code = "need_material", detail = {item = "coal", need = 3, have = 1}}
	r.cost = [{id = "coal", name = "Coal", need = 3, have = 1}]
	assert_str(P0MaterialLogic.workbench_model(v, "tools")[0].button.label).is_equal("Need 2 more Coal")

func test_first_dig_reads_its_own_view_and_content_without_tracking_mutation() -> void:
	var v := _view()
	v.residents = {res_pip = {request = {id = "unrelated", status = "accepted"}}}
	var before := v.duplicate(true)
	var d := Gear.first_dig_card(v)
	assert_str(d.title).is_equal("Pip's First Dig")
	assert_str(d.line).contains("Reach Floor 6")
	assert_str(d.needs[0].name).is_equal("Reach Floor 6 · any mine")
	assert_str(d.reward).is_equal("+9 Friendship · Copper Sword")
	assert_str(d.needs_label).is_empty()
	assert_bool(d.close_only).is_true()
	assert_bool(d.has("deliver_to")).is_false()
	assert_dict(v).is_equal(before)
	v.first_dig = null
	assert_dict(Gear.first_dig_card(v)).is_empty()

func test_first_dig_today_is_tappable_progress_without_red_dot() -> void:
	var v := _view()
	v.plots = [{state = "growing", crop = "crop_radish", ready_in = 600000}]
	var rows := P0Logic.today_rows(v)
	var dig := rows.filter(func(r): return bool(r.get("first_dig", false)))
	assert_int(dig.size()).is_equal(1)
	assert_str(dig[0].line).is_equal("Pip's First Dig · Floor 2/6")
	assert_str(dig[0].dot).is_empty()
	v.first_dig = null
	assert_bool(P0Logic.today_rows(v).any(func(r): return bool(r.get("first_dig", false)))).is_false()

func test_first_dig_reward_only_says_equipped_when_server_view_equipped_it() -> void:
	var v := _view()
	var events := [{kind = "first_dig", done = true}]
	v.gear.weapon = COPPER
	assert_str(Gear.first_dig_reward(v, events)).is_equal("Copper Sword · equipped")
	v.gear.weapon = IRON
	assert_str(Gear.first_dig_reward(v, events)).is_equal("Copper Sword")
	assert_str(Gear.first_dig_reward(v, [])).is_empty()

func _texts(n: Node) -> Array:
	var out := []
	if n is Label or n is Button: out.append(n.text)
	for c in n.get_children(): out.append_array(_texts(c))
	return out

func test_first_dig_card_has_only_close_no_bring_accept_or_deliver() -> void:
	var c := UiRequestCard.new(Gear.first_dig_card(_view()))
	add_child(c)
	await get_tree().process_frame
	assert_array(_texts(c)).contains(["Close"])
	for text in ["Bring", "Accept", "Deliver to", "Not now"]: assert_bool(_texts(c).has(text)).is_false()
	assert_int(c.action_button().kind).is_equal(UiCommandButton.Kind.SECONDARY)
	c.free()

func test_weapon_art_maps_new_ids_and_iron_is_a_recolor_of_copper() -> void:
	assert_str(Art.weapon_art_id(COPPER)).is_equal("copper_sword")
	assert_str(Art.weapon_art_id(WOOD)).is_equal("sword_wooden")
	var copper := Art.model(COPPER)
	var iron := Art.model(IRON)
	assert_that(copper.mesh.get_aabb()).is_equal(iron.mesh.get_aabb())
	var a: Array = copper.mesh.surface_get_arrays(0)
	var b: Array = iron.mesh.surface_get_arrays(0)
	assert_bool(a[Mesh.ARRAY_COLOR] == b[Mesh.ARRAY_COLOR]).is_false()
	copper.free()
	iron.free()

func _ui() -> P0Ui:
	var ui := P0Ui.new()
	ui.tips_path = "user://test_355_g_%d_tips.json" % OS.get_process_id()
	ui.quick_store = "user://test_355_g_%d_bar.json" % OS.get_process_id()
	add_child(auto_free(ui))
	await get_tree().process_frame
	ui.set_view(_view())
	ui.set_surface("mine")
	ui.set_mode("combat", "mine")
	return ui

func test_combat_potion_selection_only_sends_when_main_key_is_pressed() -> void:
	var ui := await _ui()
	var sent := []
	ui.action_pressed.connect(func(cmd): sent.append(cmd))
	assert_int(ui.quick_bar_node().slot(0).quantity).is_equal(5)
	ui._on_slot_tapped(POTION)
	assert_array(sent).is_empty()
	ui.set_action({verb = "Attack", enabled = true, cmd = {type = "mine_swing"}})
	assert_bool(ui.fab_state().enabled).is_false()
	ui.set_potion_cooldown(0)
	ui.set_action({verb = "Attack", enabled = true, cmd = {type = "mine_swing"}})
	assert_str(ui.fab_state().verb).is_equal("Drink")
	ui._fab_pressed()
	assert_int(sent.size()).is_equal(1)
	assert_str(sent[0].type).is_equal("mine_drink")
	ui.set_potion_cooldown(1700)
	ui.set_action({verb = "Attack", enabled = true, cmd = {type = "mine_swing"}})
	ui._fab_pressed()
	assert_int(sent.size()).is_equal(1)
	assert_str(ui.quick_bar_node().slot(0).cooldown).is_equal("0:02")
	assert_str(ui.quick_bar_node().cells()[0].quantity).is_equal("×5 · 0:02")
	var many := _view()
	many.bag.slots = [{id = POTION, qty = 340}]
	ui.set_view(many)
	var label: Label = ui.quick_bar_node().cells()[0]._qty
	var width := label.get_theme_font(&"font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x
	assert_float(width).is_less_equal(UiTokens.SIZE_QUICK_SLOT_W - 8.0)
	ui._on_slot_tapped(POTION)
	ui.set_action({verb = "Attack", enabled = true, cmd = {type = "mine_swing"}})
	assert_str(ui.fab_state().verb).is_equal("Attack")

func test_potion_ghost_opens_materials_and_is_not_shown_outside_mine() -> void:
	var ui := await _ui()
	var v := _view()
	v.bag.slots = []
	ui.set_view(v)
	assert_str(ui.quick_bar_node().slot(0).title).is_equal("Potion")
	assert_bool(ui.quick_bar_node().slot(0).ghost).is_true()
	ui.quick_bar_node().ghost_tapped.emit(0)
	assert_str(ui._bag.category).is_equal("Materials")
	ui.close_modal()
	ui.set_surface("farm")
	ui._refresh_bar()
	assert_array(ui.quick_bar_node().slots).is_empty()

func test_first_dig_today_opens_card_and_refreshes_until_server_completion() -> void:
	var ui := await _ui()
	ui.open_today()
	var index := -1
	for i in ui._today_rows.size():
		if bool(ui._today_rows[i].get("first_dig", false)): index = i
	assert_int(index).is_greater_equal(0)
	ui._today_panel.row_pressed.emit(index)
	assert_str(ui.modal_kind).is_equal("first_dig")
	var v := _view()
	v.first_dig.have = 4
	ui.set_view(v)
	assert_str(ui._first_dig_sig).contains('"have":4')
	v.first_dig = null
	ui.set_view(v)
	assert_bool(ui.has_modal()).is_false()
