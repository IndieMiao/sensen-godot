class_name UiTodayPanel
extends PanelContainer
## Today panel (SGODOT-222; Gensen Refactor/TodayPanel 1145:81715 + TodayRow 1145:81714, LOCK-06): a small
## panel right under the two HUD chips (x 10, y 96, 340 wide), as tall as its first 5 rows; more scroll inside it (A 包反馈 2,
## 不知火舞's spec ②: a 16 px fade at an edge with rows past it, a 3 px bar at the right, a drag scrolls — never a Show,
## even begun on one). Never a bottom sheet, never over the quick bar or main key; the host closes it on a tap outside.
## An `empty` row (nothing taken, P0Logic.TODAY_EMPTY) is grey and has no button.
## A row is {icon, line, tail?, action?, state?}: icon + one sentence + an optional Show pill that only moves
## the camera (LOCK-08). state "done" = tick, faded, secondary ink; "short" = grey tail line with the Energy
## it needs and when it comes back. Emits `show_pressed(index)`. A row with `tap` and no Show (q(104): a request whose
## fish the player cannot land yet, its tail `Fishing Lv4 needed`) takes a tap on the whole row: `row_pressed(index)`.

signal show_pressed(index: int)
signal row_pressed(index: int)

const VISIBLE_ROWS := 5   # the panel holds this many; the rest scroll (spec ②)
const _FADE := 16          # px of fade at an edge with rows past it
const _BAR_W := 3          # the scroll bar, 4 px in from the panel's inner edge
const _BAR_INSET := 4
const _COAST := 0.92       # a drag's speed kept each frame after the finger lifts (the inertia)
const CHECK_GLYPH := preload("res://assets/ui/kit_icons/check.svg")

const _PAD := Vector2(12, 8)       # TodayPanel main padding
const _ROW_GAP := 8                # TodayRow icon → text → pill
const _DONE_CHECK := 18            # Done row tick disc
const _ROW_SEP := 2                # rows and dividers

var _list: VBoxContainer
var _scroll: ScrollContainer
var _over: Control          # the fades and the bar, over the rows
var _fade_top: TextureRect
var _fade_bottom: TextureRect
var _bar: Panel
var _structure: Array = []
var _press := Vector2.INF   # where a press in the panel began (global), while it is down
var _dragging := false      # it moved past TAP_SLOP: it scrolls, and no Show fires on its release
var _speed := 0.0           # px a frame, coasting after a drag
var _refit := false         # measure the first five again once the list has laid them out (_process)

func _init(rows: Array = []) -> void:
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_CARD
	box.shadow_size = UiTokens.SIZE_SHADOW_CARD_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_CARD_OFFSET_Y)
	add_theme_stylebox_override(&"panel", box.with_margins(_PAD.x, _PAD.y, _PAD.x, _PAD.y))
	custom_minimum_size.x = UiTokens.SIZE_TODAY_PANEL_W
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED   # SHOW_NEVER once rows pass VISIBLE_ROWS (_fit)
	add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", _ROW_SEP)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_over = Control.new()
	_over.name = "Over"
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_over)
	_fade_top = _fade(true)
	_fade_bottom = _fade(false)
	_bar = Panel.new()
	_bar.name = "Bar"
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_BORDER, _BAR_W * 0.5))
	_over.add_child(_bar)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v): _mark())
	_scroll.resized.connect(_mark)
	_list.resized.connect(func(): _refit = true)   # a line wrapped: the first five measured again
	set_rows(rows)

func set_rows(rows: Array) -> void:
	# A clock tick changes only text. Keep Show pills alive so it cannot cancel a press begun just before the tick; the
	# scroll stays where it is (spec ②: a row done or replaced keeps the place).
	var structure := rows.map(func(r): return [r.get("icon"), r.get("state", "default"), r.get("action", ""),
		bool(r.get("tap", false)), str(r.get("state", "")) == "short" and str(r.get("tail", "")) != "", bool(r.get("empty", false))])
	if structure == _structure and _list.get_child_count() > 0:
		for i in rows.size():
			var row := _list.get_child(i * 2)
			_set_line(row.find_child("Line", true, false), rows[i])
			var tail := row.find_child("Tail", true, false) as Label
			if tail != null: tail.text = str(rows[i].get("tail", ""))
		return
	_structure = structure
	for c in _list.get_children(): c.free()
	for i in rows.size():
		if i > 0: _list.add_child(_divider())
		_list.add_child(_row(rows[i], i))
	_refit = true

## The panel as tall as its first VISIBLE_ROWS rows (each as tall as its lines make it, dividers between); taller lists
## scroll inside it. Fewer rows: as tall as they are, nothing scrolls.
func _fit() -> bool:
	if not is_instance_valid(_list): return true
	var rows := _list.get_children().filter(func(c): return c is HBoxContainer)
	if rows.size() > VISIBLE_ROWS and (rows[VISIBLE_ROWS - 1] as Control).position.y <= 0.0: return false   # not laid out yet
	if rows.size() <= VISIBLE_ROWS:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.custom_minimum_size.y = 0
	else:
		var last: Control = rows[VISIBLE_ROWS - 1]
		_scroll.custom_minimum_size.y = last.position.y + last.size.y
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_mark()
	return true

## Rows past the top or the bottom: that edge fades; the bar shows where the view is in the list.
func _mark() -> void:
	if not is_instance_valid(_over): return
	var view_h := _scroll.size.y
	var list_h := _list.size.y
	var at := float(_scroll.scroll_vertical)
	var scrolls := _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED and list_h > view_h + 0.5
	_fade_top.visible = scrolls and at > 0.5
	_fade_bottom.visible = scrolls and at < list_h - view_h - 0.5
	_bar.visible = scrolls
	var top := _scroll.position.y
	for f in [_fade_top, _fade_bottom]:
		(f as TextureRect).position.x = _scroll.position.x
		(f as TextureRect).size = Vector2(_scroll.size.x, _FADE)
	_fade_top.position.y = top
	_fade_bottom.position.y = top + view_h - _FADE
	if scrolls:
		var h := maxf(12.0, view_h * view_h / list_h)
		_bar.size = Vector2(_BAR_W, h)
		_bar.position = Vector2(size.x - _BAR_INSET - _BAR_W, top + (view_h - h) * at / maxf(1.0, list_h - view_h))

func scrolls() -> bool:
	return _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED

func _fade(top: bool) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, UiTokens.COLOR_SURFACE)
	g.set_color(1, Color(UiTokens.COLOR_SURFACE, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0) if top else Vector2(0, 1)
	tex.fill_to = Vector2(0, 1) if top else Vector2(0, 0)
	tex.width = 4
	tex.height = _FADE
	var r := TextureRect.new()
	r.name = "FadeTop" if top else "FadeBottom"
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	_over.add_child(r)
	return r

## A drag in the panel scrolls it, with a coast after the finger lifts; past TAP_SLOP it is a drag, so a Show pill it
## began on does not fire (spec ②). Read here, ahead of the rows and pills, so a drag on a pill scrolls too.
func _input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not scrolls(): return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and get_global_rect().has_point(e.position):
			_press = e.position
			_dragging = false
			_speed = 0.0
		elif not e.pressed and _press != Vector2.INF:
			_press = Vector2.INF
			if _dragging: _end_drag.call_deferred()   # after the pill's own release, which reads _dragging
	elif e is InputEventMouseMotion and _press != Vector2.INF:
		if not _dragging and e.position.distance_to(_press) > GestureArbiter.TAP_SLOP: _dragging = true
		if _dragging:
			_speed = -e.relative.y
			_scroll.scroll_vertical = int(_scroll.scroll_vertical - e.relative.y)

func _end_drag() -> void:
	_dragging = false

func _process(_dt: float) -> void:
	if _refit and _fit(): _refit = false
	if _press == Vector2.INF and absf(_speed) > 0.5:
		_scroll.scroll_vertical = int(_scroll.scroll_vertical + _speed)
		_speed *= _COAST
	elif _press == Vector2.INF:
		_speed = 0.0

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
	var grey := done or bool(r.get("empty", false))   # spec ①: nothing taken is a grey line, no button
	var line := UiKit.label(str(r.get("line", "")), UiTokens.STYLE_BODY_XB14, UiTokens.COLOR_SECONDARY if grey else UiTokens.COLOR_TEXT)
	# TUT-3-03B (1410:104474; 不知火舞 on SGODOT-232): the sentence wraps to two lines next to a wide pill such as
	# Show on map and the row grows with it; only a third line is cut with an ellipsis. The pill stays centred.
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.max_lines_visible = 2
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Two lines break at a " · " (不知火舞 on #201): `Catch 2 Pond Crucian` / `Fern Pond`, not `… Crucian ·` / `Fern Pond`.
	line.name = "Line"
	line.set_meta("row", r)
	line.set_meta("sentence", str(r.get("line", "")))
	line.resized.connect(func(): _set_line(line, line.get_meta("row", {})))
	text.add_child(line)
	if state == "short" and str(r.get("tail", "")) != "":
		var tail := UiKit.label(str(r.tail), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
		tail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tail.name = "Tail"
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
	elif str(r.get("action", "")) != "" and not bool(r.get("empty", false)):
		var pill := UiShowPill.new(str(r.action), UiShowPill.Kind.TODAY)   # 55 × 28 like the main, 44 to the touch
		pill.pressed.connect(func(): if not _dragging: show_pressed.emit(index))   # a drag begun on it only scrolls
		row.add_child(pill)
	# a row with `tap` takes a tap anywhere off its Show pill (spec ③ v3: Pip's Homestead request opens HOME-1, its Show
	# still moves the camera); a drag in a scrolling panel is never a tap
	if bool(r.get("tap", false)) and not done and not bool(r.get("empty", false)):
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var down := [Vector2.INF]
		row.gui_input.connect(func(e: InputEvent):   # a tap, not a drag (touch arrives as the emulated mouse)
			if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT): return
			row.accept_event()
			if e.pressed: down[0] = e.position
			elif down[0] != Vector2.INF and e.position.distance_to(down[0]) <= GestureArbiter.TAP_SLOP and not _dragging:
				down[0] = Vector2.INF
				row_pressed.emit(index))
	return row

## A row's sentence as its line shows it, measured at the line's width: two lines break at a " · " (UiKit.break_at_dot);
## a row that ends with its city (`city`, q(276)) breaks only before it, the dot dropped and the city whole on a line of
## its own — the need's name dropped (`line_short`) only when the first line still runs long; a first line long even so
## wraps by words (the label takes a third line: a square's name is never cut, the city never shortened).
static func _set_line(line: Label, r: Dictionary) -> void:
	line.set_meta("row", r)
	line.set_meta("sentence", str(r.get("line", "")))
	var font := line.get_theme_font(&"font")
	var size := line.get_theme_font_size(&"font_size")
	var city := str(r.get("city", ""))
	var shown := UiKit.break_at_dot(str(r.get("line", "")), font, size, line.size.x) if city == "" \
		else city_lines(str(r.get("line", "")), str(r.get("line_short", "")), city, font, size, line.size.x)
	line.max_lines_visible = 2 if city == "" else 3
	if line.text != shown: line.text = shown

## q(276): `sentence` (` · <city>` at its end) in `width` — as it is when it fits; else broken before the city, the dot
## dropped (`Pond Catch · Pond Crucian 1/2` / `Rio de Janeiro`); `short` (the same without the need's name) taking the
## first line's place when that still runs long (`Big Market Order · 1/2` / `Mexico City`).
static func city_lines(sentence: String, short: String, city: String, font: Font, size: int, width: float) -> String:
	if font == null or width <= 0.0: return sentence
	var fits := func(t: String) -> bool: return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width
	if fits.call(sentence): return sentence
	var tail := " · " + city
	var first := sentence.trim_suffix(tail)
	if not fits.call(first) and short != "": first = short.trim_suffix(tail)
	return first + "\n" + city
