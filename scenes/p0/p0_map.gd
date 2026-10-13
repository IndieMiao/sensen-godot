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
const MapFogLayer := preload("res://modules/map/map_fog_layer.gd")   # the fog's holes as the map draws the ground (SGODOT-298)
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
const P0CityPlaces := preload("res://modules/p0/p0_city_places.gd")   # other cities' places (SGODOT-280)
const P0ArrivalCard := preload("res://modules/p0/p0_arrival_card.gd")   # MAP-7-FREE, the first visit's three things
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

## Into the farm — every way home comes here: the Homestead card's Go home, the place chip, the home city's bubble, the
## avatar's own pin, a world's "farm" on the way back. From another city it flies home first (q(152) ①).
func _open_my_farm() -> void:
	if AppRouter.top_instance() != null or AppRouter._navigation_pending: return
	if city_map != null and rt != null and P0Travel.away(_view()) and not travelling():
		_fly_home()
		return
	_enter_farm()

func _enter_farm() -> void:
	_return_home()
	_clear_farm_selection()
	_reset_gesture()
	P0Runtime.nav_started()
	open_farm.call()

## How the farm opens (tests hold it to stay on the map).
var open_farm := func(): AppRouter.open_instance(P0_FARM, {})

## q(152) ① (不知火舞 on 299 9cbdf991): home from another city is the same 3 s flight as going out — up from where the
## camera is, along, down to the homestead's pin at the zoom its pin's card shows (SHOW_ZOOM) — the pill saying
## Homestead and how far. Nothing is sent before it lands (苏烈: the server moves `here` home with return_home or the
## farm's own read, so a flight cut short leaves the player where they are); on landing the chip says Homestead, then
## the farm opens as ever and Welcome home floats (q(108)): no stamp, no Energy, no card.
func _fly_home() -> void:
	var held := P0Travel.here(_view())
	var home := Vector2(home_lat, home_lng)
	var km := roundi(P0PlaceSheet.km_between(_origin(), home))
	var hr := P0Clusters.region(P0Clusters.cluster_of_region(P0_REGION))
	var bearing := float(CityMapData.city(str(hr.get("id", ""))).get("overview", {}).get("bearing", city_bearing)) if not hr.is_empty() else city_bearing
	if not hr.is_empty(): _switch_city(hr)
	if rt.ui.has_modal(): rt.ui.close_modal()   # no card stays over the flight (周瑜 on #341)
	_travel_fly({lat = home.x, lng = home.y, zoom = SHOW_ZOOM, bearing = bearing}, _origin(), held, "Homestead", km, func():
		# landed with another scene over the map (it was suspended) or another way out under way: not home yet — the
		# player is where they were, and goes home again from there (周瑜 on #341)
		if AppRouter.top_instance() != null or AppRouter._navigation_pending: return
		rt.ui.hold_here(P0Travel.home(_view()))   # Homestead from the landing; the server's here follows with return_home
		_enter_farm())

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
		city_map.bubble_state = city_bubble
		city_map.bubble_clear_rects = bubble_clear_rects   # no half bubble under the HUD, the keys or the bar (不知火舞 on 279)
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
		# the map's credit line keeps above the card open over it, and is not drawn under a page (q(133) v3)
		city_map.credits_floor = func() -> float: return rt.ui.modal_top() if rt != null else INF
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

## The pond card's info. It reads the received view as it is — the card needs no timers — never session.current(),
## which copies the whole view each call (int11 / int12 hand test: the map ran hot and slow with a few copies per pond
## pin per frame).
func _pond_info(entry: Dictionary) -> Dictionary:
	if rt == null or rt.session == null: return {}
	var km := P0PlaceSheet.km_between(_origin(), Vector2(float(entry.lat), float(entry.lng)))
	return PondCard.info(rt.session.view, str(entry.id), km)

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

## Details ›: the pond's fish list (P0PondCard.open_fish). ×, Back and a tap outside all go back to the pond card (P0Ui.
## back_modal, the layered way back of 亚瑟 on #37; 哪吒 on #95); from the card they close it.
func _open_pond_fish(entry: Dictionary) -> void:
	var info := _pond_info(entry)
	var back := [false]   # lambdas capture locals by value: share the flag through an array
	var id := str(entry.id)
	var holder := PondCard.open_fish(rt.ui, id, info, func():
		back[0] = true
		_open_pond_card(entry, info))
	holder.tree_exiting.connect(func():
		if not back[0] and city_map and str(city_map.selected.get("id", "")) == id: city_map.clear_selection())

func _prewarm_pond(id: String) -> void:
	var pond := P0Ponds.location(id)
	if not pond.is_empty(): WaterShore.prewarm(id, SystemPonds.site(pond))

func _set_outpost_places() -> void:
	var places: Array = P0Outposts.all().map(func(o): return P0Outposts.place_entry(o, int(_online.get(str(o.id), 0))))
	for cluster in _shown_cities:   # other cities' outposts (SGODOT-280), once their places are in
		for o in P0CityPlaces.city(cluster).get("outposts", []):
			var e := P0Outposts.place_entry(o, int(_online.get(str(o.id), 0)))
			e["cluster"] = cluster
			places.append(e)
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
var _styles_explored := ""   # home and the count of cities visited the styles were made for: a city explored drops its silhouettes

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
	# cheap per pin per frame: visits only grow, so their count and the home say when the explored list changed
	var t: Dictionary = _view().get("travel", {})
	var explored := "%s|%d" % [str(t.get("home", "")), (t.get("visits", {}) as Dictionary).size()]
	if explored != _styles_explored:
		_styles_explored = explored
		_dest_styles.clear()
	if not _dest_styles.has(key): _dest_styles[key] = _destination_style_of(entry)
	return _dest_styles[key]

func _destination_style_of(entry: Dictionary) -> Dictionary:
	var style := {}
	var name := str(entry.get("name", ""))
	match str(entry.get("kind", "")):
		"pond":
			var beginner := str(entry.get("id", "")) == NEAREST_POND or bool(entry.get("beginner", false))
			style = {"icon": P0Logic.icon("pond"), "label": short_name(name), "rank": PIN_RANK.beginner if beginner else PIN_RANK.pond}
		"place":
			# The homestead keeps its plate and its whole name (q(137) leaves it as it was), first after the always-in pins.
			if str(entry.get("id", "")) == HOME_PIN: return {"icon": P0Logic.icon("home"), "plate": true, "label": "Homestead",
				"rank": PIN_RANK.beginner}
			var o := P0Outposts.find(str(entry.get("id", "")))
			if not o.is_empty():
				var role := str(o.role)
				# A tackle shop has no name on the map: it is always its pond's (q(137) ②)
				style = {"icon": P0Logic.icon(str(PIN_ICONS.get(role, "travel"))), "label": "" if role == "tackle" else short_name(name),
					"rank": int(PIN_RANK.get(role, PIN_RANK.post))}
	# A place of a city the fog covers (MAP-2 2107:32861, 不知火舞 on #281): its silhouette until the city is explored
	if not style.is_empty() and P0Travel.fog(_view(), cluster_of_entry(entry, P0Travel.home(_view()))) == "unexplored":
		style["silhouette"] = true
		style["label"] = ""
		style["rank"] = PIN_RANK.silhouette
	return style

## q(137) ⑤: the fixed packing order of the map's pins after the always-in ones (the selected, a marked one, where the
## player is): beginner pond, other ponds, market, tea house, travel post and cabin, tackle shop, silhouette.
const PIN_RANK := {"beginner": 1, "pond": 2, "market": 3, "tea": 4, "post": 5, "tackle": 6, "silhouette": 7}
## The type words a place's name ends with (q(137) ①): the generator's (server world.ts, Pond / Creek / Cove) and the
## hand-written ones. Longest first, so `Trading Post` is not read as `Post`.
const TYPE_WORDS := ["Market Square", "Tackle Shop", "Trading Post", "Travel Post", "Tea House", "Creek", "Pond", "Cove"]

## The map pin's short name (q(137) ①): the place's own word without its type — `Willow Pond` → `Willow`, `Maple Market
## Square` → `Maple`, `Union Square Travel Post` → `Union Square`. A name that is only a type word stays whole.
static func short_name(name: String) -> String:
	for w in TYPE_WORDS:
		if name.ends_with(" " + w): return name.substr(0, name.length() - w.length() - 1).strip_edges()
	return name

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
	if rt == null or city_map == null or travelling(): return   # the avatar stays in the city left until it lands
	var at := _origin()
	var sig := "%s|%s|%s|%.7f|%.7f" % [rt.here.get("space", ""), rt.here.get("place", ""), P0Travel.here(_view()), home_lat, home_lng]
	if sig == _here_sig: return
	_here_sig = sig
	set_self_at(at.x, at.y)
	if farm_markers:
		farm_markers.self_label_off = away()   # the avatar is not the homestead's mark there
		if away(): farm_markers.anchor_shift["self"] = AVATAR_BESIDE
		else: farm_markers.anchor_shift.erase("self")
	# Also how the pins learn where the player is (their packing keeps that pin in, kept_pin), and the city view lays its
	# pins out again only when their entries are replaced (SGODOT-260, CityMapView._layout_wanted).
	_set_outpost_places()
	_marks_sig = ""   # the homestead's mark moves between the avatar and its pin

## The place card spec (q(80), P0PlaceSheet): an outpost — its name, data category, Distance, Online now (no row at
## 0), Go; the homestead — Homestead, Your farm, Distance, Go home. At the place the player is at: no Distance,
## Back to <name>. {} for a place P0 does not know.
func place_card(entry: Dictionary) -> Dictionary:
	var id := str(entry.get("id", ""))
	var to := Vector2(float(entry.get("lat", 0.0)), float(entry.get("lng", 0.0)))
	var distance := ["Distance", P0PlaceSheet.distance_text(P0PlaceSheet.km_between(_origin(), to))]
	if id == HOME_PIN:
		return P0PlaceSheet.for_here({"title": "Homestead", "subtitle": "Your farm", "reason": PinReason.reason(_view(), id),
			"facts": [distance], "primary": "Go home"}, not away())   # a 0-Energy action is the verb alone (q(122))
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
## landing, selects it, as a tap on its pin does away (its card: Homestead · Go home) and on the avatar at home.
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

## Where a city bubble must not sit (screen px): the two HUD rows, the right-hand keys (home, recenter) and the quick
## bar / Bag row. A bubble overlapping one is not drawn (its dot stays).
func bubble_clear_rects() -> Array:
	if rt == null: return []
	var vp := get_viewport().get_visible_rect().size
	var top := rt.ui.safe_top() + UiTokens.SIZE_HUD_TOP + UiTokens.SIZE_HUD_H
	var bar := vp.y - rt.ui.safe_bottom() - UiTokens.SIZE_QUICK_BAR_BOTTOM - UiTokens.SIZE_QUICK_BAR_H
	var out: Array = [Rect2(0, 0, vp.x, top), Rect2(0, bar, vp.x, vp.y - bar)]
	for key in [city_map.recenter, city_map.home_key] if city_map else []:
		if key and (key as Control).is_visible_in_tree(): out.append((key as Control).get_global_rect())
	return out

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
	if travelling():   # left mid-flight: nothing more to show here, but the chip and Energy must not stay held
		_trip = {}
		_show_self(true)
		if rt != null: rt.release_travel()
	super._exit_tree()

# ---------------------------------------------------------------- travel (SGODOT-275, §11.8; the free first version)
## The travel card (MAP-5 in the place-sheet layout until its frame comes): the city, how far and which Trip, what it
## costs (nothing in the first version: Free), whether it is a first visit, and that going home is always free. Fly
## sends `travel`; the server's arrival event flies the camera there (on_arrival). From a city bubble, and from a
## pond / outpost of that city refused with pass_required / trip_expired (the server's preview then names it).
## MAP-3-FREE (§11.8.3, Figma 482:403): an unexplored city's silhouette card — climate, trip, local time, and its ponds,
## outposts and residents from the server (GET /p0/city/:cluster: the counts and the local time come with its preview).
## Travel details › opens the free travel card (Fly); Keep browsing closes it. A visited city goes straight to its
## travel card. While the city's places are on their way the card opens on what the client knows and fills in.
func open_city_card(cluster: String) -> void:
	var c := P0Clusters.get_cluster(cluster)
	if c.is_empty() or rt == null: return
	_mark_opened(cluster)   # a pin's city too (_travel_first)
	if P0Travel.fog(_view(), cluster) != "unexplored":
		open_travel(cluster)
		return
	P0CityPlaces.fetch(rt.session, cluster, func(_city):
		if rt.ui.modal_kind == "city_card" and _card_city == cluster: _refresh_city_card(cluster))
	_card_city = cluster
	_fill_city_card(cluster)

var _card_city := ""
var _city_card: Control   # the silhouette card open now (its holder)

func _fill_city_card(cluster: String) -> void:
	if rt.ui.modal_kind == "city_card": rt.ui.close_modal()
	# Travel details' action rides in the spec: looked up by name, the card closed for the refill was still in the tree
	# this frame and took it, so the first card's link did nothing (李元芳, 279 fd340f21).
	var spec := city_card(_view(), cluster, P0CityPlaces.city(cluster))
	spec["links"] = [["Travel details", func():
		rt.ui.close_modal()
		open_travel(cluster, P0CityPlaces.city(cluster).get("preview", {}))]]
	_city_card = P0ArrivalCard.open(rt.ui, spec, func(): pass, "city_card")

## The city's read came in while its card is open: its local time and counts fill in where they are. The card is not
## closed and opened again, so a tap on it in that moment (Travel details, the first time: the read takes a while on a
## phone) still lands (李元芳 0.2.1 smoke, 286 bfae88c7).
func _refresh_city_card(cluster: String) -> void:
	if _city_card == null or not is_instance_valid(_city_card) or _city_card.is_queued_for_deletion():
		_fill_city_card(cluster)
		return
	var spec := city_card(_view(), cluster, P0CityPlaces.city(cluster))
	var facts: Array = _city_card.find_children("*", "UiFactRow", true, false)
	for i in mini(facts.size(), (spec.facts as Array).size()): (facts[i] as UiFactRow).value = str(spec.facts[i][1])
	var rows: Array = _city_card.find_children("*", "UiItemRow", true, false)
	for i in mini(rows.size(), (spec.rows as Array).size()):
		(rows[i] as UiItemRow).quantity = str(spec.rows[i].quantity)
		(rows[i] as UiItemRow).quantity_label = str(spec.rows[i].unit)

## "Trip 6 · Intercontinental": a city's trip tier, the server's (its preview) when it is in, else the client's.
static func trip_state(view: Dictionary, cluster: String, city: Dictionary) -> String:
	var pv: Dictionary = city.get("preview", {}) if city.get("preview") is Dictionary else {}
	var trip := P0Travel.trip(view, cluster)
	if pv.has("trip"): trip = {trip = int(pv.trip), name = str(pv.get("trip_name", trip.get("name", "")))}
	return "Trip %d · %s" % [int(trip.get("trip", 1)), str(trip.get("name", ""))]

## The silhouette card's spec (pure, tested): `city` = P0CityPlaces.city (its preview carries the server's counts and UTC
## offset), {} before it is in. Counts and local time stay "–" until then.
static func city_card(view: Dictionary, cluster: String, city: Dictionary) -> Dictionary:
	var c := P0Clusters.get_cluster(cluster)
	var pv: Dictionary = city.get("preview", {}) if city.get("preview") is Dictionary else {}
	var trip := P0Travel.trip(view, cluster)
	if pv.has("trip"): trip = {km = int(pv.get("km", trip.get("km", 0))), trip = int(pv.trip), name = str(pv.get("trip_name", trip.get("name", "")))}
	var counts: Dictionary = pv.get("counts", {})
	var count := func(key: String) -> String: return str(int(counts[key])) if counts.has(key) else "–"
	var offset = pv.get("utc_offset_min", null)
	var local := "–"
	if offset != null:
		var t := Time.get_datetime_dict_from_unix_time(int(P0Travel.now_ms(view) / 1000.0) + int(offset) * 60)
		local = "%02d:%02d" % [int(t.hour), int(t.minute)]
	return {
		"title": str(c.get("name", "")), "state": "Unexplored", "effect": "Preview the city before travelling.",
		"facts": [["Climate", str(c.get("climate", "")).capitalize()], ["Trip", "%d · %s" % [int(trip.get("trip", 1)), str(trip.get("name", ""))]],
			["Local time", local]],
		"rows": [
			{"icon": P0Logic.icon("pond"), "title": "Ponds", "effect": "Basic and regional fishing", "quantity": count.call("ponds"), "unit": "ponds"},
			{"icon": P0Logic.icon("home"), "title": "Outposts", "effect": "Local shops and requests", "quantity": count.call("outposts"), "unit": "outposts"},
			{"icon": P0Logic.icon("face_player"), "title": "Residents", "effect": "People to meet", "quantity": count.call("residents"), "unit": "residents"},
		],
		"links": [["Travel details", func(): pass]],
		"primary": "", "dismiss": "Keep browsing",
	}

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
		_here_before = P0Travel.here(_view())
		rt.session.send({"type": "travel", "to": cluster}), Callable(), Callable(), "travel_card")

var _origin_before := Vector2.ZERO   # where the player stood when Fly was pressed: the flight frames it with the city ahead
var _here_before := ""   # the city they stood in then: the place chip keeps it until the flight lands (q(147) ⑤)

## The server's arrival (events {kind: "arrival"}): the camera flies to the city's overview and lands with the welcome
## (q(108): a first visit is stamped, its +10 Energy floats as Energy does; a return only floats Welcome back). The
## flight is q(147)'s fixed 3 s (SGODOT-299): up from where the camera is — no jump back to the city left first — until
## the city left and the one ahead are both in view, along, down to the overview; a cover takes every touch meanwhile,
## a tap after its first 0.5 s or Back lands it. The place chip and the avatar keep the city left until it lands.
func on_arrival(ev: Dictionary) -> void:
	var cluster := str(ev.get("cluster", ""))
	var c := P0Clusters.get_cluster(cluster)
	if c.is_empty():
		if rt != null: rt.release_travel()   # no flight: nothing held waits for one
		return
	var r := P0Clusters.region(cluster)
	var overview: Dictionary = CityMapData.city(str(r.get("id", ""))).get("overview", {})
	var left := _origin_before if _origin_before != Vector2.ZERO else Vector2(center_lat, center_lng)
	_origin_before = Vector2.ZERO   # one arrival per Fly: a later arrival (another device) starts from where it lands
	var held := _here_before
	_here_before = ""
	var first := bool(ev.get("first", false))
	var welcome := ("Welcome to %s · Stamp collected" % str(c.name)) if first else "Welcome back"
	_switch_city(r)
	_load_city_places(cluster)   # its ponds and outposts, read while the camera flies
	_travel_fly({lat = float(overview.get("lat", c.lat)), lng = float(overview.get("lng", c.lng)),
		zoom = float(overview.get("zoom", 11.0)), bearing = float(overview.get("bearing", 0.0))}, left, held, str(c.name),
		int(ev.get("km", 0)), func():
			# §11.8.4 steps 5 then 7 (q(152) ②): a first visit's stamp says itself for 1.5 s with its +10 Energy, then
			# goes, and only then the card slides up, so the toast never lies over it; a return only floats Welcome back.
			if not first:
				rt.ui.toast(welcome)
				return
			rt.ui.toast(welcome, STAMP_S)
			_arrival_card_after_stamp(cluster))
	# q(147) ⑤ "it changes on landing": a first visit's city still reads Unexplored, its bubble and its fog hole, until
	# the flight lands, with the chip and the stamp (不知火舞 on #340)
	if first and travelling(): _trip.first_in_air = cluster

## The stamp's beat of the arrival (§11.8.4 ≤ 1.5 s, q(152) ②): its toast's time, after which the arrival card comes.
const STAMP_S := 1.5
var _card_token := 0

## The first visit's card once the stamp has said itself — unless the map is gone, another flight is in the air, or
## another arrival has come meanwhile (each waits for its own stamp).
func _arrival_card_after_stamp(cluster: String) -> void:
	_card_token += 1
	var token := _card_token
	get_tree().create_timer(STAMP_S).timeout.connect(func():
		if is_inside_tree() and token == _card_token and not travelling(): open_arrival_card(cluster))

## The cross-city flight under way (q(147)): its plan, how far it is, the cover, what landing does, the city left.
var _trip := {}

## to: the overview ahead ({lat, lng, zoom, bearing}, kept in f64 so it lands exactly there).
func _travel_fly(to: Dictionary, left: Vector2, held: String, city: String, km: int, land: Callable) -> void:
	if not _trip.is_empty(): _travel_land()   # one at a time: an earlier one lands first
	_reset_gesture()
	_city_bounds()
	if _flight != null: _flight.kill()
	var vp := get_viewport().get_visible_rect().size
	var view := Vector2(vp.x * _map_logical_height() / maxf(1.0, vp.y), _map_logical_height())
	var cover := P0TravelCover.new()
	add_child(cover)
	if city_map: cover.adopt_route(city_map)   # the route under the pins and city bubbles, over the fog (q(152) ④)
	var top := 120.0
	if rt != null and rt.ui.open_marker_area().has_area(): top = rt.ui.open_marker_area().position.y + 8.0
	cover.open(city, km, top)
	# q(152) ③: both ends in the safe area at the top — 32 in from each side, from the pill's bottom to the Bag key's top
	# (the bottom of the area markers may use), in the map's logical units
	var safe := Rect2()
	if rt != null and rt.ui.open_marker_area().has_area():
		var k := _map_logical_height() / maxf(1.0, vp.y)
		var pill_bottom := top + cover.pill.get_combined_minimum_size().y
		safe = Rect2(Vector2(SAFE_SIDE, pill_bottom) * k, Vector2(vp.x - SAFE_SIDE * 2.0, rt.ui.open_marker_area().end.y - pill_bottom) * k)
	var plan := P0TravelFlight.plan(center_lat, center_lng, zoom + _zoom_elastic, city_bearing, left, float(to.lat),
		float(to.lng), float(to.zoom), float(to.bearing), view, safe)
	_zoom_elastic = 0.0
	cover.skip_requested.connect(_skip_travel)
	if rt != null and held != "": rt.ui.hold_here(held)
	_focus_tween = create_tween()
	_focus_tween.tween_method(_travel_at, 0.0, P0TravelFlight.TOTAL_S, P0TravelFlight.TOTAL_S)
	_focus_tween.tween_callback(_travel_land)
	_trip = {plan = plan, to = to, t = 0.0, cover = cover, land = land, tween = _focus_tween, left = left,
		start_us = Time.get_ticks_usec()}
	_show_self(false)   # the avatar leaves with the take-off (v2)
	_flight = _focus_tween
	_flight_kind = "travel"

## The tween only calls this each frame: where the flight is comes from the clock, so it takes 3 s of real time even
## when frames are slow — the engine caps a frame's step (about 0.13 s), and a tween stepped by it stretched the flight
## on a slow device (李元芳 on 279 45546042: 4.9 s on the emulator; 9.5 s at 400 ms a frame). It lands on time.
## Recording frames (P0_SHOT_FRAMES, a fixed frame rate) the clock runs faster than the frames saved, so a video takes
## the tween's own time there, frame for frame (不知火舞 on 299: it cut before landing).
func _travel_at(step: float) -> void:
	if _trip.is_empty(): return
	var clock := (Time.get_ticks_usec() - int(_trip.start_us)) / 1e6
	var t := minf(step if OS.has_environment("P0_SHOT_FRAMES") else clock, P0TravelFlight.TOTAL_S)
	if t >= P0TravelFlight.TOTAL_S:
		_travel_land()
		return
	_trip.t = t
	var at: Vector4 = (_trip.plan as P0TravelFlight).sample(t)
	center_lat = at.x
	center_lng = at.y
	city_bearing = at.w
	_set_zoom(at.z)
	_camera_dirty = true
	if not is_instance_valid(_trip.cover): return
	var cover := _trip.cover as P0TravelCover
	cover.show_progress(t)
	# the route and its plane between the two cities, where the map draws them now (§11.8 / MAP-7, v2)
	var from = geo_to_screen(float(_trip.left.x), float(_trip.left.y))
	var to = geo_to_screen(float(_trip.to.lat), float(_trip.to.lng))
	cover.show_route(from if from != null else Vector2.INF, to if to != null else Vector2.INF, t)

func _show_self(on: bool) -> void:
	hide_self = not on
	if farm_markers: farm_markers.visible = on

## The flight's safe area's side margin (q(152) ③), UI px.
const SAFE_SIDE := 32.0

## In the air the map may go out past the city map's floor (z 2) to fit a long trip's two ends (q(152) ③, z 0.8).
func _minimum_zoom() -> float:
	var floor_z := super._minimum_zoom()
	return minf(P0TravelFlight.TOP_MIN_ZOOM, floor_z) if travelling() else floor_z

## Whether a cross-city flight is under way (the cover is up).
func travelling() -> bool:
	return not _trip.is_empty()

## A flight whose tween anything else stopped (MapPoc's gesture reset, another flight) lands at once: the cover never
## outlives its flight (asked each frame).
func _travel_watch() -> void:
	if _trip.is_empty(): return
	var tween = _trip.get("tween")
	if not (tween is Tween) or not (tween as Tween).is_valid() or not (tween as Tween).is_running(): _travel_land()

## Sent to the background or losing focus mid-flight: it lands (the gesture reset would stop it anyway).
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and travelling(): _travel_land()

## Covered by another scene mid-flight: it lands first.
func suspend() -> void:
	if travelling(): _travel_land()
	super.suspend()

## A tap on the cover after its first 0.5 s, or Back: straight down to the city's overview, then as on landing.
func _skip_travel() -> void:
	if _trip.is_empty() or float(_trip.t) < P0TravelFlight.UP_S: return
	_travel_land()

## Down: the camera at the overview, the cover gone, the chip and the avatar in the new city, then the welcome. Also
## how every other way out ends a flight (skipped, the map suspended or left, the app sent to the background, the
## tween stopped by anything else), so the cover never stays up.
func _travel_land() -> void:
	if _trip.is_empty(): return
	var trip := _trip
	_trip = {}
	if _focus_tween != null and _focus_tween.is_valid(): _focus_tween.kill()
	var to: Dictionary = trip.to
	center_lat = float(to.lat)
	center_lng = float(to.lng)
	city_bearing = float(to.bearing)
	_set_zoom(float(to.zoom))
	_camera_dirty = true
	if is_instance_valid(trip.cover):   # off at once: the map takes touches again this frame
		var cover := trip.cover as Node
		if cover.get_parent() != null: cover.get_parent().remove_child(cover)
		cover.queue_free()
	if rt != null: rt.release_travel()   # the chip and Energy follow the view, the held +10 floats, with the welcome
	_here_sig = ""
	_sync_here()
	_sync_farm_markers()   # where it stands now, laid out before it shows: no frame of it at the city left (不知火舞 on 299)
	_show_self(true)   # the avatar stands in the city ahead, as the chip changes
	if (trip.land as Callable).is_valid() and is_inside_tree(): (trip.land as Callable).call()

## MAP-7-FREE (§11.8.4 step 7, Figma 482:412): a first visit lands on "3 things to do here" — the local pond, an
## outpost and the new stamp. Show local pond only moves the camera to the beginner pond's pin (LOCK-08, the player taps
## Go); Visit the outpost goes into the city's market square (an outpost room, its pass just issued). Waits for the
## city's places when they are still on their way.
func open_arrival_card(cluster: String) -> void:
	if rt == null: return
	if not P0CityPlaces.has_city(cluster):
		P0CityPlaces.fetch(rt.session, cluster, func(_c): open_arrival_card(cluster))
		return
	var c := P0Clusters.get_cluster(cluster)
	var pond := P0CityPlaces.beginner_pond(cluster)
	# the market square nearest to where the player stands (the city's overview on landing; 不知火舞 on #248)
	var outpost := P0CityPlaces.nearest_outpost(cluster, Vector2(center_lat, center_lng))
	var climate := str(c.get("climate", "")).capitalize()   # the table's "temperate" → "Temperate" (§11.9.3 bands)
	var spec := {
		# the trip tier as the silhouette card writes it, never "Nearby" for a city across the ocean (司空震 286 16ffaf67)
		"title": str(c.get("name", "")), "state": trip_state(_view(), cluster, P0CityPlaces.city(cluster)),
		"effect": "Choose your first local activity.",
		"rows": [
			{"icon": P0Logic.icon("pond"), "title": "Local pond", "effect": "Pond Crucian for every level"},
			{"icon": P0Logic.icon("home"), "title": "Outpost", "effect": ("%s seeds and local requests" % climate) if climate != "" else "Local requests"},
			{"icon": P0Logic.icon("passport"), "title": "%s stamp" % str(c.get("name", "")), "state": "New", "effect": "View it in your Passport"},
		],
		"links": [] if pond.is_empty() else [["Show local pond", func():
			rt.ui.close_modal()
			_show_generated(pond.merged({"kind": "pond"}))]],
		"primary": "Visit the outpost" if not outpost.is_empty() else "",
	}
	P0ArrivalCard.open(rt.ui, spec, func():
		rt.ui.close_modal()
		if not outpost.is_empty(): _open_outpost(str(outpost.id)))

## The camera flies to another city's pin and selects it (Show, LOCK-08: nothing is entered).
func _show_generated(entry: Dictionary) -> void:
	_fly("show:" + str(entry.get("id", "")), float(entry.lat), float(entry.lng), SHOW_ZOOM, func(): city_map.select(entry))

## A city bubble's line (不知火舞 on #227): the home city its players online with a house; an explored city Visited;
## the rest Unexplored. Second Home is not shown in this version (it comes with the paid second version).
func city_bubble(region_id: String) -> Dictionary:
	var tier := int(_bubble_tiers.get(region_id, BUBBLE_OTHER))
	var out := _city_bubble_face(region_id)
	out["dot_stays"] = tier <= BUBBLE_VISITED   # q(153) ①
	out["keeps"] = tier <= BUBBLE_HOME   # q(153) ②: never gives way
	return out

func _city_bubble_face(region_id: String) -> Dictionary:
	var cluster := P0Clusters.cluster_of_region(region_id)
	if cluster == P0Travel.home(_view()):
		var online := 0
		for n in _online.values(): online += int(n)
		# nobody online: the house alone, like an outpost pin's bare name (q(72): 0 tells nothing, only looks empty)
		return {text = "%d online" % online if online > 0 else "", icon = "house"}
	if cluster == _first_in_air(): return {text = "Unexplored"}   # changes on landing (q(147) ⑤)
	return {text = "Unexplored" if P0Travel.fog(_view(), cluster) == "unexplored" else "Visited"}

## The city a first visit is flying to, still unexplored to the eye until it lands; "" otherwise.
func _first_in_air() -> String:
	return str(_trip.get("first_in_air", "")) if travelling() else ""

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
	open_city_card(cluster)   # unexplored: the silhouette card first (MAP-3-FREE); visited: its travel card
	return true

## The fog's holes (§11.7.3): one round every explored city near the screen, a little wider than its radius on the
## ground, in the city view's pixels; the farthest at most MapFogLayer.MAX_HOLES. Asked each frame; projection only, no
## list work. Rebuilt only when the camera or the explored list changes, so a still map costs nothing (SGODOT-260).
var _fog_key := ""
var _fog_holes: Array = []

func fog_holes() -> Array:
	if city_map == null: return []
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(360, 800)
	var explored := P0Travel.explored(_view())
	if _first_in_air() != "": explored = explored.filter(func(c): return c != _first_in_air())   # its hole opens on landing
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
		var hole := _ground_hole(float(c.lat), float(c.lng), km, at)
		if hole.is_empty(): hole = {at = at, r = r}   # its ground off the camera (up close): the flat circle covers
		if not Rect2(Vector2.ZERO, vp).grow(float(hole.r) + 2.0).has_point(at): continue   # only holes that reach the screen
		out.append(hole)
		if out.size() >= 64: break
	_fog_holes = out
	return out

## A city's hole as the map draws its ground (SGODOT-298: from z 8 the map tilts and a circle of the flat scale missed
## it): four points half its radius out, then the rim at its radius, east / north / west / south, in km on the ground.
## {} when one of them is behind the camera.
func _ground_hole(lat: float, lng: float, km: float, at: Vector2) -> Dictionary:
	var ground: Array = []
	var screen: Array = []
	var rim: Array = []
	for reach in [0.5, 1.0]:
		for dir in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
			var g: Vector2 = dir * km * reach
			var q = geo_to_screen(lat + g.y / 111.32, lng + g.x / (111.32 * maxf(0.05, cos(deg_to_rad(lat)))))
			if q == null: return {}
			var v: Vector2 = (q as Vector2) - city_map.global_position - at
			if reach < 1.0:
				ground.append(Vector2(g.x, -g.y))   # the screen's y runs south
				screen.append(v)
			else: rim.append(v)
	return MapFogLayer.ground_hole(at, ground, screen, km, rim)

## Going home from another city (q(108)): free and instant — `return_home`, then the farm as ever. Welcome home
## floats; no stamp, no Energy. At home it does nothing.
func _return_home() -> void:
	if rt == null or not P0Travel.away(_view()): return
	rt.session.send({"type": "return_home"})
	rt.toast_on_arrival("Welcome home")   # after the farm's loading cover when Go home opens it (司空震 on 286)

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
	_load_city_places(P0Clusters.cluster_of_region(str(r.get("id", ""))))

## Another city's ponds and outposts (SGODOT-280, the server's generator): read once per city when the camera city
## becomes it (or the player arrives there), then pinned like the home city's. A pin of a city without a pass still
## opens its travel card (_travel_first). The home city keeps its hand-written pins.
var _shown_cities: Array = []
const SHOWN_CITIES := 6   # the cities whose pins stay on the map, the latest last

func _load_city_places(cluster: String) -> void:
	if cluster == "" or rt == null or cluster == P0Travel.home(_view()): return
	P0CityPlaces.fetch(rt.session, cluster, _show_city_places.bind(cluster))

func _show_city_places(_city: Dictionary, cluster: String) -> void:
	if not city_map or _shown_cities.has(cluster): return
	_shown_cities.append(cluster)
	if _shown_cities.size() > SHOWN_CITIES: _shown_cities.pop_front()
	city_map.preload_ponds(P0CityPlaces.city(cluster).get("ponds", []))
	_set_outpost_places()

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
	_mark_opened(cluster)
	if cluster == "" or cluster == P0Travel.here(_view()) or rt == null: return
	# Home is never a trip (q(108)): from another city the home city's bubble goes home, as the homestead's Go home —
	# flying there first (q(152) ①).
	if cluster == P0Travel.home(_view()): _open_my_farm()
	else: open_city_card(cluster)

## At most this many city bubbles, at least this far apart on screen (px), most populous first — the visited on screen
## besides, whatever their number (q(153) ①: their dots always show).
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
	var here := P0Travel.here(_view())
	var key := "%.1f|%d|%d|%s|%dx%d|%d|%s|%s" % [z, roundi(center_lat / step), roundi(center_lng / step), str(region.get("id", "")), vp.x, vp.y,
		P0Travel.explored(_view()).hash(), _opened_city, here]
	if key == _regions_key: return _regions
	_regions_key = key
	var out: Array = []
	var ids := {}
	var placed: Array = []
	_bubble_tiers.clear()
	var at_screen := func(cluster: String) -> Variant:   # the city's point in this view, null when off it
		var c := P0Clusters.get_cluster(cluster)
		if c.is_empty(): return null
		var p = geo_to_screen(float(c.lat), float(c.lng))
		if p == null or not Rect2(Vector2.ZERO, vp).grow(60).has_point((p as Vector2) - (city_map.global_position if city_map else Vector2.ZERO)): return null
		return p
	var add := func(r: Dictionary, tier: int, at = null) -> void:
		if r.is_empty() or ids.has(str(r.id)): return
		ids[str(r.id)] = true
		out.append(r)
		_bubble_tiers[str(r.id)] = tier
		var p = at if at != null else at_screen.call(P0Clusters.cluster_of_region(str(r.id)))
		if p != null: placed.append(p)   # the rest keep 72 px clear of it
	# q(153): by priority — the city just opened, where the player is, home, the visited (most populous first), then the
	# rest; the bubbles draw and give way in this order (CityMapView._yield_bubbles)
	if not _asked.is_empty(): add.call(_asked, BUBBLE_OPENED)
	if _opened_city != "": add.call(P0Clusters.region(_opened_city), BUBBLE_OPENED)
	if here != "": add.call(P0Clusters.region(here), BUBBLE_HERE)
	add.call(P0Clusters.region(P0Clusters.cluster_of_region(P0_REGION)), BUBBLE_HOME)
	# Visited cities at any zoom, whatever their size (不知火舞 on #216): the player's own map of where they have been —
	# their dots always, their bubbles as they fit (q(153))
	var visited: Array = P0Travel.explored(_view()).filter(func(cl): return at_screen.call(cl) != null)
	visited.sort_custom(func(a, b):
		var pa := int(P0Clusters.get_cluster(a).get("population", 0))
		var pb := int(P0Clusters.get_cluster(b).get("population", 0))
		return pa > pb if pa != pb else str(a) < str(b))
	for cluster in visited:   # every one on screen: their dots always stay (周瑜 on #346), the cap is for the rest
		add.call(P0Clusters.region(cluster), BUBBLE_VISITED)
	if not region.is_empty(): add.call(region, BUBBLE_OTHER)   # the camera's city
	var box := _view_box(vp, z)
	for c in P0Clusters.in_box(box.x, box.y, box.z, box.w, city_min_population(z), 200):
		if out.size() >= CITY_BUBBLES: break
		var p = geo_to_screen(float(c.lat), float(c.lng))
		if p == null: continue
		if placed.any(func(q: Vector2): return q.distance_to(p) < BUBBLE_GAP): continue   # clear of every city above too
		add.call(P0Clusters.region(str(c.id)), BUBBLE_OTHER, p)
	_regions = out
	return out

## q(153)'s tiers, highest first: the city just opened, where the player is, home — their bubbles never give way — then
## the visited — their dots always stay, their bubbles give way to higher ones — then the rest, which give way entirely.
enum { BUBBLE_OPENED, BUBBLE_HERE, BUBBLE_HOME, BUBBLE_VISITED, BUBBLE_OTHER }
var _bubble_tiers := {}
## The city whose card a bubble or a pin last opened (q(153): its bubble first).
var _opened_city := ""

func _mark_opened(cluster: String) -> void:
	if cluster == _opened_city: return
	_opened_city = cluster
	_regions_key = ""

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
	if next.begins_with("travel:"):   # a room that refused the player (no pass, SGODOT-280): that city's travel card
		open_travel.call_deferred(next.trim_prefix("travel:"))
		return true
	if next.begins_with("go:pond:"):   # Go on the Bite Board's pond card (SGODOT-283): into that pond, as this map's card
		var pond := P0Ponds.location(next.trim_prefix("go:pond:"))
		if pond.is_empty(): return false
		_on_city_pond_requested.call_deferred(pond)
		return true
	match next:
		"farm": _open_my_farm.call_deferred()      # FISH-4 Go home
		"tackle": show_place.call_deferred("outpost:tackle")   # FISH-5 Tackle Shop: the camera goes to Old Kai's pin
		_:
			# Show on map (SGODOT-225): P0Runtime._leave_then("show:<target>") from Today, NeedSource, the Energy card.
			# Browse the map (show:map) and unknown targets point nowhere: a fresh map frames its opening view (亚瑟 on #96).
			if not next.begins_with("show:"): return false
			var target := next.trim_prefix("show:")
			# another city's place not read yet: show_place reads it first (its pin is not known before)
			if place_for(target).is_empty() and P0CityPlaces.cluster_of(target.trim_prefix("outpost:").trim_prefix("pond:")) == "": return false
			show_place.call_deferred(target)
	return true

## Show on map (SGODOT-225; LOCK-08, guidance only, nothing is entered): the camera flies to the target's pin and
## selects it — "outpost:<role>" an outpost, "pond:<id>" a catalog pond, "home" the homestead (fly only: its pin
## would offer Enter). "map" (Browse the map) and unknown targets leave the camera where the player left it.
func show_place(target: String) -> void:
	if city_map == null: return
	# Another city's place (a cross-city request's `outpost:gn-…~market0`, 苏烈 SGODOT-284): its city is read and pinned
	# first, then the camera flies there as to any pin.
	var cluster := P0CityPlaces.cluster_of(target.trim_prefix("outpost:").trim_prefix("pond:"))
	if cluster != "" and not P0CityPlaces.has_city(cluster) and rt != null:
		P0CityPlaces.fetch(rt.session, cluster, func(city):
			_show_city_places(city, cluster)
			show_place(target), _show_failed)
		return
	if cluster != "" and not _shown_cities.has(cluster): _show_city_places(P0CityPlaces.city(cluster), cluster)
	var entry := place_for(target)
	if entry.is_empty(): return
	# Flies since SGODOT-267 (_fly sets the city-wide pan bounds, else the homestead's 450 m box pulls the camera back);
	# the pin is selected on landing.
	_fly("show:" + target, float(entry.lat), float(entry.lng), SHOW_ZOOM, func(): if target != "home": city_map.select(entry))

## Show on map's city read failed: the player asked for this, so say so (不知火舞 on #279), as any command that did not go
## through — only while the map is still where they are (不知火舞 on #282: not once they have left it).
func _show_failed() -> void:
	if rt == null or rt.world != self or not is_visible_in_tree(): return
	rt.ui.show_sys(UiSysBanner.Kind.CMD_FAIL, "Didn't go through · try again", P0Runtime.CMD_FAIL_S)

## Show from a panel opened on the map (Today, the Energy card, a NeedSource): every target is a pin here; a homestead
## target (plots, stall, stove …) is the homestead's.
func p0_show_spot(where: String) -> void:
	show_place(P0Ui.map_target(where))

## The pin a Show on map target points at ({lat, lng} plus the city-map entry for outposts and ponds), or {}.
func place_for(target: String) -> Dictionary:
	if target == "home": return {"lat": home_lat, "lng": home_lng}
	if target.begins_with("outpost:"):
		var key := target.trim_prefix("outpost:")
		var o := P0Outposts.find(key) if key.find("~") > 0 else P0Outposts.by_role(key)   # another city's by id (SGODOT-280)
		return {} if o.is_empty() else P0Outposts.place_entry(o, int(_online.get(str(o.id), 0)))
	if target.begins_with("pond:"):
		var id := target.trim_prefix("pond:")
		if id.find("~") > 0:   # another city's pond: its pin entry (P0CityPlaces registered it with SystemPonds)
			var p := P0CityPlaces.pond(id)
			return {} if p.is_empty() else p.merged({"kind": "pond"})
		return P0Ponds.location(id)
	return {}

func p0_surface() -> String: return "map"

## Android Back on the map (李元芳 int10): P0's own layers first, one per press — a dragged or lifted slot flies back,
## then the radial, then a card, then a drawer (P0Ui.close_top_layer, LOCK-06) — and only with none left the map's own
## (its city card, relocation, a farm selection). #92 brought P0's HUD and Bag to the map without this, so Bag, Today,
## the Inbox and the place cards could not be closed with Back there.
func is_back_navigation_locked() -> bool:
	if travelling():   # q(147): Back lands a flight (after its first 0.5 s); it never leaves the map mid-air
		_skip_travel()
		return true
	if rt != null and rt.ui.close_top_layer(): return true
	return super.is_back_navigation_locked()

## Map marks (plan §9.5.2, q(48)): ✓ deliverable, ! request, ◆ new, in priority order. One list badges the pins
## (CityMapView.set_marks: the first five on screen) and packs them first with whole labels (#83's _marker_of, through
## city_pin_markers), so a badge and its pin never disagree (亚瑟 on 234).
func p0_frame(view: Dictionary, _dt: float) -> void:
	if city_map == null: return
	_travel_watch()
	MapUsage.last_view = Vector3(center_lat, center_lng, zoom)   # Licenses › Mapbox › Improve this map (q(133) v3)
	_sync_here()
	# The recenter key gives way to an open sheet (不知火舞 on 234 A2: it showed under the card's ×).
	var key_shown := not rt.ui.has_modal()
	if city_map.recenter.visible != key_shown: city_map.recenter.visible = key_shown
	if city_map.home_key.visible != key_shown: city_map.home_key.visible = key_shown   # the home key with it
	var list := _marks_now(view)
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
## Review shots' marks (marks:sh_market_1=request|sh_tea_1=deliver), over the view's; none outside a shot.
var _dev_marks: Array = []

func _marks_now(view: Dictionary) -> Array:
	return _dev_marks.duplicate() if not _dev_marks.is_empty() else pin_marks(view)

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
	var list := _marks_now(v)
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
		"fishscroll":   # fishscroll — the Details list scrolled to its end (SGODOT-283 shots)
			for n in rt.ui.find_children("FishList", "ScrollContainer", true, false):
				(n as ScrollContainer).scroll_vertical = 100000
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
		"marks":   # marks:sh_market_1=request|sh_tea_1=deliver — map marks on those pins, for shots (q(146) review)
			_dev_marks = []
			for pair in step[1].split("|", false):
				var kv := pair.split("=")
				_dev_marks.append({"id": kv[0], "state": str(MARK_STATES.get(kv[1], kv[1]))})
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
		"fly":   # fly:gn-1850147 — the travel card's Fly for that city (review shots, SGODOT-280): travel, then the arrival
			_origin_before = _origin()
			_here_before = P0Travel.here(_view())
			rt.session.send({"type": "travel", "to": step[1]})
		"citycard":   # citycard:gn-1850147 — that city's silhouette card (MAP-3-FREE), as a tap on its bubble
			open_city_card(step[1])
		"arrivalcard":   # arrivalcard:gn-1850147 — the first visit's card (MAP-7-FREE) for that city
			open_arrival_card(step[1])
		"arrivalgo":   # the arrival card's Visit the outpost, as a tap on it
			var b := rt.ui.root.find_child("Primary", true, false)
			if b is UiCommandButton: (b as UiCommandButton).activated.emit()
		"center":   # center:31.228:121.478 (the city overview) — where the camera looks, for shots
			center_lat = float(step[1])
			center_lng = float(step[2])
			_camera_dirty = true
		_: return false
	return true
