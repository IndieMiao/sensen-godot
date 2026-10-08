class_name UiTodayPanel
extends PanelContainer
## Today panel (SGODOT-222; Gensen Refactor/TodayPanel 1145:81715 + TodayRow 1145:81714, LOCK-06): a small
## panel right under the two HUD chips (x 10, y 96, 340 wide) with at most 3 rows. Never a bottom sheet,
## never over the quick bar or main key; the host closes it on a tap outside.
## A row is {icon, line, tail?, action?, state?}: icon + one sentence + an optional Show pill that only moves
## the camera (LOCK-08). state "done" = tick, faded, secondary ink; "short" = grey tail line with the Energy
## it needs and when it comes back. Emits `show_pressed(index)`.

signal show_pressed(index: int)

const MAX_ROWS := 3
const CHECK_GLYPH := preload("res://assets/ui/kit_icons/check.svg")

const _PAD := Vector2(12, 8)       # TodayPanel main padding
const _ROW_GAP := 8                # TodayRow icon → text → pill
const _DONE_CHECK := 18            # Done row tick disc
const _ROW_SEP := 2                # rows and dividers

var _list: VBoxContainer

func _init(rows: Array = []) -> void:
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_CARD
	box.shadow_size = UiTokens.SIZE_SHADOW_CARD_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_CARD_OFFSET_Y)
	add_theme_stylebox_override(&"panel", box.with_margins(_PAD.x, _PAD.y, _PAD.x, _PAD.y))
	custom_minimum_size.x = UiTokens.SIZE_TODAY_PANEL_W
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", _ROW_SEP)
	add_child(_list)
	set_rows(rows)

func set_rows(rows: Array) -> void:
	for c in _list.get_children(): c.free()
	var n := mini(rows.size(), MAX_ROWS)
	for i in n:
		if i > 0: _list.add_child(_divider())
		_list.add_child(_row(rows[i], i))

func row_count() -> int:
	return _list.get_children().filter(func(c): return c is HBoxContainer).size()

static func _divider() -> ColorRect:
	var d := ColorRect.new()
	d.color = UiTokens.COLOR_BORDER
	d.custom_minimum_size.y = UiTokens.STROKE_DEFAULT
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

func _row(r: Dictionary, index: int) -> HBoxContainer:
	var state := str(r.get("state", "default"))
	var done := state == "done"
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", _ROW_GAP)
	row.custom_minimum_size.y = UiTokens.SIZE_TODAY_ROW_H
	if done: row.modulate.a = UiTokens.OPACITY_TODAY_DONE
	var icon := UiKit.icon(r.get("icon", null), UiTokens.SIZE_TODAY_ICON)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 0)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var line := UiKit.label(str(r.get("line", "")), UiTokens.STYLE_BODY_XB14, UiTokens.COLOR_SECONDARY if done else UiTokens.COLOR_TEXT)
	# TUT-3-03B (1410:104474; 不知火舞 on SGODOT-232): the sentence wraps to two lines next to a wide pill such as
	# Show on map and the row grows with it; only a third line is cut with an ellipsis. The pill stays centred.
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.max_lines_visible = 2
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(line)
	if state == "short" and str(r.get("tail", "")) != "":
		var tail := UiKit.label(str(r.tail), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		tail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(tail)
	row.add_child(text)
	if done:
		var tick := Panel.new()
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tick.custom_minimum_size = Vector2(_DONE_CHECK, _DONE_CHECK)
		tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tick.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY, _DONE_CHECK * 0.5))
		var glyph := UiKit.icon(CHECK_GLYPH, _DONE_CHECK * 0.5)
		glyph.position = Vector2(_DONE_CHECK, _DONE_CHECK) * 0.25
		glyph.size = Vector2(_DONE_CHECK, _DONE_CHECK) * 0.5
		glyph.self_modulate = UiTokens.COLOR_SURFACE_RAISED
		tick.add_child(glyph)
		row.add_child(tick)
	elif str(r.get("action", "")) != "":
		var pill := UiShowPill.new(str(r.action), UiShowPill.Kind.TODAY)   # 55 × 28 like the main, 44 to the touch
		pill.pressed.connect(func(): show_pressed.emit(index))
		row.add_child(pill)
	return row
