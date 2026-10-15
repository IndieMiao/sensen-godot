class_name UiBigPotKey
extends Control
## Compact/BigPotKey 2729:153438 (q(201), 安其拉 row 99; 不知火舞 on 286): the Big Pot switch for the current stove, the
## same size as Cook — a 68 × 34 surface, radius 17, in a 44 px touch row — with only the i-big-pot icon (20 px), no
## word. Off: surfaceRaised, a 1 px border, the icon in ink. On: the selected look (primaryTint, a 1.5 px primary
## outline, the icon green), never the solid green of Cook. Greyed (`enabled` false): the same look at 50 %, showing on
## or off; a tap says why (`refused(toast)`) and never flips it. Emits `toggled(on)`.

signal toggled(on: bool)
signal refused(reason: String)

const ICON := preload("res://assets/ui/kit_icons/big_pot.svg")
const _W := 68.0
const _ICON := 20.0

var on := false: set = set_on
var enabled := true: set = set_enabled
var toast := ""

var _surface: Panel
var _icon: TextureRect

func _init() -> void:
	custom_minimum_size = Vector2(_W, UiTokens.SIZE_TOUCH)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface = Panel.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.position = Vector2(0, (UiTokens.SIZE_TOUCH - UiTokens.SIZE_COMMAND_COMPACT) * 0.5)
	_surface.size = Vector2(_W, UiTokens.SIZE_COMMAND_COMPACT)
	add_child(_surface)
	_icon = UiKit.icon(ICON, _ICON)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.position = (Vector2(_W, UiTokens.SIZE_COMMAND_COMPACT) - Vector2(_ICON, _ICON)) * 0.5
	_icon.size = Vector2(_ICON, _ICON)
	_surface.add_child(_icon)
	var hit := Button.new()   # the 44 px touch row, flat: the surface above draws the key
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(press)
	add_child(hit)
	_restyle()

## A tap: flips and says so when enabled, else says why it cannot (also what tests and shots call).
func press() -> void:
	if not enabled:
		refused.emit(toast)
		return
	on = not on
	toggled.emit(on)

func set_on(v: bool) -> void:
	on = v
	_restyle()

func set_enabled(v: bool) -> void:
	enabled = v
	_restyle()

func _restyle() -> void:
	if _surface == null: return
	var box := UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT if on else UiTokens.COLOR_SURFACE_RAISED, UiTokens.RADIUS_COMPACT_COMMAND,
		UiTokens.COLOR_PRIMARY if on else UiTokens.COLOR_BORDER, UiTokens.STROKE_SELECTED_CELL if on else UiTokens.STROKE_DEFAULT)
	_surface.add_theme_stylebox_override(&"panel", box)
	_icon.self_modulate = UiTokens.COLOR_PRIMARY if on else UiTokens.COLOR_TEXT
	_surface.modulate.a = 1.0 if enabled else 0.5   # Off grey / On grey: the whole key at 50 % (不知火舞 on 286 ①)

## The drawn 68 × 34 surface on screen (shots, tests).
func surface_rect() -> Rect2: return _surface.get_global_rect()
