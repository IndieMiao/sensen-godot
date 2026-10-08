class_name UiWorldNameBar
extends Control
## World prompt name strip (SGODOT-250; WorldNameBar 1674:101190, LOCK-07 v2): the nearest facility within reach opens
## its icon button into this strip along the side the character faces. 32 high, color/surface pill with a 1 px
## color/border edge and a soft shadow; icon 22 + name (Caption ExtraBold 12) + at most one fact ("· Empty", Caption
## Bold 12, secondary). Side Right keeps the icon at the button's spot and opens to the right (padding 5 / 12); Left is
## the mirror, for a screen edge. Dimmed (used today, e.g. Rested today): icon 45 %, name in secondary ink. With a
## state the StatusBadge, scaled to 22, takes the icon's place (LOCK-11). No Tap to …, no finger. Opening and closing
## animate the width over 160 ms with the icon held still. Display only: a tap on it is a tap on the facility.

enum Dir { RIGHT, LEFT }   # not "Side": that is a global Godot enum

const _H := 32.0
const _ICON := 22.0
const _GAP := 6.0
const _PAD_ICON := 5.0       # on the icon's side
const _PAD_TEXT := 12.0      # on the text's side
const _EXPAND_MS := 160.0
const _DIM_ICON := 0.45

var icon: Texture2D: set = set_icon
var text := "": set = set_text
## One fact after the name ("Empty", "+60 Energy"), or "" for none.
var fact := "": set = set_fact
var side: Dir = Dir.RIGHT: set = set_side
var dimmed := false: set = set_dimmed
## A UiStatusBadge.State in the icon's place, or -1.
var status := -1: set = set_status

var _panel: PanelContainer
var _row: HBoxContainer
var _glyph: TextureRect
var _badge_holder: Control
var _badge: UiStatusBadge
var _name: Label
var _dot: Label
var _fact: Label
var _anchor := Vector2.ZERO   # the icon button's centre this strip opens from
var _open := 0.0              # 0 = folded to the icon, 1 = fully open
var _tween: Tween

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override(&"separation", int(_GAP))
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(_row)
	_glyph = UiKit.icon(null, _ICON)
	_glyph.custom_minimum_size = Vector2(_ICON, _ICON)
	_badge_holder = Control.new()
	_badge_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_holder.custom_minimum_size = Vector2(_ICON, _ICON)
	_name = UiKit.label("", UiTokens.STYLE_CAPTION_XB12, UiTokens.COLOR_TEXT)
	_dot = UiKit.label("·", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	_fact = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	for c in [_glyph, _badge_holder, _name, _dot, _fact]: _row.add_child(c)   # all stay in the row; _rebuild shows and orders
	_panel.minimum_size_changed.connect(_layout)
	_rebuild()

func set_icon(v: Texture2D) -> void: icon = v; _rebuild()
func set_text(v: String) -> void: text = v; _rebuild()
func set_fact(v: String) -> void: fact = v; _rebuild()
func set_side(v: Dir) -> void: side = v; _rebuild()
func set_dimmed(v: bool) -> void: dimmed = v; _rebuild()
func set_status(v: int) -> void: status = v; _rebuild()

func is_expanded() -> bool: return _open >= 1.0
## Opening progress, 0 (folded to the icon) … 1 (open).
func openness() -> float: return _open

## The strip's icon sits on the icon button's centre (its parent's coordinates); width changes keep it there.
func anchor_at(icon_center: Vector2) -> void:
	_anchor = icon_center
	_layout()

## Fully open width (the pill's natural size).
func full_width() -> float: return _panel.get_combined_minimum_size().x

## Width when folded: just the icon with its padding.
func folded_width() -> float: return _PAD_ICON * 2.0 + _ICON

func expand() -> void: _animate_to(1.0)
func collapse() -> void: _animate_to(0.0)

## Jump to an openness (gallery stills, tests).
func set_openness(v: float) -> void:
	if _tween: _tween.kill()
	_open = clampf(v, 0.0, 1.0)
	_layout()

## The strip's touch area, 44 tall, in global coordinates (the host's _tap_at tests it).
func hit_rect() -> Rect2:
	var r := get_global_rect()
	return r.grow_individual(0, (UiTokens.SIZE_TOUCH - r.size.y) * 0.5, 0, (UiTokens.SIZE_TOUCH - r.size.y) * 0.5)

func _animate_to(target: float) -> void:
	if _tween: _tween.kill()
	if not is_inside_tree():
		set_openness(target)
		return
	_tween = create_tween()
	_tween.tween_method(func(v: float):
		_open = v
		_layout(), _open, target, UiKit.secs(_EXPAND_MS * absf(target - _open))).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _rebuild() -> void:
	if _row == null: return
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _H * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 3)
	var right := side == Dir.RIGHT
	box.with_margins(_PAD_ICON if right else _PAD_TEXT, 0, _PAD_TEXT if right else _PAD_ICON, 0)
	_panel.add_theme_stylebox_override(&"panel", box)
	_panel.custom_minimum_size.y = _H
	_glyph.texture = icon
	_glyph.modulate.a = _DIM_ICON if dimmed else 1.0
	_name.text = text
	_name.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY if dimmed else UiTokens.COLOR_TEXT)
	_fact.text = fact
	if status >= 0:
		if _badge == null:
			_badge = UiStatusBadge.new(status, UiStatusBadge.Size.WORLD)
			var k := _ICON / float(UiTokens.SIZE_STATUS_BADGE_WORLD)
			_badge.scale = Vector2(k, k)   # StatusBadge World 28 scaled to 22 in the strip
			_badge_holder.add_child(_badge)
		_badge.state = status
		_badge.icon = icon
	_glyph.visible = status < 0
	_badge_holder.visible = status >= 0
	_dot.visible = fact != ""
	_fact.visible = fact != ""
	var order: Array[Control] = [_glyph, _badge_holder, _name, _dot, _fact]
	if not right: order.reverse()
	for i in order.size(): _row.move_child(order[i], i)
	_layout()

func _layout() -> void:
	if _panel == null: return
	var full := full_width()
	var w := lerpf(folded_width(), full, _open)
	size = Vector2(w, _H)
	_panel.size = Vector2(full, _H)
	# The icon stays on the anchor: Right grows to the right of it, Left to the left.
	var icon_off := _PAD_ICON + _ICON * 0.5
	if side == Dir.RIGHT:
		position = Vector2(_anchor.x - icon_off, _anchor.y - _H * 0.5)
		_panel.position = Vector2.ZERO
	else:
		position = Vector2(_anchor.x + icon_off - w, _anchor.y - _H * 0.5)
		_panel.position = Vector2(w - full, 0)
