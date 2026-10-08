class_name P0PlaceSheet
extends RefCounted
## The map's place card (Figma TUT-3-04 482:193): a bottom sheet with the object header (title / subtitle), an
## optional line, fact rows, an optional Details › link and one primary command, and a × floating above its corner.
## Ponds use it today (SGODOT-227 follow-up, q(48)); the homestead and outposts in SGODOT-234 A2 (亚瑟), with the
## same rule for the place the player is at (q(80)): no Distance row, and the primary reads "Back to <name>",
## re-entering that scene through the loading cover as Go does.

## "0.8 km" on a card or pin tag; 0.1 km at the least.
static func distance_text(km: float) -> String:
	return "%.1f km" % maxf(0.1, km)

## Great-circle distance in km between two (lat, lng) points.
static func km_between(a: Vector2, b: Vector2) -> float:
	var r := 6371.0
	var la1 := deg_to_rad(a.x)
	var la2 := deg_to_rad(b.x)
	var dla := la2 - la1
	var dlo := deg_to_rad(b.y - a.y)
	var h := sin(dla * 0.5) ** 2 + cos(la1) * cos(la2) * sin(dlo * 0.5) ** 2
	return 2.0 * r * asin(minf(1.0, sqrt(h)))

## The card spec for where the player is (q(80)): `here` drops the Distance fact and sets primary "Back to <title>";
## elsewhere the primary is spec.primary, else "Go". spec: {title, subtitle, line?, facts: [[label, value]], primary?}.
static func for_here(spec: Dictionary, here: bool) -> Dictionary:
	var out := spec.duplicate(true)
	if here:
		out["facts"] = (spec.get("facts", []) as Array).filter(func(f): return str(f[0]) != "Distance")
		out["primary"] = "Back to %s" % str(spec.get("title", ""))
	else:
		out["primary"] = str(spec.get("primary", "Go"))
	return out

## Opens the sheet as `ui`'s modal (modal_kind = kind). go: the primary's action (the sheet does not close itself;
## the caller decides); details: Details › (none when empty); closed: called once the sheet leaves the tree.
## Returns the holder.
static func open(ui: P0Ui, spec: Dictionary, go: Callable, details := Callable(), closed := Callable(), kind := "place_card") -> Control:
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
	col.add_child(UiObjectHeader.new({"title": str(spec.get("title", "")), "state": str(spec.get("subtitle", ""))}))
	if str(spec.get("line", "")) != "": col.add_child(UiKit.label(str(spec.line), UiTokens.STYLE_C14_B))
	for f in spec.get("facts", []): col.add_child(UiFactRow.new(str(f[0]), str(f[1])))
	if details.is_valid():
		var link := Button.new()
		link.name = "Details"
		link.flat = true
		link.focus_mode = Control.FOCUS_NONE
		link.custom_minimum_size = Vector2(0, UiTokens.SIZE_TOUCH)
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dl := UiKit.label("Details", UiTokens.STYLE_C14_XB, UiTokens.COLOR_INFO)
		dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(dl)
		row.add_child(UiKit.label("›", UiTokens.STYLE_C14_XB, UiTokens.COLOR_INFO))
		link.add_child(row)
		link.pressed.connect(details)
		col.add_child(link)
	var primary := UiCommandButton.new(str(spec.get("primary", "Go")))
	primary.name = "Primary"
	primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary.activated.connect(go)
	col.add_child(primary)
	holder.add_child(panel)
	var close := UiCloseButton.new()   # floats 6 above the sheet's top-right corner
	close.pressed.connect(ui.close_modal)
	holder.add_child(close)
	panel.resized.connect(func():
		close.position = Vector2(panel.size.x - 16 - UiTokens.SIZE_CLOSE, panel.position.y - 6 - UiTokens.SIZE_CLOSE))
	if closed.is_valid(): holder.tree_exiting.connect(closed)
	ui._open_modal(holder, 0.0, false)
	ui.modal_kind = kind
	return holder
