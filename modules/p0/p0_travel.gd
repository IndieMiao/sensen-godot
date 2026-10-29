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
	return h if h != "" else written()

## The cluster the player is in (arrived there or at home).
static func here(view: Dictionary) -> String:
	var t: Dictionary = view.get("travel", {})
	var h := str(t.get("here", ""))
	return h if h != "" else home(view)

## The written city's cluster (San Francisco): its places are the client's hand-written tables, never read from the
## server; any other home's are generated (P0CityPlaces).
static func written() -> String:
	return P0Clusters.cluster_of_region(P0City.region())

static func home_is_written(view: Dictionary) -> bool:
	return home(view) == written()

## The home city's name (view.home.name, SGODOT-303), the written city's where the view has none.
static func home_name(view: Dictionary) -> String:
	var h = view.get("home", null)
	var n := str((h as Dictionary).get("name", "")) if h is Dictionary else ""
	if n != "": return n
	if not home_is_written(view):
		var cl := P0Clusters.get_cluster(home(view))
		if not cl.is_empty(): return str(cl.name)
	return P0City.city_name()

## The farm's point on the map (view.home.farm, the spot picked with the home), the written city's content point
## where the view has none.
static func home_farm(view: Dictionary) -> Vector2:
	var h = view.get("home", null)
	var f = (h as Dictionary).get("farm", null) if h is Dictionary else null
	if f is Dictionary and f.has("lat") and f.has("lng"): return Vector2(float(f.lat), float(f.lng))
	return P0City.farm_at()

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
		# a city the table does not have (a closed country's, q(189)) opens no fog
		if not out.has(str(c)) and not P0Clusters.get_cluster(str(c)).is_empty(): out.append(str(c))
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
	if not away(view) or space in HOMESTEAD_SPACES: return home_chip(view, info)
	var c := P0Clusters.get_cluster(here(view))
	var out := info.duplicate()
	var city := str(c.name) if not c.is_empty() else str(info.get("city", ""))
	if str(info.get("city", "")) != city: out["space"] = "Arrived"
	out["city"] = city
	out["kind"] = UiHud.PlaceKind.FOREIGN
	out["day_pass"] = ""
	return out

## At home the scenes write the written city into their chip (P0City.chip: `San Francisco · Homestead`); a generated
## home's chip names that home instead (SGODOT-311: `Tokyo · Homestead`). Another city's own place keeps its name.
static func home_chip(view: Dictionary, info: Dictionary) -> Dictionary:
	var city := str(info.get("city", ""))
	if home_is_written(view) or not (city == P0City.city_name() or city == P0City.short_name()): return info
	var out := info.duplicate()
	out["city"] = home_name(view)
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

## q(184): the home's base point Trip distances are measured from — the written city's content point (San Francisco's
## Noe Valley), another home's cluster centre; the picked farm spot only places the home pin (the server's homeBase).
static func home_base(view: Dictionary) -> Vector2:
	var h := home(view)
	if h == P0Clusters.cluster_of_region(P0City.region()): return P0City.farm_at()
	var cl := P0Clusters.get_cluster(h)
	return Vector2(float(cl.lat), float(cl.lng)) if not cl.is_empty() else P0City.farm_at()

## The trip tier to a cluster from the home's base point, for browsing (the server's preview is authoritative).
static func trip(view: Dictionary, cluster: String) -> Dictionary:
	return P0Clusters.trip(cluster, home(view), home_base(view), view.get("travel", {}).get("fallback", {}))

# ---------------------------------------------------------------- fares (q(256) / q(257), SGODOT-367)
## Every coin spend but seeds keeps this much in the wallet (§8.1.1, the server's content.wallet_floor).
const WALLET_FLOOR := 40

## q(256) ①: the seven tiers' first-visit fares, Trip 1 first — view.travel.fares, the server's content table
## ({energy: [0, 10, …], coins: [0, 20, …]}); a server from before sends none: every trip is free there.
static func fare_table(view: Dictionary) -> Dictionary:
	var t = view.get("travel", {}).get("fares", {})
	return t if t is Dictionary and t.get("energy") is Array and t.get("coins") is Array else {}

## What going to a cluster costs now (q(256), the server's fareOf: its preview and the travel reply settle it): the
## trip tier's fare (the frozen fallback in the tier: the 3 nearest cities are Trip 1, free), each half rounded up on a
## return (visited before); nothing home or where the player already is with a running pass. {energy, coins, revisit,
## free (nothing to pay), pass_ms (ms left on a running pass: no new pass, no visit counted, q(256) ②)}.
static func fare(view: Dictionary, cluster: String) -> Dictionary:
	var revisit := visits(view, cluster) > 0
	var out := {energy = 0, coins = 0, revisit = revisit, free = true, pass_ms = pass_left_ms(view, cluster)}
	var table := fare_table(view)
	if table.is_empty() or cluster == home(view) or (cluster == here(view) and covers(view, cluster)): return out
	var i := clampi(int(trip(view, cluster).get("trip", 1)) - 1, 0, (table.energy as Array).size() - 1)
	var e := int(table.energy[i])
	var c := int(table.coins[mini(i, (table.coins as Array).size() - 1)])
	if revisit:
		e = ceili(e / 2.0)
		c = ceili(c / 2.0)
	out.merge({energy = e, coins = c, free = e == 0 and c == 0}, true)
	return out

## q(257) ③ (LOCK-10): what Fly says when the fare cannot be paid — the coins first (`Need 10 more coins`: fare + the
## 40 floor − the wallet), else the Energy (`Need 11 more Energy`); {} when it can. {text, short ("coins" / "energy"),
## need}.
static func fare_gap(view: Dictionary, f: Dictionary) -> Dictionary:
	var coins := int(view.get("coins", 0))
	if int(f.coins) > 0 and coins < int(f.coins) + WALLET_FLOOR:
		var need := int(f.coins) + WALLET_FLOOR - coins
		return {text = "Need %d more coins" % need, short = "coins", need = need}
	var energy := int(view.get("energy", {}).get("value", 0))
	if int(f.energy) > energy:
		var need := int(f.energy) - energy
		return {text = "Need %d more Energy" % need, short = "energy", need = need}
	return {}

# ---------------------------------------------------------------- the Travel Post's Fare Board (q(165))
## q(165) Trip fares (§9.11.4 / §17.3.1, read only): the seven tiers in order, each {title `Trip 1 · Local`, line its
## bounds (§11.1 — `Up to 30 km, or the 3 nearest cities`, `Up to 100 km, or the 10 nearest cities` with the frozen
## fallback lists of §11.2.3, … `Over 10,000 km`), fare}. Travel is free in P2's first version, every fare `Free`; its
## costs come here when they do.
static func fares() -> Array:
	var km: Array = P0Clusters.TRIP_KM
	var nearest := {0: 3, 1: 10}   # Trip 1: near3, Trip 2: near10
	var out := []
	for i in P0Clusters.TRIP_NAMES.size():
		var line := ("Up to %s km" % grouped(int(km[i]))) if i < km.size() else ("Over %s km" % grouped(int(km[-1])))
		if nearest.has(i): line += ", or the %d nearest cities" % int(nearest[i])
		out.append({title = "Trip %d · %s" % [i + 1, P0Clusters.TRIP_NAMES[i]], line = line, fare = "Free"})
	return out

# ---------------------------------------------------------------- Nearby cities (MAP-8)
## MAP-8 Nearby cities (§11.8.1; the user on 10-13: this one page, the other three come with P2): the ten clusters
## nearest home that the save froze (travel.fallback.near10, §11.2.3), nearest first. Each row: {cluster, name,
## region (the row's second part as the server writes it, travel.regions, q(208) ①: a US city's state `Salinas ·
## California`, elsewhere the country `Tokyo · Japan`, none when it is the city's own name, a province for one of two
## same-named cities; a server from before: travel.admins, else the country as P0Clusters.country_part writes it), km, trip, trip_name (the tier's name: Nearby, Regional …), climate ("Temperate"), visited,
## stamped, landmark (the city's landmark stamp art, "" for none: the row shows its climate band instead)}.
static func nearby(view: Dictionary) -> Array:
	var stamped := {}
	for st in stamps(view): stamped[str(st.get("cluster", ""))] = true
	var admins: Dictionary = view.get("travel", {}).get("admins", {})
	var regions: Dictionary = view.get("travel", {}).get("regions", {})
	var rows: Array = []
	for id in view.get("travel", {}).get("fallback", {}).get("near10", []):
		var c := str(id)
		var cl := P0Clusters.get_cluster(c)
		if cl.is_empty(): continue
		var t := trip(view, c)
		rows.append({cluster = c, name = str(cl.get("name", "")), region = str(regions[c] if regions.has(c) else admins.get(c, P0Clusters.country_part(cl))),
			km = int(t.get("km", 0)), trip = int(t.get("trip", 0)), trip_name = str(t.get("name", "")),
			climate = str(cl.get("climate", "")).capitalize(), visited = visits(view, c) > 0, stamped = stamped.has(c),
			landmark = landmark_stamp(c)})
	rows.sort_custom(func(a, b): return a.km < b.km if a.km != b.km else a.cluster < b.cluster)
	return rows

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
		if c == h or P0Clusters.get_cluster(str(c)).is_empty(): continue   # a closed country's city is not shown or counted (q(189))
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
				facts = [["Visits", "%d/%d" % [mini(n, LOCAL_VISITS), LOCAL_VISITS]]]},   # as the progress above (不知火舞 on #256)
		]}
