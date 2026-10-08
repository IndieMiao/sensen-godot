class_name UiTipCard
extends PanelContainer
## TipCard 1243:87540 (TUT-2 482:72; A-03, §14.3; SGODOT-232 U6, 235-B2): the first session's one-sentence teaching card.
## Cream surface, 1 px border, radius 16, padding 14 / 12, a 22 px icon 10 before Nunito Bold 14 text, 296 wide and as
## tall as its text (48 for one line, 64 for two). No buttons and no Got it; a tap on it emits `tapped` (its owner closes
## it), and it never plays for the player. Where it sits and how long it stays are its owner's (P0Ui: centred, the top
## 120 under HUD row 2, above the kitchen drawer; the Toast's duration; it closes when the player does what it teaches).
## The shadow (0 / 10, blur 14, 20 %) is not a token yet (PENDING "tipCard"): constants here until the next export.

signal tapped

const WIDTH := 296.0
const _PAD_X := 14.0
const _PAD_Y := 12.0
const _GAP := 10
const _RADIUS := 16.0
const _ICON := 22.0
const _SHADOW := Color(0x2E / 255.0, 0x3B / 255.0, 0x33 / 255.0, 0.2)   # rgba(46, 59, 51, 0.2)
const _SHADOW_BLUR := 14.0
const _SHADOW_OFFSET := Vector2(0, 10)

## Each P0 tip's icon, as the TUT-2 specimens (不知火舞 on 232): Levels has no card of its own (it is inside the level-up
## banner) but keeps the main's default sprout.
const ICONS := {
	"sow": preload("res://assets/ui/kit_icons/tip/i-radish-seeds.svg"),
	"creel": preload("res://assets/ui/kit_icons/tip/i-fish.svg"),
	"cast": preload("res://assets/ui/kit_icons/tip/i-energy.svg"),
	"cook": preload("res://assets/ui/kit_icons/tip/i-pot.svg"),
	"heat": preload("res://assets/ui/kit_icons/tip/i-pot.svg"),
	"eat": preload("res://assets/ui/kit_icons/tip/i-energy.svg"),
	"map": preload("res://assets/ui/kit_icons/tip/i-map.svg"),
	"levels": preload("res://assets/ui/kit_icons/tip/i-sprout.svg"),
}
const DEFAULT_ICON := preload("res://assets/ui/kit_icons/tip/i-sprout.svg")

var tip := "": set = set_tip
var _icon: TextureRect
var _text: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	size = Vector2(WIDTH, 0)
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _RADIUS, UiTokens.COLOR_BORDER, 1.0).with_margins(_PAD_X, _PAD_Y, _PAD_X, _PAD_Y)
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

## The sentence and its icon (a tip key from P0Guide.TIPS, or a texture).
func show_tip(text: String, icon: Variant = null) -> void:
	set_tip(text)
	var tex: Texture2D = icon if icon is Texture2D else ICONS.get(str(icon), DEFAULT_ICON) if icon != null else DEFAULT_ICON
	_icon.texture = tex

func set_tip(v: String) -> void:
	tip = v
	if _text: _text.text = v
	reset_size()

func icon_texture() -> Texture2D: return _icon.texture

func _gui_input(e: InputEvent) -> void:
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		tapped.emit()
		accept_event()
