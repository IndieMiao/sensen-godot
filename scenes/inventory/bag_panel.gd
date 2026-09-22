class_name BagPanel
extends SessionPanel

signal goal_requested(goal: Dictionary)
signal close_requested()

const CharacterPreview = preload("res://scenes/inventory/character_preview.gd")

var target := "supplies"
var category := "all"
var query := ""
var selected_stack := ""
var showing_overflow := false
var mode := "grid"
var page := "bag"
var equipment_slot := "main_hand"
var _focused_equipment_slot := "main_hand"
var request_slot := ""
var request_operation := ""
var request_sequence := -1
var request_timber_only := false
var search: LineEdit
var category_filter: OptionButton
var grid: GridContainer
var body_scroll: ScrollContainer
var quantity: SpinBox
var _body: VBoxContainer
var _filters: HBoxContainer
var _selection: PanelContainer
var _selection_body: VBoxContainer
var _preview_stash: Control
var _character_preview: BagCharacterPreview
var _capacity: Label
var _back: Button
var _overflow: Button
var _sort: MenuButton
var _equipped: Button
var _recovery: Button
var _close_button: Button
var _built := false
var _needs_refresh := false
var _pages: Dictionary = {}

func _ready() -> void:
	super._ready()
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_resize_grid)

func _build_controls() -> void:
	_built = true
	content.add_theme_constant_override("separation", 6)
	var header := HBoxContainer.new()
	header.name = "BagHeader"
	header.custom_minimum_size.y = 44
	header.add_theme_constant_override("separation", 3)
	content.add_child(header)
	_back = GameUi.button("arrow-left", "", L10n.text("Back to bag"))
	_back.name = "BagBack"
	_back.theme_type_variation = &"IconButton"
	_back.custom_minimum_size = Vector2(44, 44)
	_back.pressed.connect(consume_back)
	header.add_child(_back)
	for spec in [["bag", "backpack", "Your bag"], ["character", "user-round", "Character"], ["requests", "list-checks", "Requests"]]:
		var tab := GameUi.button(str(spec[1]), L10n.text(str(spec[2])) if spec[0] != "requests" else "", L10n.text(str(spec[2])))
		tab.name = "BagPage_" + str(spec[0])
		tab.custom_minimum_size = Vector2(64 if spec[0] != "requests" else 44, 44)
		tab.add_theme_font_size_override("font_size", 12)
		tab.clip_text = true
		tab.pressed.connect(select_page.bind(str(spec[0])))
		header.add_child(tab)
		_pages[spec[0]] = tab
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(space)
	_capacity = GameUi.label("", 11)
	_capacity.name = "BagCapacity"
	_capacity.custom_minimum_size.x = 44
	_capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_capacity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_capacity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_capacity)
	var close_button := GameUi.button("x", "", L10n.text("Close"))
	close_button.name = "CloseBag"
	_close_button = close_button
	close_button.theme_type_variation = &"IconButton"
	close_button.custom_minimum_size = Vector2(44, 44)
	close_button.pressed.connect(func(): close_requested.emit())
	header.add_child(close_button)
	_selection = PanelContainer.new()
	_selection.name = "SelectedItemStrip"
	_selection.add_theme_stylebox_override("panel", GameUi.card_style(false, 8))
	content.add_child(_selection)
	_selection_body = VBoxContainer.new()
	_selection_body.add_theme_constant_override("separation", 4)
	_selection.add_child(_selection_body)
	_filters = HBoxContainer.new()
	_filters.name = "BagTools"
	_filters.add_theme_constant_override("separation", 4)
	content.add_child(_filters)
	search = LineEdit.new()
	search.name = "BagSearch"
	search.placeholder_text = L10n.text("Search items")
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(60, 44)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_font_size_override("font_size", 12)
	_style_input(search)
	search.text_changed.connect(func(value):
		query = value
		refresh())
	_filters.add_child(search)
	_sort = MenuButton.new()
	_sort.name = "BagSort"
	_sort.icon = GameUi.icon("arrow-up-down")
	_sort.tooltip_text = L10n.text("Sort bag")
	_sort.custom_minimum_size = Vector2(44, 44)
	_sort.theme_type_variation = &"IconButton"
	_sort.get_popup().add_item(L10n.text("Sort by category"), 0)
	_sort.get_popup().add_item(L10n.text("Sort by name"), 1)
	_sort.get_popup().id_pressed.connect(func(id): _manage("sort_bag", {"mode": "category" if id == 0 else "name"}, "Bag sorted"))
	_filters.add_child(_sort)
	category_filter = OptionButton.new()
	category_filter.name = "BagFilter"
	category_filter.tooltip_text = L10n.text("Filter items")
	category_filter.custom_minimum_size = Vector2(70, 44)
	category_filter.fit_to_longest_item = false
	category_filter.add_theme_font_size_override("font_size", 11)
	for id in ItemCatalog.CATEGORIES: category_filter.add_item(ItemCatalog.category_name(id))
	category_filter.item_selected.connect(func(index):
		category = ItemCatalog.CATEGORIES[index]
		refresh())
	_filters.add_child(category_filter)
	_overflow = GameUi.button("package-check", "", L10n.text("Overflow items"))
	_overflow.name = "BagOverflow"
	_overflow.custom_minimum_size = Vector2(44, 44)
	_overflow.pressed.connect(func():
		if busy: return
		showing_overflow = not showing_overflow
		mode = "grid"
		selected_stack = ""
		refresh())
	_filters.add_child(_overflow)
	_equipped = GameUi.button("shovel", "", L10n.text("Equipped main hand"))
	_equipped.name = "BagEquipped"
	_equipped.custom_minimum_size = Vector2(44, 44)
	_equipped.pressed.connect(func():
		var entry = BagModel.snapshot(state()).get("equipped", {}).get("main_hand")
		if entry is Dictionary: select_stack(str(entry.id)))
	_filters.add_child(_equipped)
	_recovery = GameUi.button("refresh-cw", L10n.text("Refresh bag"), L10n.text("Refresh bag"), true)
	_recovery.name = "ReconnectSession"
	_recovery.custom_minimum_size.y = 44
	_recovery.pressed.connect(_recover_bag)
	_recovery.hide()
	content.add_child(_recovery)
	body_scroll = TouchScrollContainer.new()
	body_scroll.name = "BagScroll"
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(body_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	body_scroll.add_child(_body)
	_preview_stash = Control.new()
	_preview_stash.name = "CharacterPreviewCache"
	_preview_stash.hide()
	add_child(_preview_stash)

func _rebuild() -> void:
	_refresh_queued = false
	if not is_inside_tree() or content == null: return
	if not _built: _build_controls()
	var offset := body_scroll.scroll_vertical
	_clear_body()
	var bag := BagModel.snapshot(state())
	var used: int = bag.get("slots", []).size()
	var capacity := int(bag.get("capacity", 24))
	for id in _pages:
		_pages[id].theme_type_variation = &"TabSelectedButton" if id == page else &"TabButton"
		_pages[id].disabled = busy
	_capacity.text = "%d / %d" % [used, capacity]
	_capacity.tooltip_text = L10n.format_text("Bag %d / %d", [used, capacity])
	_capacity.visible = page == "bag" and mode in ["grid", "details"]
	if used >= capacity: _capacity.text += "  " + L10n.text("Full")
	_capacity.add_theme_color_override("font_color", GameUi.CORAL if used >= capacity else GameUi.INK)
	_overflow.text = str(bag.get("overflow", []).size())
	_overflow.visible = page == "bag" and (not bag.get("overflow", []).is_empty() or showing_overflow)
	_overflow.disabled = busy
	_overflow.theme_type_variation = &"ChoiceSelectedButton" if showing_overflow else &"SecondaryButton"
	_sort.disabled = not _can_manage() or showing_overflow
	_sort.visible = page == "bag" and mode in ["grid", "details"]
	_filters.visible = page == "bag" and mode in ["grid", "details"]
	_selection.visible = _filters.visible
	_back.visible = mode not in ["grid", "details"] or showing_overflow or (page == "character" and mode == "details")
	_back.disabled = busy
	category_filter.disabled = busy
	search.editable = not busy
	var tool = bag.get("equipped", {}).get("main_hand")
	_equipped.tooltip_text = L10n.text("Equipped main hand") + ": " + (ItemCatalog.name_of(str(tool.item_id)) if tool is Dictionary else L10n.text("None"))
	_equipped.icon = ItemCatalog.texture(str(tool.item_id)) if tool is Dictionary else GameUi.icon("shovel")
	_equipped.disabled = busy or not tool is Dictionary
	_equipped.visible = size.x >= 420
	message.visible = not message.text.is_empty()
	if page == "requests": _render_requests()
	elif mode not in ["grid", "equipment"] and BagModel.stack(state(), selected_stack).is_empty():
		mode = "grid"
		selected_stack = ""
		refresh()
	elif mode == "equipment": _render_equipment()
	elif mode == "grid" and page == "character": _render_character()
	elif page == "bag" and mode in ["grid", "details"]:
		_render_selection(BagModel.stack(state(), selected_stack))
		_render_grid(bag)
	else: _render_details(BagModel.stack(state(), selected_stack))
	_recovery.visible = session != null and (session.offline or session.has_unconfirmed_command() or not BagModel.canonical(state()) or _needs_refresh)
	_recovery.text = L10n.text("Reconnect" if session != null and session.offline else "Refresh bag")
	_recovery.disabled = busy
	_close_button.disabled = busy
	for button in _body.find_children("*", "BaseButton", true, false):
		(button as BaseButton).mouse_filter = Control.MOUSE_FILTER_PASS
	body_scroll.set_deferred("scroll_vertical", offset)
	_resize_grid.call_deferred()

func _clear_body() -> void:
	if is_instance_valid(_character_preview):
		_character_preview.set_active(false)
		if _character_preview.get_parent() != _preview_stash: _character_preview.reparent(_preview_stash)
	for child in _selection_body.get_children():
		_selection_body.remove_child(child)
		child.queue_free()
	grid = null
	quantity = null
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

func _selection_button(parent: Container, id: String, symbol: String, title: String, callback: Callable, allowed := true, primary := false) -> Button:
	var button := GameUi.button(symbol, L10n.text(title), L10n.text(title), primary)
	button.name = id
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_font_size_override("font_size", 11)
	button.clip_text = true
	button.disabled = not allowed or busy
	button.pressed.connect(func():
		if not button.disabled: callback.call())
	parent.add_child(button)
	return button

func _render_selection(entry: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_selection_body.add_child(head)
	var id := str(entry.get("item_id", ""))
	var artwork := VBoxContainer.new()
	artwork.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	artwork.add_theme_constant_override("separation", 2)
	head.add_child(artwork)
	var art := GameUi.picture(ItemCatalog.texture(id) if not entry.is_empty() else GameUi.icon("backpack"), 48)
	artwork.add_child(art)
	if not entry.is_empty():
		var amount := GameUi.label("×" + str(int(entry.quantity)), 12, GameUi.GREEN)
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		artwork.add_child(amount)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 3)
	head.add_child(words)
	var title := GameUi.label(ItemCatalog.name_of(id) if not entry.is_empty() else L10n.text("Your bag"), 15)
	title.name = "SelectedItemName"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(title)
	var spec := ItemCatalog.definition(id)
	var description := GameUi.label(L10n.text(str(spec.get("description", ""))) if not entry.is_empty() else L10n.text("Select an item to view its details."), 11, GameUi.MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.max_lines_visible = 2
	description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	words.add_child(description)
	if entry.is_empty(): return
	var quality := FishingModel.tier_name(id) if spec.get("category") == "fish" else ItemCatalog.quality_name(str(entry.get("quality", "normal")))
	words.add_child(GameUi.label(quality, 10, GameUi.BLUE))
	var primary := VBoxContainer.new()
	primary.custom_minimum_size.x = 78
	primary.add_theme_constant_override("separation", 0)
	primary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(primary)
	var bag := BagModel.snapshot(state())
	var overflow: bool = bag.get("overflow", []).any(func(stack): return stack.id == entry.id)
	var slot := CharacterModel.equipped_slot(state(), str(entry.id))
	var equipment := CharacterModel.equipment(id)
	var meal := CharacterModel.consumable(id)
	if spec.get("category") == "fish":
		_selection_button(primary, "SellFish", "", "Sell fish", func(): _set_mode("sell_fish"), _can_manage(), true)
	elif not meal.is_empty():
		_selection_button(primary, "EatItem", "", "Eat one" if CharacterModel.can_eat(state(), id) else "Effect active", func(): _manage("use_bag_item", {"stack_id": selected_stack}, "Meal effect applied"), _can_manage() and CharacterModel.canonical(state()) and CharacterModel.can_eat(state(), id), true)
	elif overflow:
		_selection_button(primary, "ClaimOverflow", "", "Move into bag", func(): _manage("claim_bag_overflow", {"stack_id": selected_stack}, "Item moved into bag"), _can_manage(), true)
	elif not equipment.is_empty():
		if not slot.is_empty():
			_selection_button(primary, "UnequipTool", "", "Unequip", func(): _manage("unequip_bag_item", {"slot": slot}, "Equipment unequipped"), _can_manage(), true)
		else:
			var choices := CharacterModel.equipment_slots(id)
			var destination := equipment_slot if equipment_slot in choices else str(choices[0])
			_selection_button(primary, "EquipTool" if choices.size() == 1 else "EquipTo_" + destination, "", L10n.format_text("Equip to %s", CharacterModel.slot_name(destination)), func(): _manage("equip_bag_item", {"stack_id": selected_stack, "slot": destination}, "Equipment equipped"), _can_manage(), true)
	else:
		var routes := BagModel.routes(state(), id)
		var usable := routes.filter(func(goal): return goal.place == "farm" or PlaceCatalog.available(str(goal.place), state()))
		if not usable.is_empty():
			var goal: Dictionary = usable[0]
			var action_label := "Go craft" if str(goal.target) == "workbench" else ("Go cook" if str(goal.target) == "counter" else str(goal.label))
			var route_button := _selection_button(primary, "BagUse_" + str(goal.place) + "_" + str(goal.target), "", action_label, func(): goal_requested.emit(goal), _can_navigate(), true)
			route_button.tooltip_text = str(goal.label)
	var details := _selection_button(primary, "ItemDetails", "info", "Item details", func(): _set_mode("inspect"))
	details.text = ""
	details.theme_type_variation = &"IconButton"
	details.size_flags_horizontal = Control.SIZE_SHRINK_END

func _render_grid(bag: Dictionary) -> void:
	if showing_overflow: _text(L10n.text("Overflow items"), 15)
	var entries: Array = bag.get("overflow" if showing_overflow else "slots", [])
	var visible_entries := entries.filter(func(entry): return ItemCatalog.matches(str(entry.item_id), category, query))
	grid = GridContainer.new()
	grid.name = "BagGrid"
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	_body.add_child(grid)
	for entry in visible_entries: grid.add_child(_tile(entry))
	if category == "all" and query.strip_edges().is_empty() and not showing_overflow:
		for index in maxi(0, int(bag.get("capacity", 24)) - entries.size()): grid.add_child(_tile({}))
	if visible_entries.is_empty():
		_text(L10n.text("No overflow items" if showing_overflow and entries.is_empty() else ("No matching items" if not entries.is_empty() else "Your bag is empty")))

func _tile(entry: Dictionary) -> Button:
	var button := GameUi.button("", "", "")
	button.custom_minimum_size = Vector2(44, 80)
	button.theme_type_variation = &"ItemSlotSelectedButton" if not entry.is_empty() and str(entry.id) == selected_stack else &"ItemSlotButton"
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	if entry.is_empty():
		button.name = "EmptySlot"
		button.disabled = true
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(center)
		var empty := GameUi.picture(GameUi.icon("plus"), 18)
		empty.modulate = GameUi.BORDER
		center.add_child(empty)
		return button
	var id := str(entry.item_id)
	button.name = "BagSlot_" + str(entry.id)
	button.tooltip_text = ItemCatalog.name_of(id) + " x" + str(int(entry.quantity))
	button.disabled = busy
	button.pressed.connect(select_stack.bind(str(entry.id)))
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 4
	column.offset_right = -4
	column.offset_top = 4
	column.offset_bottom = -4
	column.add_theme_constant_override("separation", 1)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(column)
	column.add_child(GameUi.picture(ItemCatalog.texture(id), 34))
	var label := GameUi.label(ItemCatalog.name_of(id), 11)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size.y = 17
	column.add_child(label)
	var count := GameUi.label("×" + str(int(entry.quantity)), 12, GameUi.GREEN)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(count)
	return button

func _resize_grid() -> void:
	if is_instance_valid(grid): grid.columns = 5

func select_page(id: String) -> void:
	if busy: return
	page = id
	mode = "grid"
	selected_stack = ""
	showing_overflow = false
	if is_instance_valid(search): search.release_focus()
	if is_instance_valid(body_scroll): body_scroll.scroll_vertical = 0
	message.text = ""
	refresh()

func _render_character() -> void:
	var health := HBoxContainer.new()
	health.add_theme_constant_override("separation", 8)
	_body.add_child(health)
	var hp := GameUi.label(L10n.format_text("HP %d / %d", [CharacterModel.hp(state()), int(CharacterModel.current(state(), "max_hp"))]), 14, GameUi.GREEN)
	hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	health.add_child(hp)
	var hp_bar := ProgressBar.new()
	hp_bar.name = "CharacterHealth"
	hp_bar.custom_minimum_size.y = 8
	hp_bar.max_value = CharacterModel.current(state(), "max_hp")
	hp_bar.value = CharacterModel.hp(state())
	hp_bar.show_percentage = false
	_body.add_child(hp_bar)
	var paper := PanelContainer.new()
	paper.name = "CharacterEquipment"
	paper.add_theme_stylebox_override("panel", GameUi.card_style(false, 6))
	_body.add_child(paper)
	var equipment := HBoxContainer.new()
	equipment.add_theme_constant_override("separation", 6)
	paper.add_child(equipment)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 7)
	left.custom_minimum_size.x = 60
	equipment.add_child(left)
	var portrait := VBoxContainer.new()
	portrait.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equipment.add_child(portrait)
	if not is_instance_valid(_character_preview):
		_character_preview = CharacterPreview.new()
		_character_preview.name = "CharacterPreview"
		portrait.add_child(_character_preview)
	else: _character_preview.reparent(portrait)
	_character_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character_preview.set_active(true)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 7)
	right.custom_minimum_size.x = 60
	equipment.add_child(right)
	for index in CharacterModel.SLOTS.size():
		_character_slot(CharacterModel.SLOTS[index], left if index < 3 else right)
	for slot in CharacterModel.SLOTS: _character_slot_actions(slot)
	_text(L10n.text("Attributes"), 15, GameUi.INK)
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 6)
	stats.add_theme_constant_override("v_separation", 6)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(stats)
	for stat in CharacterModel.STATS:
		var values := CharacterModel.breakdown(state(), stat)
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", GameUi.card_style(false, 7))
		card.tooltip_text = CharacterModel.stat_description(stat) + "\n" + L10n.format_text("Base %s / Equipment +%s / Meals +%s", [ItemCatalog.property_value(values.base), ItemCatalog.property_value(values.equipment), ItemCatalog.property_value(values.meals)])
		stats.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var caption := GameUi.label(CharacterModel.stat_name(stat), 11)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(caption)
		var value := GameUi.label(ItemCatalog.property_value(values.current), 16, GameUi.GREEN)
		value.name = "CharacterStat_" + stat
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(value)
	_text(L10n.text("Main-hand attributes"), 15, GameUi.INK)
	var hand := CharacterModel.main_hand_stats(state())
	var attributes := GridContainer.new()
	attributes.columns = 2
	attributes.add_theme_constant_override("h_separation", 12)
	attributes.add_theme_constant_override("v_separation", 4)
	_body.add_child(attributes)
	for stat in CharacterModel.HAND_STATS:
		var label := GameUi.label(ItemCatalog.property_name(stat) + "  " + ItemCatalog.property_value(hand[stat]), 11, GameUi.INK)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		attributes.add_child(label)
	_text(L10n.text("Higher gathering efficiency reduces action time; it does not multiply the loot."), 11)
	var craft := _button("hammer", "Make equipment", func(): goal_requested.emit({"place": "nursery", "target": "workbench"}), _can_navigate())
	craft.name = "CharacterCraftEquipment"
	if int(state().get("mine", {}).get("floor", 0)) == 0 and JourneyProgress.active(state()):
		var rest := _button("heart", "Rest at the farm", func(): _manage("rest_character", {}, "Health restored"), _can_manage() and CharacterModel.hp(state()) < CharacterModel.current(state(), "max_hp"))
		rest.name = "RestCharacter"
		rest.custom_minimum_size.y = 44
		rest.add_theme_font_size_override("font_size", 11)
	_text(L10n.text("Active meals"), 15, GameUi.INK)
	var effects := CharacterModel.buffs(state())
	if effects.is_empty(): _text(L10n.text("No active meal effects"), 12)
	for buff in effects:
		var spec := CharacterModel.consumable(str(buff.source_item_id))
		_text(ItemCatalog.name_of(str(buff.source_item_id)) + " · " + CharacterModel.stat_name(str(spec.stat)) + " +" + str(int(spec.amount)) + " / " + L10n.format_text("%d uses left", int(buff.remaining_uses)), 12, GameUi.GREEN)
	if not CharacterModel.canonical(state()): _text(L10n.text("Refresh to load character actions."), 12)

func _character_slot(slot: String, parent: VBoxContainer) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	parent.add_child(column)
	var caption := GameUi.label(CharacterModel.slot_name(slot), 10, GameUi.MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption)
	var entry := CharacterModel.equipped(state(), slot)
	var symbol := str({"main_hand": "sword", "fishing_rod": "fish", "ring_1": "circle", "ring_2": "circle", "necklace": "gem", "gloves": "hand"}.get(slot, "shirt"))
	var selected := GameUi.button(symbol, "", ItemCatalog.name_of(str(entry.item_id)) if not entry.is_empty() else L10n.text("Empty equipment slot"))
	selected.name = "CharacterSlot_" + slot
	selected.theme_type_variation = &"ItemSlotSelectedButton" if slot == _focused_equipment_slot else &"ItemSlotButton"
	selected.custom_minimum_size = Vector2(60, 48)
	selected.add_theme_constant_override("icon_max_width", 36)
	selected.disabled = busy
	if not entry.is_empty():
		selected.icon = ItemCatalog.texture(str(entry.item_id))
		var tint := GameUi.BLUE if GameUi.is_game_icon(selected.icon) else Color.WHITE
		for state_name in ["normal", "hover", "pressed", "focus"]: selected.add_theme_color_override("icon_" + state_name + "_color", tint)
	selected.pressed.connect(func():
		if busy: return
		_focused_equipment_slot = slot
		equipment_slot = slot
		if entry.is_empty(): _choose_equipment(slot)
		else: refresh())
	column.add_child(selected)

func _character_slot_actions(slot: String) -> void:
	var entry := CharacterModel.equipped(state(), slot)
	var context := VBoxContainer.new()
	context.name = "CharacterSlotActions_" + slot
	context.visible = slot == _focused_equipment_slot
	context.add_theme_constant_override("separation", 3)
	_body.add_child(context)
	var title := GameUi.label(CharacterModel.slot_name(slot) + " · " + (ItemCatalog.name_of(str(entry.item_id)) if not entry.is_empty() else L10n.text("Empty equipment slot")), 12)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	context.add_child(title)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	context.add_child(controls)
	var change := _selection_button(controls, "ChangeEquipment_" + slot, "arrow-up-down", "Change equipment", _choose_equipment.bind(slot), not busy, true)
	change.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not entry.is_empty():
		var remove := _selection_button(controls, "UnequipSlot_" + slot, "minus", "Unequip", func(): _manage("unequip_bag_item", {"slot": slot}, "Equipment unequipped"), _can_manage())
		remove.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var details := _selection_button(controls, "EquipmentDetails_" + slot, "info", "Item details", select_stack.bind(str(entry.id)))
		details.text = ""

func _render_requests() -> void:
	if not JourneyProgress.active(state()):
		_text(L10n.text("Neighbourhood requests begin at the nursery."))
		_button("compass", "Visit the nursery", func(): goal_requested.emit({"place": "nursery", "target": "resident"}), _can_navigate())
		return
	if mode == "request_details":
		var spec := JourneyProgress.offer(state(), request_slot)
		_text(L10n.text(str(ResidentCast.definition(str(StreetCommons.RESIDENTS[request_slot])).name)), 16, GameUi.INK)
		_text(L10n.text(str(spec.get("name", "Request"))), 15, GameUi.INK)
		_text(JourneyRequests.status(state(), request_slot), 12, GameUi.GREEN)
		_text(L10n.text(str(spec.get("description", ""))), 13)
		_request_items(JourneyRequests.requirements(state(), request_slot))
		_text(L10n.format_text("Reward: %d coins", int(spec.get("coins", 0))), 13, GameUi.GREEN)
		_text(StreetCommons.progress(state(), str(spec.get("effect", ""))), 13)
		if JourneyRequests.available(state(), request_slot):
			if not JourneyRequests.accepted(state(), request_slot):
				var accept := _button("check", "Accept and track", _request_command.bind("accept_opportunity", request_slot, int(JourneyRequests.progress(state(), request_slot).sequence)), _can_manage(), true)
				accept.name = "DetailsAcceptRequest_" + request_slot
			else:
				var goal := JourneyRequests.goal(JourneyProgress.goal_state(session), session.server_now(), request_slot)
				var ready := JourneyRequests.supplies_ready(state(), request_slot)
				var go := _button("package-check" if ready else str(goal.get("icon", "compass")), "Go to delivery" if ready else str(goal.get("hint", "Go to current goal")), func(): goal_requested.emit(goal), _can_navigate() and not goal.is_empty(), true)
				go.name = "DetailsGoToRequest_" + request_slot
		if request_slot == "restorer" and spec.get("id") != "timber_for_repairs" and JourneyRequests.available(state(), request_slot):
			var timber := _button("axe", "Request timber-only work", _confirm_request.bind("decline_opportunity", request_slot, true) if JourneyRequests.accepted(state(), request_slot) else _request_command.bind("decline_opportunity", request_slot, int(JourneyRequests.progress(state(), request_slot).sequence), true), _can_manage())
			timber.name = "BoardTimberOnlyRequest"
		var reply := JourneyRequests.last_reply(state(), request_slot)
		if not reply.is_empty():
			_text(L10n.text("Last delivery"), 14, GameUi.INK)
			_text(reply, 13)
		return
	if mode == "request_history":
		var record := JourneyRequests.last_completed(state(), request_slot)
		var spec := JourneyRequests.completed_offer(state(), request_slot)
		_text(L10n.text("Last delivery"), 16, GameUi.INK)
		_text(L10n.text(str(spec.get("name", "Request"))), 15, GameUi.INK)
		_request_items(record.get("consumed", {}), true)
		_text(L10n.format_text("Received %d coins", int(record.get("coins", 0))), 13, GameUi.GREEN)
		_text(JourneyRequests.last_reply(state(), request_slot), 13)
		return
	if mode == "request_confirm":
		_text(L10n.text("Abandon this request?" if request_operation == "abandon_opportunity" else "Replace this request?"), 16, GameUi.INK)
		_text(L10n.text(str(JourneyProgress.offer(state(), request_slot).get("name", "Request"))), 14)
		_text(L10n.text("Your items stay in your bag."))
		var confirm := _button("x", "Confirm abandon" if request_operation == "abandon_opportunity" else "Confirm replacement", _request_command.bind(request_operation, request_slot, request_sequence, request_timber_only), _can_manage(), true)
		confirm.name = "ConfirmRequestChange"
		return
	for slot in JourneyRequests.SLOTS:
		var spec := JourneyProgress.offer(state(), slot)
		if spec.is_empty(): continue
		var resident_id := str(StreetCommons.RESIDENTS[slot])
		var sequence := int(JourneyRequests.progress(state(), slot).get("sequence", -1))
		var head := HBoxContainer.new()
		_body.add_child(head)
		var heading := _text(L10n.text(str(ResidentCast.definition(resident_id).name)), 16, GameUi.INK)
		heading.name = "RequestResident_" + slot
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.reparent(head)
		var details := _button("chevron-right", "Request details", _show_request_details.bind(slot), not busy)
		details.name = "RequestDetails_" + slot
		details.text = ""
		details.reparent(head)
		_text(L10n.text(str(spec.name)), 14, GameUi.INK).name = "RequestTitle_" + slot
		_text(JourneyRequests.status(state(), slot), 12, GameUi.GREEN).name = "RequestStatus_" + slot
		_request_items(JourneyRequests.requirements(state(), slot), false, true)
		_text(L10n.format_text("Reward: %d coins", int(spec.coins)) + " / " + StreetCommons.progress(state(), str(spec.effect)), 12, GameUi.GREEN)
		var accepted := JourneyRequests.accepted(state(), slot)
		var available := JourneyRequests.available(state(), slot)
		var tracked: bool = JourneyRequests.tracked(state()).get("slot") == slot
		var commands := HBoxContainer.new()
		_body.add_child(commands)
		if not available:
			_text(L10n.text("Share your first meal with the host first." if slot == "bistro" else "Discover more of the neighbourhood first."), 12)
		elif not accepted:
			var accept := _button("check", "Accept and track", _request_command.bind("accept_opportunity", slot, sequence), _can_manage(), true)
			accept.name = "AcceptRequest_" + slot
			accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			accept.reparent(commands)
		else:
			var ready := JourneyRequests.supplies_ready(state(), slot)
			var goal := JourneyRequests.goal(JourneyProgress.goal_state(session), session.server_now(), slot)
			var go := _button("package-check" if ready else str(goal.get("icon", "compass")), "Go to delivery" if ready else str(goal.get("hint", "Go to current goal")), func(): goal_requested.emit(goal), _can_navigate() and not goal.is_empty(), true)
			go.name = "GoToRequest_" + slot
			go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			go.reparent(commands)
		if accepted:
			var track := _button("compass", "Stop tracking request" if tracked else "Track request", _request_command.bind("stop_tracking" if tracked else "track_journey_opportunity", slot, sequence), _can_manage() and available)
			track.name = "BoardTrackRequest_" + slot
			track.theme_type_variation = &"ChoiceSelectedButton" if tracked else &"SecondaryButton"
			track.text = ""
			track.reparent(commands)
			var abandon := _button("x", "Abandon request", _confirm_request.bind("abandon_opportunity", slot), _can_manage() and available)
			abandon.name = "AbandonRequest_" + slot
			abandon.text = ""
			abandon.reparent(commands)
		var replace := _button("skip-forward", "Another request", _confirm_request.bind("decline_opportunity", slot) if accepted else _request_command.bind("decline_opportunity", slot, sequence), _can_manage() and available)
		replace.name = "BoardChangeRequest_" + slot
		replace.text = ""
		replace.reparent(commands)
		if not JourneyRequests.last_completed(state(), slot).is_empty():
			var history := _button("book-open", "Last delivery", _show_request_history.bind(slot), not busy)
			history.name = "LastRequest_" + slot
			history.text = ""
			history.reparent(head)
		_body.add_child(HSeparator.new())

func _request_items(needs: Dictionary, delivered := false, compact := false) -> void:
	var flow: HFlowContainer
	if compact:
		flow = HFlowContainer.new()
		_body.add_child(flow)
	for id in needs:
		if int(needs[id]) < 1: continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.tooltip_text = ItemCatalog.name_of(str(id))
		row.add_child(GameUi.picture(ItemCatalog.texture(str(id)), 32))
		var text := ItemCatalog.name_of(str(id)) + " x" + str(int(needs[id])) if delivered else L10n.format_text("%s %d/%d", [ItemCatalog.name_of(str(id)), JourneyRequests.quantity(state(), str(id)), int(needs[id])])
		if compact: text = str(JourneyRequests.quantity(state(), str(id))) + "/" + str(int(needs[id]))
		var label := GameUi.label(text, 13)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF if compact else TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		if compact: flow.add_child(row)
		else: _body.add_child(row)

func _confirm_request(operation: String, slot: String, timber_only := false) -> void:
	if busy: return
	request_slot = slot
	request_operation = operation
	request_sequence = int(JourneyRequests.progress(state(), slot).get("sequence", -1))
	request_timber_only = timber_only
	_set_mode("request_confirm")

func _show_request_history(slot: String) -> void:
	if busy: return
	request_slot = slot
	_set_mode("request_history")

func _show_request_details(slot: String) -> void:
	if busy: return
	request_slot = slot
	_set_mode("request_details")

func _request_command(type: String, slot: String, sequence := -1, timber_only := false) -> void:
	if not _can_manage(): return
	var payload := {"slot": slot, "sequence": sequence if sequence >= 0 else int(JourneyRequests.progress(state(), slot).get("sequence", -1))}
	var operation := type
	if timber_only: payload.timber_only = true
	if type in ["track_journey_opportunity", "stop_tracking"]:
		payload.tracking = type == "track_journey_opportunity"
		operation = "track_journey_opportunity"
	var success := {"accept_opportunity": "Request accepted and tracked.", "track_journey_opportunity": "Request tracked.", "stop_tracking": "Request tracking stopped.", "abandon_opportunity": "Request abandoned.", "decline_opportunity": "A different request is ready."}
	var accepted := await command(operation, payload, L10n.text(str(success[type])))
	if not is_inside_tree(): return
	if accepted: mode = "grid"
	elif session.last_error_code == "REQUEST_DONE":
		mode = "grid"
		request_sequence = -1
		request_operation = ""
		request_timber_only = false
		if await _recover_bag(): message.text = L10n.text("The request changed. Review the current offer.")
	refresh()

func _choose_equipment(slot: String) -> void:
	if busy: return
	equipment_slot = slot
	_set_mode("equipment")

func _render_equipment() -> void:
	_text(CharacterModel.slot_name(equipment_slot), 16, GameUi.INK)
	var bag := BagModel.snapshot(state())
	var entries: Array = bag.get("slots", []) + bag.get("overflow", [])
	var matches := entries.filter(func(entry): return equipment_slot in CharacterModel.equipment_slots(str(entry.item_id)))
	if matches.is_empty(): _text(L10n.text("No other equipment for this slot"))
	for entry in matches:
		var label := ItemCatalog.name_of(str(entry.item_id))
		if bag.get("overflow", []).has(entry): label += " / " + L10n.text("Overflow items")
		var choice := _button("", label, select_stack.bind(str(entry.id)))
		choice.name = "ChooseEquipment_" + str(entry.id)
		choice.icon = ItemCatalog.texture(str(entry.item_id))
		var modifier := CharacterModel.modifier_label(str(entry.item_id))
		if not modifier.is_empty(): _text(modifier, 12)
	_button("hammer", "Make equipment", func(): goal_requested.emit({"place": "nursery", "target": "workbench"}), _can_navigate())

func select_stack(id: String) -> void:
	if busy: return
	selected_stack = id
	mode = "details"
	search.release_focus()
	if page != "bag": body_scroll.scroll_vertical = 0
	message.text = ""
	refresh()

func _render_details(entry: Dictionary) -> void:
	var id := str(entry.item_id)
	var spec := ItemCatalog.definition(id)
	var bag := BagModel.snapshot(state())
	var overflow: bool = bag.get("overflow", []).any(func(stack): return stack.id == entry.id)
	var equipped_slot := CharacterModel.equipped_slot(state(), str(entry.id))
	var wearing := not equipped_slot.is_empty()
	var equipment := CharacterModel.equipment(id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(GameUi.picture(ItemCatalog.texture(id), 54))
	var name_column := VBoxContainer.new()
	name_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_column)
	var title := GameUi.label(ItemCatalog.name_of(id), 17)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_column.add_child(title)
	name_column.add_child(GameUi.label(ItemCatalog.category_name(str(spec.get("category", ""))), 12, GameUi.MUTED))
	_body.add_child(head)
	_text(L10n.format_text("Quantity %d / %d per stack", [int(entry.quantity), int(spec.get("max_stack", 1))]))
	_text(L10n.text(str(spec.get("description", ""))))
	var attributes := FishingModel.tier_name(id) if spec.get("category") == "fish" else ItemCatalog.quality_name(str(entry.get("quality", "normal")))
	if entry.has("seed_lot"): attributes += " / " + L10n.text("Gift seeds" if entry.seed_lot == "bound" else "Purchased seeds")
	if wearing: attributes += " / " + L10n.text("Equipped")
	if overflow: attributes += " / " + L10n.text("Overflow items")
	_text(attributes, 12)
	if entry.has("instance_id"): _text(L10n.format_text("Equipment no. %s", str(entry.instance_id).trim_prefix("item_")), 12)
	for property in ItemCatalog.gameplay_properties(state(), id): _text(str(property), 12)
	var reserved := BagModel.reserved(state(), entry)
	if reserved > 0: _text(L10n.format_text("%d reserved for construction", reserved), 12, GameUi.CORAL)
	var properties: Dictionary = spec.get("properties", {}).duplicate()
	properties.merge(entry.get("attributes", {}), true)
	for key in properties: _text(ItemCatalog.property_name(str(key)) + ": " + ItemCatalog.property_value(properties[key]), 13)
	if not equipment.is_empty():
		_text(CharacterModel.slot_name(str(equipment.slot)), 13, GameUi.INK)
		for stat in CharacterModel.STATS:
			var current := CharacterModel.current(state(), stat)
			var replacement := CharacterModel.compare(state(), id, stat, equipment_slot)
			if current != replacement:
				_text(L10n.format_text("%s: %s > %s", [CharacterModel.stat_name(stat), ItemCatalog.property_value(current), ItemCatalog.property_value(replacement)]), 13, GameUi.GREEN if replacement > current else GameUi.CORAL)
		if equipment.get("slot") == "main_hand" and not wearing:
			var old := CharacterModel.equipped(state(), "main_hand")
			for stat in CharacterModel.HAND_STATS:
				var before = CharacterModel.main_hand_stats(state()).get(stat, 0)
				_text(L10n.format_text("%s: %s > %s", [ItemCatalog.property_name(stat), ItemCatalog.property_value(before), ItemCatalog.property_value(properties.get(stat, 0))]), 13)
	var meal := CharacterModel.consumable(id)
	if not meal.is_empty():
		_text(CharacterModel.effect_label(id), 13, GameUi.GREEN)
		_text(L10n.format_text("Restores %d HP", int(meal.get("heal", 0))), 13, GameUi.GREEN)
		_text(CharacterModel.stat_description(str(meal.stat)), 12)
		var effect := CharacterModel.active_buff(state(), id)
		if not effect.is_empty(): _text(L10n.format_text("Active: %d uses left", int(effect.remaining_uses)), 13, GameUi.GREEN)
	var uses: Array[String] = []
	for use in spec.get("uses", []): uses.append(L10n.text(str(use)))
	if not uses.is_empty(): _text(L10n.text("Uses") + ": " + " / ".join(uses), 12)
	_body.add_child(HSeparator.new())
	if mode == "sell_fish":
		var price := int(FishingModel.fish(id).price)
		quantity = SpinBox.new()
		quantity.name = "FishSellQuantity"
		quantity.min_value = 1
		quantity.max_value = int(entry.quantity)
		quantity.value = 1
		quantity.step = 1
		quantity.rounded = true
		quantity.custom_minimum_size.y = 44
		quantity.editable = not busy
		_style_input(quantity.get_line_edit())
		_body.add_child(quantity)
		var total := _text(L10n.format_text("Sell %d fish · +%d coins", [1, price]), 16, GameUi.GREEN)
		quantity.value_changed.connect(func(value): total.text = L10n.format_text("Sell %d fish · +%d coins", [int(value), int(value) * price]))
		var sell := _button("coins", "Confirm sale", func(): _manage("sell_fish", {"stack_id": selected_stack, "quantity": int(quantity.value)}, "Fish sold"), _can_manage(), true)
		sell.name = "ConfirmFishSale"
		return
	if mode == "split" or mode == "discard":
		var maximum := int(entry.quantity) - 1 if mode == "split" else BagModel.discardable_quantity(state(), entry)
		_text(L10n.text("Split quantity" if mode == "split" else "Discard quantity"), 15)
		quantity = SpinBox.new()
		quantity.name = "BagQuantity"
		quantity.min_value = 1
		quantity.max_value = maxi(1, maximum)
		quantity.value = mini(maxi(1, floori(float(entry.quantity) * 0.5)), maximum)
		quantity.step = 1
		quantity.rounded = true
		quantity.custom_minimum_size.y = 44
		quantity.editable = not busy
		_style_input(quantity.get_line_edit())
		_body.add_child(quantity)
		if mode == "discard": _text(L10n.text("Discarded items cannot be recovered."), 12, GameUi.CORAL)
		var operation := mode
		var confirm := _button("scissors" if mode == "split" else "trash-2", "Split stack" if mode == "split" else "Confirm discard", func():
			var amount := int(quantity.value)
			_manage("split_bag_stack" if operation == "split" else "discard_bag_stack", {"stack_id": selected_stack, "quantity": amount}, "Stack split" if operation == "split" else "Items discarded"), _can_manage() and maximum > 0, true)
		confirm.name = "ConfirmSplit" if mode == "split" else "ConfirmDiscard"
		return
	if mode == "merge":
		_text(L10n.text("Merge into a stack"), 15)
		for destination in BagModel.merge_targets(state(), entry):
			var dest_id := str(destination.id)
			var label := ItemCatalog.name_of(str(destination.item_id)) + "  " + str(int(destination.quantity)) + "/" + str(int(spec.get("max_stack", 1)))
			var button := _button("package-check", label, func(): _manage("merge_bag_stacks", {"source_id": selected_stack, "target_id": dest_id}, "Stacks merged"), _can_manage(), true)
			button.name = "MergeInto_" + dest_id
		return
	if spec.get("category") == "fish":
		var sell := _button("coins", "Sell fish", func(): _set_mode("sell_fish"), _can_manage(), true)
		sell.name = "SellFish"
	var management_index := _body.get_child_count()
	if not meal.is_empty():
		var eat := _button("utensils", "Eat one" if CharacterModel.can_eat(state(), id) else "Effect active", func(): _manage("use_bag_item", {"stack_id": selected_stack}, "Meal effect applied"), _can_manage() and CharacterModel.canonical(state()) and CharacterModel.can_eat(state(), id), true)
		eat.name = "EatItem"
	if overflow:
		var claim := _button("backpack", "Move into bag", func(): _manage("claim_bag_overflow", {"stack_id": selected_stack}, "Item moved into bag"), _can_manage(), true)
		claim.name = "ClaimOverflow"
	elif not equipment.is_empty():
		if wearing:
			var remove := _button("minus", "Unequip", func(): _manage("unequip_bag_item", {"slot": equipped_slot}, "Equipment unequipped"), _can_manage(), true)
			remove.name = "UnequipTool"
		else:
			for slot in CharacterModel.equipment_slots(id):
				var label := L10n.format_text("Equip to %s", CharacterModel.slot_name(slot))
				var wear := _button("check", label, func(): _manage("equip_bag_item", {"stack_id": selected_stack, "slot": slot}, "Equipment equipped"), _can_manage(), true)
				wear.name = "EquipTool" if CharacterModel.equipment_slots(id).size() == 1 else "EquipTo_" + slot

	else:
		for goal in BagModel.routes(state(), id):
			var allowed: bool = goal.place == "farm" or PlaceCatalog.available(str(goal.place), state())
			var use := _button(str(goal.icon), str(goal.label), func(): goal_requested.emit(goal), _can_navigate() and allowed)
			use.name = "BagUse_" + str(goal.place) + "_" + str(goal.target)
	if not wearing:
		var manage_row := HBoxContainer.new()
		_body.add_child(manage_row)
		if not overflow and int(entry.quantity) > 1 and int(spec.get("max_stack", 1)) > 1:
			var split := _button("scissors", "Split stack", func(): _set_mode("split"), _can_manage() and bag.get("slots", []).size() < int(bag.capacity))
			split.name = "SplitStack"
			split.text = ""
			split.reparent(manage_row)
		if not overflow and not BagModel.merge_targets(state(), entry).is_empty():
			var merge := _button("package-check", "Merge stacks", func(): _set_mode("merge"), _can_manage())
			merge.name = "MergeStacks"
			merge.text = ""
			merge.reparent(manage_row)
		if bool(spec.get("discardable", false)):
			var discard := _button("trash-2", "Discard", func(): _set_mode("discard"), _can_manage() and BagModel.discardable_quantity(state(), entry) > 0)
			discard.name = "DiscardStack"
			discard.text = ""
			discard.reparent(manage_row)
		_body.move_child(manage_row, management_index)

func _set_mode(value: String) -> void:
	if busy: return
	mode = value
	body_scroll.scroll_vertical = 0
	refresh()

func consume_back() -> bool:
	if busy: return true
	if mode in ["split", "merge", "discard", "sell_fish", "inspect"]:
		_set_mode("details")
		return true
	if mode != "grid":
		selected_stack = ""
		_set_mode("grid")
		return true
	if showing_overflow:
		showing_overflow = false
		refresh()
		return true
	return false

func _can_manage() -> bool:
	return _can_navigate() and BagModel.canonical(state())

func _can_navigate() -> bool:
	return not busy and not _needs_refresh and session != null and not session.offline and not session.has_unconfirmed_command()

func _manage(type: String, payload: Dictionary, success: String) -> void:
	if not _can_manage(): return
	payload.sequence = int(state().bag.sequence)
	var accepted := await command(type, payload, L10n.text(success))
	if not is_inside_tree(): return
	if accepted:
		mode = "details" if not selected_stack.is_empty() and not BagModel.stack(state(), selected_stack).is_empty() else "grid"
	elif session.last_error_code == "BAG_CHANGED":
		_needs_refresh = true
		if await _recover_bag():
			mode = "details" if not BagModel.stack(state(), selected_stack).is_empty() else "grid"
			message.text = bag_error("BAG_CHANGED")
	else:
		message.text = bag_error(session.last_error_code)
	refresh()

func _recover_bag() -> bool:
	if busy or session == null: return false
	busy = true
	refresh()
	var accepted := await session.refresh()
	busy = false
	if not is_inside_tree(): return accepted
	_needs_refresh = not accepted
	message.text = L10n.text("Bag refreshed") if accepted else bag_error(session.last_error_code)
	refresh()
	return accepted

static func bag_error(code: String) -> String:
	match code:
		"BAG_FULL": return L10n.text("Your bag is full. Merge stacks, use items or free a slot.")
		"BAG_CHANGED": return L10n.text("Your bag changed. Select the item again.")
		"INVALID_BAG_ACTION": return L10n.text("This item cannot be moved or used that way.")
		"EFFECT_ACTIVE": return L10n.text("This meal effect is still active. No item was consumed.")
		"EQUIPMENT_OWNED": return L10n.text("You already own this equipment.")
	return SessionPanel.error_text(code)

func _text(value: String, font_size := 13, color := GameUi.MUTED) -> Label:
	var label := GameUi.label(value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)
	return label

func _style_input(input: LineEdit) -> void:
	input.add_theme_stylebox_override("normal", GameUi.surface(GameUi.PAPER, 10, 6))
	input.add_theme_stylebox_override("read_only", GameUi.surface(GameUi.MINT, 10, 6))
	var focus := GameUi.surface(Color.TRANSPARENT, 10, 6)
	focus.border_color = GameUi.GREEN
	focus.set_border_width_all(2)
	input.add_theme_stylebox_override("focus", focus)
	input.add_theme_color_override("font_color", GameUi.INK)
	input.add_theme_color_override("font_uneditable_color", GameUi.MUTED)
	input.add_theme_color_override("font_placeholder_color", GameUi.MUTED)
	input.add_theme_color_override("caret_color", GameUi.INK)
	input.add_theme_color_override("selection_color", GameUi.MINT)
	input.add_theme_color_override("font_selected_color", GameUi.INK)

func _button(symbol: String, text: String, callback: Callable, enabled := true, accent := false) -> Button:
	var button := GameUi.button(symbol, L10n.text(text), L10n.text(text), accent)
	button.disabled = not enabled or busy
	button.clip_text = true
	button.pressed.connect(func():
		if not button.disabled: callback.call())
	_body.add_child(button)
	return button
