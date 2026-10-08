class_name UiSysBanner
extends PanelContainer
## SysBanner 1187:82581 (WP6, SGODOT-206 accepted; SGODOT-233): the system line under the HUD (x 16, y 100 of 800),
## 328 × 40, over the scene and over an open drawer (SYS-OFFLINE-3).
##   OFFLINE      ink fill, white wifi-off glyph and `Offline · Reconnecting…`, a Retry pill (white 16 %, white edge)
##   BACK_ONLINE  primary fill, white wifi glyph and `Back online` (the host takes it down after a moment)
##   CMD_FAIL     danger tint with a danger edge, the alert glyph and `Didn't go through · try again` in ink
## Retry shows on OFFLINE only and emits retry_pressed; the host decides what retrying does.

signal retry_pressed

enum Kind { OFFLINE, BACK_ONLINE, CMD_FAIL }

const WIDTH := 328.0
const HEIGHT := 40.0
# SysBanner main (WP6; not exported as tokens yet, like the other system mains):
const _RADIUS := 14.0
const _PAD := Vector4(12, 5, 6, 5)   # left, top, right, bottom: 6 in Figma, but the 30 high Retry centres at y 5
const _GAP := 8.0
const _ICON := 20.0
const _RETRY_PAD := Vector2(14, 6)
const _RETRY_ALPHA := 0.16
const _SHADOW_SIZE := 12.0
const _SHADOW_Y := 4.0
const _GLYPHS := {
	Kind.OFFLINE: preload("res://assets/ui/kit_icons/wifi_off.svg"),
	Kind.BACK_ONLINE: preload("res://assets/ui/kit_icons/wifi.svg"),
	Kind.CMD_FAIL: preload("res://assets/ui/kit_icons/alert.svg"),
}

var kind: Kind = Kind.OFFLINE: set = set_kind
var message := "Offline · Reconnecting…": set = set_message

var _glyph: TextureRect
var _label: Label
var _retry: Button

func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	# A status line that may stay up a long while (Offline): taps on it reach the scene or drawer under it; only
	# Retry takes its own.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", int(_GAP))
	add_child(row)
	_glyph = UiKit.icon(null, _ICON)
	_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_glyph)
	_label = UiKit.label("", UiTokens.STYLE_C14_XB)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.clip_text = true
	row.add_child(_label)
	_retry = Button.new()
	_retry.text = "Retry"
	_retry.focus_mode = Control.FOCUS_NONE
	_retry.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_retry.pressed.connect(func(): retry_pressed.emit())
	var pill := UiStyleBox.make(UiKit.alpha(UiTokens.COLOR_SURFACE_RAISED, _RETRY_ALPHA), _RADIUS, UiTokens.COLOR_SURFACE_RAISED, UiTokens.STROKE_DEFAULT)
	pill.with_margins(_RETRY_PAD.x, _RETRY_PAD.y, _RETRY_PAD.x, _RETRY_PAD.y)
	for st in [&"normal", &"hover", &"pressed", &"focus"]: _retry.add_theme_stylebox_override(st, pill)
	_retry.add_theme_font_override(&"font", UiKit.theme().get_font(&"font", UiTokens.STYLE_C12_XB))
	_retry.add_theme_font_size_override(&"font_size", UiKit.theme().get_font_size(&"font_size", UiTokens.STYLE_C12_XB))
	for c in [&"font_color", &"font_hover_color", &"font_pressed_color"]: _retry.add_theme_color_override(c, UiTokens.COLOR_SURFACE_RAISED)
	row.add_child(_retry)
	_refresh()

func set_kind(v: Kind) -> void: kind = v; _refresh()
func set_message(v: String) -> void: message = v; _refresh()

## The Retry pill (tests press it).
func retry_button() -> Button: return _retry

func _refresh() -> void:
	if _label == null: return
	var fill := UiTokens.COLOR_TEXT
	var edge := Color.TRANSPARENT
	var ink := UiTokens.COLOR_SURFACE_RAISED
	match kind:
		Kind.BACK_ONLINE: fill = UiTokens.COLOR_PRIMARY
		Kind.CMD_FAIL:
			fill = UiTokens.COLOR_DANGER_TINT
			edge = UiTokens.COLOR_DANGER
			ink = UiTokens.COLOR_TEXT
	var box := UiStyleBox.make(fill, _RADIUS, edge, UiTokens.STROKE_DEFAULT if kind == Kind.CMD_FAIL else 0.0)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = _SHADOW_SIZE
	box.shadow_offset = Vector2(0, _SHADOW_Y)
	add_theme_stylebox_override(&"panel", box.with_margins(_PAD.x, _PAD.y, _PAD.z, _PAD.w))
	_glyph.texture = _GLYPHS[kind]
	_label.text = message
	_label.add_theme_color_override(&"font_color", ink)
	_retry.visible = kind == Kind.OFFLINE
