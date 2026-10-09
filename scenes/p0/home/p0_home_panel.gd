extends RefCounted
## HOME-1 upgrade sheet (Figma 482:152) and the HOME-2 moment (482:154 / MomentBanner 1228:108620) for
## Homestead Lv1–3 (plan §8.1–8.6, SGODOT-228). Data comes from P0Logic.home_panel / home_moment; this file
## only lays them out with the kit (UiNeedTile, UiNeedSource, UiCommandButton) on P0Ui's modal base.

const SHEET_TOP := 194.0        # sheet edge on the 360 × 800 frame; scrolling content above the fixed actions
## MomentBanner sits under the HUD (x16 y108 w328). P0Ui.show_moment places it — SIZE_HUD_TOP + SIZE_HUD_H + 10 plus the
## safe top — so this is the spec's number at safe top 0, which the test holds it to.
const MOMENT_TOP := 108.0
const MOMENT_S := 3.0           # the first Homestead upgrade: 3 s; later ones MOMENT_LATER_S (§8.1.2 ②); tap to skip
const MOMENT_LATER_S := 1.5

## HOME-1 over the farm. at_home false (the Profile farm card away from home: ui.space != "home") greys the button
## with `At home` and a tap says `Upgrade at home · Going home is free`; the tiles, What changes and the sources still
## read (the view carries homestead.next anywhere).
static func open(ui: P0Ui, at_home := true) -> void:
	var model := P0Logic.home_panel(ui.view, at_home)
	var panel := PanelContainer.new()
	panel.theme = UiKit.theme()
	if bool(model.max):   # nothing to list: a short sheet that hugs the title, the button and Close
		panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	else:
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.offset_top = SHEET_TOP
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sheet := UiStyleBox.make(UiTokens.COLOR_SURFACE, 18)
	sheet.corner_radius = Vector4(18, 18, 0, 0)
	panel.add_theme_stylebox_override(&"panel", sheet.with_margins(16, 16, 16, 12 + ui.safe_bottom()))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	panel.add_child(col)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 8)
	if bool(model.max):
		col.add_child(body)
	else:
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(scroll)
		scroll.add_child(body)
	body.add_child(UiKit.label(str(model.title), UiTokens.STYLE_C14_XB))
	if str(model.look) != "":
		body.add_child(UiKit.label(str(model.look), UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY))
	if not model.tiles.is_empty():
		var needs := VBoxContainer.new()
		needs.add_theme_constant_override(&"separation", 10)
		needs.add_child(UiKit.label("Needs", UiTokens.STYLE_C12_XB))
		var tiles: Array = []
		for t in model.tiles:
			var tile := UiNeedTile.new(str(t.name), int(t.have), int(t.need), UiNeedTile.Size.L, P0Logic.icon(str(t.icon)))
			var id := str(t.id)
			tile.pressed.connect(func(): _source(ui, tile, id))
			tiles.append(tile)
		needs.add_child(UiNeedTile.group(tiles))
		body.add_child(needs)
	if not model.changes.is_empty():
		var changes := VBoxContainer.new()
		changes.add_theme_constant_override(&"separation", 6)
		var gap := Control.new()   # pt 4 above "What changes"
		gap.custom_minimum_size = Vector2(0, 4)
		changes.add_child(gap)
		changes.add_child(UiKit.label("What changes", UiTokens.STYLE_C12_XB))
		for c in model.changes: changes.add_child(_change_row(c))
		body.add_child(changes)
	var button := UiCommandButton.new(str(model.label))
	button.reason = str(model.reason)
	button.sends = true   # homestead_upgrade: Offline while offline (§10.7.1)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.activated.connect(func(): ui.command.emit({"type": "homestead_upgrade"}))
	var tap := str(model.get("tap", ""))   # away from home: `Upgrade at home · Going home is free`, else the gap itself
	button.unavailable_pressed.connect(func(reason: String): ui.toast(tap if tap != "" else reason))
	col.add_child(button)
	panel.set_meta(&"toast_above", button)   # q(16): a toast over the sheet's fixed decision area, 8 above the button
	if not bool(model.max):
		var foot := UiKit.label(str(model.footer), UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
		foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(foot)
	var close := UiDismissButton.new("Close")
	close.pressed.connect(ui.close_layer)   # from the profile: back to it, as the system Back (int11); else the world
	col.add_child(close)
	ui._open_modal(panel, 0.3, true)
	ui.modal_kind = "homestead"

## One "What changes" row: icon 16 · what (fills) · the value it replaces, py 5.
static func _change_row(c: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.custom_minimum_size = Vector2(0, 25)
	var icon := UiKit.icon(P0Logic.icon(str(c.icon)), 16)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := UiKit.label(str(c.text), UiTokens.STYLE_C12_XB)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text)
	var note := UiKit.label(str(c.note), UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(note)
	return row

## A tapped tile: one source line above it; Show only moves the camera (LOCK-10 / LOCK-08).
static func _source(ui: P0Ui, tile: Control, id: String) -> void:
	var src := P0Logic.home_source(ui.view, id)
	var go := str(src.go) if ui.spot_reachable() else ""
	var on_show := Callable() if go == "" else func():
		ui.close_modal()
		ui.show_spot.emit(go)
	var layer := UiNeedSource.popup(ui.root, tile.get_global_rect(), str(src.text), on_show)
	layer.theme = UiKit.theme()

## PLAQUE-READ (Figma 1510:97745): read-only, only ×. ObjectHeader "Upgrade Plaque" / "Homestead LvN", one fact per
## upgrade with its date. TODO(224): swap for the InfoSheet once it lands; the content stays the same.
static func plaque(ui: P0Ui) -> void:
	var view: Dictionary = ui.view
	var holder := Control.new()
	holder.theme = UiKit.theme()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sheet := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_SHEET, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	panel.add_theme_stylebox_override(&"panel", sheet.with_margins(16, 16, 16, 24 + ui.safe_bottom()))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	panel.add_child(col)
	col.add_child(UiObjectHeader.new({"title": "Upgrade Plaque", "state": "Homestead Lv%d" % int(view.get("homestead", {}).get("level", 1))}))
	for line in P0Logic.plaque_lines(view): col.add_child(UiFactRow.new(str(line.label), str(line.value)))
	holder.add_child(panel)
	var close := UiCloseButton.new()   # floats 6 above the sheet's top-right corner
	close.pressed.connect(ui.close_modal)
	holder.add_child(close)
	panel.resized.connect(func():
		close.position = Vector2(panel.size.x - 16 - UiTokens.SIZE_CLOSE, panel.position.y - 6 - UiTokens.SIZE_CLOSE))
	ui._open_modal(holder, 0.0, true)   # like HOME-1: the main key and quick bar step aside (the frame has neither)
	ui.modal_kind = "plaque"

## HOME-2: the kit MomentBanner (Kind=LevelUp: gold accent and level disc) under the HUD for MOMENT_S (later levels
## MOMENT_LATER_S), gone on a tap; one moment at a time with the others (q(49) ④, SGODOT-233). Never covers the main
## key or quick bar.
static func moment(ui: P0Ui, m: Dictionary) -> Control:
	var spec := m.duplicate()
	spec["kind"] = "level_up"
	spec["seconds"] = MOMENT_S if int(str(m.get("level", 2))) <= 2 else MOMENT_LATER_S
	return ui.show_banner(spec)
