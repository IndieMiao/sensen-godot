class_name ToastLayer
extends Control
## Non-modal toast (SGODOT-211, WP7-B F-08 §3), with the q(49) ⑤ rules (SGODOT-233): one at a time, a new toast
## replaces the one showing; the same sentence again within REPEAT_MS only keeps it up longer (it does not pop
## again). Never blocks input except the toast itself (tap to dismiss early). Duration = MOTION_TOAST_BASE_MS +
## MOTION_TOAST_PER20_CHARS_MS per 20 characters, capped at MOTION_TOAST_MAX_MS, unless the caller gives seconds.
## Look: Toast R1 (1178:82265): Success a light green fill and edge with the check, Info the cream surface with the
## info glyph, Refused / Error a light red fill and edge with the alert glyph; the text in ExtraBold 14 ink. An
## optional action (`Open bag ›`, §4.8.6 Creel full) sits under the text and emits action_pressed.
## Placement (WP2 D-01, user-confirmed 2026-10-07 on SGODOT-202): the toast's bottom edge sits
## SPACE_OVERLAY_BODY above an anchor's top edge, left-aligned at SPACE_PAGE and WIDTH wide, so it stays
## clear of the main action key on the right and of the quick bar below. In a scene the anchor is the quick
## bar (default, from tokens); while a drawer is open, anchor_above() its fixed decision area and pass null
## when it closes. The toast grows upward from that edge. Confirmation-type feedback uses an info sheet.
## C-186 (C-185 §3.5 O-02, MS-18): v3 skin — white `surface/raised`, radius 16, no edge, e3 shadow; a 24 disc on the
## left: success `action/primary` with a check, info `phone/accent` with an "i", refused / error `action/danger` with a
## "!"; a `Received … ×N` toast may show the item's icon in its place (show_toast's `icon`). Motion: in from y + 12 and
## ×0.96 with a fade, 200 back-out; out up 8 with a fade, 160 cubic-in; a replaced toast fades out in 120 while the new
## one comes in. The motion is drawn by a vertex shader (MOTION_SHADER), so the card's rect — where it sits, what a tap
## hits, what hosts measure — is always the settled one. Reduced motion: 120 fades. Text, lengths and rules unchanged.

signal shown(text: String, severity: Severity)
## The toast's action (its text, e.g. "Open bag") was tapped; the toast closes.
signal action_pressed(action: String)

enum Severity { SUCCESS, INFO, REFUSED, ERROR }

## The same sentence again within this long only keeps the toast up (q(49) ⑤).
const REPEAT_MS := 2000
## Toast · R1 width (Figma 1178:82265, WP2 accepted; both placement demos 1182:82260 use it).
const WIDTH := UiTokens.SIZE_TOAST_W
## At the foot of a drawer with no decision area (q(16); GUESTBOOK-DELETED, 不知火舞 a414d0da): 232 wide. A constant
## until the next token export adds it.
const NARROW_WIDTH := 232.0
const _GLYPHS := {
	Severity.SUCCESS: preload("res://assets/ui/kit_icons/success.svg"),
	Severity.INFO: preload("res://assets/ui/kit_icons/info.svg"),
	Severity.REFUSED: preload("res://assets/ui/kit_icons/alert.svg"),
	Severity.ERROR: preload("res://assets/ui/kit_icons/alert.svg"),
}
const _ICON_GAP := 8.0   # the 24 disc, then the text
## Draws the card offset and scaled about `pivot` (canvas space) without moving the Control (C-186, MS-18).
const MOTION_SHADER := """shader_type canvas_item;
uniform vec2 pivot = vec2(0.0);
uniform float amount = 1.0;
uniform vec2 offset = vec2(0.0);
void vertex() {
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	w = pivot + (w - pivot) * amount + offset;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(w, 0.0, 1.0)).xy;
}
"""
static var _shader: Shader
const _LINE_GAP := 4.0

var _anchor: WeakRef
var _bottom_y := -1.0   # anchor_bottom: the toast's bottom edge, layer-local; -1 when it sits above an anchor
var _width := WIDTH

var _current := {}
var _left := 0.0
var _clock_ms := 0
var _panel: PanelContainer
var _glyph: TextureRect
var _disc: _Disc
var _label: Label
var _action: Label
var _motion: ShaderMaterial
var _tween: Tween
## Settled on screen at least once since it was last shown (a replacement fades the old one out only then).
var _leaving := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # fill the parent whatever size it had when added
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = card(Severity.INFO, "")
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	_glyph = _panel.find_child("Glyph", true, false)
	_disc = _panel.find_child("Disc", true, false) as _Disc
	_label = _panel.find_child("Text", true, false)
	_action = _panel.find_child("Action", true, false)
	_action.mouse_filter = Control.MOUSE_FILTER_STOP
	_action.gui_input.connect(_on_action_input)
	add_child(_panel)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = MOTION_SHADER
	_motion = ShaderMaterial.new()
	_motion.shader = _shader
	_panel.material = _motion
	for n in _panel.find_children("*", "CanvasItem", true, false): (n as CanvasItem).use_parent_material = true
	# Wrapped text settles its height after layout; keep the bottom edge fixed whenever it changes.
	_panel.minimum_size_changed.connect(_place)
	resized.connect(_place)

## One toast card, as the layer shows it (the gallery and the layer share it): glyph, text, the optional action line.
static func card(severity: Severity, text: String, action := "", icon: Texture2D = null) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", int(_LINE_GAP))
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(_ICON_GAP))
	col.add_child(row)
	var disc := _Disc.new()
	disc.name = "Disc"
	disc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(disc)
	var g := UiKit.icon(null, UiTokens.SIZE_TOAST_ICON_V3)
	g.name = "Glyph"
	g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	disc.add_child(g)
	var l := UiKit.label("", UiTokens.STYLE_C14_XB, UiTokens.COLOR_TEXT)
	l.name = "Text"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var a := UiKit.label("", UiTokens.STYLE_C12_XB, UiTokens.COLOR_INFO)
	a.name = "Action"
	var actions := MarginContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override(&"margin_left", int(UiTokens.SIZE_TOAST_ICON_V3 + _ICON_GAP))
	actions.add_child(a)
	col.add_child(actions)
	fill(panel, severity, text, action, icon)
	return panel

## Puts a severity, text and action on a card() (an action reads `Open bag ›`). `icon` (an item's) replaces the disc's
## tone mark (`Received Carrot Seeds ×3`).
static func fill(panel: PanelContainer, severity: Severity, text: String, action := "", icon: Texture2D = null) -> void:
	panel.add_theme_stylebox_override(&"panel", panel_style(severity))
	var disc := panel.find_child("Disc", true, false) as _Disc
	disc.severity = severity
	disc.item = icon != null
	disc.queue_redraw()
	(panel.find_child("Glyph", true, false) as TextureRect).texture = icon
	(panel.find_child("Text", true, false) as Label).text = keep_units(text)
	var a := panel.find_child("Action", true, false) as Label
	a.text = (action + " ›") if action != "" and not action.ends_with("›") else action
	a.get_parent().visible = action != ""

static var _number_unit: RegEx
## A number never wraps away from the word after it (不知火舞 on 344, 66948360: `Request complete ·` / `+20 coins`, not
## `… +20` / `coins`): the space after a figure becomes a no-break space, in every toast. Only the label shows it;
## what the toast says (current_text) keeps plain spaces.
static func keep_units(text: String) -> String:
	if _number_unit == null:
		_number_unit = RegEx.new()
		_number_unit.compile("(\\d) (?=\\p{L})")
	return _number_unit.sub(text, "$1\u00a0", true)

## The panel's style (C-185 §3.5): white `surface/raised`, radius 16, no edge, the e3 shadow, the R1 padding. The tone
## lives in the disc (disc_color); `severity` is kept for callers.
static func panel_style(_severity: Severity = Severity.INFO) -> UiStyleBox:
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, UiTokens.RADIUS_LG)
	box.shadow_color = UiTokens.ELEVATION_E3_COLOR
	box.shadow_size = UiTokens.ELEVATION_E3_BLUR * 0.5
	box.shadow_offset = Vector2(0, UiTokens.ELEVATION_E3_OFFSET_Y)
	return box.with_margins(UiTokens.SIZE_TOAST_PAD_LEFT, UiTokens.SIZE_TOAST_PAD_TOP, UiTokens.SIZE_TOAST_PAD_RIGHT, UiTokens.SIZE_TOAST_PAD_BOTTOM)

## The disc's colour per tone: success `action/primary`, info `phone/accent`, refused / error `action/danger`.
static func disc_color(severity: Severity) -> Color:
	match severity:
		Severity.SUCCESS: return UiTokens.COLOR_ACTION_PRIMARY
		Severity.REFUSED, Severity.ERROR: return UiTokens.COLOR_ACTION_DANGER
	return UiTokens.COLOR_PHONE_ACCENT

## The R1 glyph textures (kept for callers that draw a tone mark elsewhere; the toast draws its own disc).
static func glyph(severity: Severity) -> Texture2D: return _GLYPHS[severity]

## Sit above `c` (a drawer's fixed decision area, or a collapsed quick bar handle); null = the quick bar.
func anchor_above(c: Control) -> void:
	_anchor = weakref(c) if c != null else null
	_bottom_y = -1.0
	_width = WIDTH
	_place()

## Sit with the bottom edge at layer-local `y`, `width` wide: the foot of a drawer with no decision area (q(16)).
func anchor_bottom(y: float, width := WIDTH) -> void:
	_anchor = null
	_bottom_y = y
	_width = width
	_place()

## Layer-local y of the edge the toast sits above.
func anchor_top() -> float:
	var c: Control = _anchor.get_ref() if _anchor != null else null
	if c != null and c.is_visible_in_tree():
		return (get_global_transform().affine_inverse() * c.get_global_rect().position).y
	return size.y - UiTokens.SIZE_QUICK_BAR_BOTTOM - UiTokens.SIZE_QUICK_BAR_H

static func duration_ms(text: String) -> float:
	var ms := UiTokens.MOTION_TOAST_BASE_MS + UiTokens.MOTION_TOAST_PER20_CHARS_MS * floorf(text.length() / 20.0)
	return minf(ms, UiTokens.MOTION_TOAST_MAX_MS)

## Show `text` now (it replaces any toast showing). The same text again within REPEAT_MS keeps the toast up, without
## popping it again. `action` adds the action line (`Open bag ›`); `seconds` > 0 overrides the length rule; `icon` (an
## item's) takes the disc's place (C-185 §3.5: `Received Carrot Seeds ×3`).
func show_toast(text: String, severity := Severity.INFO, action := "", seconds := 0.0, icon: Texture2D = null) -> void:
	if text == "": return
	var secs := seconds if seconds > 0.0 else duration_ms(text) / 1000.0
	if not _current.is_empty() and _current.text == text and _clock_ms - int(_current.at) <= REPEAT_MS:
		_current.at = _clock_ms
		_left = secs
		return
	var replacing := not _current.is_empty() and _panel != null and _panel.visible and not _leaving
	if replacing: _fade_ghost()
	_current = {text = text, severity = severity, action = action, at = _clock_ms, icon = icon}
	_left = secs
	_render()
	shown.emit(text, severity)

## Closes the toast now: what it says is gone at once (current_text() is ""), the card plays its exit (MS-18).
func dismiss() -> void:
	_current = {}
	if _panel == null or not _panel.visible or _leaving: return
	_leaving = true
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_tween()
	if not is_inside_tree():
		_panel.visible = false
		_leaving = false
		return
	var ms := UiTokens.MOTION_DURATION_FAST_MS if UiMotion.reduced else UiTokens.MOTION_DURATION_QUICK_MS
	_tween = UiMotion.tween(_panel, UiTokens.MOTION_EASING_EXIT)
	if not UiMotion.reduced:
		_motion.set_shader_parameter(&"pivot", _pivot())
		_tween.tween_method(func(v: float): _motion.set_shader_parameter(&"offset", Vector2(0, -v)), 0.0,
			float(UiTokens.MOTION_OFFSET_TOAST_EXIT), UiMotion.secs(ms))
	_tween.parallel().tween_property(_panel, "modulate:a", 0.0, UiMotion.secs(ms))
	_tween.tween_callback(func():
		_panel.visible = false
		_leaving = false
		_reset_motion())

func current_text() -> String: return "" if _current.is_empty() else str(_current.text)
func current_severity() -> int: return -1 if _current.is_empty() else int(_current.severity)
func current_action() -> String: return "" if _current.is_empty() else str(_current.action)

## The text label (hosts and tests read what is showing).
func label() -> Label: return _label

func _process(delta: float) -> void: advance(delta)

## Drive time explicitly (tests call this directly).
func advance(delta: float) -> void:
	_clock_ms += int(delta * 1000.0)
	if _current.is_empty(): return
	_left -= delta
	if _left <= 0.0: dismiss()

func _render() -> void:
	if _panel == null: return
	fill(_panel, _current.severity, str(_current.text), str(_current.action), _current.get("icon") as Texture2D)
	_kill_tween()
	_leaving = false
	_panel.visible = true
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.reset_size()   # a size set for a longer text never shrinks on its own
	_place()
	_enter()

## MS-18 in: from y + 12 and ×0.96 about the bottom middle, fading in, 200 back-out (reduced: a 120 fade).
func _enter() -> void:
	_reset_motion()
	if not is_inside_tree():
		_panel.modulate.a = 1.0
		return
	_panel.modulate.a = 0.0
	if UiMotion.reduced:
		_tween = UiMotion.tween(_panel, UiTokens.MOTION_EASING_LINEAR)
		_tween.tween_property(_panel, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		return
	var ms := UiMotion.secs(UiTokens.MOTION_DURATION_BASE_MS)
	_motion.set_shader_parameter(&"pivot", _pivot())
	_tween = UiMotion.tween(_panel, UiTokens.MOTION_EASING_POP)
	_tween.tween_method(_enter_step, 0.0, 1.0, ms)
	_tween.parallel().tween_property(_panel, "modulate:a", 1.0, ms).set_trans(Tween.TRANS_CUBIC)

## One step of MS-18's entrance (0 → 1): ×0.96 → 1 and y + 12 → 0, drawn by the shader.
func _enter_step(v: float) -> void:
	_motion.set_shader_parameter(&"amount", lerpf(UiTokens.MOTION_SCALE_TOAST_ENTER, 1.0, v))
	_motion.set_shader_parameter(&"offset", Vector2(0, UiTokens.MOTION_OFFSET_TOAST_ENTER * (1.0 - v)))

## A replaced toast: a copy of the card as it is fades out in 120 where it was, over nothing else.
func _fade_ghost() -> void:
	if not is_inside_tree(): return
	var ghost := _panel.duplicate() as Control
	ghost.name = "LeavingToast"
	ghost.material = null
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for n in ghost.find_children("*", "Control", true, false): (n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var from_disc := _disc as _Disc
	var to_disc := ghost.find_child("Disc", true, false) as _Disc
	if from_disc != null and to_disc != null:
		to_disc.severity = from_disc.severity
		to_disc.item = from_disc.item
	add_child(ghost)
	move_child(ghost, _panel.get_index())
	ghost.position = _panel.position
	ghost.size = _panel.size
	var tw := UiMotion.tween(ghost, UiTokens.MOTION_EASING_EXIT)
	tw.tween_property(ghost, "modulate:a", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	tw.tween_callback(ghost.queue_free)

func _pivot() -> Vector2:
	var r := _panel.get_global_rect()
	return Vector2(r.get_center().x, r.end.y)

func _reset_motion() -> void:
	if _motion == null: return
	_motion.set_shader_parameter(&"amount", 1.0)
	_motion.set_shader_parameter(&"offset", Vector2.ZERO)

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = null

func _place() -> void:
	if _panel == null or not _panel.visible: return
	var w := minf(_width, size.x - UiTokens.SPACE_PAGE * 2.0)
	_panel.custom_minimum_size = Vector2(w, UiTokens.SIZE_TOAST_MIN_H)
	var h := _panel.get_combined_minimum_size().y
	_panel.size = Vector2(w, h)
	var bottom := _bottom_y if _bottom_y >= 0.0 else anchor_top() - UiTokens.SPACE_OVERLAY_BODY
	_panel.position = Vector2(UiTokens.SPACE_PAGE, bottom - h)

func _on_panel_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		dismiss()
		accept_event()

## The disc left of the text (24): a tone colour with a white check / "i" / "!", or the item icon (Glyph) on white.
class _Disc extends Control:
	var severity := ToastLayer.Severity.INFO
	var item := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2.ONE * UiTokens.SIZE_TOAST_ICON_V3

	func _draw() -> void:
		if item: return   # the item's icon (the Glyph child) on the white card
		var r := size.x * 0.5
		var c := size * 0.5
		draw_circle(c, r, ToastLayer.disc_color(severity), true, -1.0, true)
		var w := 2.2 * r / 10.0
		var ink := UiTokens.COLOR_SURFACE_RAISED
		match severity:
			ToastLayer.Severity.SUCCESS:
				draw_polyline(PackedVector2Array([c + Vector2(-4.4, 0.4) * r / 10.0, c + Vector2(-1.4, 3.3) * r / 10.0,
					c + Vector2(4.4, -2.8) * r / 10.0]), ink, w, true)
			ToastLayer.Severity.INFO:
				draw_circle(c + Vector2(0, -4.5) * r / 10.0, w * 0.65, ink, true, -1.0, true)
				draw_line(c + Vector2(0, -0.6) * r / 10.0, c + Vector2(0, 3.8) * r / 10.0, ink, w, true)
			_:
				draw_line(c + Vector2(0, -4.5) * r / 10.0, c + Vector2(0, 0.6) * r / 10.0, ink, w, true)
				draw_circle(c + Vector2(0, 4.5) * r / 10.0, w * 0.65, ink, true, -1.0, true)

func _on_action_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		var act := current_action()
		dismiss()
		accept_event()
		if act != "": action_pressed.emit(act)
