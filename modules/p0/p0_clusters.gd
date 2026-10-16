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
	# A cluster's display name (content travel.cluster_names, as the server's loader): the id stays frozen
	var names: Dictionary = (P0Logic.content().get("travel", {}) as Dictionary).get("cluster_names", {})
	# q(189): a closed country's cities (content travel.closed_countries, as the server's loader) are not in the table:
	# no bubble, search hit, nearest city or Nearby row
	var closed: Array = (P0Logic.content().get("travel", {}) as Dictionary).get("closed_countries", [])
	for r in table.get("rows", []):
		var c := {}
		for k in col: c[k] = r[col[k]]
		if closed.has(str(c.get("country_code", ""))): continue
		c.population = int(c.population)
		c.members = int(c.members)
		if names.has(c.id): c.name = str(names[c.id])
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

## A city's country as the game writes it (q(210), the server's home.ts countryPart): Unicode CLDR's English name by its
## code (content travel.country_names), "" for a place whose cities read their name alone (travel.city_only_countries:
## Hong Kong, Macao, Taiwan, the Palestinian Territories, Kosovo, Western Sahara) and when the city's name already holds
## the country's as a whole word (q(209) ②: `Mexico City`, `Singapore`).
static func country_part(c: Dictionary) -> String:
	var travel: Dictionary = P0Logic.content().get("travel", {})
	var code := str(c.get("country_code", ""))
	if code in travel.get("city_only_countries", []): return ""
	var name := str((travel.get("country_names", {}) as Dictionary).get(code, c.get("country", "")))
	return "" if names_country(str(c.get("name", "")), name) else name

## Whether `city` holds `country` as a whole word: no letter right before or after it (`Iranshahr` does not hold Iran).
static func names_country(city: String, country: String) -> bool:
	if country == "": return false
	var from := 0
	while true:
		var at := city.find(country, from)
		if at < 0: return false
		var before := city.substr(at - 1, 1) if at > 0 else ""
		var after := city.substr(at + country.length(), 1)
		if not _letter(before) and not _letter(after): return true
		from = at + 1
	return false

static func _letter(ch: String) -> bool:
	return ch != "" and ch.to_upper() != ch.to_lower()

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

# ---------------------------------------------------------------- the map's regions (SGODOT-275 browse)

## The curated map regions (regions.json, with their own city files) by the cluster they alias (geonames_id).
static var _curated: Dictionary = {}

static func _curated_regions() -> Dictionary:
	if _curated.is_empty():
		var regions := FarmRegions.load_default()
		if regions != null:
			for r in regions.regions:
				if str(r.get("geonames_id", "")) != "": _curated[str(r.geonames_id)] = r
	return _curated

## The cluster a map region id stands for: a curated region by its geonames_id (san_francisco → gn-5391959), a
## cluster id as itself; "" for anything else.
static func cluster_of_region(region_id: String) -> String:
	var curated := _curated_regions()
	for id in curated:
		if str(curated[id].id) == region_id: return id
	return region_id if not get_cluster(region_id).is_empty() else ""

## A cluster's radius as the city directory sizes cities (server/tools/build_cities.mjs radiusKm).
static func radius_km(population: int) -> float:
	return 45.0 if population >= 5000000 else 30.0 if population >= 1000000 else 20.0 if population >= 300000 else 12.0

## The map region a cluster is shown as: its curated region where there is one (its authored city, landmarks), else
## a region built from the cluster (centre, radius, bounds of one radius around it) with the cluster id as its id.
static func region(cluster: String) -> Dictionary:
	if _curated_regions().has(cluster): return _curated_regions()[cluster]
	var c := get_cluster(cluster)
	if c.is_empty(): return {}
	var r := radius_km(int(c.population))
	var dlat := r / 111.0
	var dlng := r / (111.0 * maxf(0.1, cos(deg_to_rad(float(c.lat)))))
	return {id = cluster, name = c.name, timezone = c.timezone, center = [c.lat, c.lng], radius_km = r,
		placement_bounds = [c.lat - dlat, c.lng - dlng, c.lat + dlat, c.lng + dlng], street_zoom = 16, pitch = 45,
		candidates = [], country = c.country, country_code = c.country_code, global = true, cluster = cluster}

## Clusters whose centre is inside a lat/lng box, most populous first, at least `min_pop` people, at most `limit`.
## Wide boxes walk the population-ordered list and stop at `min_pop`; narrow ones read the grid cells.
static func in_box(south: float, west: float, north: float, east: float, min_pop: int, limit: int) -> Array:
	_load()
	var out: Array = []
	var inside := func(c: Dictionary) -> bool:
		var lat := float(c.lat)
		var lng := float(c.lng)
		var in_lng := (lng >= west and lng <= east) if west <= east else (lng >= west or lng <= east)
		return lat >= south and lat <= north and in_lng
	var width := 360.0 if east == west else east - west + (360.0 if east < west else 0.0)   # the whole world: west -180, east 180
	if (north - south) * width > 400.0:
		for c in _list:
			if int(c.population) < min_pop: break
			if inside.call(c): out.append(c)
			if out.size() >= limit: break
		return out
	var a := _cell(south, west)
	var b := _cell(north, east if east >= west else east + 360.0)
	for i in range(a.x, b.x + 1):
		for j in range(a.y, b.y + 1):
			for c in _grid.get(Vector2i(i, wrapi(j, -180, 180)), []):
				if int(c.population) >= min_pop and inside.call(c): out.append(c)
	out.sort_custom(func(x, y): return int(x.population) > int(y.population) or (int(x.population) == int(y.population) and str(x.id) < str(y.id)))
	return out.slice(0, limit)
