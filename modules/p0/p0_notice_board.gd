extends RefCounted
## The Homestead Stall's Notice Board (§9.3.1, §8.3.1 Lv5; 李白 q(164), SGODOT-284): from Homestead Lv5 a board by the
## stall, tap-triggered, read-only — `Notice Board` / `<home city> · Today`, a `Ponds` section (each home pond with
## today's best bite, as the Bite Board's keeper line (q(119)) without its bait; `Your trap · 2/3` when a trap of the
## player's is in it) and an `Outposts` section (each home outpost by its short name (q(137)), its kind, or the reason
## its pin is marked (q(103)), and `3 online`, none at 0 (q(72))). Every row's `Show on map ›` flies the map to that
## pin and moves nobody (q(31), k(1)). Built from the view and the presence counts the map already polls: no server
## field. Pure and static; the board's frame comes from 不知火舞. Preloaded, no class_name (as P0City).

const Board := preload("res://modules/p0/p0_bite_board.gd")
const Ponds := preload("res://modules/p0/p0_ponds.gd")
const Map := preload("res://scenes/p0/p0_map.gd")
const P0City := preload("res://modules/p0/p0_city.gd")

## Homestead Lv5 brings the board (view.homestead.unlocks.notice_board).
static func unlocked(view: Dictionary) -> bool:
	return bool(view.get("homestead", {}).get("unlocks", {}).get("notice_board", false))

## {title, subtitle, ponds: [{id, name, line, trap, go}], outposts: [{id, name, line, online, go}]}; `online` is the
## presence count per outpost id (all its rooms), as the map holds it.
static func model(view: Dictionary, online: Dictionary = {}) -> Dictionary:
	var level := int(view.get("skills", {}).get("fishing", {}).get("level", 1))
	var caught: Dictionary = view.get("fishing", {}).get("caught", {})
	var places: Dictionary = view.get("fishing", {}).get("places", {})
	var ponds: Array = []
	for p in Ponds.all():
		var id := str(p.get("id", ""))
		if not places.has(id): continue
		var place: Dictionary = places[id]
		var trap := P0Logic.P0Trap.pond_fact(view, id)
		ponds.append({id = id, name = str(place.get("name", p.get("name", id))),
			line = bite_line(place, level, caught),
			trap = "%s · %s" % [str(trap[0]), str(trap[1])] if not trap.is_empty() else "",
			go = "pond:" + id})
	var outposts: Array = []
	for o in P0Outposts.all():
		var id := str(o.get("id", ""))
		var why := P0Logic.PinReason.reason(view, id)
		var n := int(online.get(id, 0))
		outposts.append({id = id, name = Map.short_name(str(o.get("name", id))),
			line = str(why.get("text", "")) if not why.is_empty() else str(o.get("category", "")),
			marked = not why.is_empty(), online = "%d online" % n if n > 0 else "", go = "outpost:" + id})
	return {title = "Notice Board", subtitle = "%s · Today" % P0City.city_name(), ponds = ponds, outposts = outposts}

## A pond's best bite today: the Bite Board keeper's sentence for that pond's fish (q(119): the landable fish with the
## highest factor now and today, its time and weather words), without the bait — `Rainbow Trout bite in the rain`.
static func bite_line(place: Dictionary, level: int, caught: Dictionary) -> String:
	var said := Board.line(place.get("fish", []), str(place.get("weather", "")), level, caught)
	return said.split(". ")[0].trim_suffix(".")
