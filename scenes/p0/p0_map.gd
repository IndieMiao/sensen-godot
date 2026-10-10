extends "res://scenes/map_poc/map_poc.gd"
## The P0 map: the old map scene and city view as they are (Mapbox tiles, 3D landmarks, POI
## declutter, pond pins and their info card, the farm miniature), with only the entry points
## rewired to P0. The home city is fixed (P0City), the homestead sits at its farm point, pond pins come from P0's
## pond list (P0Ponds), and nothing here talks to the old farm server or writes the old app's choices. Every city
## cluster can be browsed (SGODOT-275, plan §11.8.1): its bubble at the country zoom, the camera city switching as
## the camera goes over it. Browsing moves only the camera; where the player is (the place chip) never changes.

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")   # every city cluster (SGODOT-275)
const P0Travel := preload("res://modules/p0/p0_travel.gd")   # where the player is in the world (SGODOT-275)
const P0_FARM := "res://scenes/p0/p0_farm.tscn"
const P0_POND := "res://scenes/p0/p0_pond.tscn"
static var P0_REGION := P0City.region()   # the home city's map region (SGODOT-270: from content, san_francisco)
## The homestead's map footprint: the Hengshan Road layout, between Pebble Pond and Reed Pond.
const P0_FARM_CHOICE := {"layout_patch_id": "sh_a", "revision": 2}
## The home-set outposts (tackle shop, tea house, travel post, market square) come from the shared
## outpost table; Go opens the outpost room above the map like a pond (SGODOT-227).
const P0_OUTPOST := "res://scenes/p0/p0_outpost.tscn"
static var NEAREST_POND := P0City.beginner_pond()   # the beginner pond, the closest to home (SGODOT-270: from content)
const PondCard := preload("res://modules/p0/p0_pond_card.gd")
const P0Ponds := preload("res://modules/p0/p0_ponds.gd")   # P0's own ponds: San Francisco (SGODOT-270)
const PinReason := preload("res://modules/p0/p0_pin_reason.gd")   # why a pin wears its mark (q(103))
## Online counts on the outpost pins (GET /p0/presence), refreshed while the map is on top.
const PRESENCE_S := 15.0
## Show on map lands this close (the outpost / pond pins and the homestead read at this zoom).
const SHOW_ZOOM := 15.5

var rt: P0Runtime
var _presence: HTTPRequest
var _online := {}   # outpost id → players online across its rooms
var _marks_sig := ""

func _initial_region_id() -> String:
	return P0_REGION

func _ready() -> void:
	rt = P0Runtime.ensure()
	own_farm_name = "Homestead"   # the player's own pin (不知火舞 on 234: My Farm → Homestead)
	CityMapData.set_region_provider(P0Clusters.region)   # every cluster is a city of the map (SGODOT-275)
	super._ready()
	rt.attach(self)
	for child in $HUD/SafeArea/Root.get_children():
		if child.name == "AccountButton" or child is LanguageButton: child.hide()

# ---------------------------------------------------------------- homestead and ponds
## The homestead: sh_a's farm placed at the home city's farm point, in its region (SGODOT-270: San Francisco's Noe
## Valley). Placing it moves only its map overlay — the pin and where the map lands; the farm scene is P0Garden's.
func _resolve_farm_choice() -> Dictionary:
	var at := P0City.farm_at()
	var choice := P0_FARM_CHOICE.duplicate(true)
	if at != Vector2.ZERO: choice["location"] = {"lat": at.x, "lng": at.y}
	choice["region_id"] = P0_REGION
	return choice

func _server_has_no_farm() -> bool:
	return false

func _open_my_farm() -> void:
	if AppRouter.top_instance() != null or AppRouter._navigation_pending: return
	_return_home()
	_clear_farm_selection()
	_reset_gesture()
	P0Runtime.nav_started()
	AppRouter.open_instance(P0_FARM, {})

func _on_city_pond_requested(entry: Dictionary) -> void:
	if AppRouter.top_instance() != null or AppRouter._navigation_pending: return
	if _travel_first(entry): return
	var pond := P0Ponds.location(str(entry.get("id", "")))
	if pond.is_empty(): return
	_reset_gesture()
	P0Runtime.nav_started()
	AppRouter.open_instance(P0_POND, {"pond_id": pond.id})

## Touch screens have no hover; the farm marker's "Select My Farm" tooltip only shows up under the
## emulator's resting pointer.
func _enter_farm_home(r: Dictionary) -> void:
	super._enter_farm_home(r)
	if farm_markers:
		for c in farm_markers.find_children("*", "Control", true, false): (c as Control).tooltip_text = ""

func _install_city_map() -> void:
	super._install_city_map()
	if city_map:
		# MAP-1 (§10.6.1; 不知火舞 on 234): P0's two-row HUD and Bag take the map's own chrome — no city title, filters,
		# place list or compass, no Map / Farm / Me dock, no + / −; the recenter key stays over Bag. Ponds say Go.
		city_map.host_chrome = true
		city_map.bottom_inset = UiTokens.SIZE_QUICK_BAR_BOTTOM + UiTokens.SIZE_QUICK_BAR_H
		city_map.pond_action = "Go"
		city_map.destination_style = _destination_style
		city_map.host_card = _own_card
		city_map.kept_pin = _kept_pin   # where the player is keeps its pin; the rest give way (SGODOT-269)
		city_map.fog_holes = fog_holes   # §11.7: the world greyed but for the cities explored (SGODOT-275)
		city_map.bubble_state = func(region_id: String) -> String:
			return P0Travel.fog(_view(), P0Clusters.cluster_of_region(region_id))
		_style_locate(city_map.recenter)
		_style_locate(city_map.home_key, "home")   # the home key over it: the same key, i-home (SGODOT-261)
		city_map.home_key.visible = true
	if city_map and not city_map.bundled_ponds:
		city_map.preload_ponds(P0Ponds.all())
		_set_outpost_places()
		city_map.place_requested.connect(_on_place_requested)
		_start_presence()
		# A pond's bank is generated off the main thread while its card is read, so Go is quick.
		city_map.entry_selected.connect(func(e: Dictionary): if str(e.get("kind", "")) == "pond": _prewarm_pond(str(e.id)))
		city_map.entry_selected.connect(_on_entry_selected)
		city_map.pin_tag = _pin_tag
		get_tree().create_timer(2.0).timeout.connect(_prewarm_pond.bind(NEAREST_POND))

# ---------------------------------------------------------------- pond card (TUT-3-04, q(48))
## Where Distance is measured from: the place the player last was (the place chip), home by default.
func _origin() -> Vector2:
	var here: Dictionary = rt.here if rt else {}
	if P0Travel.away(_view()):   # arrived in another city: the player stands at its centre (its places come with 280)
		var c := P0Clusters.get_cluster(P0Travel.here(_view()))
		if not c.is_empty(): return Vector2(float(c.lat), float(c.lng))
	match str(here.get("space", "home")):
		"outpost":
			var o := P0Outposts.find(str(here.get("place", "")))
			if not o.is_empty(): return Vector2(float(o.lat), float(o.lng))
		"pond":
			var p := P0Ponds.location(str(here.get("place", "")))
			if not p.is_empty(): return Vector2(float(p.lat), float(p.lng))
	return Vector2(home_lat, home_lng)

## The map asks for a pond's info for its pin's name every frame (pin_tag, through CityMapView._label_text): it reads
## the received view as it is — the card needs no timers — never session.current(), which copies the whole view each
## call (int11 / int12 hand test: the map ran hot and slow with a few copies per pond pin per frame).
func _pond_info(entry: Dictionary) -> Dictionary:
	if rt == null or rt.session == null: return {}
	var km := P0PlaceSheet.km_between(_origin(), Vector2(float(entry.lat), float(entry.lng)))
	return PondCard.info(rt.session.view, str(entry.id), km)

## "Reed Pond · Beginner pond · 0.8 km" (q(48)); outposts keep their "· N online" tag.
func _pin_tag(entry: Dictionary) -> String:
	if str(entry.get("kind", "")) != "pond": return ""
	var tag := str(_pond_info(entry).get("tag", ""))
	# The pond the player is at says no distance, as its card shows no Distance there (q(80)).
	if is_here("pond", str(entry.get("id", ""))) and tag.contains(" · "): tag = tag.substr(0, tag.rfind(" · "))
	return tag

func _on_entry_selected(entry: Dictionary) -> void:
	if rt == null: return
	if _travel_first(entry): return
	if str(entry.get("kind", "")) == "place":
		var spec := place_card(entry)
		if spec.is_empty(): return
		city_map.info.hide()
		_open_place_card(entry, spec)
		return
	if str(entry.get("kind", "")) != "pond": return
	var info := _pond_info(entry)
	if info.is_empty(): return   # a pond P0 does not know keeps the city view's own card
	city_map.info.hide()
	_open_pond_card(entry, info)

## The pond card (P0PlaceSheet, Figma TUT-3-04 482:193): header (name / Beginner or template), the beginner line,
## Distance and Recommended, Details › (the pond's fish list), Go. At the pond the player is at (q(80)): no Distance,
## and Back to <pond> re-enters it through the loading cover. Tapping outside closes it and clears the selection.
func _open_pond_card(entry: Dictionary, info: Dictionary) -> void:
	var id := str(entry.id)
	var to_fish := [false]
	var spec := P0PlaceSheet.for_here(info, is_here("pond", id))
	spec["reason"] = PinReason.reason(_view(), id)   # q(103): why the pin wears its mark, under the subtitle
	P0PlaceSheet.open(rt.ui, spec,
		func():
			rt.ui.close_modal()
			_on_city_pond_requested(entry),
		func():
			to_fish[0] = true
			_open_pond_fish(entry),
		func():
			if not to_fish[0] and city_map and str(city_map.selected.get("id", "")) == id: city_map.clear_selection(),
		"pond_card")

## The pin of the place the player is at (a pond or an outpost): away from home the avatar stands beside it, so it never
## gives way to the avatar or to a pin packed before it (SGODOT-269). Its changes reach the map's layout with the
## entries _sync_here replaces (CityMapView._layout_wanted).
func _kept_pin(entry: Dictionary) -> bool:
	match str(entry.get("kind", "")):
		"pond": return is_here("pond", str(entry.get("id", "")))
		"place": return is_here("outpost", str(entry.get("id", "")))
	return false

## Whether the player is at this place now (the place chip's place, P0Runtime.here): q(80)'s Back to <name>.
func is_here(space: String, place: String) -> bool:
	return rt != null and str(rt.here.get("space", "")) == space and str(rt.here.get("place", "")) == place

## Details ›: the pond's fish list (q(48) c): caught fish in colour with their name, the rest as a silhouette with
## the Fishing level they need. ×, Back and a tap outside all go back to the pond card (P0Ui.back_modal, the layered
## way back of 亚瑟 on #37; 哪吒 on #95); from the card they close it.
func _open_pond_fish(entry: Dictionary) -> void:
	var ui := rt.ui
	var info := _pond_info(entry)
	var holder := Control.new()
	holder.theme = UiKit.theme()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sheet := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_SHEET, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	panel.add_theme_stylebox_override(&"panel", sheet.with_margins(16, 18, 16, 20 + ui.safe_bottom()))
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 12)
	panel.add_child(col)
	col.add_child(UiObjectHeader.new({"title": str(info.get("title", "")), "state": "%s fish" % ("Pond" if str(info.get("subtitle", "")) == "Beginner" else str(info.get("subtitle", "")))}))
	for f in PondCard.fish_rows(ui.view, str(entry.id)):
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		var icon := UiKit.icon(P0Logic.icon(str(f.id)), 32)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not f.caught: icon.modulate = Color(0.13, 0.15, 0.14)   # silhouette
		row.add_child(icon)
		var text := VBoxContainer.new()
		text.add_theme_constant_override(&"separation", 2)
		text.add_child(UiKit.label(str(f.name), UiTokens.STYLE_C14_XB))
		if not f.caught: text.add_child(UiKit.label("Fishing Lv%d" % int(f.level), UiTokens.STYLE_C12_XB, UiTokens.COLOR_SECONDARY))
		row.add_child(text)
		col.add_child(row)
	holder.add_child(panel)
	var back := [false]   # lambdas capture locals by value: share the flag through an array
	var close := UiCloseButton.new()
	close.pressed.connect(func():
		back[0] = true
		_open_pond_card(entry, info))
	holder.add_child(close)
	panel.resized.connect(func():
		close.position = Vector2(panel.size.x - 16 - UiTokens.SIZE_CLOSE, panel.position.y - 6 - UiTokens.SIZE_CLOSE))
	var id := str(entry.id)
	holder.tree_exiting.connect(func():
		if not back[0] and city_map and str(city_map.selected.get("id", "")) == id: city_map.clear_selection())
	ui._open_modal(holder, 0.0, false)
	ui.modal_kind = "pond_fish"
	ui._modal_back = func():   # set after _open_modal, which clears it
		back[0] = true
		_open_pond_card(entry, info)

func _prewarm_pond(id: String) -> void:
	var pond := P0Ponds.location(id)
	if not pond.is_empty(): WaterShore.prewarm(id, SystemPonds.site(pond))

func _set_outpost_places() -> void:
	var places: Array = P0Outposts.all().map(func(o): return P0Outposts.place_entry(o, int(_online.get(str(o.id), 0))))
	if away(): places.append(home_entry())   # away from home the farm wears its Homestead pin (不知火舞 on 234)
	city_map.set_places(places)

func _on_place_requested(entry: Dictionary) -> void:
	if _travel_first(entry): return
	var outpost := P0Outposts.find(str(entry.get("id", "")))
	if outpost.is_empty(): return
	city_map.dismiss_overlays()
	_open_outpost(str(outpost.id))

## Go: the outpost room opens above the map (the player walks in at the door); leaving it returns here.
func _open_outpost(id: String) -> void:
	if AppRouter.top_instance() != null or AppRouter._navigation_pending: return
	if not ResourceLoader.exists(P0_OUTPOST):
		if str(P0Outposts.find(id).get("role", "")) == "tackle": rt.ui.open_kai_greeting()   # until the room scene lands
		return
	_reset_gesture()
	P0Runtime.nav_started()
	AppRouter.open_instance(P0_OUTPOST, {"outpost_id": id})

# ---------------------------------------------------------------- destination pins and place cards (SGODOT-234 A2)
const HOME_PIN := "home"
## The outposts' MapDestination icons by role (不知火舞 on 234): tea pot, tackle rod, market board, post travel.
const PIN_ICONS := {"tea": "pot", "tackle": "rod", "market": "board", "post": "travel"}
## Away from home the avatar stands left of the pin of the place it is at, level with its disc (Figma 1802:118849).
const AVATAR_BESIDE := Vector2(-44, 0)
var _here_sig := ""
var _dest_styles := {}   # "kind:id" -> a pond's / place's style: asked several times per pin per frame (刘邦 on #100)

## Ponds P0 knows, outposts and the homestead open P0PlaceSheet, not the city view's info panel; landmarks and POIs
## keep that name card.
func _own_card(entry: Dictionary) -> bool:
	match str(entry.get("kind", "")):
		"pond": return not _pond_info(entry).is_empty()
		"place": return not place_card(entry).is_empty()
	return false

## MapDestination 1795:103793 (LOCK-24): outposts by role, ponds, and the homestead's pin with its name on a plate.
## Landmarks and POIs keep the city view's own pins.
func _destination_style(entry: Dictionary) -> Dictionary:
	if not str(entry.get("kind", "")) in ["pond", "place"]: return {}   # landmarks and POIs: none, and not cached
	var key := "%s:%s" % [entry.get("kind", ""), entry.get("id", "")]
	if not _dest_styles.has(key): _dest_styles[key] = _destination_style_of(entry)
	return _dest_styles[key]

func _destination_style_of(entry: Dictionary) -> Dictionary:
	match str(entry.get("kind", "")):
		"pond": return {"icon": P0Logic.icon("pond")}
		"place":
			if str(entry.get("id", "")) == HOME_PIN: return {"icon": P0Logic.icon("home"), "plate": true}
			var o := P0Outposts.find(str(entry.get("id", "")))
			if not o.is_empty(): return {"icon": P0Logic.icon(str(PIN_ICONS.get(str(o.role), "travel")))}
	return {}

## Whether the player is away from the homestead — at a pond or an outpost (the place chip's place). At home, in the
## farmhouse or the mine, the avatar is the homestead's mark and no Homestead pin is drawn (不知火舞 on 234).
func away() -> bool:
	if rt == null: return false
	return str(rt.here.get("space", "home")) in ["pond", "outpost"] or P0Travel.away(_view())

func avatar_shift() -> Vector2:
	return AVATAR_BESIDE if away() else Vector2.ZERO

## The homestead's pin, drawn only while the player is away (its avatar stands at the place it is at). A MapDestination
## with its own card (host_card), so no art or action of the city view's: `filter` "pond" only keeps it with the
## outposts if the map's filter were ever Ponds (P0 shows no filters).
func home_entry() -> Dictionary:
	return {"id": HOME_PIN, "kind": "place", "name": "Homestead", "category": "Your farm", "lat": home_lat,
		"lng": home_lng, "filter": "pond", "tag": ""}

## The avatar stands where the player is (the place chip, P0Runtime.here) and the farm wears its pin while away.
## Cheap to call every frame: it acts when the place or the homestead's point changes.
func _sync_here() -> void:
	if rt == null or city_map == null: return
	var at := _origin()
	var sig := "%s|%s|%s|%.7f|%.7f" % [rt.here.get("space", ""), rt.here.get("place", ""), P0Travel.here(_view()), home_lat, home_lng]
	if sig == _here_sig: return
	_here_sig = sig
	set_self_at(at.x, at.y)
	if farm_markers:
		farm_markers.self_label_off = away()   # the avatar is not the homestead's mark there
		if away(): farm_markers.anchor_shift["self"] = AVATAR_BESIDE
		else: farm_markers.anchor_shift.erase("self")
	# Also how the pins learn where the player is: a pond's name says its distance from here (_pin_tag), and the city
	# view lays its pins out again only when their entries are replaced (SGODOT-260, CityMapView._layout_wanted).
	_set_outpost_places()
	_marks_sig = ""   # the homestead's mark moves between the avatar and its pin

## The place card spec (q(80), P0PlaceSheet): an outpost — its name, data category, Distance, Online now (no row at
## 0), Go; the homestead — Homestead, Your farm, Distance, Go home · Free. At the place the player is at: no Distance,
## Back to <name>. {} for a place P0 does not know.
func place_card(entry: Dictionary) -> Dictionary:
	var id := str(entry.get("id", ""))
	var to := Vector2(float(entry.get("lat", 0.0)), float(entry.get("lng", 0.0)))
	var distance := ["Distance", P0PlaceSheet.distance_text(P0PlaceSheet.km_between(_origin(), to))]
	if id == HOME_PIN:
		return P0PlaceSheet.for_here({"title": "Homestead", "subtitle": "Your farm", "reason": PinReason.reason(_view(), id),
			"facts": [distance], "primary": "Go home · Free"}, not away())
	var o := P0Outposts.find(id)
	if o.is_empty(): return {}
	var facts: Array = [distance]
	var online := int(_online.get(id, 0))
	if online > 0: facts.append(["Online now", str(online)])
	return P0PlaceSheet.for_here({"title": str(o.name), "subtitle": str(o.category), "reason": PinReason.reason(_view(), id),
		"facts": facts, "primary": "Go"}, is_here("outpost", id))

## The view as received (no copy, as _pond_info); {} before a session.
func _view() -> Dictionary:
	return rt.session.view if rt != null and rt.session != null else {}

## Go / Back to: the homestead's opens the farm, an outpost's its room (re-entered through the loading cover when the
## player was there, q(80)). Tapping outside closes the card and clears the selection.
func _open_place_card(entry: Dictionary, spec: Dictionary) -> void:
	var id := str(entry.get("id", ""))
	P0PlaceSheet.open(rt.ui, spec,
		func():
			rt.ui.close_modal()
			if id == HOME_PIN: _open_my_farm()
			else: _open_outpost(id),
		Callable(),
		func():
			if city_map and str(city_map.selected.get("id", "")) == id: city_map.clear_selection(),
		"place_card")

# ---------------------------------------------------------------- outpost online counts
func _start_presence() -> void:
	if is_instance_valid(_presence): return
	_presence = HTTPRequest.new()
	_presence.timeout = 8.0
	add_child(_presence)
	_presence.request_completed.connect(_on_presence)
	var timer := Timer.new()
	timer.wait_time = PRESENCE_S
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_poll_presence)
	_poll_presence()

func _poll_presence() -> void:
	if not is_instance_valid(_presence) or not is_visible_in_tree() or rt == null: return
	if _presence.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED: return
	var headers := PackedStringArray(["x-p0-player: " + rt.session.player_id])
	if rt.session.access_key != "": headers.append("x-p0-key: " + rt.session.access_key)   # the demo server's key
	_presence.request(rt.session.base_url + "/p0/presence", headers)

func _on_presence(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or city_map == null: return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or not (data.get("outposts") is Dictionary): return
	var online := {}
	for id in data.outposts: online[str(id)] = int(data.outposts[id].get("online", 0))
	if online == _online: return
	_online = online
	_set_outpost_places()

## The city view's own controls: the recenter key brings the camera back to the player without changing the zoom
## (不知火舞 on 234); outfits are not in P0 (their button is gone with the old chrome).
func _city_action(action: String) -> void:
	match action:
		"recenter":   # back to the player, the zoom kept, nothing selected (LOCK-24; flies since SGODOT-267)
			var at := _origin()
			_fly("recenter", at.x, at.y, zoom)
		"home": go_home_view()
		"outfit": rt.ui.toast("Outfits come later")
		_: super._city_action(action)

## The home key (SGODOT-261, the user's call; 不知火舞 keeps 197): from anywhere — at a pond or an outpost the camera
## follows the player there and the homestead is lost among the pins — the camera flies back to the homestead and, on
## landing, selects it, as a tap on its pin does away (its card: Homestead · Go home · Free) and on the avatar at home.
func go_home_view() -> void:
	if city_map == null or rt == null: return
	_fly("home", home_lat, home_lng, SHOW_ZOOM, func():
		if away(): city_map.select(home_entry())
		else: _own_pin_pressed())

## The map's own camera moves fly (SGODOT-267, the user's call; 197 LOCK-24 / LOCK-08 updated by 不知火舞): the home
## key, the recenter key and Show on map share one flight, the city's (MapFlight, cubic in-out) capped at FLIGHT_MAX_S,
## each with what it does on landing (`land`). A touch on the map stops it where it is with nothing landing (MapPoc
## kills the flight on a press); the same move asked again while it flies is ignored, another one takes over.
const FLIGHT_MAX_S := 1.2   # a same-city flight longer than this feels like waiting; MapFlight's 3 s is a city's
var _flight: Tween
var _flight_kind := ""

func _fly(kind: String, lat: float, lng: float, to_zoom: float, land := Callable()) -> void:
	if _flight != null and _flight.is_running() and kind == _flight_kind: return
	_flight_kind = kind
	# Already there (to about a centimetre: is_equal_approx's relative tolerance is some 35 m at this latitude).
	if absf(center_lat - lat) < 1e-7 and absf(center_lng - lng) < 1e-7 and absf(zoom - to_zoom) < 1e-3:
		if _flight != null: _flight.kill()   # a flight elsewhere gives way
		if land.is_valid(): land.call()   # already there: nothing to fly
		return
	_fly_to(lat, lng, to_zoom, city_bearing, land, FLIGHT_MAX_S)
	_flight = _focus_tween

## MapLocateButton 1793:103795 (LOCK-24): the recenter key as a 44 round button styled like Close (color/surface,
## 1 px color/border) with a light shadow, the 22 i-locate in its own colours. The home key wears the same with i-home.
func _style_locate(b: Button, glyph := "locate") -> void:
	b.theme = UiKit.theme()
	b.theme_type_variation = UiTokens.BUTTON_CLOSE_ROUND
	for state in [&"normal", &"hover", &"focus", &"disabled", &"pressed", &"hover_pressed"]:
		b.remove_theme_stylebox_override(state)   # the map's own 32 disc
		var sb := b.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		if sb != null:
			sb.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
			sb.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
			sb.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
			b.add_theme_stylebox_override(state, sb)
		b.add_theme_color_override(StringName("icon_%s_color" % state), Color.WHITE)   # the glyph's own ink and green
	b.icon = P0Logic.icon(glyph)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_constant_override(&"icon_max_width", 22)
	b.custom_minimum_size = Vector2(UiTokens.SIZE_CLOSE, UiTokens.SIZE_CLOSE)

## The player's own avatar: the card of the place the player is at (q(80): Back to <name>) — the homestead's at home,
## the pond's or the outpost's when it stands beside their pin.
func _own_pin_pressed() -> void:
	if city_map == null or rt == null: return
	_clear_farm_selection()
	city_map.dismiss_overlays()
	var place := str(rt.here.get("place", ""))
	match str(rt.here.get("space", "home")):
		"pond":
			var p := P0Ponds.location(place)
			if not p.is_empty():
				city_map.select((p as Dictionary).merged({"kind": "pond"}))
				return
		"outpost":
			var o := P0Outposts.find(place)
			if not o.is_empty():
				city_map.select(P0Outposts.place_entry(o, int(_online.get(place, 0))))
				return
	_open_place_card(home_entry(), place_card(home_entry()))

func _on_city_visit_requested(farm_id: String) -> void:
	if farm_id == "self":
		city_map.dismiss_overlays()
		_open_my_farm()
	else: super._on_city_visit_requested(farm_id)

# ---------------------------------------------------------------- the opening view (MAP-1, 不知火舞 on 234)
## Opening the map frames the home set (MAP-1; 不知火舞 on 234 A2): a view in z13.5–16, pins and their name rows inside
## the safe frame (names slide in from the edges) — under the HUD's second row + 16, over Bag − 16, 16 from the sides.
## The avatar and every pin wearing a marker (the first session's Reed Pond) always go in; then the home set — each role's outpost nearest home, and away from
## home the Homestead pin — nearest the avatar first, each while the view still holds them all at z13.5: the first that
## would not stays offscreen, and so do the farther ones. At z13.5 outposts of different roles (300 m apart at least)
## never cover each other whole. Not even the must-haves fit: z13.5 on the avatar. Recenter keeps the zoom; Show on
## map and the camera kept on return are unchanged.
const FRAME_ZOOM_MAX := 16.0
const FRAME_ZOOM_MIN := 13.5
const FRAME_PAD := 16.0
## What the last opening view holds (frame_home_set).
var framed: Array = []

func _frame_home() -> void:
	# A farm booted as the root scene (the first session lands on the farm, q(44)) leaves by swapping the root for a
	# fresh map, so no resume: a Show on map from there points at its pin instead of the opening view (int9 S1).
	if _take_after_leave(): return
	frame_home_set.call_deferred()   # the city view has its size once the frame lays it out

func frame_home_set() -> void:
	if city_map == null or city_map.size.y <= 0.0 or not is_inside_tree(): return
	var safe := frame_safe_rect()
	var chosen := frame_must()
	var view := _fit(chosen, safe)
	if not view.is_empty():
		for it in frame_optional():
			var more := _fit(chosen + [it], safe)
			if more.is_empty(): break   # the nearest that does not fit: it and the farther ones stay offscreen
			chosen.append(it)
			view = more
	framed = chosen
	if view.is_empty(): _look(_origin(), FRAME_ZOOM_MIN)
	else:
		view = _part_pins(chosen, view, safe)
		_look(view.at, float(view.z))
	_update_cameras()   # the trials moved only the Godot camera: now the map, pawns and markers follow

## 不知火舞 on 269: space pins give way to the pins packed before them, so the opening view zooms in a tenth at a time,
## up to z16, while that brings more of the pins it holds into view untouched (the first session's Tackle Shop by Reed
## Pond). The must set (the avatar, the marked pins) stays in the frame, centred on the whole set and, where that pushes
## it out, on the must set. It takes the first view that shows more of them; where none does before z16 or before the
## must set stops fitting, the opening view stays as it was rather than zooming in for nothing and losing farther pins,
## and the packing folds the touching ones. Trials move the Godot camera only.
func _part_pins(items: Array, view: Dictionary, safe: Rect2) -> Dictionary:
	var must := frame_must()
	_look(view.at, float(view.z))
	var base := _pins_shown(items, safe)
	if base == items.filter(func(it): return not it.get("self_pin", false)).size(): return view   # all shown already
	var z := float(view.z)
	while z < FRAME_ZOOM_MAX - 0.001:
		z = minf(FRAME_ZOOM_MAX, z + 0.1)
		_look(Vector2(center_lat, center_lng), z)
		_centre_on(items, safe)
		if not safe.encloses(_frame_box(must)): _centre_on(must, safe)
		if not safe.encloses(_frame_box(must)): break   # closer would push the avatar or a marked pin out
		if _pins_shown(items, safe) > base: return {"at": Vector2(center_lat, center_lng), "z": z}
	return view

## Pans the trial camera so `items` sit centred in `safe` (with the map's pitch their middle is not the screen's).
func _centre_on(items: Array, safe: Rect2) -> void:
	for k in 4:
		var shift := safe.get_center() - _frame_box(items).get_center()
		if shift.length() < 1.0: break
		_pan_by(shift)

## How many space pins of `items` this trial view would show: in the frame, and clear by the packing's margin of those
## counted before them (in their order: the marked pins first, then the nearest), a marked pin always (their discs over
## their points, MapDestination; CityMapView._place_candidate decides on the map).
func _pins_shown(items: Array, safe: Rect2) -> int:
	var placed: Array = []
	var d := UiMapDestination.DISC
	for it in items:
		if it.get("self_pin", false): continue
		var p = geo_to_screen(float(it.lat), float(it.lng))
		if p == null or not safe.has_point(p): continue
		var disc := Rect2((p as Vector2) - Vector2(d * 0.5, d), Vector2(d, d))
		if str(it.get("marker", "")) == "" and placed.any(func(r): return (r as Rect2).intersects(disc.grow(CityMapView.PACK_MARGIN))): continue
		placed.append(disc)
	return placed.size()

## The smallest view in z13.5–16 holding `items` inside `safe`, centred on them: {at, z}; {} when z13.5 does not hold
## them. Trials move the Godot camera only (刘邦 on #92).
func _fit(items: Array, safe: Rect2) -> Dictionary:
	var mid := Vector2.ZERO
	for it in items: mid += Vector2(float(it.lat), float(it.lng))
	mid /= maxf(1.0, items.size())
	var steps := int(round((FRAME_ZOOM_MAX - FRAME_ZOOM_MIN) * 10.0))
	var at := mid
	for i in steps + 1:
		_look(at, FRAME_ZOOM_MAX - i * 0.1)
		for k in 4:   # centre the set in the frame: with the map's pitch its middle is not the screen's
			var box := _frame_box(items)
			var shift := safe.get_center() - box.get_center()
			if shift.length() < 1.0: break
			_pan_by(shift)
		if safe.encloses(_frame_box(items)): return {"at": Vector2(center_lat, center_lng), "z": zoom}
		at = Vector2(center_lat, center_lng)   # the next tenth starts centred where this one ended
	return {}

## What the opening view always holds: the own avatar (where the player is) and every pin wearing a marker.
func frame_must() -> Array:
	var at := _origin()
	var out: Array = [{lat = at.x, lng = at.y, self_pin = true, shift = avatar_shift()}]
	var marked := city_pin_markers()
	for e in city_map.entries:
		if marked.has(str(e.get("id", ""))): out.append((e as Dictionary).merged({marker = marked[str(e.id)]}, true))
	return out

## The home set it adds while they fit, nearest the avatar first: each role's outpost nearest home, and away from home
## the Homestead pin; pins already in frame_must are not repeated.
func frame_optional() -> Array:
	var nearest := {}   # role -> outpost
	for o in P0Outposts.all():
		var e := P0Outposts.place_entry(o, int(_online.get(str(o.id), 0)))
		var r := str(o.role)
		if not nearest.has(r) or city_map._home_distance(e) < city_map._home_distance(nearest[r]): nearest[r] = e
	var out: Array = nearest.values()
	if away(): out.append(home_entry())
	var must := frame_must().map(func(x): return str(x.get("id", "")))
	out = out.filter(func(x): return not must.has(str(x.get("id", ""))))
	var at := _origin()
	out.sort_custom(func(a, b): return P0PlaceSheet.km_between(at, Vector2(float(a.lat), float(a.lng))) \
		< P0PlaceSheet.km_between(at, Vector2(float(b.lat), float(b.lng))))
	return out

## Every pin the opening view may hold: frame_must, then frame_optional in the order they are tried.
func home_set_items() -> Array:
	return frame_must() + frame_optional()

## The safe frame in screen space: under the HUD's second row + 16, over Bag − 16, 16 from the sides.
func frame_safe_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	var top := rt.ui.safe_top() + UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H + FRAME_PAD
	var bottom := vp.y - rt.ui.safe_bottom() - UiTokens.SIZE_QUICK_BAR_BOTTOM - UiTokens.SIZE_QUICK_BAR_H - FRAME_PAD
	return Rect2(FRAME_PAD, top, vp.x - FRAME_PAD * 2.0, bottom - top)

func _frame_box(items: Array) -> Rect2:
	var box := Rect2()
	var first := true
	for it in items:
		var p = geo_to_screen(float(it.lat), float(it.lng))
		if p == null: continue
		var fp: Rect2 = FarmMarkers.self_footprint(zoom) if it.get("self_pin", false) else _frame_footprint(it)
		var r := Rect2((p as Vector2) + fp.position + (it.get("shift", Vector2.ZERO) as Vector2), fp.size)
		box = r if first else box.merge(r)
		first = false
	return box

## What a pin needs in the opening view: a MapDestination its disc and a name row under it and over it (the name goes
## over when under touches another; 刘邦 on #111) — the name slides in from the screen edge (CityMapView.LABEL_EDGE),
## so only its height counts; other pins their whole footprint.
func _frame_footprint(it: Dictionary) -> Rect2:
	if city_map._destination(it).is_empty(): return city_map.pin_footprint(it)
	var name_h := UiMapDestination.label_size_for(city_map._label_text(it)).y
	var d := UiMapDestination.DISC
	if name_h <= 0.0: return Rect2(-d * 0.5, -d, d, d)
	var over := UiMapDestination.above_gap_for(city_map._marker_of(it) != "") + name_h
	return Rect2(-d * 0.5, -d - over, d, over + d + UiMapDestination.LABEL_GAP + name_h)

## One trial view: the Godot camera only (刘邦 on #92: a hundred full updates in a frame would push the native map's
## camera and the marker sync each time).
func _look(at: Vector2, z: float) -> void:
	center_lat = at.x
	center_lng = at.y
	_set_zoom(z)
	_place_camera()

## Moves the view so what is on screen moves by `shift` (screen px).
func _pan_by(shift: Vector2) -> void:
	var c = geo_to_screen(center_lat, center_lng)
	if c == null: return
	var ground = _ground_point((c as Vector2) - shift)
	if not ground is Vector3: return
	var g := MapGeoMath.world_to_geo(ground, anchor_lat, anchor_lng)
	_look(g, zoom)

## The place chip on the map (MAP-1): back to where the player is (P0Runtime.return_to).
func p0_return(route: String) -> void:
	if route.begins_with("pond:"): _on_city_pond_requested({"id": route.trim_prefix("pond:")})
	elif route.begins_with("outpost:"): _open_outpost(route.trim_prefix("outpost:"))
	else: _open_my_farm()

## Without the native map (desktop, tests holding the map in a SubViewport) the map drawn is the viewport: the camera
## follows its height as on a phone. map_poc takes the window's, which can be taller — the desktop's 1280 override, a
## 1200 shot, the test runner's window — and drew the map further out than a phone does at the same zoom (苏烈: the
## map tests passed or failed by the runner's window). With the native map: its own logical height, as before.
func _map_logical_height() -> float:
	if map == null and is_inside_tree():
		var h := get_viewport().get_visible_rect().size.y
		if h > 0.0: return h
	return super._map_logical_height()

func _exit_tree() -> void:
	CityMapData.set_region_provider(Callable())
	super._exit_tree()

# ---------------------------------------------------------------- travel (SGODOT-275, §11.8; the free first version)
## The travel card (MAP-5 in the place-sheet layout until its frame comes): the city, how far and which Trip, what it
## costs (nothing in the first version: Free), whether it is a first visit, and that going home is always free. Fly
## sends `travel`; the server's arrival event flies the camera there (on_arrival). From a city bubble, and from a
## pond / outpost of that city refused with pass_required / trip_expired (the server's preview then names it).
func open_travel(cluster: String, preview := {}) -> void:
	var c := P0Clusters.get_cluster(cluster)
	if c.is_empty() or rt == null: return
	var trip := P0Travel.trip(_view(), cluster)
	if not preview.is_empty(): trip = {km = int(preview.get("km", trip.get("km", 0))), trip = int(preview.get("trip", trip.get("trip", 1))),
		name = str(preview.get("trip_name", trip.get("name", "")))}
	var first := P0Travel.fog(_view(), cluster) == "unexplored"
	var spec := {
		"title": "%s, %s" % [str(c.name), str(c.country)] if str(c.country) != "" else str(c.name),
		"subtitle": "Unexplored" if first else "Visited ×%d" % P0Travel.visits(_view(), cluster),
		"line": P0Travel.trip_line(trip),
		"facts": [["Cost", "Free"], ["Visit", "First visit · stamp + 10 Energy" if first else "Return visit"]],
		"primary": "Fly",
	}
	P0PlaceSheet.open(rt.ui, spec, func():
		rt.ui.close_modal()
		_origin_before = _origin()
		rt.session.send({"type": "travel", "to": cluster}), Callable(), Callable(), "travel_card")

var _origin_before := Vector2.ZERO   # where the player stood when Fly was pressed: the arrival flight starts there

## The server's arrival (events {kind: "arrival"}): the camera flies to the city's overview (3–5 s by Trip, §11.8.4)
## and lands with the welcome (q(108): a first visit is stamped, its +10 Energy floats as Energy does; a return only
## floats Welcome back). The avatar stands there from now on (_sync_here reads view.travel).
func on_arrival(ev: Dictionary) -> void:
	var cluster := str(ev.get("cluster", ""))
	var c := P0Clusters.get_cluster(cluster)
	if c.is_empty(): return
	var r := P0Clusters.region(cluster)
	var overview: Dictionary = CityMapData.city(str(r.get("id", ""))).get("overview", {})
	# §11.8.4: from where the player was (the homestead, or the last city) up and along to the city's overview.
	var from := _origin_before
	_origin_before = Vector2.ZERO   # one arrival per Fly: a later arrival (another device) starts from where it lands
	_here_sig = ""
	_sync_here()
	if from != Vector2.ZERO:
		center_lat = from.x
		center_lng = from.y
	var welcome := ("Welcome to %s · Stamp collected" % str(c.name)) if bool(ev.get("first", false)) else "Welcome back"
	_switch_city(r)
	_fly_to(float(overview.get("lat", c.lat)), float(overview.get("lng", c.lng)), float(overview.get("zoom", 11.0)),
		float(overview.get("bearing", 0.0)), func(): rt.ui.toast(welcome), P0Travel.flight_s(int(ev.get("trip", 1))))
	_flight = _focus_tween
	_flight_kind = "travel"

## The city a pin is in: its `cluster` (generated places, SGODOT-280: also the prefix of their id, `gn-1850147~pond0`),
## else the home city (P0's hand-written places).
static func cluster_of_entry(entry: Dictionary, home: String) -> String:
	var c := str(entry.get("cluster", ""))
	if c != "": return c
	var id := str(entry.get("id", ""))
	return id.substr(0, id.find("~")) if id.find("~") > 0 else home

## §11.7.2: a pond or outpost of a city the player holds no pass for is not entered — its tap opens that city's travel
## card (the server would refuse with pass_required anyway). True when it did.
func _travel_first(entry: Dictionary) -> bool:
	if not str(entry.get("kind", "")) in ["pond", "place"] or str(entry.get("id", "")) == HOME_PIN: return false
	var cluster := cluster_of_entry(entry, P0Travel.home(_view()))
	if P0Travel.covers(_view(), cluster): return false
	if city_map: city_map.clear_selection()
	open_travel(cluster)
	return true

## The fog's holes (§11.7.3): one round every explored city near the screen, a little wider than its radius, in the city
## view's pixels; the farthest at most MapFogLayer.MAX_HOLES. Asked each frame; projection only, no list work.
## Rebuilt only when the camera or the explored list changes, so a still map costs nothing (SGODOT-260).
var _fog_key := ""
var _fog_holes: Array = []

func fog_holes() -> Array:
	if city_map == null: return []
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(360, 800)
	var explored := P0Travel.explored(_view())
	var key := "%.7f|%.7f|%.4f|%.2f|%.2f|%s|%d" % [center_lat, center_lng, zoom + _zoom_elastic, bearing, pitch, vp, explored.hash()]
	if key == _fog_key: return _fog_holes
	_fog_key = key
	var scale := vp.y / _map_logical_height() * 512.0 * pow(2.0, zoom + _zoom_elastic)   # px per unit of Web Mercator
	var out: Array = []
	for cluster in explored:
		var c := P0Clusters.get_cluster(cluster)
		if c.is_empty(): continue
		var p = geo_to_screen(float(c.lat), float(c.lng))
		if p == null: continue
		var km := P0Clusters.radius_km(int(c.population)) * 1.15
		var r := km / (40075.0 * maxf(0.05, cos(deg_to_rad(float(c.lat))))) * scale
		var at: Vector2 = (p as Vector2) - city_map.global_position
		if not Rect2(Vector2.ZERO, vp).grow(r + 2.0).has_point(at): continue   # only holes that reach the screen
		out.append({at = at, r = r})
		if out.size() >= 64: break
	_fog_holes = out
	return out

## Going home from another city (q(108)): free and instant — `return_home`, then the farm as ever. Welcome home
## floats; no stamp, no Energy. At home it does nothing.
func _return_home() -> void:
	if rt == null or not P0Travel.away(_view()): return
	rt.session.send({"type": "return_home"})
	rt.ui.toast("Welcome home")

# ---------------------------------------------------------------- browsing every city (SGODOT-275, §11.8.1)
## The camera city switches as the camera goes over a city (map_poc._update_active_city) and a bubble flies to its
## city (fly_to_city): both are Browse. Only the camera's city and the map's title change; the old app's saved city
## choice is not written, the homestead and the place chip stay where the player is.
func _switch_city(r: Dictionary) -> void:
	if not city_map or str(r.get("id", "")) == str(region.get("id", "")): return
	_clear_farm_selection()
	city_map.dismiss_overlays()
	region = r
	city_map.region_changed()
	_refresh_nearby()

## Any city by its region or cluster id, not only those around the camera (a bubble, later the destination lists):
## map_poc.fly_to_city looks it up in city_regions(), so it is in the list while it does.
func fly_to_city(id: String) -> void:
	var r := P0Clusters.region(P0Clusters.cluster_of_region(id))
	if r.is_empty(): return
	_asked = r
	_regions_key = ""
	super.fly_to_city(str(r.id))
	_asked = {}
	_regions_key = ""
	var cluster := P0Clusters.cluster_of_region(str(r.id))
	if cluster == "" or cluster == P0Travel.here(_view()) or rt == null: return
	# Home is never a trip (q(108)): from another city the home city's bubble goes home, as the homestead's Go home.
	if cluster == P0Travel.home(_view()): _return_home()
	else: open_travel(cluster)

## At most this many city bubbles, at least this far apart on screen (px), most populous first.
const CITY_BUBBLES := 30
const BUBBLE_GAP := 72.0
var _regions_key := ""
var _regions: Array = []
var _asked := {}

## The cities around the camera (map_poc asks for its bubbles, the title and the camera city): the home city, the
## camera's city, and the most populous clusters in view, fewer the farther out (city_min_population) and kept
## apart on screen. Rebuilt only when the camera has moved enough to change them.
func city_regions() -> Array:
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(360, 800)
	var z := zoom + _zoom_elastic
	var step := 360.0 / pow(2.0, z) / 4.0   # a quarter of a 512 px tile's width in degrees
	var key := "%.1f|%d|%d|%s|%dx%d" % [z, roundi(center_lat / step), roundi(center_lng / step), str(region.get("id", "")), vp.x, vp.y]
	if key == _regions_key: return _regions
	_regions_key = key
	var out: Array = []
	var ids := {}
	var add := func(r: Dictionary) -> void:
		if r.is_empty() or ids.has(str(r.id)): return
		ids[str(r.id)] = true
		out.append(r)
	add.call(P0Clusters.region(P0Clusters.cluster_of_region(P0_REGION)))
	if not region.is_empty(): add.call(region)
	add.call(_asked)
	var box := _view_box(vp, z)
	var placed: Array = []
	for c in P0Clusters.in_box(box.x, box.y, box.z, box.w, city_min_population(z), 200):
		if out.size() >= CITY_BUBBLES: break
		var p = geo_to_screen(float(c.lat), float(c.lng))
		if p == null: continue
		if placed.any(func(q: Vector2): return q.distance_to(p) < BUBBLE_GAP): continue
		placed.append(p)
		add.call(P0Clusters.region(str(c.id)))
	_regions = out
	return out

## The lat/lng box the map shows, a fifth wider each way and at least a city's radius (0.5°) beyond the edges, so a
## city whose centre is just off screen is still the camera city (south, west, north, east); from the Web Mercator
## scale geo_to_screen draws with.
func _view_box(vp: Vector2, z: float) -> Vector4:
	var scale := vp.y / _map_logical_height() * 512.0 * pow(2.0, z)
	var half_w := minf(180.0, vp.x / scale * 360.0 * 0.6 + 0.5)
	var half_h := minf(85.0, vp.y / scale * 360.0 * 0.6 * cos(deg_to_rad(clampf(center_lat, -80.0, 80.0))) + 0.5)
	var west := wrapf(center_lng - half_w, -180.0, 180.0)
	var east := wrapf(center_lng + half_w, -180.0, 180.0)
	if half_w >= 180.0:
		west = -180.0
		east = 180.0
	return Vector4(maxf(-85.0, center_lat - half_h), west, minf(85.0, center_lat + half_h), east)

## Fewer cities the farther out: at the country zoom only the large ones get a bubble, near the city zoom (where the
## camera city switches, map_poc.AUTO_SWITCH_ZOOM) every cluster counts, so the title follows the camera anywhere.
static func city_min_population(z: float) -> int:
	if z < 3.0: return 3000000
	if z < 4.0: return 1000000
	if z < 5.0: return 400000
	if z < 6.0: return 150000
	if z < 7.0: return 50000
	return 0

# ---------------------------------------------------------------- old server / account hooks off
func _on_net_booted(_ok: bool) -> void: pass
func _on_net_booted_guest(_ok: bool) -> void: pass
func _on_account_changed(_signed_in: bool) -> void: pass
## P0 has no nearby list, but the region must count as set up: map_poc's resume rebuilds the region UI when
## _nearby_region differs, which flies the camera back to the homestead (int5 hand test 31: back from an outpost
## the map must stay where it was).
func _refresh_nearby() -> void: _nearby_region = str(region.get("id", ""))
func _refresh_city_counts() -> void: pass
func _open_account() -> void: pass

# ---------------------------------------------------------------- stacking
func resume() -> void:
	super.resume()
	rt.attach(self)
	_poll_presence.call_deferred()   # back from a room: refresh the outpost online counts
	_take_after_leave()

## What the world just left asked for (P0Runtime._leave_then), on resume or on a fresh map (_frame_home); true when
## it moves the camera or the player, so the opening view is not framed over it.
func _take_after_leave() -> bool:
	if rt == null: return false
	var next := rt.after_leave
	rt.after_leave = ""
	match next:
		"farm": _open_my_farm.call_deferred()      # FISH-4 Go home · Free
		"tackle": show_place.call_deferred("outpost:tackle")   # FISH-5 Tackle Shop: the camera goes to Old Kai's pin
		_:
			# Show on map (SGODOT-225): P0Runtime._leave_then("show:<target>") from Today, NeedSource, the Energy card.
			# Browse the map (show:map) and unknown targets point nowhere: a fresh map frames its opening view (亚瑟 on #96).
			if not next.begins_with("show:") or place_for(next.trim_prefix("show:")).is_empty(): return false
			show_place.call_deferred(next.trim_prefix("show:"))
	return true

## Show on map (SGODOT-225; LOCK-08, guidance only, nothing is entered): the camera flies to the target's pin and
## selects it — "outpost:<role>" an outpost, "pond:<id>" a catalog pond, "home" the homestead (fly only: its pin
## would offer Enter). "map" (Browse the map) and unknown targets leave the camera where the player left it.
func show_place(target: String) -> void:
	if city_map == null: return
	var entry := place_for(target)
	if entry.is_empty(): return
	# Flies since SGODOT-267 (_fly sets the city-wide pan bounds, else the homestead's 450 m box pulls the camera back);
	# the pin is selected on landing.
	_fly("show:" + target, float(entry.lat), float(entry.lng), SHOW_ZOOM, func(): if target != "home": city_map.select(entry))

## Show from a panel opened on the map (Today, the Energy card, a NeedSource): every target is a pin here; a homestead
## target (plots, stall, stove …) is the homestead's.
func p0_show_spot(where: String) -> void:
	show_place(P0Ui.map_target(where))

## The pin a Show on map target points at ({lat, lng} plus the city-map entry for outposts and ponds), or {}.
func place_for(target: String) -> Dictionary:
	if target == "home": return {"lat": home_lat, "lng": home_lng}
	if target.begins_with("outpost:"):
		var o := P0Outposts.by_role(target.trim_prefix("outpost:"))
		return {} if o.is_empty() else P0Outposts.place_entry(o, int(_online.get(str(o.id), 0)))
	if target.begins_with("pond:"): return P0Ponds.location(target.trim_prefix("pond:"))
	return {}

func p0_surface() -> String: return "map"

## Android Back on the map (李元芳 int10): P0's own layers first, one per press — a dragged or lifted slot flies back,
## then the radial, then a card, then a drawer (P0Ui.close_top_layer, LOCK-06) — and only with none left the map's own
## (its city card, relocation, a farm selection). #92 brought P0's HUD and Bag to the map without this, so Bag, Today,
## the Inbox and the place cards could not be closed with Back there.
func is_back_navigation_locked() -> bool:
	if rt != null and rt.ui.close_top_layer(): return true
	return super.is_back_navigation_locked()

## Map marks (plan §9.5.2, q(48)): ✓ deliverable, ! request, ◆ new, in priority order. One list badges the pins
## (CityMapView.set_marks: the first five on screen) and packs them first with whole labels (#83's _marker_of, through
## city_pin_markers), so a badge and its pin never disagree (亚瑟 on 234).
func p0_frame(view: Dictionary, _dt: float) -> void:
	if city_map == null: return
	_sync_here()
	# The recenter key gives way to an open sheet (不知火舞 on 234 A2: it showed under the card's ×).
	var key_shown := not rt.ui.has_modal()
	if city_map.recenter.visible != key_shown: city_map.recenter.visible = key_shown
	if city_map.home_key.visible != key_shown: city_map.home_key.visible = key_shown   # the home key with it
	var list := pin_marks(view)
	var home := home_mark(view)
	# Away, the homestead's ✓ hangs on its pin (deliverable, the highest mark, so first); at home on the avatar.
	if away() and home != "": list.push_front({"id": HOME_PIN, "state": home})
	var sig := JSON.stringify(list) + home
	if sig == _marks_sig: return
	_marks_sig = sig
	city_map.set_marks(list)
	if farm_markers: farm_markers.set_mark("self", CityMapView.status_badge(home) if home != "" and not away() else null)

const MARK_STATES := {"deliver": "deliverable", "request": "request", "new": "new"}

## The pins' marks [{id, state}]: the server's view.map_markers whenever it sends them (蒙恬, SGODOT-232 U6), else
## the ones the client knows before then (tutorial_marks). The homestead's goes on the farm pin (home_mark).
static func pin_marks(view: Dictionary) -> Array:
	return marks_from(view) if view.has("map_markers") else tutorial_marks(view)

## [{id, state}] from view.map_markers: place ids are the pins' ids (catalog pond ids, outpost ids); "home" is the
## homestead's farm pin, which FarmMarkers draws (home_mark).
static func marks_from(view: Dictionary) -> Array:
	var out: Array = []
	for m in view.get("map_markers", []):
		if not (m is Dictionary): continue
		var state := str(MARK_STATES.get(str(m.get("kind", "")), ""))
		var place := str(m.get("place", ""))
		if state != "" and place != "" and place != "home": out.append({"id": place, "state": state})
	return out

## Map markers the client knows before the server's map_markers come (蒙恬 on #83, q(48); the server's rule since
## q(103) ④, PinReason.fallback): once the tutorial Pond Catch is taken and while it is still short of its fish, the
## beginner pond Today points at wears the Request ! — at the city level beside the Tackle Shop, 200 m away
## (CityMapView packs marker pins first). Untaken it marks no pond: its ! is the stall's own. With the fish in the bag
## the ✓ goes on the homestead (home_mark). Read off the board like the guide (P0Guide.tutorial), not req_done: that
## keeps only the last 20.
static func tutorial_marks(view: Dictionary) -> Array:
	var out: Array = []
	for m in PinReason.fallback(view):
		if str(m.place) != HOME_PIN: out.append({"id": str(m.place), "state": str(MARK_STATES.get(str(m.kind), ""))})
	return out

## CityMapView asks once per update (#83): the same marks by pin id, the first (highest) mark per pin.
func city_pin_markers() -> Dictionary:
	var v: Dictionary = rt.session.view if rt != null and rt.session != null else {}   # every frame: no copy (_pond_info)
	var out := {}
	var list := pin_marks(v)
	if away() and home_mark(v) != "": list.push_front({"id": HOME_PIN, "state": home_mark(v)})
	for m in list:
		if not out.has(str(m.id)): out[str(m.id)] = str(m.state)
	return out

## The homestead's mark ("deliverable" when a Stall Board request can be handed in; 蒙恬's server only sends
## deliver for home, and the client's own first-session marks give it the taken Pond Catch's ✓, q(103)), drawn on the
## farm pin by FarmMarkers; "" for none.
static func home_mark(view: Dictionary) -> String:
	for m in PinReason.markers(view):
		if str(m.get("place", "")) == HOME_PIN: return str(MARK_STATES.get(str(m.get("kind", "")), ""))
	return ""

## Today's "Show on map" (SGODOT-232 U6): a short pulse on that place's pin.
func pulse_place(place: String) -> void:
	if city_map: city_map.pulse_pin(place)

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"farm": _open_my_farm()
		"pond": _on_city_pond_requested({"id": step[1]})
		"pondcard", "pondfish":   # the pond card as after tapping the pin; pondfish then opens Details ›
			var e := P0Ponds.location(step[1]).duplicate(true)
			e["kind"] = "pond"
			if city_map: city_map.select(e)
			if step[0] == "pondfish": _open_pond_fish(e)
		"shop":
			if city_map: city_map.select(P0Outposts.place_entry(P0Outposts.by_role(step[1] if step.size() > 1 else "tackle")))
		"listpick":   # as a tap on the place list: select the outpost and fly the camera to it
			var e := P0Outposts.place_entry(P0Outposts.by_role(step[1] if step.size() > 1 else "post"))
			if city_map:
				city_map.select(e)
				city_map.focus_requested.emit(e)
		"outpost": _open_outpost(step[1])
		"enter":
			if city_map: city_map._on_info_action()
		"zoom":
			_set_zoom(float(step[1]))
			_camera_dirty = true
		"online":   # online:sh_tea_1:3 — the presence count an outpost pin says, for shots
			_online[step[1]] = int(step[2])
			_set_outpost_places()
		"pin":   # pin:home / pin:sh_tea_1 — a tap on that pin (its card), the Homestead pin only while away
			var hit: Array = city_map.entries.filter(func(e): return str(e.get("id", "")) == step[1]) if city_map else []
			if not hit.is_empty(): city_map.select(hit[0])
		"tapself": _own_pin_pressed()   # a tap on the player's own avatar: the card of where the player is
		"recenter": _city_action("recenter")   # the MapLocateButton: back to the player, the zoom kept
		"homekey": _city_action("home")   # the home key over it: back to the homestead, selected (SGODOT-261)
		"maptouch":   # maptouch:180:300[:1.15] — a finger down and up on the map there, after that many seconds (steps
			# run 0.8 s apart: a delay lands it inside the next step's flight); it stops a flight (SGODOT-267)
			var at := Vector2(float(step[1]), float(step[2]))
			var tap := func():
				for down in [true, false]:
					var touch := InputEventScreenTouch.new()
					touch.position = at
					touch.pressed = down
					_unhandled_input(touch)
			if step.size() > 3: get_tree().create_timer(float(step[3])).timeout.connect(tap)
			else: tap.call()
		"center":   # center:31.228:121.478 (the city overview) — where the camera looks, for shots
			center_lat = float(step[1])
			center_lng = float(step[2])
			_camera_dirty = true
		_: return false
	return true
