extends RefCounted
## The places of cities other than home (SGODOT-280 / 275): ponds and outposts the server's generator gives each city
## cluster, read once per city from GET /v1/p0/city/:cluster and kept for the session. Home keeps its hand-written
## tables (P0Ponds, P0Outposts). A generated pond becomes a SystemPonds location (its template is bundled), so the pond
## scene, the loading cover and the map read it like Fern Pond; a generated outpost takes the shape of a p0_outposts.json
## entry, its room walls and keeper art borrowed from the hand-written room of its art (the placeholder rooms, world_gen
## room). Preloaded, no class_name (a new global class needs an editor import).

const P0Outposts := preload("res://modules/p0/p0_outposts.gd")

## cluster → {ponds: [GenPond], outposts: [GenOutpost], fish, residents, tier, climate} as the server sent it.
static var _cities: Dictionary = {}
static var _pending: Dictionary = {}   # cluster → true while its read is out
## generated id → its entry (ponds: a SystemPonds location; outposts: a p0_outposts-shaped entry).
static var _ponds: Dictionary = {}
static var _outposts: Dictionary = {}

## The city id a generated place id carries (`gn-1850147~pond0` → `gn-1850147`), "" for a hand-written id.
static func cluster_of(id: String) -> String:
	var cut := id.find("~")
	return id.substr(0, cut) if cut > 0 else ""

static func has_city(cluster: String) -> bool: return _cities.has(cluster)
static func city(cluster: String) -> Dictionary: return _cities.get(cluster, {})

## Ask the server for a city once (and again after a failure); `done` is called with the city when it is in.
static func fetch(session: Node, cluster: String, done := Callable()) -> void:
	if cluster == "" or session == null: return
	if _cities.has(cluster):
		if done.is_valid(): done.call(_cities[cluster])
		return
	if _pending.has(cluster): return
	_pending[cluster] = true
	var path := "/p0/city/" + cluster.uri_encode()
	var t: Variant = session.get("transport")
	if t is Callable and (t as Callable).is_valid():   # tests answer with accept()
		(t as Callable).call(HTTPClient.METHOD_GET, path, {}, {"type": "city", "cluster": cluster})
		return
	var http := HTTPRequest.new()
	http.timeout = 8.0
	session.add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		_pending.erase(cluster)
		if result != HTTPRequest.RESULT_SUCCESS or code != 200: return
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary and data.get("city") is Dictionary:
			accept(cluster, data.city)
			if done.is_valid(): done.call(_cities[cluster]))
	if http.request(str(session.get("base_url")) + path, session.call("_headers")) != OK:
		http.queue_free()
		_pending.erase(cluster)

## A city's answer (the route's `city`: ponds / outposts ids, residents, fish, detail {ponds, outposts}, preview).
static func accept(cluster: String, city_: Dictionary) -> void:
	_pending.erase(cluster)
	var detail: Dictionary = city_.get("detail", {}) if city_.get("detail") is Dictionary else {}
	var out := {ponds = [], outposts = [], fish = city_.get("fish", []), residents = int(city_.get("residents", 0)),
		tier = str(city_.get("tier", "")), climate = str(city_.get("climate", "")), preview = city_.get("preview", {})}
	for p in detail.get("ponds", []):
		var entry := pond_entry(cluster, p)
		if entry.is_empty(): continue
		_ponds[entry.id] = entry
		out.ponds.append(entry)
	for o in detail.get("outposts", []):
		var entry := outpost_entry(cluster, o)
		if entry.is_empty(): continue
		_outposts[entry.id] = entry
		out.outposts.append(entry)
	_cities[cluster] = out

## A generated pond as a SystemPonds location: registered so SystemPonds.location / site / blueprint know it.
static func pond_entry(cluster: String, p: Dictionary) -> Dictionary:
	var spec := SystemPonds.template(str(p.get("template_id", "")))
	if spec.is_empty() or str(p.get("id", "")) == "": return {}
	var entry := {"id": str(p.id), "region_id": cluster, "cluster": cluster, "name": str(p.get("name", "Pond")),
		"kind": "pond", "category": "Fishing pond", "lat": float(p.get("lat", 0.0)), "lng": float(p.get("lng", 0.0)),
		"template_id": str(p.template_id), "decoration_seed": int(p.get("decoration_seed", 0)),
		"layout_revision": int(spec.revision), "enabled": true, "site": str(p.get("site", "pond")),
		"beginner": bool(p.get("beginner", false))}
	SystemPonds._remote[entry.id] = entry
	return entry

## A generated outpost shaped like a p0_outposts.json entry: walls, seats, anchors and backdrop from the hand-written
## room its art stands in for; its own name, role, keeper, point and capacity.
static func outpost_entry(cluster: String, o: Dictionary) -> Dictionary:
	var room := {}
	for h in P0Outposts.all():
		if str(h.get("art", "")) == str(o.get("art", "")): room = h
	if room.is_empty() or str(o.get("id", "")) == "": return {}
	var entry: Dictionary = room.duplicate(true)
	for k in ["id", "role", "name", "category", "lat", "lng", "capacity", "keeper", "residents", "nearest"]:
		if o.has(k): entry[k] = o[k]
	entry["cluster"] = cluster
	entry["anchors"] = str(o.get("anchors", room.get("anchors", "")))
	return entry

static func pond(id: String) -> Dictionary: return _ponds.get(id, {})
static func outpost(id: String) -> Dictionary: return _outposts.get(id, {})

## The city's beginner pond (its pond 0, §11.8.5), else its first; {} before the city is in.
static func beginner_pond(cluster: String) -> Dictionary:
	var ponds: Array = city(cluster).get("ponds", [])
	for p in ponds: if bool(p.get("beginner", false)): return p
	return ponds[0] if not ponds.is_empty() else {}

## The city's first market square, else its first outpost (the arrival card's "Visit the outpost").
static func first_outpost(cluster: String, role := "market") -> Dictionary:
	var outposts: Array = city(cluster).get("outposts", [])
	for o in outposts: if str(o.get("role", "")) == role: return o
	return outposts[0] if not outposts.is_empty() else {}

## Tests.
static func clear() -> void:
	for id in _ponds: SystemPonds._remote.erase(id)
	_cities.clear()
	_pending.clear()
	_ponds.clear()
	_outposts.clear()
