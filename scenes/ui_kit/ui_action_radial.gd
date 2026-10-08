class_name UiActionRadial
extends Control
## Action radial v2 (SGODOT-247; LOCK-03 v2, 197 72b6233e; spec 247 78108a8b, bubble 493b326c). RadialPetal
## 1122:79385 v2, RadialReason 1655:101164; page-14 row 50: open 1651:100657, unavailable tapped 1651:100787, motion
## 1651:100816. Four icon-only petals on a ring around the SCREEN centre (radius 88; -135 / -45 / 45 / 135°, i.e.
## Farming, Fishing, Mining, Combat clockwise from the upper left). No names, no reasons on screen, no connector.
##   current action  solid primary 72, white icon 38, 3 px white edge, shadow
##   available       surface 64, colour icon 34
##   unavailable     surface 64, icon 35 %, lock badge 18 at (48, -2)
## Every petal takes a 72 px tap. Full-screen overlay: the modal scrim dims the scene and blocks the joystick.
##   open      scrim 120 ms; the petals fly out of the centre one after another, 40 ms apart, each 180 ms
##             ease-out-back (c1 1.45): scale 0.3 → 1, opacity linear; the current petal then pulses 1 → 1.08 → 1.
##   tap       available or current → it pops 1 → 1.15 → 1 (150 ms) with a light buzz, picked(id) at once, the
##             others shrink back to the centre (120 ms) and the scrim fades: closed.
##             unavailable → it shakes ±6 px twice (200 ms) with a buzz and RadialReason shows at the ring centre for
##             1.5 s, its tail towards that petal; the menu stays open.
##   close     off a petal or Back: all petals shrink back to the centre, 120 ms ease-in.
## options: [{id, name, icon: Texture2D, available: bool, reason}] in ring order; `selected` is the current action.
## Animation is a function of time (advance(ms)), so the gallery can pose any frame and tests can step it.

signal picked(id: String)
signal closed

enum Phase { HIDDEN, OPENING, OPEN, CLOSING }
enum Tail { UP_LEFT, UP_RIGHT, DOWN_RIGHT, DOWN_LEFT }

const LOCK_GLYPH := preload("res://assets/p0/icons/lock.svg")
const ANGLES := [-135.0, -45.0, 45.0, 135.0]   # screen y down: upper left, upper right, lower right, lower left
const _BACK_C1 := 1.45            # ease-out-back overshoot (P3 1651:100816, about 7.5 %)
const _FROM_SCALE := 0.3
const _PULSE := 0.08              # the current petal's arrival pulse, 1 → 1.08 → 1
const _PULSE_MS := 160.0
const _POP := 0.15                # a tapped petal, 1 → 1.15 → 1
const _SHAKE_PX := 6.0            # an unavailable petal, ±6 px twice
const _LOCK_AT := Vector2(48, -2) # lock badge on the 64 px petal
const _REASON_FADE_MS := 200.0
const _TAIL := Vector2(12, 7)     # RadialReason tail
const _TAIL_IN := 16.0            # tail inset from the bubble's side
const _WHITE_ICON := "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0, 1.0, 1.0, texture(TEXTURE, UV).a * COLOR.a); }"

var options: Array = []: set = set_options
var selected := "": set = set_selected
## Vibrate on a tap; off in tests and the gallery.
var haptics := true
## A still: frame steps do not advance the animation (gallery poses; Godot turns _process on at ready anyway).
var frozen := false

var _scrim: ColorRect
var _layer: Control
var _petals: Array[Button] = []
var _reason: PanelContainer
var _reason_text: Label
var _reason_tail: Control
var _phase := Phase.HIDDEN
var _t := 0.0                     # ms since the phase began
var _picked := -1                 # the petal tapped to close (it pops instead of shrinking)
var _pops := {}                   # petal → ms since its pop / shake began
var _shakes := {}
var _reason_ms := -1.0            # ms the bubble has shown, -1 when hidden
static var _white: Shader

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim = ColorRect.new()
	_scrim.color = UiTokens.COLOR_SCRIM_MODAL
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.gui_input.connect(_on_scrim_input)
	add_child(_scrim)
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_layer)
	_build_reason()
	visible = false
	set_process(false)

func set_options(v: Array) -> void: options = v; _rebuild()
func set_selected(v: String) -> void: selected = v; _rebuild()

func petals() -> Array[Button]: return _petals
func phase() -> Phase: return _phase
## Open and taking taps (not on its way out).
func is_open() -> bool: return visible and _phase in [Phase.OPENING, Phase.OPEN]
func reason_visible() -> bool: return _reason.visible
func reason_text() -> String: return _reason_text.text
func reason_tail() -> Tail: return _reason_tail.get_meta("tail", Tail.UP_LEFT)

## The ring's centre: the middle of the overlay (the screen).
func ring_center() -> Vector2: return size * 0.5

## Where petal i rests when fully open.
func petal_center(i: int) -> Vector2:
	var a := deg_to_rad(float(ANGLES[i]))
	return ring_center() + Vector2(cos(a), sin(a)) * UiTokens.SIZE_RADIAL_RING

func open() -> void:
	visible = true
	_phase = Phase.OPENING
	_t = 0.0
	_picked = -1
	_pops.clear()
	_shakes.clear()
	_hide_reason()
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_apply()

## v1 entry point (the fan followed the character); v2 always opens around the screen centre.
func open_at(_point: Vector2) -> void: open()

func close() -> void:
	if not is_open(): return
	_phase = Phase.CLOSING
	_t = 0.0
	_hide_reason()
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE   # the scene takes touches again at once
	_apply()

## Step the animation by `ms` (the frame step calls this; tests and the gallery call it directly).
func advance(ms: float) -> void:
	if _phase == Phase.HIDDEN: return
	_t += ms
	for i in _pops.keys(): _pops[i] += ms
	for i in _shakes.keys(): _shakes[i] += ms
	if _reason_ms >= 0.0:
		_reason_ms += ms
		if _reason_ms >= UiTokens.MOTION_RADIAL_REASON_MS + _REASON_FADE_MS: _hide_reason()
	if _phase == Phase.OPENING and _t >= _open_ms(): _phase = Phase.OPEN
	if _phase == Phase.CLOSING and _t >= _close_ms():
		_t = _close_ms()
		_apply()   # the last pose (all at the centre) before it hides
		_finish_close()
		return
	_apply()

## Pose the opening at `ms` (gallery storyboard, P3 1651:100816).
func pose_opening(ms: float) -> void:
	open()
	advance(ms)

func _process(delta: float) -> void:
	if not frozen: advance(delta * 1000.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED: _apply()   # the ring follows the overlay's size (opened before its first layout)

func _open_ms() -> float:
	return float(UiTokens.MOTION_RADIAL_STAGGER_MS * maxi(0, _petals.size() - 1) + UiTokens.MOTION_RADIAL_PETAL_IN_MS) + _PULSE_MS

func _close_ms() -> float:
	return float(UiTokens.MOTION_RADIAL_TAP_MS if _picked >= 0 else UiTokens.MOTION_RADIAL_RETRACT_MS)

func _finish_close() -> void:
	_phase = Phase.HIDDEN
	visible = false
	set_process(false)
	closed.emit()

# ------------------------------------------------------------------ pose

## Opening progress of petal i at the current time, 0..1 (linear; the motion eases it).
func progress(i: int) -> float:
	if _phase == Phase.OPENING:
		return clampf((_t - UiTokens.MOTION_RADIAL_STAGGER_MS * i) / UiTokens.MOTION_RADIAL_PETAL_IN_MS, 0.0, 1.0)
	return 1.0 if _phase == Phase.OPEN else 0.0

func scrim_alpha() -> float:
	match _phase:
		Phase.OPENING: return clampf(_t / UiTokens.MOTION_RADIAL_SCRIM_MS, 0.0, 1.0)
		Phase.OPEN: return 1.0
		Phase.CLOSING: return 1.0 - clampf(_t / _close_ms(), 0.0, 1.0)
	return 0.0

static func _back_out(p: float) -> float:
	var q := p - 1.0
	return 1.0 + (_BACK_C1 + 1.0) * q * q * q + _BACK_C1 * q * q

func _apply() -> void:
	_scrim.modulate.a = scrim_alpha()
	var c := ring_center()
	for i in _petals.size():
		var b := _petals[i]
		var home := petal_center(i)
		var out := 1.0            # 0 at the centre, 1 at rest (overshoots while easing)
		var scale_k := 1.0
		var alpha := 1.0
		if _phase == Phase.OPENING:
			var p := progress(i)
			out = _back_out(p)
			scale_k = lerpf(_FROM_SCALE, 1.0, out)
			alpha = p
			var arrived := _t - (UiTokens.MOTION_RADIAL_STAGGER_MS * i + UiTokens.MOTION_RADIAL_PETAL_IN_MS)
			if _is_current(i) and arrived > 0.0 and arrived < _PULSE_MS: scale_k *= 1.0 + _PULSE * sin(PI * arrived / _PULSE_MS)
		elif _phase == Phase.CLOSING:
			if i == _picked:
				alpha = 1.0 - clampf(_t / _close_ms(), 0.0, 1.0)
			else:
				var k := clampf(_t / UiTokens.MOTION_RADIAL_RETRACT_MS, 0.0, 1.0)
				k = k * k * k   # ease-in
				out = 1.0 - k
				scale_k = lerpf(1.0, _FROM_SCALE, k)
				alpha = 1.0 - k
		if _pops.has(i):
			var q := clampf(float(_pops[i]) / UiTokens.MOTION_RADIAL_TAP_MS, 0.0, 1.0)
			scale_k *= 1.0 + _POP * sin(PI * q)
		var shake := 0.0
		if _shakes.has(i):
			var q := clampf(float(_shakes[i]) / UiTokens.MOTION_RADIAL_SHAKE_MS, 0.0, 1.0)
			shake = _SHAKE_PX * sin(TAU * 2.0 * q)
		var at := c + (home - c) * out + Vector2(shake, 0.0)
		b.position = at - b.size * 0.5
		b.scale = Vector2.ONE * scale_k
		b.modulate.a = alpha
	if _reason_ms >= 0.0:
		var fade := clampf((_reason_ms - UiTokens.MOTION_RADIAL_REASON_MS) / _REASON_FADE_MS, 0.0, 1.0)
		_reason.modulate.a = 1.0 - fade
		_place_reason()

func _is_current(i: int) -> bool:
	return i < options.size() and str(options[i].get("id", "")) == selected

# ------------------------------------------------------------------ build

func _rebuild() -> void:
	if _layer == null: return
	for p in _petals: p.queue_free()
	_petals.clear()
	for i in mini(options.size(), ANGLES.size()):
		_petals.append(_petal(i, options[i]))
	_apply()

func _petal(i: int, o: Dictionary) -> Button:
	var on := _is_current(i)
	var available := bool(o.get("available", true))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var hit := float(UiTokens.SIZE_RADIAL_HIT)
	b.size = Vector2(hit, hit)
	b.pivot_offset = b.size * 0.5
	var d := float(UiTokens.SIZE_RADIAL_PETAL_CURRENT if on else UiTokens.SIZE_RADIAL_PETAL)
	var inset := (hit - d) * 0.5
	var box := UiStyleBox.make(UiTokens.COLOR_PRIMARY if on else UiTokens.COLOR_SURFACE, d * 0.5,
		UiTokens.COLOR_SURFACE if on else UiTokens.COLOR_BORDER, UiTokens.STROKE_RADIAL_SELECTED if on else UiTokens.STROKE_DEFAULT)
	box.with_inset(inset, inset, inset, inset)
	box.shadow_color = UiTokens.COLOR_SHADOW_PETAL
	box.shadow_size = UiTokens.SIZE_SHADOW_PETAL_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_PETAL_OFFSET_Y)
	for k in [&"normal", &"hover", &"focus", &"pressed", &"hover_pressed", &"disabled"]: b.add_theme_stylebox_override(k, box)
	var side := float(UiTokens.SIZE_RADIAL_ICON_CURRENT if on else UiTokens.SIZE_RADIAL_ICON)
	var icon := UiKit.icon(o.get("icon", null), side)
	icon.name = "Icon"
	icon.position = Vector2((hit - side) * 0.5, (hit - side) * 0.5)
	icon.size = Vector2(side, side)
	if on:   # the current petal's icon is white on primary (1122:79346; 安其拉: "tint the icon white")
		if _white == null:
			_white = Shader.new()
			_white.code = _WHITE_ICON
		var m := ShaderMaterial.new()
		m.shader = _white
		icon.material = m
	if not available: icon.modulate.a = UiTokens.OPACITY_UNAVAILABLE_ICON
	b.add_child(icon)
	if not available:
		var lb := float(UiTokens.SIZE_RADIAL_LOCK_BADGE)
		var badge := Panel.new()
		badge.name = "Lock"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(inset, inset) + _LOCK_AT
		badge.size = Vector2(lb, lb)
		badge.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, lb * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
		var lock := UiKit.icon(LOCK_GLYPH, UiTokens.SIZE_RADIAL_LOCK_ICON)
		lock.position = Vector2((lb - UiTokens.SIZE_RADIAL_LOCK_ICON) * 0.5, (lb - UiTokens.SIZE_RADIAL_LOCK_ICON) * 0.5)
		lock.size = Vector2(UiTokens.SIZE_RADIAL_LOCK_ICON, UiTokens.SIZE_RADIAL_LOCK_ICON)
		badge.add_child(lock)
		b.add_child(badge)
	b.pressed.connect(_on_petal.bind(i))
	_layer.add_child(b)
	return b

func _build_reason() -> void:
	_reason = PanelContainer.new()
	_reason.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, 14.0, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_PETAL
	box.shadow_size = UiTokens.SIZE_SHADOW_PETAL_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_PETAL_OFFSET_Y)
	box.with_margins(11, 6, 11, 6)   # RadialReason 1655:101164: 109 × 28, text at (11, 6)
	_reason.add_theme_stylebox_override(&"panel", box)
	_reason_text = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_TEXT)
	_reason.add_child(_reason_text)
	_reason_tail = Control.new()
	_reason_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reason_tail.draw.connect(_draw_tail)
	_reason.visible = false
	_reason_tail.visible = false
	add_child(_reason_tail)   # under the bubble, like the main (tail drawn beneath the body)
	add_child(_reason)

func _show_reason(i: int) -> void:
	_reason_text.text = str(options[i].get("reason", ""))
	if _reason_text.text == "": return
	_reason_tail.set_meta("tail", [Tail.UP_LEFT, Tail.UP_RIGHT, Tail.DOWN_RIGHT, Tail.DOWN_LEFT][i])
	_reason.visible = true
	_reason_tail.visible = true
	_reason_ms = 0.0
	_place_reason()

func _hide_reason() -> void:
	_reason_ms = -1.0
	if _reason:
		_reason.visible = false
		_reason_tail.visible = false

func _place_reason() -> void:
	var s := _reason.get_combined_minimum_size()
	_reason.size = s
	_reason.position = ring_center() - s * 0.5
	var tail: Tail = reason_tail()
	var right := tail in [Tail.UP_RIGHT, Tail.DOWN_RIGHT]
	var up := tail in [Tail.UP_LEFT, Tail.UP_RIGHT]
	var x := _reason.position.x + (s.x - _TAIL_IN - _TAIL.x if right else _TAIL_IN)
	var y := _reason.position.y - _TAIL.y + 1.0 if up else _reason.position.y + s.y - 1.0
	_reason_tail.position = Vector2(x, y)
	_reason_tail.size = _TAIL
	_reason_tail.modulate.a = _reason.modulate.a
	_reason_tail.queue_redraw()

func _draw_tail() -> void:
	var up := reason_tail() in [Tail.UP_LEFT, Tail.UP_RIGHT]
	var right := reason_tail() in [Tail.UP_RIGHT, Tail.DOWN_RIGHT]
	var w := _TAIL.x
	var h := _TAIL.y
	# A small wedge leaning towards its petal's side.
	var tip := Vector2(w if right else 0.0, 0.0 if up else h)
	var base_y := h if up else 0.0
	_reason_tail.draw_colored_polygon(PackedVector2Array([Vector2(0, base_y), Vector2(w, base_y), tip]), UiTokens.COLOR_SURFACE)

# ------------------------------------------------------------------ input

func _on_petal(i: int) -> void:
	if not is_open(): return
	var available := bool(options[i].get("available", true))
	if haptics and OS.has_feature("mobile"): Input.vibrate_handheld(20)
	if not available:
		_shakes[i] = 0.0
		_show_reason(i)
		return
	_pops[i] = 0.0
	_picked = i
	picked.emit(str(options[i].get("id", "")))
	close()

func _on_scrim_input(e: InputEvent) -> void:
	var up: bool = (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed)
	if up:
		accept_event()
		close()
