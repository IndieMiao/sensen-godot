class_name UiActionKey
extends Control
## ActionKey 1117:78924 (SGODOT-221, LOCK-02 / 03): the bottom-right action group, 95 × 148.
##   switch key (48, LOCK-03)  above the main key; tap → switch_pressed (the owner opens the action radial)
##   main key (UiSceneAction 88, LOCK-02)   see UiSceneAction for its states and touch-down firing
##   tool badge (28)           top-left of the main key, the equipped tool; display only, never a touch target
##   caption (optional)        one line under the group, e.g. "uses your Energy" (first-time hint)
## Pure facility spaces (kitchen, counters) hide this whole group (LOCK-07, plan §10.3.5).
## Clay (C-185 §3.7, owner Q-285; C-186), `UiActionKey.new(true)`: the group is 112 wide (95 → 112), the main key the
## 104 × 96 clay lump (UiSceneAction clay), the tool badge a 34 cream clay disc with its 22 icon, the switch key a 44
## dark glass disc with white arrows (its hit area stays 48) that spins its arrows 180° when tapped. `shown` plays
## MS-23: the group pops in 0.6 → 1 (200, pop) and fades in; hiding shrinks to 0.9 and fades (120) before it hides.

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
var clay := false
## MS-23: false once the group is (being) hidden; set with set_shown().
var shown := true
var _show_tween: Tween
var _switch_icon: TextureRect

# Clay layout: the switch 44 centred over the key, the key 104 × 96 at (8, 56), the badge 34 at (0, 50).
const _CLAY_KEY := Vector2(8, 56)
const _CLAY_BADGE := Vector2(0, 50)

func _init(clay_ := false) -> void:
	clay = clay_
	custom_minimum_size = _group_size()
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_switch = _build_switch()
	add_child(_switch)
	_key = UiSceneAction.new(clay)
	_key.position = _CLAY_KEY if clay else Vector2(_KEY_X, _KEY_Y)
	add_child(_key)
	_badge = _build_badge()
	add_child(_badge)
	_caption = UiKit.label("", UiTokens.STYLE_CAPTION_B12)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override(&"font_outline_color", UiTokens.COLOR_SURFACE)
	_caption.add_theme_constant_override(&"outline_size", _CAPTION_HALO)
	_caption.position = Vector2(-1, _group_size().y + 4.0 if clay else _CAPTION_Y)
	_caption.size = Vector2(_group_size().x + 1, _CAPTION_H)
	add_child(_caption)
	_refresh()

func set_tool_icon(v: Texture2D) -> void:
	if v == tool_icon: return
	var had := tool_icon != null
	tool_icon = v
	_refresh()
	if had and v != null: _pop_badge_icon()
func set_caption(v: String) -> void: caption = v; _refresh()
func set_switch_visible(v: bool) -> void: switch_visible = v; _refresh()

func key() -> UiSceneAction: return _key

## The group's box: 95 × 148 round, 112 × 152 clay.
func _group_size() -> Vector2:
	if clay: return Vector2(UiTokens.SIZE_CLAY_KEY_GROUP_W, _CLAY_KEY.y + UiTokens.SIZE_CLAY_KEY_H)
	return Vector2(UiTokens.SIZE_ACTION_KEY_W, UiTokens.SIZE_ACTION_KEY_H)

## MS-23: shows the group with a pop (0.6 → 1, 200) or hides it (0.9 and fade, 120). Showing is immediate in
## `visible`; hiding keeps it drawn until the fade ends but stops taking touches at once. Reduced: 120 fades.
func set_shown(v: bool) -> void:
	if v == shown and (v == visible): return
	shown = v
	if _show_tween != null and _show_tween.is_valid(): _show_tween.kill()
	pivot_offset = Vector2(size.x * 0.5, size.y)
	var animate := clay and is_inside_tree() and get_parent() is CanvasItem and (get_parent() as CanvasItem).is_visible_in_tree()
	if v:
		var was := visible
		visible = true
		_key.mouse_filter = Control.MOUSE_FILTER_STOP
		if not animate or was:
			scale = Vector2.ONE
			modulate.a = 1.0
			return
		modulate.a = 0.0
		var ms := UiTokens.MOTION_DURATION_FAST_MS if UiMotion.reduced else UiTokens.MOTION_DURATION_BASE_MS
		_show_tween = UiMotion.tween(self, UiTokens.MOTION_EASING_POP)
		if not UiMotion.reduced:
			scale = Vector2.ONE * UiTokens.MOTION_SCALE_KEY_CONTENT_FROM
			_show_tween.tween_property(self, "scale", Vector2.ONE, UiMotion.secs(ms))
		_show_tween.parallel().tween_property(self, "modulate:a", 1.0, UiMotion.secs(ms)).set_trans(Tween.TRANS_CUBIC)
		return
	if not visible: return
	if not animate:
		visible = false
		return
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_show_tween = UiMotion.tween(self, UiTokens.MOTION_EASING_EXIT)
	if not UiMotion.reduced:
		_show_tween.tween_property(self, "scale", Vector2.ONE * UiTokens.MOTION_SCALE_KEY_HIDE, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	_show_tween.parallel().tween_property(self, "modulate:a", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	_show_tween.tween_callback(func():
		visible = false
		scale = Vector2.ONE
		modulate.a = 1.0
		_key.mouse_filter = Control.MOUSE_FILTER_STOP)

## The optional caption hangs below the 148 px group (y 152 in the main); count it while it shows.
func _get_minimum_size() -> Vector2:
	var g := _group_size()
	var h := g.y
	if caption != "": h = _caption.position.y + _CAPTION_H if _caption != null else g.y
	return Vector2(g.x, h)
func switch_button() -> Button: return _switch
func tool_badge() -> Control: return _badge

func _build_switch() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var s := UiTokens.SIZE_SWITCH_KEY
	b.position = Vector2(_SWITCH_X, 0)
	b.size = Vector2(s, s)
	b.custom_minimum_size = b.size
	if clay: return _build_clay_switch(b)
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

## The tool badge pops 1 → 1.15 → 1 (150 ms) when an action is picked on the radial (SGODOT-247).
func pop_tool() -> void:
	if _badge == null or not _badge.visible: return
	_badge.pivot_offset = _badge.size * 0.5
	var half := UiKit.secs(UiTokens.MOTION_RADIAL_TAP_MS * 0.5)
	var t := _badge.create_tween()
	t.tween_property(_badge, ^"scale", Vector2.ONE * 1.15, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_badge, ^"scale", Vector2.ONE, half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _build_badge() -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE   # display only (LOCK-02 工具徽标只显示)
	var s := float(UiTokens.SIZE_CLAY_KEY_TOOL_BADGE if clay else UiTokens.SIZE_TOOL_BADGE)
	var icon := float(UiTokens.SIZE_CLAY_KEY_TOOL_ICON if clay else UiTokens.SIZE_TOOL_BADGE_ICON)
	p.position = _CLAY_BADGE if clay else Vector2(0, _BADGE_Y)
	p.size = Vector2(s, s)
	if clay: p.add_theme_stylebox_override(&"panel", UiClay.face(s * 0.5))
	else: p.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, s * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT))
	_tool = UiKit.icon(null, icon)
	_tool.position = Vector2((s - icon) * 0.5, (s - icon) * 0.5)
	_tool.size = Vector2(icon, icon)
	p.add_child(_tool)
	return p

## Clay: a 44 dark glass disc with white arrows centred in the 48 hit area, over the key's centre.
func _build_clay_switch(b: Button) -> Button:
	var hit := float(UiTokens.SIZE_SWITCH_KEY)
	var s := float(UiTokens.SIZE_CLAY_KEY_SWITCH)
	b.position = Vector2(_CLAY_KEY.x + UiTokens.SIZE_CLAY_KEY_W * 0.5 - hit * 0.5, 0)
	var inset := (hit - s) * 0.5
	var box := UiClay.glass_dark(s * 0.5)
	box.expand_margin_left = -inset
	box.expand_margin_right = -inset
	box.expand_margin_top = -inset
	box.expand_margin_bottom = -inset
	var down := UiClay.glass_dark(s * 0.5)
	down.bg_color = UiTokens.COLOR_GLASS_DARK.darkened(0.2)
	down.expand_margin_left = -inset
	down.expand_margin_right = -inset
	down.expand_margin_top = -inset
	down.expand_margin_bottom = -inset
	for k in [&"normal", &"hover", &"focus", &"disabled"]: b.add_theme_stylebox_override(k, box)
	for k in [&"pressed", &"hover_pressed"]: b.add_theme_stylebox_override(k, down)
	var i := float(UiTokens.SIZE_SWITCH_ICON)
	_switch_icon = UiKit.icon(SWITCH_GLYPH, i)
	_switch_icon.position = Vector2((hit - i) * 0.5, (hit - i) * 0.5)
	_switch_icon.size = Vector2(i, i)
	_switch_icon.pivot_offset = Vector2(i, i) * 0.5
	_switch_icon.modulate = UiTokens.COLOR_TEXT_ON_DARK
	b.add_child(_switch_icon)
	b.pressed.connect(func():
		if UiMotion.reduced or not b.is_inside_tree(): return
		var tw := UiMotion.tween(_switch_icon, UiTokens.MOTION_EASING_POP)
		tw.tween_property(_switch_icon, "rotation", _switch_icon.rotation + deg_to_rad(UiTokens.MOTION_ANGLE_SWITCH_SPIN),
			UiMotion.secs(UiTokens.MOTION_DURATION_BASE_MS)))
	b.pressed.connect(func(): switch_pressed.emit())
	return b

## MS-22's badge: when the tool icon changes, the new one pops 0.6 → 1 (200) with the key.
func _pop_badge_icon() -> void:
	if not clay or UiMotion.reduced or not is_visible_in_tree(): return
	_tool.pivot_offset = _tool.size * 0.5
	_tool.scale = Vector2.ONE * UiTokens.MOTION_SCALE_KEY_CONTENT_FROM
	var tw := UiMotion.tween(_tool, UiTokens.MOTION_EASING_POP)
	tw.tween_property(_tool, "scale", Vector2.ONE, UiMotion.secs(UiTokens.MOTION_DURATION_KEY_CONTENT_MS))

func _refresh() -> void:
	if _badge == null: return
	_tool.texture = tool_icon
	_badge.visible = tool_icon != null
	_switch.visible = switch_visible
	_caption.text = caption
	_caption.visible = caption != ""
	update_minimum_size()
