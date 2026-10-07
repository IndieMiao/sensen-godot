class_name UiKitGallerySections
## Gallery registry (SGODOT-211 / 212). Add one entry per component:
##   {id = "object_header", title = "ObjectHeader", figma = "ObjectHeader 483:196", build = Callable}
## `build` returns a Control at most 328 px wide showing every state of the component.
## Keep `id` stable: layout snapshots (tests/ui_kit/snapshots/<id>.json) and PNG shots key on it.
## Reference Figma by main component name + main node id, never by descendant node ids (WP7-A §1).

static func all() -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{id = "tokens_color", title = "Colour tokens", figma = "Gensen Refactor · Semantic variables", build = _colors},
		{id = "tokens_type", title = "Type ramp", figma = "Text styles Gensen Refactor/* and Gensen/Compact/*", build = _type_ramp},
		{id = "theme_buttons", title = "Button variations", figma = "CommandButton 483:216 · Compact/Command 633:41273", build = _buttons},
		{id = "theme_nav", title = "Navigation, dismiss, close, chips", figma = "NavigationRow 483:217 · Dismiss 483:220 · Close 483:336 · Compact/Filter 633:41280 · Tab 483:322", build = _nav},
		{id = "theme_panels", title = "Panel variations", figma = "Sheet 483:190 · InformationSheet 932:71686 · Toast 483:302 · StateBadge 483:324", build = _panels},
		{id = "style_box", title = "UiStyleBox inset, dashed, shadow", figma = "Compact/Command 633:41273 (34 in 44) · Compact/QuickSlot 633:41279 empty / lifted / drop-target", build = _style_boxes},
		# SGODOT-212 atomic components
		{id = "object_header", title = "UiObjectHeader", figma = "ObjectHeader 483:196", build = _object_header},
		{id = "fact_row", title = "UiFactRow", figma = "Fact 483:222 · Cost 483:225", build = _fact_rows},
		{id = "item_row", title = "UiItemRow", figma = "ItemRow 483:228", build = _item_rows},
		{id = "item_cell_inventory", title = "UiItemCell · inventory", figma = "Compact/InventoryCell 633:41278 · LOCK-12", build = _cells_inventory},
		{id = "item_cell_quick", title = "UiItemCell · quick", figma = "Compact/QuickSlot 633:41279 · LOCK-04 / 05", build = _cells_quick},
		{id = "item_cell_kitchen", title = "UiItemCell · kitchen", figma = "Compact/Kitchen/Cell 655:58506 · LOCK-20", build = _cells_kitchen},
		{id = "item_cell_gear", title = "UiItemCell · gear", figma = "Compact/GearSlot 663:61299 · LOCK-13", build = _cells_gear},
		{id = "command_button", title = "UiCommandButton", figma = "CommandButton 483:216 · Compact/Command 633:41273 · LOCK-10", build = _commands},
		{id = "nav_buttons", title = "UiNavButton · Dismiss · Close", figma = "NavigationRow 483:217 · Compact/Navigation 633:41276 · Dismiss 483:220 · Close 483:336", build = _navigation},
		{id = "filter_chip", title = "UiFilterChip", figma = "Compact/Filter 633:41280", build = _filter_chips},
		{id = "segment_tab", title = "UiSegmentTab", figma = "Tab 483:322 · Compact/Kitchen/Mode 655:58504 · LOCK-13 / 20", build = _segment_tabs},
		{id = "badge", title = "UiBadge", figma = "StateBadge 483:324", build = _badges},
		# SGODOT-222 world display
		{id = "need_tile", title = "UiNeedTile", figma = "NeedTile 1090:78003 · LOCK-10", build = _need_tiles},
		{id = "need_source", title = "UiNeedSource", figma = "NeedSource 1092:77266 · LOCK-10 / 08", build = _need_sources},
		{id = "hud", title = "UiHud", figma = "HUD 1143:103373 · LOCK-06 (shown at 328/360)", build = _huds},
		{id = "today_panel", title = "UiTodayPanel", figma = "TodayPanel 1145:81715 · TodayRow 1145:81714 · LOCK-06 (328/360)", build = _today_panels},
		{id = "energy_card", title = "UiEnergyCard · card", figma = "Energy 1094:77504 Kind=Card · EnergyTile 1093:77292 · LOCK-09", build = _energy_cards},
		{id = "energy_panel", title = "UiEnergyCard · panel", figma = "Energy 1094:77504 Kind=Panel · LOCK-09", build = _energy_panels},
		{id = "empty_state", title = "UiEmptyState", figma = "EmptyState 1234:87237 Kind=Panel / Row · WP6", build = _empty_states},
	]
	return out

static func _column(gap: float = UiTokens.SPACE_ROW) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", int(gap))
	return v

static func _row(gap: float = UiTokens.SPACE_WITHIN) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override(&"h_separation", int(gap))
	h.add_theme_constant_override(&"v_separation", int(gap))
	return h

static func _colors() -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", int(UiTokens.SPACE_WITHIN))
	grid.add_theme_constant_override(&"v_separation", int(UiTokens.SPACE_WITHIN))
	var consts: Dictionary = (UiTokens as Script).get_script_constant_map()
	# StringName ordering is not alphabetical; sort plain Strings so snapshots stay stable.
	var names := consts.keys().map(func(k): return String(k)).filter(func(k): return k.begins_with("COLOR_"))
	names.sort()
	for k in names:
		var cell := _column(2)
		var sw := Panel.new()
		sw.custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_SLOT_W * 1.4, UiTokens.SIZE_TOUCH * 0.5)
		sw.add_theme_stylebox_override(&"panel", UiStyleBox.make(consts[k], UiTokens.RADIUS_CHIP * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
		cell.add_child(sw)
		# Long keys (status_insufficient_ring) wrap inside the swatch width so the grid stays in the 328 column.
		var name := UiKit.label(String(k).trim_prefix("COLOR_").to_lower().replace("_", " "), UiTokens.STYLE_C9_B, UiTokens.COLOR_SECONDARY)
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name.custom_minimum_size.x = sw.custom_minimum_size.x
		cell.add_child(name)
		grid.add_child(cell)
	return grid

static func _type_ramp() -> Control:
	var v := _column(2)
	var consts: Dictionary = (UiTokens as Script).get_script_constant_map()
	var names := consts.keys().map(func(k): return String(k)).filter(func(k): return k.begins_with("STYLE_"))
	names.sort()
	for k in names:
		var l := UiKit.label("%s · Radish ×24" % consts[k], consts[k])
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(l)
	return v

static func _button(text: String, variation: StringName, disabled := false, toggle := false, pressed := false) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.disabled = disabled
	b.toggle_mode = toggle
	b.button_pressed = pressed
	return b

static func _buttons() -> Control:
	var v := _column()
	for kind in [UiTokens.BUTTON_CMD_PRIMARY, UiTokens.BUTTON_CMD_SECONDARY, UiTokens.BUTTON_CMD_DESTRUCTIVE,
			UiTokens.BUTTON_CMD_DANGER_SECONDARY]:
		var b := _button(String(kind), kind)
		b.custom_minimum_size.y = UiTokens.SIZE_COMMAND
		v.add_child(b)
	# Unavailable (LOCK-10): the reason is the label and the button stays tappable to explain itself.
	var unavailable := _button("Need 6 more Timber", UiTokens.BUTTON_CMD_BLOCKED)
	unavailable.custom_minimum_size.y = UiTokens.SIZE_COMMAND
	v.add_child(unavailable)
	# Truly disabled (e.g. offline): Button.disabled on any kind.
	var disabled := _button("Offline", UiTokens.BUTTON_CMD_PRIMARY, true)
	disabled.custom_minimum_size.y = UiTokens.SIZE_COMMAND
	v.add_child(disabled)
	var row := _row()
	for kind in [UiTokens.BUTTON_CMD_PRIMARY_COMPACT, UiTokens.BUTTON_CMD_SECONDARY_COMPACT, UiTokens.BUTTON_CMD_BLOCKED_COMPACT]:
		var b := _button("Eat", kind)
		UiKit.ensure_hit_area(b)
		row.add_child(b)
	v.add_child(row)
	return v

static func _nav() -> Control:
	var v := _column(0)
	var nav := _button("View details  ›", UiTokens.BUTTON_NAV_ROW)
	nav.alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(nav)
	var dismiss := _button("Not now", UiTokens.BUTTON_DISMISS)
	dismiss.custom_minimum_size.y = UiTokens.SIZE_DISMISS
	v.add_child(dismiss)
	var row := _row()
	var close := _button("", UiTokens.BUTTON_CLOSE_ROUND)
	close.icon = load("res://assets/p0/icons/close.svg")
	close.expand_icon = true
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.custom_minimum_size = Vector2(UiTokens.SIZE_CLOSE, UiTokens.SIZE_CLOSE)
	row.add_child(close)
	row.add_child(_button("Gift ›", UiTokens.BUTTON_NAV_COMPACT))
	var group := ButtonGroup.new()
	for i in 3:
		var chip := _button(["All", "Seeds", "Fish"][i], UiTokens.BUTTON_FILTER_CHIP, false, true, i == 0)
		chip.button_group = group
		chip.custom_minimum_size.y = UiTokens.SIZE_FILTER_TOUCH
		row.add_child(chip)
	v.add_child(row)
	var seg := HBoxContainer.new()
	var seg_group := ButtonGroup.new()
	for i in 2:
		var tab := _button(["Bag", "Gear"][i], UiTokens.BUTTON_SEGMENT_TAB, false, true, i == 0)
		tab.button_group = seg_group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = UiTokens.SIZE_SEGMENT_TAB
		seg.add_child(tab)
	v.add_child(seg)
	return v

static func _panels() -> Control:
	var v := _column()
	for p in [[UiTokens.PANEL_CARD, "Card"], [UiTokens.PANEL_HUD_CHIP, "HudChip  142/200"], [UiTokens.PANEL_INFO_SHEET, "InfoSheet"]]:
		var panel := PanelContainer.new()
		panel.theme_type_variation = p[0]
		panel.add_child(UiKit.label(p[1], UiTokens.STYLE_BODY_B14))
		v.add_child(panel)
	var toast := PanelContainer.new()
	toast.theme_type_variation = UiTokens.PANEL_TOAST_PANEL
	toast.add_child(UiKit.label("Bag full · free a slot first", UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SURFACE_RAISED))
	v.add_child(toast)
	var badge := PanelContainer.new()
	badge.theme_type_variation = UiTokens.PANEL_BADGE
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.custom_minimum_size.y = UiTokens.SIZE_STATE_BADGE_H
	var bl := UiKit.label("Ready", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_PRIMARY)
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	v.add_child(badge)
	return v

static func _style_boxes() -> Control:
	var row := _row(UiTokens.SPACE_ROW)
	var pill := UiStyleBox.make(UiTokens.COLOR_PRIMARY, UiTokens.RADIUS_COMPACT_COMMAND)
	pill.visual_height = UiTokens.SIZE_COMMAND_COMPACT
	row.add_child(_sample(Vector2(UiTokens.SIZE_TOUCH * 1.6, UiTokens.SIZE_TOUCH), pill))
	row.add_child(_sample(Vector2(UiTokens.SIZE_TOUCH * 1.6, UiTokens.SIZE_TOUCH),
		UiStyleBox.make(Color.TRANSPARENT, 0.0, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)))
	var slot := Vector2(UiTokens.SIZE_QUICK_SLOT_W, UiTokens.SIZE_QUICK_SLOT_SURFACE_H)
	var ghost := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CELL, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	ghost.dashed = true
	ghost.dash = UiTokens.DASH_QUICK[0]
	ghost.gap = UiTokens.DASH_QUICK[1]
	row.add_child(_sample(slot, ghost))
	var lifted := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CELL, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_SELECTED)
	lifted.shadow_color = UiTokens.COLOR_LIFT_SHADOW
	lifted.shadow_size = UiTokens.SIZE_LIFT_SHADOW_RADIUS
	lifted.shadow_offset = Vector2(0, UiTokens.SIZE_LIFT_SHADOW_OFFSET_Y)
	row.add_child(_sample(slot, lifted))
	var drop := UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, UiTokens.RADIUS_CELL, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_SELECTED)
	drop.dashed = true
	drop.dash = UiTokens.DASH_DROP_TARGET[0]
	drop.gap = UiTokens.DASH_DROP_TARGET[1]
	row.add_child(_sample(slot, drop))
	return row

static func _sample(min_size: Vector2, box: StyleBox) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = min_size
	p.add_theme_stylebox_override(&"panel", box)
	return p

# ---------------------------------------------------------------- SGODOT-212 atomic components

static func _tex(id: String) -> Texture2D:
	return load("res://assets/p0/icons/%s.svg" % id)

## A sample with its state name underneath, so every shot says which state it shows.
static func _captioned(c: Control, caption: String) -> VBoxContainer:
	var v := _column(UiTokens.SPACE_WITHIN)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(c)
	var l := UiKit.label(caption, UiTokens.STYLE_C9_B, UiTokens.COLOR_SECONDARY)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v

static func _object_header() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	v.add_child(UiObjectHeader.new({title = "Grilled Crucian", quantity = "2", quantity_label = "dishes",
		state = "Good", effect = "Restores 40 Energy."}))
	v.add_child(UiObjectHeader.new({title = "Starter Rod", effect = "Reaches Common and Fine fish."}))
	v.add_child(UiObjectHeader.new({title = "Herb Baked Perch with Lemon", quantity = "12", quantity_label = "dishes"}))
	return v

static func _fact_rows() -> Control:
	var v := _column(0)
	v.add_child(UiFactRow.new("Progress", "2/8"))
	v.add_child(UiFactRow.new("Grows in", "4m 30s"))
	v.add_child(UiFactRow.new("Cost", "120 coins", UiFactRow.Kind.COST))
	return v

static func _item_rows() -> Control:
	var v := _column(0)
	v.add_child(UiItemRow.new({icon = _tex("fish_crucian"), title = "Pond Crucian", state = "Common",
		effect = "A simple pond fish", quantity = "7", quantity_label = "fish"}))
	v.add_child(UiItemRow.new({icon = _tex("bait_worm"), title = "Worm Bait", effect = "Faster bites",
		quantity = "12", quantity_label = "bait"}))
	v.add_child(UiItemRow.new({icon = _tex("crop_herb"), title = "Herb"}))
	return v

static func _cell(density: UiItemCell.Density, fields: Dictionary) -> UiItemCell:
	var c := UiItemCell.new(density)
	for k in fields: c.set(k, fields[k])
	return c

static func _cells_inventory() -> Control:
	var row := _row(UiTokens.SPACE_ROW)
	var D := UiItemCell.Density.INVENTORY
	var S := UiItemCell.State
	row.add_child(_captioned(_cell(D, {icon = _tex("fish_crucian"), quantity = "×3"}), "default"))
	row.add_child(_captioned(_cell(D, {icon = _tex("fish_trout"), quantity = "×1", rarity = 2}), "rarity"))
	row.add_child(_captioned(_cell(D, {icon = _tex("crop_radish"), quantity = "×19", state = S.SELECTED}), "selected"))
	row.add_child(_captioned(_cell(D, {state = S.EMPTY}), "empty"))
	return row

static func _cells_quick() -> Control:
	var row := _row(UiTokens.SPACE_ROW)
	var D := UiItemCell.Density.QUICK
	var S := UiItemCell.State
	var radish := {icon = _tex("seed_radish"), title = "Radish Seeds", quantity = "×24"}
	var samples := [
		["default", {}], ["selected", {state = S.SELECTED}], ["pinned", {pinned = true}],
		["pinned + selected", {pinned = true, state = S.SELECTED}], ["lifted", {pinned = true, state = S.LIFTED}],
		["drop target", {state = S.DROP_TARGET}], ["zero", {pinned = true, state = S.ZERO, quantity = "×0"}],
		["empty", {state = S.EMPTY}],
	]
	for sample in samples:
		var fields: Dictionary = radish.duplicate()
		fields.merge(sample[1], true)
		row.add_child(_captioned(_cell(D, fields), sample[0]))
	row.add_child(_captioned(_cell(D, {icon = _tex("compost"), title = "Compost", quantity = "×6"}), "one-line name"))
	return row

static func _cells_kitchen() -> Control:
	var row := _row(UiTokens.SPACE_ROW)
	var D := UiItemCell.Density.KITCHEN
	var S := UiItemCell.State
	row.add_child(_captioned(_cell(D, {icon = _tex("dish_grilled_crucian")}), "default"))
	row.add_child(_captioned(_cell(D, {icon = _tex("dish_fish_soup"), status = "Tasted"}), "state label"))
	row.add_child(_captioned(_cell(D, {icon = _tex("fish_crucian"), quantity = "×3", rarity = 1}), "quantity"))
	row.add_child(_captioned(_cell(D, {icon = _tex("dish_carp_cakes"), state = S.SELECTED}), "selected"))
	row.add_child(_captioned(_cell(D, {icon = _tex("dish_radish_salad"), marked = true}), "cooked"))
	row.add_child(_captioned(_cell(D, {state = S.EMPTY}), "empty"))
	return row

static func _cells_gear() -> Control:
	var row := _row(UiTokens.SPACE_ROW)
	var D := UiItemCell.Density.GEAR
	var S := UiItemCell.State
	row.add_child(_captioned(_cell(D, {role = "Fishing", icon = _tex("rod_starter"), title = "Starter Rod"}), "default"))
	row.add_child(_captioned(_cell(D, {role = "Farming", icon = _tex("hoe_starter"), title = "Starter Hoe", state = S.SELECTED}), "selected"))
	row.add_child(_captioned(_cell(D, {role = "Ring", state = S.EMPTY}), "empty"))
	return row

static func _commands() -> Control:
	var v := _column()
	var K := UiCommandButton.Kind
	for k in [[K.PRIMARY, "Craft"], [K.SECONDARY, "Store"], [K.DESTRUCTIVE, "Discard"], [K.DANGER_SECONDARY, "Leave"]]:
		v.add_child(UiCommandButton.new(k[1], k[0]))
	var pressed := UiCommandButton.new("Craft · pressed")
	pressed.toggle_mode = true   # gallery only: hold the pressed look for the shot
	pressed.button_pressed = true
	v.add_child(pressed)
	var unavailable := UiCommandButton.new("Craft")
	unavailable.reason = "Need 6 more Timber"
	v.add_child(unavailable)
	var pending := UiCommandButton.new("Craft")
	pending.phase = CommandLifecycle.State.PENDING
	v.add_child(pending)
	var offline := UiCommandButton.new("Offline")
	offline.disabled = true
	v.add_child(offline)
	var row := _row()
	row.add_child(_captioned(UiCommandButton.new("Eat", K.PRIMARY, true), "primary"))
	row.add_child(_captioned(UiCommandButton.new("Sell", K.SECONDARY, true), "secondary"))
	var c_unavailable := UiCommandButton.new("Sell", K.PRIMARY, true)
	c_unavailable.reason = "Sell at home"
	row.add_child(_captioned(c_unavailable, "unavailable"))
	var c_pending := UiCommandButton.new("Buy", K.PRIMARY, true)
	c_pending.phase = CommandLifecycle.State.PENDING
	row.add_child(_captioned(c_pending, "pending"))
	v.add_child(row)
	return v

static func _navigation() -> Control:
	var v := _column(0)
	v.add_child(UiNavButton.new("View details"))
	var pressed := UiNavButton.new("View details · pressed")
	pressed.toggle_mode = true   # gallery only
	pressed.button_pressed = true
	v.add_child(pressed)
	v.add_child(UiDismissButton.new("Not now"))
	var row := _row(UiTokens.SPACE_ROW)
	row.add_child(_captioned(UiNavButton.new("Gift", true), "compact"))
	row.add_child(_captioned(UiCloseButton.new(), "close"))
	var close_pressed := UiCloseButton.new()
	close_pressed.toggle_mode = true   # gallery only
	close_pressed.button_pressed = true
	row.add_child(_captioned(close_pressed, "close · pressed"))
	v.add_child(row)
	return v

static func _filter_chips() -> Control:
	return UiFilterChip.row(PackedStringArray(["All", "Seeds", "Fish", "Produce", "Dishes"]), 0)

static func _segment_tabs() -> Control:
	var v := _column()
	v.add_child(UiSegmentTab.new(["Bag", "Gear"], 0))
	v.add_child(UiSegmentTab.new([{label = "Cookbook", count = "4/48"}, {label = "Experiment"}], 1))
	v.add_child(UiSegmentTab.new(["To do", "Parcels", "Updates"], 1))
	return v

static func _badges() -> Control:
	var row := _row()
	row.add_child(UiBadge.new("Ready"))
	row.add_child(UiBadge.new("Familiar"))
	return row

static func _empty_states() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	v.add_child(UiEmptyState.new("Your bag is empty", _tex("bag")))
	v.add_child(UiEmptyState.new("No seeds yet", _tex("seed_radish"), "Show stall"))
	v.add_child(UiEmptyState.new("No open requests · next in 3h 12m", _tex("board"), "", UiEmptyState.Kind.ROW))
	return v

# ---------------------------------------------------------------- SGODOT-222 world display

## Full-width (360) components drawn at 328/360 so they fit the gallery column.
static func _phone(content: Control, height: float) -> Control:
	var frame := Control.new()
	var k := (360.0 - UiTokens.SPACE_PAGE * 2.0) / 360.0
	frame.custom_minimum_size = Vector2(360.0 * k, height * k)
	var screen := Control.new()
	screen.size = Vector2(360.0, height)
	screen.scale = Vector2(k, k)
	screen.add_child(content)
	frame.add_child(screen)
	return frame

static func _need_tiles() -> Control:
	var v := _column(UiTokens.SPACE_ROW)
	var wood := _tex("wood")
	var S := UiNeedTile.Size
	for size in [S.L, S.M, S.S]:
		v.add_child(UiNeedTile.group([
			_captioned(UiNeedTile.new("Timber", 16, 16, size, wood), "met"),
			_captioned(UiNeedTile.new("Timber", 10, 16, size, wood), "short"),
			_captioned(UiNeedTile.new("Meals", 100, 300, size, _tex("eat"), true), "count"),
		]))
	v.add_child(UiNeedTile.group([
		_captioned(UiNeedTile.new("Coins", 5, 4, S.M, _tex("coin")), "surplus 5/4"),
		_captioned(UiNeedTile.new("Copper Ore", 0, 6, S.M, _tex("stone")), "short 0"),
		_captioned(UiNeedTile.new("Fish-dex", 12, 20, S.M, _tex("fish_crucian"), true), "collection"),
	]))
	return v

static func _need_sources() -> Control:
	var v := _column()
	v.add_child(UiNeedSource.new("Copper Ore · The mine, floors 1–4"))
	v.add_child(UiNeedSource.new("Radish Seeds · Homestead Stall"))
	return v

static func _hud_sample(state: Dictionary) -> UiHud:
	var h := UiHud.new()
	h.apply(state)
	return h

static func _huds() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 0)
	var home := {city = "Shanghai", space = "Homestead", kind = UiHud.PlaceKind.HOME}
	var samples := [
		{energy = 142, energy_max = 200, regen = "+1 in 2:40", skills = {farming = 0.6, fishing = 0.4}, coins = 230,
			today = "Radishes ready in 1h 12m", place = home},
		{energy = 1, energy_max = 200, next_cost = 2, regen = "+1 in 2:41", skills = {farming = 0.6, fishing = 0.3}, coins = 230,
			unread = 3, buff = {icon = _tex("crop_herb"), remaining = "2h 59m"}, today = "Sow your first plot",
			place = {city = "Shanghai", space = "Farmhouse", kind = UiHud.PlaceKind.HOME}},
		{energy = 0, energy_max = 200, regen = "+1 in 3:59", coins = 12, unread = 12, today = "",
			place = {city = "Tokyo", space = "Arrived", kind = UiHud.PlaceKind.FOREIGN, day_pass = "23h"}},
		{energy = 200, energy_max = 200, regen = "Full", skills = {farming = 1.0, fishing = 1.0}, coins = 1840,
			today = "Pond Catch · 2 Pond Crucian · Stall Board", place = {city = "Shanghai", space = "Willow Pond", kind = UiHud.PlaceKind.HOME}},
		{energy = 214, energy_max = 200, regen = "Bonus +14", coins = 230, today = "Herb Grilled Fish ready at the stove", place = home},
	]
	for s in samples:
		var screen := Control.new()
		screen.custom_minimum_size = Vector2(360, UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H)
		screen.add_child(_hud_sample(s))
		col.add_child(_phone(screen, UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H))
	return col

static func _today_panels() -> Control:
	var col := _column()
	var rows := [
		{icon = _tex("crop_radish"), line = "Radishes ready in 1h 12m", action = "Show"},
		{icon = _tex("seed_radish"), line = "Sow your first plot", tail = "needs 2 Energy · +1 in 2:41", action = "Show", state = "short"},
		{icon = _tex("board"), line = "Pond Catch · 2 Pond Crucian", state = "done"},
	]
	var p := UiTodayPanel.new(rows)
	p.position = Vector2(UiTokens.SIZE_TODAY_PANEL_X, 0)
	col.add_child(_phone(p, 150))
	return col

static func _energy_facts(zero: bool, home: bool) -> Dictionary:
	return {
		have = 0 if zero else 1, max = 200, regen = "+1 in 3:59" if zero else "+1 in 2:41", zero = zero,
		fact = "Recover or do something free" if zero else "Sow 1 plot needs 2 Energy · you have 1",
		wait = "Wait · Full in 13h 20m",
		tiles = [
			{icon = _tex("dish_grilled_fish"), label = "Eat", fact = "3 dishes in bag", guide = "Open bag", go = "bag", on = true},
			{icon = _tex("pot"), label = "Cook", fact = "4 fish in creel" if home else "At home", guide = "Show kitchen", go = "stove", on = home},
			{icon = _tex("dish_fruit_tea"), label = "Tea", fact = "Tea House opens later", guide = "", go = "", on = false},
			{icon = _tex("rest"), label = "Rest", fact = "Available" if home else "At home", guide = "Show bench", go = "home", on = home},
		],
	}

static func _energy_cards() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	v.add_child(_captioned(UiEnergyCard.card(_energy_facts(false, true)), "short"))
	v.add_child(_captioned(UiEnergyCard.card(_energy_facts(true, false)), "empty · away from home"))
	return v

static func _energy_panels() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	var facts := {max = 200, level = "Homestead Lv1", uses = [
		{name = "Meals", have = 100, need = 300, icon = _tex("dish_grilled_fish")},
		{name = "Tea", have = 1, need = 3, icon = _tex("dish_fruit_tea")},
		{name = "Rest", have = 0, need = 1, icon = _tex("rest")},
		{name = "Refunds", have = 3, need = 10, icon = _tex("rod_starter")},
	], blessing = {title = "Newcomer Blessing · 5 days left", detail = "Energy returns 1.5× faster · Meals 300 a day"}}
	var p := UiEnergyCard.panel(facts)
	var holder := MarginContainer.new()
	holder.add_theme_constant_override(&"margin_top", int(UiTokens.SPACE_ROW))
	holder.add_child(p)
	v.add_child(holder)
	return v
