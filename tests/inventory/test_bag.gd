extends GdUnitTestSuite

var _locale := "en"

func before_test() -> void:
	_locale = TranslationServer.get_locale()
	Localization.select_language("en")

func after_test() -> void:
	Localization.select_language(_locale)
	await _settle()

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0}, "wallet": 180, "tools": {"row_tool": true},
		"character": {"version": 1, "buffs": []},
		"inventory": {"seeds": {"R": {"bound": 3, "bought": 2}}, "produce": {"C": 5}, "dishes": {"salad": 1}},
		"engineering": {"reserved": {"C": 2}}, "journey": {"version": 1, "facts": ["workbench", "side_path"],
			"unlocks": ["bistro", "kitchen", "crafting", "crop_C"], "materials": {"copper_ore": 8}, "wood": 2,
			"workshop": {"stock": {"crate": 1}, "sequence": 0, "displays": {}}, "exploration": {"round": 0, "collected": []}},
		"bag": {"version": 2, "sequence": 4, "capacity": 24, "next_id": 9,
			"slots": [
				{"id": "bag_1", "item_id": "seed_R", "quantity": 3, "quality": "normal", "seed_lot": "bound"},
				{"id": "bag_2", "item_id": "copper_ore", "quantity": 6, "quality": "normal"},
				{"id": "bag_3", "item_id": "copper_ore", "quantity": 2, "quality": "normal"},
				{"id": "bag_4", "item_id": "C", "quantity": 5, "quality": "normal"},
				{"id": "bag_5", "item_id": "row_tool", "quantity": 1, "quality": "normal", "instance_id": "item_2"}],
			"overflow": [], "equipped": {"main_hand": {"id": "bag_6", "item_id": "hand_tools", "quantity": 1, "quality": "normal", "instance_id": "item_1"}}}}

func _panel(initial: Dictionary, responses: Array = []) -> Array:
	var transport := FakeTransport.new(responses)
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = initial
	session.version = 10
	var stage := Control.new()
	stage.size = Vector2(328, 600)
	add_child(auto_free(stage))
	var sheet := BagSheet.new()
	sheet.setup(session)
	stage.add_child(sheet)
	sheet.open()
	return [sheet.active, session, transport, sheet]

func _settle() -> void:
	for frame in 3: await get_tree().process_frame

func _button(panel: BagPanel, id: String) -> Button:
	return panel.find_child(id, true, false) as Button

func test_legacy_projection_preserves_counts_seed_lots_and_source_state() -> void:
	var state := _state()
	state.erase("bag")
	var original := state.duplicate(true)
	var bag := BagModel.snapshot(state)
	var seed_lots: Array = bag.slots.filter(func(entry): return entry.item_id == "seed_R")
	assert_int(seed_lots.size()).is_equal(2)
	assert_int(seed_lots[0].quantity + seed_lots[1].quantity).is_equal(5)
	assert_bool(BagModel.canonical(state)).is_false()
	assert_that(state).is_equal(original)

func test_stack_merge_respects_quality_seed_binding_attributes_and_equipment_instances() -> void:
	var first := {"id": "a", "item_id": "seed_R", "quantity": 2, "quality": "normal", "seed_lot": "bound"}
	var second := first.duplicate(true)
	second.id = "b"
	assert_bool(BagModel.compatible(first, second)).is_true()
	for difference in [{"seed_lot": "bought"}, {"quality": "gold"}, {"attributes": {"origin": "special"}}, {"instance_id": "item_4"}]:
		assert_bool(BagModel.compatible(first, second.merged(difference, true))).is_false()
	assert_bool(BagModel.compatible(first, first)).is_false()

func test_full_target_stacks_are_not_merge_destinations() -> void:
	var state := _state()
	state.bag.slots[2].quantity = 99
	assert_array(BagModel.merge_targets(state, state.bag.slots[1])).is_empty()
	state.bag.slots[2].quantity = 98
	assert_int(BagModel.merge_targets(state, state.bag.slots[1]).size()).is_equal(1)

func test_equipped_tool_controls_scope_independently_of_permanent_ownership() -> void:
	var state := _state()
	assert_bool(state.tools.row_tool).is_true()
	assert_int(BagModel.tool_scope(state)).is_equal(1)
	state.bag.equipped.main_hand = state.bag.slots[4]
	assert_int(BagModel.tool_scope(state)).is_equal(3)
	state.bag.equipped.main_hand = null
	assert_int(BagModel.tool_scope(state)).is_equal(1)
	state.erase("bag")
	assert_int(BagModel.tool_scope(state)).is_equal(3)

func test_reserved_produce_and_tools_cannot_be_discarded() -> void:
	var state := _state()
	assert_int(BagModel.discardable_quantity(state, state.bag.slots[3])).is_equal(3)
	state.engineering.reserved.C = 5
	assert_int(BagModel.discardable_quantity(state, state.bag.slots[3])).is_zero()
	assert_int(BagModel.discardable_quantity(state, state.bag.slots[4])).is_zero()

func test_item_uses_reach_real_mining_crafting_cooking_and_planting_destinations() -> void:
	var state := _state()
	var copper := BagModel.routes(state, "copper_ore")
	assert_bool(copper.any(func(goal): return goal.place == "nursery" and goal.target == "workbench")).is_true()
	assert_bool(copper.any(func(goal): return goal.place == "farm" and goal.target == "mine")).is_true()
	assert_bool(BagModel.routes(state, "rock_salt").any(func(goal): return goal.place == "bistro" and goal.target == "counter")).is_true()
	var seed := BagModel.routes(state, "seed_R")[0] as Dictionary
	assert_str(seed.plant_crop).is_equal("R")
	assert_str(seed.place).is_equal("farm")
	assert_str(seed.target).is_empty()

func test_type_properties_use_current_journey_rules_and_legacy_prices() -> void:
	var state := _state()
	assert_array(ItemCatalog.gameplay_properties(state, "seed_R")).contains(["Growth after care: ready", "Seed price: 4 coins"])
	assert_array(ItemCatalog.gameplay_properties(state, "R")).contains(["Stall price: 5 coins"])
	assert_array(ItemCatalog.gameplay_properties(state, "vegetable_soup")).contains(["Stall price: 16 coins", "Ingredients: Radish x1 / Lettuce x1 / Rock salt x1"])
	assert_array(ItemCatalog.gameplay_properties(state, "copper_ore")).contains(["Mining bonus chance: 35%"])
	state.erase("journey")
	assert_array(ItemCatalog.gameplay_properties(state, "R")).contains(["Stall price: 8 coins"])
	assert_str(ItemCatalog.quality_name("gold")).is_equal("Gold quality")
	assert_str(ItemCatalog.quality_name("unrecognized")).is_equal("Unknown quality")

func test_search_refresh_keeps_input_focus_and_filters_the_unified_grid() -> void:
	var pair := _panel(_state())
	var panel: BagPanel = pair[0]
	await _settle()
	assert_int(panel.grid.get_child_count()).is_equal(24)
	var search := panel.search
	search.grab_focus()
	search.text = "copper"
	search.text_changed.emit(search.text)
	await _settle()
	assert_bool(panel.search == search).is_true()
	assert_bool(search.has_focus()).is_true()
	assert_int(panel.grid.get_child_count()).is_equal(2)
	panel.category_filter.select(ItemCatalog.CATEGORIES.find("equipment"))
	panel.category_filter.item_selected.emit(ItemCatalog.CATEGORIES.find("equipment"))
	await _settle()
	assert_int(panel.grid.get_child_count()).is_zero()
	assert_int(pair[2].requests.size()).is_zero()

func test_split_sends_selected_quantity_and_current_bag_sequence() -> void:
	var initial := _state()
	var after := initial.duplicate(true)
	after.bag.sequence = 5
	after.bag.slots[1].quantity = 4
	after.bag.slots.append({"id": "bag_9", "item_id": "copper_ore", "quantity": 2, "quality": "normal"})
	var pair := _panel(initial, [{"status": 200, "json": {"version": 11, "state": after}}])
	var panel: BagPanel = pair[0]
	await _settle()
	_button(panel, "BagSlot_bag_2").pressed.emit()
	await _settle()
	_button(panel, "ItemDetails").pressed.emit()
	await _settle()
	_button(panel, "SplitStack").pressed.emit()
	await _settle()
	panel.quantity.value = 2
	_button(panel, "ConfirmSplit").pressed.emit()
	await _settle()
	assert_str(pair[2].last_body().type).is_equal("split_bag_stack")
	assert_str(pair[2].last_body().payload.stack_id).is_equal("bag_2")
	assert_int(int(pair[2].last_body().payload.quantity)).is_equal(2)
	assert_int(int(pair[2].last_body().payload.sequence)).is_equal(4)
	assert_str(panel.selected_stack).is_equal("bag_2")
	assert_int(pair[1].state.bag.slots[1].quantity).is_equal(4)

func test_discard_needs_explicit_confirmation_and_back_cancels_without_a_command() -> void:
	var pair := _panel(_state())
	var panel: BagPanel = pair[0]
	await _settle()
	panel.select_stack("bag_4")
	await _settle()
	_button(panel, "ItemDetails").pressed.emit()
	await _settle()
	_button(panel, "DiscardStack").pressed.emit()
	await _settle()
	assert_str(panel.mode).is_equal("discard")
	assert_int(int(panel.quantity.max_value)).is_equal(3)
	assert_int(pair[2].requests.size()).is_zero()
	assert_bool(panel.consume_back()).is_true()
	await _settle()
	assert_str(panel.mode).is_equal("details")
	assert_int(pair[2].requests.size()).is_zero()

func test_offline_and_legacy_bags_remain_readable_without_management_commands() -> void:
	for legacy in [false, true]:
		var initial := _state()
		if legacy: initial.erase("bag")
		var pair := _panel(initial)
		var panel: BagPanel = pair[0]
		if not legacy: pair[1].offline = true
		await _settle()
		assert_bool(panel.find_child("BagSort", true, false).disabled).is_true()
		panel.select_stack("legacy_copper_ore" if legacy else "bag_2")
		await _settle()
		_button(panel, "ItemDetails").pressed.emit()
		await _settle()
		assert_bool(_button(panel, "SplitStack").disabled).is_true()
		assert_int(pair[2].requests.size()).is_zero()

func test_full_bag_blocks_split_but_keeps_overflow_and_merge_available() -> void:
	var initial := _state()
	initial.bag.capacity = initial.bag.slots.size()
	initial.bag.overflow = [{"id": "bag_8", "item_id": "wood", "quantity": 2, "quality": "normal"}]
	var pair := _panel(initial)
	var panel: BagPanel = pair[0]
	await _settle()
	assert_str(panel.find_child("BagCapacity", true, false).text).contains("Full")
	assert_bool(_button(panel, "BagOverflow").visible).is_true()
	panel.select_stack("bag_2")
	await _settle()
	_button(panel, "ItemDetails").pressed.emit()
	await _settle()
	assert_bool(_button(panel, "SplitStack").disabled).is_true()
	assert_bool(_button(panel, "MergeStacks").disabled).is_false()
	panel.select_stack("bag_8")
	await _settle()
	assert_object(_button(panel, "ClaimOverflow")).is_not_null()
	assert_str(BagPanel.bag_error("BAG_FULL")).contains("full")

func test_chinese_catalog_covers_every_description_use_and_name() -> void:
	Localization.select_language("zh_CN")
	for id in ItemCatalog.data().items:
		var spec := ItemCatalog.definition(str(id))
		for value in [spec.name, spec.description] + spec.uses:
			assert_str(L10n.text(str(value))).override_failure_message("Missing Chinese item text: " + str(value)).is_not_equal(str(value))
	assert_bool(ItemCatalog.matches("copper_ore", "mineral", "铜矿")).is_true()
	assert_bool(ItemCatalog.matches("rock_salt", "all", "蔬菜汤")).is_true()

func test_changed_sequence_refreshes_authoritative_bag_before_the_next_action() -> void:
	var initial := _state()
	var current := initial.duplicate(true)
	current.bag.sequence = 5
	current.bag.slots[1].quantity = 5
	var sorted := current.duplicate(true)
	sorted.bag.sequence = 6
	var pair := _panel(initial, [
		{"status": 422, "json": {"code": "BAG_CHANGED"}},
		{"status": 200, "json": {"version": 10, "state": current}},
		{"status": 200, "json": {"version": 11, "state": sorted}}])
	var panel: BagPanel = pair[0]
	await _settle()
	panel.select_stack("bag_2")
	await _settle()
	await panel._manage("split_bag_stack", {"stack_id": "bag_2", "quantity": 2}, "Stack split")
	await _settle()
	assert_int(int(pair[1].state.bag.sequence)).is_equal(5)
	assert_int(int(pair[1].state.bag.slots[1].quantity)).is_equal(5)
	assert_str(panel.message.text).contains("changed")
	assert_int(pair[2].requests.size()).is_equal(2)
	assert_str(pair[2].requests[1].method).is_equal("GET")
	await panel._manage("sort_bag", {"mode": "category"}, "Bag sorted")
	assert_int(int(pair[2].last_body().payload.sequence)).is_equal(5)
	assert_int(int(pair[1].state.bag.sequence)).is_equal(6)

func test_character_attributes_derive_equipment_and_meals_without_changing_ownership() -> void:
	var state := _state()
	state.bag.equipped.main_hand = {"id": "pick", "item_id": "copper_pickaxe", "quantity": 1, "instance_id": "item_10"}
	state.bag.equipped.gloves = {"id": "gloves", "item_id": "foraging_gloves", "quantity": 1, "instance_id": "item_11"}
	state.character.buffs = [{"id": "mining_meal", "source_item_id": "vegetable_soup", "remaining_uses": 2},
		{"id": "gathering_meal", "source_item_id": "salad", "remaining_uses": 1}]
	var original := state.duplicate(true)
	assert_that(CharacterModel.breakdown(state, "mining_bonus")).is_equal({"base": 0, "equipment": 1, "meals": 1, "current": 2})
	assert_float(CharacterModel.current(state, "gather_bonus")).is_equal(2.0)
	assert_float(CharacterModel.current(state, "tool_scope")).is_equal(1.0)
	assert_float(CharacterModel.compare(state, "row_tool", "tool_scope")).is_equal(3.0)
	assert_float(CharacterModel.compare(state, "row_tool", "mining_bonus")).is_equal(1.0)
	assert_float(CharacterModel.current(state, "move_speed")).is_equal(3.75)
	assert_float(CharacterModel.compare(state, "trail_boots", "move_speed")).is_equal(4.25)
	assert_bool(CharacterModel.owns(state, "copper_pickaxe")).is_true()
	assert_that(state).is_equal(original)

func test_action_previews_match_primary_material_and_basic_crafting_budget() -> void:
	var state := _state()
	state.bag.equipped.gloves = {"id": "apron", "item_id": "artisan_apron", "quantity": 1, "instance_id": "item_11"}
	state.character.buffs = [{"id": "crafting_tea", "source_item_id": "tea", "remaining_uses": 3},
		{"id": "gathering_meal", "source_item_id": "salad", "remaining_uses": 3}]
	var input := {"fiber": 4, "stone": 2, "wood": 1, "copper_ore": 4}
	assert_that(CharacterModel.craft_materials(state, input)).is_equal({"fiber": 3, "stone": 1, "wood": 1, "copper_ore": 4})
	assert_that(input).is_equal({"fiber": 4, "stone": 2, "wood": 1, "copper_ore": 4})
	assert_that(CharacterModel.gathered_materials(state, {"fiber": 2, "stone": 2, "wood": 2})).is_equal({"fiber": 2, "stone": 2, "wood": 3})
	assert_that(CharacterModel.gathered_materials(state, {"fiber": 3, "wood": 2})).is_equal({"fiber": 4, "wood": 2})
	assert_that(CharacterModel.craft_materials(state, {"wood": 1, "stone": 1, "fiber": 1, "copper_ore": 4})).is_equal({"wood": 1, "stone": 1, "fiber": 1, "copper_ore": 4})

func test_character_page_preserves_equipment_navigation_and_offline_reading() -> void:
	var pair := _panel(_state())
	var panel: BagPanel = pair[0]
	await _settle()
	_button(panel, "BagPage_character").pressed.emit()
	await _settle()
	assert_str(panel.page).is_equal("character")
	assert_str(panel.find_child("CharacterStat_tool_scope", true, false).text).is_equal("1")
	assert_object(_button(panel, "CharacterSlot_gloves")).is_not_null()
	_button(panel, "ChangeEquipment_main_hand").pressed.emit()
	await _settle()
	assert_str(panel.mode).is_equal("equipment")
	_button(panel, "ChooseEquipment_bag_5").pressed.emit()
	await _settle()
	assert_str(panel.selected_stack).is_equal("bag_5")
	assert_bool(panel.consume_back()).is_true()
	await _settle()
	assert_str(panel.page).is_equal("character")
	assert_str(panel.mode).is_equal("grid")
	pair[1].offline = true
	panel.refresh()
	await _settle()
	assert_bool(_button(panel, "UnequipSlot_main_hand").disabled).is_true()
	assert_int(pair[2].requests.size()).is_zero()

func test_eating_uses_selected_stack_sequence_and_blocks_repeating_active_effect() -> void:
	var initial := _state()
	initial.bag.slots.append({"id": "meal", "item_id": "vegetable_soup", "quantity": 2, "quality": "normal"})
	var after := initial.duplicate(true)
	after.bag.slots[-1].quantity = 1
	after.bag.sequence = 5
	after.character.buffs = [{"id": "mining_meal", "source_item_id": "vegetable_soup", "remaining_uses": 3}]
	var pair := _panel(initial, [{"status": 200, "json": {"version": 11, "state": after}}])
	var panel: BagPanel = pair[0]
	await _settle()
	panel.select_stack("meal")
	await _settle()
	_button(panel, "EatItem").pressed.emit()
	await _settle()
	assert_str(pair[2].last_body().type).is_equal("use_bag_item")
	assert_str(pair[2].last_body().payload.stack_id).is_equal("meal")
	assert_int(int(pair[2].last_body().payload.sequence)).is_equal(4)
	assert_int(pair[2].requests.size()).is_equal(1)
	assert_bool(_button(panel, "EatItem").disabled).is_true()
	assert_float(CharacterModel.current(pair[1].state, "mining_bonus")).is_equal(1.0)
	assert_int(CharacterModel.active_buff(pair[1].state, "vegetable_soup").remaining_uses).is_equal(3)

func test_accessory_unequip_keeps_the_tool_slot_and_sends_explicit_slot() -> void:
	var initial := _state()
	initial.bag.equipped.gloves = {"id": "gloves", "item_id": "foraging_gloves", "quantity": 1, "instance_id": "item_10"}
	var after := initial.duplicate(true)
	after.bag.slots.append(after.bag.equipped.gloves)
	after.bag.equipped.gloves = null
	after.bag.sequence = 5
	var pair := _panel(initial, [{"status": 200, "json": {"version": 11, "state": after}}])
	var panel: BagPanel = pair[0]
	await _settle()
	panel.select_page("character")
	await _settle()
	_button(panel, "UnequipSlot_gloves").pressed.emit()
	await _settle()
	assert_str(pair[2].last_body().type).is_equal("unequip_bag_item")
	assert_str(pair[2].last_body().payload.slot).is_equal("gloves")
	assert_float(CharacterModel.current(pair[1].state, "gather_bonus")).is_zero()
	assert_str(CharacterModel.equipped(pair[1].state, "main_hand").item_id).is_equal("hand_tools")
	assert_bool(CharacterModel.owns(pair[1].state, "foraging_gloves")).is_true()

func test_character_chinese_effects_and_equipment_are_readable() -> void:
	Localization.select_language("zh_CN")
	assert_str(CharacterModel.effect_label("vegetable_soup")).contains("开采石料加成")
	assert_str(CharacterModel.effect_label("tea")).contains("3 次")
	assert_str(CharacterModel.stat_description("craft_savings")).contains("至少消耗一份")
	assert_str(BagPanel.bag_error("EFFECT_ACTIVE")).contains("没有消耗")
	assert_str(ItemCatalog.name_of("copper_pickaxe")).is_equal("铜镐")
	for stat in CharacterModel.STATS:
		assert_str(CharacterModel.stat_name(stat)).is_not_equal(stat)

func test_workbench_crafts_equipment_with_bag_sequence_and_discounted_materials() -> void:
	var initial := _state()
	initial.journey.facts.append("planter_crafted")
	initial.journey.wood = 1
	initial.journey.materials = {"fiber": 3, "copper_ore": 0, "stone": 0}
	initial.journey.workshop.sequence = 99
	initial.bag.equipped.gloves = {"id": "apron", "item_id": "artisan_apron", "quantity": 1, "instance_id": "item_12"}
	initial.character.buffs = [{"id": "crafting_tea", "source_item_id": "tea", "remaining_uses": 3}]
	var after := initial.duplicate(true)
	after.bag.sequence = 5
	after.bag.slots.append({"id": "gloves", "item_id": "foraging_gloves", "quantity": 1, "instance_id": "item_13"})
	after.journey.wood = 0
	after.journey.materials.fiber = 0
	after.character.buffs[0].remaining_uses = 2
	var transport := FakeTransport.new([{"status": 200, "json": {"version": 11, "state": after, "outcome": "applied",
		"events": [{"type": "equipment_crafted", "item_id": "foraging_gloves", "actual_saved": {"wood": 1, "fiber": 1}}]}}])
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = initial
	session.version = 10
	var panel := JourneyActivityPanel.new()
	panel.target = "workbench"
	panel.place_id = "nursery"
	panel.setup(session)
	add_child(auto_free(panel))
	await _settle()
	var craft := panel.find_child("CraftEquipment_foraging_gloves", true, false) as Button
	assert_bool(craft.disabled).is_false()
	assert_bool((panel.find_child("CraftEquipment_artisan_apron", true, false) as Button).disabled).is_true()
	craft.pressed.emit()
	await _settle()
	assert_str(transport.last_body().type).is_equal("craft_equipment")
	assert_str(transport.last_body().payload.item_id).is_equal("foraging_gloves")
	assert_int(int(transport.last_body().payload.sequence)).is_equal(4)
	assert_bool((panel.find_child("CraftEquipment_foraging_gloves", true, false) as Button).disabled).is_true()
	assert_str(panel.message.text).contains("in your bag")
	assert_str(panel.message.text).contains("Saved: 1 wood + 1 reeds")
	assert_str(panel.message.text).contains("Tea: 2 uses left")

func test_six_slots_and_main_hand_efficiency_match_the_selected_item() -> void:
	var state := _state()
	assert_array(CharacterModel.SLOTS).is_equal(["main_hand", "fishing_rod", "ring_1", "ring_2", "necklace", "gloves"])
	assert_array(CharacterModel.equipment_slots("copper_ring")).is_equal(["ring_1", "ring_2"])
	state.bag.equipped.main_hand = {"item_id": "copper_pickaxe"}
	assert_float(CharacterModel.gather_seconds(state, "ore", 1)).is_equal(0.5)
	assert_float(float(CharacterModel.main_hand_stats(state).damage)).is_equal(7.0)
	state.bag.equipped.main_hand = {"item_id": "copper_axe"}
	assert_float(CharacterModel.gather_seconds(state, "wood")).is_equal(0.45)
	assert_bool(CharacterModel.has_fishing_rod(state)).is_false()
	state.bag.equipped.fishing_rod = {"item_id": "starter_fishing_rod"}
	assert_bool(CharacterModel.has_fishing_rod(state)).is_true()
	state.bag.equipped.ring_1 = {"item_id": "copper_ring"}
	state.bag.equipped.ring_2 = {"item_id": "wooden_ring"}
	assert_float(CharacterModel.current(state, "defense")).is_equal(1.0)
	assert_float(CharacterModel.current(state, "max_hp")).is_equal(110.0)


func test_character_preview_renders_at_physical_density_without_changing_logical_layout() -> void:
	var stage := auto_free(Control.new()) as Control
	add_child(stage)
	var screen_scale := get_viewport().get_screen_transform().x.length()
	stage.scale = Vector2.ONE * (3.0 / maxf(0.001, screen_scale))
	var preview := BagCharacterPreview.new()
	stage.add_child(preview)
	preview.size = Vector2(112, 196)
	preview._resize_viewport()
	assert_vector(preview.size).is_equal(Vector2(112, 196))
	assert_vector(preview.viewport.size).is_equal(Vector2i(336, 588))
	assert_object(preview.texture).is_same(preview.viewport.get_texture())
	# A subsequent physical scale change does not have to resize the logical control.
	stage.scale = Vector2.ONE * (4.0 / maxf(0.001, screen_scale))
	preview._resize_viewport()
	assert_vector(preview.viewport.size).is_equal(Vector2i(448, 784))
	preview.size = Vector2(224, 392)
	preview._resize_viewport()
	assert_int(preview.viewport.size.y).is_equal(1024)
	assert_float(float(preview.viewport.size.x) / preview.viewport.size.y).is_equal_approx(224.0 / 392.0, 0.002)
	assert_vector(preview.size).is_equal(Vector2(224, 392))
	assert_object(preview.rig).is_null()

func test_character_preview_keeps_saved_outfit_world_camera_and_hidden_rendering_state() -> void:
	var saved := Avatar.load_outfit().to_json_text()
	var camera := get_viewport().get_camera_3d()
	var preview := auto_free(BagCharacterPreview.new()) as BagCharacterPreview
	add_child(preview)
	preview.set_active(true)
	for frame in 180:
		if preview.rig != null and not preview.rig.is_busy(): break
		await get_tree().process_frame
	assert_object(preview.rig).is_not_null()
	assert_bool(preview.rig.is_busy()).is_false()
	assert_int(preview.viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_ALWAYS)
	assert_str(Avatar.load_outfit().to_json_text()).is_equal(saved)
	assert_object(get_viewport().get_camera_3d()).is_equal(camera)
	preview.hide()
	assert_int(preview.viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)
	assert_bool(preview.is_processing()).is_false()
	Avatar.outfit_saved.emit(Avatar.load_outfit())
	assert_bool(preview._outfit_dirty).is_true()
	preview.show()
	assert_bool(preview._outfit_dirty).is_false()
	preview.set_active(false)
	assert_int(preview.viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)
	assert_bool(preview.is_processing()).is_false()
