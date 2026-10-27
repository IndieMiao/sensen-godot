class_name UiFeltAction
extends Control
## FeltAction (SGODOT-351 C13, 不知火舞 on 351 37022a3c / d835ac7e): an action printed on the Blackjack felt instead of
## a button — cream text, letter-spaced, in a thin capsule frame (1.5). Large (Deal / Hit / Stand) and Small (Double /
## Split / Rules); the touch area is never under 48 × 48. Pressed brightens and settles at 0.96; Disabled fades the text
## and frame to about 35% and prints the reason in a caption under it (the "grey keys say why" rule, printed). Sentence
## case as written (`Deal`), never upper-cased. Emits `activated` on release inside; a disabled one emits
## `unavailable_pressed(reason)`. Drawn here until 安其拉's master lands.

signal activated
signal unavailable_pressed(reason: String)

enum Size { LARGE, SMALL }

const INK := Color("FBF8F1")
const _FADED := 0.35
const _FRAME := 1.5
const _PAD := {Size.LARGE: Vector2(28, 10), Size.SMALL: Vector2(16, 6)}
const _FONT := {Size.LARGE: 20, Size.SMALL: 14}
const _SPACING := {Size.LARGE: 1, Size.SMALL: 1}   # 6% tracking at 20 / 14 (186:167316)
const _MIN_HIT := 51.0                             # the master's touch height

var text := "": set = set_text
var reason := "": set = set_reason
var enabled := true: set = set_enabled
var size_kind: Size = Size.LARGE
## Where the reason caption hangs from the frame: centred, or flush with its left / right edge (an action near the
## table's edge keeps its caption on the table).
var reason_align := HORIZONTAL_ALIGNMENT_CENTER: set = set_reason_align
## A printed word with no frame and no touch (the felt's two rule lines use the same lettering).
var plain := false

var _label: Label
var _why: Label
var _pressed := false

func _init(text_ := "", size_ := Size.LARGE, plain_ := false) -> void:
	size_kind = size_
	plain = plain_
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_IGNORE if plain else Control.MOUSE_FILTER_STOP
	_label = UiKit.label("", UiTokens.STYLE_TITLE_XB20 if size_ == Size.LARGE else UiTokens.STYLE_BODY_XB14, INK)
	_label.add_theme_font_size_override(&"font_size", _FONT[size_])
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_why = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiKit.alpha(INK, 0.8))
	_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_why.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_why.visible = false
	add_child(_why)
	text = text_

func set_text(v: String) -> void:
	text = v
	if _label == null: return
	_label.text = v
	var spacing := int(_SPACING[size_kind])
	var w := _text_w(v)
	_apply_spacing(spacing)
	var pad: Vector2 = _PAD[size_kind]
	var frame := Vector2(w + pad.x * 2.0, _FONT[size_kind] + 8.0 + pad.y * 2.0)
	custom_minimum_size = Vector2(maxf(frame.x, _MIN_HIT), maxf(frame.y, _MIN_HIT))
	size = custom_minimum_size
	pivot_offset = size * 0.5
	_label.position = Vector2.ZERO
	_label.size = size
	_lay_reason()
	queue_redraw()

## ExtraBold, letter-spaced: the printed look. The token font is itself a FontVariation (weight 800 over the variable
## file): a variation nested on it loses that weight (the kit's bold-italic note), so this copies its base and weight.
func _apply_spacing(spacing: int) -> void:
	var xb := UiKit.font(&"extrabold")
	var fv := FontVariation.new()
	if xb is FontVariation:
		fv.base_font = (xb as FontVariation).base_font
		fv.variation_opentype = (xb as FontVariation).variation_opentype
	else:
		fv.base_font = xb
	fv.spacing_glyph = spacing
	_label.add_theme_font_override(&"font", fv)

func _text_w(t: String) -> float:
	return UiKit.font(&"extrabold").get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, _FONT[size_kind]).x + _SPACING[size_kind] * t.length()

func set_reason(v: String) -> void:
	reason = v
	if _why == null: return
	_why.text = v
	_why.visible = v != "" and not enabled
	_lay_reason()

func set_enabled(v: bool) -> void:
	enabled = v
	if _label != null: _label.modulate.a = 1.0 if v else _FADED   # the reason caption keeps full strength
	if _why != null: _why.visible = reason != "" and not v
	queue_redraw()

func set_reason_align(v: HorizontalAlignment) -> void:
	reason_align = v
	_lay_reason()

func _lay_reason() -> void:
	if _why == null: return
	_why.size = _why.get_combined_minimum_size()
	var f := frame_rect()
	var x := (size.x - _why.size.x) * 0.5
	if reason_align == HORIZONTAL_ALIGNMENT_LEFT: x = f.position.x
	elif reason_align == HORIZONTAL_ALIGNMENT_RIGHT: x = f.end.x - _why.size.x
	_why.horizontal_alignment = reason_align
	_why.position = Vector2(x, size.y - 4.0)

## The frame's rect in this control (the touch area may be bigger).
func frame_rect() -> Rect2:
	var pad: Vector2 = _PAD[size_kind]
	var w := _text_w(text) + pad.x * 2.0
	var h := float(_FONT[size_kind]) + 8.0 + pad.y * 2.0
	return Rect2((size - Vector2(w, h)) * 0.5, Vector2(w, h))

func _draw() -> void:
	if plain: return
	var r := frame_rect()
	# 1.5 cream line over a 4% cream fill; pressed: full line, 16% fill; disabled: the capsule at 35% (186:167316)
	var k := 1.0 if enabled else _FADED
	var line := UiKit.alpha(INK, (1.0 if _pressed else 0.85) * k)
	draw_style_box(_capsule(UiKit.alpha(INK, (0.16 if _pressed else 0.04) * k), line), r)

static func _capsule(fill: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = edge
	sb.set_border_width_all(int(ceil(_FRAME)))
	sb.set_corner_radius_all(64)
	sb.anti_aliasing = true
	return sb

func _gui_input(event: InputEvent) -> void:
	if plain: return
	var down: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch
	if not down: return
	if event.pressed:
		_press(true)
		accept_event()
	elif _pressed:
		_press(false)
		accept_event()
		if Rect2(Vector2.ZERO, size).has_point(event.position): press()

## A tap's effect, also for tests and shots.
func press() -> void:
	if enabled: activated.emit()
	else: unavailable_pressed.emit(reason)

func _press(on: bool) -> void:
	_pressed = on and enabled
	scale = Vector2.ONE * (0.96 if _pressed else 1.0)
	queue_redraw()
