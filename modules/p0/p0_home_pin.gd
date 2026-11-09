extends RefCounted
## The free pin's rules on the client (q(216) ②③, SGODOT-342 PR-2; 340 fc814d17 §5, 3e4fbec7, fdf7c5df): where the
## pin may stand in a city — within range_km of its base and clear_m of every outpost, hut and pond centre (the
## server's pinRefusal, #473) — what the card under the map says, and what the grey Build here says and toasts. The
## server's word is final; the client judges a little inside it (9.95 km / 305 m, 周瑜 on #473) so a pin it shows as
## buildable is never refused. GET /v1/p0/home/spots/:cluster's `pin` {base, range_km, clear_m, start, blocks} is the
## area; points are Vector2(lat, lng). Pure, tested headless. Preloaded, no class_name (a new global class needs an
## editor import).

## The client's judgement inside the server's: a pin this far in from the circle's edge, this far out from a place.
const RANGE_MARGIN_KM := 0.05
const CLEAR_MARGIN_M := 5.0
## The 300 m circle of a place is drawn while the pin is this near it (340 §5: not a screen full of circles).
const SHOW_CLEAR_M := 600.0
## The start (spot 1, checked by the server, #473) stands even where it is within the client's margins: this near it.
const START_M := 2.0
const COMPASS := ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]

## The read's `pin` as an area {base, range_km, clear_m, start, blocks: [{id, at}]}; {} when it is missing or not whole
## (an older server, a city that cannot be a home: the page reads it as a failed read, 周瑜 on #473).
static func area(pin: Variant) -> Dictionary:
	if not pin is Dictionary: return {}
	var p := pin as Dictionary
	var base = point(p.get("base"))
	var start = point(p.get("start"))
	if base == null or start == null or not (p.get("range_km") is float or p.get("range_km") is int): return {}
	var blocks: Array = []
	for b in (p.get("blocks", []) if p.get("blocks") is Array else []):
		var at = point(b)
		if at != null and b is Dictionary: blocks.append({id = str(b.get("id", "")), at = at})
	# start_ll: the start in doubles (a Vector2 is single precision, about a metre off): where the camera is put
	return {base = base, range_km = float(p.range_km), clear_m = float(p.get("clear_m", 0.0)), start = start,
		start_ll = [float(p.start.lat), float(p.start.lng)], blocks = blocks}

## {lat, lng} → Vector2(lat, lng), null when it is not one.
static func point(v: Variant) -> Variant:
	if not v is Dictionary: return null
	var lat = v.get("lat")
	var lng = v.get("lng")
	if not (lat is float or lat is int) or not (lng is float or lng is int): return null
	return Vector2(float(lat), float(lng))

## Great-circle km (the server's world.km).
static func km(a: Vector2, b: Vector2) -> float:
	var d_lat := deg_to_rad(b.x - a.x)
	var d_lng := deg_to_rad(b.y - a.y)
	var h := pow(sin(d_lat / 2.0), 2) + cos(deg_to_rad(a.x)) * cos(deg_to_rad(b.x)) * pow(sin(d_lng / 2.0), 2)
	return 2.0 * 6371.0 * asin(minf(1.0, sqrt(h)))

## km between two [lat, lng] in doubles: for the metre a Vector2 cannot hold (a same-city move taken, 周瑜 on #495).
static func km_ll(a: Array, b: Array) -> float:
	var d_lat := deg_to_rad(float(b[0]) - float(a[0]))
	var d_lng := deg_to_rad(float(b[1]) - float(a[1]))
	var h := pow(sin(d_lat / 2.0), 2) + cos(deg_to_rad(float(a[0]))) * cos(deg_to_rad(float(b[0]))) * pow(sin(d_lng / 2.0), 2)
	return 2.0 * 6371.0 * asin(minf(1.0, sqrt(h)))

## The compass word from a to b (the server's toward: flat, fine within a city).
static func toward(a: Vector2, b: Vector2) -> String:
	var deg := rad_to_deg(atan2((b.y - a.y) * cos(deg_to_rad(a.x)), b.x - a.x))
	return COMPASS[int(round(fposmod(deg, 360.0) / 45.0)) % 8]

## Why the pin may not stand at `at`, {} when it may: {code: "far", km} outside the circle (judged range − 50 m);
## {code: "near", id, m} the nearest place closer than clear + 5 m. The start itself always stands (340 §5: Build here
## at once). On the page's own start (`origin`, [lat, lng]: spot 1, or the farm for a same-city re-pin) the margins go
## and only the server's 10 km / 300 m judge (不知火舞 235af5d7): a farm the server once took is not greyed for the
## client's 5 m, yet one truly within 300 m of a place still says why.
static func refusal(a: Dictionary, at: Vector2, origin: Variant = null) -> Dictionary:
	if a.is_empty(): return {code = "far", km = INF}
	if km(at, a.start) * 1000.0 < START_M: return {}   # the server's vetted start stands as it is, margins or not
	var on_origin := origin is Array and (origin as Array).size() == 2 \
		and km(at, Vector2(float(origin[0]), float(origin[1]))) * 1000.0 < START_M
	var range_margin := 0.0 if on_origin else RANGE_MARGIN_KM
	var clear_margin := 0.0 if on_origin else CLEAR_MARGIN_M
	var d := km(at, a.base)
	if d > float(a.range_km) - range_margin: return {code = "far", km = d}
	if float(a.clear_m) > 0.0:
		var near := {}
		for b in a.blocks:
			var m := km(at, b.at) * 1000.0
			if m < float(a.clear_m) + clear_margin and (near.is_empty() or m < float(near.m)): near = {code = "near", id = b.id, m = m}
		if not near.is_empty(): return near
	return {}

## The places whose 300 m circle shows: within SHOW_CLEAR_M of the pin, nearest first.
static func shown_blocks(a: Dictionary, at: Vector2) -> Array:
	if a.is_empty() or float(a.clear_m) <= 0.0: return []
	var out := (a.blocks as Array).filter(func(b): return km(at, b.at) * 1000.0 <= SHOW_CLEAR_M)
	out.sort_custom(func(x, y): return km(at, x.at) < km(at, y.at))
	return out

## A distance as q(132) writes it: under 10 km one decimal (`0.8 km`), from 10 km whole with thousands (`11 km`).
static func km_text(d: float) -> String:
	return km_figure(d) + " km"

## km_text's figure alone (`0.8`, `8,269`): the two lines below keep ` km` in their own words, so 中文's `%s km to %s`
## takes only a distance — a bare `%s to %s` took any line with a ` to ` in it (SGODOT-450, 周瑜).
static func km_figure(d: float) -> String:
	if snappedf(d, 0.1) < 10.0: return String.num(snappedf(d, 0.1), 1)   # 9.96 is `10 km`, not `10.0 km` (周瑜)
	var n := str(int(round(d)))
	var out := ""
	while n.length() > 3:
		out = "," + n.right(3) + out
		n = n.left(n.length() - 3)
	return n + out

## The card's one line (3e4fbec7; fdf7c5df: the same when it cannot stand): `0.8 km to Fern Pond · west`, the pin on
## the pond's west. pond: {name, at}.
static func card_line(at: Vector2, pond: Dictionary) -> String:
	if pond.is_empty(): return ""
	return "%s km to %s · %s" % [km_figure(km(pond.at, at)), str(pond.name), toward(pond.at, at)]

## The confirm card's first line (q(216) ③): `San Francisco · 0.8 km to Fern Pond`, no side.
static func confirm_line(city_name: String, at: Vector2, pond: Dictionary) -> String:
	if pond.is_empty(): return city_name
	return "%s · %s km to %s" % [city_name, km_figure(km(pond.at, at)), str(pond.name)]

## The grey Build here and its toast for a refusal (q(216) ③): {key, short, toast}. `short` is the general word for
## when the place's own name does not fit the key (pond / shop / hut; the page measures). names: id → {name, kind}.
static func refusal_text(no: Dictionary, names: Dictionary) -> Dictionary:
	if no.is_empty(): return {}
	if no.code == "far":
		return {key = "Too far from the city", short = "Too far from the city", toast = "Move the pin back inside the circle."}
	var place: Dictionary = names.get(no.id, {})
	var kind := str(place.get("kind", kind_of(str(no.id))))
	var general := "Too close to a %s" % kind
	var named := str(place.get("name", ""))
	return {key = "Too close to %s" % named if named != "" else general, short = general,
		toast = "Leave some room around ponds and shops."}

## pond / hut / shop from a place id when no name table has it (generated ids: `gn-…~pond0`, `gn-…~hut…`).
static func kind_of(id: String) -> String:
	if id.contains("~pond") or id.begins_with("pond_") or id.ends_with("_pond"): return "pond"
	if id.contains("~hut") or id.contains("hut"): return "hut"
	return "shop"

## Where the pin starts — and where the back-to-start key takes it back to (q(223), 340 78cbe60f): spot 1 for a first
## pick or another city; the farm as it stands for the home city itself (q(216) ⑨; `farm`, view.home.farm as [lat,
## lng]). [lat, lng] in doubles.
static func start(a: Dictionary, same_city: bool, farm: Variant) -> Array:
	if same_city and farm is Array and (farm as Array).size() == 2: return [float(farm[0]), float(farm[1])]
	return a.get("start_ll", [0.0, 0.0])

## {lat, lng} → [lat, lng] in doubles, null when it is not one.
static func lat_lng(v: Variant) -> Variant:
	var p = point(v)
	return [float(v.lat), float(v.lng)] if p != null else null

## The command (q(216); 周瑜 on #473): {type, city, at: [lat, lng], spot: -1} — an older server answers bad_spot rather
## than building on spot 1; never at: null. lat / lng as the map's camera holds them (doubles; a Vector2 is single
## precision, about a metre off at these longitudes).
static func command(type: String, city: String, lat: float, lng: float) -> Dictionary:
	return {type = type, city = city, at = [lat, lng], spot = -1}
