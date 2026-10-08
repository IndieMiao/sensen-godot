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
const _ICON_GAP := 8.0   # glyph 20, then the text (R1: text at x 39 of the card)
const _LINE_GAP := 4.0

var _anchor: WeakRef
var _bottom_y := -1.0   # anchor_bottom: the toast's bottom edge, layer-local; -1 when it sits above an anchor
var _width := WIDTH

var _current := {}
var _left := 0.0
var _clock_ms := 0
var _panel: PanelContainer
var _glyph: TextureRect
var _label: Label
var _action: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # fill the parent whatever size it had when added
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = card(Severity.INFO, "")
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	_glyph = _panel.find_child("Glyph", true, false)
	_label = _panel.find_child("Text", true, false)
	_action = _panel.find_child("Action", true, false)
	_action.mouse_filter = Control.MOUSE_FILTER_STOP
	_action.gui_input.connect(_on_action_input)
	add_child(_panel)
	# Wrapped text settles its height after layout; keep the bottom edge fixed whenever it changes.
	_panel.minimum_size_changed.connect(_place)
	resized.connect(_place)

## One toast card, as the layer shows it (the gallery and the layer share it): glyph, text, the optional action line.
static func card(severity: Severity, text: String, action := "") -> PanelContainer:
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
	var g := UiKit.icon(null, UiTokens.SIZE_TOAST_ICON)
	g.name = "Glyph"
	g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(g)
	var l := UiKit.label("", UiTokens.STYLE_C14_XB, UiTokens.COLOR_TEXT)
	l.name = "Text"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var a := UiKit.label("", UiTokens.STYLE_C12_XB, UiTokens.COLOR_INFO)
	a.name = "Action"
	var actions := MarginContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override(&"margin_left", int(UiTokens.SIZE_TOAST_ICON + _ICON_GAP))
	actions.add_child(a)
	col.add_child(actions)
	fill(panel, severity, text, action)
	return panel

## Puts a severity, text and action on a card() (an action reads `Open bag ›`).
static func fill(panel: PanelContainer, severity: Severity, text: String, action := "") -> void:
	panel.add_theme_stylebox_override(&"panel", panel_style(severity))
	(panel.find_child("Glyph", true, false) as TextureRect).texture = glyph(severity)
	(panel.find_child("Text", true, false) as Label).text = text
	var a := panel.find_child("Action", true, false) as Label
	a.text = (action + " ›") if action != "" and not action.ends_with("›") else action
	a.get_parent().visible = action != ""

## The panel's style for a severity (Toast R1): fill and edge per tone, the R1 padding, the soft float shadow.
static func panel_style(severity: Severity) -> UiStyleBox:
	var fill := UiTokens.COLOR_SURFACE
	var edge := UiTokens.COLOR_BORDER
	match severity:
		Severity.SUCCESS:
			fill = UiTokens.COLOR_PRIMARY_TINT
			edge = UiTokens.COLOR_PRIMARY
		Severity.REFUSED, Severity.ERROR:
			fill = UiTokens.COLOR_DANGER_TINT
			edge = UiTokens.COLOR_DANGER
	var box := UiStyleBox.make(fill, UiTokens.RADIUS_CARD, edge, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	return box.with_margins(UiTokens.SIZE_TOAST_PAD_LEFT, UiTokens.SIZE_TOAST_PAD_TOP, UiTokens.SIZE_TOAST_PAD_RIGHT, UiTokens.SIZE_TOAST_PAD_BOTTOM)

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
## popping it again. `action` adds the action line (`Open bag ›`); `seconds` > 0 overrides the length rule.
func show_toast(text: String, severity := Severity.INFO, action := "", seconds := 0.0) -> void:
	if text == "": return
	var secs := seconds if seconds > 0.0 else duration_ms(text) / 1000.0
	if not _current.is_empty() and _current.text == text and _clock_ms - int(_current.at) <= REPEAT_MS:
		_current.at = _clock_ms
		_left = secs
		return
	_current = {text = text, severity = severity, action = action, at = _clock_ms}
	_left = secs
	_render()
	shown.emit(text, severity)

func dismiss() -> void:
	_current = {}
	if _panel: _panel.visible = false

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
	fill(_panel, _current.severity, str(_current.text), str(_current.action))
	_panel.visible = true
	_panel.reset_size()   # a size set for a longer text never shrinks on its own
	_place()

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

func _on_action_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		var act := current_action()
		dismiss()
		accept_event()
		if act != "": action_pressed.emit(act)
