class_name UiActionKey
extends Control
## ActionKey 1117:78924 (SGODOT-221, LOCK-02 / 03): the bottom-right action group, 95 × 148.
##   switch key (48, LOCK-03)  above the main key; tap → switch_pressed (the owner opens the action radial)
##   main key (UiSceneAction 88, LOCK-02)   see UiSceneAction for its states and touch-down firing
##   tool badge (28)           top-left of the main key, the equipped tool; display only, never a touch target
##   caption (optional)        one line under the group, e.g. "uses your Energy" (first-time hint)
## Pure facility spaces (kitchen, counters) hide this whole group (LOCK-07, plan §10.3.5).

signal switch_pressed

const SWITCH_GLYPH := preload("res://assets/p0/icons/switch.svg")

# Layout of the ActionKey main (1117:78924):
const _SWITCH_X := 27.0           # switch key 48 at (27, 0)
const _KEY_X := 7.0               # main key 88 at (7, 60)
const _KEY_Y := 60.0
const _BADGE_Y := 54.0            # tool badge 28 at (0, 54), tool icon 18 inside
const _CAPTION_Y := 152.0         # caption 96 × 16 at (-1, 152), 3 px surface halo
const _CAPTION_H := 16.0
const _CAPTION_HALO := 3

## Equipped tool shown in the badge (hoe, rod, pickaxe, sword); null hides the badge.
var tool_icon: Texture2D: set = set_tool_icon
var caption := "": set = set_caption
## Hide the switch key where only one action exists.
var switch_visible := true: set = set_switch_visible

var _switch: Button
var _key: UiSceneAction
var _badge: Panel
var _tool: TextureRect
var _caption: Label

func _init() -> void:
	custom_minimum_size = Vector2(UiTokens.SIZE_ACTION_KEY_W, UiTokens.SIZE_ACTION_KEY_H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_switch = _build_switch()
	add_child(_switch)
	_key = UiSceneAction.new()
	_key.position = Vector2(_KEY_X, _KEY_Y)
	add_child(_key)
	_badge = _build_badge()
	add_child(_badge)
	_caption = UiKit.label("", UiTokens.STYLE_CAPTION_B12)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override(&"font_outline_color", UiTokens.COLOR_SURFACE)
	_caption.add_theme_constant_override(&"outline_size", _CAPTION_HALO)
	_caption.position = Vector2(-1, _CAPTION_Y)
	_caption.size = Vector2(UiTokens.SIZE_ACTION_KEY_W + 1, _CAPTION_H)
	add_child(_caption)
	_refresh()

func set_tool_icon(v: Texture2D) -> void:
	if v != tool_icon: tool_icon = v; _refresh()
func set_caption(v: String) -> void: caption = v; _refresh()
func set_switch_visible(v: bool) -> void: switch_visible = v; _refresh()

func key() -> UiSceneAction: return _key

## The optional caption hangs below the 148 px group (y 152 in the main); count it while it shows.
func _get_minimum_size() -> Vector2:
	var h := UiTokens.SIZE_ACTION_KEY_H
	if caption != "": h = _CAPTION_Y + _CAPTION_H
	return Vector2(UiTokens.SIZE_ACTION_KEY_W, h)
func switch_button() -> Button: return _switch
func tool_badge() -> Control: return _badge

func _build_switch() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var s := UiTokens.SIZE_SWITCH_KEY
	b.position = Vector2(_SWITCH_X, 0)
	b.size = Vector2(s, s)
	b.custom_minimum_size = b.size
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, s * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_KEY
	box.shadow_size = UiTokens.SIZE_SHADOW_KEY_RADIUS
	box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_KEY_OFFSET_Y)
	var down := UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, s * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	for k in [&"normal", &"hover", &"focus", &"disabled"]: b.add_theme_stylebox_override(k, box)
	for k in [&"pressed", &"hover_pressed"]: b.add_theme_stylebox_override(k, down)
	var icon := UiKit.icon(SWITCH_GLYPH, UiTokens.SIZE_SWITCH_ICON)
	icon.position = Vector2((s - UiTokens.SIZE_SWITCH_ICON) * 0.5, (s - UiTokens.SIZE_SWITCH_ICON) * 0.5)
	icon.size = Vector2(UiTokens.SIZE_SWITCH_ICON, UiTokens.SIZE_SWITCH_ICON)
	b.add_child(icon)
	b.pressed.connect(func(): switch_pressed.emit())
	return b

func _build_badge() -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE   # display only (LOCK-02 工具徽标只显示)
	var s := UiTokens.SIZE_TOOL_BADGE
	p.position = Vector2(0, _BADGE_Y)
	p.size = Vector2(s, s)
	p.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, s * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
	_tool = UiKit.icon(null, UiTokens.SIZE_TOOL_BADGE_ICON)
	_tool.position = Vector2((s - UiTokens.SIZE_TOOL_BADGE_ICON) * 0.5, (s - UiTokens.SIZE_TOOL_BADGE_ICON) * 0.5)
	_tool.size = Vector2(UiTokens.SIZE_TOOL_BADGE_ICON, UiTokens.SIZE_TOOL_BADGE_ICON)
	p.add_child(_tool)
	return p

func _refresh() -> void:
	if _badge == null: return
	_tool.texture = tool_icon
	_badge.visible = tool_icon != null
	_switch.visible = switch_visible
	_caption.text = caption
	_caption.visible = caption != ""
	update_minimum_size()
