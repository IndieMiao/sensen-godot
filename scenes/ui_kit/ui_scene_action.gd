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
## being clipped or ellipsised ("Need 2 Energy", "Ready in 3h 59m"). Copy too wide even at _MIN_FONT is clipped:
## callers check `cost_fits` and pass their shorter form.
##
## Clay (C-185 D-489 §3.7 / §3.8, owner Q-285; C-186), `UiSceneAction.new(true)`: a 104 × 96 clay lump coloured by
## action (UiActionClay groups: earth, sow, water, harvest, rest; grey clay for any refusal), a 26 single-colour action
## icon over the verb (ExtraBold 25, cream with a 2 px shadow, stepping down to 17) and the second line in a cream pill
## (20 high, at most 84 wide; 11 stepping down to 10, PM C-186#13). The same six states: short of Energy keeps the
## colour and turns the pill dark (`action/clay/pillShort`) with `hud/energyLow` text and a bolt; unavailable is grey
## clay without sparkles or the verb's shadow; held repeats draw a cream stroke round the lump; pending dims the
## content to 45% and turns a short cream arc round it. A press squashes it (×1.04 × 0.92 from its bottom edge, 80)
## and springs back (160, pop); it still fires on touch-down (LOCK-24 feel). MS-22: a new verb squashes the lump to
## 1.10 × 0.84 (90), swaps the content and springs back through 0.95 × 1.07 (240) while the colour cross-fades (160
## from 60) and the content pops 0.6 → 1.1 → 1; a second change within 250 ms only cross-fades; a press takes over at
## once. A new second line alone cross-fades its text (120), a new state alone its colour (160).

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
## Clay: the pill's text padding each side, and the room a verb has inside the lump (10 from each side).
const _PILL_PAD := 2.0
const _CLAY_SIDE := 10.0
const _CLAY_CONTENT_ALPHA_PENDING := 0.45

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

## The clay look (dynamic farm); false keeps the 88 round key (P0 worlds).
var clay := false
var _face: Control          # clay: draws the lump; scaled by presses and switches
var _content: Control       # clay: icon, verb and pill; scaled and faded by switches
var _icon: TextureRect
var _pill: Panel
var _pill_box: StyleBoxFlat
var _bolt: TextureRect
var _tint_from: Array[Color] = []
var _tint_t := 1.0
var _shown_verb := ""        # clay: the verb the content shows (a switch swaps it 90 ms after `verb` changes)
var _last_switch_ms := -100000
var _switch: Tween
var _tint: Tween

func _init(clay_ := false) -> void:
	clay = clay_
	var side := Vector2(UiTokens.SIZE_CLAY_KEY_W, UiTokens.SIZE_CLAY_KEY_H) if clay \
		else Vector2(UiTokens.SIZE_SCENE_ACTION, UiTokens.SIZE_SCENE_ACTION)
	custom_minimum_size = side
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	if clay: _build_clay()
	else:
		_verb = _text(UiTokens.STYLE_BUTTON_XB15, _VERB_TOP, _VERB_H)
		_cost = _text(UiTokens.STYLE_CAPTION_B12, _COST_TOP, _COST_H)
	set_process(false)
	_refresh()

# Owners set these every frame (P0 worlds call set_action per frame): unchanged values skip the relayout.
func set_verb(v: String) -> void:
	if v == verb: return
	var was := verb
	verb = v
	if clay and was != "" and _can_animate(): _switch_verb()
	else:
		_shown_verb = v
		_refresh()
func set_cost(v: String) -> void:
	if v == cost: return
	var swap := clay and cost != "" and v != "" and _can_animate() and (_switch == null or not _switch.is_valid())
	cost = v
	if swap:
		UiMotion.swap_text(_cost, v)
		_fit_pill.call_deferred()
	else: _refresh()
func set_state(v: State) -> void:
	if v == state and _verb != null: return
	if clay and _can_animate(): _start_tint()
	state = v
	set_process(v == State.PENDING)
	_refresh()
func set_hold_progress(v: float) -> void:
	hold_progress = clampf(v, 0.0, 1.0)
	queue_redraw()
	if _face != null: _face.queue_redraw()

func is_held() -> bool: return _held

## Whether `text` shows whole as the second line, at the smallest step _fit takes (wider is clipped). A caller with a
## shorter form puts that on the key where this is false and keeps the whole sentence for the tap's toast (`Need 2
## more Carrot` → `Need 2 more`, as P0's keys do, p0_locals.gd KEY_W).
static func cost_fits(text: String) -> bool:
	var font := UiKit.theme().get_font(&"font", UiTokens.STYLE_CAPTION_B12)
	var round_fits := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, _MIN_FONT).x <= UiTokens.SIZE_SCENE_ACTION - _TEXT_INSET * 2.0
	return round_fits and clay_cost_fits(text)

## The clay key's pill at its smallest step (10, bold; the short-of-Energy bolt not counted).
static func clay_cost_fits(text: String) -> bool:
	var w := UiKit.font(&"bold").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTokens.SIZE_CLAY_KEY_PILL_FONT_MIN).x
	return w <= UiTokens.SIZE_CLAY_KEY_PILL_MAX_W - _PILL_PAD * 2.0

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
	if clay:
		_refresh_clay()
		return
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
	var text := _shown_verb if clay else verb
	if cost != "" or not text.contains(" ") or not _verb.is_inside_tree(): return text
	var font := _verb.get_theme_font(&"font")
	var fs := _verb.get_theme_font_size(&"font_size")
	var w := func(t: String) -> float: return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if float(w.call(text)) <= (float(UiTokens.SIZE_CLAY_KEY_W) - _CLAY_SIDE * 2.0 if clay else VERB_ALONE_MAX): return text
	var words := text.split(" ")
	var best := text
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
	if _face != null: _face.queue_redraw()

func _draw() -> void:
	if clay: return
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
	if clay: _squash(true)
	_refresh()
	pressed_down.emit()

func _release() -> void:
	_held = false
	_touch = -1
	if clay: _squash(false)
	_refresh()
	released.emit()

# ---------------------------------------------------------------- clay (C-185 §3.7 / §3.8, C-186)

func _can_animate() -> bool:
	return not UiMotion.reduced and is_inside_tree() and is_visible_in_tree()

func _build_clay() -> void:
	_face = Control.new()
	_face.name = "Clay"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face.draw.connect(_draw_clay)
	add_child(_face)
	_content = Control.new()
	_content.name = "Content"
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face.add_child(_content)
	var s := float(UiTokens.SIZE_CLAY_KEY_ICON)
	_icon = UiKit.icon(null, s)
	_icon.name = "Icon"
	_content.add_child(_icon)
	_verb = UiKit.label("", UiTokens.STYLE_BUTTON_XB15)
	_verb.name = "Verb"
	_verb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_verb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_verb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_verb.add_theme_font_override(&"font", UiKit.font(&"extrabold"))
	_verb.add_theme_constant_override(&"shadow_offset_x", 0)
	_verb.add_theme_constant_override(&"shadow_offset_y", 2)
	_verb.add_theme_constant_override(&"shadow_outline_size", 0)
	_verb.clip_text = true
	_content.add_child(_verb)
	_pill = Panel.new()
	_pill.name = "Pill"
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill_box = StyleBoxFlat.new()
	_pill_box.set_corner_radius_all(int(UiTokens.SIZE_CLAY_KEY_PILL_H * 0.5))
	_pill_box.anti_aliasing = true
	_pill.add_theme_stylebox_override(&"panel", _pill_box)
	_content.add_child(_pill)
	_bolt = UiKit.icon(UiActionClay.BOLT, 10.0)
	_bolt.name = "Bolt"
	_pill.add_child(_bolt)
	_cost = UiKit.label("", UiTokens.STYLE_CAPTION_B12)
	_cost.name = "Cost"
	_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cost.add_theme_font_override(&"font", UiKit.font(&"bold"))
	_cost.clip_text = true
	_pill.add_child(_cost)

## What the clay key is coloured as now: the verb's group, or grey clay for a refusal.
func clay_group() -> UiActionClay.Group:
	return UiActionClay.Group.OFF if state == State.UNAVAILABLE else UiActionClay.group_of(_shown_verb)

## The palette drawn this frame: the target, cross-faded from where the last change started.
func _palette() -> Array[Color]:
	var to := UiActionClay.palette(clay_group())
	if _tint_t >= 1.0 or _tint_from.size() != to.size(): return to
	var out: Array[Color] = []
	for i in to.size(): out.append(_tint_from[i].lerp(to[i], _tint_t))
	return out

## Starts a colour cross-fade from the palette drawn now (`delay_ms` later, over `motion/duration/keyTint`).
func _start_tint(delay_ms := 0.0) -> void:
	_tint_from = _palette()
	_tint_t = 0.0
	if _tint != null and _tint.is_valid(): _tint.kill()
	_tint = UiMotion.tween(self, UiTokens.MOTION_EASING_STANDARD)
	if delay_ms > 0.0: _tint.tween_interval(UiMotion.secs(delay_ms))
	_tint.tween_method(func(t: float):
		_tint_t = t
		if _face != null: _face.queue_redraw(), 0.0, 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_KEY_TINT_MS))

func _refresh_clay() -> void:
	var s := drawn_state()
	var group := clay_group()
	var pal := UiActionClay.palette(group)
	var grey := group == UiActionClay.Group.OFF
	_verb.remove_theme_font_size_override(&"font_size")
	_verb.add_theme_font_size_override(&"font_size", UiTokens.SIZE_CLAY_KEY_VERB_FONT)
	_verb.text = _verb_lines()
	_icon.texture = UiActionClay.icon_of(_shown_verb)
	_icon.modulate = UiActionClay.glyph_color(group)
	_verb.add_theme_color_override(&"font_color", pal[3] if grey else UiTokens.COLOR_ACTION_CLAY_VERB)
	_verb.add_theme_color_override(&"font_shadow_color", Color.TRANSPARENT if grey else UiTokens.COLOR_ACTION_CLAY_VERB_SHADOW)
	var short := s == State.INSUFFICIENT
	_pill_box.bg_color = UiTokens.COLOR_ACTION_CLAY_PILL_SHORT if short else UiTokens.COLOR_ACTION_CLAY_PILL
	_cost.add_theme_color_override(&"font_color", UiTokens.COLOR_HUD_ENERGY_LOW if short else pal[3])
	_bolt.visible = short
	_bolt.modulate = UiTokens.COLOR_HUD_ENERGY_LOW
	# The second line always follows `cost` (a set_cost cross-fade writes the same text at its midpoint).
	_cost.text = cost
	_pill.visible = cost != ""
	_place_clay()
	_content.modulate.a = _CLAY_CONTENT_ALPHA_PENDING if s == State.PENDING else 1.0
	modulate.a = 1.0
	_face.queue_redraw()

## Icon over the verb over the pill, as one block centred in the lump (the bottom 4 is its thickness).
func _place_clay() -> void:
	var w := float(UiTokens.SIZE_CLAY_KEY_W)
	var h := float(UiTokens.SIZE_CLAY_KEY_H - UiTokens.SIZE_CLAY_KEY_THICKNESS)
	var lines := _verb.text.count("\n") + 1
	var line_h := 26.0 if lines == 1 else 22.0
	var icon_h := float(UiTokens.SIZE_CLAY_KEY_ICON) if _icon.texture != null else 0.0
	var pill_h := float(UiTokens.SIZE_CLAY_KEY_PILL_H) if cost != "" else 0.0
	var gap := 2.0
	var total := icon_h + (gap if icon_h > 0.0 else 0.0) + line_h * lines + (gap + pill_h if pill_h > 0.0 else 0.0)
	var y := (h - total) * 0.5
	_icon.position = Vector2((w - icon_h) * 0.5, y)
	_icon.size = Vector2(icon_h, icon_h)
	if icon_h > 0.0: y += icon_h + gap
	if lines > 1: _verb.add_theme_font_size_override(&"font_size", int(line_h - 2.0))
	_verb.position = Vector2(_CLAY_SIDE, y - 1.0)
	_verb.size = Vector2(w - _CLAY_SIDE * 2.0, line_h * lines + 2.0)
	_fit_clay_verb()
	y += line_h * lines + gap
	_pill.position.y = y
	_fit_pill()

## Steps the verb down from 25 to 17 until its widest line fits the lump less 10 each side.
func _fit_clay_verb() -> void:
	if not _verb.is_inside_tree() or _verb.text == "": return
	var font := _verb.get_theme_font(&"font")
	var fs := _verb.get_theme_font_size(&"font_size")
	var room := float(UiTokens.SIZE_CLAY_KEY_W) - _CLAY_SIDE * 2.0
	var widest := func(size_: int) -> float:
		var m := 0.0
		for line in _verb.text.split("\n"): m = maxf(m, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size_).x)
		return m
	while fs > UiTokens.SIZE_CLAY_KEY_VERB_FONT_MIN and float(widest.call(fs)) > room: fs -= 1
	_verb.add_theme_font_size_override(&"font_size", fs)

## The pill hugs its text (11, stepping to 10) plus the bolt when short, at most 84 wide, centred.
func _fit_pill() -> void:
	if _pill == null: return
	var font := UiKit.font(&"bold")
	var fs := UiTokens.SIZE_CLAY_KEY_PILL_FONT
	var text := cost
	# The bolt only where the whole sentence still fits beside it (the copy wins over the glyph).
	var full := UiTokens.SIZE_CLAY_KEY_PILL_MAX_W - _PILL_PAD * 2.0
	if drawn_state() == State.INSUFFICIENT:
		_bolt.visible = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTokens.SIZE_CLAY_KEY_PILL_FONT_MIN).x + 11.0 <= full
	var bolt := 11.0 if _bolt.visible else 0.0
	var room := full - bolt
	while fs > UiTokens.SIZE_CLAY_KEY_PILL_FONT_MIN and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room: fs -= 1
	_cost.add_theme_font_size_override(&"font_size", fs)
	var tw := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, room)
	var pw := minf(ceilf(tw + bolt + _PILL_PAD * 2.0 + 8.0), UiTokens.SIZE_CLAY_KEY_PILL_MAX_W)
	var ph := float(UiTokens.SIZE_CLAY_KEY_PILL_H)
	_pill.size = Vector2(pw, ph)
	_pill.position.x = (float(UiTokens.SIZE_CLAY_KEY_W) - pw) * 0.5
	_bolt.position = Vector2(_PILL_PAD + 1.0, (ph - 10.0) * 0.5)
	_bolt.size = Vector2(10, 10)
	_cost.position = Vector2(_PILL_PAD + bolt, 0)
	_cost.size = Vector2(pw - _PILL_PAD * 2.0 - bolt, ph)

## MS-01 for the clay key: down squashes ×1.04 × 0.92 from the bottom edge (80, standard); up springs back (160, pop).
## A press takes over a switch at once: the new content is already in (the logic changed first).
func _squash(down: bool) -> void:
	if _switch != null and _switch.is_valid():
		_switch.kill()
		_finish_switch()
	_face.pivot_offset = Vector2(_face.size.x * 0.5, _face.size.y)
	if UiMotion.reduced or not is_inside_tree():
		_face.scale = Vector2.ONE
		return
	var tw := UiMotion.tween(_face, UiTokens.MOTION_EASING_STANDARD if down else UiTokens.MOTION_EASING_POP)
	var to := Vector2(UiTokens.MOTION_SCALE_KEY_PRESS_X, UiTokens.MOTION_SCALE_KEY_PRESS_Y) if down else Vector2.ONE
	tw.tween_property(_face, "scale", to, UiMotion.secs(UiTokens.MOTION_DURATION_INSTANT_MS if down else UiTokens.MOTION_DURATION_QUICK_MS))
	_switch = null

## MS-22 (做法 C 捏扁弹回): squash 90, swap the content, spring back 240 through the overshoot; the colour cross-fades
## from 60 over 160. A change while one runs (or within 250 ms of the last) shows the newest content at once: mid-switch
## it springs back from its current shape, otherwise only the content cross-fades (120).
func _switch_verb() -> void:
	var now := Time.get_ticks_msec()
	var recent := now - _last_switch_ms < UiTokens.MOTION_DURATION_KEY_REPEAT_GUARD_MS
	_last_switch_ms = now
	if _held:
		_shown_verb = verb
		_start_tint()
		_refresh()
		return
	if _switch != null and _switch.is_valid():
		_switch.kill()
		_shown_verb = verb
		_start_tint()
		_refresh()
		_spring()
		return
	if recent:
		_shown_verb = verb
		_start_tint()
		_refresh()
		_content.modulate.a = 0.0
		var tw := UiMotion.tween(_content, UiTokens.MOTION_EASING_STANDARD)
		tw.tween_property(_content, "modulate:a", _content_alpha(), UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		return
	_face.pivot_offset = Vector2(_face.size.x * 0.5, _face.size.y)
	_content.pivot_offset = _content.size * 0.5
	_start_tint(UiTokens.MOTION_DELAY_KEY_TINT)
	var squash := UiMotion.secs(UiTokens.MOTION_DURATION_KEY_SQUASH_MS)
	_switch = UiMotion.tween(_face, UiTokens.MOTION_EASING_EXIT)
	_switch.tween_property(_face, "scale", Vector2(UiTokens.MOTION_SCALE_KEY_SQUASH_X, UiTokens.MOTION_SCALE_KEY_SQUASH_Y), squash)
	_switch.parallel().tween_property(_content, "scale", Vector2.ONE * UiTokens.MOTION_SCALE_KEY_CONTENT_FROM, squash)
	_switch.parallel().tween_property(_content, "modulate:a", 0.0, squash)
	_switch.tween_callback(func():
		_shown_verb = verb
		_refresh()
		_spring())

## The spring back (240): the lump through 0.95 × 1.07 to 1, the content 0.6 → 1.1 → 1 (200) fading in.
func _spring() -> void:
	var half := UiMotion.secs(UiTokens.MOTION_DURATION_KEY_SPRING_MS * 0.5)
	var pop := UiMotion.secs(UiTokens.MOTION_DURATION_KEY_CONTENT_MS)
	_switch = UiMotion.tween(_face, UiTokens.MOTION_EASING_POP)
	_switch.tween_property(_face, "scale", Vector2(UiTokens.MOTION_SCALE_KEY_OVERSHOOT_X, UiTokens.MOTION_SCALE_KEY_OVERSHOOT_Y), half)
	_switch.tween_property(_face, "scale", Vector2.ONE, half)
	if _content.scale.x > UiTokens.MOTION_SCALE_KEY_CONTENT_FROM + 0.01 and _content.modulate.a > 0.99: return
	var c := UiMotion.tween(_content, UiTokens.MOTION_EASING_POP)
	_content.scale = Vector2.ONE * UiTokens.MOTION_SCALE_KEY_CONTENT_FROM
	c.tween_property(_content, "scale", Vector2.ONE * UiTokens.MOTION_SCALE_KEY_CONTENT_POP, pop * 0.6)
	c.parallel().tween_property(_content, "modulate:a", _content_alpha(), pop * 0.5)
	c.tween_property(_content, "scale", Vector2.ONE, pop * 0.4)

func _finish_switch() -> void:
	_shown_verb = verb
	_face.scale = Vector2.ONE
	_content.scale = Vector2.ONE
	_refresh()

func _content_alpha() -> float:
	return _CLAY_CONTENT_ALPHA_PENDING if drawn_state() == State.PENDING else 1.0

## The lump, bottom to top: a soft warm shadow (y +7), its thickness in the shade colour (4 down), the body shading
## to the shade colour over its lower part, a soft light patch at the top-left; sparkles while it can be done; the
## hold progress or the pending arc as a cream stroke round its outline.
func _draw_clay() -> void:
	var pal := _palette()
	var s := drawn_state()
	var w := _face.size.x
	var h := _face.size.y - float(UiTokens.SIZE_CLAY_KEY_THICKNESS)
	var pts := UiActionClay.outline(w, h)
	var c := Vector2(w, h) * 0.5
	var shadow := UiTokens.COLOR_ACTION_CLAY_SHADOW
	for k in 4:
		var grow := 1.0 + 0.03 * k
		var layer := PackedVector2Array()
		for p in pts: layer.append(c + (p - c) * grow + Vector2(0, 7))
		_face.draw_colored_polygon(layer, Color(shadow, shadow.a * (0.45 - 0.1 * k)))
	var thick := PackedVector2Array()
	for p in pts: thick.append(p + Vector2(0, UiTokens.SIZE_CLAY_KEY_THICKNESS))
	_face.draw_colored_polygon(thick, pal[1])
	var colors := PackedColorArray()
	for p in pts: colors.append(pal[0].lerp(pal[1], smoothstep(0.5, 1.0, p.y / h) * 0.85))
	_face.draw_polygon(pts, colors)
	# The light patch: stacked soft ellipses at the top-left, fading out.
	var hl := Vector2(w * 0.3, h * 0.27)
	for k in 5:
		var r := Vector2(w * 0.2, h * 0.12) * (1.0 - 0.15 * k)
		_face.draw_set_transform(hl, -0.5, r / maxf(r.x, 1.0))
		_face.draw_circle(Vector2.ZERO, r.x, Color(pal[2], 0.16 + 0.06 * k), true, -1.0, true)
	_face.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if clay_group() != UiActionClay.Group.OFF and s != State.PENDING and _icon.texture != null:
		var at := _content.position + _icon.position * _content.scale + Vector2(_icon.size.x + 1.0, 1.0)
		UiClay.draw_sparkle(_face, at, 1.0, UiTokens.COLOR_ACTION_CLAY_SPARKLE)
	var ring := UiTokens.COLOR_ACTION_CLAY_VERB
	var n := pts.size()
	if s == State.HOLDING and hold_progress > 0.0:
		# From the top centre clockwise (the outline starts at the right: a quarter turn back).
		var start := n * 3 / 4
		var count := int(round(float(n) * hold_progress))
		var line := PackedVector2Array()
		for i in count + 1: line.append(pts[(start + i) % n])
		if line.size() >= 2: _face.draw_polyline(line, ring, UiTokens.SIZE_HOLD_RING, true)
	if s == State.PENDING:
		var first := int(round(_spin / TAU * float(n))) + n * 3 / 4
		var arc := PackedVector2Array()
		for i in n / 4 + 1: arc.append(pts[(first + i) % n])
		_face.draw_polyline(arc, ring, UiTokens.SIZE_PENDING_RING, true)
