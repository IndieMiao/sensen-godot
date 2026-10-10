extends RefCounted
## MAP-7-FREE (plan v2 §11.8.4 step 7, Figma 482:412): the first visit's card, "3 things to do here". The place card's
## sheet (P0PlaceSheet: the object header, the × above its corner) with item rows instead of facts, navigation rows
## (Show local pond ›) and one primary command (Visit the outpost). Preloaded, no class_name (a new global class needs
## an editor import).

## spec: {title, state, effect, rows: [{icon, title, state?, effect}], links: [[label, Callable]], primary ("" none)}.
## go: the primary's action. Returns the holder; ui.modal_kind = "arrival_card".
static func open(ui: P0Ui, spec: Dictionary, go: Callable) -> Control:
	var holder := Control.new()
	holder.theme = UiKit.theme()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sheet := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_SHEET, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	panel.add_theme_stylebox_override(&"panel", sheet.with_margins(16, 18, 16, 16 + ui.safe_bottom()))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	panel.add_child(col)
	col.add_child(UiObjectHeader.new({"title": str(spec.get("title", "")), "state": str(spec.get("state", "")),
		"effect": str(spec.get("effect", ""))}))
	for r in spec.get("rows", []):
		var row := UiItemRow.new({"icon": r.get("icon", null), "title": str(r.get("title", "")),
			"state": str(r.get("state", "")), "effect": str(r.get("effect", ""))})
		row.name = "Row_" + str(r.get("title", "")).replace(" ", "_")
		col.add_child(row)
	for link in spec.get("links", []):
		var nav := UiNavButton.new(str(link[0]))
		nav.name = "Link_" + str(link[0]).replace(" ", "_")
		nav.pressed.connect(link[1])
		col.add_child(nav)
	if str(spec.get("primary", "")) != "":
		var primary := UiCommandButton.new(str(spec.primary))
		primary.name = "Primary"
		primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary.activated.connect(go)
		col.add_child(primary)
	holder.add_child(panel)
	var close := UiCloseButton.new()   # floats 6 above the sheet's top-right corner, as the place card's
	close.pressed.connect(ui.close_modal)
	holder.add_child(close)
	panel.resized.connect(func():
		close.position = Vector2(panel.size.x - 16 - UiTokens.SIZE_CLOSE, panel.position.y - 6 - UiTokens.SIZE_CLOSE))
	ui._open_modal(holder, 0.0, false)
	ui.modal_kind = "arrival_card"
	return holder
