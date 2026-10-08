class_name UiBarRemoveZone
extends Control
## BarRemoveZone 1588:97952 (LOCK-04 / 05 v1.10, user hands-on feedback 2026-10-08): the one way to take an item off
## the quick bar by dragging. The quick bar shows it when a lifted slot starts to drag, its target centred on
## `center` (screen x-centre, GestureArbiter.REMOVE_ZONE_ABOVE over the bar), fading in over FADE_IN_MS.
##   Idle   64 px dashed circle (surface fill, shadow/menu, 2 px secondary edge) with the close glyph,
##          `Remove from bar` in a surface pill under it (radius 12, 10 / 4 inset, 6 below the circle)
##   Hover  72 px ink circle with the glyph in surface ink, `Release to remove` (finger within REMOVE_ZONE_HIT)
## Never red: taking an item off the bar is not destructive (it stays in the Bag). Display only, takes no touches.

const CLOSE_GLYPH := preload("res://assets/ui/kit_icons/close.svg")
const FADE_IN_MS := 120
const FADE_OUT_MS := 200
const _IDLE_D := 64.0
const _HOVER_D := 72.0
const _IDLE_GLYPH := 24.0    # the i-close instance (its 14 / 16 px cross inside)
const _HOVER_GLYPH := 28.0
const _EDGE := 2.0
const _DASH := 6.0
const _PILL_GAP := 6.0      # pill 70 / 78 below the target's top: 6 under the circle
const _PILL_H := 24.0
const _PILL_PAD := 10.0

var hover := false: set = set_hover
## Global point the target circle is centred on.
var center := Vector2.ZERO: set = set_center

var _glyph: TextureRect
var _pill: PanelContainer
var _label: Label

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	_glyph = UiKit.icon(CLOSE_GLYPH, _IDLE_GLYPH)
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
	hover = false

func _ready() -> void:
	_layout()

func set_hover(v: bool) -> void:
	hover = v
	_label.text = "Release to remove" if v else "Remove from bar"
	_label.add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT if v else UiTokens.COLOR_SECONDARY)
	_glyph.self_modulate = UiTokens.COLOR_SURFACE if v else UiTokens.COLOR_SECONDARY
	var g := _HOVER_GLYPH if v else _IDLE_GLYPH
	_glyph.custom_minimum_size = Vector2(g, g)
	_glyph.size = Vector2(g, g)
	_layout()

func set_center(v: Vector2) -> void:
	center = v
	_layout()

func diameter() -> float: return _HOVER_D if hover else _IDLE_D

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
	# Both states sit over the scene, so the circle carries shadow/menu (0 4 12) like the menu cards.
	var disc := UiStyleBox.make(UiTokens.COLOR_TEXT if hover else UiTokens.COLOR_SURFACE, r)
	disc.shadow_color = UiTokens.COLOR_SHADOW_MENU
	disc.shadow_size = UiTokens.SIZE_SHADOW_MENU_RADIUS
	disc.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_MENU_OFFSET_Y)
	draw_style_box(disc, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0))
	if hover: return
	# Dashed edge: short arcs around the circle.
	var n := int(TAU * r / (_DASH * 2.0))
	for i in n:
		var a := TAU * i / n
		draw_arc(c, r - _EDGE * 0.5, a, a + TAU / n * 0.5, 6, UiTokens.COLOR_SECONDARY, _EDGE, true)

## Fade in over FADE_IN_MS (call when it enters the tree).
func appear() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, ^"modulate:a", 1.0, UiKit.secs(FADE_IN_MS))

## Fade out over FADE_OUT_MS, then free.
func vanish() -> void:
	var t := create_tween()
	t.tween_property(self, ^"modulate:a", 0.0, UiKit.secs(FADE_OUT_MS))
	t.tween_callback(queue_free)
