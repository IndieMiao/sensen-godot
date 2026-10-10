class_name UiMapDestination
extends Control
## MapDestination 1795:103793 (LOCK-24, MAP-1; SGODOT-234 A2): a destination pin on the city map — a 40 disc
## (color/surface, 1 px color/primary edge) with a 24 icon and a name under it. The homestead's name sits on a surface
## plate (`plate`: 10 Bold, whole text). The others take Label=Short (q(137), 2391:127664): the place's short name,
## 11 Bold dark with a cream outline, no plate, one line at most 96 px. `mark` hangs a StatusBadge World over the
## disc's top-left corner (q(48): request / deliverable / new); `online` is the top-right count (a person and the
## number, none at 0, q(137)); `count` the ×N corner of a P1 cluster.
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
## Label=Short (q(137)): 11 Bold, a 2 px cream outline (Godot's outline_size is the stroke's whole width), at most 96.
const SHORT_MAX_W := 96.0
const _SHORT_HALO := 4
const _PERSON := "res://assets/ui/kit_icons/count_person.svg"
const _PERSON_SIDE := 9.0

var icon: Texture2D: set = set_icon
var text := "": set = set_text
var plate := false: set = set_plate
## A UiStatusBadge state key ("request", "deliverable", "new" …); "" for none.
var mark := "": set = set_mark
var count := "": set = set_count
## Players in this place now (q(137)): the top-right count, a person and the number; 0 shows none.
var online := 0: set = set_online
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
## A place of a city the fog still covers (MAP-2 2107:33077, 不知火舞 on #281; P1, the P0 pin is untouched): a 32 px
## surface disc with a 1 px border-colour edge, the 18 px type glyph in color/secondary, no name, the whole pin at 55 %.
## Its point stays at the disc's centre and its tap area is the pin's as ever.
var silhouette := false: set = set_silhouette
const SILHOUETTE_DISC := 32.0
const SILHOUETTE_ICON := 18.0
const SILHOUETTE_ALPHA := 0.55

var _pin: Control
var _disc: Panel
var _icon: TextureRect
var _badge: UiStatusBadge
var _count: PanelContainer
var _count_label: Label
var _count_person: TextureRect
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
	var count_row := HBoxContainer.new()
	count_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_row.add_theme_constant_override(&"separation", 2)
	_count.add_child(count_row)
	_count_person = UiKit.icon(null, _PERSON_SIDE)
	_count_person.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_count_person.visible = false
	count_row.add_child(_count_person)
	_count_label = UiKit.label("", UiTokens.STYLE_C10_XB, UiTokens.COLOR_SURFACE_RAISED)
	count_row.add_child(_count_label)
	_count.visible = false
	_pin.add_child(_count)
	_label_box = PanelContainer.new()
	_label_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label_box)
	_label = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_TEXT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override(&"font_outline_color", UiTokens.COLOR_SURFACE)
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
	_fit_short()
	_layout()

func set_name_shown(v: bool) -> void:
	if v == name_shown: return
	name_shown = v
	if _label_box == null: return
	_label_box.visible = text != "" and v and not silhouette
	_layout()

func set_silhouette(v: bool) -> void:
	if v == silhouette: return
	silhouette = v
	if _disc == null: return
	var d := SILHOUETTE_DISC if v else DISC
	_disc.size = Vector2(d, d)
	_disc.position = Vector2.ONE * (DISC - d) * 0.5   # centred where the full disc is: the point does not move
	_disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, d * 0.5,
		UiTokens.COLOR_BORDER if v else UiTokens.COLOR_PRIMARY, UiTokens.STROKE_DEFAULT))
	var side := SILHOUETTE_ICON if v else ICON
	_icon.custom_minimum_size = Vector2(side, side)   # first: a size under the old minimum would be clamped back up
	_icon.size = Vector2(side, side)
	_icon.position = Vector2.ONE * (DISC - side) * 0.5
	_icon.material = _ink() if v else null   # the glyph as a one-colour silhouette
	modulate.a = SILHOUETTE_ALPHA if v else 1.0   # the whole pin, its glyph and mark too (不知火舞 on #287)
	if _badge: _badge.position = _mark_at()
	_label_box.visible = text != "" and name_shown and not v
	_layout()

## A mark's badge over the disc's top-left corner: a silhouette's smaller disc moves the corner in (蒙恬 on #287).
func _mark_at() -> Vector2:
	return _MARK_AT + Vector2.ONE * ((DISC - SILHOUETTE_DISC) * 0.5 if silhouette else 0.0)

## A canvas material drawing a texture's shape in color/secondary: the silhouette's glyph. The incoming COLOR's alpha
## (the texture's, times the node's modulate) is kept, so the pin's 55 % fades the glyph with the disc (不知火舞 on
## #287: written over, the glyph stayed at full opacity).
static var _ink_mat: ShaderMaterial
static func _ink() -> ShaderMaterial:
	if _ink_mat == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nuniform vec4 ink : source_color;\nvoid fragment() { COLOR = vec4(ink.rgb, COLOR.a * ink.a); }"
		_ink_mat = ShaderMaterial.new()
		_ink_mat.shader = sh
		_ink_mat.set_shader_parameter("ink", UiTokens.COLOR_SECONDARY)
	return _ink_mat

## The map sets every pin's fields each frame (CityMapView._place_candidate): only a change restyles or lays out.
var _plate_on := -1   # the plate last drawn (-1: none yet)
func set_plate(v: bool) -> void:
	plate = v
	if _plate_on == int(v): return   # a new style box per frame restyled and relaid every pin (int12 map frame cost)
	_plate_on = int(v)
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE if v else Color.TRANSPARENT, _PLATE_RADIUS)
	# The homestead's plate keeps its 6 / 2 padding (10 Bold); a short name is the text alone, 2 over and under.
	var pad_x := _LABEL_PAD_X if v else 0.0
	_label_box.add_theme_stylebox_override(&"panel", box.with_margins(pad_x, _LABEL_PAD_Y, pad_x, _LABEL_PAD_Y))
	_label.theme_type_variation = UiTokens.STYLE_C10_B if v else UiTokens.STYLE_C11_B
	_label.add_theme_constant_override(&"outline_size", 0 if v else _SHORT_HALO)
	_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if v else TextServer.OVERRUN_TRIM_ELLIPSIS
	_fit_short()
	_layout()

## A short name keeps to one line of at most 96 px, cut with an ellipsis past it (q(137)); a plate's name is whole.
func _fit_short() -> void:
	if _plate_on < 0: return
	_label.custom_minimum_size.x = 0.0 if plate else label_size_for(text, false).x

func set_mark(v: String) -> void:
	if v == mark: return
	mark = v
	var i := UiStatusBadge.state_of(v)
	if i < 0:
		if _badge: _badge.visible = false
		return
	if _badge == null:
		_badge = UiStatusBadge.new(i, UiStatusBadge.Size.WORLD)
		_badge.position = _mark_at()
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
	_count_person.visible = false
	_count.visible = v != ""

func set_online(v: int) -> void:
	if v == online and (_count.visible == (v > 0)): return
	online = v
	if v <= 0:
		if count == "": _count.visible = false
		return
	if _count_person.texture == null: _count_person.texture = load(_PERSON)
	_count_person.visible = true
	_count_label.text = str(v)
	_count.visible = true

## The name's size for `text` before any pin exists (the city map packs pins by it). A plate's: Compact/10 Bold, 6 / 2
## padding, never cut. A short name's (q(137)): 11 Bold, 2 over and under, at most 96 wide. Matches label_size() of a
## built pin. Measured once per name: the city map asks for every pin it packs, every frame.
static func label_size_for(text: String, plated := true) -> Vector2:
	if text == "": return Vector2.ZERO
	var key := text + ("|p" if plated else "|s")
	if _label_sizes.has(key): return _label_sizes[key]
	var style := UiTokens.STYLE_C10_B if plated else UiTokens.STYLE_C11_B
	var th := UiKit.theme()   # the name's own style (the city map gives the pin this theme)
	var f := th.get_font(&"font", style)
	var fs := th.get_font_size(&"font_size", style)
	var w := ceilf(f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var size := Vector2(w + _LABEL_PAD_X * 2.0 if plated else minf(w, SHORT_MAX_W), ceilf(f.get_height(fs)) + _LABEL_PAD_Y * 2.0)
	if _label_sizes.size() >= 512: _label_sizes.clear()   # names come from a fixed catalogue; a bound all the same
	_label_sizes[key] = size
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
	var l := label_size() if not silhouette else Vector2.ZERO
	var w := maxf(DISC, l.x)
	custom_minimum_size = Vector2(w, DISC + (LABEL_GAP + l.y if l.y > 0.0 else 0.0))
	size = custom_minimum_size
	_pin.position = Vector2((w - DISC) * 0.5, 0.0)
	_label_box.position = Vector2((w - l.x) * 0.5 + label_shift, -above_gap - l.y if label_above else DISC + LABEL_GAP)
	_label_box.size = l
