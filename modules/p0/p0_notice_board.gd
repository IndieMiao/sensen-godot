extends RefCounted
## The Homestead Stall's Notice Board (§9.3.1, §8.3.1 Lv5; 李白 q(164), 不知火舞's spec on SGODOT-284): from Homestead
## Lv5 a board by the stall, tap-triggered, read-only — `Notice Board` / `<home city> · Today · tap a place to see it on
## the map`, a `Ponds` section (each home pond by its short name (q(137)) with today's best bite, as the Bite Board's
## keeper line (q(119)) without its bait, and the player's trap in it as `2/3`; the beginner pond first, the rest
## nearest the homestead first) and an `Outposts` section (each home outpost by its short name, its kind or the reason
## its pin is marked (q(103)), and who is in, none at 0 (q(72)); market, tea house, tackle shop, travel post, then any
## other nearest first). A tap on a row flies the map to that pin and moves nobody (q(31), k(1)). Built from the view
## and the presence counts the map already polls: no server field. Pure and static. Preloaded, no class_name (as P0City).

const Board := preload("res://modules/p0/p0_bite_board.gd")
const Ponds := preload("res://modules/p0/p0_ponds.gd")
const Map := preload("res://scenes/p0/p0_map.gd")
const P0City := preload("res://modules/p0/p0_city.gd")

const ROLE_ORDER := ["market", "tea", "tackle", "post"]   # the home set's four, in this order (不知火舞)

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
	var home := P0City.farm_at()
	var beginner := P0City.beginner_pond()
	var ponds: Array = []
	for p in Ponds.all():
		var id := str(p.get("id", ""))
		if not places.has(id): continue
		var place: Dictionary = places[id]
		var trap := P0Logic.P0Trap.pond_fact(view, id)
		var why := P0Logic.PinReason.reason(view, id)   # a marked pond says why instead (NOTICE-BOARD 2608:133862)
		ponds.append({id = id, name = Map.short_name(str(place.get("name", p.get("name", id)))), icon = "pond",
			line = str(why.get("text", "")) if not why.is_empty() else bite_line(place, level, caught), reason = why,
			trap = str(trap[1]) if trap.size() > 1 else "", go = "pond:" + id,
			_first = id == beginner, _km = _km(home, p)})
	ponds.sort_custom(_before)
	var outposts: Array = []
	for o in P0Outposts.all():
		var id := str(o.get("id", ""))
		var why := P0Logic.PinReason.reason(view, id)
		var role := str(o.get("role", ""))
		outposts.append({id = id, name = Map.short_name(str(o.get("name", id))), icon = str(Map.PIN_ICONS.get(role, "travel")),
			line = str(why.get("text", "")) if not why.is_empty() else str(o.get("category", "")), reason = why,
			online = int(online.get(id, 0)), go = "outpost:" + id,
			_rank = ROLE_ORDER.find(role) if ROLE_ORDER.has(role) else ROLE_ORDER.size(), _km = _km(home, o)})
	outposts.sort_custom(func(a, b): return a._rank < b._rank if a._rank != b._rank else a._km < b._km)
	for list in [ponds, outposts]:
		for r in list:
			for k in ["_first", "_rank", "_km"]: r.erase(k)
	return {title = "Notice Board", subtitle = "%s · Today · tap a place to see it on the map" % P0City.city_name(),
		ponds = ponds, outposts = outposts}

## A pond's best bite today: the Bite Board keeper's sentence for that pond's fish (q(119): the landable fish with the
## highest factor now and today, its time and weather words), without the bait — `Rainbow Trout bite in the rain`.
static func bite_line(place: Dictionary, level: int, caught: Dictionary) -> String:
	var said := Board.line(place.get("fish", []), str(place.get("weather", "")), level, caught)
	return said.split(". ")[0].trim_suffix(".")

static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a._first != b._first: return a._first
	return a._km < b._km

## Straight-line km from the homestead (lat, lng) to a place with lat / lng: the order only, never shown.
static func _km(home: Vector2, p: Dictionary) -> float:
	var lat := float(p.get("lat", 0.0))
	var lng := float(p.get("lng", 0.0))
	var k := cos(deg_to_rad((home.x + lat) / 2.0))
	return Vector2((lng - home.y) * k, lat - home.x).length() * 111.32
