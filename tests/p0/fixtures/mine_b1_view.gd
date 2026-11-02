extends RefCounted
## A view as the server sends it inside a mine (355 b1, contract-efg §7.1; server/src/p0/mine.ts mineView), for the E
## client's tests. view(n, opts): the player on floor n of `opts.mine` (wd-254-114 `Ironvale Vein`, a vein); opts
## override any field — mobs, rocks, broken, lit, deck, bag_ok, ground, station, stations, next, prev, hp, day,
## energy, notice, records, name, type, max.

const MINE := "wd-254-114"

static func mob(kind: String, hp: int, maximum := -1, elite := false, guard := false, tier := 0) -> Dictionary:
	return {"kind": kind, "hp": hp, "max": maximum if maximum >= 0 else hp, "elite": elite, "guard": guard, "tier": tier}

static func floor_state(n: int, opts := {}) -> Dictionary:
	var mobs: Array = opts.get("mobs", [mob("mob_slime", 9), mob("mob_cave_bat", 5)])
	var rocks := int(opts.get("rocks", 5))
	var broken: Array = opts.get("broken", [])
	if broken.size() != rocks:
		broken = []
		for i in rocks: broken.append(false)
	var left := broken.filter(func(b): return not b).size()
	return {"floor": n, "paid": bool(opts.get("paid", true)), "cleared": mobs.all(func(m): return int(m.hp) <= 0),
		"rocks": rocks, "left": left, "broken": broken, "lit": bool(opts.get("lit", false)), "deck": opts.get("deck", null),
		"bag_ok": bool(opts.get("bag_ok", true)), "station": bool(opts.get("station", n % 10 == 0)),
		"guard": opts.get("guard", null), "ground": opts.get("ground", []), "mobs": mobs}

static func view(n := 3, opts := {}) -> Dictionary:
	var fs := floor_state(n, opts)
	var next = opts.get("next", {"floor": n + 1, "paid": false, "fee": 2, "open": fs.cleared, "locked": null})
	var prev = opts.get("prev", null if n == 1 else {"floor": n - 1, "paid": true, "fee": 0})
	var mine := str(opts.get("mine", MINE))
	return {
		"energy": {"value": int(opts.get("energy", 200)), "max": 200},
		"names": {"stone": "Stone", "copper_ore": "Copper Ore", "iron_ore": "Iron Ore", "coal": "Coal", "torch": "Torch",
			"drop_t1_bat_wing": "Bat Wing"},
		"bag": {"capacity": 25, "free": 25, "slots": opts.get("slots", [])},
		"mine": {"floor_energy": 2, "rock_energy": 2, "hp_max": 100, "rank": int(opts.get("rank", n)),
			"weapon": {"id": "weapon_wooden_sword", "name": "Wooden Sword", "attack": 3, "speed": 2.0, "tier": 1},
			"notice": opts.get("notice", null),
			"at": {"mine": mine, "type": str(opts.get("type", "vein")), "name": str(opts.get("name", "Ironvale Vein")),
				"max": int(opts.get("max", 40)), "floor": n, "hp": int(opts.get("hp", 100)), "day": str(opts.get("day", "2026-11-02")),
				"stations": opts.get("stations", []), "floor_state": fs, "next": next, "prev": prev},
			"records": opts.get("records", {mine: {"deepest": n, "guards": []}})},
	}
