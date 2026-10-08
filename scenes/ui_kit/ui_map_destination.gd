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
const _COUNT_AT := Vector2(26.0, -4.0)   # ×N, top-right (P1)

var icon: Texture2D: set = set_icon
var text := "": set = set_text
var plate := false: set = set_plate
## A UiStatusBadge state key ("request", "deliverable", "new" …); "" for none.
var mark := "": set = set_mark
var count := "": set = set_count
## The name under the disc; the city map folds it when it would overlap another (C30 / q(72)) — the pin stays.
var name_shown := true: set = set_name_shown

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

func set_plate(v: bool) -> void:
	plate = v
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE if v else Color.TRANSPARENT, _PLATE_RADIUS)
	_label_box.add_theme_stylebox_override(&"panel", box.with_margins(_LABEL_PAD_X, _LABEL_PAD_Y, _LABEL_PAD_X, _LABEL_PAD_Y))
	_layout()

func set_mark(v: String) -> void:
	if v == mark: return
	mark = v
	var i := UiStatusBadge._KEYS.find(v)
	if i < 0:
		if _badge: _badge.visible = false
		return
	if _badge == null:
		_badge = UiStatusBadge.new(i, UiStatusBadge.Size.WORLD)
		_badge.position = _MARK_AT
		_pin.add_child(_badge)
	_badge.state = i
	_badge.visible = true

func set_count(v: String) -> void:
	count = v
	_count_label.text = v
	_count.visible = v != ""

## The name plate's size for `text` before any pin exists (the city map packs pins by it): Compact/10 Bold, 6 / 2
## padding, never cut. Matches label_size() of a built pin.
static func label_size_for(text: String) -> Vector2:
	if text == "": return Vector2.ZERO
	var f := UiKit.font(&"bold")
	return Vector2(ceilf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x) + _LABEL_PAD_X * 2.0,
		ceilf(f.get_height(10) * 1.25 / 1.25) + _LABEL_PAD_Y * 2.0)

## The name's plate size (0 when there is no name).
func label_size() -> Vector2:
	return _label_box.get_combined_minimum_size() if _label_box.visible else Vector2.ZERO

## Where the geographic point sits in this control: under the middle of the disc.
func anchor_offset() -> Vector2:
	return Vector2(size.x * 0.5, DISC)

## What it covers around its geographic point: the disc over it, the name under it (for the map's packing).
func footprint() -> Rect2:
	var l := label_size()
	return Rect2(-DISC * 0.5, -DISC, DISC, DISC).merge(Rect2(-l.x * 0.5, LABEL_GAP, l.x, l.y)) if l.x > 0.0 \
		else Rect2(-DISC * 0.5, -DISC, DISC, DISC)

func _layout() -> void:
	if _label_box == null: return
	var l := label_size()
	var w := maxf(DISC, l.x)
	custom_minimum_size = Vector2(w, DISC + (LABEL_GAP + l.y if l.y > 0.0 else 0.0))
	size = custom_minimum_size
	_pin.position = Vector2((w - DISC) * 0.5, 0.0)
	_label_box.position = Vector2((w - l.x) * 0.5, DISC + LABEL_GAP)
	_label_box.size = l
