class_name UiLookOption
extends Control
## LookOption (Figma 2196:120904; LOOK-PICK, SGODOT-282 49498df6 / e2d76a7c): one Homestead look to pick. 158 wide:
## a 158 × 100 thumbnail under the card's 12 top corners, the look's name 15 ExtraBold under it (12 inset, up to two
## lines), on color/surfaceRaised. Selected: a 2 px color/primary edge and a 22 px primary disc with a white check, 8 in
## from the top right; default: a 1 px color/border edge. Two stand side by side as tall as the taller (pair()).
## A tap emits `picked`.

signal picked

const W := 158.0
const THUMB_H := 100.0
const RADIUS := 12
const PAD := 12.0
const CHECK := 22.0
const CHECK_GLYPH := 14.0
const CHECK_INSET := 8.0
const _CHECK_ICON := preload("res://assets/ui/kit_icons/check.svg")

var look_name := "": set = set_look_name
var thumbnail: Texture2D: set = set_thumbnail
var selected := false: set = set_selected

var _card: Panel       # the white card; clips the thumbnail to its rounded corners
var _thumb: TextureRect
var _name: Label
var _edge: Panel       # the edge over everything (the thumbnail would cover the card's own border)
var _check: Control

func _init(name_: String = "", thumb: Texture2D = null) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_card = Panel.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_card.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, RADIUS))
	add_child(_card)
	_thumb = TextureRect.new()
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumb.position = Vector2.ZERO
	_thumb.size = Vector2(W, THUMB_H)
	_card.add_child(_thumb)
	_name = UiKit.label("", UiTokens.STYLE_ROW_TITLE_XB15)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible = 2
	_name.position = Vector2(PAD, THUMB_H + PAD)
	_name.size = Vector2(W - PAD * 2.0, 0)
	_name.custom_minimum_size.x = W - PAD * 2.0
	_card.add_child(_name)
	_edge = Panel.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_edge)
	_check = _CheckDisc.new()
	_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check.size = Vector2(CHECK, CHECK)
	add_child(_check)
	_name.minimum_size_changed.connect(_layout)
	resized.connect(_layout)
	look_name = name_
	thumbnail = thumb
	_apply()

func set_look_name(v: String) -> void:
	look_name = v
	if _name: _name.text = v
	_layout()

func set_thumbnail(v: Texture2D) -> void:
	thumbnail = v
	if _thumb: _thumb.texture = v

func set_selected(v: bool) -> void:
	selected = v
	_apply()

## The card's natural height: thumbnail, 12, the name (one or two 20 px lines), 12 — 144 or 164.
func natural_height() -> float:
	return THUMB_H + PAD * 2.0 + maxf(20.0, _name.get_combined_minimum_size().y)

## Two cards side by side as tall as the taller one (e2d76a7c: `Timber Kitchen Wing` takes two lines).
static func pair(a: UiLookOption, b: UiLookOption) -> void:
	var h := maxf(a.natural_height(), b.natural_height())
	for o in [a, b]: (o as UiLookOption).custom_minimum_size = Vector2(W, h)

func _apply() -> void:
	if _edge == null: return
	_edge.add_theme_stylebox_override(&"panel", UiStyleBox.make(Color.TRANSPARENT, RADIUS,
		UiTokens.COLOR_PRIMARY if selected else UiTokens.COLOR_BORDER, 2.0 if selected else float(UiTokens.STROKE_DEFAULT)))
	_check.visible = selected

func _layout() -> void:
	if _card == null: return
	if custom_minimum_size.y < natural_height(): custom_minimum_size = Vector2(W, natural_height())
	_card.size = size
	_edge.size = size
	_check.position = Vector2(size.x - CHECK_INSET - CHECK, CHECK_INSET)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		accept_event()
		picked.emit()

## The 22 px primary disc with the white check (Selected check, 14 px glyph).
class _CheckDisc extends Control:
	func _draw() -> void:
		draw_circle(size * 0.5, UiLookOption.CHECK * 0.5, UiTokens.COLOR_PRIMARY)
		var g := UiLookOption.CHECK_GLYPH
		draw_texture_rect(UiLookOption._CHECK_ICON, Rect2((size - Vector2(g, g)) * 0.5, Vector2(g, g)), false, Color.WHITE)
