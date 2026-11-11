class_name P0PlaceSheet
extends RefCounted
## The map's place card (Figma TUT-3-04 482:193): a bottom sheet with the object header (title / subtitle), an
## optional line, fact rows, an optional Details › link and one primary command, and a × floating above its corner.
## Ponds use it today (SGODOT-227 follow-up, q(48)); the homestead and outposts in SGODOT-234 A2 (亚瑟), with the
## same rule for the place the player is at (q(80)): no Distance row, and the primary reads "Back to <name>",
## re-entering that scene through the loading cover as Go does.

const REASON_H := 24      # q(103): one line, 24 high (the column's 8 above and below)
const REASON_ICON := 18.0
const REASON_GAP := 6

## "0.8 km" on a card or pin tag; 0.1 km at the least.
## Every distance the map writes (pin cards, pond cards, the Bite Board, city cards; 李白 / 不知火舞 2026-10-10): under
## 10 km one decimal (`0.8 km`, `3.6 km`), from 10 km whole km with thousands commas (`12 km`, `8,269 km`); rounded,
## never under `0.1 km` (q(132)). Where the player is shows no Distance at all (q(80), for_here).
static func distance_text(km: float) -> String:
	var tenths := roundf(maxf(0.1, km) * 10.0) / 10.0
	if tenths < 10.0: return "%.1f km" % maxf(0.1, tenths)
	return "%s km" % load("res://modules/p0/p0_travel.gd").grouped(roundi(km))

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
## elsewhere the primary is spec.primary, else "Go". spec: {title, subtitle, thumb? (a pond's template, UiPondThumb),
## conditions? ([[icon, word]]: the condition line), reason? (PinReason.reason), line?, facts: [[label, value]] (a value
## that is an Array of [day, icon] draws the Forecast row), primary?}.
static func for_here(spec: Dictionary, here: bool) -> Dictionary:
	var out := spec.duplicate(true)
	if here:
		out["facts"] = (spec.get("facts", []) as Array).filter(func(f): return str(f[0]) != "Distance")
		out["primary"] = "Back to %s" % str(spec.get("title", ""))
	else:
		out["primary"] = str(spec.get("primary", "Go"))
	return out

## The reason line (q(103), 不知火舞 on 268): the pin's own mark as an 18 px STATE-ICONS badge, 6 px, the reason in
## C13 bold ink on one 24 px line, cut with an ellipsis; no fill. Placed under the subtitle, above the line.
static func reason_row(why: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.name = "Reason"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size.y = REASON_H
	row.add_theme_constant_override(&"separation", REASON_GAP)
	var mark := Control.new()   # the 28 px world badge drawn at 18 px
	mark.name = "Mark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.custom_minimum_size = Vector2(REASON_ICON, REASON_ICON)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var state := UiStatusBadge.state_of(str(why.get("state", "")))
	if state >= 0:
		var badge := UiStatusBadge.new(state as UiStatusBadge.State)
		badge.scale = Vector2.ONE * (REASON_ICON / float(UiTokens.SIZE_STATUS_BADGE_WORLD))
		mark.add_child(badge)
	row.add_child(mark)
	var text := UiKit.label(str(why.get("text", "")), UiTokens.STYLE_C13_B, UiTokens.COLOR_TEXT)
	text.name = "Text"
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(text)
	return row

## The condition line (283 e61cda10 ①, 2255:143071): 16 px icons and C12 bold secondary words, 4 apart, ` · ` between
## — `[i-dawn-dusk] Dusk · [i-windy] Windy`. The pond card and the Bite Board's title share it.
static func conditions_row(parts: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Conditions"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 4)
	for i in parts.size():
		if i > 0: row.add_child(UiKit.label("·", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY))
		var icon := UiKit.icon(P0Logic.icon(str(parts[i][0])), 16)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		row.add_child(UiKit.label(str(parts[i][1]), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY))
	return row

## The Forecast fact (Fishing Lv3+, 2255:143080): the label, then `Sat [i-rain] · Sun [i-windy] · Mon [i-clear]` on the
## right — day names body XB14 ink, 16 px weather icons, secondary ` · `, 4 apart; padded as a Fact row.
static func forecast_row(label: String, days: Array) -> MarginContainer:
	var box := MarginContainer.new()
	box.name = "Forecast"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"margin_top", int(UiTokens.SPACE_WITHIN))
	box.add_theme_constant_override(&"margin_bottom", int(UiTokens.SPACE_WITHIN))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_OVERLAY_BODY))
	box.add_child(row)
	var name_ := UiKit.label(label, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	name_.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_)
	var right := HBoxContainer.new()
	right.name = "Days"
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override(&"separation", 4)
	for i in days.size():
		if i > 0: right.add_child(UiKit.label("·", UiTokens.STYLE_BODY_XB14, UiTokens.COLOR_SECONDARY))
		right.add_child(UiKit.label(str(days[i][0]), UiTokens.STYLE_BODY_XB14))
		var icon := UiKit.icon(P0Logic.icon(str(days[i][1])), 16)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		right.add_child(icon)
	row.add_child(right)
	return box

## Opens the sheet as `ui`'s modal (modal_kind = kind). go: the primary's action (the sheet does not close itself;
## the caller decides); details: Details › (none when empty); closed: called once the sheet leaves the tree.
## spec.blocked: the primary's gap in LOCK-10's unavailable look (`Need 10 more coins`, still tappable: a tap calls
## spec.on_blocked, never `go`; spec.blocked_energy: in need-energy's amber, an Energy gap); spec.footer: a caption
## under it (MAP-5: `Return home is always free`); spec.toast_over_card: a toast sits over the card's top edge, not
## over its rows (q(318), the travel cards; P0Ui._aim_toast).
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
	var header := UiObjectHeader.new({"title": str(spec.get("title", "")), "state": str(spec.get("subtitle", ""))})
	if str(spec.get("thumb", "")) != "":   # a pond: its thumbnail left of the title, 12 apart (2255:143162)
		var top := HBoxContainer.new()
		top.name = "Header"
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override(&"separation", 12)
		var thumb := UiPondThumb.new(str(spec.thumb), UiPondThumb.CARD)
		thumb.name = "Thumb"
		thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(thumb)
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(header)
		col.add_child(top)
	else:
		col.add_child(header)
	var now: Array = spec.get("conditions", [])
	if not now.is_empty(): col.add_child(conditions_row(now))
	var why: Dictionary = spec.get("reason", {}) if spec.get("reason", {}) is Dictionary else {}
	if not why.is_empty(): col.add_child(reason_row(why))
	# a state said, not a fact: secondary grey (E4 329:182456 `Not open yet`, 不知火舞 355 850d2fc2)
	if str(spec.get("line", "")) != "": col.add_child(UiKit.label(str(spec.line), UiTokens.STYLE_C14_B, UiTokens.COLOR_SECONDARY))
	for f in spec.get("facts", []):   # [label, value] or [label, value, its glyph] (q(318) v3)
		if f[1] is Array:
			col.add_child(forecast_row(str(f[0]), f[1]))
			continue
		var fact := UiFactRow.new(str(f[0]), str(f[1]))
		if f.size() > 2 and f[2] is Texture2D: fact.icon = f[2]
		col.add_child(fact)
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
	if not bool(spec.get("no_primary", false)):   # spec.no_primary: no key at all (a wild mine not open yet, E4)
		var primary := UiCommandButton.new(str(spec.get("primary", "Go")))
		primary.name = "Primary"
		primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		primary.activated.connect(go)
		if str(spec.get("blocked", "")) != "":
			primary.reason = str(spec.blocked)
			primary.need_energy = bool(spec.get("blocked_energy", false))
			if spec.get("on_blocked") is Callable: primary.unavailable_pressed.connect(func(_r): (spec.on_blocked as Callable).call())
		col.add_child(primary)
	if str(spec.get("footer", "")) != "":
		var foot := UiKit.label(str(spec.footer), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		foot.name = "Footer"
		foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(foot)
	holder.add_child(panel)
	if bool(spec.get("toast_over_card", false)): holder.set_meta(&"toast_over_card", panel)
	var close := UiCloseButton.new()   # floats 6 above the sheet's top-right corner
	close.pressed.connect(ui.close_modal)
	holder.add_child(close)
	panel.resized.connect(func():
		close.position = Vector2(panel.size.x - 16 - UiTokens.SIZE_CLOSE, panel.position.y - 6 - UiTokens.SIZE_CLOSE))
	if closed.is_valid(): holder.tree_exiting.connect(closed)
	ui._open_modal(holder, 0.0, false)
	ui.modal_kind = kind
	return holder
