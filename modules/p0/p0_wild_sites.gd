extends RefCounted
## Wild sites (SGODOT-355 first batch, plan v4 §1.4 / §3.3; 后裔's contract C v0.2, #616): one frozen catalog for every
## player, read by the map's viewport from GET /v1/p0/wild?bbox=s,w,n,e&zoom=z — at most 40 a read (`capped`, `total`),
## none below zoom 9; the mine types only — quarries and veins open, the geodes, abysses and ruins grey (`open: false`,
## *Not open yet*); woodland, waterside and bloom sites stay in the catalog unshown (v4q(3)). A site is the catalog's
## entry (id `wd-<row>-<col>`, type, lat / lng, name — the card's title —, short — the pin's label, q(137) —, near, open,
## mine) plus the player's own (km, trip, free, visited, pass_until, best_floor). Kept for the session by id; a box read
## once is not read again. Preloaded, no class_name (a new global class needs an import).
##
## Until the server's route is on the branch, `mock` (a path to a wild_mock.json, the env P0_WILD_MOCK on a desktop)
## answers from a local file: the player's own fields worked out here from the home city's base point (q(184): the point
## the nearest three cities count from too), the nearest three open ones free.

const P0Clusters := preload("res://modules/p0/p0_clusters.gd")

const MIN_ZOOM := 9.0
## The types the map shows (#616): the mine types, open or not yet.
const SHOWN := ["quarry", "vein", "geode", "abyss", "ruin"]
const CAP := 40
const PREFIX := "wd-"

## id → site (catalog + the player's fields, as last read).
static var _sites: Dictionary = {}
## box key → true once read; box key → [done] / [failed] while out.
static var _read: Dictionary = {}
static var _pending: Dictionary = {}
static var _failing: Dictionary = {}
## The local stand-in (see above): the path of its file and its sites.
static var mock := ""
static var _mock_sites: Array = []

static func is_wild(id: String) -> bool: return id.begins_with(PREFIX)
static func has_site(id: String) -> bool: return _sites.has(id)
static func site(id: String) -> Dictionary: return _sites.get(id, {})
## Every site read this session, of the types the map shows; how many (a map redraws its pins when it grows).
static func all() -> Array: return _sites.values().filter(func(x): return str(x.get("type", "")) in SHOWN)
static func count() -> int: return _sites.size()

## The sites known in a box (south, west, north, east; west > east across the 180° line), in the server's order.
static func in_box(box: Array) -> Array:
	return _sites.values().filter(func(s): return _inside(box, float(s.lat), float(s.lng)))

## Forget everything read (a new account, tests).
static func clear() -> void:
	_sites.clear()
	_read.clear()
	_pending.clear()
	_failing.clear()
	_mock_sites = []

## The sites of a box at a zoom: `done(sites)` once they are in (at once when the box was read already, [] below zoom 9);
## `failed()` when the read does not come back — the next ask reads again. A box is keyed by its corners to 0.5° and
## the zoom to a whole level, so a camera nudged a little asks nothing new.
static func fetch(session: Node, box: Array, zoom: float, done := Callable(), failed := Callable()) -> void:
	if box.size() != 4 or session == null: return
	if zoom < MIN_ZOOM:
		if done.is_valid(): done.call([])
		return
	var key := box_key(box, zoom)
	if _read.has(key):
		if done.is_valid(): done.call(in_box(box))
		return
	if _pending.has(key):
		if done.is_valid(): (_pending[key] as Array).append(func(): done.call(in_box(box)))
		if failed.is_valid(): (_failing.get_or_add(key, []) as Array).append(failed)
		return
	_pending[key] = [func(): done.call(in_box(box))] if done.is_valid() else []
	_failing[key] = [failed] if failed.is_valid() else []
	var query := "bbox=%s&zoom=%d" % [",".join(box.map(func(x): return "%.4f" % float(x))), int(floor(zoom))]
	if mock == "" and OS.get_environment("P0_WILD_MOCK") != "": mock = OS.get_environment("P0_WILD_MOCK")
	if mock != "":
		_answer_from_mock.call_deferred(session, key, box)
		return
	var t: Variant = session.get("transport")
	if t is Callable and (t as Callable).is_valid():   # tests answer with accept()
		(t as Callable).call(HTTPClient.METHOD_GET, "/p0/wild?" + query, {}, {"type": "wild", "key": key, "box": box})
		return
	var http := P0HttpRequest.new()   # its wait in live time, not stalls (SGODOT-370)
	session.add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		var data = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
		if data is Dictionary and data.get("sites") is Array: accept(key, data)
		else: fail(key))
	if http.send(str(session.get("base_url")) + "/p0/wild?" + query, session.call("_headers")) != OK:
		http.queue_free()
		fail(key)

## A box's answer ({sites, capped, total}): its sites kept (the player's fields replaced by the newer read), everyone
## waiting on it told.
static func accept(key: String, data: Dictionary) -> void:
	for s in data.get("sites", []):
		if s is Dictionary and is_wild(str(s.get("id", ""))): _sites[str(s.id)] = s
	_read[key] = true
	var waiting: Array = _pending.get(key, [])
	_pending.erase(key)
	_failing.erase(key)
	for f in waiting: if _alive(f): (f as Callable).call()

static func fail(key: String) -> void:
	var told: Array = _failing.get(key, [])
	_pending.erase(key)
	_failing.erase(key)
	for f in told: if _alive(f): (f as Callable).call()

## The player's fields as the view has them for the site they are at (view.wild.here) win over a box read's.
static func remember(view: Dictionary) -> void:
	var here = view.get("wild", {}).get("here", null) if view.get("wild", null) is Dictionary else null
	if here is Dictionary and is_wild(str(here.get("id", ""))): _sites[str(here.id)] = here

static func box_key(box: Array, zoom: float) -> String:
	var r := func(x): return str(roundi(float(x) * 2.0))
	return "%s,%s,%s,%s@%d" % [r.call(box[0]), r.call(box[1]), r.call(box[2]), r.call(box[3]), int(floor(zoom))]

static func _inside(box: Array, lat: float, lng: float) -> bool:
	var s := float(box[0]); var w := float(box[1]); var n := float(box[2]); var e := float(box[3])
	if lat < s or lat > n: return false
	return lng >= w and lng <= e if w <= e else (lng >= w or lng <= e)

static func _alive(f) -> bool:
	if not (f is Callable) or not (f as Callable).is_valid(): return false
	var o: Object = (f as Callable).get_object()
	return o == null or is_instance_valid(o)

# ---------------------------------------------------------------- the local stand-in (until the server has the route)
static func _answer_from_mock(session: Node, key: String, box: Array) -> void:
	if _mock_sites.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(mock)) if FileAccess.file_exists(mock) else null
		_mock_sites = data.get("sites", []) if data is Dictionary else []
	var view: Dictionary = session.get("view") if session.get("view") is Dictionary else {}
	accept(key, mock_answer(_mock_sites, box, home_point(view)))

## The point the player's own fields count from (contract v0.2): the home city's base, as the nearest three cities'.
static func home_point(view: Dictionary) -> Vector2:
	var t: Dictionary = view.get("travel", {}) if view.get("travel", null) is Dictionary else {}
	var home := P0Clusters.get_cluster(str(t.get("home", "")))
	return Vector2(float(home.get("lat", 0.0)), float(home.get("lng", 0.0))) if not home.is_empty() else Vector2.ZERO

## The server's answer worked out from a catalog: the mine types shown (#616); the nearest three open ones free (one
## quarry and one vein among them when the catalog has them, plan v4 §1.5); trips by distance (a rough stand-in for the
## server's Trip table); the cap and its order (nearer first, then by id).
static func mock_answer(catalog: Array, box: Array, home: Vector2) -> Dictionary:
	var by_km := catalog.filter(func(s): return str(s.get("type", "")) in SHOWN) \
		.map(func(s): return [P0Clusters.distance_km(home.x, home.y, float(s.lat), float(s.lng)), s])
	by_km.sort_custom(func(a, b): return a[0] < b[0])
	var free := {}
	for want in ["quarry", "vein"]:
		for e in by_km:
			if str(e[1].type) == want and bool(e[1].open):
				free[str(e[1].id)] = true
				break
	for e in by_km:
		if free.size() >= 3: break
		if bool(e[1].open): free[str(e[1].id)] = true
	var sites: Array = []
	for e in by_km:
		var s: Dictionary = e[1]
		if not _inside(box, float(s.lat), float(s.lng)): continue
		var km := float(e[0])
		sites.append(s.merged({"km": snappedf(km, 0.1), "trip": 1 if km < 300 else 2 if km < 800 else 3 if km < 2000 else 4,
			"free": free.has(str(s.id)), "visited": false, "pass_until": null, "best_floor": 0}))
	sites.sort_custom(_before)
	return {"sites": sites.slice(0, CAP), "capped": sites.size() > CAP, "total": sites.size()}

static func _before(a: Dictionary, b: Dictionary) -> bool:
	if float(a.km) != float(b.km): return float(a.km) < float(b.km)
	return str(a.id) < str(b.id)
