extends Control
## HOME-WELCOME (SGODOT-340 §4, 338 S0 t_city; SGODOT-342): a new player's first page when the address is near an open
## city (q(205) Near you). The card at the bottom — 16 from the sides, the safe area + 16 from the bottom, radius 20,
## 20 in: `Welcome to Gensen!` (ExtraBold 22), the city's row (as HOME-PICK's), one line (Body 14), then `Start here`
## (primary) and `Choose another city` (secondary), 48 each, 8 apart. No ×, no later. Modal: nothing under it moves.
## Behind it the real map (PR-2b, the flow's `map`: the P0 map in its pick mode): the camera flies from the globe to the
## city in about a second, then the card slides in from the bottom (slide_in); the land colour (§4: #F6F4EA) lies over
## the map till it has drawn, and alone where there is none; the map's credit line 6 over the card's top (q(133) ①,
## 不知火舞 342). Frames: row 101 51:160750 / 51:160776 / 51:160801 (Figma 5SVgfevrLzZXqD83uyPgmV); copy per q(216)
## 7aa8ffad.
## placeholder(): while the first read is out (不知火舞 342 8c4168ab, as HOME-PIN-LOADING): the card's place and size
## (a one-line city name) as an edge only — no fill, no words, no spinner; the real card takes its place.
## Emits start_pressed, other_pressed.

signal start_pressed
signal other_pressed

const P0CityRow := preload("res://scenes/p0/panels/p0_city_row.gd")
const P0Travel := preload("res://modules/p0/p0_travel.gd")
const LAND := Color("F6F4EA")   # HOME-WELCOME's map-loading ground (340 §4, row 101 51:160776)
const _SIDE := 16
const _BOTTOM := 16
const _PAD := 20
const _GAP := 12
const _KEY_GAP := 8
const _TITLE_SIZE := 22
## The line under the city (q(216); Near you reaches 1,500 km, so it does not say how near).
const LINE := "Start your farm here? It's the closest home city to you."

var row: Dictionary
var map: Object               # the real map under it (pick_has_ground / pick_px_per_pt), null on the land alone
var land: ColorRect
var credits: Label
var card: PanelContainer
var start: UiCommandButton
var other: UiCommandButton

## row_: the Near you city row ({id, name, region, climate, …}, P0HomePick.cities' `near`).
var _waiting := false          # the card held back for the flight: laid out but not drawn, its keys quiet
var _safe_top := 0.0
var _safe_bottom := 0.0
var _slide: Tween

func _init(row_: Dictionary = {}, safe_bottom := 0.0, safe_top := 0.0) -> void:
	row = row_
	_safe_top = safe_top
	_safe_bottom = safe_bottom
	name = "HomeWelcome"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	land = bg
	bg.name = "Land"
	bg.color = LAND
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	card = PanelContainer.new()
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = _SIDE
	card.offset_right = -_SIDE
	card.offset_bottom = -_BOTTOM - safe_bottom
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := UiStyleBox.make(UiTokens.COLOR_SURFACE, 20.0, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(_PAD, _PAD, _PAD, _PAD)
	sb.shadow_color = Color(0.18, 0.231, 0.2, 0.14)
	sb.shadow_size = 28.0
	sb.shadow_offset = Vector2(0, 10)
	card.add_theme_stylebox_override(&"panel", sb)
	add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", _GAP)
	card.add_child(col)
	var title := UiKit.label("Welcome to Gensen!", UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	title.add_theme_font_size_override(&"font_size", _TITLE_SIZE)
	col.add_child(title)
	var id := str(row.get("id", ""))
	var city := P0CityRow.new({cluster = id, name = str(row.get("name", "")), region = str(row.get("region", "")),
		climate = str(row.get("climate", "")), landmark = P0Travel.landmark_stamp(id)}, "")   # as HOME-PICK's row, not picked
	city.name = "City"
	city.custom_minimum_size.x = 0   # the card's column, not the list's 344
	var inner := city.get_node("Row") as Control   # the list's row sits 8 in for its picked ground; the card's starts at
	inner.offset_left = 0                          # the padding (row 101 51:160754 at 21 = the card's 20 + its 1 px edge)
	inner.offset_right = 0
	city.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(city)
	var line := UiKit.label(LINE, UiTokens.STYLE_BODY_R14, UiTokens.COLOR_SECONDARY)   # 不知火舞 on #476: secondary, as the pick page's line
	line.name = "Line"
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(line)
	var keys := VBoxContainer.new()
	keys.add_theme_constant_override(&"separation", _KEY_GAP)
	col.add_child(keys)
	start = UiCommandButton.new("Start here")
	start.name = "Start"
	start.custom_minimum_size.y = 48
	start.activated.connect(func(): if not _waiting: start_pressed.emit())
	keys.add_child(start)
	other = UiCommandButton.new("Choose another city", UiCommandButton.Kind.SECONDARY)
	other.name = "Other"
	other.custom_minimum_size.y = 48
	other.activated.connect(func(): if not _waiting: other_pressed.emit())
	keys.add_child(other)

## Where the city's centre goes on the page (不知火舞 342 bce34a87): halfway between the status bar's bottom and the
## card's top, so the card covers none of it.
func city_point() -> Vector2:
	var w := size.x if size.x > 0.0 else 360.0
	var h := size.y if size.y > 0.0 else 800.0
	var card_top := h - _BOTTOM - _safe_bottom - (card.size.y if card.size.y > 0.0 else card.get_combined_minimum_size().y)
	return Vector2(w * 0.5, (_safe_top + card_top) * 0.5)

## The card held back while the camera flies (slide_in brings it): still laid out (city_point reads its height), not
## drawn, its keys quiet.
func wait_for_map() -> void:
	_waiting = true
	card.modulate.a = 0.0

func waiting() -> bool: return _waiting

## The card in: sliding up from below the screen over motion.drawerMs, ease out (`animate`: after the flight, and back
## to the card; 不知火舞 342 bce34a87), or there at once. `again`: slide in even while shown.
func slide_in(animate: bool, again := false) -> void:
	if not _waiting and not again: return
	_waiting = false
	card.modulate.a = 1.0
	if not animate: return
	if _slide != null and _slide.is_valid(): _slide.kill()
	# from its laid-out place (the bottom anchors and grow-up keep it there), drawn lower by the card's height and margin
	var drop := card.get_combined_minimum_size().y + _BOTTOM + _safe_bottom
	_slide_y = drop
	_slide = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide.tween_property(self, ^"_slide_y", 0.0, UiKit.secs(UiTokens.MOTION_DRAWER_MS))

## How far below its place the card is drawn while it slides in (its layout untouched, so anchors never fight it).
var _slide_y := 0.0:
	set(v):
		_slide_y = v
		if card != null: card.position.y = _laid_y() + v

func _laid_y() -> float:
	return (size.y if size.y > 0.0 else 800.0) - _BOTTOM - _safe_bottom - card.size.y

func _map_live() -> bool:
	return map != null and (not map is Node or (is_instance_valid(map) and (map as Node).is_inside_tree()))

func _process(_dt: float) -> void:
	var live := _map_live()
	if not live and _waiting: slide_in(false)   # its map went mid-flight: the card all the same
	var ground := live and bool(map.pick_has_ground())
	if land != null and land.visible == ground: land.visible = not ground
	_place_credits(ground and not _waiting)

## The map's credit line over the real map (q(133) ①; CityMapView's constants): 16 pt from the left, 6 pt over the card.
func _place_credits(on: bool) -> void:
	if credits == null:
		if not on: return
		credits = UiKit.label("© Mapbox © OpenStreetMap", UiTokens.STYLE_BODY_R14)
		credits.name = "MapCredits"
		credits.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
		credits.add_theme_color_override(&"font_color", Color(UiTokens.COLOR_TEXT, CityMapView.CREDITS_ALPHA))
		credits.add_theme_constant_override(&"outline_size", 0)
		add_child(credits)
		move_child(credits, card.get_index())
	credits.visible = on
	if not on: return
	var k := float(map.pick_px_per_pt()) if map.has_method("pick_px_per_pt") else 1.0
	var font := maxi(1, roundi(CityMapView.CREDITS_PT * k))
	if credits.get_theme_font_size(&"font_size") != font: credits.add_theme_font_size_override(&"font_size", font)
	var m := credits.get_combined_minimum_size()
	credits.size = m
	credits.position = Vector2(CityMapView.CREDITS_LEFT_PT * k, card.position.y - CityMapView.CREDITS_GAP_PT * k - m.y)

## The card's outline alone, the size of a one-line city's card, where the card goes; nothing inside it reads or
## takes a tap (342 8c4168ab).
static func placeholder(safe_bottom := 0.0) -> Control:
	var w = new({name = "San Francisco"}, safe_bottom)   # any one-line name: the card's height
	w.name = "HomeWelcomeLoading"
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.get_node("Land").queue_free()   # the flow's own ground stays under it
	var sb := UiStyleBox.make(Color(0, 0, 0, 0), 20.0, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(_PAD, _PAD, _PAD, _PAD)
	w.card.add_theme_stylebox_override(&"panel", sb)
	var col := w.card.get_child(0) as Control
	col.modulate.a = 0.0   # kept for its size
	_quiet(w.card)
	return w

static func _quiet(n: Node) -> void:
	if n is Control: (n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if n is BaseButton: (n as BaseButton).disabled = true
	for c in n.get_children(): _quiet(c)
