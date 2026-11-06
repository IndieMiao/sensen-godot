extends RefCounted
## The Homestead Stall's Notice Board (§9.3.1, §8.3.1 Lv5; 李白 q(164), 不知火舞's spec on SGODOT-284): from Homestead
## Lv5 a board by the stall, tap-triggered, read-only — `Notice Board` / `<home city> · Today · tap a place to see it on
## the map`, a `Ponds` section (each home pond by its short name (q(137)) with today's best bite, as the Bite Board's
## keeper line (q(119)) without its bait, and the player's trap in it as `2/3`; the beginner pond first, the rest
## nearest the homestead first) and an `Outposts` section (each home outpost by its short name, its kind or the reason
## its pin is marked (q(103)), and who is in, none at 0 (q(72)); market, tea house, tackle shop, travel post, then any
## other nearest first). A tap on a row flies the map to that pin and moves nobody (q(31), k(1)). Built from the view
## and the presence counts the map already polls: no server field. Home is the player's own (view.home, SGODOT-303).
## Pure and static. Preloaded, no class_name (as P0City).

const Board := preload("res://modules/p0/p0_bite_board.gd")
const Ponds := preload("res://modules/p0/p0_ponds.gd")
const Map := preload("res://scenes/p0/p0_map.gd")
const P0City := preload("res://modules/p0/p0_city.gd")

const ROLE_ORDER := ["market", "tea", "tackle", "post"]   # the home set's four, in this order (不知火舞)
## Places that post nothing: the card room (SGODOT-351) and Grace Cathedral (SGODOT-423, 后裔's #800: a place to see).
const QUIET_ROLES := ["casino", "church"]

## Homestead Lv5 brings the board (view.homestead.unlocks.notice_board).
static func unlocked(view: Dictionary) -> bool:
	return bool(view.get("homestead", {}).get("unlocks", {}).get("notice_board", false))

## {title, subtitle, ponds: [{id, name, icon, line, reason, trap, go}], outposts: [{id, name, icon, line, reason, online, go}]};
## `online` is the presence count per outpost id (all its rooms), as the map holds it. `trap` is `2/3` or "";
## `reason` is PinReason.reason (its `text` is then the line), {} when the pin wears no mark.
static func model(view: Dictionary, online: Dictionary = {}) -> Dictionary:
	var level := int(view.get("skills", {}).get("fishing", {}).get("level", 1))
	var caught: Dictionary = view.get("fishing", {}).get("caught", {})
	var places: Dictionary = view.get("fishing", {}).get("places", {})
	var h := home(view)
	var at: Vector2 = h.farm
	var beginner := str(h.set.get("pond", P0City.beginner_pond()))
	var ponds: Array = []
	for p in Ponds.all():
		var id := str(p.get("id", ""))
		# the home city's ponds the view knows (a generated home's are not in view.fishing.places yet, as the Bite Board's)
		if not places.has(id) or (h.city != "" and str(p.get("region_id", p.get("cluster", ""))) != h.city): continue
		var place: Dictionary = places[id]
		var trap := P0Logic.P0Trap.pond_fact(view, id)
		var why := P0Logic.PinReason.reason(view, id)   # a marked pond says why instead (NOTICE-BOARD 2608:133862)
		ponds.append({id = id, name = Map.short_name(str(place.get("name", p.get("name", id)))), icon = "pond",
			line = str(why.get("text", "")) if not why.is_empty() else bite_line(place, level, caught), reason = why,
			trap = str(trap[1]) if trap.size() > 1 else "", go = "pond:" + id,
			_first = id == beginner, _km = _km(at, p)})
	ponds.sort_custom(_before)
	var outposts: Array = []
	for o in _home_outposts(h):
		var id := str(o.get("id", ""))
		var why := P0Logic.PinReason.reason(view, id)
		var role := str(o.get("role", ""))
		outposts.append({id = id, name = Map.short_name(str(o.get("name", id))), icon = str(Map.PIN_ICONS.get(role, "travel")),
			line = str(why.get("text", "")) if not why.is_empty() else str(o.get("category", "")), reason = why,
			online = int(online.get(id, 0)), go = "outpost:" + id,
			_rank = ROLE_ORDER.find(role) if ROLE_ORDER.has(role) else ROLE_ORDER.size(), _km = _km(at, o)})
	outposts.sort_custom(func(a, b): return a._rank < b._rank if a._rank != b._rank else a._km < b._km)
	for list in [ponds, outposts]:
		for r in list:
			for k in ["_first", "_rank", "_km"]: r.erase(k)
	return {title = "Notice Board", subtitle = "%s · Today · tap a place to see it on the map" % h.name,
		ponds = ponds, outposts = outposts}

## The player's home (SGODOT-303, view.home): {city, name, set, farm}. Its city's cluster and name, its home set
## (market / tea / tackle / post / the beginner pond) and the farm's point; the written city's where the view has none
## (an older server), or a field is missing.
static func home(view: Dictionary) -> Dictionary:
	var h: Dictionary = view.get("home", {}) if view.get("home", {}) is Dictionary else {}
	var farm = h.get("farm", null)
	var set_ = h.get("set", null)
	return {city = str(h.get("city", "")), name = str(h.get("name", "")) if str(h.get("name", "")) != "" else P0City.city_name(),
		set = set_ if set_ is Dictionary else {},
		farm = Vector2(float(farm.get("lat", 0.0)), float(farm.get("lng", 0.0))) if farm is Dictionary else P0City.farm_at()}

## The outposts the board lists: the home set's four, then any other of the home city (P0Outposts: the written city's
## table, a generated city's once read); without a home set, the written city's table.
static func _home_outposts(h: Dictionary) -> Array:
	var set_: Dictionary = h.set
	if set_.is_empty(): return P0Outposts.all().filter(func(o): return not str(o.get("role", "")) in QUIET_ROLES)
	var out: Array = []
	var ids := {}
	for role in ROLE_ORDER:
		var o := P0Outposts.find(str(set_.get(role, "")))
		if o.is_empty() or ids.has(str(o.id)): continue
		ids[str(o.id)] = true
		out.append(o)
	for o in P0Outposts.all():
		if str(o.get("role", "")) in QUIET_ROLES: continue
		if not ids.has(str(o.get("id", ""))) and (h.city == "" or str(o.get("cluster", "")) == h.city): out.append(o)
	return out

## A pond's best bite today: the Bite Board keeper's sentence for that pond's fish (q(119): the landable fish with the
## highest factor now and today, its time and weather words), without the bait — `Rainbow Trout bite in the rain`.
static func bite_line(place: Dictionary, level: int, caught: Dictionary) -> String:
	return Board.line(place.get("fish", []), str(place.get("weather", "")), level, caught, false)

static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a._first != b._first: return a._first
	return a._km < b._km

## Straight-line km from the homestead (lat, lng) to a place with lat / lng: the order only, never shown.
static func _km(home: Vector2, p: Dictionary) -> float:
	var lat := float(p.get("lat", 0.0))
	var lng := float(p.get("lng", 0.0))
	var k := cos(deg_to_rad((home.x + lat) / 2.0))
	return Vector2((lng - home.y) * k, lat - home.x).length() * 111.32
