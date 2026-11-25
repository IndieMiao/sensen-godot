class_name UiTaskRow
extends Button
## UI v3 task row (C-107; C-84 C-M3 in the phone, C-T1 in the HUD's task drop-down): a Ø20 check circle, 6 before a
## pill with the task's `type/caption` line and an optional short count at its right.
##   PHONE  pill 28 high on `phone/row`, `phone/text`; the current task's circle and pill carry an `action/primary`
##          ring (the pill's at 70 %); done: a ✓, a line through and `phone/textMuted`
##   GLASS  pill 24 high on `glass/fillStrong`, white; done: a ✓, a line through and `text/onDarkMuted`
## complete() plays the design's finishing beat (C-85 ⑧ motion 2): the circle pops 0.6 → 1 with its ✓ (200, back
## out), the line draws left to right (200), then the text greys (120). Emits `pressed` like any Button; rows that are
## not `tappable` let touches through to what is under them. A `link` row (the drop-down's `More…`) has no circle and
## its text in `action/selected`.

enum Look { PHONE, GLASS }
enum State { TODO, CURRENT, DONE }

const _CHECK := 20.0
const _RING := 2.0
const _PILL_RING := 1.5
const _PILL_RING_ALPHA := 0.7
const _TICK_STROKE := 2.0
const _STRIKE := 1.5
const _POP_FROM := 0.6

var look: Look = Look.PHONE
var state: State = State.TODO: set = set_state
var title := "": set = set_title
## A short count at the pill's right (`0/1`), "" for none.
var count := "": set = set_count
var tappable := true: set = set_tappable
var link := false: set = set_link

var _row: HBoxContainer
var _check: _Check
var _pill: PanelContainer
var _label: Label
var _count: Label
var _strike: _Strike

func _init(title_ := "", state_: State = State.TODO, look_: Look = Look.PHONE) -> void:
	look = look_
	focus_mode = Control.FOCUS_NONE
	flat = true
	for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	custom_minimum_size.y = UiTokens.SIZE_PHONE_ROW_H if look == Look.PHONE else UiTokens.SIZE_TODO_ROW_H
	var row := HBoxContainer.new()
	_row = row
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S3))
	add_child(row)
	_check = _Check.new()
	_check.row = self
	_check.custom_minimum_size = Vector2.ONE * _CHECK
	_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_check)
	_pill = PanelContainer.new()
	_pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_pill)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", int(UiTokens.SPACE_S3))
	_pill.add_child(line)
	var style := UiTokens.STYLE_TYPE_CAPTION if look == Look.PHONE else UiTokens.STYLE_TYPE_CAPTION_ON_DARK
	_label = UiKit.label("", style)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if look == Look.PHONE:
		# The phone's pill spans the page and cuts a long line with …; the drop-down's pill hugs its text.
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_label.clip_text = true
	else:
		_pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row.minimum_size_changed.connect(_hug)
	line.add_child(_label)
	_count = UiKit.label("", style)
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.visible = false
	line.add_child(_count)
	_strike = _Strike.new()
	_strike.row = self
	_strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_child(_strike)
	UiMotion.press_feedback(self)
	title = title_
	state = state_
	_restyle()

func _ready() -> void:
	_hug()

## The drop-down's row is as wide as its circle and pill.
func _hug() -> void:
	if look == Look.GLASS: custom_minimum_size.x = _row.get_combined_minimum_size().x

func set_title(v: String) -> void:
	title = v
	if _label != null:
		_label.text = v
		_strike.queue_redraw()

func set_count(v: String) -> void:
	count = v
	if _count != null:
		_count.text = v
		_count.visible = not v.is_empty()

func set_tappable(v: bool) -> void:
	tappable = v
	mouse_filter = Control.MOUSE_FILTER_STOP if v else Control.MOUSE_FILTER_IGNORE

func set_link(v: bool) -> void:
	link = v
	if _check != null: _restyle()

func set_state(v: State) -> void:
	state = v
	if _check == null: return
	_check.pop = 1.0
	_strike.progress = 1.0 if v == State.DONE else 0.0
	_restyle()

func label() -> Label: return _label
func pill() -> PanelContainer: return _pill
## How much of the line through is drawn (0 … 1); 1 for a done row once its beat has played.
func strike_progress() -> float: return _strike.progress

## The finishing beat (C-85 ⑧ 2): the row turns done with the circle's pop, the line drawn across, then the grey.
## Reduced motion (UiMotion.reduced): the done look fades in over 120.
func complete() -> void:
	if state == State.DONE or not is_inside_tree():
		state = State.DONE
		return
	state = State.DONE
	var ms := UiTokens.MOTION_DURATION_BASE_MS
	if UiMotion.reduced:
		modulate.a = 0.0
		var fade := UiMotion.tween(self, UiTokens.MOTION_EASING_LINEAR)
		fade.tween_property(self, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		return
	_check.pop = _POP_FROM
	_strike.progress = 0.0
	_tint(_on_colour())
	var tw := UiMotion.tween(self, UiTokens.MOTION_EASING_POP)
	tw.tween_property(_check, "pop", 1.0, UiMotion.secs(ms))
	tw.parallel().tween_property(_strike, "progress", 1.0, UiMotion.secs(ms)).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(t: float): _tint(_on_colour().lerp(_muted_colour(), t)), 0.0, 1.0,
		UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS)).set_trans(Tween.TRANS_LINEAR)

func _on_colour() -> Color:
	if link: return UiTokens.COLOR_ACTION_SELECTED
	return UiTokens.COLOR_PHONE_TEXT if look == Look.PHONE else UiTokens.COLOR_TEXT_ON_DARK

func _muted_colour() -> Color:
	return UiTokens.COLOR_PHONE_TEXT_MUTED if look == Look.PHONE else UiTokens.COLOR_TEXT_ON_DARK_MUTED

func _tint(c: Color) -> void:
	_label.add_theme_color_override(&"font_color", c)
	_count.add_theme_color_override(&"font_color", UiTokens.COLOR_PHONE_TEXT_MUTED if look == Look.PHONE else c)
	_strike.colour = c
	_strike.queue_redraw()

func _restyle() -> void:
	var fill := UiTokens.COLOR_PHONE_ROW if look == Look.PHONE else UiTokens.COLOR_GLASS_FILL_STRONG
	var box := UiStyleBox.make(fill, UiTokens.RADIUS_PILL).with_margins(UiTokens.SPACE_S5 - UiTokens.SPACE_S1, 0,
		UiTokens.SPACE_S5 - UiTokens.SPACE_S1, 0)
	if look == Look.PHONE and state == State.CURRENT:
		box.border_color = UiKit.alpha(UiTokens.COLOR_ACTION_PRIMARY, _PILL_RING_ALPHA)
		box.border_width = _PILL_RING
	_pill.add_theme_stylebox_override(&"panel", box)
	_tint(_muted_colour() if state == State.DONE else _on_colour())
	_check.queue_redraw()

## The check circle: its fill, the current task's ring and a done task's ✓, drawn scaled by `pop` (a Container would
## reset a scale set on the node).
class _Check extends Control:
	var row: UiTaskRow
	var pop := 1.0:
		set(v):
			pop = v
			queue_redraw()

	func _draw() -> void:
		if row.link: return
		var c := size * 0.5
		var r := UiTaskRow._CHECK * 0.5 * pop
		var fill := UiTokens.COLOR_PHONE_ROW if row.look == UiTaskRow.Look.PHONE else UiTokens.COLOR_GLASS_FILL_STRONG
		draw_circle(c, r, fill, true, -1.0, true)
		if row.state == UiTaskRow.State.CURRENT and row.look == UiTaskRow.Look.PHONE:
			draw_circle(c, r - UiTaskRow._RING * 0.5, UiTokens.COLOR_ACTION_PRIMARY, false, UiTaskRow._RING, true)
		if row.state == UiTaskRow.State.DONE:
			var s := r / (UiTaskRow._CHECK * 0.5)
			var tick := PackedVector2Array([c + Vector2(-4.5, 0.5) * s, c + Vector2(-1.5, 3.5) * s, c + Vector2(4.5, -3.5) * s])
			draw_polyline(tick, UiTokens.COLOR_TEXT_ON_DARK, UiTaskRow._TICK_STROKE, true)

## The line through a done task's text, across the text's own width, drawn `progress` of the way from the left.
class _Strike extends Control:
	var row: UiTaskRow
	var colour := Color.TRANSPARENT
	var progress := 0.0:
		set(v):
			progress = v
			queue_redraw()

	func _draw() -> void:
		if progress <= 0.0: return
		var text := row.label()
		var width := minf(text.get_theme_font(&"font").get_string_size(text.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			text.get_theme_font_size(&"font_size")).x, text.size.x)
		var y := text.position.y + text.size.y * 0.5 + UiTaskRow._STRIKE * 0.5
		var from := Vector2(text.position.x, y)
		draw_line(from, from + Vector2(width * progress, 0), colour, UiTaskRow._STRIKE, true)
