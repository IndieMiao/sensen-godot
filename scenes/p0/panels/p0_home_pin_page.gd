extends Control
## Pick your farm spot with a free pin (HOME-PIN, SGODOT-342 PR-2; q(216) ②③⑨, q(223); 340 fc814d17 §5 as 3e4fbec7,
## 6cb4d10e, fdf7c5df and 78cbe60f correct it; frames row 102 54:160901 in Figma 5SVgfevrLzZXqD83uyPgmV). In place of
## the three spots (HOME-PICK-3): the city's map under a pin fixed at the middle of the visible map; the player drags
## and pinches the map, the page reads where the pin's tip lands.
##   Top panel (54:160904): surface, bottom radius 16, shadow sm, safe area + 112: BackPill `‹  Change city` at 7,
##   the title (ExtraBold 22) at 52, the city (Bold 14, secondary) at 80.
##   The pin (54:160909): its tip at the middle of the map between the panel and the card (180, 378 in the frame); a 44
##   white head with the home pin's house (P0Logic.icon home, 26), a 2 × 12 stem, an 8 × 4 shadow; where it may stand a
##   primary 30 % glow under it; where it may not, no glow and the same house in one colour, the secondary ink (56:160935). Lifted 8 px
##   while the map is dragged, its shadow at 70 %, down again 120 ms after.
##   Over the map: outside the city's circle a 30 % text-colour veil, its edge a 2 px white 80 % dash; a place's 300 m
##   ring (ink 50 %, 1.5 px dash) while the pin is within 600 m of it; the city's ponds, outposts and huts as plain pins
##   (no marks, no taps).
##   The card (54:160918): 328 × 48 at 620, radius 16, one line ExtraBold 15 — `0.8 km to Fern Pond · west`, the same
##   where the pin may not stand (fdf7c5df); 50 % while dragging. Build here (680): where the pin may not stand, grey
##   with the reason (`Too far from the city`, `Too close to Oak Tea House`, the general `… a pond / a shop / a hut`
##   when the name does not fit), its tap the sentence as a toast. The back-to-start key (67:161569): 44, 12 over the
##   card at the right, a home line house; hidden while the pin stands on the start (q(223): spot 1, or the farm for a
##   same-city re-pin).
##   Reading (HOME-PIN-LOADING 57:161006) / failed (HOME-PIN-ERR 57:161028): the plain land, no pin, rings or places; an
##   outline card in the card's place, or `Couldn't load farm spots` + Retry in a 56-high card at 612; Build here grey
##   and quiet; no back-to-start key; ‹ Change city as ever.
## The map is whatever answers pick_geo_at / pick_screen_of / pick_put / pick_dragging / pick_px_per_m /
## pick_has_ground (the P0 map in its pick mode); without one the page keeps its own flat map (FlatMap: the desktop,
## the tests), dragged on the page.
## Emits back_pressed, chosen(lat, lng), retry_pressed, unavailable(text).

signal back_pressed
signal chosen(lat: float, lng: float)
signal retry_pressed
signal unavailable(text: String)

const P0HomePin := preload("res://modules/p0/p0_home_pin.gd")
const P0HomeWelcome := preload("res://scenes/p0/panels/p0_home_welcome.gd")
const BackPill := preload("res://scenes/p0/panels/p0_back_pill.gd")
const P0MapScript := preload("res://scenes/p0/p0_map.gd")
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")
const P0Outposts := preload("res://modules/p0/p0_outposts.gd")
const HOME_LINE := preload("res://assets/ui/kit_icons/home_line.svg")   # i-home line · ink (67:161570)

const _PANEL_H := 112.0
const _BACK_Y := 7.0
const _TITLE_Y := 52.0
const _CITY_Y := 80.0
const _TITLE_SIZE := 22
const _CARD_Y := 620.0
const _CARD_H := 48.0
const _ERR_Y := 612.0
const _ERR_H := 56.0
const _BUILD_Y := 680.0
const _KEY_H := 48.0
const _KEY_SIDE := 44.0
const _KEY_GAP := 12.0
const VEIL := Color(0.184, 0.227, 0.2, 0.30)            # COLOR_TEXT 30 %
const EDGE := Color(1, 1, 1, 0.8)
const RING := Color(0.184, 0.227, 0.2, 0.5)
const DRAG_FADE := 0.5
const OVER_NAMES_Z := 2

var cluster := ""
var city_name := ""
var same_city := false
var farm: Variant = null      # [lat, lng]: the farm as it stands, for a same-city re-pin
var map: Object               # the map the pin reads (pick_*), or the page's own FlatMap
var area: Dictionary = {}     # P0HomePin.area of the read; {} while reading or after a failure
var pond: Dictionary = {}     # the beginner pond {name, at} the card measures from
var names: Dictionary = {}    # place id → {name, kind}
var failed := false
var at := [0.0, 0.0]          # the pin's tip on the earth (lat, lng; doubles)
var refusal: Dictionary = {}

var panel: PanelContainer
var title: Label
var land: ColorRect
var veil: ColorRect
var overlay: Overlay
var pin: Pin
var card: PanelContainer
var line: Label
var loading_card: Panel
var error_card: PanelContainer
var build: UiCommandButton
var back_key: Button
var credits: Label            # the map's credit line over the real map (q(133) ①, 不知火舞 342)
var _places: Dictionary = {}  # id → UiMapDestination
var _safe := Vector2.ZERO

func _init(cluster_ := "", city_name_ := "", heading := "Pick your farm spot", safe_top := 0.0, safe_bottom := 0.0,
		same_city_ := false, farm_: Variant = null, map_: Object = null) -> void:
	cluster = cluster_
	city_name = city_name_
	same_city = same_city_
	farm = farm_
	_safe = Vector2(safe_top, safe_bottom)
	name = "HomePinPage"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # the map under it takes the drags and pinches
	map = map_ if map_ != null else FlatMap.new()
	land = ColorRect.new()
	land.name = "Land"
	land.color = P0HomeWelcome.LAND
	land.set_anchors_preset(Control.PRESET_FULL_RECT)
	land.mouse_filter = Control.MOUSE_FILTER_STOP if map is FlatMap else Control.MOUSE_FILTER_IGNORE
	land.gui_input.connect(_flat_input)
	add_child(land)
	veil = ColorRect.new()
	veil.name = "Veil"
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _veil_shader()
	veil.material = mat
	add_child(veil)
	overlay = Overlay.new()
	overlay.page = self
	add_child(overlay)
	pin = Pin.new()
	add_child(pin)
	_make_panel(heading)
	_make_card()
	build = UiCommandButton.new("Build here")
	build.name = "Build"
	build.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	build.offset_left = UiTokens.SPACE_PAGE
	build.offset_right = -UiTokens.SPACE_PAGE
	build.offset_top = _BUILD_Y - 800.0 - safe_bottom
	build.offset_bottom = build.offset_top + _KEY_H
	build.activated.connect(func(): if _can_build() and not bool(map.pick_dragging()): chosen.emit(float(at[0]), float(at[1])))
	build.unavailable_pressed.connect(func(_t: String):
		if not refusal.is_empty(): unavailable.emit(str(P0HomePin.refusal_text(refusal, names).toast)))
	add_child(build)
	back_key = _back_key()
	add_child(back_key)
	credits = UiKit.label("© Mapbox © OpenStreetMap", UiTokens.STYLE_BODY_R14)
	credits.name = "MapCredits"
	credits.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	credits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	credits.add_theme_color_override(&"font_color", Color(UiTokens.COLOR_TEXT, CityMapView.CREDITS_ALPHA))
	credits.add_theme_constant_override(&"outline_size", 0)
	credits.visible = false
	add_child(credits)
	# over the places' names (UiMapDestination.NAME_Z 1, drawn over every disc): the pin, the panel, the card and keys
	for n in [pin, panel, card, loading_card, error_card, build, back_key, credits]: (n as CanvasItem).z_index = OVER_NAMES_Z
	resized.connect(_keep_pin)
	show_loading()

## The page laid out again (a safe area, a rotation): the pin's tip moves on the screen, the point under it stays.
func _keep_pin() -> void:
	if area.is_empty() or not _map_live(): return
	put(float(at[0]), float(at[1]))
	_refresh()

func _make_panel(heading: String) -> void:
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size.y = _safe.x + _PANEL_H
	var sb := UiStyleBox.make(UiTokens.COLOR_SURFACE, 0.0)
	sb.corner_radius = Vector4(0, 0, 16, 16)
	sb.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	sb.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	sb.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	panel.add_theme_stylebox_override(&"panel", sb)
	add_child(panel)
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var back := BackPill.new("Change city")
	back.position = Vector2(12, _safe.x + _BACK_Y)
	back.pressed.connect(func(): back_pressed.emit())
	box.add_child(back)
	title = UiKit.label(heading, UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	title.add_theme_font_size_override(&"font_size", _TITLE_SIZE)
	title.position = Vector2(UiTokens.SPACE_PAGE, _safe.x + _TITLE_Y)
	box.add_child(title)
	var city := UiKit.label(city_name, UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
	city.name = "City"
	city.position = Vector2(UiTokens.SPACE_PAGE, _safe.x + _CITY_Y)
	box.add_child(city)

func _bottom(c: Control, y: float, h: float) -> void:
	c.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	c.offset_left = UiTokens.SPACE_PAGE
	c.offset_right = -UiTokens.SPACE_PAGE
	c.offset_top = y - 800.0 - _safe.y
	c.offset_bottom = c.offset_top + h

func _make_card() -> void:
	card = PanelContainer.new()
	card.name = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := UiStyleBox.make(UiTokens.COLOR_SURFACE, 16.0).with_margins(16, 0, 16, 0)
	sb.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
	sb.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
	sb.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
	card.add_theme_stylebox_override(&"panel", sb)
	_bottom(card, _CARD_Y, _CARD_H)
	line = UiKit.label("", UiTokens.STYLE_TITLE_XB20)
	line.name = "Line"
	line.add_theme_font_size_override(&"font_size", 15)
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(line)
	add_child(card)
	loading_card = Panel.new()   # HOME-PIN-LOADING: the card's place, an edge only (as HOME-WELCOME's, 342 7d39efc5)
	loading_card.name = "Loading"
	loading_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ob := UiStyleBox.make(Color(0, 0, 0, 0), 16.0, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	loading_card.add_theme_stylebox_override(&"panel", ob)
	_bottom(loading_card, _CARD_Y, _CARD_H)
	add_child(loading_card)
	error_card = PanelContainer.new()   # HOME-PIN-ERR 57:161043
	error_card.name = "Error"
	error_card.mouse_filter = Control.MOUSE_FILTER_STOP
	error_card.add_theme_stylebox_override(&"panel", sb.duplicate().with_margins(16, 6, 12, 6))
	_bottom(error_card, _ERR_Y, _ERR_H)
	var row := HBoxContainer.new()
	var msg := UiKit.label("Couldn't load farm spots", UiTokens.STYLE_TITLE_XB20)   # ExtraBold 15, ink, as the card's line (57:161044)
	msg.name = "ErrorLine"
	msg.add_theme_font_size_override(&"font_size", 15)
	msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(msg)
	var retry := UiCommandButton.new("Retry", UiCommandButton.Kind.SECONDARY, true)
	retry.name = "Retry"
	retry.fit_text = true
	retry.min_width = 68
	retry.activated.connect(func():
		show_loading()
		retry_pressed.emit())
	row.add_child(retry)
	error_card.add_child(row)
	add_child(error_card)

## The back-to-start key (67:161569): MapLocateButton's shell — a 44 circle, surface, a 1 px border, a 0 3 4 shadow at
## 16 % — and the i-home line house in ink, 24 at 10, 10.
func _back_key() -> Button:
	var b := Button.new()
	b.name = "BackToStart"
	b.focus_mode = Control.FOCUS_NONE
	for state in [&"normal", &"hover", &"focus", &"pressed", &"hover_pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTokens.COLOR_SURFACE.darkened(0.04) if state == &"pressed" else UiTokens.COLOR_SURFACE
		sb.border_color = UiTokens.COLOR_BORDER
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(22)
		sb.shadow_color = Color(0.18, 0.231, 0.2, 0.16)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(0, 3)
		b.add_theme_stylebox_override(state, sb)
	var glyph := TextureRect.new()
	glyph.name = "Glyph"
	glyph.texture = HOME_LINE
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.position = Vector2(10, 10)
	glyph.size = Vector2(24, 24)
	b.add_child(glyph)
	b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	b.offset_right = -UiTokens.SPACE_PAGE
	b.offset_left = b.offset_right - _KEY_SIDE
	b.offset_bottom = _CARD_Y - _KEY_GAP - 800.0 - _safe.y
	b.offset_top = b.offset_bottom - _KEY_SIDE
	b.pressed.connect(back_to_start)
	return b

## The spots read came: its pin area, the beginner pond (the first spot's), the places' names.
func show_area(read: Dictionary) -> void:
	area = P0HomePin.area(read.get("pin"))
	var spots: Array = read.get("spots", []) if read.get("spots") is Array else []
	var p: Dictionary = spots[0].get("pond", {}) if not spots.is_empty() and spots[0] is Dictionary and spots[0].get("pond") is Dictionary else {}
	var pond_at = P0HomePin.point(p)
	pond = {name = str(p.get("name", "")), at = pond_at} if pond_at != null else {}
	if area.is_empty():   # an older server, a city that cannot be a home (周瑜 on #473): as a failed read
		show_failed()
		return
	failed = false
	names = place_names(area, pond, p)
	if map.has_method("pick_area"): map.pick_area(area.base.x, area.base.y, float(area.range_km))
	var s := start_point()
	at = [s[0], s[1]]
	put(s[0], s[1])
	_make_places()
	_refresh()

## Where the pin starts and the back-to-start key takes it (q(223)).
func start_point() -> Array:
	return P0HomePin.start(area, same_city, farm)

## The places' names for the grey key (Too close to Oak Tea House): the written city's tables, a generated city's read.
static func place_names(a: Dictionary, beginner: Dictionary, beginner_raw: Dictionary) -> Dictionary:
	var out := {}
	for b in a.get("blocks", []):
		var id := str(b.id)
		var o := P0Outposts.find(id)
		if not o.is_empty():
			out[id] = {name = str(o.get("name", "")), kind = "hut" if str(o.get("role", "")) == "mine_hut" else "shop"}
			continue
		var pond_ := P0CityPlaces.pond(id)
		if pond_.is_empty(): pond_ = SystemPonds.location(id)
		if not pond_.is_empty():
			out[id] = {name = str(pond_.get("name", "")), kind = "pond"}
			continue
		for h in P0CityPlaces.huts(P0CityPlaces.cluster_of(id)):
			if str(h.get("id", "")) == id: out[id] = {name = str(h.get("name", "")), kind = "hut"}
	if not beginner.is_empty() and beginner_raw.has("id"): out[str(beginner_raw.id)] = {name = beginner.name, kind = "pond"}
	return out

func _make_places() -> void:
	for p in _places.values(): (p as Node).queue_free()
	_places.clear()
	for b in area.blocks:
		var n: Dictionary = names.get(b.id, {})
		var kind := str(n.get("kind", P0HomePin.kind_of(str(b.id))))
		var o := P0Outposts.find(str(b.id))
		var icon := P0Logic.icon("pond") if kind == "pond" else P0Logic.icon(str(P0MapScript.PIN_ICONS.get(str(o.get("role", "")), "travel")))
		var label := "" if str(o.get("role", "")) == "tackle" else P0MapScript.short_name(str(n.get("name", "")))
		var d := UiMapDestination.new(icon, label)
		d.name = "Place_" + str(b.id).validate_node_name()
		d.resized.connect(_place_places)   # its name laid out widens it: its anchor moves (the page no longer redoes each frame)
		add_child(d)
		move_child(d, pin.get_index())   # under the pin and the panels
		_places[b.id] = d

## Reading (again, after Retry): the plain land and the outline card.
func show_loading() -> void:
	failed = false
	area = {}
	for p in _places.values(): (p as Node).queue_free()
	_places.clear()
	_refresh()

## HOME-PIN-ERR: the spots did not come.
func show_failed() -> void:
	failed = true
	area = {}
	for p in _places.values(): (p as Node).queue_free()
	_places.clear()
	_refresh()

## The map speaks the viewport's points; the page's own may sit elsewhere on it (a canvas layer, a parent's offset).
func geo_at(p: Vector2) -> Array: return map.pick_geo_at(get_global_transform_with_canvas() * p)

func screen_of(lat: float, lng: float) -> Variant:
	var v = map.pick_screen_of(lat, lng)
	return get_global_transform_with_canvas().affine_inverse() * (v as Vector2) if v != null else null

## The map moved so (lat, lng) lies under the pin's tip.
func put(lat: float, lng: float) -> void: map.pick_put(lat, lng, get_global_transform_with_canvas() * tip())

## The pin's tip on the screen: the middle of the map between the panel and the card.
func tip() -> Vector2:
	var top := _safe.x + _PANEL_H
	var bottom := (size.y if size.y > 0.0 else 800.0) - (800.0 - _CARD_Y) - _safe.y
	return Vector2((size.x if size.x > 0.0 else 360.0) * 0.5, (top + bottom) * 0.5)

func _can_build() -> bool: return not area.is_empty() and refusal.is_empty()

func back_to_start() -> void:
	if area.is_empty(): return
	var s := start_point()
	at = [s[0], s[1]]
	put(s[0], s[1])
	_refresh()

## Each frame only asks the map where the tip is, where the circle's centre is on the screen, how near it is and
## whether it is dragged; the page and the overlay (some 540 dash arcs on a 10 km circle) redo only when one of those or
## the page's size moved (周瑜 on #495: 260 / 292 heat). The centre catches a map laid out again under a still tip.
func _process(_dt: float) -> void:
	if area.is_empty() or not _map_live(): return
	if _view_key() != _last_key: _refresh()

var _last_key: Array = []
func _view_key() -> Array:
	return [geo_at(tip()), screen_of(area.base.x, area.base.y), map.pick_px_per_m(), map.pick_dragging(),
		map.pick_has_ground(), size]   # the ground arriving lifts the page's land and shows the credit line

## The map is still there to read: the real one is popped before the page goes (a pick built, ‹ Change city).
func _map_live() -> bool:
	return map != null and (not map is Node or (is_instance_valid(map) and (map as Node).is_inside_tree()))

func _refresh() -> void:
	if not _map_live(): return
	var ready := not area.is_empty()
	_last_key = _view_key() if ready else []
	var dragging := ready and bool(map.pick_dragging())
	# sliding on after the finger lifted: the card's line, the key and the pin's look stay as they were till the camera
	# settles (不知火舞 342, to be ruled on the recording); a finger on it reads live
	var settling := dragging and map.has_method("pick_settling") and bool(map.pick_settling())
	if ready:
		var g: Array = geo_at(tip())
		at = [float(g[0]), float(g[1])]
		if not settling: refusal = P0HomePin.refusal(area, Vector2(at[0], at[1]), start_point())
	else: refusal = {}
	land.visible = not ready or bool(map.pick_has_ground())
	veil.visible = ready
	overlay.visible = ready
	pin.visible = ready
	card.visible = ready
	loading_card.visible = not ready and not failed
	error_card.visible = failed
	_place_credits(ready)
	var s := start_point()
	back_key.visible = ready and P0HomePin.km(Vector2(at[0], at[1]), Vector2(s[0], s[1])) * 1000.0 > P0HomePin.START_M
	if not ready:
		build.reason = "Build here"   # grey and quiet (6cb4d10e): no refusal, so no toast
		return
	if not settling:
		line.text = P0HomePin.card_line(Vector2(at[0], at[1]), pond)
		build.reason = _key_text()
	card.modulate.a = DRAG_FADE if dragging else 1.0
	pin.set_state(refusal.is_empty(), dragging)
	pin.position = tip() - Pin.TIP
	_place_veil()
	_place_places()
	overlay.queue_redraw()

## The map's credit line (q(133) ①; 不知火舞 342: as the map draws it, CityMapView's constants): over the real map only
## — not while reading or failed, not on the page's own flat map (the desktop, the tests) — 16 pt from the left, its
## bottom 6 pt over the card's top; a confirm card's scrim covers it.
func _place_credits(ready: bool) -> void:
	credits.visible = ready and not map is FlatMap and bool(map.pick_has_ground())
	if not credits.visible: return
	var k := float(map.pick_px_per_pt()) if map.has_method("pick_px_per_pt") else 1.0
	var font := maxi(1, roundi(CityMapView.CREDITS_PT * k))
	if credits.get_theme_font_size(&"font_size") != font: credits.add_theme_font_size_override(&"font_size", font)
	var h := credits.get_combined_minimum_size().y
	credits.size = Vector2(credits.get_combined_minimum_size().x, h)
	credits.position = Vector2(CityMapView.CREDITS_LEFT_PT * k, card.position.y - CityMapView.CREDITS_GAP_PT * k - h)

## The grey key's words: the place's own name while it fits the key, else its general word (q(216) ③).
func _key_text() -> String:
	if refusal.is_empty(): return ""
	var t := P0HomePin.refusal_text(refusal, names)
	var font := build.get_theme_font(&"font")
	var fit := (size.x if size.x > 0.0 else 360.0) - UiTokens.SPACE_PAGE * 2.0 - 32.0
	if font != null and font.get_string_size(str(t.key), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x > fit: return str(t.short)
	return str(t.key)

func circle() -> Dictionary:
	var c = screen_of(area.base.x, area.base.y)
	if c == null: return {}
	return {at = c, r = float(area.range_km) * 1000.0 * float(map.pick_px_per_m())}

func _place_veil() -> void:
	var c := circle()
	var mat := veil.material as ShaderMaterial
	mat.set_shader_parameter(&"centre", c.get("at", Vector2(-1e6, -1e6)))
	mat.set_shader_parameter(&"radius", float(c.get("r", 0.0)))
	mat.set_shader_parameter(&"veil", VEIL)

func _place_places() -> void:
	if area.is_empty() or not _map_live(): return   # a name freed after the area went still says resized (周瑜 on #495)
	for b in area.blocks:
		var d: UiMapDestination = _places.get(b.id)
		if d == null: continue
		var s = screen_of(b.at.x, b.at.y)
		d.visible = s != null
		if s != null: d.position = (s as Vector2) - d.anchor_offset()

## The page's own map (the desktop, the tests): drags move it. The mouse only: a touch comes as the mouse too
## (emulate_mouse_from_touch), and a mouse as a touch where the touch is emulated (the shots' drag) — both read, a drag
## moved the map twice its length.
func _flat_input(e: InputEvent) -> void:
	if not map is FlatMap: return
	var f := map as FlatMap
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		f.dragging = (e as InputEventMouseButton).pressed
		if not f.dragging: _refresh()
	elif e is InputEventMouseMotion and f.dragging:
		f.pan((e as InputEventMouseMotion).relative)
		_refresh()

static func _veil_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform vec2 centre = vec2(-1e6);
uniform float radius = 0.0;
uniform vec4 veil : source_color = vec4(0.184, 0.227, 0.2, 0.3);
varying vec2 local;
void vertex() { local = VERTEX; }
void fragment() {
	float d = distance(local, centre);
	COLOR = d > radius ? veil : vec4(0.0);
}
"""
	return s

## The circle's edge and the places' 300 m rings (dashes).
class Overlay extends Control:
	const P0HomePin := preload("res://modules/p0/p0_home_pin.gd")
	var page

	func _init() -> void:
		name = "Overlay"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if page == null or page.area.is_empty(): return
		var c: Dictionary = page.circle()
		if not c.is_empty(): dashed_circle(self, c.at, c.r, page.EDGE, 2.0, 10.0, 6.0)
		var here := Vector2(page.at[0], page.at[1])
		var r_m := float(page.area.clear_m)
		for b in P0HomePin.shown_blocks(page.area, here):
			var s = page.screen_of(b.at.x, b.at.y)
			if s != null: dashed_circle(self, s, r_m * float(page.map.pick_px_per_m()), page.RING, 1.5, 5.0, 4.0)

	static func dashed_circle(ci: CanvasItem, centre: Vector2, r: float, color: Color, width: float, dash: float, gap: float) -> void:
		if r <= 1.0: return
		var steps := maxi(12, int(TAU * r / (dash + gap)))
		var per := TAU / float(steps)
		var on := per * dash / (dash + gap)
		for i in steps: ci.draw_arc(centre, r, per * i, per * i + on, 4, color, width, true)

## The farm pin (54:160909): 60 × 80, its tip at TIP.
class Pin extends Control:
	const TINT := preload("res://scenes/p0/panels/p0_city_row_tint.gdshader")
	const TIP := Vector2(30, 68)
	const LIFT := 8.0
	var can := true
	var lifted := false
	var _house: TextureRect
	var _lift_t := 0.0

	func _init() -> void:
		name = "Pin"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(60, 80)
		_house = TextureRect.new()
		_house.texture = P0Logic.icon("home")
		_house.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_house.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_house.size = Vector2(26, 26)
		_house.position = Vector2(17, 21)
		_house.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()   # where the pin may not stand, the same house in one colour, secondary (56:160935)
		m.shader = TINT
		m.set_shader_parameter("tint", UiTokens.COLOR_SECONDARY)
		_house.material = m
		add_child(_house)

	func set_state(can_: bool, lifted_: bool) -> void:
		if can_ == can and lifted_ == lifted: return
		can = can_
		if lifted_ != lifted:
			lifted = lifted_
			var t := create_tween()
			t.tween_property(self, "_lift_t", 1.0 if lifted else 0.0, 0.12)
			t.tween_callback(queue_redraw)
		(_house.material as ShaderMaterial).set_shader_parameter("mode", 0 if can else 1)
		queue_redraw()

	func _process(_dt: float) -> void:
		var y := 21.0 - LIFT * _lift_t
		if _house.position.y != y:
			_house.position.y = y
			queue_redraw()

	func _draw() -> void:
		var up := LIFT * _lift_t
		if can:   # the glow, 40 × 16 under the tip
			draw_set_transform(Vector2(30, 68), 0.0, Vector2(1.0, 0.4))
			draw_circle(Vector2.ZERO, 20.0, Color(UiTokens.COLOR_PRIMARY, 0.3))
			draw_set_transform(Vector2.ZERO)
		var s := lerpf(1.0, 0.7, _lift_t)
		draw_set_transform(Vector2(30, 68), 0.0, Vector2(4.0 * s, 2.0 * s))
		draw_circle(Vector2.ZERO, 1.0, Color(0.184, 0.227, 0.2, 0.35))
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(29, 56 - up, 2, 12), UiTokens.COLOR_TEXT)
		draw_circle(Vector2(30, 34 - up) + Vector2(0, 2), 23.0, Color(0.184, 0.227, 0.2, 0.18))
		draw_circle(Vector2(30, 34 - up), 22.0, Color.WHITE)

## A flat stand-in for the map (Web Mercator near a point is as good as flat at a city's scale): the desktop and the
## tests. The camera's middle is the screen's middle.
class FlatMap extends RefCounted:
	var centre := [37.7749, -122.4194]   # lat, lng
	var px_per_m := 0.137                # HOME-PIN-1: about 137 px a km
	var view := Vector2(360, 800)
	var dragging := false

	func _m_per_deg_lng(lat: float) -> float: return 111320.0 * cos(deg_to_rad(lat))

	func pick_geo_at(screen: Vector2) -> Array:
		var d := (screen - view * 0.5) / px_per_m
		return [float(centre[0]) - d.y / 111320.0, float(centre[1]) + d.x / _m_per_deg_lng(float(centre[0]))]

	func pick_screen_of(lat: float, lng: float) -> Variant:
		var d := Vector2((lng - float(centre[1])) * _m_per_deg_lng(float(centre[0])), -(lat - float(centre[0])) * 111320.0)
		return view * 0.5 + d * px_per_m

	func pick_put(lat: float, lng: float, screen: Vector2) -> void:
		var d := (screen - view * 0.5) / px_per_m
		var c_lat := lat + d.y / 111320.0
		centre = [c_lat, lng - d.x / _m_per_deg_lng(c_lat)]   # the centre's scale, as pick_geo_at reads it back

	func pick_dragging() -> bool: return dragging
	func pick_px_per_m() -> float: return px_per_m
	func pick_has_ground() -> bool: return true

	func pan(by_px: Vector2) -> void:
		var d := by_px / px_per_m
		centre = [float(centre[0]) + d.y / 111320.0, float(centre[1]) - d.x / _m_per_deg_lng(float(centre[0]))]
