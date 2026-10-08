class_name UiBarDropZone
extends Control
## BarDropZone 1588:97952 (LOCK-04 / 05 v1.11, 221 b0a83924): the two places a lifted quick-bar slot can be dropped
## to change it. Both fade in when a slot lifts (FADE_IN_MS), centred `center` over the bar (Pin / Unpin at x 72,
## Remove at x 168, y 612 on 360 × 800); hover = the finger within GestureArbiter.DROP_ZONE_HIT of the centre.
##   Pin / Unpin  amber (the pin is amber, LOCK-05): Idle 64 surface circle, 2 px amber dashed edge, i-pin /
##                i-pin-off and `Pin` / `Unpin` in warning ink; Hover 72 amber disc, ink glyph, `Release to pin`
##   Remove       never red (the item stays in the Bag): Idle 64 surface circle, secondary dashed edge, i-trash and
##                `Remove` in secondary ink; Hover 72 ink disc, surface glyph, `Release to remove`
## The label sits in a surface pill (radius 12, 10 / 4 inset) 6 below the circle; the circle carries shadow/menu.
## Display only, takes no touches.

enum Kind { PIN, UNPIN, REMOVE }

const PIN_GLYPH := preload("res://assets/ui/kit_icons/pin.svg")
const PIN_OFF_GLYPH := preload("res://assets/ui/kit_icons/pin_off.svg")
const TRASH_GLYPH := preload("res://assets/ui/kit_icons/trash.svg")
const FADE_IN_MS := 120
const FADE_OUT_MS := 200
const _IDLE_D := 64.0
const _HOVER_D := 72.0
const _IDLE_GLYPH := 24.0
const _HOVER_GLYPH := 28.0
const _EDGE := 2.0
const _DASH := Vector2(5, 4)   # dash, gap
const _PILL_GAP := 6.0
const _PILL_H := 24.0
const _PILL_PAD := 10.0
const IDLE_TEXT := {Kind.PIN: "Pin", Kind.UNPIN: "Unpin", Kind.REMOVE: "Remove"}
const HOVER_TEXT := {Kind.PIN: "Release to pin", Kind.UNPIN: "Release to unpin", Kind.REMOVE: "Release to remove"}

var kind: Kind = Kind.REMOVE: set = set_kind
var hover := false: set = set_hover
## Layer point the target circle is centred on (top_level: the same space as the quick bar's global rect).
var center := Vector2.ZERO: set = set_center

var _glyph: TextureRect
var _pill: PanelContainer
var _label: Label

func _init(kind_: Kind = Kind.REMOVE) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	_glyph = UiKit.icon(TRASH_GLYPH, _IDLE_GLYPH)
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glyph)
	_pill = PanelContainer.new()
	_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, _PILL_H * 0.5).with_margins(_PILL_PAD, 0, _PILL_PAD, 0))
	add_child(_pill)
	_label = UiKit.label("", UiTokens.STYLE_C12_XB)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.custom_minimum_size.y = _PILL_H
	_pill.add_child(_label)
	_pill.minimum_size_changed.connect(_layout)   # the label sizes once the theme reaches it
	kind = kind_

func _ready() -> void:
	_layout()

func set_kind(v: Kind) -> void:
	kind = v
	_restyle()

func set_hover(v: bool) -> void:
	hover = v
	_restyle()

func set_center(v: Vector2) -> void:
	center = v
	_layout()

func diameter() -> float: return _HOVER_D if hover else _IDLE_D

## Ink of the glyph and the label, by kind and state.
func _ink() -> Array:
	if kind == Kind.REMOVE:
		return [UiTokens.COLOR_SURFACE, UiTokens.COLOR_TEXT] if hover else [UiTokens.COLOR_SECONDARY, UiTokens.COLOR_SECONDARY]
	return [UiTokens.COLOR_TEXT, UiTokens.COLOR_TEXT] if hover else [UiTokens.COLOR_WARNING, UiTokens.COLOR_WARNING]

func _restyle() -> void:
	_glyph.texture = {Kind.PIN: PIN_GLYPH, Kind.UNPIN: PIN_OFF_GLYPH, Kind.REMOVE: TRASH_GLYPH}[kind]
	var ink := _ink()
	_glyph.self_modulate = ink[0]
	_label.text = str((HOVER_TEXT if hover else IDLE_TEXT)[kind])
	_label.add_theme_color_override(&"font_color", ink[1])
	var g := _HOVER_GLYPH if hover else _IDLE_GLYPH
	_glyph.custom_minimum_size = Vector2(g, g)
	_glyph.size = Vector2(g, g)
	_layout()

func _layout() -> void:
	var d := diameter()
	var pill := _pill.get_combined_minimum_size()
	size = Vector2(maxf(d, pill.x), d + _PILL_GAP + _PILL_H)
	position = center - Vector2(size.x * 0.5, d * 0.5)   # top_level: position is in the layer, like `center`
	_glyph.position = Vector2(size.x * 0.5, d * 0.5) - _glyph.size * 0.5
	_pill.set_deferred(&"size", pill)
	_pill.position = Vector2((size.x - pill.x) * 0.5, d + _PILL_GAP)
	queue_redraw()

func _draw() -> void:
	var c := Vector2(size.x * 0.5, diameter() * 0.5)
	var r := diameter() * 0.5
	var edge := UiTokens.COLOR_SECONDARY if kind == Kind.REMOVE else UiTokens.COLOR_AMBER
	var fill := UiTokens.COLOR_SURFACE
	if hover: fill = UiTokens.COLOR_TEXT if kind == Kind.REMOVE else UiTokens.COLOR_AMBER
	# Both states sit over the scene, so the circle carries shadow/menu (0 4 12) like the menu cards.
	var disc := UiStyleBox.make(fill, r)
	disc.shadow_color = UiTokens.COLOR_SHADOW_MENU
	disc.shadow_size = UiTokens.SIZE_SHADOW_MENU_RADIUS
	disc.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_MENU_OFFSET_Y)
	draw_style_box(disc, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	if hover: return
	# Dashed edge (5 on, 4 off) around the circle.
	var step := (_DASH.x + _DASH.y) / (r - _EDGE * 0.5)
	var on := _DASH.x / (r - _EDGE * 0.5)
	var a := 0.0
	while a < TAU:
		draw_arc(c, r - _EDGE * 0.5, a, minf(a + on, TAU), 4, edge, _EDGE, true)
		a += step

## Fade in over FADE_IN_MS (call when it enters the tree).
func appear() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, ^"modulate:a", 1.0, UiKit.secs(FADE_IN_MS))

## Fade out over FADE_OUT_MS, then free.
func vanish() -> void:
	var t := create_tween()
	t.tween_property(self, ^"modulate:a", 0.0, UiKit.secs(FADE_OUT_MS))
	t.tween_callback(queue_free)
