extends RefCounted
## Where the player is in the world and what their travel has left (SGODOT-275, plan v2 §11; 亚瑟's cross-city plan
## on 275, v1.1): reads view.travel {home, here, passes, visits, stamps, fallback, explorer} as the server sends it.
## A view without it (a server before v5) is at home in the home city. Pure and static: tested headless.

const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const P0City := preload("res://modules/p0/p0_city.gd")

## The home cluster: the save's, else the content's home city (San Francisco).
static func home(view: Dictionary) -> String:
	var t: Dictionary = view.get("travel", {})
	var h := str(t.get("home", ""))
	return h if h != "" else P0Clusters.cluster_of_region(P0City.region())

## The cluster the player is in (arrived there or at home).
static func here(view: Dictionary) -> String:
	var t: Dictionary = view.get("travel", {})
	var h := str(t.get("here", ""))
	return h if h != "" else home(view)

static func away(view: Dictionary) -> bool:
	return here(view) != home(view)

## The server's clock for the view (ms), for pass countdowns.
static func now_ms(view: Dictionary) -> float:
	return float(view.get("now", Time.get_unix_time_from_system() * 1000.0))

## ms left on the Day Pass for a cluster; 0 for the home city (it needs none) and for none or an expired one.
static func pass_left_ms(view: Dictionary, cluster: String) -> float:
	if cluster == home(view): return 0.0
	var p: Dictionary = view.get("travel", {}).get("passes", {}).get(cluster, {})
	return maxf(0.0, float(p.get("until", 0)) - now_ms(view))

## Whether the player may go in there now: the home city, or a Day Pass still running (§11.7.3).
static func covers(view: Dictionary, cluster: String) -> bool:
	return cluster == home(view) or pass_left_ms(view, cluster) > 0.0

## §11.7.1 fog's three states: "second_home" for a city set as one (travel.second_homes, P2's second version sets
## them; the client already draws the state), "explored" once visited or the home city, else "unexplored".
static func fog(view: Dictionary, cluster: String) -> String:
	if (view.get("travel", {}).get("second_homes", []) as Array).has(cluster): return "second_home"
	if cluster == home(view): return "explored"
	return "explored" if view.get("travel", {}).get("visits", {}).has(cluster) else "unexplored"

## Every city out of the fog: home, the visited and the second homes (no repeats).
static func explored(view: Dictionary) -> Array:
	var out: Array = [home(view)]
	var t: Dictionary = view.get("travel", {})
	for c in t.get("visits", {}).keys() + (t.get("second_homes", []) as Array):
		if not out.has(str(c)): out.append(str(c))
	return out

static func visits(view: Dictionary, cluster: String) -> int:
	return int(view.get("travel", {}).get("visits", {}).get(cluster, {}).get("n", 0))

static func stamps(view: Dictionary) -> Array:
	return view.get("travel", {}).get("stamps", [])

## The Day Pass on the place chip: "23h" / "47m" while it runs, "" otherwise (LOCK-06: Tokyo · Arrived · Day Pass 23h).
static func pass_text(view: Dictionary, cluster: String) -> String:
	var ms := pass_left_ms(view, cluster)
	if ms <= 0.0: return ""
	var minutes := ceili(ms / 60000.0)
	return "%dh" % ceili(minutes / 60.0) if minutes >= 60 else "%dm" % minutes

## The place chip while away (LOCK-06): the arrived city's name and Foreign (Tokyo · Arrived). The free first version
## shows no Day Pass (q(108), pending the user: the server still issues one, an expired one only brings back the free
## confirm panel); pass_text is kept for the paid version. At home the scene's own "City · Space" stands. `info` is
## P0Logic.place_info's {city, space, kind, day_pass}.
## A scene of the home city ("San Francisco · Homestead" on the map) is not where an arrived player is: away, the chip
## reads "<City> · Arrived" until they go into a space of that city (whose own chip names its city).
## The homestead's own spaces (the farm, its farmhouse and kitchen, the mine) are always home, whatever `here` still
## says: on a cold start the first read goes out before the farm is attached, so the server's `here` can lag one read
## (李元芳, SGODOT-278; the server settles it on the next read, #233).
const HOMESTEAD_SPACES := ["home", "mine"]

static func place(view: Dictionary, info: Dictionary, space := "") -> Dictionary:
	if not away(view) or space in HOMESTEAD_SPACES: return info
	var c := P0Clusters.get_cluster(here(view))
	var out := info.duplicate()
	var city := str(c.name) if not c.is_empty() else str(info.get("city", ""))
	if str(info.get("city", "")) != city: out["space"] = "Arrived"
	out["city"] = city
	out["kind"] = UiHud.PlaceKind.FOREIGN
	out["day_pass"] = ""
	return out

## "1,758" (km on the travel card).
static func grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## "1,758 km · Trip 5 · Continental" (§11.8.2); the home city: "Your home city".
static func trip_line(trip_info: Dictionary) -> String:
	if trip_info.is_empty() or int(trip_info.get("km", 0)) == 0: return "Your home city"
	return "%s km · Trip %d · %s" % [grouped(int(trip_info.km)), int(trip_info.trip), str(trip_info.name)]

## The arrival flight's length by tier (§11.8.4: Trip 1–3 3 s, 4–5 4 s, 6–7 5 s).
static func flight_s(trip: int) -> float:
	return 3.0 if trip <= 3 else 4.0 if trip <= 5 else 5.0

## The trip tier to a cluster from the home farm, for browsing (the server's preview is authoritative).
static func trip(view: Dictionary, cluster: String) -> Dictionary:
	return P0Clusters.trip(cluster, home(view), P0City.farm_at(), view.get("travel", {}).get("fallback", {}))

# ---------------------------------------------------------------- Passport (PASS-1) and a city's page (PASS-2)
## §11.9.1 three tiers by cluster: Visited (a first visit), Regular (≥ 5 visits and ≥ 3 local deliveries), Local (≥ 10
## visits, both regional fish caught, a regional recipe learned). The server counts visits and deliveries (visits[c]).
const REGULAR_VISITS := 5
const REGULAR_TRADES := 3
const LOCAL_VISITS := 10
const FIRST_VISITS_PER_DAY := 2

## "Visited" / "Regular" / "Local" by the counts the client has ("" for a city never reached). Local also needs the
## regional fish and recipe, which this version does not track: it stops at Regular.
static func tier(view: Dictionary, cluster: String) -> String:
	var v: Dictionary = view.get("travel", {}).get("visits", {}).get(cluster, {})
	if v.is_empty(): return ""
	if int(v.get("n", 0)) >= REGULAR_VISITS and int(v.get("deliveries", 0)) >= REGULAR_TRADES: return "Regular"
	return "Visited"

## Stamps counted on the server's today (two a day count, §11.9.2): the Passport's "First visits today 1/2".
static func first_visits_today(view: Dictionary) -> int:
	var today := str(view.get("travel", {}).get("today", ""))
	if today == "": return 0
	return stamps(view).filter(func(s): return str(s.get("counted_on", "")) == today).size()

## PASS-1 (Figma 482:429): {title, state, effect, facts, rows: home first, then the visited cities newest first}.
## Each row: {cluster, icon, title, state, effect}; the stamp art is the landmark's (travel.landmarks) when there is one.
static func passport(view: Dictionary) -> Dictionary:
	var h := home(view)
	var visits: Dictionary = view.get("travel", {}).get("visits", {})
	var order: Array = visits.keys()
	order.sort_custom(func(a, b): return float(visits[a].get("first_at", 0)) > float(visits[b].get("first_at", 0)))
	var rows: Array = [{cluster = h, icon = "home", title = str(P0Clusters.get_cluster(h).get("name", "")), state = "Home",
		effect = "Your home city"}]
	for c in order:
		if c == h: continue
		var t := tier(view, c)
		rows.append({cluster = c, icon = "stamp", stamp = landmark_stamp(c),   # PASS-1: i-stamp (431:318), the landmark art when it has one
			title = str(P0Clusters.get_cluster(c).get("name", "")), state = t,
			effect = "A new connection" if t == "Visited" else "A regular here"})
	return {title = "Passport", state = "Collection", effect = "Browse your visited cities and stamps.",
		facts = [["Cities visited", str(rows.size())], ["First visits today", "%d/%d" % [first_visits_today(view), FIRST_VISITS_PER_DAY]]],
		rows = rows}

## The landmark stamp's art for a cluster (content travel.landmarks: res://assets/p0/stamps/<stamp>.png), "" for a
## climate stamp.
static func landmark_stamp(cluster: String) -> String:
	var l: Dictionary = P0Logic.content().get("travel", {}).get("landmarks", {}).get(cluster, {})
	return "res://assets/p0/stamps/%s.png" % str(l.stamp) if l.has("stamp") else ""

## PASS-2 (Figma 482:431): a visited city's three tiers — Visited (Complete), Regular (visits 1/5, local trades 0/3),
## Local (visits needed 10).
static func city_page(view: Dictionary, cluster: String) -> Dictionary:
	var v: Dictionary = view.get("travel", {}).get("visits", {}).get(cluster, {})
	var n := int(v.get("n", 0))
	var trades := int(v.get("deliveries", 0))
	var regular := tier(view, cluster) == "Regular"
	return {title = str(P0Clusters.get_cluster(cluster).get("name", "")), state = tier(view, cluster) if not v.is_empty() else "Unexplored",
		effect = "Build your connection with this city.",
		facts = [["Visits", "%d/%d" % [mini(n, REGULAR_VISITS), REGULAR_VISITS]], ["Local trades", "%d/%d" % [mini(trades, REGULAR_TRADES), REGULAR_TRADES]]],
		rows = [
			{icon = "stamp", stamp = landmark_stamp(cluster), title = "Visited", state = "Complete" if not v.is_empty() else "",
				effect = "Your stamp has been collected" if not v.is_empty() else "Travel here to collect its stamp"},
			{icon = "home", title = "Regular", state = "Complete" if regular else "", effect = "Keep visiting and trading",
				facts = [] if regular else [["Visits", "%d/%d" % [mini(n, REGULAR_VISITS), REGULAR_VISITS]], ["Local trades", "%d/%d" % [mini(trades, REGULAR_TRADES), REGULAR_TRADES]]]},
			{icon = "fish", title = "Local", state = "", effect = "Catch both regional fish and learn a regional recipe",
				facts = [["Visits needed", str(LOCAL_VISITS)]]},
		]}
