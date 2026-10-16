extends RefCounted
## The home pick's data (SGODOT-303, q(160) / q(188) / q(205) / q(207)): GET /v1/p0/home/cities[?q=] — the open cities,
## `Near you` (the open city nearest the address, or none), and a search's matches with why one cannot be picked — and
## GET /v1/p0/home/spots/:cluster — this player's three farm spots there. The pick and spot pages
## (p0_home_pick_page.gd, p0_home_spot_page.gd) lay out what these say. Pure where it can be, tested headless.
## Preloaded, no class_name (a new global class needs an editor import).

## The climate groups of `Recommended`, in this order (HOME-PICK-1: Temperate, Subtropical, Tropical; then Cool).
const BANDS := ["temperate", "subtropical", "tropical", "cool"]
## A search asks the server from this many letters (the route answers nothing shorter).
const SEARCH_MIN := 2

## path → [done, failed] while a test's transport holds the read (answer() settles it).
static var _waiting: Dictionary = {}

## The open cities (and with `query`, the matches): done({open, matches, near}); failed() on a network failure or a
## refusal.
static func cities(session: Node, query: String, done: Callable, failed: Callable) -> void:
	var q := query.strip_edges()
	_read(session, "/p0/home/cities" + ("?q=" + q.uri_encode() if q.length() >= SEARCH_MIN else ""), func(d: Dictionary):
		done.call({open = d.get("open", []), matches = d.get("matches", []), near = d.get("near", null)}), failed)

## A city's three spots: done({city, spots, resets_at}) — each spot {spot, lat, lng, km, toward, pond {id, name, lat,
## lng}, hood}; failed() when they do not come.
static func spots(session: Node, cluster: String, done: Callable, failed: Callable) -> void:
	_read(session, "/p0/home/spots/" + cluster.uri_encode(), func(d: Dictionary):
		if not d.get("spots") is Array or (d.spots as Array).size() != 3: failed.call()
		else: done.call(d), failed)

static func _read(session: Node, path: String, done: Callable, failed: Callable) -> void:
	if session == null:
		failed.call()
		return
	var t: Variant = session.get("transport")
	if t is Callable and (t as Callable).is_valid():   # tests answer with answer()
		_waiting[path] = [done, failed]
		(t as Callable).call(HTTPClient.METHOD_GET, path, {}, {"type": "home_pick"})
		return
	var http := HTTPRequest.new()
	http.timeout = 8.0
	session.add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		var data = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
		if data is Dictionary and bool(data.get("ok", false)): done.call(data)
		else: failed.call())
	if http.request(str(session.get("base_url")) + path, session.call("_headers")) != OK:
		http.queue_free()
		failed.call()

## A test's answer to a read on its transport: the route's body, or null for a failure.
static func answer(path: String, data: Variant) -> void:
	var w: Array = _waiting.get(path, [])
	_waiting.erase(path)
	if w.is_empty(): return
	if data is Dictionary and bool((data as Dictionary).get("ok", false)): (w[0] as Callable).call(data)
	else: (w[1] as Callable).call()

static func waiting(path: String) -> bool: return _waiting.has(path)
static func clear() -> void: _waiting.clear()

## Why a row cannot be picked (its third line, HOME-PICK-2 / q(205) ④), "" when it can: the home it already is (the
## change), a small town, a city not open yet.
static func note(row: Dictionary, home := "") -> String:
	if home != "" and str(row.get("id", "")) == home: return "Your home city"
	match str(row.get("status", "")):
		"open": return ""
		"small": return "Small town · pick a nearby city"
		_: return "Not open yet · pick a nearby city"

## The list's parts in order (HOME-PICK-1, NOIP 2771:162818): with a city near, the `Near you` title and its row; then
## `Recommended` and each climate group's title and rows — the open cities in the server's order, the near one not
## again. A search (`matches` given) is only its rows, no titles (HOME-PICK-2). Each part: {kind: "title" | "band" |
## "row", text?, band?, row?}.
static func sections(open: Array, near: Variant, matches: Variant = null) -> Array:
	var out: Array = []
	if matches is Array:
		for r in matches: out.append({kind = "row", row = r})
		return out
	var near_id := ""
	if near is Dictionary and not (near as Dictionary).is_empty():
		near_id = str(near.get("id", ""))
		out.append({kind = "title", text = "Near you"})
		out.append({kind = "row", row = near})
	out.append({kind = "title", text = "Recommended"})
	for b in BANDS:
		var rows := open.filter(func(r): return band(r) == b and str(r.get("id", "")) != near_id)
		if rows.is_empty(): continue
		out.append({kind = "band", band = b, text = b.capitalize()})
		for r in rows: out.append({kind = "row", row = r})
	return out

## A row's climate band key, "temperate" for an unknown one.
static func band(row: Dictionary) -> String:
	var b := str(row.get("climate", "")).to_lower()
	return b if b in BANDS else "temperate"

## The city the page opens with (q(205) ②): the first pick takes `Near you`; no city near, or a change of home, none.
static func preselect(near: Variant, change := false) -> String:
	if change or not near is Dictionary: return ""
	return str((near as Dictionary).get("id", ""))

## A spot card's line (HOME-PICK-3): `1.2 km to Fern Pond · northeast`.
static func spot_line(spot: Dictionary) -> String:
	var pond: Dictionary = spot.get("pond", {}) if spot.get("pond") is Dictionary else {}
	return "%s km to %s · %s" % [String.num(snappedf(float(spot.get("km", 0.0)), 0.1), 1), str(pond.get("name", "")), str(spot.get("toward", ""))]

## A spot card's title: its district, else `Spot N`.
static func spot_title(spot: Dictionary) -> String:
	var hood := str(spot.get("hood", "")) if spot.get("hood") != null else ""
	return hood if hood != "" else "Spot %d" % (int(spot.get("spot", 0)) + 1)
