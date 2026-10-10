extends RefCounted
## P0 city clusters (SGODOT-275, plan v2 §11.1): the unit travel, stamps and passes are keyed by, read from
## assets/p0/city_clusters.json (shared with the server's CityClusters, built by server/tools/build_clusters.mjs and
## frozen). Loaded on first use. The trip tier rule mirrors the server's (§11.2.1 + §11.2.3); the server's preview
## and arrival carry the authoritative tier, this one is for browsing (silhouette cards, lists) before any request.

const PATH := "res://assets/p0/city_clusters.json"
## Trip n is ≤ TRIP_KM[n - 1] km; beyond the last is Trip 7 (§11.2.1).
const TRIP_KM := [30.0, 100.0, 500.0, 1600.0, 4000.0, 10000.0]
const TRIP_NAMES := ["Local", "Nearby", "Regional", "Long Haul", "Continental", "Intercontinental", "Antipodal"]
const CELL := 1.0   # degrees, for nearest lookups

static var _by_id: Dictionary = {}
static var _list: Array = []
static var _grid: Dictionary = {}

static func _load() -> void:
	if not _by_id.is_empty(): return
	var table = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (table is Dictionary): return
	var f: Array = table.get("fields", [])
	var col := {}
	for i in f.size(): col[f[i]] = i
	for r in table.get("rows", []):
		var c := {}
		for k in col: c[k] = r[col[k]]
		c.population = int(c.population)
		c.members = int(c.members)
		_by_id[c.id] = c
		_list.append(c)
		var k := _cell(float(c.lat), float(c.lng))
		if not _grid.has(k): _grid[k] = []
		_grid[k].append(c)

static func _cell(lat: float, lng: float) -> Vector2i: return Vector2i(floori(lat / CELL), floori(lng / CELL))

static func count() -> int:
	_load()
	return _by_id.size()

## {id, name, lat, lng, country_code, country, population, members, climate, continent, timezone}, or {} if unknown.
static func get_cluster(id: String) -> Dictionary:
	_load()
	return _by_id.get(id, {})

## All clusters, most populous first (the order of the file).
static func all() -> Array:
	_load()
	return _list

static func distance_km(lat_a: float, lng_a: float, lat_b: float, lng_b: float) -> float:
	var d_lat := deg_to_rad(lat_b - lat_a)
	var d_lng := deg_to_rad(lng_b - lng_a)
	var h := sin(d_lat / 2.0) ** 2 + cos(deg_to_rad(lat_a)) * cos(deg_to_rad(lat_b)) * sin(d_lng / 2.0) ** 2
	return 2.0 * 6371.0 * asin(minf(1.0, sqrt(h)))

static func trip_by_km(km: float) -> int:
	for i in TRIP_KM.size():
		if km <= TRIP_KM[i]: return i + 1
	return 7

## The tier to `to` from the home farm `farm` (Vector2 lat, lng): by distance, then the lower of that and the frozen
## fallback lists (view.travel.fallback: near3 → Trip 1, near10 → at most Trip 2). The home cluster is Trip 1.
## {km, trip, name}; {} for an unknown cluster.
static func trip(to: String, home: String, farm: Vector2, fallback: Dictionary = {}) -> Dictionary:
	var c := get_cluster(to)
	if c.is_empty(): return {}
	var km := 0.0 if to == home else distance_km(farm.x, farm.y, c.lat, c.lng)
	var t := 1 if to == home else trip_by_km(km)
	if (fallback.get("near3", []) as Array).has(to): t = 1
	elif (fallback.get("near10", []) as Array).has(to): t = mini(t, 2)
	return {km = roundi(km), trip = t, name = TRIP_NAMES[t - 1]}

## The cluster whose centre is nearest a point, within `max_km` ("" when none): the city the map camera is over.
static func nearest(lat: float, lng: float, max_km := 60.0) -> String:
	_load()
	var at := _cell(lat, lng)
	var best := ""
	var best_km := max_km
	var span := ceili(max_km / (111.0 * CELL * maxf(0.1, cos(deg_to_rad(lat))))) + 1
	for di in range(-1, 2):
		for dj in range(-span, span + 1):
			for c in _grid.get(at + Vector2i(di, dj), []):
				var d := distance_km(lat, lng, c.lat, c.lng)
				if d < best_km or (d == best_km and best != "" and str(c.id) < best):
					best_km = d
					best = c.id
	return best
