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
		{id = "style_box", title = "UiStyleBox inset and dashed", figma = "Compact/Command 633:41273 (34 in 44) · empty slot", build = _style_boxes},
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
	var names := consts.keys().filter(func(k): return String(k).begins_with("COLOR_"))
	names.sort()
	for k in names:
		var cell := _column(2)
		var sw := Panel.new()
		sw.custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_SLOT_W * 1.4, UiTokens.SIZE_TOUCH * 0.5)
		sw.add_theme_stylebox_override(&"panel", UiStyleBox.make(consts[k], UiTokens.RADIUS_CHIP * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
		cell.add_child(sw)
		cell.add_child(UiKit.label(String(k).trim_prefix("COLOR_").to_lower(), UiTokens.STYLE_C9_B, UiTokens.COLOR_SECONDARY))
		grid.add_child(cell)
	return grid

static func _type_ramp() -> Control:
	var v := _column(2)
	var consts: Dictionary = (UiTokens as Script).get_script_constant_map()
	var names := consts.keys().filter(func(k): return String(k).begins_with("STYLE_"))
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
			UiTokens.BUTTON_CMD_DANGER_SECONDARY, UiTokens.BUTTON_CMD_BLOCKED]:
		var b := _button(String(kind), kind)
		b.custom_minimum_size.y = UiTokens.SIZE_COMMAND
		v.add_child(b)
	var disabled := _button("Need 6 more Timber", UiTokens.BUTTON_CMD_PRIMARY, true)
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
	var inset := Panel.new()
	inset.custom_minimum_size = Vector2(UiTokens.SIZE_TOUCH * 1.6, UiTokens.SIZE_TOUCH)
	var pill := UiStyleBox.make(UiTokens.COLOR_PRIMARY, UiTokens.RADIUS_COMPACT_COMMAND)
	pill.visual_height = UiTokens.SIZE_COMMAND_COMPACT
	inset.add_theme_stylebox_override(&"panel", pill)
	row.add_child(inset)
	var hit := Panel.new()
	hit.custom_minimum_size = inset.custom_minimum_size
	hit.add_theme_stylebox_override(&"panel", UiStyleBox.make(Color.TRANSPARENT, 0.0, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
	row.add_child(hit)
	var ghost := Panel.new()
	ghost.custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_SLOT_W, UiTokens.SIZE_QUICK_SLOT_SURFACE_H)
	var dashed := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CELL, UiTokens.COLOR_EDGE_STRONG, UiTokens.STROKE_SELECTED_CELL)
	dashed.dashed = true
	ghost.add_theme_stylebox_override(&"panel", dashed)
	row.add_child(ghost)
	return row
