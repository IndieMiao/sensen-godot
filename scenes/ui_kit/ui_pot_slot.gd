class_name UiPotSlot
extends Control
## PotSlot44 1913:32881 (SGODOT-256 ⑤ A', LOCK-20): one slot of the pot card under the 3D pot. The ingredient reads by
## its icon; no name under it (names stay in the bag grid and the detail card). A 44 circle, also the tap size, the
## icon 32 in the middle: filled is surface-raised with a 1.5 primary stroke; empty a 1.5 dashed border; locked the
## border colour with only the 16 px lock. Filled may carry ×N at the bottom right (C11 ExtraBold, its pill 2 past the
## circle's foot and 6 past its right) and the remove ✕ 18 at the top right (centred on the 45° point, tap area 44). No
## Rack tag here: where a seasoning came from shows on its bag cell (不知火舞 on 256). `point_at_remove` draws the
## gold-brown ring round ✕ (the pot is full, q(64)). A tap on a filled slot or its ✕ emits `tapped` (back to the bag); on the
## locked one `locked_tapped` (the owner says what opens it in a toast). Slots in the card are 20 apart, so ✕ and ×N
## never touch the next one.

signal tapped
signal locked_tapped

enum State { FILLED, EMPTY, LOCKED }

const SIZE := 44.0
const _ICON := 32.0
const _LOCK := 16.0
const _STROKE := 1.5
const _QTY := Rect2(26, 30, 24, 16)
const _QTY_PAD := 4.0
const _REMOVE := Rect2(29, -3, 18, 18)
const _REMOVE_HIT := 44.0
const _RING := Rect2(25, -7, 26, 26)
const _RING_STROKE := 2.0
const _EDGE := 1.5                 # the surface ring that lifts ×N and ✕ off the circle
const LOCK_GLYPH := preload("res://assets/ui/kit_icons/lock.svg")

var state: State = State.EMPTY: set = set_state
var icon: Texture2D: set = set_icon
## "×1"; "" hides it.
var quantity := "": set = set_quantity
var removable := false: set = set_removable
var point_at_remove := false: set = set_point_at_remove

var _circle: Panel
var _icon: TextureRect
var _qty_pill: PanelContainer
var _qty: Label
var _remove: Panel
var _remove_hit: Control
var _ring: Panel

func _init(state_: State = State.EMPTY) -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_circle = Panel.new()
	_circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_circle.size = Vector2(SIZE, SIZE)
	add_child(_circle)
	_icon = UiKit.icon(null, _ICON)
	_circle.add_child(_icon)
	_qty_pill = PanelContainer.new()
	_qty_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty_pill.position = _QTY.position
	_qty_pill.custom_minimum_size = _QTY.size
	_qty_pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, _QTY.size.y * 0.5, UiTokens.COLOR_SURFACE, _EDGE)
		.with_margins(_QTY_PAD, 0.0, _QTY_PAD, 0.0))
	add_child(_qty_pill)
	_qty = UiKit.label("", UiTokens.STYLE_C11_XB)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_qty_pill.add_child(_qty)
	_ring = Panel.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.position = _RING.position
	_ring.size = _RING.size
	_ring.add_theme_stylebox_override(&"panel", UiStyleBox.make(Color.TRANSPARENT, _RING.size.x * 0.5, UiTokens.COLOR_WARNING, _RING_STROKE))
	add_child(_ring)
	_remove = Panel.new()
	_remove.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_remove.position = _REMOVE.position
	_remove.size = _REMOVE.size
	_remove.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_TEXT, _REMOVE.size.x * 0.5, UiTokens.COLOR_SURFACE, _EDGE))
	add_child(_remove)
	var x := UiKit.label("×", UiTokens.STYLE_C13_XB, UiTokens.COLOR_SURFACE)
	x.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	x.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	x.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_remove.add_child(x)
	# ✕'s own 44 tap area, centred on it; it reaches past the slot's box, which does not clip input.
	_remove_hit = Control.new()
	_remove_hit.mouse_filter = Control.MOUSE_FILTER_STOP
	_remove_hit.size = Vector2(_REMOVE_HIT, _REMOVE_HIT)
	_remove_hit.position = _REMOVE.get_center() - _remove_hit.size * 0.5
	_remove_hit.gui_input.connect(_on_input)
	add_child(_remove_hit)
	state = state_

func set_state(v: State) -> void: state = v; _refresh()
func set_icon(v: Texture2D) -> void: icon = v; _refresh()
func set_quantity(v: String) -> void: quantity = v; _refresh()
func set_removable(v: bool) -> void: removable = v; _refresh()
func set_point_at_remove(v: bool) -> void: point_at_remove = v; _refresh()

## Screen point where an ingredient leaves from / lands back on this slot (the circle's centre).
func ring_center() -> Vector2:
	return get_global_rect().position + Vector2(SIZE, SIZE) * 0.5

func remove_rect() -> Rect2: return Rect2(_remove.position, _remove.size)
func remove_hit_rect() -> Rect2: return Rect2(_remove_hit.position, _remove_hit.size)

func _refresh() -> void:
	if _circle == null: return
	var filled := state == State.FILLED
	var box: UiStyleBox
	match state:
		State.FILLED: box = UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, SIZE * 0.5, UiTokens.COLOR_PRIMARY, _STROKE)
		State.EMPTY:
			box = UiStyleBox.make(Color.TRANSPARENT, SIZE * 0.5, UiTokens.COLOR_BORDER, _STROKE)
			box.dashed = true
			box.dash = UiTokens.DASH_KITCHEN[0]
			box.gap = UiTokens.DASH_KITCHEN[1]
		State.LOCKED: box = UiStyleBox.make(UiTokens.COLOR_BORDER, SIZE * 0.5)
	_circle.add_theme_stylebox_override(&"panel", box)
	var side := _LOCK if state == State.LOCKED else _ICON
	_icon.custom_minimum_size = Vector2(side, side)
	_icon.size = Vector2(side, side)
	_icon.position = (Vector2(SIZE, SIZE) - _icon.size) * 0.5
	_icon.texture = LOCK_GLYPH if state == State.LOCKED else icon
	_icon.self_modulate = UiTokens.COLOR_SECONDARY if state == State.LOCKED else Color.WHITE
	_icon.visible = state != State.EMPTY and _icon.texture != null
	_qty.text = quantity
	_qty_pill.visible = filled and quantity != ""
	_remove.visible = filled and removable
	_remove_hit.visible = _remove.visible
	_ring.visible = _remove.visible and point_at_remove
	mouse_filter = Control.MOUSE_FILTER_IGNORE if state == State.EMPTY or (filled and not removable) else Control.MOUSE_FILTER_STOP

func _gui_input(e: InputEvent) -> void: _on_input(e)

## On release (as the old slot bar did): a filled slot or its ✕ goes back to the bag; the lock says what opens it.
func _on_input(e: InputEvent) -> void:
	var up: bool = (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed)
	if not up: return
	if state == State.FILLED and removable:
		accept_event()
		tapped.emit()
	elif state == State.LOCKED:
		accept_event()
		locked_tapped.emit()
