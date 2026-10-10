extends RefCounted
## The P0 home city (SGODOT-270: San Francisco from 2026-10-09, was Shanghai), read from content.profile so moving the
## whole server to another city is a data change: the place chip's `San Francisco · …`, the map's region, the beginner
## pond, the homestead's map point and the keepers' "around San Francisco". Every P0 player shares it (P0 has one home
## city; choosing one is P1). Preloaded, no class_name (a new global class needs an editor import).

## "San Francisco".
static func city_name() -> String:
	return str(_profile().get("city", "San Francisco"))

## The map region and city-data id ("san_francisco": regions.json, assets/map/cities/<id>.json, catalog region_id).
static func region() -> String:
	return str(_profile().get("region", city_name().to_lower().replace(" ", "_")))

## The beginner pond Today and the first session point at (q(32): Fern Pond in San Francisco): content.fishing.places'
## beginner one, as the server's markers pick it (周瑜 on 270: one source).
static func beginner_pond() -> String:
	var places: Dictionary = P0Logic.content().get("fishing", {}).get("places", {})
	for id in places:
		if bool((places[id] as Dictionary).get("beginner", false)): return str(id)
	return ""

## The homestead's map point (lat, lng).
static func farm_at() -> Vector2:
	var at: Array = _profile().get("farm_at", [])
	return Vector2(float(at[0]), float(at[1])) if at.size() >= 2 else Vector2.ZERO

## The short form for a chip that cannot hold the full name ("SF", q(106); profile.city_short, else the full name).
## Which chips use it is 刘邦's measurement (q(106)): the place itself is never cut.
static func short_name() -> String:
	return str(_profile().get("city_short", city_name()))

## "San Francisco · Homestead": the place chip, the loading cover's destination. profile.chip_city, when the content sets
## it, is the city every chip writes (不知火舞 on 270 asks for "SF" on all of them, pending 李白); short = the short form.
static func chip(place: String, short := false) -> String:
	var city := short_name() if short else str(_profile().get("chip_city", city_name()))
	return "%s · %s" % [city, place]

## "Tokyo · Tokyo Market Square": a place of another city (a generated id `gn-1850147~market0`, SGODOT-280) names its
## own city; a home place names home as chip() does. The place chip keeps the space for a place of the city the player
## arrived in (P0Travel.place).
static func chip_for(place: String, id: String) -> String:
	var cut := id.find("~")
	if cut <= 0: return chip(place)
	var c: Dictionary = load("res://modules/p0/p0_clusters.gd").get_cluster(id.substr(0, cut))
	return "%s · %s" % [str(c.get("name", city_name())), place] if not c.is_empty() else chip(place)

static func _profile() -> Dictionary:
	return P0Logic.content().get("profile", {})
