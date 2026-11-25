class_name UiBagSlot
extends Control
## UI v3 bag slot (C-P5 / C-P6, C-105): a Ø72 `surface/slot` disc with the item's 48 icon and its count (`x20`,
## `type/micro` in `text/primary`) at the bottom right, allowed 4 past the disc's edge. States: EMPTY, FILLED,
## SELECTED (a 3 `action/primary` ring, M-03), NEW (a Ø8 `badge/unread` dot), LOCKED (50 % and a 16 lock), ADD (a +).
## A tap on a filled slot emits `tapped(id)`; presses play M-01. Data in: `item` {id, icon, qty}.

signal tapped(id: String)

enum State { EMPTY, FILLED, SELECTED, NEW, LOCKED, ADD }

const LOCK := preload("res://assets/ui/kit_icons/lock.svg")
const _RING := 3.0
const _DOT := 8.0
const _LOCK := 16.0
const _PLUS := 20.0
const _PLUS_STROKE := 3.5
const _QTY_OUT := 4.0

var item := {}: set = set_item
var state: State = State.EMPTY: set = set_state
var is_new := false: set = set_is_new
var _icon: TextureRect
var _qty: Label
var _ring_alpha := 0.0
var _down := false

func _init(item_ := {}) -> void:
	custom_minimum_size = Vector2.ONE * UiTokens.SIZE_PANEL_SLOT
	mouse_filter = Control.MOUSE_FILTER_STOP
	_icon = UiKit.icon(null, UiTokens.SIZE_PANEL_SLOT_ICON)
	_icon.size = Vector2.ONE * UiTokens.SIZE_PANEL_SLOT_ICON
	_icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	add_child(_icon)
	_qty = UiKit.label("", UiTokens.STYLE_TYPE_MICRO, UiTokens.COLOR_TEXT_PRIMARY)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_qty)
	item = item_

func set_item(v: Dictionary) -> void:
	item = v
	if _icon == null: return
	_icon.texture = v.get("icon")
	var q := int(v.get("qty", 0))
	_qty.text = "x%d" % q if q > 0 else ""
	if state in [State.EMPTY, State.FILLED]: state = State.FILLED if not v.is_empty() else State.EMPTY
	_layout_qty()
	queue_redraw()

func set_state(v: State) -> void:
	var was := state
	state = v
	if _icon == null: return
	_icon.visible = state != State.ADD and not item.is_empty()
	_icon.modulate.a = 0.5 if state == State.LOCKED else 1.0
	# M-03: the ring fades in, the icon grows ×1.06 (back out); clearing reverses (ease in).
	var on := state == State.SELECTED
	if (was == State.SELECTED) != on and is_inside_tree() and not UiMotion.reduced:
		_icon.pivot_offset = _icon.size * 0.5
		var tw := UiMotion.tween(self, UiTokens.MOTION_EASING_STANDARD if on else UiTokens.MOTION_EASING_EXIT)
		tw.tween_method(_set_ring, _ring_alpha, 1.0 if on else 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		tw.parallel().tween_property(_icon, "scale", Vector2.ONE * (UiTokens.MOTION_SELECT_SCALE if on else 1.0),
			UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS)).set_trans(Tween.TRANS_BACK)
	else:
		_ring_alpha = 1.0 if on else 0.0
		_icon.scale = Vector2.ONE * (UiTokens.MOTION_SELECT_SCALE if on else 1.0)
	queue_redraw()

func set_is_new(v: bool) -> void:
	is_new = v
	queue_redraw()

func _set_ring(a: float) -> void:
	_ring_alpha = a
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _layout_qty()

## The count's right edge 4 past the disc, its baseline on the disc's bottom.
func _layout_qty() -> void:
	if _qty == null: return
	var s := _qty.get_combined_minimum_size()
	_qty.size = s
	_qty.position = Vector2(size.x + _QTY_OUT - s.x, size.y - s.y)

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c, r, UiTokens.COLOR_SURFACE_SLOT, true, -1.0, true)
	if _ring_alpha > 0.0:
		draw_arc(c, r - _RING * 0.5, 0.0, TAU, 64, Color(UiTokens.COLOR_ACTION_PRIMARY, _ring_alpha), _RING, true)
	match state:
		State.LOCKED:
			draw_texture_rect(LOCK, Rect2(c - Vector2.ONE * _LOCK * 0.5, Vector2.ONE * _LOCK), false, UiTokens.COLOR_TEXT_MUTED)
		State.ADD:
			var h := _PLUS * 0.5
			draw_line(c - Vector2(h, 0), c + Vector2(h, 0), UiTokens.COLOR_TEXT_SECONDARY, _PLUS_STROKE, true)
			draw_line(c - Vector2(0, h), c + Vector2(0, h), UiTokens.COLOR_TEXT_SECONDARY, _PLUS_STROKE, true)
	if is_new:
		draw_circle(c + Vector2(r, -r) * 0.72, _DOT * 0.5, UiTokens.COLOR_BADGE_UNREAD, true, -1.0, true)

func _has_point(p: Vector2) -> bool:
	return p.distance_to(size * 0.5) <= maxf(minf(size.x, size.y), UiTokens.SIZE_TOUCH_MIN) * 0.5

func _gui_input(e: InputEvent) -> void:
	var touch := DisplayServer.is_touchscreen_available()
	var is_press: bool = (touch and e is InputEventScreenTouch) or \
		(not touch and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT)
	if not is_press: return
	if e.pressed:
		_down = true
		UiMotion.press(self, true)
	elif _down:
		_down = false
		UiMotion.press(self, false)
		if _has_point(e.position) and not item.is_empty() and state != State.LOCKED: tapped.emit(str(item.get("id", "")))
	accept_event()
