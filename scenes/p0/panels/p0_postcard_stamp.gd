extends Control
## PostcardStamp (Figma 2615:134287; q(171), 不知火舞 on 284): a resident's postcard as a postage stamp — perforated
## paper, the picture inset in it, and on an earned one a round postmark over its lower right corner.
##   earned    the resident's render card at its stamp crop (P0Ui.resident_crop, portrait_crops.json; 上官婉儿 #405) — or,
##             until their card exists, their initial in ExtraBold primary on primaryTint (不知火舞: never the grey
##             silhouette, that reads unearned)
##   unearned  a grey silhouette on grey paper, no postmark
## Sizes: PASSPORT 34 × 42 (PASS-POSTCARDS' cells), CARD 40 × 50 (the arrival card's item, KINDRED-PIP). Display only.
## Preloaded, no class_name (a new global class needs an editor import).

const PASSPORT := Vector2(34, 42)
const CARD := Vector2(40, 50)
const _TOOTH := 1.6          # a perforation's radius
const _PITCH := 4.4          # perforation to perforation along an edge
const _INSET := 4.0          # paper's margin round the picture
const _PAPER := Color("FFFFFF")
const _EDGE := UiTokens.COLOR_BORDER     # the perforated rim
const _GREY_PAPER := Color("F1F0EC")
const _GREY_PICTURE := UiTokens.COLOR_DISABLED
const _GREY_FIGURE := Color("F4F3EF")
const _MARK := Color(0.42, 0.45, 0.42, 0.85)
const _INITIAL_SIZE := 16

var resident := ""
var earned := false
var face: Texture2D
var _initial: Label

func _init(resident_ := "", earned_ := false, size_ := PASSPORT) -> void:
	resident = resident_
	earned = earned_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = size_
	size = size_
	if earned:
		var key := str(P0Logic.content().get("residents", {}).get(resident, {}).get("portrait", ""))
		face = P0Ui.resident_crop(key, "stamp")
		if face == null:   # no card yet: the initial (不知火舞 on 284)
			_initial = UiKit.label(load("res://modules/p0/p0_kindred.gd").initial(resident), UiTokens.STYLE_ROW_TITLE_XB15, UiTokens.COLOR_PRIMARY_INK)
			_initial.name = "Initial"
			_initial.add_theme_font_size_override(&"font_size", _INITIAL_SIZE)
			_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_initial)
	resized.connect(_place_initial)
	_place_initial()

## The initial fills the picture's rect, centred in it.
func _place_initial() -> void:
	if _initial == null: return
	var r := _picture()
	_initial.position = r.position
	_initial.size = r.size

## The picture's rect inside the paper.
func _picture() -> Rect2:
	var s := size if size != Vector2.ZERO else custom_minimum_size
	return Rect2(Vector2(_INSET, _INSET), s - Vector2(_INSET, _INSET) * 2.0)

func _draw() -> void:
	var s := size if size != Vector2.ZERO else custom_minimum_size
	var paper := _PAPER if earned else _GREY_PAPER
	# Perforations: the rim's teeth round a paper rect a tooth in, then the paper over their inner halves.
	var body := Rect2(Vector2(_TOOTH, _TOOTH), s - Vector2(_TOOTH, _TOOTH) * 2.0)
	for p in _teeth(body): draw_circle(p, _TOOTH, _EDGE)
	draw_rect(body, _EDGE)
	draw_rect(body.grow(-0.75), paper)
	var pic := _picture()
	if not earned:
		draw_rect(pic, _GREY_PICTURE)
		_figure(pic)
		return
	if face: draw_texture_rect_region(face, pic, cover(face.get_size(), pic.size))
	else: draw_rect(pic, UiTokens.COLOR_PRIMARY_TINT)
	_postmark(s)

## The part of an image that fills a frame of `frame`'s shape without stretching: as wide (or tall) as it can, centred
## across and from the top down (a portrait without its face crop shows its head, not its middle).
static func cover(image: Vector2, frame: Vector2) -> Rect2:
	if image.x <= 0.0 or image.y <= 0.0 or frame.x <= 0.0 or frame.y <= 0.0: return Rect2(Vector2.ZERO, image)
	var want := frame.x / frame.y
	if image.x / image.y > want:
		var w := image.y * want
		return Rect2(Vector2((image.x - w) * 0.5, 0), Vector2(w, image.y))
	return Rect2(Vector2.ZERO, Vector2(image.x, image.x / want))

## The teeth's centres along the paper's four edges, evenly spaced, the corners included.
static func _teeth(r: Rect2) -> Array:
	var out: Array = []
	var nx := maxi(1, roundi(r.size.x / _PITCH))
	var ny := maxi(1, roundi(r.size.y / _PITCH))
	for i in nx + 1:
		var x := r.position.x + r.size.x * float(i) / float(nx)
		out.append(Vector2(x, r.position.y))
		out.append(Vector2(x, r.end.y))
	for j in range(1, ny):
		var y := r.position.y + r.size.y * float(j) / float(ny)
		out.append(Vector2(r.position.x, y))
		out.append(Vector2(r.end.x, y))
	return out

## The unearned silhouette: a head and shoulders, pale on the grey picture.
func _figure(pic: Rect2) -> void:
	var c := pic.get_center()
	var w := pic.size.x
	draw_circle(Vector2(c.x, pic.position.y + pic.size.y * 0.38), w * 0.2, _GREY_FIGURE)
	var shoulders := PackedVector2Array()
	var cy := pic.end.y
	for i in 17:
		var a := PI + PI * float(i) / 16.0
		shoulders.append(Vector2(c.x + cos(a) * w * 0.38, cy + sin(a) * pic.size.y * 0.3))
	draw_colored_polygon(shoulders, _GREY_FIGURE)

## An earned stamp's postmark: two rings over its lower right corner and a short wave beside them.
func _postmark(s: Vector2) -> void:
	var r := s.x * 0.2
	var at := Vector2(s.x - r * 0.55, s.y - r * 0.9)
	draw_arc(at, r, 0.0, TAU, 28, _MARK, 1.2, true)
	draw_arc(at, r * 0.6, 0.0, TAU, 20, _MARK, 1.0, true)
	var wave := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		wave.append(Vector2(at.x - r * 2.4 + t * r * 1.5, at.y + r * 0.55 + sin(t * TAU) * 1.4))
	draw_polyline(wave, _MARK, 1.0, true)
