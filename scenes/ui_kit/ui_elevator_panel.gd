class_name UiElevatorPanel
extends PanelContainer
## ElevatorPanel 1230:107860 with ElevatorRow 1230:107859 (Locked · LOCK-21, SGODOT-231 / 235 B3): the small card
## above the elevator key, opened with Elevator · Free. A 12 ExtraBold title (`Elevator · stops this run`), then one
## 44 row per stop, floor name left and its state right:
##   HERE     current stop, primary-tint row, both ExtraBold, state in secondary; not tappable
##   FREE     paid this run, state in primary green; travels at no Energy
##   COST     an unpaid floor's fee (`2 Energy`), both in text ink
##   LOCKED   `Clear Floor 1 first` / `Bag full`, both in secondary; still takes the tap and says why (LOCK-10)
##   SHORT    `Need 2 Energy`, state in warning amber; opens the Energy card
##   EXPRESS  `Floor 5 · Express · Free` (P1), state in primary green
## Width 280 (rows 264), padding 10 / 8 / 8, gaps 2, row radius 10. The panel only lays the rows out: a tap on a row
## emits `row_pressed(index)`, a LOCKED row `unavailable_pressed(index)`; the owner travels, opens the card or toasts.

signal row_pressed(index: int)
signal unavailable_pressed(index: int)

enum State { HERE, FREE, COST, LOCKED, SHORT, EXPRESS }

const WIDTH := 280.0
const _ROW_H := 44.0
const _ROW_PAD := 12.0
const _ROW_RADIUS := 10.0
const _RADIUS := 16.0
const _PAD := Vector4(8, 10, 8, 8)   # left, top, right, bottom
const _GAP := 2
const _SHADOW := UiTokens.COLOR_SHADOW_CARD   # 0 4 8 rgba(46,59,51,0.16)
const _SHADOW_SIZE := 8
const _SHADOW_Y := 4.0

var title := "": set = set_title
## [{floor: String, value: String, state: State}]
var rows: Array = []: set = set_rows

var _title: Label
var _rows: VBoxContainer

func _init(title_ := "", rows_: Array = []) -> void:
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = _SHADOW
	box.shadow_size = _SHADOW_SIZE
	box.shadow_offset = Vector2(0, _SHADOW_Y)
	add_theme_stylebox_override(&"panel", box.with_margins(_PAD.x, _PAD.y, _PAD.z, _PAD.w))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", _GAP)
	add_child(col)
	_title = UiKit.label("", UiTokens.STYLE_C12_XB, UiTokens.COLOR_SECONDARY)
	col.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", _GAP)
	col.add_child(_rows)
	title = title_
	rows = rows_

func set_title(v: String) -> void:
	title = v
	if _title != null:
		_title.text = v
		_title.visible = v != ""

func set_rows(v: Array) -> void:
	rows = v
	if _rows == null: return
	for c in _rows.get_children(): c.queue_free()
	for i in v.size(): _rows.add_child(_row(i, v[i]))

func row(i: int) -> Button: return _rows.get_child(i) as Button if i < _rows.get_child_count() else null

func _row(i: int, r: Dictionary) -> Button:
	var state: State = int(r.get("state", State.FREE))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, _ROW_H)
	var here := state == State.HERE
	var flat := UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT if here else Color.TRANSPARENT, _ROW_RADIUS)
	var down := UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT if here else UiTokens.COLOR_SURFACE, _ROW_RADIUS)
	for s in [&"normal", &"hover", &"focus", &"disabled"]: b.add_theme_stylebox_override(s, flat)
	b.add_theme_stylebox_override(&"pressed", down)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = _ROW_PAD
	h.offset_right = -_ROW_PAD
	b.add_child(h)
	var name_color: Color = UiTokens.COLOR_SECONDARY if state == State.LOCKED else UiTokens.COLOR_TEXT
	var floor_l := UiKit.label(str(r.get("floor", "")), UiTokens.STYLE_C13_XB if here else UiTokens.STYLE_C13_B, name_color)
	floor_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	floor_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(floor_l)
	var value_color: Color = {State.HERE: UiTokens.COLOR_SECONDARY, State.FREE: UiTokens.COLOR_PRIMARY,
		State.EXPRESS: UiTokens.COLOR_PRIMARY, State.COST: UiTokens.COLOR_TEXT, State.LOCKED: UiTokens.COLOR_SECONDARY,
		State.SHORT: UiTokens.COLOR_WARNING}[state]
	var value_l := UiKit.label(str(r.get("value", "")), UiTokens.STYLE_C12_XB, value_color)
	value_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(value_l)
	if here: b.mouse_filter = Control.MOUSE_FILTER_IGNORE   # Here is not tappable
	else: b.pressed.connect(func(): (unavailable_pressed if state == State.LOCKED else row_pressed).emit(i))
	return b
