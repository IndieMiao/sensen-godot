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
		{id = "inbox_row", title = "UiInboxRow", figma = "InboxRow 1309:89969 Kind=Item / System · C2-01 · LOCK-14 (SGODOT-234)", build = _inbox_rows},
		{id = "badge", title = "UiBadge", figma = "StateBadge 483:324", build = _badges},
		{id = "empty_state", title = "UiEmptyState", figma = "EmptyState 1234:87237 Kind=Panel / Row · WP6", build = _empty_states},
		# SGODOT-226 cooking results (shared with the catch card, SGODOT-233)
		{id = "quality_badge", title = "UiQualityBadge", figma = "QualityBadge 1178:82154", build = _quality_badges},
		{id = "reward_moment", title = "UiRewardMoment", figma = "RewardMoment 1179:82271 · COOK-4 / COOK-6 / COOK-P0-9", build = _reward_moments},
		{id = "moment_banner", title = "UiMomentBanner", figma = "MomentBanner 1226:104630 · §4.8.3 / §4.8.6 (SGODOT-233)", build = _moment_banners},
		{id = "sys_banner", title = "UiSysBanner", figma = "SysBanner 1187:82581 · SYS-OFFLINE / -2 / SYS-CMD-FAIL (WP6, SGODOT-233)", build = _sys_banners},
		{id = "system_card", title = "UiSystemCard", figma = "SystemCard 1237:87229 Kind=Blocking · SYS-LOADING-FAIL 1243:108638 (SGODOT-233)", build = _system_cards},
		{id = "system_card_trip", title = "UiSystemCard · secondary", figma = "SYS-LOADING-SCENE-FAIL 1780:103778 · q(78) (SGODOT-233)", build = _system_card_trip},
		{id = "wordmark", title = "UiWordmark · UiSpinner", figma = "Wordmark (placeholder) 1187:82582 · Spinner 1237:87185 · SYS-LOADING-2 1243:108614", build = _wordmark_spinner},
		# SGODOT-221 world controls · interaction
		{id = "quick_bar", title = "UiQuickBar (drawn at 328 of 336)", figma = "Compact/QuickSlot 633:41279 · QuickEnd/Bag 907:72112 · BAR-1 / BAR-1-2 · LOCK-04 / 05", build = _quick_bars},
		{id = "pin_menu", title = "UiPinMenu", figma = "PinMenu 1141:80291 · LOCK-05", build = _pin_menus},
		{id = "scene_action", title = "UiSceneAction", figma = "SceneAction 1116:78934 · LOCK-02", build = _scene_actions},
		{id = "action_key", title = "UiActionKey", figma = "ActionKey 1117:78924 · LOCK-02 / 03", build = _action_keys},
		{id = "bar_drop_zone", title = "UiBarDropZone", figma = "BarDropZone 1588:97952 · LOCK-04 / 05 v1.11 (221 b0a83924)", build = _bar_drop_zones},
		{id = "bar_drag", title = "Quick slot drag · UiUndoToast", figma = "QuickSlot State=lifted · Toast Tone=Info 1178:82247 · LOCK-04 v1.11", build = _bar_drags},
		{id = "action_radial", title = "UiActionRadial", figma = "RadialPetal 1122:79385 v2 · RadialReason 1655:101164 · row 50 · LOCK-03 v2", build = _action_radial},
		{id = "action_radial_motion", title = "UiActionRadial · opening", figma = "Motion 1651:100816 · 0 / 80 / 160 / 300 ms", build = _action_radial_motion},
		{id = "status_badge", title = "UiStatusBadge", figma = "StatusBadge 1132:79554 · LOCK-11", build = _status_badges},
		{id = "world_prompts", title = "World prompts", figma = "UiWorldIconButton · UiWorldNameBar · UiNpcNameTag · WorldIconButton 1674:101157 · WorldNameBar 1674:101190 · NpcNameTag 1674:101195 · row 51 · LOCK-07 / 16 v2", build = _world_prompts},
		{id = "entry_card", title = "UiEntryCard", figma = "EntryCard 1468:94344 · LOCK-21 / LOCK-10", build = _entry_cards},
		# SGODOT-222 world display
		{id = "need_tile", title = "UiNeedTile", figma = "NeedTile 1090:78003 · LOCK-10", build = _need_tiles},
		{id = "need_source", title = "UiNeedSource", figma = "NeedSource 1092:77266 · LOCK-10 / 08", build = _need_sources},
		{id = "show_pill", title = "UiShowPill", figma = "Show pill of TodayRow 1145:81714 / NeedSource 1092:77266 · LOCK-08", build = _show_pills},
		{id = "hud", title = "UiHud", figma = "HUD 1143:103373 · LOCK-06 (shown at 328/360)", build = _huds},
		{id = "creel_badge", title = "UiCreelBadge", figma = "CreelBadge 1126:79349 · FISH-1 / FISH-4 · q(83)", build = _creel_badges},
		{id = "today_panel", title = "UiTodayPanel", figma = "TodayPanel 1145:81715 · TodayRow 1145:81714 · LOCK-06 (328/360)", build = _today_panels},
		{id = "energy_card", title = "UiEnergyCard · card", figma = "Energy 1094:77504 Kind=Card · EnergyTile 1093:77292 · LOCK-09", build = _energy_cards},
		{id = "energy_panel", title = "UiEnergyCard · panel", figma = "Energy 1094:77504 Kind=Panel · LOCK-09", build = _energy_panels},
		# SGODOT-225 shared panel parts
		{id = "drawer", title = "UiDrawer", figma = "Sheet 483:190 · bag drawer of BAG-2-2 · LOCK-12 / 15 (328/360)", build = _drawers},
		{id = "inventory_grid", title = "UiInventoryGrid", figma = "Bag layout five-column grid · LOCK-12 / 15", build = _inventory_grids},
		{id = "dialogue_card", title = "UiDialogueCard", figma = "Head of KeeperGreeting 1205:83238 / ResidentDialogue 1213:83392 (336 at 328)", build = _dialogue_cards},
		{id = "bag_header", title = "UiBagHeader", figma = "BagHeader 1225:83885 · LOCK-12 / 13", build = _bag_headers},
		{id = "gear_row", title = "UiGearRow", figma = "Gear candidate rows of BAG-2 · Gear · LOCK-13", build = _gear_rows},
		{id = "profile_parts", title = "Profile parts", figma = "ProfileTopBar 1233:107734 · ProfileMoreMenu 1233:107735 · SkillRing 1251:109246 · LOCK-22 (336 at 328)", build = _profile_parts},
		{id = "request_card", title = "UiRequestCard", figma = "ResidentRequestCard 1211:83296 · LOCK-18 (336 at 328)", build = _request_cards},
		{id = "resident_bar", title = "UiResidentBar", figma = "ResidentDialogue 1213:83392 Row / Stacked · LOCK-18 (336 at 328)", build = _resident_bars},
		{id = "resident_profile", title = "UiResidentProfile", figma = "RES-PIP 482:586 / RES-KAI 482:592 · sheet content (328/360)", build = _resident_profiles},
		{id = "notice_row", title = "UiNoticeRow", figma = "Bag capacity recovery of BAG-5 482:144 (336 at 328)", build = _notice_rows},
		{id = "float_text", title = "UiFloatText", figma = "FloatText 1178:82191 · six tones, Hug / Wrap (static pills)", build = _float_texts},
		# SGODOT-224 panels
		{id = "info_sheet", title = "UiInfoSheet", figma = "Compact/SelectedItem 633:41257 · BAG-1 482:10 · F-07 (SGODOT-207 168a4cc3)", build = _info_sheets},
		{id = "gate_card", title = "Gate card (UiInfoSheet)", figma = "SKILL-2 482:169 · §4.8.7 four things (SGODOT-233)", build = _gate_cards},
		{id = "board_card", title = "UiBoardCard", figma = "BOARD-READY 1498:96193 · Compact/Information row · E-11 (312 wide)", build = _board_cards},
		{id = "board_card_states", title = "UiBoardCard states", figma = "BOARD-SHORT 1498:96574 · BOARD-DONE 1498:96382", build = _board_card_states},
		{id = "keeper_bar", title = "UiKeeperBar", figma = "KeeperBar 1143:102525 Layout=Titled · NPC-2-2 482:118 / NPC-7-P0 1507:97237 · LOCK-16 (336 at 328)", build = _keeper_bars},
		{id = "shop_row", title = "UiShopRow · UiStepper", figma = "Compact/ShopProduct 702:80447 · Compact/Stepper 1245:108953 · FARM-6 482:46 · C1-01", build = _shop_rows},
		# SGODOT-231 workbench
		{id = "blueprint_card", title = "UiBlueprintCard", figma = "BlueprintCard 1434:93844 · B2-06 · LOCK-10 / 29", build = _blueprint_cards},
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
	# Toast R1 tones (1178:82265; SGODOT-233): Success / Info / Error, an Error with its guiding action.
	for t in [[ToastLayer.Severity.SUCCESS, "Floor 2 cleared · Elevator stop", ""],
			[ToastLayer.Severity.INFO, "Room 1 is full · you're in Room 2", ""],
			[ToastLayer.Severity.ERROR, "Creel full · 0 free slots · Sell or cook first", "Open bag"]]:
		var toast := ToastLayer.card(t[0], t[1], t[2])
		toast.custom_minimum_size = Vector2(ToastLayer.WIDTH, UiTokens.SIZE_TOAST_MIN_H)
		toast.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
		["empty", {state = S.EMPTY}], ["ghost", {state = S.GHOST, title = "Seeds", quantity = ""}],
	]
	for sample in samples:
		var fields: Dictionary = radish.duplicate()
		fields.merge(sample[1], true)
		row.add_child(_captioned(_cell(D, fields), sample[0]))
	row.add_child(_captioned(_cell(D, {icon = _tex("compost"), title = "Compost", quantity = "×6"}), "one-line name"))
	for sample in [["new (ring at peak)", {}], ["new + selected", {state = S.SELECTED}]]:
		var fields: Dictionary = {icon = _tex("seed_lettuce"), title = "Lettuce Seeds", quantity = "×10"}
		fields.merge(sample[1], true)
		var c: UiItemCell = _cell(D, fields)
		c.show_new_ring()   # State=new 1663:101150: the 600 ms ring, held at its peak for the shot
		row.add_child(_captioned(c, sample[0]))
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
	var K := UiItemCell.KitchenState
	row.add_child(_captioned(_cell(D, {kitchen_state = K.HIDDEN, families = ["W", "F", "S"]}), "hidden"))
	row.add_child(_captioned(_cell(D, {kitchen_state = K.CLUED, families = ["W", "F", "S"], clues = [_tex("fish_crucian"), null, null]}), "clued"))
	row.add_child(_captioned(_cell(D, {kitchen_state = K.CLUED, families = ["F"], clues = [UiItemCell.family_icon("F")]}), "clued · family"))
	row.add_child(_captioned(_cell(D, {kitchen_state = K.HIDDEN, families = ["W", "O"], might_have = true}), "might have"))
	row.add_child(_captioned(_cell(D, {icon = _tex("dish_fish_soup"), kitchen_state = K.TASTED}), "tasted"))
	row.add_child(_captioned(_cell(D, {icon = _tex("dish_grilled_fish"), kitchen_state = K.MASTERED}), "mastered"))
	row.add_child(_captioned(_cell(D, {kitchen_state = K.LOCKED, families = ["W", "F", "S"], clues = [null, _tex("crop_potato"), null]}), "locked"))
	row.add_child(_captioned(_cell(D, {icon = _tex("fish_crucian"), quantity = "×2", rarity = 1, kitchen_state = K.IN_POT}), "in pot"))
	row.add_child(_captioned(_cell(D, {icon = _tex("fish_crucian"), rarity = 1, kitchen_state = K.IN_POT}), "in pot · last one"))
	row.add_child(_captioned(_cell(D, {icon = _tex("crop_herb"), quantity = "×12", rarity = 1, rack = true}), "rack"))
	row.add_child(_captioned(_cell(D, {icon = _tex("crop_herb"), rarity = 1, rack = true, kitchen_state = K.IN_POT}), "in pot · rack"))
	row.add_child(_captioned(_cell(D, {icon = _tex("fish_koi"), rarity = 3, kitchen_state = K.NOT_FOR_COOKING}), "not for cooking"))
	return row

static func _cells_gear() -> Control:
	var row := _row(UiTokens.SPACE_ROW)
	var D := UiItemCell.Density.GEAR
	var S := UiItemCell.State
	row.add_child(_captioned(_cell(D, {role = "Fishing", icon = _tex("rod_starter"), title = "Starter Rod"}), "default"))
	row.add_child(_captioned(_cell(D, {role = "Farming", icon = _tex("hoe_starter"), title = "Starter Hoe", state = S.SELECTED}), "selected"))
	row.add_child(_captioned(_cell(D, {role = "Mining", icon = _tex("pick_starter"), title = "Starter Pickaxe"}), "two-line name"))
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
	v.add_child(UiSegmentTab.new([{label = "To do", badge = 2}, {label = "Parcels", badge = 3}, {label = "Updates", dot = true}], 1))   # INBOX-PARCELS
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
			_captioned(UiNeedTile.new("Meals", 100, 300, size, _tex("dish_grilled_fish"), true), "count"),
		]))
	v.add_child(UiNeedTile.group([
		_captioned(UiNeedTile.new("Coins", 5, 4, S.M, _tex("coin")), "surplus 5/4"),
		_captioned(UiNeedTile.new("Timber", 0, 6, S.M, _tex("wood")), "short 0"),
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
			{icon = _tex("dish_fruit_tea"), label = "Tea", fact = "0/3 today · 40 coins", guide = "Show on map", go = "outpost:tea", on = true},
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

# ---------------------------------------------------------------- SGODOT-225 shared panel parts

static func _bag_items() -> Array:
	var out := []
	for e in [["seed_radish", 24, 0], ["seed_carrot", 10, 0], ["fish_crucian", 3, 1], ["fish_perch", 1, 2],
			["dish_grilled_fish", 2, 2], ["crop_radish", 12, 0], ["wood", 20, 0], ["stone", 64, 0], ["bait_worm", 7, 0]]:
		out.append({id = e[0], icon = _tex(e[0]), qty = e[1], rarity = e[2], kind = String(e[0]).get_slice("_", 0)})
	return out

static func _sample_grid(sell := false) -> UiInventoryGrid:
	var g := UiInventoryGrid.new()
	g.custom_minimum_size.y = UiTokens.SIZE_INVENTORY_CELL * 2.0 + UiTokens.SPACE_WITHIN
	g.capacity = 25
	g.items = _bag_items()
	if sell:
		g.can_sell = func(it: Dictionary) -> bool: return it.kind in ["crop", "fish"]
		g.sell_mode = true
	g.select("fish_crucian")
	return g

static func _drawers() -> Control:
	var screen := Control.new()
	screen.size = Vector2(360, 546)
	var scene := ColorRect.new()   # the world behind, under the drawer scrim (color/scrimDrawer)
	scene.color = UiKit.alpha(UiTokens.COLOR_SCRIM, UiTokens.OPACITY_SCRIM_DRAWER)
	scene.size = screen.size
	screen.add_child(scene)
	var d := UiDrawer.new(546.0)   # BAG-2-2: the Bag drawer is 546 of 800
	d.animate = false
	d.safe_bottom = UiTokens.SPACE_ROW
	screen.add_child(d)
	# BAG-2-2 rows: the quick bar (the P0 UI puts PR #12's UiQuickBar there; its last cell turns into Close), the
	# BagHeader (Bag | Gear, Sort · Type, capacity bar), the Tabs and the grid.
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override(&"separation", int(UiTokens.SPACE_QUICK_BAR_GAP))
	for f in [{icon = _tex("seed_radish"), title = "Radish Seeds", quantity = "×24", state = UiItemCell.State.SELECTED},
			{icon = _tex("seed_carrot"), title = "Carrot Seeds", quantity = "×10"}, {icon = _tex("compost"), title = "Compost", quantity = "×6"},
			{icon = _tex("seed_radish"), title = "Orchard Feed", quantity = "×2"}, {state = UiItemCell.State.EMPTY}]:
		quick.add_child(_cell(UiItemCell.Density.QUICK, f))
	quick.add_child(_QuickEndClose.new())   # stand-in for Compact/QuickEnd · Close (PR #12's UiQuickBar draws the real one)
	d.body.add_child(quick)
	var gap := Control.new()
	gap.custom_minimum_size.y = UiTokens.SPACE_OVERLAY_BODY
	d.body.add_child(gap)
	var header := UiBagHeader.new(9, 25)
	header.sort_label = "Type"
	d.body.add_child(header)
	d.body.add_child(UiFilterChip.row(PackedStringArray(["All", "Seeds", "Fish", "Produce", "Dishes"]), 0))
	var grid := _sample_grid()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.body.add_child(grid)
	return _phone(screen, 546.0)

static func _inventory_grids() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	v.add_child(_captioned(_sample_grid(), "bag · Crucian selected · dashed empties to capacity 25"))
	v.add_child(_captioned(_sample_grid(true), "sell_mode · this counter takes crops and fish only"))
	return v

## Compact/QuickEnd · Close (52 × 68, the Bag end cell's shape: cross above, label below) for the drawer sample;
## the game draws PR #12's UiQuickBar end cell.
class _QuickEndClose extends PanelContainer:
	func _init() -> void:
		custom_minimum_size = Vector2(52, 68)   # Compact/QuickEnd main
		add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, UiTokens.RADIUS_CELL,
			UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override(&"separation", int(UiTokens.SPACE_QUICK_BAR_GAP))
		add_child(v)
		var x := UiKit.icon(preload("res://assets/ui/kit_icons/close.svg"), UiTokens.SIZE_CLOSE_ICON)
		x.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		x.self_modulate = UiTokens.COLOR_TEXT
		v.add_child(x)
		var l := UiKit.label("Close", UiTokens.STYLE_C10_B)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)

## Bottom cards are 336 wide on the 360 screen (12 at each side); laid out at 336 and drawn at 328/336.
class _At336 extends Container:
	const W := 336.0

	func _k() -> float: return (360.0 - UiTokens.SPACE_PAGE * 2.0) / W

	func _get_minimum_size() -> Vector2:
		if get_child_count() == 0: return Vector2.ZERO
		return Vector2(W, (get_child(0) as Control).get_combined_minimum_size().y) * _k()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN and get_child_count() > 0:
			var c := get_child(0) as Control
			fit_child_in_rect(c, Rect2(Vector2.ZERO, Vector2(W, c.get_combined_minimum_size().y)))
			c.scale = Vector2(_k(), _k())

static func _at_336(c: Control) -> Control:
	var box := _At336.new()
	box.add_child(c)
	return box

static func _dialogue_cards() -> Control:
	# The KeeperGreeting main's own sample (Mei); the greeting itself, with its Trade sub-copy, is 2A.
	var c := UiDialogueCard.new(load("res://assets/ui/kit_images/keeper_mei.jpg"), "Market Keeper · Mei", "",
		"Morning! Row Hoes just came in — sows three plots at once, Farming Lv4. Anything I can get you?")
	c.portrait_size = UiDialogueCard.KEEPER_PORTRAIT
	c.place = "Keeps the stall · Xuhui Market Square"
	c.content.add_child(UiCommandButton.new("Trade · open the stall"))
	c.content.add_child(UiCommandButton.new("What's fresh today?", UiCommandButton.Kind.SECONDARY))
	c.content.add_child(UiDismissButton.new("Just passing by"))
	return _captioned(_at_336(c), "keeper layout: Role · Name, place line, no profile link")

static func _resident_bars() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	var pip := {portrait = load("res://assets/p0/art/pip-portrait.jpg"), name = "Pip", role = "Courier Kid", stage = "Acquainted",
		have = 28, need = 45, next = "Familiar", line = "Could you catch me a fish? Any kind is fine.", meal = true, lesson = true}
	v.add_child(_captioned(_at_336(UiResidentBar.new(pip)), "Choices=Row · Today’s meal and Recipe lesson available"))
	var busy := pip.duplicate()
	busy.merge({gift_reason = "Gift already given today", meal = false, lesson = false}, true)
	v.add_child(_captioned(_at_336(UiResidentBar.new(busy)), "Choices=Stacked · Gift unavailable with its reason (NPC-5 layout)"))
	return v

static func _bag_headers() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	v.add_child(_captioned(UiBagHeader.new(19, 25), "Bag side · Sort · Type · capacity bar"))
	v.add_child(_captioned(UiBagHeader.new(23, 25), "92 % full · amber bar"))
	v.add_child(_captioned(UiBagHeader.new(19, 25, UiBagHeader.Pane.GEAR), "Gear side · no Sort, no bar"))
	var gift := UiBagHeader.new(19, 25)
	gift.show_tabs = false
	v.add_child(_captioned(gift, "gift drawer · count only"))
	return v

static func _gear_rows() -> Control:
	var v := _column(0)
	var rod := _tex("rod_starter")
	v.add_child(UiGearRow.equipped_badge())
	v.add_child(UiGearRow.new({icon = rod, title = "Starter Rod", state = &"equipped", effect = "Lands up to Fine fish · Bite window 2.2 s"}))
	v.add_child(UiGearRow.new({icon = _tex("rod_reed"), title = "Reed Rod", state = &"owned", effect = "Lands up to Rare fish · Bite window 2.6 s",
		action = {id = &"equip", label = "Equip", kind = &"primary"}}))
	# A locked candidate: P0 lists no Carbon Rod (no source); from P1 it reads like this (李白 q(46)).
	v.add_child(UiGearRow.new({icon = _tex("rod"), title = "Carbon Rod", state = &"Fishing Lv6 · 350 coins at the Tackle Shop", effect = "Lands up to Legendary fish"}))
	var note := UiKit.label("locked · P1 only (BAG-2 lists Starter and Reed in P0)", UiTokens.STYLE_C9_B, UiTokens.COLOR_SECONDARY)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	return v

static func _profile_parts() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	v.add_child(_captioned(_at_336(UiProfileTopBar.new(UiProfileTopBar.Kind.SELF, "Profile")), "Kind=Self · back, Profile, gear (hidden in P0)"))
	v.add_child(_captioned(_at_336(UiProfileTopBar.new(UiProfileTopBar.Kind.OTHER, "Ann")), "Kind=Other · ··· opens the more menu"))
	var menus := _row(UiTokens.SPACE_ROW)
	menus.add_child(_captioned(UiProfileMoreMenu.new(&"close_friend"), "close friend (P2)"))
	menus.add_child(_captioned(UiProfileMoreMenu.new(&"blocked"), "blocked (P2)"))
	v.add_child(menus)
	var skills := HBoxContainer.new()
	skills.add_theme_constant_override(&"separation", 8)
	skills.add_child(UiSkillCard.new("Farming", 1, 0.6, _tex("hoe")))
	skills.add_child(UiSkillCard.new("Fishing", 2, 0.2, _tex("rod")))
	skills.add_child(UiSkillCard.new("Cooking", 2, 0.1, _tex("pot")))
	v.add_child(_captioned(_at_336(skills), "SkillRing · ring floored to 10 %"))
	var farm := UiFarmCard.new("Farmer's Homestead", "Level 1", "Radishes ready 3h 32m", load("res://assets/p0/art/homestead-thumb.jpg"))
	v.add_child(_captioned(_at_336(farm), "farm overview"))
	return v

static func _request_cards() -> Control:
	var d := {portrait = load("res://assets/p0/art/pip-portrait.jpg"), title = "Pip's request", who = "Pip · Courier Kid · personal request",
		line = "Could you catch me a fish? Any kind is fine.", needs = [{name = "Common fish", have = 0, need = 1, icon = _tex("fish_crucian")}],
		reward = "+5 Friendship · 20 coins", deliver_to = "Pip · Travel Post"}
	return _captioned(_at_336(UiRequestCard.new(d)), "open · Accept")
static func _show_pills() -> Control:
	var row := _row(UiTokens.SPACE_SECTION)
	row.add_child(_captioned(UiShowPill.new("Show", UiShowPill.Kind.TODAY), "TODAY · 28 high"))
	row.add_child(_captioned(UiShowPill.new("Show on map", UiShowPill.Kind.TODAY), "TODAY · elsewhere"))
	row.add_child(_captioned(UiShowPill.new("Show ›", UiShowPill.Kind.SOURCE), "SOURCE · 31 high"))
	var note := UiKit.label("Drawn at the main's size; touches reach 44 × 44 around it (_has_point).", UiTokens.STYLE_C9_B, UiTokens.COLOR_SECONDARY)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var v := _column(UiTokens.SPACE_WITHIN)
	v.add_child(row)
	v.add_child(note)
	return v

## Normal / Low (one slot left) / Full (no slot: warning tint and the alert dot), as FISH-1 / FISH-4 hang them.
static func _creel_badges() -> Control:
	var v := _column()
	for spec in [[UiCreelBadge.State.NORMAL, "Creel 7 · 6 free", "Normal"], [UiCreelBadge.State.LOW, "Creel 9 · 1 free", "Low"],
			[UiCreelBadge.State.FULL, "Creel 12 · 0 free", "Full"]]:
		var b := UiCreelBadge.new(_tex("fish"))
		b.text = str(spec[1])
		b.state = spec[0]
		v.add_child(_captioned(b, str(spec[2])))
	return v

static func _resident_profiles() -> Control:
	var face := AtlasTexture.new()   # the face square of Pip's portrait, as the P0 UI crops it (P0Ui.FACE_CROPS)
	face.atlas = load("res://assets/p0/art/pip-portrait.jpg")
	face.region = Rect2(30, 163, 232, 232)
	var d := {face = face, name = "Pip", role = "Courier Kid", stage = "Familiar",
		friendship = "52/90", likes = "Dessert", likes_icon = _tex("dish_carrot_cake")}
	var page := UiResidentProfile.new(d)
	page.custom_minimum_size = Vector2(296, 411)   # Profile content + fixed decision area of the 443 sheet
	var sheet := PanelContainer.new()
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, 0.0)
	box.corner_radius = Vector4(UiTokens.RADIUS_SHEET, UiTokens.RADIUS_SHEET, 0.0, 0.0)
	sheet.add_theme_stylebox_override(&"panel", box.with_margins(UiTokens.SPACE_PAGE, UiTokens.SPACE_PAGE, UiTokens.SPACE_PAGE, UiTokens.SPACE_PAGE))
	sheet.add_child(page)
	return _captioned(sheet, "Details hidden in P0 (no page behind it) · Back returns to the bar")

static func _notice_rows() -> Control:
	return _captioned(_at_336(UiNoticeRow.new("Bag full · +5 slots at Homestead Lv3")), "Bag full · navigation only (LOCK-08)")

static func _float_texts() -> Control:
	var v := _column(UiTokens.SPACE_ROW)
	var tones := [["+5 XP", UiFloatText.Tone.XP, null], ["+25 Energy", UiFloatText.Tone.ENERGY_GAIN, null],
		["−2 Energy", UiFloatText.Tone.ENERGY_COST, null], ["+12 coins", UiFloatText.Tone.COINS, null],
		["+2 · first chat today", UiFloatText.Tone.AFFINITY, null], ["+6 Timber", UiFloatText.Tone.ITEM, _tex("wood")]]
	for t in tones:
		var row := HBoxContainer.new()   # hugs the pill
		row.add_child(UiFloatText.pill(t[0], t[1], t[2]))
		v.add_child(row)
	var scene := PanelContainer.new()   # a scene-dark ground so the 82 % cream backing shows
	scene.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_BORDER, UiTokens.RADIUS_CARD)
		.with_margins(UiTokens.SPACE_ROW, UiTokens.SPACE_ROW, UiTokens.SPACE_ROW, UiTokens.SPACE_ROW))
	scene.add_child(v)
	return _captioned(scene, "static look (×1.0) · play() pops, rises 48 and fades over 1100 ms")

## Specs as P0ItemInfo returns them for the F-07 states the card has to draw.
static func _info_sheets() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	var specs := [
		["bag · dish", {title = "Grilled Crucian", icon = _tex("dish_grilled_crucian"), quantity = 3, info = true, rarity_text = "Common", quality = 1,
			facts = ["+20 Energy"], buttons = [{id = &"gift", label = "Gift ›", kind = &"nav"}, {id = &"eat", label = "Eat · +20 Energy", kind = &"primary"}],
			lock = {shown = true, locked = false}}],
		["counter sell · quota short", {title = "Radish", icon = _tex("crop_radish"), quantity = 12, info = true, rarity_text = "Common",
			facts = ["12 · Harvested at home", "4 each"], buttons = [{id = &"sell", label = "Sell", kind = &"secondary"},
			{id = &"sell_all", label = "Sell 5 · 20 coins", kind = &"primary"}], lock = {shown = true, locked = false}}],
		["locked stack", {title = "Radish", icon = _tex("crop_radish"), quantity = 12, info = true, badge = &"locked",
			facts = ["5 each"], buttons = [{id = &"locked", label = "Locked", kind = &"unavailable"}, {id = &"unlock", label = "Unlock", kind = &"secondary"}],
			lock = {shown = true, locked = true}}],
		["bag · seed away from home", {title = "Radish Seeds", icon = _tex("seed_radish"), quantity = 20, info = true, badge = &"pinned",
			facts = ["2 Energy per plot · Ready in 4h 0m"], buttons = [{id = &"pin", label = "Unpin", kind = &"secondary"},
			{id = &"store", label = "At home only", kind = &"unavailable"}], lock = {shown = true, locked = false}}],
	]
	for pair in specs:
		var sheet := UiInfoSheet.new()
		var spec: Dictionary = pair[1]
		sheet.rules = func(id, ctx, o): return spec
		sheet.custom_minimum_size.x = 328   # the gallery column (the main is 336 inside the 360 drawer)
		sheet.open("sample", &"bag")
		v.add_child(_captioned(sheet, pair[0]))
	return v

## The four-things gate card (SKILL-2 482:169, §4.8.7; SGODOT-233): an InfoSheet with the lead line, a NeedTile with
## how far beside it, the level-up gift row and one guiding button (none for Fishing).
static func _gate_cards() -> Control:
	var v := _column()
	var specs := [
		["gate card · seed (SKILL-2)", {title = "Carrot Seeds", icon = _tex("seed_carrot"), badge = &"locked", rarity_text = "Locked",
			lead = "Farming Lv2 unlocks Carrot and Herb",
			need = {name = "Farming XP", have = 32, need = 50, icon = _tex("hoe"), note = "18 XP to go · harvest 9 radishes"},
			info_row = {title = "Carrot Seeds", qty = "×5", lines = ["Level-up gift", "At Lv2"]},
			buttons = [{id = &"guide", label = "Show my plots", kind = &"nav", chevron = false}]}],
		["gate card · Fish-dex silhouette, rod", {title = "Golden Koi", icon = _tex("fish_koi"), badge = &"locked", rarity_text = "Rare · Locked",
			lead = "Reed Rod lands up to Rare fish",
			need = {name = "Coins", have = 40, need = 80, icon = _tex("coin"), note = "80 coins at Tackle Shop"}}],
	]
	for pair in specs:
		var sheet := UiInfoSheet.new()
		var spec: Dictionary = pair[1]
		sheet.rules = func(id, ctx, o): return spec
		sheet.custom_minimum_size.x = 328
		sheet.open("sample", &"gate")
		v.add_child(_captioned(sheet, pair[0]))
	return v

## The Market Board page as BOARD-READY draws it: the day's facts, a request ready to hand in, an open one taking
## three crops (short ones in amber on the tiles).
static func _board_cards() -> Control:
	var page := _column(8)
	page.custom_minimum_size.x = 312
	page.add_child(UiBoardCard.fact_row("Requests today", "4 of 6"))
	page.add_child(UiBoardCard.fact_row("Next request", "3h 58m"))
	page.add_child(_board_card({id = "m1", title = "Dusk Haul", info = true, status = "Ready to deliver", facts = ["4 Fine fish · any kind"],
		reward = "36 coins", needs = [{id = "fish_crucian", name = "Fine fish", have = 4, need = 4, icon = _tex("fish_crucian")}], command = "Deliver"}))
	page.add_child(_board_card({id = "m2", title = "Market Basket", info = true, status = "Open", facts = ["3 crops · 6 each"],
		reward = "140 coins", needs = [{id = "crop_radish", name = "Radish", have = 6, need = 6, icon = _tex("crop_radish")},
			{id = "crop_carrot", name = "Carrot", have = 4, need = 6, icon = _tex("crop_carrot")},
			{id = "crop_potato", name = "Potato", have = 0, need = 6, icon = _tex("crop_potato")}], command = "Track"}))
	return _captioned(page, "page facts · Ready · Open")

## BOARD-SHORT: tracked and short, the gap on the button; BOARD-DONE: delivered, Done with its Reward, no button.
static func _board_card_states() -> Control:
	var page := _column(8)
	page.custom_minimum_size.x = 312
	page.add_child(_board_card({id = "m1", title = "Dusk Haul", info = true, status = "Tracked", facts = ["4 Fine fish · any kind"],
		reward = "36 coins", needs = [{id = "fish_crucian", name = "Fine fish", have = 3, need = 4, icon = _tex("fish_crucian")}],
		command = "Deliver", reason = "Need 1 more Fine fish"}))
	page.add_child(_board_card({id = "m1", title = "Dusk Haul", info = false, status = "Done", facts = ["4 Fine fish · any kind"],
		reward = "36 coins", done = true}))
	return _captioned(page, "Tracked · short · Done")

static func _board_card(d: Dictionary) -> UiBoardCard:
	var c := UiBoardCard.new()
	c.show_request(d)
	return c

## Counter buy rows as FARM-6 draws them: available (stepper + Buy), more than one, sold out, gated, a one-off rod.
static func _keeper_bars() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	var samples := [
		[UiKeeperBar.Role.TACKLE, "finn", "Finn's Tackle", "Xuhui Tackle Shop", "Tackle Keeper · Finn",
			"Reed rods are in. Fishing Lv3 and Fine fish stop slipping the hook.", "", "tackle · the line wraps"],
		[UiKeeperBar.Role.MARKET, "mei", "Mei's Stall", "Xuhui Market Square", "Market Keeper · Mei",
			"Row Hoe's 240 coins. Farming Lv4 to use.", "", "market"],
		[UiKeeperBar.Role.TEA, "ama", "Ama's Tea", "Lotus Tea House", "Tea Host · Ama",
			"Sit a minute. Hot tea, 30 Energy a cup.", "Counts across all tea houses · 3 cups a day", "tea · with a note"],
		[UiKeeperBar.Role.POST, "sigrid", "Sigrid's Desk", "Huangpu Travel Post", "Post Clerk · Sigrid",
			"Coffee's fresh. Pip's been asking for a hand.", "Shares the 3 cups a day with tea", "post · with a note"],
	]
	for s in samples:
		var b := UiKeeperBar.new(s[0])
		b.portrait = load("res://assets/p0/art/keepers/%s_head.jpg" % s[1])
		b.title = s[2]
		b.place = s[3]
		b.keeper = s[4]
		b.line = s[5]
		b.note = s[6]
		v.add_child(_captioned(_at_336(b), s[7]))
	return v

static func _shop_rows() -> Control:
	var v := _column(0)
	var buy := [{id = &"buy", label = "Buy", kind = &"secondary", payload = {}}]
	var rows := [
		[{id = "seed_radish", icon = _tex("seed_radish"), title = "Radish Seeds", info = true, facts = ["Ready in 4h", "Bag ×24"],
			price = {text = "4 coins", line = ""}, buttons = buy}, false, 1],
		[{id = "fert_compost", icon = _tex("compost"), title = "Compost", info = true, facts = ["Grows faster", "Bag ×6"],
			price = {text = "4 coins", line = "2 × 2 coins"}, buttons = buy}, false, 2],
		[{id = "bait_worm", icon = _tex("bait_worm"), title = "Worm Bait", info = true, facts = ["Bites come faster", "Stock 0/30 · Bag ×5"],
			price = {text = "2 coins", line = ""}, buttons = [{id = &"buy", label = "Sold out · 9h 12m", kind = &"unavailable", payload = {}}]}, false, 1],
		# STALL-NEW-2 (E-04, SGODOT-233): Gate tone=New, the row's gate line in newInk.
		[{id = "seed_carrot", icon = _tex("seed_carrot"), title = "Carrot Seeds", info = true, facts = ["Ready in 12h", "◆ New for you"],
			gate_tone = &"new", price = {text = "9 coins", line = ""}, buttons = buy}, false, 1],
		[{id = "seed_tomato", icon = _tex("seed_tomato"), title = "Tomato Seeds", info = true, facts = ["Ready in 6h", "210 XP to go"],
			price = {text = "12 coins", line = ""}, buttons = [{id = &"buy", label = "Farming Lv4 needed", kind = &"unavailable", payload = {}}]}, false, 1],
		[{id = "rod_reed", icon = _tex("rod"), title = "Reed Rod", info = true, facts = ["Lands up to Rare fish", "Fishing Lv3"],
			price = {text = "80 coins", line = ""}, buttons = buy}, true, 1],
	]
	for r in rows:
		var row := UiShopRow.new()
		row.custom_minimum_size.x = 328   # the gallery column (336 in the 360 drawer)
		row.show_spec(r[0], r[1], 9)
		if row.stepper: row.stepper.value = r[2]
		v.add_child(row)
	return v

## The real bar is 336 wide (12 px screen margins); the gallery column is 328, so it is drawn scaled.
static func _fit_bar(bar: UiQuickBar, caption: String) -> VBoxContainer:
	var k := 328.0 / UiTokens.SIZE_QUICK_BAR_W
	var host := Control.new()
	host.custom_minimum_size = Vector2(328, (UiTokens.SIZE_QUICK_BAR_H + UiTokens.SIZE_QUICK_SLOT_LIFT) * k)
	bar.haptics = false
	bar.scale = Vector2(k, k)
	bar.position.y = UiTokens.SIZE_QUICK_SLOT_LIFT * k
	host.add_child(bar)
	return _captioned(host, caption)

static func _bar_slots() -> Array:
	return [
		{id = "seed_radish", icon = _tex("seed_radish"), title = "Radish Seeds", quantity = 24, pinned = true},
		{id = "seed_carrot", icon = _tex("seed_carrot"), title = "Carrot Seeds", quantity = 6},
		{id = "compost", icon = _tex("compost"), title = "Compost", quantity = 0, pinned = true},
		{id = "seed_potato", icon = _tex("seed_potato"), title = "Potato Seeds", quantity = 3},
	]

static func _bar_drop_zones() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	var K := UiBarDropZone.Kind
	# Idle: the three looks side by side. Hover: the real pair at its real spacing (x 72 / 168, 96 apart), one
	# zone hovered at a time as under a finger, so the label pills read as they do on screen.
	var rows := [
		[[K.PIN, false, 56.0], [K.UNPIN, false, 164.0], [K.REMOVE, false, 272.0], "idle · Pin · Unpin · Remove"],
		[[K.PIN, true, 72.0], [K.REMOVE, false, 168.0], "hover Pin · Remove idle (x 72 / 168)"],
		[[K.UNPIN, false, 72.0], [K.REMOVE, true, 168.0], "Unpin idle · hover Remove"],
	]
	for spec in rows:
		var row := ColorRect.new()   # over a scene-grey backdrop: on the gallery's surface the zones' own surface vanishes
		row.color = UiKit.alpha(UiTokens.COLOR_TEXT, UiTokens.OPACITY_SCRIM_MODAL)
		row.custom_minimum_size = Vector2(328, 116)
		for z_spec in spec.slice(0, spec.size() - 1):
			var z := UiBarDropZone.new(z_spec[0])
			z.top_level = false   # drawn in the gallery row, not at its screen spot
			z.hover = z_spec[1]
			row.add_child(z)
			z.center = Vector2(z_spec[2], 42)
		v.add_child(_captioned(row, spec[spec.size() - 1]))
	return v

## The drag itself, in its own section so each shot fits the 1280 px gallery screen (不知火舞 on #38).
static func _bar_drags() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	var lifted := _row(UiTokens.SPACE_SECTION)
	lifted.add_child(_captioned(_lifted_slot(false), "drag: 24 above finger"))
	lifted.add_child(_captioned(_lifted_slot(true), "over a zone: 80 %"))
	v.add_child(lifted)
	v.add_child(_captioned(UiUndoToast.new("Radish Seeds off the bar"), "removed: Info toast with Undo (5 s)"))
	return v

## A lifted quick slot placed the way UiQuickBar._move_drag places it over the finger (white dot), optionally over
## a hovered Pin zone (centred on the finger) at the hover scale.
static func _lifted_slot(over_zone: bool) -> Control:
	var frame := ColorRect.new()
	frame.color = UiKit.alpha(UiTokens.COLOR_TEXT, UiTokens.OPACITY_SCRIM_MODAL)
	frame.custom_minimum_size = Vector2(150, 220)
	var finger := Vector2(75, 150)
	if over_zone:
		var z := UiBarDropZone.new(UiBarDropZone.Kind.PIN)
		z.top_level = false
		z.hover = true
		frame.add_child(z)
		z.center = finger
	var cell := UiItemCell.new(UiItemCell.Density.QUICK)
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.icon = _tex("seed_radish")
	cell.title = "Radish Seeds"
	cell.quantity = "×12"
	cell.state = UiItemCell.State.LIFTED
	cell.pivot_offset = cell.custom_minimum_size * 0.5
	frame.add_child(cell)
	cell.position = finger - Vector2(cell.custom_minimum_size.x * 0.5, cell.custom_minimum_size.y + UiQuickBar._RIDE_ABOVE)
	if over_zone: cell.scale = Vector2.ONE * UiQuickBar._HOVER_SCALE
	var dot := Panel.new()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, 7))
	dot.size = Vector2(14, 14)
	dot.position = finger - Vector2(7, 7)
	frame.add_child(dot)
	return frame

static func _quick_bars() -> Control:
	var v := _column()
	var a := UiQuickBar.new()
	a.slots = _bar_slots()
	a.selected = "seed_carrot"
	v.add_child(_fit_bar(a, "selected · pinned · zero (pinned, 0 left) · empty"))
	var g := UiQuickBar.new()
	g.slots = [{id = "seed_lettuce", icon = _tex("seed_lettuce"), title = "Lettuce Seeds", quantity = 0, pinned = true},
		{ghost = true, icon = _tex("seed_radish"), title = "Seeds"}]
	v.add_child(_fit_bar(g, "nothing in stock (pinned 0): first empty slot is the ghost"))
	var b := UiQuickBar.new()
	b.slots = _bar_slots()
	b.capacity_warning = true
	b.cells()[0].state = UiItemCell.State.LIFTED
	b.cells()[3].state = UiItemCell.State.DROP_TARGET
	v.add_child(_fit_bar(b, "lifted (dragging) · drop target · Bag at 90%"))
	var c := UiQuickBar.new()
	c.slots = _bar_slots()
	c.bag_open = true
	v.add_child(_fit_bar(c, "bag drawer open: Close"))
	var d := UiQuickBar.new()
	d.collapsed = true
	v.add_child(_fit_bar(d, "no action chosen: handle + Bag"))
	return v

static func _pin_menus() -> Control:
	var row := _row(UiTokens.SPACE_ROW)
	row.add_child(_captioned(UiPinMenu.new(true), "after pinning"))
	row.add_child(_captioned(UiPinMenu.new(false), "after unpinning"))
	return row

static func _scene_action(verb: String, cost: String, state: UiSceneAction.State, progress := 0.0) -> UiSceneAction:
	var k := UiSceneAction.new()
	k.verb = verb
	k.cost = cost
	k.state = state
	k.hold_progress = progress
	k.set_process(false)   # keep the Pending spinner still for the PNG snapshot
	return k

static func _scene_actions() -> Control:
	var row := _row(UiTokens.SPACE_ROW)
	var S := UiSceneAction.State
	row.add_child(_captioned(_scene_action("Cast", "5 Energy", S.DEFAULT), "default"))
	row.add_child(_captioned(_scene_action("Sow ×1", "Need 2 Energy", S.INSUFFICIENT), "insufficient"))
	row.add_child(_captioned(_scene_action("Growing", "Ready in 2h", S.UNAVAILABLE), "unavailable"))
	row.add_child(_captioned(_scene_action("Cast", "5 Energy", S.PRESSED), "pressed"))
	row.add_child(_captioned(_scene_action("Sow ×1", "2 Energy", S.HOLDING, 0.6), "holding"))
	row.add_child(_captioned(_scene_action("Cast", "5 Energy", S.PENDING), "pending"))
	row.add_child(_captioned(_scene_action("Till", "", S.DEFAULT), "0 Energy: no price"))
	return row

static func _action_keys() -> Control:
	var row := _row(UiTokens.SPACE_SECTION)
	var a := UiActionKey.new()
	a.tool_icon = _tex("hoe")
	a.key().verb = "Sow ×1"
	a.key().cost = "2 Energy"
	a.caption = "uses your Energy"
	row.add_child(_captioned(a, "farming · first-time caption"))
	var b := UiActionKey.new()
	b.tool_icon = _tex("rod")
	b.key().verb = "Cast"
	b.key().cost = "Need 5 Energy"
	b.key().state = UiSceneAction.State.INSUFFICIENT
	row.add_child(_captioned(b, "fishing · not enough Energy"))
	return row

static func _radial_options() -> Array:
	return [
		{id = "farming", name = "Farming", icon = _tex("hoe"), available = false, reason = "No plots here"},
		{id = "fishing", name = "Fishing", icon = _tex("fish"), available = true},
		{id = "mining", name = "Mining", icon = _tex("pickaxe"), available = false, reason = "Enter the mine"},
		{id = "combat", name = "Combat", icon = _tex("sword"), available = false, reason = "Mine floors 3–5"},
	]

## A radial in a fixed host, posed: `ms` of opening (-1 = fully open), optionally a locked petal tapped.
static func _radial_frame(host_size: Vector2, ms: float, tap := -1, k := 1.0) -> Control:
	var host := Control.new()
	host.custom_minimum_size = host_size * k
	host.clip_contents = true
	var holder := Control.new()
	holder.size = host_size
	holder.scale = Vector2(k, k)
	host.add_child(holder)
	var r := UiActionRadial.new()
	r.haptics = false
	holder.add_child(r)    # full-rect inside the holder
	r.options = _radial_options()
	r.selected = "fishing"
	r.pose_opening(ms if ms >= 0.0 else 1000.0)
	if tap >= 0:
		r.petals()[tap].pressed.emit()
		r.advance(100.0)   # the shake has settled; the reason shows
	r.frozen = true   # a still: frame steps leave the pose alone
	return host

## LOCK-03 v2 (247): P1 open 1651:100657 and P2 a locked petal tapped 1651:100787.
static func _action_radial() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	v.add_child(_captioned(_radial_frame(Vector2(328, 226), -1.0), "open · ring around the screen centre · Fishing current"))
	v.add_child(_captioned(_radial_frame(Vector2(328, 226), -1.0, 3), "tap a locked petal · it shakes, the reason shows at the centre"))
	return v

## P3 motion 1651:100816: 0 / 80 / 160 / 300 ms of the opening (petals 40 ms apart, 180 ms ease-out-back each).
static func _action_radial_motion() -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", int(UiTokens.SPACE_WITHIN))
	grid.add_theme_constant_override(&"v_separation", int(UiTokens.SPACE_WITHIN))
	for ms in [0.0, 80.0, 160.0, 300.0]:
		grid.add_child(_captioned(_radial_frame(Vector2(220, 220), ms, -1, 0.72), "%d ms" % int(ms)))
	return grid

## A scene-grey strip so the surface-coloured prompts read as they do over the world.
static func _scene_row(h: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = UiKit.alpha(UiTokens.COLOR_TEXT, UiTokens.OPACITY_SCRIM_MODAL)
	r.custom_minimum_size = Vector2(328, h)
	return r

## SGODOT-250 (row 51 1674:101146): the icon buttons a facility shows within view, the one name strip of the nearest,
## and NPC name tags.
static func _world_prompts() -> Control:
	var v := _column(UiTokens.SPACE_SECTION)
	var icons := _scene_row(60)
	var x := 30.0
	for spec in [["home", false, -1, ""], ["seat", true, -1, ""], ["homestead_stall", false, UiStatusBadge.State.REQUEST, ""], ["workbench", false, -1, ""], ["cabinet", false, -1, "4/6"]]:
		var b := UiWorldIconButton.new()
		icons.add_child(b)
		b.icon = _tex(spec[0])
		b.near = spec[1]
		b.status = spec[2]
		b.count = spec[3]
		b.place_at(Vector2(x, 30))
		x += 66.0
	v.add_child(_captioned(icons, "icons · default · Near · state · count"))
	var D := UiWorldNameBar.Dir
	var bars := [
		[_tex("home"), "Farmhouse", "", D.RIGHT, false, -1, 1.0],
		[_tex("home"), "Farmhouse", "", D.LEFT, false, -1, 1.0],
		[_tex("pot"), "Stove 1/1", "Empty", D.RIGHT, false, -1, 1.0],
		[_tex("homestead_stall"), "Homestead Stall", "", D.RIGHT, false, UiStatusBadge.State.REQUEST, 1.0],
		[_tex("rest"), "+60 Energy", "", D.RIGHT, false, -1, 1.0],
		[_tex("rest"), "Rested today", "", D.RIGHT, true, -1, 1.0],
		[_tex("door"), "Map", "", D.RIGHT, false, -1, 1.0],
		[_tex("workbench"), "Workbench", "", D.RIGHT, false, -1, 0.5],
	]
	var captions := ["Right", "Left · edge", "one fact", "state", "bench", "Dimmed", "door", "opening 50 %"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", int(UiTokens.SPACE_WITHIN))
	grid.add_theme_constant_override(&"v_separation", int(UiTokens.SPACE_WITHIN))
	for i in bars.size():
		var spec: Array = bars[i]
		var row := _scene_row(48)
		row.custom_minimum_size = Vector2(160, 48)
		var bar := UiWorldNameBar.new()
		row.add_child(bar)
		bar.icon = spec[0]
		bar.text = spec[1]
		bar.fact = spec[2]
		bar.side = spec[3]
		bar.dimmed = spec[4]
		bar.status = spec[5]
		bar.anchor_at(Vector2(134 if spec[3] == D.LEFT else 26, 24))
		bar.set_openness(spec[6])
		grid.add_child(_captioned(row, captions[i]))
	v.add_child(grid)
	var tags := _scene_row(60)
	var ama := UiNpcNameTag.new("Ama")
	tags.add_child(ama)
	ama.place_over(Vector2(100, 44))
	var pip := UiNpcNameTag.new("Pip")
	tags.add_child(pip)
	pip.highlight = true
	pip.place_over(Vector2(220, 44))
	v.add_child(_captioned(tags, "NPC · Default · Highlight"))
	return v

static func _status_badges() -> Control:
	var v := _column()
	var row := _row(UiTokens.SPACE_ROW)
	var names := ["available", "ready", "countdown", "cooling", "used today", "locked", "insufficient", "full", "new",
		"request", "deliverable", "event", "gift", "blocked", "sell"]
	for s in UiStatusBadge.State.values():
		var b := UiStatusBadge.new(s)
		b.icon = _tex("dish_grilled_fish")
		if s == UiStatusBadge.State.COUNTDOWN: b.caption = "1h 12m"
		row.add_child(_captioned(b, names[s]))
	v.add_child(row)
	var npc := _row(UiTokens.SPACE_ROW)
	for s in [UiStatusBadge.State.REQUEST, UiStatusBadge.State.DELIVERABLE, UiStatusBadge.State.GIFT, UiStatusBadge.State.NEW]:
		npc.add_child(_captioned(UiStatusBadge.new(s, UiStatusBadge.Size.NPC), "NPC · " + names[s]))
	v.add_child(npc)
	return v

## The main's four variants: State=Available / Unavailable × Pointer=Center / Right (gate near the right edge).
static func _entry_cards() -> Control:
	var v := _column()
	var A := UiEntryCard.State.AVAILABLE
	var U := UiEntryCard.State.UNAVAILABLE
	for it in [["New run · 2 Energy", "Current run will end · Runs today 1/2", A, false, "available"],
			["New run · Clear Floor 2 first", "", U, false, "unavailable: the reason on the action line"],
			["New run · 2 Energy", "Current run will end · Runs today 1/2", A, true, "available, gate near the right edge"],
			["Mine runs today 2/2 · Resets in 9h 12m", "", U, true, "unavailable, gate near the right edge"]]:
		var c := UiEntryCard.new(it[0], it[1], it[2])
		if it[3]: c.point_at(1000.0)
		v.add_child(_captioned(c, it[4]))
	return v

## B2-06's cards: Tools (a gap on the button, craftable, Equip, Equipped, Owned · always on) and Supplies (Craft with
## You get / You have, No room, the Farming Lv3 gate).
static func _blueprint_cards() -> Control:
	var v := _column(10)
	var P := UiBlueprintCard.Kind.PRIMARY
	var S := UiBlueprintCard.Kind.SECONDARY
	var U := UiBlueprintCard.Kind.UNAVAILABLE
	var ore := func(have: int) -> Dictionary: return {"icon": _tex("copper_ore"), "name": "Copper Ore", "have": have, "need": 5}
	var wood := func(need: int) -> Dictionary: return {"icon": _tex("wood"), "name": "Timber", "have": 17, "need": need}
	var reeds := func(need: int) -> Dictionary: return {"icon": _tex("fiber"), "name": "Reeds", "have": 8, "need": need}
	for it in [
			[{"icon": _tex("pick_copper"), "name": "Copper Pickaxe", "effect": "2 Stone per rock", "materials": [ore.call(4), wood.call(4)],
				"button": {"label": "Need 1 more Copper Ore", "kind": U}}, "Tools · a gap on the button"],
			[{"icon": _tex("gather_gloves"), "name": "Gather Gloves", "effect": "+1 at every gathering spot", "materials": [reeds.call(8), wood.call(4)],
				"button": {"label": "Craft", "kind": P}}, "Tools · craftable"],
			[{"icon": _tex("pick_copper"), "name": "Copper Pickaxe", "effect": "2 Stone per rock", "button": {"label": "Equip", "kind": S}}, "owned · Equip"],
			[{"icon": _tex("pick_copper"), "name": "Copper Pickaxe", "effect": "2 Stone per rock", "button": {"label": "Equipped", "kind": U}}, "equipped"],
			[{"icon": _tex("gather_gloves"), "name": "Gather Gloves", "effect": "+1 at every gathering spot",
				"button": {"label": "Owned · always on", "kind": U}}, "passive · owned"],
			[{"icon": _tex("torch"), "name": "Torch", "effect": "See what rocks hold", "yield": "You get 2", "have": "You have 6",
				"materials": [wood.call(1), reeds.call(1)], "button": {"label": "Craft", "kind": P}}, "Supplies · craftable"],
			[{"icon": _tex("torch"), "name": "Torch", "effect": "See what rocks hold", "yield": "You get 2", "have": "You have 6",
				"materials": [wood.call(1), reeds.call(1)], "button": {"label": "No room · free a slot first", "kind": U}}, "Supplies · bag full"],
			[{"icon": _tex("compost"), "name": "Compost", "effect": "Crops ready 20% sooner", "yield": "You get 2", "have": "You have 0",
				"materials": [reeds.call(2), wood.call(1)], "button": {"label": "Farming Lv3", "kind": U}}, "Supplies · skill gate"]]:
		var c := UiBlueprintCard.new(it[0])
		c.custom_minimum_size.x = 328
		v.add_child(_captioned(c, it[1]))
	return v

static func _quality_badges() -> Control:
	var row := _row(UiTokens.SPACE_ROW)
	row.add_child(_captioned(UiQualityBadge.new(1), "Good"))
	row.add_child(_captioned(UiQualityBadge.new(2), "Perfect"))
	return row

static func _reward_moment(fields: Dictionary) -> UiRewardMoment:
	var r := UiRewardMoment.new()
	r.show_fields(fields)
	return r

## SysBanner (1187:82581, WP6): Offline with Retry, Back online, a command that didn't go through.
static func _sys_banners() -> Control:
	var v := _column()
	for t in [[UiSysBanner.Kind.OFFLINE, "Offline · Reconnecting…", "Offline (SYS-OFFLINE)"],
			[UiSysBanner.Kind.BACK_ONLINE, "Back online", "BackOnline (SYS-OFFLINE-2)"],
			[UiSysBanner.Kind.CMD_FAIL, "Didn't go through · try again", "CmdFail (SYS-CMD-FAIL)"]]:
		var b := UiSysBanner.new()
		b.kind = t[0]
		b.message = t[1]
		v.add_child(_captioned(b, t[2]))
	return v

## InboxRow (1309:89969, SGODOT-234): a parcel with Claim, the same with the bag full (grey Claim), an expired parcel
## (Kind=System, unread).
static func _inbox_rows() -> Control:
	var v := _column()
	var specs := [
		[UiInboxRow.Kind.ITEM, {key = "a", icon = _tex("fish_perch"), title = "Perch ×7", sub = "Request reward · Stall Board", left = "23h 40m left", can_claim = true}, "Kind=Item · Claim"],
		[UiInboxRow.Kind.ITEM, {key = "b", icon = _tex("bait_worm"), title = "Worm Bait ×3", sub = "Fishing Lv2 reward", left = "12h left", can_claim = false}, "Kind=Item · bag full"],
		[UiInboxRow.Kind.SYSTEM, {key = "c", icon = _tex("parcel"), title = "Parcel expired · +18 coins", sub = "Perch ×7 · turned into coins at 80%", time = "Just now", unread = true}, "Kind=System · unread"],
	]
	for s in specs:
		var row := UiInboxRow.new(s[0])
		row.show_row(s[1])
		v.add_child(_captioned(row, s[2]))
	return v

## SystemCard (1237:87229, SGODOT-233): Blocking as SYS-LOADING-FAIL draws it (Can't connect · Retry, the wifi-off glyph
## in ink on the primaryTint disc).
static func _system_cards() -> Control:
	var v := _column()
	var fail := UiSystemCard.new()
	fail.show_card({icon = preload("res://assets/ui/kit_icons/wifi_off.svg"), icon_tint = UiTokens.COLOR_TEXT, title = "Can't connect",
		body = "Check your connection and try again.", primary = "Retry"})
	v.add_child(_captioned(fail, "Kind=Blocking · SYS-LOADING-FAIL"))
	return v

## SYS-LOADING-SCENE-FAIL (1780:103778, q(78)): the same card with its secondary Go back, a CommandButton Kind=secondary.
static func _system_card_trip() -> Control:
	var v := _column()
	var trip := UiSystemCard.new()
	trip.show_card({icon = preload("res://assets/ui/kit_icons/wifi_off.svg"), icon_tint = UiTokens.COLOR_TEXT, title = "Couldn't get there",
		body = "Check your connection and try again.", primary = "Retry", secondary = "Go back"})
	v.add_child(_captioned(trip, "Kind=Blocking + secondary · SYS-LOADING-SCENE-FAIL"))
	return v

## The placeholder wordmark (sprout + Gensen, 148 × 44) and the 28 px spinner (held still) with SYS-LOADING-2's caption.
static func _wordmark_spinner() -> Control:
	var v := _column()
	v.add_child(_captioned(UiWordmark.new(), "Wordmark (placeholder)"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_ROW))
	var spin := UiSpinner.new()
	spin.spinning = false
	row.add_child(spin)
	row.add_child(UiKit.label("Taking longer than usual…", UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY))
	v.add_child(_captioned(row, "Spinner · SYS-LOADING-2"))
	return v

## MomentBanner (1226:104630, SGODOT-233): the account's first level-up (rewards, recipe, tip, Use bait), a later level
## (unlocks and what is next) and Kind=Complete (a crafted tool).
static func _moment_banners() -> Control:
	var v := _column()
	var first := UiMomentBanner.new()
	first.level = "2"
	first.title = "Fishing Lv 2"
	first.subtitle = "Fine fish now stay on the hook"
	first.rewards = [UiFloatText.pill("+50 Energy", UiFloatText.Tone.ENERGY_GAIN), UiFloatText.pill("+3 Worm Bait", UiFloatText.Tone.ITEM, _tex("bait_worm")),
		UiFloatText.pill("+3 Wild Herb", UiFloatText.Tone.ITEM, _tex("crop_herb"))]
	first.detail = "New recipe: Herb Grilled Fish"
	first.tip = "Levels unlock gear, fish and seeds. Basics never lock."
	first.action = "Use bait"
	v.add_child(_captioned(first, "LevelUp · SKILL-3, the account's first (≤ 3 s)"))
	var later := UiMomentBanner.new()
	later.level = "2"
	later.title = "Farming Lv 2"
	later.subtitle = "New for you · Carrot Seeds, Herb Seeds"
	later.rewards = [UiFloatText.pill("+30 Energy", UiFloatText.Tone.ENERGY_GAIN), UiFloatText.pill("+5 Carrot Seeds", UiFloatText.Tone.ITEM, _tex("seed_carrot"))]
	later.tip = "Next Lv3 · 150 XP"
	v.add_child(_captioned(later, "LevelUp · FARM-LV2, a later level (1.5 s)"))
	var done := UiMomentBanner.new()
	done.kind = UiMomentBanner.Kind.COMPLETE
	done.title = "Gather Gloves"
	done.subtitle = "+1 at every gathering spot"
	v.add_child(_captioned(done, "Complete"))
	return v

static func _reward_moments() -> Control:
	var row := _row(UiTokens.SPACE_SECTION)
	row.add_child(_captioned(_reward_moment({event = "New recipe!", icon = _tex("dish_herb_grilled_fish"), item_name = "Herb Grilled Fish",
		rarity = 2, rarity_word = "Fine", quality = 1, strip = "First cooked · +20 Cooking XP · Cookbook 2/48", strip_icon = _tex("cookbook"),
		primary = "Eat · +45 Energy", secondary = "Keep", note = "Gift later from your bag"}), "Reward · first cook (COOK-4)"))
	row.add_child(_captioned(_reward_moment({event = "Dish ready", icon = _tex("dish_herb_grilled_fish"), item_name = "Herb Grilled Fish",
		rarity = 2, rarity_word = "Fine", quality = 1, strip = "Collected from Stove 1", strip_icon = _tex("cookbook"),
		primary = "Energy full", primary_reason = "Energy full", secondary = "Keep", note = "Gift later from your bag"}), "Reward · ready, Energy full (COOK-P0-9)"))
	row.add_child(_captioned(_reward_moment({tone = UiRewardMoment.Tone.NEUTRAL, event = "Mystery Dish", icon = _tex("dish_mystery"),
		item_name = "Hmm… not a dish", strip = "A clue was added to your Cookbook", strip_icon = _tex("cookbook"),
		primary = "Eat · +5 Energy", secondary = "Keep", note = "Can't be sold or delivered"}), "Neutral · Mystery Dish (COOK-6)"))
	row.add_child(_captioned(_reward_moment({tone = UiRewardMoment.Tone.NEUTRAL, event = "No dish this time", icon = _tex("dish_mystery"),
		item_name = "Ingredients back", rarity_word = "9 left today", primary = "OK"}), "Neutral · No dish, blessing refund"))
	row.add_child(_captioned(_reward_moment({tone = UiRewardMoment.Tone.MILESTONE, event = "Home Cook", icon = _tex("cookbook"),
		item_name = "Cookbook 8/48", strip = "Title · +50 Energy"}), "Milestone · no buttons"))
	return row

