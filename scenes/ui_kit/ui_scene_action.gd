class_name UiSceneAction
extends Control
## SceneAction 1116:78934 (SGODOT-221, LOCK-02): the 88 px main action key, verb over cost on a round key.
##   DEFAULT       surface, primary ring                     tap runs the action
##   INSUFFICIENT  amber, warning ring, "Need N Energy"       tap opens the Energy card (the owner decides)
##   UNAVAILABLE   neutral grey, the second line is the reason
##   PRESSED       primary tint, 3 px ring, while a finger is down (drawn automatically over DEFAULT)
##   HOLDING       primary tint with a ring showing `hold_progress` while the action repeats
##   PENDING       sent with no reply yet: dimmed, a quarter-arc spinner turns
## Like the shipped key (LOCK-24 feel) it fires on touch-down: `pressed_down` on contact, `released` when the
## finger lifts, so the owner can repeat while it is held. On touchscreens it reads ScreenTouch of any finger
## (the right thumb is often the second finger, which Godot does not emulate as a mouse); on desktop the mouse.
## Zero-Energy actions carry no price (LOCK-02 "0 体力的动作不写价"): pass "" as `cost`.

signal pressed_down
signal released

enum State { DEFAULT, INSUFFICIENT, UNAVAILABLE, PRESSED, HOLDING, PENDING }

# Text boxes inside the 88 px main (SceneAction 1116:78934): verb 80×20 at (4, 23), cost 80×16 at (4, 49).
const _TEXT_INSET := 4.0
const _VERB_TOP := 23.0
const _VERB_H := 20.0
const _COST_TOP := 49.0
const _COST_H := 16.0
const _SPIN_TURN_S := 1.0          # one spinner turn per second (engineering default, WP7-B F-08)
const _SPIN_SWEEP := PI * 0.5      # Pending spinner arc: -90° to 0° in the main

var verb := "": set = set_verb
## The second line: "2 Energy", "Need 2 Energy" or the reason; "" hides it.
var cost := "": set = set_cost
var state: State = State.DEFAULT: set = set_state
## 0–1, the HOLDING ring.
var hold_progress := 0.0: set = set_hold_progress

var _verb: Label
var _cost: Label
var _held := false
var _touch := -1
var _spin := 0.0

func _init() -> void:
	custom_minimum_size = Vector2(UiTokens.SIZE_SCENE_ACTION, UiTokens.SIZE_SCENE_ACTION)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_verb = _text(UiTokens.STYLE_BUTTON_XB15, _VERB_TOP, _VERB_H)
	_cost = _text(UiTokens.STYLE_CAPTION_B12, _COST_TOP, _COST_H)
	set_process(false)
	_refresh()

func set_verb(v: String) -> void: verb = v; _refresh()
func set_cost(v: String) -> void: cost = v; _refresh()
func set_state(v: State) -> void:
	state = v
	set_process(v == State.PENDING)
	_refresh()
func set_hold_progress(v: float) -> void: hold_progress = clampf(v, 0.0, 1.0); queue_redraw()

func is_held() -> bool: return _held

## What is drawn: a finger on a DEFAULT key shows PRESSED.
func drawn_state() -> State:
	return State.PRESSED if _held and state == State.DEFAULT else state

func _text(style: StringName, top: float, h: float) -> Label:
	var l := UiKit.label("", style)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.clip_text = true
	l.anchor_right = 1.0
	l.offset_left = _TEXT_INSET
	l.offset_right = -_TEXT_INSET
	l.offset_top = top
	l.offset_bottom = top + h
	add_child(l)
	return l

func _refresh() -> void:
	if _verb == null: return
	var s := drawn_state()
	_verb.text = verb
	_cost.text = cost
	_cost.visible = cost != ""
	var grey := s == State.UNAVAILABLE
	_verb.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY if grey else UiTokens.COLOR_TEXT)
	_cost.add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT if s == State.INSUFFICIENT else UiTokens.COLOR_SECONDARY)
	modulate.a = UiTokens.OPACITY_SCENE_ACTION_PENDING if s == State.PENDING else 1.0
	queue_redraw()

func _process(delta: float) -> void:
	_spin = fmod(_spin + delta * TAU / _SPIN_TURN_S, TAU)
	queue_redraw()

func _draw() -> void:
	var s := drawn_state()
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var fill := UiTokens.COLOR_SURFACE
	var ring := UiTokens.COLOR_PRIMARY
	var width := float(UiTokens.STROKE_SCENE_ACTION)
	match s:
		State.INSUFFICIENT:
			fill = UiTokens.COLOR_AMBER
			ring = UiTokens.COLOR_WARNING
		State.UNAVAILABLE:
			fill = UiTokens.COLOR_DISABLED
			ring = UiTokens.COLOR_BORDER
		State.PRESSED:
			fill = UiTokens.COLOR_PRIMARY_TINT
			width = UiTokens.STROKE_SCENE_ACTION_PRESSED
		State.HOLDING:
			fill = UiTokens.COLOR_PRIMARY_TINT
	draw_circle(c, r, fill)
	draw_arc(c, r - width * 0.5, 0.0, TAU, 96, ring, width, true)
	if s == State.HOLDING and hold_progress > 0.0:
		var w := UiTokens.SIZE_HOLD_RING
		draw_arc(c, r - w * 0.5, -PI * 0.5, -PI * 0.5 + TAU * hold_progress, 96, UiTokens.COLOR_PRIMARY, w, true)
	if s == State.PENDING:
		var w := UiTokens.SIZE_PENDING_RING
		draw_arc(c, r - w * 0.5, -PI * 0.5 + _spin, -PI * 0.5 + _spin + _SPIN_SWEEP, 32, UiTokens.COLOR_PRIMARY, w, true)

func _gui_input(e: InputEvent) -> void:
	if DisplayServer.is_touchscreen_available():
		if e is InputEventScreenTouch:
			if e.pressed and not _held: _press(e.index)
			elif not e.pressed and e.index == _touch: _release()
			accept_event()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed and not _held: _press(0)
		elif not e.pressed and _held: _release()
		accept_event()

func _notification(what: int) -> void:
	# A key that disappears or loses the pointer mid-hold must not keep repeating.
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _held: _release()

func _press(index: int) -> void:
	_held = true
	_touch = index
	_refresh()
	pressed_down.emit()

func _release() -> void:
	_held = false
	_touch = -1
	_refresh()
	released.emit()
