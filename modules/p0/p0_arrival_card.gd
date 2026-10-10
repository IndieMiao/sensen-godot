extends RefCounted
## MAP-7-FREE (plan v2 §11.8.4 step 7, Figma 482:412): the first visit's card, "3 things to do here". The place card's
## sheet (P0PlaceSheet: the object header, the × above its corner) with item rows instead of facts, navigation rows
## (Show local pond ›) and one primary command (Visit the outpost). Preloaded, no class_name (a new global class needs
## an editor import).

## spec: {title, state, effect, facts: [[label, value]], rows: [{icon, title, state?, effect, quantity?, unit?}],
## links: [[label, Callable]], primary ("" none), dismiss ("" none: the quiet bottom button, e.g. Keep browsing)}.
## go: the primary's action. Returns the holder; ui.modal_kind = kind ("arrival_card"; the silhouette card MAP-3-FREE
## uses the same sheet as "city_card").
static func open(ui: Node, spec: Dictionary, go: Callable, kind := "arrival_card") -> Control:   # ui: P0Ui (untyped: P0Ui preloads this)
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
	col.add_child(_handle())   # the sheet's grip (Figma Sheet · Handle, as UiDrawer draws it)
	col.add_child(UiObjectHeader.new({"title": str(spec.get("title", "")), "state": str(spec.get("state", "")),
		"effect": str(spec.get("effect", ""))}))
	for f in spec.get("facts", []): col.add_child(UiFactRow.new(str(f[0]), str(f[1])))
	for r in spec.get("rows", []):
		var row := UiItemRow.new({"icon": r.get("icon", null), "title": str(r.get("title", "")),
			"state": str(r.get("state", "")), "effect": str(r.get("effect", "")),
			"quantity": str(r.get("quantity", "")), "quantity_label": str(r.get("unit", ""))})
		row.name = "Row_" + str(r.get("title", "")).replace(" ", "_")
		if r.get("pressed") is Callable:   # a row that opens something (the Passport's cities): the row inside a flat button
			var b := Button.new()
			b.flat = true
			b.focus_mode = Control.FOCUS_NONE
			b.name = row.name
			b.pressed.connect(r.pressed)
			row.name = "ItemRow"
			b.add_child(row)
			# a Button does not lay out its children: it takes the row's height, and the row its width
			row.minimum_size_changed.connect(func(): b.custom_minimum_size.y = row.get_combined_minimum_size().y)
			b.resized.connect(func(): row.size = Vector2(b.size.x, row.get_combined_minimum_size().y))
			b.custom_minimum_size.y = row.get_combined_minimum_size().y
			col.add_child(b)
		else:
			col.add_child(row)
		for f in r.get("facts", []): col.add_child(UiFactRow.new(str(f[0]), str(f[1])))
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
	if str(spec.get("dismiss", "")) != "":
		var quiet := UiDismissButton.new(str(spec.dismiss))
		quiet.name = "Dismiss"
		quiet.pressed.connect(ui.back_modal)   # Back to where it was opened from (the profile, the Passport), else closes
		col.add_child(quiet)
	holder.add_child(panel)
	var close := UiCloseButton.new()   # floats 6 above the sheet's top-right corner, as the place card's
	close.pressed.connect(ui.close_modal)
	holder.add_child(close)
	panel.resized.connect(func():
		close.position = Vector2(panel.size.x - 16 - UiTokens.SIZE_CLOSE, panel.position.y - 6 - UiTokens.SIZE_CLOSE))
	ui._open_modal(holder, 0.0, false)
	ui.modal_kind = kind
	return holder

## The sheet's grip, centred over the header: UiDrawer's handle (its size and colour), display only.
static func _handle() -> Control:
	var grip := Control.new()
	grip.name = "Handle"
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.custom_minimum_size = Vector2(0, UiDrawer._HANDLE.y)
	grip.draw.connect(func():
		var r := Rect2(Vector2((grip.size.x - UiDrawer._HANDLE.x) * 0.5, 0), UiDrawer._HANDLE)
		grip.draw_style_box(UiStyleBox.make(UiTokens.COLOR_BORDER, UiDrawer._HANDLE.y * 0.5), r))
	return grip
