class_name UiMapDestination
extends Control
## MapDestination 1795:103793 (LOCK-24, MAP-1; SGODOT-234 A2): a destination pin on the city map — a 40 disc
## (color/surface, 1 px color/primary edge) with a 24 icon, the name under it (10 Bold, whole text, never cut). The
## homestead's name sits on a surface plate (`plate`); the others are plain text. `mark` hangs a StatusBadge World over
## the disc's top-left corner (q(48): request / deliverable / new); `count` is the ×N corner of a P1 cluster.
## Display only: the city map takes the tap. The geographic point is under the disc (anchor_offset()).

const DISC := 40.0
const ICON := 24.0
const LABEL_GAP := 2.0
const _LABEL_PAD_X := 6.0
const _LABEL_PAD_Y := 2.0
const _PLATE_RADIUS := 10.0
const _MARK_AT := Vector2(-8.0, -8.0)    # StatusBadge World 28 over the disc's top-left corner
## How far a mark's badge pokes over the disc's top: a name over a marked disc clears it (刘邦 on #111).
const MARK_OVERHANG := 8.0
const _COUNT_AT := Vector2(26.0, -4.0)   # ×N, top-right (P1)

var icon: Texture2D: set = set_icon
var text := "": set = set_text
var plate := false: set = set_plate
## A UiStatusBadge state key ("request", "deliverable", "new" …); "" for none.
var mark := "": set = set_mark
var count := "": set = set_count
## The name under the disc; the city map folds it when it would overlap another (C30 / q(72)) — the pin stays.
var name_shown := true: set = set_name_shown
## The disc's own scale about its geographic point (a Show on map pulse); the name keeps its size.
var focus := 1.0: set = set_focus
## The name's sideways shift from under the disc (px): the city map keeps a name near the screen edge on screen.
var label_shift := 0.0: set = set_label_shift
## The name over the disc instead of under it: the city map's second place when under it would touch another (不知火舞
## on 234 A2). The disc keeps its place.
var label_above := false: set = set_label_above
## The gap between the disc's top and a name over it (above_gap_for).
var above_gap := LABEL_GAP: set = set_above_gap

var _pin: Control
var _disc: Panel
var _icon: TextureRect
var _badge: UiStatusBadge
var _count: PanelContainer
var _count_label: Label
var _label_box: PanelContainer
var _label: Label

func _init(icon_: Texture2D = null, text_ := "", plate_ := false) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin = Control.new()
	_pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin.size = Vector2(DISC, DISC)
	add_child(_pin)
	_disc = Panel.new()
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.size = Vector2(DISC, DISC)
	_disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, DISC * 0.5, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_DEFAULT))
	_pin.add_child(_disc)
	_icon = UiKit.icon(null, ICON)
	_icon.position = Vector2.ONE * (DISC - ICON) * 0.5
	_pin.add_child(_icon)
	_count = PanelContainer.new()
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY, 8.0).with_margins(4.0, 1.0, 4.0, 1.0))
	_count.position = _COUNT_AT
	_count_label = UiKit.label("", UiTokens.STYLE_C10_XB, UiTokens.COLOR_SURFACE_RAISED)
	_count.add_child(_count_label)
	_count.visible = false
	_pin.add_child(_count)
	_label_box = PanelContainer.new()
	_label_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label_box)
	_label = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label_box.add_child(_label)
	_label_box.minimum_size_changed.connect(_layout)
	icon = icon_
	text = text_
	plate = plate_
	_layout()

# The city map sets these on every pass: an unchanged value does nothing.
func set_icon(v: Texture2D) -> void:
	if v == icon and _icon.texture == v: return
	icon = v
	_icon.texture = v

func set_text(v: String) -> void:
	if v == text and _label.text == v: return
	text = v
	_label.text = v
	_label_box.visible = v != "" and name_shown
	_layout()

func set_name_shown(v: bool) -> void:
	if v == name_shown: return
	name_shown = v
	if _label_box == null: return
	_label_box.visible = text != "" and v
	_layout()

## The map sets every pin's fields each frame (CityMapView._place_candidate): only a change restyles or lays out.
var _plate_on := -1   # the plate last drawn (-1: none yet)
func set_plate(v: bool) -> void:
	plate = v
	if _plate_on == int(v): return   # a new style box per frame restyled and relaid every pin (int12 map frame cost)
	_plate_on = int(v)
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE if v else Color.TRANSPARENT, _PLATE_RADIUS)
	_label_box.add_theme_stylebox_override(&"panel", box.with_margins(_LABEL_PAD_X, _LABEL_PAD_Y, _LABEL_PAD_X, _LABEL_PAD_Y))
	_layout()

func set_mark(v: String) -> void:
	if v == mark: return
	mark = v
	var i := UiStatusBadge.state_of(v)
	if i < 0:
		if _badge: _badge.visible = false
		return
	if _badge == null:
		_badge = UiStatusBadge.new(i, UiStatusBadge.Size.WORLD)
		_badge.position = _MARK_AT
		_pin.add_child(_badge)
	_badge.state = i
	_badge.visible = true

## The gap over the disc for a name above it: LABEL_GAP, plus the mark's overhang on a marked pin.
static func above_gap_for(marked: bool) -> float:
	return LABEL_GAP + (MARK_OVERHANG if marked else 0.0)

func set_above_gap(v: float) -> void:
	if is_equal_approx(v, above_gap): return
	above_gap = v
	_layout()

func set_label_above(v: bool) -> void:
	if v == label_above: return
	label_above = v
	_layout()

func set_label_shift(v: float) -> void:
	if is_equal_approx(v, label_shift): return
	label_shift = v
	_layout()

func set_focus(v: float) -> void:
	if v == focus and _pin.scale.x == maxf(0.001, v): return
	focus = v
	_pin.pivot_offset = Vector2(DISC * 0.5, DISC)
	_pin.scale = Vector2.ONE * maxf(0.001, v)

func set_count(v: String) -> void:
	if v == count and _count_label.text == v: return
	count = v
	_count_label.text = v
	_count.visible = v != ""

## The name plate's size for `text` before any pin exists (the city map packs pins by it): Compact/10 Bold, 6 / 2
## padding, never cut. Matches label_size() of a built pin.
## Measured once per name: the city map asks for every pin it packs, every frame.
static func label_size_for(text: String) -> Vector2:
	if text == "": return Vector2.ZERO
	if _label_sizes.has(text): return _label_sizes[text]
	var th := UiKit.theme()   # the name's own style, STYLE_C10_B (the city map gives the pin this theme)
	var f := th.get_font(&"font", UiTokens.STYLE_C10_B)
	var fs := th.get_font_size(&"font_size", UiTokens.STYLE_C10_B)
	var size := Vector2(ceilf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x) + _LABEL_PAD_X * 2.0,
		ceilf(f.get_height(fs)) + _LABEL_PAD_Y * 2.0)
	if _label_sizes.size() >= 512: _label_sizes.clear()   # names come from a fixed catalogue; a bound all the same
	_label_sizes[text] = size
	return size
static var _label_sizes := {}

## The name's plate size (0 when there is no name).
func label_size() -> Vector2:
	return _label_box.get_combined_minimum_size() if _label_box.visible else Vector2.ZERO

## Where the geographic point sits in this control: under the middle of the disc.
func anchor_offset() -> Vector2:
	return Vector2(size.x * 0.5, DISC)

## What it covers around its geographic point: the disc over it, the name under it (for the map's packing).
func footprint() -> Rect2:
	var l := label_size()
	var name_y := -DISC - above_gap - l.y if label_above else LABEL_GAP
	return Rect2(-DISC * 0.5, -DISC, DISC, DISC).merge(Rect2(-l.x * 0.5 + label_shift, name_y, l.x, l.y)) if l.x > 0.0 \
		else Rect2(-DISC * 0.5, -DISC, DISC, DISC)

func _layout() -> void:
	if _label_box == null: return
	var l := label_size()
	var w := maxf(DISC, l.x)
	custom_minimum_size = Vector2(w, DISC + (LABEL_GAP + l.y if l.y > 0.0 else 0.0))
	size = custom_minimum_size
	_pin.position = Vector2((w - DISC) * 0.5, 0.0)
	_label_box.position = Vector2((w - l.x) * 0.5 + label_shift, -above_gap - l.y if label_above else DISC + LABEL_GAP)
	_label_box.size = l
