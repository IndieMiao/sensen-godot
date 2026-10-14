extends RefCounted
## The places of cities other than home (SGODOT-280 / 275): ponds and outposts the server's generator gives each city
## cluster, read once per city from GET /v1/p0/city/:cluster and kept for the session. Home keeps its hand-written
## tables (P0Ponds, P0Outposts). A generated pond becomes a SystemPonds location (its template is bundled), so the pond
## scene, the loading cover and the map read it like Fern Pond; a generated outpost takes the shape of a p0_outposts.json
## entry, its room walls and keeper art borrowed from the hand-written room of its art (the placeholder rooms, world_gen
## room). Preloaded, no class_name (a new global class needs an editor import).

const P0Outposts := preload("res://modules/p0/p0_outposts.gd")

## The residents' looks, as the outpost room reads them (p0_outpost.gd NPCS_PATH).
const NPCS_PATH := "res://assets/p0/outpost_npcs.json"

## cluster → {ponds: [GenPond], outposts: [GenOutpost], fish, residents, tier, climate} as the server sent it.
static var _cities: Dictionary = {}
static var _pending: Dictionary = {}   # cluster → [done callables] while its read is out: every asker hears the answer
static var _failing: Dictionary = {}   # cluster → [failed callables] of the same read
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
## `failed` (optional) is told when this read does not come back (a network failure, a refusal): a caller the player is
## waiting on says so (Show on map, 不知火舞 on #279); the rest stay quiet and the next ask reads again.
static func fetch(session: Node, cluster: String, done := Callable(), failed := Callable()) -> void:
	if cluster == "" or session == null: return
	if _cities.has(cluster):
		if done.is_valid(): done.call(_cities[cluster])
		return
	# A read already out (the map's camera city asked first, then the silhouette card): wait for it, never drop the
	# callback (李元芳 0.2.0: the card stayed at "–" until opened again).
	if _pending.has(cluster):
		if done.is_valid(): (_pending[cluster] as Array).append(done)
		if failed.is_valid(): (_failing.get_or_add(cluster, []) as Array).append(failed)
		return
	_pending[cluster] = [done] if done.is_valid() else []
	_failing[cluster] = [failed] if failed.is_valid() else []
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
		var data = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
		if data is Dictionary and data.get("city") is Dictionary: accept(cluster, data.city)
		else: fail(cluster))   # failed: the next ask reads again
	if http.request(str(session.get("base_url")) + path, session.call("_headers")) != OK:
		http.queue_free()
		fail(cluster)

## A city's read did not come back: those waiting with a `failed` hear it; nobody hears a later answer from this one.
static func fail(cluster: String) -> void:
	var told: Array = _failing.get(cluster, [])
	_pending.erase(cluster)
	_failing.erase(cluster)
	for f in told: if (f as Callable).is_valid(): (f as Callable).call()

## A city's answer (the route's `city`: ponds / outposts ids, residents, fish, detail {ponds, outposts}, preview).
## Every caller waiting on it is told, in the order they asked.
static func accept(cluster: String, city_: Dictionary) -> void:
	var waiting: Array = _pending.get(cluster, [])
	_pending.erase(cluster)
	_failing.erase(cluster)
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
	for done in waiting: if (done as Callable).is_valid(): (done as Callable).call(out)

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
	# This client's own anchors for the room kind where they differ from the ones the server names (world.room[kind]
	# .client_anchors): the S-tier trading post's cabin.anchors.json, which 0.2.5 and older do not have — the server
	# keeps naming the tea house's for them, so it can go out before or after this client (周瑜 on #404).
	var kind := "cabin" if bool(o.get("cabin", false)) else str(o.get("role", ""))
	var own := str(P0Logic.content().get("world", {}).get("room", {}).get(kind, {}).get("client_anchors", ""))
	if own != "": entry["anchors"] = own
	if entry.get("keeper") is Dictionary and str(entry.keeper.get("look", "")) != "":
		entry["keeper"] = (entry.keeper as Dictionary).duplicate()
		entry.keeper["look"] = keeper_look(str(entry.keeper.look), entry.get("residents", []))
	return entry

## A hair part's style: its NPC-only colour variants are the same style (Tomo's hairhat0_npc_tomo is hairhat0, darker).
static func hair_style(part: String) -> String:
	var cut := part.find("_npc_")
	return part.substr(0, cut) if cut > 0 else part

## A generated keeper's look set (world.keeper_looks `<role>_<climate>_<n>`), unless its hair style is a resident's of
## the same room (a colour variant counts: hair_style): then the first of the role and climate's three sets that is
## not, the given one when all three are (不知火舞 on 284: Lena's hairhat41, Tomo's darker hairhat0). The room, the
## keeper bar and the greeting card's portrait all read the entry, so they wear the same one.
static func keeper_look(look: String, residents: Array) -> String:
	var looks: Dictionary = P0Logic.content().get("world", {}).get("keeper_looks", {})
	var npcs: Dictionary = P0RoomAnchors.read_json(NPCS_PATH).get("npcs", {})
	var hair := {}
	for id in residents:
		var h := hair_style(str(npcs.get(str(id), {}).get("slots", {}).get("hairHat", "")))
		if h != "": hair[h] = true
	var clashes := func(k: String) -> bool: return hair.has(hair_style(str((looks.get(k, {}) as Dictionary).get("hairHat", ""))))
	if hair.is_empty() or not clashes.call(look): return look
	var stem := look.substr(0, look.rfind("_"))
	for i in 3:
		var k := "%s_%d" % [stem, i]
		if looks.has(k) and not clashes.call(k): return k
	return look

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

## The city's market square nearest to `at` (lat, lng), else its nearest outpost: the arrival card's "Nearby" outpost.
static func nearest_outpost(cluster: String, at: Vector2, role := "market") -> Dictionary:
	var best := {}
	var best_km := INF
	for pass_role in [role, ""]:
		for o in city(cluster).get("outposts", []):
			if pass_role != "" and str(o.get("role", "")) != pass_role: continue
			var km: float = load("res://modules/p0/p0_clusters.gd").distance_km(at.x, at.y, float(o.lat), float(o.lng))
			if km < best_km:
				best_km = km
				best = o
		if not best.is_empty(): return best
	return best

## Tests.
static func clear() -> void:
	for id in _ponds: SystemPonds._remote.erase(id)
	_cities.clear()
	_pending.clear()
	_failing.clear()
	_ponds.clear()
	_outposts.clear()
