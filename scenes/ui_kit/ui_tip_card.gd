class_name UiTipCard
extends PanelContainer
## TipCard 1243:87540 (TUT-2 482:72; A-03, §14.3; SGODOT-232 U6, 235-B2): the first session's one-sentence teaching card.
## Cream surface, 1 px border, radius 16, padding 14 / 12, a 22 px icon 10 before Nunito Bold 14 text, 296 wide and as
## tall as its text (48 for one line, 64 for two). No buttons and no Got it; a tap on it emits `tapped` (its owner closes
## it), and it never plays for the player. Where it sits and how long it stays are its owner's (P0Ui: centred, the top
## 120 under HUD row 2, above the kitchen drawer; the Toast's duration; it closes when the player does what it teaches).
## The shadow is lighter than the main's literal 20 % so Godot's spread reads like Figma's (不知火舞 on 235-B2); it and the
## sizes are not tokens yet (PENDING "tipCard"): constants here until the next export.

signal tapped

const WIDTH := 296.0
const _PAD_X := 14.0
const _PAD_Y := 12.0
const _GAP := 10
const _RADIUS := 16.0
const _ICON := 22.0
const _MIN_H := 48.0   # one line is 48 in the main (Nunito 14 lays out 2 px shorter here)
const _SHADOW := Color(UiTokens.COLOR_TEXT, 0.08)   # the main's #2E3A33 is COLOR_TEXT; 8 % (the main: 20 %, see above)
const _SHADOW_BLUR := 28.0   # the main's blur 28
const _SHADOW_OFFSET := Vector2(0, 6)

## The main's default icon (i-sprout, the kit's own sprout); a tip's icon comes from its owner (P0Ui.TIP_ICONS through
## the shared P0 icons: one copy of each icon in the app, 不知火舞 on 235-B2).
const DEFAULT_ICON := preload("res://assets/ui/kit_icons/sprout.svg")

var tip := "": set = set_tip
## C-186 (C-185 §3.1 C, F-03): the farm's guide bar — the place chip's dark glass, radius 18, no shadow, 13 bold white
## text after a green dot, 50 high (was the 62 cream card). Content and when it shows are unchanged.
var glass := false
var _dot: Control
var _icon: TextureRect
var _text: Label
var _down_at := Vector2.INF
var _down_ms := 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, _MIN_H)
	size = Vector2(WIDTH, _MIN_H)
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(_PAD_X, _PAD_Y, _PAD_X, _PAD_Y)
	box.shadow_color = _SHADOW
	box.shadow_size = _SHADOW_BLUR
	box.shadow_offset = _SHADOW_OFFSET
	add_theme_stylebox_override(&"panel", box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", _GAP)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = UiKit.icon(DEFAULT_ICON, _ICON)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	_text = UiKit.label("", UiTokens.STYLE_BODY_B14)
	_text.add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_text)

## Turns the card into the farm's dark glass guide bar (see `glass`).
func set_glass() -> void:
	glass = true
	var box := UiClay.padded(UiClay.glass_dark(UiTokens.SIZE_GUIDE_RADIUS), _PAD_X, 8.0)
	add_theme_stylebox_override(&"panel", box)
	custom_minimum_size = Vector2(WIDTH, UiTokens.SIZE_GUIDE_H)
	_icon.visible = false
	_dot = Control.new()
	_dot.name = "Dot"
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.custom_minimum_size = Vector2.ONE * UiTokens.SIZE_GUIDE_DOT
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.draw.connect(func(): _dot.draw_circle(_dot.size * 0.5, UiTokens.SIZE_GUIDE_DOT * 0.5, UiTokens.COLOR_ACTION_PRIMARY, true, -1.0, true))
	_icon.get_parent().add_child(_dot)
	_icon.get_parent().move_child(_dot, 0)
	_text.add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT_ON_DARK)
	_text.add_theme_font_override(&"font", UiKit.font(&"extrabold"))
	_text.add_theme_font_size_override(&"font_size", UiTokens.SIZE_GUIDE_FONT)
	reset_size()

## The sentence and its icon (null = the main's default sprout).
func show_tip(text: String, icon: Texture2D = null) -> void:
	set_tip(text)
	_icon.texture = icon if icon != null else DEFAULT_ICON

func set_tip(v: String) -> void:
	tip = v
	if _text: _text.text = v
	reset_size()

func icon_texture() -> Texture2D: return _icon.texture

## A tap closes the card on release, within GestureArbiter's slop and time, as UiEntryCard: a press that drags on
## (a thumb heading for the joystick) leaves it up (刘邦 on #110). One event family only (mouse buttons; raw touches
## only without touchscreen emulation).
func _gui_input(e: InputEvent) -> void:
	var is_mouse: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT
	var is_touch: bool = e is InputEventScreenTouch and not DisplayServer.is_touchscreen_available()
	if not (is_mouse or is_touch): return
	accept_event()
	if e.pressed:
		_down_at = e.position
		_down_ms = Time.get_ticks_msec()
		return
	var tap: bool = _down_at != Vector2.INF and e.position.distance_to(_down_at) <= GestureArbiter.TAP_SLOP \
		and Time.get_ticks_msec() - _down_ms <= GestureArbiter.TAP_MAX_MS
	_down_at = Vector2.INF
	if tap: tapped.emit()
