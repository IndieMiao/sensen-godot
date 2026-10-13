extends Button
## CityRow (MAP-8 Nearby cities, Figma row 85: MAP-8-LIST 2546:131161, MAP-8-FULL 2547:131286; 安其拉 279 a5a99803,
## 不知火舞's spec and colours): one city, 72 high, flat, the whole row a tap target.
##   Thumb 56 × 56, radius 12, 8 above and below: the city's landmark art (its stamp, travel.landmarks) on its climate
##     band's light ground, or the band's glyph (i-climate-*, 20) in the band's colour on that ground. A city never visited
##     reads soft grey: the art at saturation 0 on #ECEBE6, the glyph #A9ACA6 on it.
##   Three lines, 12 right of the thumb: `San Jose` (RowTitleXB15) and ` · California` (C13B, secondary);
##     `68 km · Trip 2 · Nearby` (BodyR14, secondary); the band's glyph 10 in its colour — information, not state, so
##     coloured either way — and `Temperate` (C13B, secondary).
##   StampSlot 28 (StampSlot below) and a `›` at the right, 16 in.
## P0's own (it reads P0Travel's rows), so it lives with the P0 panels; the bands' colours are the frame's (not yet
## design tokens). Preloaded, no class_name (a new global class needs an editor import).

const _H := 72.0
const _THUMB := 56.0
const _THUMB_RADIUS := 12
const _GAP := 12
const _GLYPH_THUMB := 20.0   # the band's glyph in a thumb without landmark art (MAP-8-FULL: 20)
const _GLYPH_LINE := 10.0   # the band's glyph before its name (MAP-8-FULL: 10)
const _ART := 52.0           # the landmark art in its thumb
## The bands' glyph colours and their light grounds (不知火舞 on MAP-8; 安其拉 279 a5a99803).
const BANDS := {
	"temperate": {ink = Color("5E8C4A"), ground = Color("E3EFD9")},
	"subtropical": {ink = Color("C98A2E"), ground = Color("FBE7C6")},
	"tropical": {ink = Color("2E8A6E"), ground = Color("D5F0E6")},
	"cool": {ink = Color("4F7DA8"), ground = Color("DDEBF5")},
}
const UNVISITED_GROUND := Color("ECEBE6")
const UNVISITED_INK := Color("A9ACA6")
const _SHADER := preload("res://scenes/p0/panels/p0_city_row_tint.gdshader")
const P0Travel := preload("res://modules/p0/p0_travel.gd")

var row := {}
var thumb: Panel
var thumb_art: TextureRect
var slot: Control

## row: P0Travel.nearby's {cluster, name, region, km, trip, trip_name, climate, visited, stamped, landmark}.
func _init(row_: Dictionary = {}) -> void:
	row = row_
	name = "City_" + str(row.get("cluster", "")).validate_node_name()
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.y = _H
	var clear := StyleBoxEmpty.new()
	for s in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]: add_theme_stylebox_override(s, clear)
	var line := HBoxContainer.new()
	line.name = "Row"
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override(&"separation", _GAP)
	add_child(line)
	line.add_child(_thumb())
	line.add_child(_text())
	slot = StampSlot.new(stamp_kind(row), str(row.get("landmark", "")))
	slot.name = "Stamp"
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(slot)
	var chevron := UiKit.label("›", UiTokens.STYLE_ROW_TITLE_XB15, UiTokens.COLOR_SECONDARY)
	chevron.name = "Chevron"
	chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(chevron)

## The band key of a row ("temperate" …), the climate name lower-cased; "temperate" for an unknown one.
static func band(r: Dictionary) -> String:
	var b := str(r.get("climate", "")).to_lower()
	return b if BANDS.has(b) else "temperate"

## What the StampSlot shows: "landmark" (visited, its city stamp), "seal" (visited without a landmark stamp: the
## passport's seal), "empty" (not visited: a dashed slot).
static func stamp_kind(r: Dictionary) -> String:
	if not bool(r.get("visited", false)): return "empty"
	return "landmark" if str(r.get("landmark", "")) != "" else "seal"

func _thumb() -> Panel:
	var visited := bool(row.get("visited", false))
	var b: Dictionary = BANDS[band(row)]
	thumb = Panel.new()
	thumb.name = "Thumb"
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.custom_minimum_size = Vector2(_THUMB, _THUMB)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ground := StyleBoxFlat.new()
	ground.bg_color = b.ground if visited else UNVISITED_GROUND
	ground.set_corner_radius_all(_THUMB_RADIUS)
	thumb.add_theme_stylebox_override(&"panel", ground)
	thumb_art = TextureRect.new()
	thumb_art.name = "Art"
	thumb_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var landmark := str(row.get("landmark", ""))
	var art := _material()
	if landmark != "" and ResourceLoader.exists(landmark):
		thumb_art.texture = load(landmark)
		_place(thumb_art, _ART)
		art.set_shader_parameter(&"mode", 0 if visited else 2)   # as it is / saturation 0
	else:
		thumb_art.texture = GameUi.icon("i-climate-" + band(row))
		_place(thumb_art, _GLYPH_THUMB)
		art.set_shader_parameter(&"mode", 1)
		art.set_shader_parameter(&"tint", b.ink if visited else UNVISITED_INK)
	thumb_art.material = art
	thumb.add_child(thumb_art)
	return thumb

static func _place(t: TextureRect, side: float) -> void:
	t.size = Vector2(side, side)
	t.position = Vector2(_THUMB - side, _THUMB - side) * 0.5

static func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _SHADER
	return m

func _text() -> VBoxContainer:
	var text := VBoxContainer.new()
	text.name = "Text"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", 0)
	var first := HBoxContainer.new()
	first.name = "First"
	first.mouse_filter = Control.MOUSE_FILTER_IGNORE
	first.add_theme_constant_override(&"separation", 0)
	var city := UiKit.label(str(row.get("name", "")), UiTokens.STYLE_ROW_TITLE_XB15)
	city.name = "Name"
	first.add_child(city)
	var region := str(row.get("region", ""))
	if region != "":
		var r := UiKit.label(" · " + region, UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
		r.name = "Region"
		r.size_flags_vertical = Control.SIZE_SHRINK_END
		r.clip_text = true
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		first.add_child(r)
	text.add_child(first)
	var trip := UiKit.label(trip_line(row), UiTokens.STYLE_BODY_R14, UiTokens.COLOR_SECONDARY)
	trip.name = "Trip"
	text.add_child(trip)
	var climate := HBoxContainer.new()
	climate.name = "Climate"
	climate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	climate.add_theme_constant_override(&"separation", 6)
	var glyph := TextureRect.new()
	glyph.name = "Glyph"
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.custom_minimum_size = Vector2(_GLYPH_LINE, _GLYPH_LINE)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.texture = GameUi.icon("i-climate-" + band(row))
	var tint := _material()
	tint.set_shader_parameter(&"mode", 1)
	tint.set_shader_parameter(&"tint", (BANDS[band(row)] as Dictionary).ink)
	glyph.material = tint
	climate.add_child(glyph)
	climate.add_child(UiKit.label(str(row.get("climate", "")), UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY))
	text.add_child(climate)
	return text

## `68 km · Trip 2 · Nearby` (the passport's and the city card's own line, §11.8.2).
static func trip_line(r: Dictionary) -> String:
	return "%s km · Trip %d · %s" % [P0Travel.grouped(int(r.get("km", 0))), int(r.get("trip", 0)), str(r.get("trip_name", ""))]

## StampSlot (Figma: Empty / Landmark / Seal; 不知火舞 on MAP-8): a 28 circle. Empty: a dashed ring, 1.5 px #E1DAC8
## (color/border), dashes 3 and gaps 2.5, nothing inside. Landmark: the city's stamp art on a white disc. Seal: the
## passport's seal (i-stamp-seal, 17.5, color/primary) on a white disc.
class StampSlot extends Control:
	const SIDE := 28.0
	const STROKE := 1.5
	const DASH := 3.0
	const GAP := 2.5
	const SEAL := 17.5
	const ART := 22.0
	var kind := "empty"
	var art: Texture2D

	func _init(kind_ := "empty", landmark := "") -> void:
		kind = kind_
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(SIDE, SIDE)
		if kind == "seal": art = GameUi.icon("i-stamp-seal")
		elif kind == "landmark" and ResourceLoader.exists(landmark): art = load(landmark)

	func _draw() -> void:
		var c := Vector2(SIDE, SIDE) * 0.5
		if kind == "empty":
			var r := (SIDE - STROKE) * 0.5
			var around := TAU * r
			var n := maxi(1, roundi(around / (DASH + GAP)))
			var step := TAU / n
			var on := step * DASH / (DASH + GAP)
			for i in n: draw_arc(c, r, i * step, i * step + on, 4, UiTokens.COLOR_BORDER, STROKE, true)
			return
		draw_circle(c + Vector2(0, 1), SIDE * 0.5, UiTokens.COLOR_SHADOW_KEY)   # a soft lift
		draw_circle(c, SIDE * 0.5, Color.WHITE)
		if art == null: return
		var side := SEAL if kind == "seal" else ART
		draw_texture_rect(art, Rect2(c - Vector2(side, side) * 0.5, Vector2(side, side)), false)
