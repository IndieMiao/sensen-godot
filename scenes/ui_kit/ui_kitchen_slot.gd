class_name UiKitchenSlot
extends Control
## Compact/Kitchen/Slot 655:58505 (SGODOT-226, LOCK-20): one ingredient slot of the slot bar under the 3D pot.
## 90×50: a 32 px ring (filled: surface + 1.2 primary stroke and the ingredient icon; empty: dashed border and
## a plus; locked: border fill, dashed, lock glyph), a 90×16 name pill under it and, when filled, a ×N pill.
## Tapping a filled slot sends that ingredient back to the bag (`tapped`); empty and locked slots do nothing
## (the locked one says what opens it on its label, LOCK-10).

signal tapped

enum State { FILLED, EMPTY, LOCKED }

const _W := 90.0
const _RING := 32.0
const _RING_X := 29.0
const _ICON := 20.0
const _LOCK := 10.0
const _PLUS := 14.0
const _PLUS_BAR := 2.0
const _LABEL_Y := 34.0
const _LABEL_H := 16.0
const _QTY_X := 55.0
const _QTY_Y := 20.0
const _QTY := Vector2(20, 13)
const _RING_STROKE := 1.2
const _DASHED_STROKE := 0.7
const LOCK_GLYPH := preload("res://assets/ui/kit_icons/lock.svg")

var state: State = State.EMPTY: set = set_state
var icon: Texture2D: set = set_icon
var title := "": set = set_title
var quantity := "": set = set_quantity

var _ring: Panel
var _icon: TextureRect
var _plus: Control
var _label_pill: Panel
var _label: Label
var _qty_pill: Panel
var _qty: Label

func _init(state_: State = State.EMPTY) -> void:
	custom_minimum_size = Vector2(_W, _LABEL_Y + _LABEL_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ring = Panel.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.position = Vector2(_RING_X, 0)
	_ring.size = Vector2(_RING, _RING)
	add_child(_ring)
	_icon = UiKit.icon(null, _ICON)
	_ring.add_child(_icon)
	_plus = Control.new()
	_plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plus.size = Vector2(_PLUS, _PLUS)
	_plus.position = (Vector2(_RING, _RING) - _plus.size) * 0.5
	for r in [Rect2((_PLUS - _PLUS_BAR) * 0.5, 0, _PLUS_BAR, _PLUS), Rect2(0, (_PLUS - _PLUS_BAR) * 0.5, _PLUS, _PLUS_BAR)]:
		var bar := ColorRect.new()
		bar.color = UiTokens.COLOR_SECONDARY
		bar.position = r.position
		bar.size = r.size
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_plus.add_child(bar)
	_ring.add_child(_plus)
	_label_pill = Panel.new()
	_label_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_pill.position = Vector2(0, _LABEL_Y)
	_label_pill.size = Vector2(_W, _LABEL_H)
	_label_pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, _LABEL_H * 0.5))
	add_child(_label_pill)
	_label = UiKit.label("", UiTokens.STYLE_C10_B)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_label.clip_text = true
	_label.position = Vector2(2, 0)
	_label.size = Vector2(_W - 4, _LABEL_H)
	_label_pill.add_child(_label)
	_qty_pill = Panel.new()
	_qty_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty_pill.position = Vector2(_QTY_X, _QTY_Y)
	_qty_pill.size = _QTY
	_qty_pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, _QTY.y * 0.5))
	add_child(_qty_pill)
	_qty = UiKit.label("", UiTokens.STYLE_C10_XB)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_qty.size = _QTY
	_qty_pill.add_child(_qty)
	state = state_

func set_state(v: State) -> void: state = v; _refresh()
func set_icon(v: Texture2D) -> void: icon = v; _refresh()
func set_title(v: String) -> void: title = v; _refresh()
func set_quantity(v: String) -> void: quantity = v; _refresh()

## Screen point where an ingredient leaves from / lands back on this slot (the ring's centre).
func ring_center() -> Vector2:
	return get_global_rect().position + Vector2(_RING_X + _RING * 0.5, _RING * 0.5)

func _refresh() -> void:
	if _label == null: return
	var box: UiStyleBox
	match state:
		State.FILLED: box = UiStyleBox.make(UiTokens.COLOR_SURFACE, _RING * 0.5, UiTokens.COLOR_PRIMARY, _RING_STROKE)
		State.EMPTY: box = UiStyleBox.make(UiTokens.COLOR_SURFACE, _RING * 0.5, UiTokens.COLOR_BORDER, _DASHED_STROKE)
		State.LOCKED: box = UiStyleBox.make(UiTokens.COLOR_BORDER, _RING * 0.5, UiTokens.COLOR_BORDER, _DASHED_STROKE)
	if state != State.FILLED:
		box.dashed = true
		box.dash = UiTokens.DASH_KITCHEN[0]
		box.gap = UiTokens.DASH_KITCHEN[1]
	_ring.add_theme_stylebox_override(&"panel", box)
	var side := _LOCK if state == State.LOCKED else _ICON
	_icon.custom_minimum_size = Vector2(side, side)
	_icon.size = Vector2(side, side)
	_icon.position = (Vector2(_RING, _RING) - _icon.size) * 0.5
	_icon.texture = LOCK_GLYPH if state == State.LOCKED else icon
	_icon.self_modulate = UiTokens.COLOR_SECONDARY if state == State.LOCKED else Color.WHITE
	_icon.visible = state != State.EMPTY and _icon.texture != null
	_plus.visible = state == State.EMPTY
	_label.text = title
	_label.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY if state == State.LOCKED else UiTokens.COLOR_TEXT)
	_qty.text = quantity
	_qty_pill.visible = state == State.FILLED and quantity != ""

func _gui_input(e: InputEvent) -> void:
	var up: bool = (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed)
	if up and state == State.FILLED:
		accept_event()
		tapped.emit()
