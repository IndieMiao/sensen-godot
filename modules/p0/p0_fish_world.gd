extends RefCounted
## Fishing part 2 (SGODOT-283, plan §6.2.5–6.2.7, 李白 q(109)): the client's copy of server/src/p0/fishing_world.ts —
## a pond's time of day, today's weather in its city, the city's 2 regional fish and the fish it can give. The server's
## view carries daypart / weather / fish for every pond it knows (view.fishing.places); this works the same answers out
## for places the view does not hold (another city's silhouette card, the 3-day forecast). tests/p0/test_p0_fish_world.gd
## checks it against the server's frozen vectors (server/test/p0/p1_fishing.test.ts).

const HOME_ALIAS := {"san francisco": "gn-5391959", "shanghai": "gn-1796236", "los angeles": "gn-5368361"}
const WEATHERS := ["sun", "rain", "wind"]
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const WEATHER_NAMES := {"sun": "Sunny", "rain": "Rain", "wind": "Windy"}
const DAYPART_NAMES := {"day": "Day", "dawn_dusk": "Dawn", "night": "Night"}

static func _rules() -> Dictionary: return P0Logic.content().get("fishing", {}).get("regional", {})
static func _seed() -> String: return str(_rules().get("seed", "gensen"))

## A [0, 1) number from a key, as the server's hash01 (sha256's first 4 bytes, big-endian).
static func hash01(key: String) -> float:
	var hex := key.sha256_text().substr(0, 8)
	return float(hex.hex_to_int()) / 4294967296.0

## §6.2.7: one weather per city per day, the same for everyone.
static func weather_on(cluster: String, date: String) -> String:
	var odds: Dictionary = _rules().get("weather", {}).get("odds", {"sun": 50, "rain": 30, "wind": 20})
	var total := 0.0
	for w in WEATHERS: total += float(odds.get(w, 0))
	var roll := hash01("%s:weather:%s:%s" % [_seed(), cluster, date]) * total
	for w in WEATHERS:
		roll -= float(odds.get(w, 0))
		if roll < 0: return w
	return "sun"

static func _title(s: String) -> String: return s.substr(0, 1).to_upper() + s.substr(1).to_lower() if s != "" else s

## §6.2.5: the city's 2 regional fish — hand-picked cities keep theirs; elsewhere the first from the climate's low tier
## (only fish in a Pond all day), the second from the rest, by a hash of the cluster id.
static func regional_fish(cluster: String) -> Array:
	var r := _rules()
	if r.is_empty(): return []
	var cl := P0Clusters.get_cluster(cluster)
	for city in r.get("curated", {}):
		if str(HOME_ALIAS.get(city, "city:" + str(city))) == cluster or str(cl.get("name", "")).to_lower() == str(city):
			return (r.curated[city] as Array).duplicate()
	var g: Dictionary = r.get("groups", {}).get(_title(str(cl.get("climate", ""))), {})
	if g.is_empty(): return []
	var firsts: Array = (g.get("low", []) as Array).filter(func(id): return _pond_all_day(_fish(str(id))))
	if firsts.is_empty(): return []
	var first: String = firsts[int(floor(hash01("%s:regional:%s:1" % [_seed(), cluster]) * firsts.size()))]
	var rest: Array = ((g.get("low", []) as Array) + (g.get("high", []) as Array)).filter(func(id): return str(id) != first)
	if rest.is_empty(): return [first]
	return [first, str(rest[int(floor(hash01("%s:regional:%s:2" % [_seed(), cluster]) * rest.size()))])]

static func _fish(id: String) -> Dictionary:
	for f in P0Logic.content().get("fish", []):
		if str(f.get("id", "")) == id: return f
	return {}

static func _pond_all_day(f: Dictionary) -> bool:
	return not f.is_empty() and (f.get("where", []) as Array).has("pond") and not (f.get("time", null) is String)

## In the pool at this time of day at all.
static func bites_at(f: Dictionary, part: String) -> bool:
	var t = f.get("time", null)
	if t is String:
		return (t == "night_only" and part == "night") or (t == "dawn_dusk_only" and part == "dawn_dusk")
	return true

## §6.2.6: the pond's fish by rarity tier (index 0 = Common), each {fish, weight}.
static func pool(template: String, cluster: String, part: String, weather: String, regional_mult := 1.0) -> Array:
	var where := template.to_lower()
	var mine := regional_fish(cluster)
	var tiers: Array = [[], [], [], []]
	for f in P0Logic.content().get("fish", []):
		var regional := bool(f.get("regional", false))
		if not (f.get("where", []) as Array).has(where): continue
		if regional and not mine.has(str(f.id)): continue
		if not bites_at(f, part): continue
		var w := (2.0 * regional_mult if regional else 1.0)
		var t = f.get("time", null)
		if t is Dictionary and part != "day": w *= float(t.get(part, 1))
		w *= float(f.get("weather", {}).get(weather, 1))
		var tier := int(f.get("rarity", 1)) - 1
		if tier >= 0 and tier < tiers.size(): tiers[tier].append({"fish": f, "weight": w})
	return tiers

## Every fish a pond can ever give (any time, any weather), easiest first.
static func ever_fish(template: String, cluster: String) -> Array:
	var where := template.to_lower()
	var mine := regional_fish(cluster)
	return P0Logic.content().get("fish", []).filter(func(f):
		return (f.get("where", []) as Array).has(where) and (not bool(f.get("regional", false)) or mine.has(str(f.id))))

## The pond card's line for now (the view's daypart / weather): `Night · Rain`.
static func now_line(place: Dictionary) -> String:
	var part := str(place.get("daypart", ""))
	var weather := str(place.get("weather", ""))
	if part == "" or weather == "": return ""
	return "%s · %s" % [DAYPART_NAMES.get(part, part), WEATHER_NAMES.get(weather, weather)]
