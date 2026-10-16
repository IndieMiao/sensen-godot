extends Control
## Pick your farm spot (HOME-PICK-3 2556:131658, SGODOT-303 / q(160) ②; 不知火舞 28883acf): the city's three farm
## spots on a still map and as three cards, none picked when it opens.
##   BackPill `‹  Change city` (2775:162964) 12 / 16; `Pick your farm spot` (ExtraBold 22) at 72 and the city (Bold 14,
##   secondary) at 102; the map card 328 × 268 at 132, radius 16; the cards from 412, 62 high, 6 apart; `Build here` at
##   680 (grey `Pick a spot` until a spot is picked, LOCK-10) and `Pick for me` (secondary, the first spot) at 736.
##   The map: north up, its frame round the beginner pond and the spots, 24 clear on every side, no pan or zoom. Its
##   ground is the city's baked picture (MapCard) when the package has one, else the map's land colour; the pond is a
##   MapDestination Short, the spots SpotNumber pins (2775:162961). A pin and its card are one: tapping either picks it
##   and both show it (the pin 36, solid; the card on primaryTint with a 2 px primary edge).
##   While the spots are read (不知火舞 on #451, q(207) ③): the map card's plain ground with no pond or pins, three blank
##   cards where the cards go (their size, a 1 px border, no words), both keys grey and quiet, the back pill as ever;
##   the real cards take their places, nothing moves.
##   PICK-ERR-SPOTS (2773:182296, q(207)): no spots — the map and the cards give way to `Couldn't load farm spots` and a
##   Retry; both keys grey and quiet (no toast); the back pill as ever.
## Emits back_pressed, chosen(cluster, spot), retry_pressed, unavailable(text).

signal back_pressed
signal chosen(cluster: String, spot: int)
signal retry_pressed
signal unavailable(text: String)

const P0HomePick := preload("res://modules/p0/p0_home_pick.gd")
const P0MapScript := preload("res://scenes/p0/p0_map.gd")

const _TITLE_Y := 72.0
const _CITY_Y := 102.0
const _MAP_Y := 132.0
const _MAP := Vector2(328, 268)
const _MAP_RADIUS := 16
const _CARDS_Y := 412.0
const _CARD_H := 62.0
const _CARD_GAP := 6.0
const _BUILD_Y := 680.0
const _KEY_H := 48.0
const _TITLE_SIZE := 22

var cluster := ""
var city_name := ""
var spots: Array = []
var picked := -1: set = set_picked
var failed := false
var title: Label
var map_card: MapCard
var cards: Array[SpotCard] = []
var build: UiCommandButton
var for_me: UiCommandButton
var empty: Control
var _cards_box: VBoxContainer

func _init(cluster_ := "", city_name_ := "", heading := "Pick your farm spot", safe_top := 0.0, safe_bottom := 0.0) -> void:
	cluster = cluster_
	city_name = city_name_
	name = "HomeSpotPage"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UiTokens.COLOR_SURFACE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var back := BackPill.new("Change city")
	back.position = Vector2(12, 16 + safe_top)
	back.pressed.connect(func(): back_pressed.emit())
	add_child(back)
	title = _at(UiKit.label(heading, UiTokens.STYLE_TITLE_XB20), _TITLE_Y + safe_top)
	title.name = "Title"
	title.add_theme_font_size_override(&"font_size", _TITLE_SIZE)
	_at(UiKit.label(city_name, UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY), _CITY_Y + safe_top).name = "City"
	map_card = MapCard.new(cluster)
	map_card.position = Vector2(UiTokens.SPACE_PAGE, _MAP_Y + safe_top)
	map_card.spot_pressed.connect(func(i: int): picked = i)
	add_child(map_card)
	_cards_box = VBoxContainer.new()
	_cards_box.name = "Cards"
	_cards_box.add_theme_constant_override(&"separation", int(_CARD_GAP))
	_at(_cards_box, _CARDS_Y + safe_top)
	_blank_cards()
	build = _key("Build here", UiCommandButton.Kind.PRIMARY, _BUILD_Y, safe_bottom)
	build.name = "Build"
	build.activated.connect(func(): if picked >= 0: chosen.emit(cluster, int(spots[picked].get("spot", picked))))
	for_me = _key("Pick for me", UiCommandButton.Kind.SECONDARY, _BUILD_Y + _KEY_H + 8.0, safe_bottom)
	for_me.name = "PickForMe"
	for_me.activated.connect(func(): if not spots.is_empty(): chosen.emit(cluster, int(spots[0].get("spot", 0))))
	for b in [build, for_me]:
		(b as UiCommandButton).unavailable_pressed.connect(func(text: String): if not failed and not spots.is_empty(): unavailable.emit(text))
	empty = _error()
	_refresh()

func _at(c: Control, y: float) -> Control:
	c.position = Vector2(UiTokens.SPACE_PAGE, y)
	if c is Label: (c as Label).custom_minimum_size.x = _MAP.x
	else: c.size.x = _MAP.x
	add_child(c)
	return c

## The two keys sit on the bottom edge (800 high in the frame: Build here 680, Pick for me 736).
func _key(text: String, kind: UiCommandButton.Kind, y: float, safe_bottom: float) -> UiCommandButton:
	var b := UiCommandButton.new(text, kind)
	b.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	b.offset_left = UiTokens.SPACE_PAGE
	b.offset_right = -UiTokens.SPACE_PAGE
	b.offset_top = y - 800.0 - safe_bottom
	b.offset_bottom = b.offset_top + _KEY_H
	add_child(b)
	return b

func _error() -> Control:
	var box := VBoxContainer.new()
	box.name = "Error"
	box.add_theme_constant_override(&"separation", 4)
	box.position = Vector2(32, _MAP_Y + 120.0)
	box.custom_minimum_size.x = 296
	var e := UiEmptyState.new("Couldn't load farm spots", preload("res://assets/ui/kit_icons/wifi_off.svg"))
	box.add_child(e)
	var retry := UiCommandButton.new("Retry", UiCommandButton.Kind.SECONDARY, true)
	retry.name = "Retry"
	retry.fit_text = true
	retry.min_width = 68   # Compact/Command: hugs its label, at least 68
	retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	retry.activated.connect(func():   # back to reading: one read at a time (周瑜 on #451)
		show_loading()
		retry_pressed.emit())
	box.add_child(retry)
	box.visible = false
	add_child(box)
	return box

## A blank card where a spot's card will be: its size and border, nothing in it.
static func _placeholder(n: int) -> Panel:
	var p := Panel.new()
	p.name = "Placeholder%d" % n
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(_MAP.x, _CARD_H)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTokens.COLOR_SURFACE_RAISED, 0.0)
	sb.border_color = UiTokens.COLOR_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(16)
	p.add_theme_stylebox_override(&"panel", sb)
	return p

## The spots came (the route's spots, their order the cards' 1 2 3).
func show_spots(spots_: Array) -> void:
	spots = spots_
	failed = false
	picked = -1
	for c in _cards_box.get_children():   # the placeholders, or the cards of a read before
		_cards_box.remove_child(c)
		c.queue_free()
	cards.clear()
	for i in spots.size():
		var card := SpotCard.new(i + 1, P0HomePick.spot_title(spots[i]), P0HomePick.spot_line(spots[i]))
		card.name = "Spot%d" % (i + 1)
		card.pressed.connect(func(): picked = i)
		_cards_box.add_child(card)
		cards.append(card)
	map_card.show_spots(spots)
	_refresh()

## Reading the spots (again, after Retry): the plain map, the blank cards, both keys grey and quiet.
func show_loading() -> void:
	failed = false
	spots = []
	_blank_cards()
	map_card.clear()
	picked = -1

func _blank_cards() -> void:
	for c in _cards_box.get_children():
		_cards_box.remove_child(c)
		c.queue_free()
	cards.clear()
	for i in 3: _cards_box.add_child(_placeholder(i + 1))

## PICK-ERR-SPOTS: they did not come.
func show_failed() -> void:
	failed = true
	spots = []
	picked = -1
	_refresh()

func set_picked(v: int) -> void:
	picked = v if v >= 0 and v < spots.size() else -1
	for i in cards.size(): cards[i].picked = i == picked
	if map_card != null: map_card.picked = picked
	_refresh()

func _refresh() -> void:
	if build == null: return
	map_card.visible = not failed
	_cards_box.visible = not failed
	empty.visible = failed
	build.reason = "Pick a spot" if picked < 0 else ""
	for_me.reason = "Pick for me" if spots.is_empty() else ""

## BackPill (2775:162964): `‹  Change city` on a white pill, ExtraBold 14, 12 / 14 in, 12 over and under; it hugs its
## label (116 wide for Change city, 94 for Settings).
class BackPill extends Button:
	func _init(label: String) -> void:
		name = "Back"
		focus_mode = Control.FOCUS_NONE
		text = "‹  " + label
		theme_type_variation = UiTokens.STYLE_BODY_XB14
		add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT)
		for s in [&"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
			add_theme_color_override(s, UiTokens.COLOR_TEXT)
		add_theme_font_size_override(&"font_size", 14)
		for s in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = UiTokens.COLOR_SURFACE_RAISED.darkened(0.04) if s == &"pressed" else UiTokens.COLOR_SURFACE_RAISED
			sb.set_corner_radius_all(22)
			sb.content_margin_left = 12
			sb.content_margin_right = 14
			sb.content_margin_top = 12
			sb.content_margin_bottom = 12
			add_theme_stylebox_override(s, sb)

## SpotNumber (2775:162961): Place=Map 30, surfaceRaised with a 2 px primary edge and a soft shadow, the number
## ExtraBold 14 primary; selected 36, solid primary, a 3 px white ring, the number 16 white. Place=Card 30, no shadow;
## selected solid primary, the number white.
class SpotNumber extends Control:
	const SIDE := 30.0
	const SIDE_PICKED := 36.0
	var number := 1
	var on_map := true
	var picked := false: set = set_picked
	var _label: Label

	func _init(number_ := 1, on_map_ := true) -> void:
		number = number_
		on_map = on_map_
		name = "Number"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label = UiKit.label(str(number), UiTokens.STYLE_C14_XB, UiTokens.COLOR_PRIMARY)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_label)
		set_picked(false)

	func side() -> float: return SIDE_PICKED if picked and on_map else SIDE

	func set_picked(v: bool) -> void:
		picked = v
		var s := side()
		custom_minimum_size = Vector2(s, s)
		size = custom_minimum_size
		_label.add_theme_color_override(&"font_color", Color.WHITE if picked else UiTokens.COLOR_PRIMARY)
		_label.add_theme_font_size_override(&"font_size", 16 if picked and on_map else 14)
		queue_redraw()

	func _draw() -> void:
		var s := side()
		var c := Vector2(s, s) * 0.5
		if on_map: draw_circle(c + Vector2(0, 2), s * 0.5 + 1.0, Color(0.18, 0.231, 0.2, 0.18))   # 0 2 6 rgba(46,59,51,.25)
		if picked and on_map:
			draw_circle(c, s * 0.5, Color.WHITE)
			draw_circle(c, s * 0.5 - 3.0, UiTokens.COLOR_PRIMARY)
		elif picked:
			draw_circle(c, s * 0.5, UiTokens.COLOR_PRIMARY)
		else:
			draw_circle(c, s * 0.5, UiTokens.COLOR_SURFACE_RAISED)
			draw_arc(c, s * 0.5 - 1.0, 0.0, TAU, 48, UiTokens.COLOR_PRIMARY, 2.0, true)

## A spot's card (HOME-PICK-3 `Farm spot card`): white, a 1 px border, radius 16, 12 / 10 in; its number, then the
## district (ExtraBold 15) over `1.2 km to Fern Pond · northeast` (Regular 13, secondary), 2 apart. Picked: primaryTint
## and a 2 px primary edge (HOME-CHANGE-CONFIRM's `Farm spot card · 1 · selected`).
class SpotCard extends Button:
	var number: SpotNumber
	var picked := false: set = set_picked

	func _init(n: int, title_: String, line: String) -> void:
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(328, 62)
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		row.offset_right = -12
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override(&"separation", 12)
		add_child(row)
		number = SpotNumber.new(n, false)
		number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(number)
		var text := VBoxContainer.new()
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		text.add_theme_constant_override(&"separation", 2)
		row.add_child(text)
		var t := UiKit.label(title_, UiTokens.STYLE_ROW_TITLE_XB15)
		t.name = "Title"
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(t)
		var l := UiKit.label(line, UiTokens.STYLE_BODY_R14, UiTokens.COLOR_SECONDARY)
		l.name = "Line"
		l.add_theme_font_size_override(&"font_size", 13)
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.add_child(l)
		set_picked(false)

	func set_picked(v: bool) -> void:
		picked = v
		number.picked = v
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTokens.COLOR_PRIMARY_TINT if v else UiTokens.COLOR_SURFACE_RAISED
		sb.border_color = UiTokens.COLOR_PRIMARY if v else UiTokens.COLOR_BORDER
		sb.set_border_width_all(2 if v else 1)
		sb.set_corner_radius_all(16)
		for s in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]: add_theme_stylebox_override(s, sb)

## The still map (328 × 268, radius 16): Web Mercator, north up. A baked picture (P0HomeSpotMaps) sets its own frame;
## without one the frame is fitted round the pond and the spots and the ground is the map's land colour (不知火舞
## 28883acf: the fallback, never a broken picture).
class MapCard extends Control:
	signal spot_pressed(i: int)
	const SIZE := Vector2(328, 268)
	const CLEAR := 24.0          # every pin and the pond's name clear of the edge by at least this
	const LAND := Color("F4F1E7") # the game map's land (GodotMapPlugin applyCityStyle)
	const P0HomeSpotMaps := preload("res://modules/p0/p0_home_spot_maps.gd")
	var cluster := ""
	var picked := -1: set = set_picked
	var frame := {}              # {center: Vector2 (mercator, 0..1), scale: px per mercator unit}
	var ground: TextureRect
	var pond: UiMapDestination
	var pins: Array[SpotNumber] = []
	var _spots: Array = []

	func _init(cluster_ := "") -> void:
		cluster = cluster_
		name = "Map"
		size = SIZE
		custom_minimum_size = SIZE
		clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		mouse_filter = Control.MOUSE_FILTER_PASS
		ground = TextureRect.new()
		ground.name = "Ground"
		ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ground.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ground.stretch_mode = TextureRect.STRETCH_SCALE
		ground.size = SIZE
		add_child(ground)

	func _draw() -> void:
		draw_style_box(_round(LAND), Rect2(Vector2.ZERO, SIZE))

	static func _round(c: Color) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(16)
		return sb

	## No spots on it: the plain ground alone (reading them).
	func clear() -> void:
		_spots = []
		for p in pins: p.queue_free()
		pins.clear()
		if pond != null: pond.queue_free()
		pond = null
		frame = {}
		ground.texture = null

	func show_spots(spots: Array) -> void:
		clear()
		_spots = spots
		var baked := P0HomeSpotMaps.map(cluster)
		var pts: Array = [_pond_point(spots)]
		for s in spots: pts.append(Vector2(float(s.lat), float(s.lng)))
		var use_baked := not baked.is_empty() and P0HomeSpotMaps.fits(baked, pts, SIZE, CLEAR)
		frame = P0HomeSpotMaps.frame_of(baked) if use_baked else P0HomeSpotMaps.fit(pts, SIZE, CLEAR)
		ground.texture = P0HomeSpotMaps.texture(baked) if use_baked else null
		var pond_info: Dictionary = spots[0].get("pond", {}) if not spots.is_empty() and spots[0].get("pond") is Dictionary else {}
		pond = UiMapDestination.new(P0Logic.icon("pond"), P0MapScript.short_name(str(pond_info.get("name", ""))))
		pond.name = "Pond"
		add_child(pond)
		pond.position = (point(pts[0]) - pond.anchor_offset()).round()
		for i in spots.size():
			var pin := SpotNumber.new(i + 1, true)
			pin.name = "Pin%d" % (i + 1)
			pin.mouse_filter = Control.MOUSE_FILTER_STOP
			pin.gui_input.connect(func(e: InputEvent): if P0Ui.is_tap(e): spot_pressed.emit(i))
			add_child(pin)
			pins.append(pin)
		set_picked(picked)

	static func _pond_point(spots: Array) -> Vector2:
		var p: Dictionary = spots[0].get("pond", {}) if not spots.is_empty() and spots[0].get("pond") is Dictionary else {}
		return Vector2(float(p.get("lat", 0.0)), float(p.get("lng", 0.0)))

	## A (lat, lng) on the card.
	func point(at: Vector2) -> Vector2:
		return P0HomeSpotMaps.to_card(frame, at, SIZE)

	func set_picked(v: int) -> void:
		picked = v
		for i in pins.size():
			pins[i].picked = i == picked
			var at := point(Vector2(float(_spots[i].lat), float(_spots[i].lng)))
			pins[i].position = (at - Vector2.ONE * pins[i].side() * 0.5).round()
			if i == picked: move_child(pins[i], -1)   # the picked pin over the others
