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
## Zero-Energy actions carry no price (LOCK-02 "0 体力的动作不写价"): pass "" as `cost`. With no second line the verb
## sits in the middle of the key; a verb wider than VERB_ALONE_MAX breaks between two words onto two centred lines at
## its own size (`Light` / `Torch`; q(122), 不知火舞 on #264, the frames of row 67). A count `×N` stays with the word
## before it (`Harvest ×5` is one line); a verb that cannot break and is too wide steps its font down as any copy.
## Both lines keep the full copy: text wider than the 80 px box steps its font size down (to _MIN_FONT) instead of
## being clipped or ellipsised ("Need 2 Energy", "Ready in 3h 59m").

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
const _MIN_FONT := 10              # smallest step for copy that does not fit (engineering default)
## A verb alone wider than this breaks at a space onto two lines (Light Torch is 80 at 15 ExtraBold).
const VERB_ALONE_MAX := 72.0

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

# Owners set these every frame (P0 worlds call set_action per frame): unchanged values skip the relayout.
func set_verb(v: String) -> void:
	if v == verb: return
	verb = v
	_refresh()
func set_cost(v: String) -> void:
	if v == cost: return
	cost = v
	_refresh()
func set_state(v: State) -> void:
	if v == state and _verb != null: return
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
	_verb.remove_theme_font_size_override(&"font_size")   # measured at its own size, not a step an earlier copy took (苏烈 on #264)
	_verb.text = _verb_lines()
	_cost.text = cost
	_cost.visible = cost != ""
	_place_verb()
	_fit(_verb)
	_fit(_cost)
	var grey := s == State.UNAVAILABLE
	_verb.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY if grey else UiTokens.COLOR_TEXT)
	_cost.add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT if s == State.INSUFFICIENT else UiTokens.COLOR_SECONDARY)
	modulate.a = UiTokens.OPACITY_SCENE_ACTION_PENDING if s == State.PENDING else 1.0
	queue_redraw()

## The verb as drawn: alone on the key and wider than VERB_ALONE_MAX, broken between two words where the longer line is
## shortest (`Light\nTorch`); never before a count `×N`; otherwise as it is. Needs the theme's font (in the tree).
func _verb_lines() -> String:
	if cost != "" or not verb.contains(" ") or not _verb.is_inside_tree(): return verb
	var font := _verb.get_theme_font(&"font")
	var fs := _verb.get_theme_font_size(&"font_size")
	var w := func(t: String) -> float: return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if float(w.call(verb)) <= VERB_ALONE_MAX: return verb
	var words := verb.split(" ")
	var best := verb
	var widest := INF
	for i in range(1, words.size()):
		if words[i].begins_with("×"): continue   # `Harvest ×5`: the count keeps to its word
		var a := " ".join(words.slice(0, i))
		var b := " ".join(words.slice(i))
		var m := maxf(float(w.call(a)), float(w.call(b)))
		if m < widest:
			widest = m
			best = a + "\n" + b
	return best

## The verb's box: over the cost (the frame's 23–43) with a second line, else centred on the key, one or two lines tall.
func _place_verb() -> void:
	var lines := _verb.text.count("\n") + 1
	var top := _VERB_TOP if cost != "" else (UiTokens.SIZE_SCENE_ACTION - _VERB_H * lines) * 0.5
	_verb.offset_top = top
	_verb.offset_bottom = top + _VERB_H * lines

## Steps the label's font size down until its widest line fits the box width; resets when it fits at the style size.
func _fit(l: Label) -> void:
	l.remove_theme_font_size_override(&"font_size")
	if not l.is_inside_tree() or l.text == "": return
	var font := l.get_theme_font(&"font")
	var fs := l.get_theme_font_size(&"font_size")
	var room := UiTokens.SIZE_SCENE_ACTION - _TEXT_INSET * 2.0
	var base := fs
	var widest := func(size: int) -> float:
		var m := 0.0
		for line in l.text.split("\n"): m = maxf(m, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		return m
	while fs > _MIN_FONT and float(widest.call(fs)) > room: fs -= 1
	if fs != base: l.add_theme_font_size_override(&"font_size", fs)

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_ENTER_TREE:
		if _verb != null: _refresh.call_deferred()
	# A key that disappears or loses the pointer mid-hold must not keep repeating.
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree() and _held: _release()

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
