extends RefCounted
## Client copy of the parcel farm state (v1, C-31 server/src/parcels/farm.ts) and its
## commands. The server is authoritative; the local fake store replays the same rules.
## Numbers come from assets/farm/data/dynamic_farm.json (owner decision Q-39, C-34#14),
## shared with the server and separate from the main farm. C-58 added the parcel's own
## coins and the `sell` / `claim_blueprint` commands (mirrored here for the local store, C-59);
## the `gather` command (outer gathering, C-60) is ParcelGather's. C-149 added `buy` (Jasmine's seeds,
## `economy.buy_prices`).
## C-150 (0.4.5): `buildings` holds every building with its type, spot, quarter turns (0–3) and the footprint it was
## built with; types (model, blueprint, footprint, how many per parcel) are the rules' `buildings`. An older save has
## only `house` (the one cottage): it reads as cottage 1 where it stood and facing as it did, and `house` stays the
## cottage's mirror for 0.4.4 and older clients. `place_house` is those clients' cottage, as on the server.
## Energy (C-148, P0's numbers per the owner's C-137#15 q3) mirrors server/src/parcels/energy.ts: `energy` in the
## rules; the save's `energy` {value, at, rested_on} (absent on saves before it: full). Clearing, tilling, sowing
## and outer gathering cost Energy, the rest is free; `rest` at the cottage gives +60 once a player day.
## Livestock and drops (C-154, the coop): a building type with `livestock` keeps its animals. `feed` takes one feed item
## (a carrot) and `energy.costs.feed`; `produce_seconds` later that animal's product (an egg) lies on the ground: a
## `drops` entry, written at feeding with its spot, animal and `ready_at`. `pick_up` takes a laid one into the bag once;
## ids come from `drop_seq` and are never reused. One wait per animal; at `max_ground` drops (laid or not) no more feeding.
## Watering (C-151, owner SEN-C-137#6, #15) mirrors server/src/parcels/farm.ts: a sown crop is dry and counts no time
## (`watered_at` null, `ripe_at` NEVER); `draw_water` at a built well (the rules' `watering.well`) fills the pail to
## `watering.pail_uses` for 2 Energy, `water` uses one on a sown, unwatered cell and starts it growing then. A crop sown
## before watering (no `watered_at`) counts as watered. The rules' `grants` (the well blueprint and the pail) are given
## once per farm on entering; the save keeps the pail's water (`pail_water`) and what was granted (`grants`).
## Farm levels (C-152, as P0's Homestead levels) mirror server/src/parcels/farm.ts: `upgrade_farm` (at Scott's) pays the
## rules' `farm_levels` entry for the next level in coins and materials, for no Energy; each level adds `energy.per_level`
## to Max Energy, and a level's `buildings` lets more of a type stand from it on (wells: 2 at Lv3, 3 at Lv5) with its
## `gift` (a well blueprint) put in the bag. The save's `level` (absent before it: 1) is kept across dataset moves.
## The barn (C-181, 0.4.6) is one more livestock type: besides its blueprint it takes `materials` (Timber and Stone), and
## its `livestock.feed_amount` (default 1; the cows 2 carrots) is taken per feeding, still for one product. Its blueprint
## is bought at Scott's: an `economy.blueprints` entry with `coins` (default 0) costs that much at `claim_blueprint`,
## refused whole (NOT_ENOUGH_COINS) when short, once only as every one-off blueprint. No save field is added.
## The sheep pen (C-182, 0.4.6, SEN-Q-282) is another: four sheep, three Wild Herbs a feeding, one Wool 30 minutes later.
## Its blueprint's `min_requests` (default 0) asks for that many delivered board requests in all (`requests_done`, 15),
## checked before `min_level` (3) and the coins (1,200): CONDITION_NOT_MET {requests_done, min_requests}.
## The request board (C-191, P0's system board at the Washington Square Travel Post) mirrors server/src/parcels/requests.ts:
## the rules' `requests`; the save's `board` {slots: [{req, refill_at}], seq, day, done_today, bonus_today} and
## `requests_done` (absent before it: an empty board, 0). `settle_board` fills due slots and swaps open requests 72 h old,
## drawing by `hash32` of (first entry, slot, draw time, id) — the same requests and ids the server draws; `apply` settles
## before and after a batch and `view` settles a copy (the server's read). `accept_request` / `deliver_request` /
## `drop_request` take a request id: delivering takes the items and pays the floor price × count plus the bonus left
## today, at most `daily_max` a player day; dropping refills the slot `drop_refill_seconds` later.
## C-197 (owner SEN-Q-281): the floor price is Jasmine's price (`floor_percent` 100); count and bonus come from the
## template's own `tiers`, else its item's `item_tiers`, else the shared `tiers`. The seed aid (server seed_aid.ts):
## with no coins for one of the rules' `seed_aid` seed, no crop seeds and no crops (in the bag or in the ground),
## `claim_seed_aid` gives `seed_aid.amount` of it once a player day; the save's `seed_aid_day` is that day (absent: never).
## C-202 (the barn's 11×6 less its rear-left 2×2, owner SEN-Q-300): a building type's optional `cutouts` are cells of its
## footprint that are not the building's, rects [x, z, width, depth] in its own unturned frame (as `livestock.spots`:
## origin at the rear-left corner, z toward the entry), turning with it. A building placed keeps a copy (`cutouts`, as it
## keeps its width and depth); other buildings, tilling and crops may use those cells.
## C-209: a building placed before its type had cutouts (C-192's 8×6 barn) is taken down when the save is read, its
## blueprint, materials and drops given back (`retire_draft_buildings`); no save field is added.
const RULES_PATH := "res://assets/farm/data/dynamic_farm.json"
const STATE_VERSION := 1
const MAX_COORD := 1024
const MAX_CELLS := 8192
const MAX_BATCH := 50
const COMMANDS := ["place_house", "place_building", "clear_obstacle", "till", "sow", "harvest", "sell", "buy", "claim_blueprint",
	"gather", "rest", "feed", "pick_up", "draw_water", "water", "upgrade_farm", "accept_request", "deliver_request", "drop_request",
	"claim_seed_aid"]
## C-191 request commands: the request id is their one field.
const REQUEST_COMMANDS := ["accept_request", "deliver_request", "drop_request"]
## Most request board slots (server requests.ts MAX_SLOTS).
const MAX_SLOTS := 8
## Commands priced by `energy.costs` (sowing is priced on the crop; feeding is P0's feed-an-animal 1, C-154).
const PRICED := ["clear_obstacle", "till", "gather", "draw_water", "feed"]
## Most animals in one livestock building, most drops on its ground, largest building / drop id in a command (server).
const MAX_ANIMALS := 16
const MAX_GROUND_DROPS := 64
const MAX_ID := 2147483647
## A dry crop's `ripe_at` (C-151): the latest time a JS Date holds, never reached (server farm.ts NEVER).
const NEVER := 8640000000000000
const DAY_MS := 86400000
## The first house's building type: an old save's `house` and `place_house` are cottages (server rules.ts HOME_BUILDING).
const HOME_BUILDING := "cottage"
## Most buildings on one parcel, all types together; most cells along a building's side (server rules.ts).
const MAX_BUILDINGS := 64
const MAX_BUILDING_SIDE := 16
## Most cutouts a building type may list (server rules.ts MAX_CUTOUTS).
const MAX_CUTOUTS := 8
## The highest level the rules may list (server rules.ts MAX_FARM_LEVEL).
const MAX_FARM_LEVEL := 99
const HOUSE_FIELDS := ["model", "x", "y", "width", "depth", "rotation", "built_at"]
## Server limits (C-58 farm.ts): the coin cap and the most one sell (C-149: buy) command may sell (buy).
const MAX_COINS := 1000000000
const MAX_SELL_COUNT := 999
const MAX_BUY_COUNT := 999
const Gather = preload("res://modules/dynamic_farm/parcel_gather.gd")

static var _rules := {}

## Parsed rules, or {} when the file is missing or malformed.
static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = parse_rules(JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH)))
	return _rules

static func parse_rules(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not whole_in(raw.get("version"), 1, 1):
		return {}
	if not raw.get("welcome_gift") is Dictionary or not raw.get("till_tool") is String or not raw.get("crops") is Dictionary:
		return {}
	if not raw.get("buildings") is Dictionary or not raw.buildings.get(HOME_BUILDING) is Dictionary: return {}
	for id in raw.buildings:
		var b = raw.buildings[id]
		if not id is String or not b is Dictionary or not b.get("model") is String or not b.get("blueprint") is String \
				or not whole_in(b.get("width"), 1, MAX_BUILDING_SIDE) or not whole_in(b.get("depth"), 1, MAX_BUILDING_SIDE) \
				or not whole_in(b.get("max"), 1, MAX_BUILDINGS):
			return {}
		if b.has("materials"):
			if not b.materials is Dictionary: return {}
			for item in b.materials:
				if not item is String or not whole_in(b.materials[item], 1, 999): return {}
		if b.has("cutouts") and not _cutouts_fit(b.cutouts, int(b.width), int(b.depth)): return {}
		if b.has("livestock") and _parse_livestock(b.livestock, b).is_empty(): return {}
	for id in raw.welcome_gift:
		if not id is String or not whole_in(raw.welcome_gift[id], 1, 999): return {}
	if raw.crops.is_empty(): return {}
	for id in raw.crops:
		var crop = raw.crops[id]
		if not crop is Dictionary or not crop.get("seed") is String or not whole_in(crop.get("grow_seconds"), 1, 30 * 24 * 3600) or not whole_in(crop.get("yield"), 1, 99) \
				or not whole_in(crop.get("energy"), 0, 1000):
			return {}
	var energy := _parse_energy(raw.get("energy"))
	if energy.is_empty(): return {}
	var watering = raw.get("watering")
	if not watering is Dictionary or not watering.get("well") is String or not raw.buildings.has(watering.well) \
			or not watering.get("pail") is String or not whole_in(watering.get("pail_uses"), 1, 99):
		return {}
	if not raw.get("grants") is Dictionary: return {}
	for id in raw.grants:
		var items = raw.grants[id]
		if not id is String or not items is Dictionary or items.is_empty(): return {}
		for item in items:
			if not item is String or not whole_in(items[item], 1, 999): return {}
	var parsed: Dictionary = raw.duplicate(true)
	for id in parsed.welcome_gift: parsed.welcome_gift[id] = int(parsed.welcome_gift[id])
	for id in parsed.crops:
		parsed.crops[id].grow_seconds = int(parsed.crops[id].grow_seconds)
		parsed.crops[id]["yield"] = int(parsed.crops[id]["yield"])
		parsed.crops[id].energy = int(parsed.crops[id].energy)
	parsed.energy = energy
	parsed.watering.pail_uses = int(parsed.watering.pail_uses)
	for id in parsed.grants:
		for item in parsed.grants[id]: parsed.grants[id][item] = int(parsed.grants[id][item])
	for id in parsed.buildings:
		for field in ["width", "depth", "max"]: parsed.buildings[id][field] = int(parsed.buildings[id][field])
		var materials := {}
		for item in parsed.buildings[id].get("materials", {}): materials[item] = int(parsed.buildings[id].materials[item])
		parsed.buildings[id].materials = materials
		if parsed.buildings[id].has("cutouts"): parsed.buildings[id].cutouts = _cutout_ints(parsed.buildings[id].cutouts)
		if parsed.buildings[id].has("livestock"):
			parsed.buildings[id].livestock = _parse_livestock(parsed.buildings[id].livestock, parsed.buildings[id])
	parsed["economy"] = _parse_economy(raw.get("economy"))
	var levels = _parse_levels(raw.get("farm_levels", []), parsed.buildings)
	if levels == null: return {}
	parsed["farm_levels"] = levels
	# C-191: no `requests`, no board ({}); out of the server's bounds, the rules are refused.
	parsed["requests"] = {}
	if raw.has("requests"):
		parsed.requests = _parse_requests(raw.requests, parsed)
		if parsed.requests.is_empty(): return {}
	# C-197: no `seed_aid`, no aid ({}); out of the server's bounds (seed_aid.ts parseSeedAidRules), the rules are refused.
	parsed["seed_aid"] = {}
	if raw.has("seed_aid"):
		parsed.seed_aid = _parse_seed_aid(raw.seed_aid, parsed)
		if parsed.seed_aid.is_empty(): return {}
	return parsed

## C-197 `seed_aid` with the server's bounds: a crop's seed that Jasmine sells (its price is what "no coins" means),
## 1–99 of it; {} when out of them.
static func _parse_seed_aid(raw: Variant, parsed: Dictionary) -> Dictionary:
	if not raw is Dictionary or not raw.get("item") is String or not _is_id(raw.item) or not whole_in(raw.get("amount"), 1, 99): return {}
	if not parsed.crops.values().any(func(c): return c.seed == raw.item): return {}
	if not parsed.economy.buy_prices.has(raw.item): return {}
	return {"item": raw.item, "amount": int(raw.amount)}

## C-191 `requests` with the server's bounds (requests.ts parseRequestRules), whole numbers made ints; {} when out of them.
## Templates keep the file's order (the draw indexes them in it).
static func _parse_requests(raw: Variant, parsed: Dictionary) -> Dictionary:
	if not raw is Dictionary or not whole_in(raw.get("slots"), 1, MAX_SLOTS) or not whole_in(raw.get("done_refill_seconds"), 0, 30 * 86400) \
			or not whole_in(raw.get("drop_refill_seconds"), 0, 30 * 86400) or not whole_in(raw.get("expire_seconds"), 3600, 30 * 86400) \
			or not whole_in(raw.get("daily_max"), 1, 100) or not whole_in(raw.get("daily_bonus_max"), 0, 100000) \
			or not whole_in(raw.get("floor_percent"), 1, 100):
		return {}
	var out := {}
	for field in ["slots", "done_refill_seconds", "drop_refill_seconds", "expire_seconds", "daily_max", "daily_bonus_max", "floor_percent"]:
		out[field] = int(raw[field])
	out.tiers = _parse_tiers(raw.get("tiers"))
	if out.tiers.is_empty(): return {}
	# C-197: tiers by item (an item not sold yet may be listed: milk and wool ahead of their buildings).
	out.item_tiers = {}
	if raw.has("item_tiers"):
		if not raw.item_tiers is Dictionary: return {}
		for item in raw.item_tiers:
			var by_item := _parse_tiers(raw.item_tiers[item])
			if not item is String or not _is_id(item) or by_item.is_empty(): return {}
			out.item_tiers[item] = by_item
	if not raw.get("templates") is Dictionary or raw.templates.is_empty(): return {}
	out.templates = {}
	for id in raw.templates:
		var t = raw.templates[id]
		if not id is String or not t is Dictionary or not t.get("item") is String or not parsed.economy.sell_prices.has(t.item): return {}
		out.templates[id] = {"item": t.item}
		if t.has("building"):
			if not t.building is String or not parsed.buildings.has(t.building): return {}
			out.templates[id].building = t.building
		# A template's own tiers (count and bonus by item), else the shared ones.
		if t.has("tiers"):
			var own := _parse_tiers(t.tiers)
			if own.is_empty(): return {}
			out.templates[id].tiers = own
	return out

## Tiers with the server's bounds (requests.ts parseTiers): from Lv1, levels rising, counts 1–999 low to high, bonus
## 0–10000; [] when out of them.
static func _parse_tiers(raw: Variant) -> Array:
	if not raw is Array or raw.is_empty(): return []
	var out: Array = []
	for t in raw:
		if not t is Dictionary or not whole_in(t.get("level"), 1, 999) or not t.get("qty") is Array or t.qty.size() != 2 \
				or not whole_in(t.qty[0], 1, 999) or not whole_in(t.qty[1], int(t.qty[0]) if _number(t.qty[0]) else 1, 999) \
				or not whole_in(t.get("bonus"), 0, 10000):
			return []
		if (out.is_empty() and int(t.level) != 1) or (not out.is_empty() and int(t.level) <= int(out[-1].level)): return []
		out.append({"level": int(t.level), "qty": [int(t.qty[0]), int(t.qty[1])], "bonus": int(t.bonus)})
	return out

## C-154 a building's `livestock` with the server's bounds (rules.ts parseLivestock), whole numbers made ints; {} when
## out of them. `spots` stay [x, z] floats in the building's own unturned frame, in cells.
static func _parse_livestock(raw: Variant, building: Dictionary) -> Dictionary:
	if not raw is Dictionary or not raw.get("animals") is Array or raw.animals.is_empty() or raw.animals.size() > MAX_ANIMALS: return {}
	for a in raw.animals:
		if not a is String: return {}
	if not raw.get("feed") is String or not raw.get("product") is String or not whole_in(raw.get("amount"), 1, 99) \
			or not whole_in(raw.get("produce_seconds"), 1, 7 * 24 * 3600) or not whole_in(raw.get("max_ground"), 1, MAX_GROUND_DROPS) \
			or (raw.has("feed_amount") and not whole_in(raw.feed_amount, 1, 99)):
		return {}
	if not raw.get("spots") is Array or raw.spots.size() < int(raw.max_ground) or raw.spots.size() > MAX_GROUND_DROPS * 4: return {}
	var spots := []
	for p in raw.spots:
		if not p is Array or p.size() != 2 or not _number(p[0]) or not _number(p[1]): return {}
		if float(p[0]) < 0 or float(p[0]) > float(building.width) or float(p[1]) < 0 or float(p[1]) > float(building.depth): return {}
		# C-202: not inside a cutout either (on its edge is the footprint's).
		for r in building.get("cutouts", []):
			if float(p[0]) > float(r[0]) and float(p[0]) < float(r[0]) + float(r[2]) and float(p[1]) > float(r[1]) \
					and float(p[1]) < float(r[1]) + float(r[3]):
				return {}
		spots.append(Vector2(float(p[0]), float(p[1])))
	return {"animals": raw.animals.duplicate(), "feed": raw.feed, "feed_amount": int(raw.get("feed_amount", 1)), "product": raw.product,
		"amount": int(raw.amount),
		"produce_seconds": int(raw.produce_seconds), "max_ground": int(raw.max_ground), "spots": spots}

## C-202 a type's `cutouts` with the server's bounds (rules.ts parseCutouts): at most MAX_CUTOUTS whole-cell rects
## [x, z, width, depth], each non-empty inside the width × depth footprint, leaving at least one cell.
static func _cutouts_fit(raw: Variant, width: int, depth: int) -> bool:
	if not raw is Array or raw.size() > MAX_CUTOUTS: return false
	for r in raw:
		if not r is Array or r.size() != 4 or not whole_in(r[0], 0, width - 1) or not whole_in(r[1], 0, depth - 1) \
				or not whole_in(r[2], 1, width - int(r[0])) or not whole_in(r[3], 1, depth - int(r[1])):
			return false
	return not own_cells(Vector2i(width, depth), raw).is_empty()

static func _cutout_ints(raw: Array) -> Array:
	return raw.map(func(r): return [int(r[0]), int(r[1]), int(r[2]), int(r[3])])

## C-152 `farm_levels` with the server's bounds (rules.ts parseFarmLevels): from Lv2 on, one entry a level, coins 0–100000,
## materials and gifts 1–999 each, a level's building limits for known types and never below the one before; null when
## out of them. Integers made ints.
static func _parse_levels(raw: Variant, buildings: Dictionary) -> Variant:
	if not raw is Array or raw.size() > MAX_FARM_LEVEL - 1: return null
	var most := {}
	for type: String in buildings: most[type] = int(buildings[type].max)
	var out: Array = []
	for i in raw.size():
		var l = raw[i]
		if not l is Dictionary or not whole_in(l.get("level"), i + 2, i + 2) or not whole_in(l.get("coins"), 0, 100000): return null
		var level := {"level": i + 2, "coins": int(l.coins)}
		for field in ["items", "gift"]:
			if field == "gift" and not l.has("gift"): continue
			var items = l.get(field)
			if not items is Dictionary: return null
			level[field] = {}
			for id in items:
				if not id is String or not whole_in(items[id], 1, 999): return null
				level[field][id] = int(items[id])
		if l.has("buildings"):
			if not l.buildings is Dictionary: return null
			level.buildings = {}
			for type in l.buildings:
				if not type is String or not most.has(type) or not whole_in(l.buildings[type], int(most[type]), MAX_BUILDINGS): return null
				most[type] = int(l.buildings[type])
				level.buildings[type] = most[type]
		out.append(level)
	return out

## C-58 `economy`: sell prices and one-off blueprints (C-181: a blueprint's `coins`, 0–100000, default 0, is its price at
## Scott's); C-149 buy prices (Jasmine's shelf).
## {sell_prices:{}, buy_prices:{}, blueprints:{}} when absent.
static func _parse_economy(raw: Variant) -> Dictionary:
	var out := {"sell_prices": {}, "buy_prices": {}, "blueprints": {}}
	if not raw is Dictionary: return out
	for field in ["sell_prices", "buy_prices"]:
		if raw.get(field) is Dictionary:
			for id in raw[field]:
				if id is String and whole_in(raw[field][id], 1, 100000): out[field][id] = int(raw[field][id])
	if raw.get("blueprints") is Dictionary:
		for id in raw.blueprints:
			var rule = raw.blueprints[id]
			if id is String and rule is Dictionary and rule.get("item") is String and whole_in(rule.get("amount"), 1, 99) \
					and whole_in(rule.get("min_sales"), 0, 1000) and (not rule.has("coins") or whole_in(rule.coins, 0, 100000)) \
					and (not rule.has("min_level") or whole_in(rule.min_level, 1, MAX_FARM_LEVEL)) \
					and (not rule.has("min_requests") or whole_in(rule.min_requests, 0, 100000)):
				# C-192 (SEN-Q-282): `min_level`, the farm level a blueprint is sold from (the barn's 2), defaults to 1.
				# C-182 (SEN-Q-282): `min_requests`, how many board requests the farm has delivered in all (`requests_done`)
				# before it is sold (the sheep pen's 15), defaults to 0.
				out.blueprints[id] = {"item": rule.item, "amount": int(rule.amount), "min_sales": int(rule.min_sales),
					"min_level": int(rule.get("min_level", 1)), "min_requests": int(rule.get("min_requests", 0)),
					"coins": int(rule.get("coins", 0))}
	return out

## C-148 `energy` with the server's bounds (energy.ts parseEnergyRules), integers made ints; {} when out of them.
static func _parse_energy(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not whole_in(raw.get("max_base"), 1, 10000) or not whole_in(raw.get("per_level"), 0, 1000) \
			or not whole_in(raw.get("regen_ms"), 1000, DAY_MS) or not whole_in(raw.get("rest_amount"), 1, 10000):
		return {}
	var b = raw.get("blessing")
	var d = raw.get("day")
	if not b is Dictionary or not whole_in(b.get("days"), 0, 365) or not _number(b.get("regen_mult")) \
			or float(b.regen_mult) < 1.0 or float(b.regen_mult) > 10.0:
		return {}
	if not d is Dictionary or not whole_in(d.get("utc_offset_hours"), -12, 14) or not whole_in(d.get("rollover_hour"), 0, 23):
		return {}
	if not raw.get("costs") is Dictionary: return {}
	var costs := {}
	for type in raw.costs:
		if type not in PRICED or not whole_in(raw.costs[type], 0, 1000): return {}
		costs[type] = int(raw.costs[type])
	return {"max_base": int(raw.max_base), "per_level": int(raw.per_level), "regen_ms": int(raw.regen_ms),
		"rest_amount": int(raw.rest_amount), "blessing": {"days": int(b.days), "regen_mult": float(b.regen_mult)},
		"day": {"utc_offset_hours": int(d.utc_offset_hours), "rollover_hour": int(d.rollover_hour)}, "costs": costs}

static func empty_state() -> Dictionary:
	return {"v": STATE_VERSION, "buildings": [], "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {}, "welcomed_at": null,
		"coins": 0, "sales": 0, "gathered": {}, "blueprints_claimed": {}, "drops": [], "drop_seq": 0, "pail_water": 0, "grants": {},
		"level": 1, "board": empty_board(), "requests_done": 0, "seed_aid_day": null}

## A board with no slots yet (C-191; server requests.ts emptyBoard).
static func empty_board() -> Dictionary:
	return {"slots": [], "seq": 0, "day": null, "done_today": 0, "bonus_today": 0}

## A state as returned by the server, with JSON floats turned back into integers.
## Returns {} for anything that is not a v1 farm.
static func normalize(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not whole_in(raw.get("v"), STATE_VERSION, STATE_VERSION):
		return {}
	var state := empty_state()
	for list: String in ["cleared", "tilled"]:
		if not raw.get(list) is Array: return {}
		for key in raw[list]:
			if parse_key(key) == null: return {}
			state[list].append(key)
	if not raw.get("crops") is Dictionary or not raw.get("bag") is Dictionary: return {}
	for key in raw.crops:
		var crop = raw.crops[key]
		if parse_key(key) == null or not crop is Dictionary or not crop.get("crop") is String: return {}
		if not _number(crop.get("planted_at")) or not _number(crop.get("ripe_at")): return {}
		state.crops[key] = {"crop": crop.crop, "planted_at": int(crop.planted_at), "ripe_at": int(crop.ripe_at)}
		# C-151: null is sown but not watered; a number is when it was watered; absent (sown before watering) counts as watered.
		if crop.has("watered_at"):
			if crop.watered_at != null and not _number(crop.watered_at): return {}
			state.crops[key].watered_at = int(crop.watered_at) if crop.watered_at != null else null
	for id in raw.bag:
		if not id is String or not whole_in(raw.bag[id], 0, 1 << 30): return {}
		if int(raw.bag[id]) > 0: state.bag[id] = int(raw.bag[id])
	var house = raw.get("house")
	if house != null and _house(house).is_empty(): return {}
	var buildings = raw.get("buildings")
	if buildings is Array:
		if buildings.size() > MAX_BUILDINGS: return {}
		for b in buildings:
			var read := _house(b)
			if read.is_empty() or not b.get("type") is String or not whole_in(b.get("id"), 1, 1 << 30): return {}
			read.id = int(b.id)
			read.type = b.type
			if b.get("animals") is Array:
				read.animals = []
				for a in b.animals:
					if not a is String: return {}
					read.animals.append(a)
			# C-202: the cutouts it was placed with; malformed ones are not counted (server rules.ts ownCells).
			if b.get("cutouts") is Array:
				var rects: Array = (b.cutouts as Array).filter(func(r): return r is Array and r.size() == 4 \
					and (r as Array).all(func(v): return whole_in(v, -MAX_COORD, MAX_COORD)))
				read.cutouts = _cutout_ints(rects)
			state.buildings.append(read)
	elif buildings != null:
		return {}
	elif house != null:
		# Before C-150: the one house is cottage 1, where it stood and facing as it did.
		var home := _house(house)
		home.id = 1
		home.type = HOME_BUILDING
		state.buildings.append(home)
	state.house = home_of(state.buildings)
	var welcomed = raw.get("welcomed_at")
	if welcomed != null and not _number(welcomed): return {}
	state.welcomed_at = int(welcomed) if welcomed != null else null
	# C-58 economy: a save from before it has none and reads as 0 coins, nothing sold, gathered or claimed.
	for field in ["coins", "sales", "pail_water"]:
		if raw.has(field):
			if not whole_in(raw[field], 0, MAX_COINS): return {}
			state[field] = int(raw[field])
	for field in ["gathered", "blueprints_claimed", "grants"]:
		if raw.get(field) == null: continue
		if not raw[field] is Dictionary: return {}
		for id in raw[field]:
			if not id is String or not _number(raw[field][id]): return {}
			state[field][id] = int(raw[field][id])
	# C-154 drops: a save from before them has none; malformed entries are dropped, as the server reads them.
	if raw.get("drops") is Array:
		for d in raw.drops:
			var drop := _drop(d)
			if not drop.is_empty(): state.drops.append(drop)
	state.drop_seq = int(raw.drop_seq) if whole_in(raw.get("drop_seq"), 0, MAX_ID) else 0
	for d: Dictionary in state.drops: state.drop_seq = maxi(state.drop_seq, int(d.id))
	# C-152: the farm level; a save from before it (or a malformed one, as the server reads it) is Lv1.
	if whole_in(raw.get("level"), 1, 1 << 30): state.level = int(raw.level)
	# C-191: the request board and the count; a save from before them has an empty board and 0, malformed parts dropped.
	state.board = _board(raw.get("board"))
	state.requests_done = int(raw.requests_done) if whole_in(raw.get("requests_done"), 0, 1 << 30) else 0
	# C-197: the player day of the last seed aid; absent or unreadable (as the server reads it) is never.
	state.seed_aid_day = raw.seed_aid_day if _is_day(raw.get("seed_aid_day")) else null
	# C-148 Energy: kept when well formed; without it (or malformed, as the server reads it) the farm is at full Energy.
	var energy = raw.get("energy")
	if energy is Dictionary and whole_in(energy.get("value"), 0, 1 << 30) and _number(energy.get("at")) \
			and (energy.get("rested_on") == null or _is_day(energy.get("rested_on"))):
		state.energy = {"value": int(energy.value), "at": int(energy.at), "rested_on": energy.get("rested_on")}
	return state

## The save's request board read as the server reads it (requests.ts boardOf): malformed slots and requests left out,
## `seq` at least the highest id on the board, the day's counts only with a day.
static func _board(raw: Variant) -> Dictionary:
	var out := empty_board()
	if not raw is Dictionary: return out
	if raw.get("slots") is Array:
		for sl in raw.slots:
			if not sl is Dictionary or not sl.has("req") or not sl.has("refill_at") or not _number(sl.refill_at): continue
			var req = sl.get("req")
			if req == null:
				out.slots.append({"req": null, "refill_at": int(sl.refill_at)})
				continue
			var r := _request(req)
			if not r.is_empty(): out.slots.append({"req": r, "refill_at": int(sl.refill_at)})
	if whole_in(raw.get("seq"), 0, MAX_ID): out.seq = int(raw.seq)
	for sl: Dictionary in out.slots:
		if sl.req != null: out.seq = maxi(int(out.seq), int(sl.req.id))
	if _is_day(raw.get("day")):
		out.day = raw.day
		if whole_in(raw.get("done_today"), 0, 10000): out.done_today = int(raw.done_today)
		if whole_in(raw.get("bonus_today"), 0, 1000000): out.bonus_today = int(raw.bonus_today)
	return out

## One request with whole numbers, or {} when malformed (server requests.ts isRequest).
static func _request(r: Variant) -> Dictionary:
	if not r is Dictionary or not whole_in(r.get("id"), 1, MAX_ID) or not _is_id(r.get("template")) or not _is_id(r.get("item")) \
			or not whole_in(r.get("qty"), 1, 999) or not whole_in(r.get("bonus"), 0, 10000) or not _number(r.get("drawn_at")) \
			or not r.get("status") in ["open", "accepted"]:
		return {}
	return {"id": int(r.id), "template": r.template, "item": r.item, "qty": int(r.qty), "bonus": int(r.bonus),
		"drawn_at": int(r.drawn_at), "status": r.status}

## A drop entry (C-154) with whole numbers, or {} when malformed (server farm.ts isDrop).
static func _drop(d: Variant) -> Dictionary:
	if not d is Dictionary or not d.get("item") is String or not _number(d.get("ready_at")): return {}
	if not whole_in(d.get("id"), 1, MAX_ID) or not whole_in(d.get("amount"), 1, 1 << 30): return {}
	for field in ["building", "animal", "spot"]:
		if not whole_in(d.get(field), 0, MAX_ID): return {}
	return {"id": int(d.id), "item": d.item, "amount": int(d.amount), "building": int(d.building), "animal": int(d.animal),
		"spot": int(d.spot), "ready_at": int(d.ready_at)}

## A building's livestock rule (C-154), {} for a type without one or unknown here.
static func livestock_of(rule_set: Dictionary, building: Dictionary) -> Dictionary:
	var rule = rule_set.get("buildings", {}).get(str(building.get("type", "")))
	return rule.get("livestock", {}) if rule is Dictionary else {}

## The drops on one building's ground, laid or not.
static func drops_in(state: Dictionary, building_id: int) -> Array:
	return state.get("drops", []).filter(func(d: Dictionary): return int(d.building) == building_id)

## Why one more feeding at `building` is refused now, or "" when it is not (C-154, the server's checks in its order):
## NOT_LIVESTOCK, NO_FEED (fewer than the rule's `feed_amount`, C-181), GROUND_FULL, ANIMALS_FED. Energy is checked apart (the key's price).
static func feed_refusal(rule_set: Dictionary, state: Dictionary, building: Dictionary, now: int) -> String:
	var rule := livestock_of(rule_set, building)
	if rule.is_empty() or not building.get("animals") is Array or building.animals.is_empty(): return "NOT_LIVESTOCK"
	# C-186#8: a full ground first (with or without the feed, nothing can be fed until some are picked up), then the feed;
	# the server's feed checks in the same order (server/src/parcels/farm.ts).
	var mine := drops_in(state, int(building.id))
	if mine.size() >= int(rule.max_ground): return "GROUND_FULL"
	if int(state.get("bag", {}).get(rule.feed, 0)) < int(rule.get("feed_amount", 1)): return "NO_FEED"
	return "" if _free_animal(building, mine, now) >= 0 else "ANIMALS_FED"

## The first animal with no product on its way (laid ones do not count), or -1.
static func _free_animal(building: Dictionary, mine: Array, now: int) -> int:
	var waiting := {}
	for d: Dictionary in mine:
		if int(d.ready_at) > now: waiting[int(d.animal)] = true
	for i in (building.animals as Array).size():
		if not waiting.has(i): return i
	return -1

## A free spot for a new drop: one no drop of this building lies on, chosen by the drop's id (server farm.ts freeSpot).
static func _free_spot(spots: int, mine: Array, id: int) -> int:
	var used := {}
	for d: Dictionary in mine: used[int(d.spot)] = true
	var free := []
	for i in spots:
		if not used.has(i): free.append(i)
	return free[(id * 7) % free.size()]

## Sown but not watered yet (C-151; server farm.ts isDry): `watered_at` is there and null.
static func is_dry(crop: Dictionary) -> bool:
	return crop.has("watered_at") and crop.watered_at == null

## The state's buildings of the watering's well type (C-151).
static func wells(rule_set: Dictionary, state: Dictionary) -> Array:
	return buildings_of(state).filter(func(b): return b is Dictionary and b.get("type") == rule_set.watering.well)

## A house-shaped entry (C-31 `house`, or a building without id and type) with whole numbers, or {}.
static func _house(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	for field in ["x", "y", "width", "depth", "rotation"]:
		if not whole_in(raw.get(field), 0, MAX_COORD): return {}
	if int(raw.rotation) > 3: return {}
	return {"model": str(raw.get("model", "")), "x": int(raw.x), "y": int(raw.y),
		"width": int(raw.width), "depth": int(raw.depth), "rotation": int(raw.rotation),
		"built_at": int(raw.get("built_at", 0)) if _number(raw.get("built_at")) else 0}

## The first cottage of `buildings` without id and type: the old save's `house`, or null.
static func home_of(buildings: Array) -> Variant:
	for b: Dictionary in buildings:
		if b.type != HOME_BUILDING: continue
		var house := {}
		for field: String in HOUSE_FIELDS: house[field] = b[field]
		return house
	return null

## The state's cottage: the first of its buildings of type HOME_BUILDING (an old house-only save read as cottage 1),
## or {} (C-148 Rest, the door and the Energy card's `Show home`).
static func home_building(state: Dictionary) -> Dictionary:
	for b in buildings_of(state):
		if b is Dictionary and b.get("type") == HOME_BUILDING: return b
	return {}

## A cottage is among the state's buildings (C-148 Rest; server farm.ts `rest`).
static func has_home(state: Dictionary) -> bool:
	return not home_building(state).is_empty()

## The buildings of a state, an older one (only `house`) read as normalize does.
static func buildings_of(state: Dictionary) -> Array:
	if state.get("buildings") is Array: return state.buildings
	var house = state.get("house")
	if not house is Dictionary: return []
	var home: Dictionary = house.duplicate()
	home.id = 1
	home.type = HOME_BUILDING
	return [home]

# ------------------------------------------------------------------ Energy (C-148, server energy.ts)

## Farm level (C-152); Lv1 for a save without one.
static func farm_level(state: Dictionary) -> int:
	return int(state.level) if whole_in(state.get("level"), 1, 1 << 30) else 1

## The rules' entry for the level after `level` ({level, coins, items, gift?, buildings?}), or {} at the top.
static func next_level(rule_set: Dictionary, level: int) -> Dictionary:
	for l: Dictionary in rule_set.get("farm_levels", []):
		if int(l.level) == level + 1: return l
	return {}

## How many of a building type may stand at `level`: its `buildings.<type>.max`, or the last level up to `level` that
## names it (server rules.ts buildingMax: wells 1, 2 from Lv3, 3 from Lv5).
static func building_max(rule_set: Dictionary, type: String, level: int) -> int:
	var most := int(rule_set.buildings[type].max)
	for l: Dictionary in rule_set.get("farm_levels", []):
		if int(l.level) <= level and l.get("buildings", {}).has(type): most = int(l.buildings[type])
	return most

static func max_energy(rule_set: Dictionary, state: Dictionary) -> int:
	return int(rule_set.energy.max_base) + int(rule_set.energy.per_level) * (farm_level(state) - 1)

## Newcomer: the first `blessing.days` × 24 h after the first entry into one's own parcel.
static func blessed(rule_set: Dictionary, state: Dictionary, now: int) -> bool:
	return state.get("welcomed_at") != null and now - int(state.welcomed_at) < int(rule_set.energy.blessing.days) * DAY_MS

## Milliseconds per +1: 4:00, or 2:40 for a newcomer (×1.5).
static func regen_ms(rule_set: Dictionary, state: Dictionary, now: int) -> int:
	var e: Dictionary = rule_set.energy
	return roundi(float(e.regen_ms) / float(e.blessing.regen_mult)) if blessed(rule_set, state, now) else int(e.regen_ms)

## Newcomer time left (ms); 0 when not a newcomer.
static func blessing_left(rule_set: Dictionary, state: Dictionary, now: int) -> int:
	return int(state.welcomed_at) + int(rule_set.energy.blessing.days) * DAY_MS - now if blessed(rule_set, state, now) else 0

## The save's Energy, or full and never rested when it has none. A copy.
static func energy_of(rule_set: Dictionary, state: Dictionary, now: int) -> Dictionary:
	var e = state.get("energy")
	if e is Dictionary: return e.duplicate()
	return {"value": max_energy(rule_set, state), "at": now, "rested_on": null}

## Brings `state.energy` up to `now` (written in place): +1 per period up to the pool; while full the timer is held at now.
static func settle_energy(rule_set: Dictionary, state: Dictionary, now: int) -> Dictionary:
	var e := energy_of(rule_set, state, now)
	state.energy = e
	var top := max_energy(rule_set, state)
	var period := regen_ms(rule_set, state, now)
	if int(e.value) >= top:
		e.at = now
		return e
	var steps := floori(float(now - int(e.at)) / period)
	if steps <= 0: return e
	e.value = mini(top, int(e.value) + steps)
	e.at = now if int(e.value) >= top else int(e.at) + steps * period
	return e

## Milliseconds to the next +1, or null when full.
static func next_tick_in(rule_set: Dictionary, state: Dictionary, now: int) -> Variant:
	var e := energy_of(rule_set, state, now)
	if int(e.value) >= max_energy(rule_set, state): return null
	return maxi(0, int(e.at) + regen_ms(rule_set, state, now) - now)

## Energy a command costs: a sown crop's own price, `energy.costs` for clearing, tilling and gathering, else 0.
static func energy_cost(rule_set: Dictionary, command: Dictionary) -> int:
	if command.get("type") == "sow":
		var crop = rule_set.crops.get(command.get("crop", ""))
		return int(crop.energy) if crop is Dictionary else 0
	return int(rule_set.energy.costs.get(command.get("type", ""), 0))

## Spends `amount` (already checked); a full pool starts its timer now.
static func _spend(rule_set: Dictionary, state: Dictionary, now: int, amount: int) -> void:
	var e := settle_energy(rule_set, state, now)
	if int(e.value) >= max_energy(rule_set, state): e.at = now
	e.value = int(e.value) - amount

## The player day, YYYY-MM-DD: local time (`day.utc_offset_hours`) put back by `day.rollover_hour`.
static func day_key(rule_set: Dictionary, now: int) -> String:
	return Time.get_date_string_from_unix_time(floori(float(now + _day_shift(rule_set)) / 1000.0))

## When the current player day ends (server ms).
static func next_rollover(rule_set: Dictionary, now: int) -> int:
	return Time.get_unix_time_from_datetime_string(day_key(rule_set, now) + "T00:00:00") * 1000 + DAY_MS - _day_shift(rule_set)

static func rested_today(rule_set: Dictionary, state: Dictionary, now: int) -> bool:
	return energy_of(rule_set, state, now).rested_on == day_key(rule_set, now)

static func _day_shift(rule_set: Dictionary) -> int:
	var d: Dictionary = rule_set.energy.day
	return (int(d.utc_offset_hours) - int(d.rollover_hour)) * 3600000

## An id as the server's rules and saves take them: 1–64 of a–z, 0–9, _ and -.
static func _is_id(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[a-z0-9_-]{1,64}$").search(value) != null

static func _is_day(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(value) != null

# ------------------------------------------------------------------ Request board (C-191, server requests.ts)

## 32-bit FNV-1a with murmur3's finish, as the server's hash32 (ASCII keys: a byte is a JS char code). Ints stay in
## [0, 2^32); _mul32 keeps every product inside 64 bits.
static func hash32(key: String) -> int:
	var h := 0x811c9dc5
	for c in key.to_ascii_buffer(): h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF
	h ^= h >> 16
	h = _mul32(h, 0x85ebca6b)
	h ^= h >> 13
	h = _mul32(h, 0xc2b2ae35)
	h ^= h >> 16
	return h

## a × b mod 2^32 (JS Math.imul's bits) for a, b in [0, 2^32).
static func _mul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF

## The tier for a farm level: the last whose level it has reached, of `template`'s own tiers when it has them, else of
## its item's `item_tiers` (C-197), else of the shared ones.
static func tier_for(rule_set: Dictionary, level: int, template := "") -> Dictionary:
	var q: Dictionary = rule_set.requests
	var own: Dictionary = q.templates.get(template, {})
	var tiers: Array = own.get("tiers", q.get("item_tiers", {}).get(own.get("item", ""), q.tiers))
	var tier: Dictionary = tiers[0]
	for t: Dictionary in tiers:
		if level >= int(t.level): tier = t
	return tier

## One item's floor price on the board: Jasmine's price × `floor_percent`%, rounded down (C-197: 100%, her price).
static func floor_price(rule_set: Dictionary, item: String) -> int:
	return int(rule_set.economy.sell_prices.get(item, 0)) * int(rule_set.requests.floor_percent) / 100

## The templates that can be drawn now, in the rules' order: those naming no building, or one the farm has.
static func eligible_templates(rule_set: Dictionary, state: Dictionary) -> Array:
	var out := []
	for id: String in rule_set.requests.templates:
		var b = rule_set.requests.templates[id].get("building")
		if b == null or buildings_of(state).any(func(x): return x is Dictionary and x.get("type") == b): out.append(id)
	return out

## Done and bonus paid in the current player day: {done, bonus}.
static func board_today(rule_set: Dictionary, state: Dictionary, now: int) -> Dictionary:
	var b: Dictionary = state.get("board", empty_board())
	if b.get("day") == day_key(rule_set, now): return {"done": int(b.done_today), "bonus": int(b.bonus_today)}
	return {"done": 0, "bonus": 0}

## Draws slot `slot`'s request at `at` (server requests.ts draw): the open templates less those on the other slots (and
## an expired one still in this slot), unless that leaves none; count and bonus by the farm level now. null: none open.
static func _draw(rule_set: Dictionary, state: Dictionary, slot: int, at: int) -> Variant:
	var q: Dictionary = rule_set.requests
	var b: Dictionary = state.board
	var open := eligible_templates(rule_set, state)
	if open.is_empty(): return null
	var taken := {}
	for sl: Dictionary in b.slots:
		if sl.req != null: taken[sl.req.template] = true
	var pool := open.filter(func(id): return not taken.has(id))
	if pool.is_empty(): pool = open
	var seed := "%d:%d:%d:%d" % [int(state.welcomed_at), slot, at, int(b.seq) + 1]
	var template: String = pool[hash32(seed + ":t") % pool.size()]
	var tier := tier_for(rule_set, farm_level(state), template)
	var qty := int(tier.qty[0]) + hash32(seed + ":q") % (int(tier.qty[1]) - int(tier.qty[0]) + 1)
	b.seq = int(b.seq) + 1
	return {"id": int(b.seq), "template": template, "item": q.templates[template].item, "qty": qty, "bonus": int(tier.bonus),
		"drawn_at": at, "status": "open"}

## Brings `state.board` up to `now` in place (server requests.ts settleBoard): slots added from the first entry, a due
## empty slot drawn at its refill time, an open request `expire_seconds` old swapped at the latest period it expired.
## A farm not entered yet, or rules without `requests`, has no board to settle.
static func settle_board(rule_set: Dictionary, state: Dictionary, now: int) -> void:
	var q: Dictionary = rule_set.get("requests", {})
	if q.is_empty() or state.get("welcomed_at") == null: return
	if not state.get("board") is Dictionary: state.board = empty_board()
	var b: Dictionary = state.board
	while b.slots.size() < int(q.slots): b.slots.append({"req": null, "refill_at": int(state.welcomed_at)})
	var expire := int(q.expire_seconds) * 1000
	for i in int(q.slots):
		var sl: Dictionary = b.slots[i]
		if sl.req == null and now >= int(sl.refill_at):
			var drawn = _draw(rule_set, state, i, int(sl.refill_at))
			sl.req = drawn
		if sl.req != null and sl.req.status == "open" and now >= int(sl.req.drawn_at) + expire:
			var at := int(sl.req.drawn_at) + (now - int(sl.req.drawn_at)) / expire * expire
			var swapped = _draw(rule_set, state, i, at)
			sl.req = swapped
			sl.refill_at = at
	var kept := []
	for i in b.slots.size():
		if i < int(q.slots) or b.slots[i].req != null: kept.append(b.slots[i])
	b.slots = kept

## The farm as the server reads it out (routes farmView): a copy with the board settled to `now` and a building from
## before its type's cutouts taken down (C-209).
static func view(rule_set: Dictionary, state: Dictionary, now: int) -> Dictionary:
	var out := state.duplicate(true)
	if not out.has("board"): out.board = empty_board()
	if not out.has("requests_done"): out.requests_done = 0
	retire_draft_buildings(rule_set, out)
	settle_board(rule_set, out, now)
	return out

## The slot holding request `id` on the state's board, or {}.
static func request_slot(state: Dictionary, id: int) -> Dictionary:
	for sl: Dictionary in state.get("board", {}).get("slots", []):
		if sl.req != null and int(sl.req.id) == id: return sl
	return {}

## accept / deliver / drop on `next` (server requests.ts requestCommand), changed only on success: {code, detail}.
static func _request_command(rule_set: Dictionary, next: Dictionary, command: Dictionary, now: int) -> Dictionary:
	var q: Dictionary = rule_set.get("requests", {})
	var id := int(command.request)
	var sl := request_slot(next, id) if not q.is_empty() else {}
	if sl.is_empty(): return {"code": "NO_REQUEST", "detail": {"request": id}}
	var r: Dictionary = sl.req
	match str(command.type):
		"accept_request":
			if r.status == "accepted": return {"code": "ALREADY_ACCEPTED", "detail": {"request": int(r.id)}}
			r.status = "accepted"
		"drop_request":
			sl.req = null
			sl.refill_at = now + int(q.drop_refill_seconds) * 1000
		"deliver_request":
			var done := board_today(rule_set, next, now)
			if int(done.done) >= int(q.daily_max):
				return {"code": "DAILY_LIMIT", "detail": {"max": int(q.daily_max), "resets_at": next_rollover(rule_set, now)}}
			var have := int(next.bag.get(r.item, 0))
			if have < int(r.qty): return {"code": "NOT_ENOUGH", "detail": {"item": r.item, "have": have, "need": int(r.qty)}}
			var bonus := maxi(0, mini(int(r.bonus), int(q.daily_bonus_max) - int(done.bonus)))
			var coins := floor_price(rule_set, r.item) * int(r.qty) + bonus
			if int(next.coins) + coins > MAX_COINS: return {"code": "COINS_CAP", "detail": {"coins": int(next.coins), "max": MAX_COINS}}
			_take(next.bag, r.item, int(r.qty))
			next.coins = int(next.coins) + coins
			next.board.day = day_key(rule_set, now)
			next.board.done_today = int(done.done) + 1
			next.board.bonus_today = int(done.bonus) + bonus
			next.requests_done = int(next.requests_done) + 1
			sl.req = null
			sl.refill_at = now + int(q.done_refill_seconds) * 1000
	return {"code": "", "detail": {}}

# ------------------------------------------------------------------ Seed aid (C-197, server seed_aid.ts)

## Whether Jasmine's seed aid can be given now: {code: "", detail: {}} when it can, else the server's refusal in its
## order — no aid in the rules, given this player day already, coins enough for one seed, a crop seed in the bag, a crop
## in the bag or in the ground.
static func seed_aid_refusal(rule_set: Dictionary, state: Dictionary, now: int) -> Dictionary:
	var aid: Dictionary = rule_set.get("seed_aid", {})
	if aid.is_empty(): return {"code": "NO_SEED_AID", "detail": {}}
	if state.get("seed_aid_day") == day_key(rule_set, now):
		return {"code": "SEED_AID_TODAY", "detail": {"resets_at": next_rollover(rule_set, now)}}
	var price := int(rule_set.economy.buy_prices[aid.item])
	var coins := int(state.get("coins", 0))
	if coins >= price: return {"code": "CONDITION_NOT_MET", "detail": {"reason": "coins", "coins": coins, "price": price}}
	var seeds := {}
	for id: String in rule_set.crops: seeds[rule_set.crops[id].seed] = true
	var bag: Dictionary = state.get("bag", {})
	for id: String in bag:
		if seeds.has(id) and int(bag[id]) > 0: return {"code": "CONDITION_NOT_MET", "detail": {"reason": "seeds", "item": id}}
	for id: String in bag:
		if rule_set.crops.has(id) and int(bag[id]) > 0: return {"code": "CONDITION_NOT_MET", "detail": {"reason": "crops", "item": id}}
	for cell: String in state.get("crops", {}):
		return {"code": "CONDITION_NOT_MET", "detail": {"reason": "crops", "cell": cell}}
	return {"code": "", "detail": {}}

static func key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

## Canonical "x,y" only (no leading zeros or spaces), as the server stores it; else null.
static func parse_key(value: Variant) -> Variant:
	if not value is String: return null
	var found := RegEx.create_from_string("^(0|[1-9]\\d{0,3}),(0|[1-9]\\d{0,3})$").search(value)
	if found == null: return null
	var cell := Vector2i(int(found.get_string(1)), int(found.get_string(2)))
	return cell if cell.x < MAX_COORD and cell.y < MAX_COORD else null

## First entry into one's own parcel: grant the welcome gift once. null if already welcomed.
static func welcome(rule_set: Dictionary, state: Dictionary, now: int) -> Variant:
	if state.welcomed_at != null: return null
	var next := state.duplicate(true)
	for id: String in rule_set.welcome_gift:
		next.bag[id] = int(next.bag.get(id, 0)) + int(rule_set.welcome_gift[id])
	next.welcomed_at = now
	return next

## The rules' one-off grants (C-151) the state has not had yet, each given once and recorded in `grants`:
## {state, gift} with the items given, or null when every grant was given before. The input is not changed.
static func grant(rule_set: Dictionary, state: Dictionary, now: int) -> Variant:
	var next := state.duplicate(true)
	if not next.get("grants") is Dictionary: next.grants = {}
	var gift := {}
	for id: String in rule_set.grants:
		if next.grants.has(id): continue
		for item: String in rule_set.grants[id]:
			var n := int(rule_set.grants[id][item])
			next.bag[item] = int(next.bag.get(item, 0)) + n
			gift[item] = int(gift.get(item, 0)) + n
		next.grants[id] = now
	return {"state": next, "gift": gift} if not gift.is_empty() else null

## C-209 (server farm.ts retireDraftBuildings): a building placed before its type had `cutouts` (C-192's 8×6 barn) would
## show the new model over its neighbours, so it is taken down when the save is read and the player places it anew: its
## blueprint and the rules' materials (what placing it again takes) go back into the bag, its animals go with it (a new
## one has the rules'), and its drops, laid or not, go into the bag as their product. `drop_seq` stays. Changes `state`
## in place (a copy with `buildings` and `drops`); true when one was taken down.
static func retire_draft_buildings(rule_set: Dictionary, state: Dictionary) -> bool:
	var gone := {}
	for b: Dictionary in buildings_of(state):
		var rule = rule_set.get("buildings", {}).get(str(b.type))
		if rule is Dictionary and not cutouts_of(rule).is_empty() and cutouts_of(b).is_empty(): gone[int(b.id)] = rule
	if gone.is_empty(): return false
	for id: int in gone:
		var back := {gone[id].blueprint: 1}
		back.merge(gone[id].get("materials", {}))
		for item: String in back: state.bag[item] = int(state.bag.get(item, 0)) + int(back[item])
	for d: Dictionary in state.get("drops", []):
		if gone.has(int(d.building)): state.bag[d.item] = int(state.bag.get(d.item, 0)) + int(d.amount)
	state.drops = state.get("drops", []).filter(func(d: Dictionary): return not gone.has(int(d.building)))
	state.buildings = buildings_of(state).filter(func(b: Dictionary): return not gone.has(int(b.id)))
	state.house = home_of(state.buildings)
	return true

## A rules entry's or a saved building's `cutouts` (C-202), [] without.
static func cutouts_of(entry: Dictionary) -> Array:
	return entry.get("cutouts", []) if entry.get("cutouts") is Array else []

## A footprint's size: `base` is width × depth unturned; a quarter or three-quarter turn swaps them.
static func turned(base: Vector2i, rotation: int) -> Vector2i:
	return Vector2i(base.y, base.x) if rotation % 2 else base

## The cells of a footprint whose lowest-x, lowest-y cell is `at`, its `cutouts` (C-202) left out.
## Row by row from the lowest y, each from the lowest x.
static func footprint(at: Vector2i, base: Vector2i, rotation: int, cutouts := []) -> Array[Vector2i]:
	var own := {}
	for cell: Vector2i in own_cells(base, cutouts): own[own_to_grid(cell, base, rotation)] = true
	var s := turned(base, rotation)
	var out: Array[Vector2i] = []
	for dy in s.y:
		for dx in s.x:
			if own.has(Vector2i(dx, dy)): out.append(at + Vector2i(dx, dy))
	return out

## C-202 the cells of an unturned width × depth footprint (`base`) that are the building's, in its own frame (x right,
## y the frame's z, toward the entry), row by row from the rear: all but those in a well-formed rect of `cutouts`.
static func own_cells(base: Vector2i, cutouts := []) -> Array[Vector2i]:
	var cut := {}
	for r in cutouts:
		if not r is Array or r.size() != 4: continue
		var whole := true
		for v in r: whole = whole and (v is int or (v is float and v == floorf(v)))
		if not whole: continue
		for z in range(maxi(0, int(r[1])), mini(base.y, int(r[1]) + int(r[3]))):
			for x in range(maxi(0, int(r[0])), mini(base.x, int(r[0]) + int(r[2]))): cut[Vector2i(x, z)] = true
	var out: Array[Vector2i] = []
	for z in base.y:
		for x in base.x:
			if not cut.has(Vector2i(x, z)): out.append(Vector2i(x, z))
	return out

## C-202 where a cell of the building's own unturned frame (x right, y toward the entry; it may lie outside the
## footprint) falls from the turned footprint's lowest cell. Unturned, the entry row is the lowest grid y; each turn
## spins it a quarter about the footprint's middle, as FarmBuilding.transform turns the model (server farm.ts footprint).
static func own_to_grid(own: Vector2i, base: Vector2i, rotation: int) -> Vector2i:
	match posmod(rotation, 4):
		1: return Vector2i(own.y, own.x)
		2: return Vector2i(base.x - 1 - own.x, own.y)
		3: return Vector2i(base.y - 1 - own.y, base.x - 1 - own.x)
	return Vector2i(own.x, base.y - 1 - own.y)

## A saved building's cells.
static func building_footprint(b: Dictionary) -> Array[Vector2i]:
	return footprint(Vector2i(int(b.x), int(b.y)), Vector2i(int(b.width), int(b.depth)), int(b.rotation), b.get("cutouts", []))

## Cells under every building, as {Vector2i: true}.
static func building_cells(state: Dictionary) -> Dictionary:
	var cells := {}
	for b: Dictionary in buildings_of(state):
		for at in building_footprint(b): cells[at] = true
	return cells

## All commands succeed or none do, like the server: {ok, state} or {ok:false, index, code, detail}.
## `parcel_id` is the owner's parcel (block id), which `gather` ids must name.
static func apply(rule_set: Dictionary, state: Dictionary, commands: Array, now: int, parcel_id := "") -> Dictionary:
	if commands.is_empty() or commands.size() > MAX_BATCH:
		return {"ok": false, "index": 0, "code": "SCHEMA"}
	var next := state.duplicate(true)
	var blank := empty_state()
	for field in ["coins", "sales", "gathered", "blueprints_claimed", "drops", "drop_seq", "pail_water", "grants", "board", "requests_done",
			"seed_aid_day"]:
		if not next.has(field): next[field] = blank[field]
	next.level = farm_level(next)
	next.buildings = buildings_of(next).duplicate(true)
	retire_draft_buildings(rule_set, next)
	settle_energy(rule_set, next, now)
	settle_board(rule_set, next, now)   # C-191: before the first command and again after the batch
	for index in commands.size():
		var command = commands[index]
		if not command is Dictionary or command.get("type") not in COMMANDS:
			return {"ok": false, "index": index, "code": "SCHEMA"}
		if command.type == "sell" or command.type == "buy":
			var most := MAX_SELL_COUNT if command.type == "sell" else MAX_BUY_COUNT
			if not command.get("item") is String or str(command.item).length() > 64 or not whole_in(command.get("count"), 1, most):
				return {"ok": false, "index": index, "code": "SCHEMA"}
		elif command.type == "claim_blueprint":
			if not command.get("blueprint") is String or str(command.blueprint).length() > 64:
				return {"ok": false, "index": index, "code": "SCHEMA"}
		elif command.type == "gather":
			if not command.get("object") is String or str(command.object).length() > Gather.MAX_OBJECT_LENGTH:
				return {"ok": false, "index": index, "code": "SCHEMA"}
		elif command.type == "rest" or command.type == "upgrade_farm" or command.type == "claim_seed_aid":
			pass
		elif command.type == "feed" or command.type == "pick_up":
			if not whole_in(command.get("building" if command.type == "feed" else "drop"), 1, MAX_ID):
				return {"ok": false, "index": index, "code": "SCHEMA"}
		elif command.type == "draw_water":
			if not whole_in(command.get("building"), 1, 1 << 30): return {"ok": false, "index": index, "code": "SCHEMA"}
		elif command.type in REQUEST_COMMANDS:
			if not whole_in(command.get("request"), 1, MAX_ID): return {"ok": false, "index": index, "code": "SCHEMA"}
		elif command.type == "place_house" or command.type == "place_building":
			if not whole_in(command.get("x"), 0, MAX_COORD - 1) or not whole_in(command.get("y"), 0, MAX_COORD - 1) \
					or (command.has("rotation") and not whole_in(command.rotation, 0, 3)) \
					or (command.type == "place_building" and (not command.get("building") is String or str(command.building).length() > 64)):
				return {"ok": false, "index": index, "code": "SCHEMA"}
		elif parse_key(command.get("cell")) == null:
			return {"ok": false, "index": index, "code": "SCHEMA"}
		var cell: String = command.get("cell", "")
		var failure := ""
		var detail := {}
		# Energy after a command's own checks, as the server: short -> NO_ENERGY with need / have / next_in.
		var cost := energy_cost(rule_set, command)
		var short: bool = cost > 0 and int(next.energy.value) < cost
		match command.type:
			"place_house", "place_building":
				var outcome := _place(rule_set, next, command, now)
				failure = outcome.code
				detail = outcome.detail
			"clear_obstacle":
				if cell in next.cleared: failure = "ALREADY_CLEARED"
				elif next.cleared.size() >= MAX_CELLS: failure = "TOO_MANY_CELLS"
				elif short: failure = "NO_ENERGY"
				else:
					_spend(rule_set, next, now, cost)
					next.cleared.append(cell)
			"till":
				if int(next.bag.get(rule_set.till_tool, 0)) <= 0:
					failure = "NO_TOOL"
					detail = {"item": rule_set.till_tool}
				elif building_cells(next).has(parse_key(cell)):
					failure = "CELL_OCCUPIED"
					detail = {"cells": [cell]}
				elif cell in next.tilled: failure = "ALREADY_TILLED"
				elif next.tilled.size() >= MAX_CELLS: failure = "TOO_MANY_CELLS"
				elif short: failure = "NO_ENERGY"
				else:
					_spend(rule_set, next, now, cost)
					next.tilled.append(cell)
			"sow":
				var crop = command.get("crop")
				var crop_rule = rule_set.crops.get(crop) if crop is String else null
				if crop_rule == null: failure = "UNKNOWN_CROP"
				elif cell not in next.tilled: failure = "NOT_TILLED"
				elif next.crops.has(cell):
					failure = "CELL_OCCUPIED"
					detail = {"cells": [cell]}
				elif int(next.bag.get(crop_rule.seed, 0)) <= 0:
					failure = "NO_SEED"
					detail = {"item": crop_rule.seed}
				elif short: failure = "NO_ENERGY"
				else:
					_spend(rule_set, next, now, cost)
					_take(next.bag, crop_rule.seed)
					# C-151: sown on dry soil, it counts no time until it is watered.
					next.crops[cell] = {"crop": crop, "planted_at": now, "ripe_at": NEVER, "watered_at": null}
			"draw_water":
				# At the well (the scene keeps the key there); the server can check the well is built.
				var water: Dictionary = rule_set.watering
				var at := -1
				for i in next.buildings.size():
					if int(next.buildings[i].id) == int(command.building): at = i
				if at < 0 or next.buildings[at].type != water.well:
					failure = "NO_WELL"
					detail = {"building": int(command.building)}
				elif int(next.bag.get(water.pail, 0)) <= 0:
					failure = "NO_PAIL"
					detail = {"item": water.pail}
				elif int(next.pail_water) >= int(water.pail_uses):
					failure = "PAIL_FULL"
					detail = {"water": int(next.pail_water)}
				elif short: failure = "NO_ENERGY"
				else:
					_spend(rule_set, next, now, cost)
					next.pail_water = int(water.pail_uses)
			"water":
				var planted = next.crops.get(cell)
				var pail: String = rule_set.watering.pail
				if int(next.bag.get(pail, 0)) <= 0:
					failure = "NO_PAIL"
					detail = {"item": pail}
				elif planted == null: failure = "NO_CROP"
				elif not is_dry(planted): failure = "ALREADY_WATERED"
				elif int(next.pail_water) <= 0: failure = "PAIL_EMPTY"
				elif not rule_set.crops.has(planted.crop): failure = "UNKNOWN_CROP"
				else:
					next.pail_water = int(next.pail_water) - 1
					planted.watered_at = now
					planted.ripe_at = now + int(rule_set.crops[planted.crop].grow_seconds) * 1000
			"harvest":
				var planted = next.crops.get(cell)
				if planted == null: failure = "NO_CROP"
				elif is_dry(planted): failure = "NOT_WATERED"
				elif now < int(planted.ripe_at):
					failure = "NOT_RIPE"
					detail = {"ripe_at": planted.ripe_at}
				else:
					next.crops.erase(cell)
					var amount := int(rule_set.crops[planted.crop]["yield"]) if rule_set.crops.has(planted.crop) else 1
					next.bag[planted.crop] = int(next.bag.get(planted.crop, 0)) + amount
			"sell":
				# The price is the rules' only (the server ignores any price in a request).
				var item: String = command.item
				var count := int(command.count)
				var prices: Dictionary = rule_set.get("economy", {}).get("sell_prices", {})
				var have := int(next.bag.get(item, 0))
				if not prices.has(item):
					failure = "NOT_SELLABLE"
					detail = {"item": item}
				elif have < count:
					failure = "NOT_ENOUGH"
					detail = {"item": item, "have": have, "need": count}
				elif int(next.coins) + int(prices[item]) * count > MAX_COINS:
					failure = "COINS_CAP"
					detail = {"coins": next.coins, "max": MAX_COINS}
				else:
					_take(next.bag, item, count)
					next.coins = int(next.coins) + int(prices[item]) * count
					next.sales = int(next.sales) + 1
			"buy":
				# The price is the rules' only (the server ignores any price in a request).
				var item: String = command.item
				var prices: Dictionary = rule_set.get("economy", {}).get("buy_prices", {})
				var total := int(prices.get(item, 0)) * int(command.count)
				if not prices.has(item):
					failure = "NOT_FOR_SALE"
					detail = {"item": item}
				elif int(next.coins) < total:
					failure = "NOT_ENOUGH_COINS"
					detail = {"coins": next.coins, "need": total}
				else:
					next.coins = int(next.coins) - total
					next.bag[item] = int(next.bag.get(item, 0)) + int(command.count)
			"claim_blueprint":
				var blueprint: String = command.blueprint
				var rule = rule_set.get("economy", {}).get("blueprints", {}).get(blueprint)
				if rule == null: failure = "UNKNOWN_BLUEPRINT"
				elif next.blueprints_claimed.has(blueprint): failure = "BLUEPRINT_CLAIMED"
				elif int(next.sales) < int(rule.min_sales):
					failure = "CONDITION_NOT_MET"
					detail = {"sales": next.sales, "min_sales": rule.min_sales}
				elif int(next.get("requests_done", 0)) < int(rule.get("min_requests", 0)):
					# C-182 (SEN-Q-282): the sheep pen's blueprint is sold after 15 delivered requests.
					failure = "CONDITION_NOT_MET"
					detail = {"requests_done": int(next.get("requests_done", 0)), "min_requests": int(rule.min_requests)}
				elif farm_level(next) < int(rule.get("min_level", 1)):
					# C-192 (SEN-Q-282): the barn's blueprint is sold from farm level 2.
					failure = "CONDITION_NOT_MET"
					detail = {"level": farm_level(next), "min_level": int(rule.min_level)}
				elif int(next.coins) < int(rule.get("coins", 0)):
					# C-181: a priced blueprint (the barn's) is bought.
					failure = "NOT_ENOUGH_COINS"
					detail = {"coins": int(next.coins), "need": int(rule.coins)}
				else:
					next.coins = int(next.coins) - int(rule.get("coins", 0))
					next.blueprints_claimed[blueprint] = now
					next.bag[rule.item] = int(next.bag.get(rule.item, 0)) + int(rule.amount)
			"gather":
				# The server knows the core cells under the house, tilled, sown or cleared: not outer.
				var o = Gather.parse_id(command.object)
				var at = parse_key(o.cell) if o != null else null
				var in_core: bool = o != null and (building_cells(next).has(at) or o.cell in next.tilled \
					or next.crops.has(o.cell) or o.cell in next.cleared)
				var outcome := Gather.take(Gather.rules(), next, command.object, parcel_id, in_core, now, short)
				failure = outcome.code
				detail = outcome.detail
				if failure.is_empty(): _spend(rule_set, next, now, cost)
			"rest":
				# At the cottage's door (the scene keeps the key there); the server can check a cottage is among the buildings.
				var e: Dictionary = next.energy
				var today := day_key(rule_set, now)
				var top := max_energy(rule_set, next)
				if not has_home(next): failure = "NO_HOUSE"
				elif e.rested_on == today:
					failure = "RESTED_TODAY"
					detail = {"resets_at": next_rollover(rule_set, now)}
				elif int(e.value) >= top: failure = "ENERGY_FULL"
				else:
					e.value = int(e.value) + mini(int(rule_set.energy.rest_amount), top - int(e.value))
					e.rested_on = today
					if int(e.value) >= top: e.at = now
			"feed":
				var b := {}
				for x: Dictionary in next.buildings:
					if int(x.id) == int(command.building): b = x
				if b.is_empty():
					failure = "NO_BUILDING"
					detail = {"building": int(command.building)}
				else:
					failure = feed_refusal(rule_set, next, b, now)
					var rule := livestock_of(rule_set, b)
					var mine := drops_in(next, int(b.id))
					match failure:
						"NOT_LIVESTOCK": detail = {"building": int(command.building)}
						"NO_FEED": detail = {"item": rule.feed}
						"GROUND_FULL": detail = {"max": int(rule.max_ground)}
						"ANIMALS_FED":
							var soonest := 0
							for d: Dictionary in mine:
								if int(d.ready_at) > now and (soonest == 0 or int(d.ready_at) < soonest): soonest = int(d.ready_at)
							detail = {"next_at": soonest}
						"":
							if short: failure = "NO_ENERGY"
							else:
								_spend(rule_set, next, now, cost)
								_take(next.bag, rule.feed, int(rule.get("feed_amount", 1)))
								next.drop_seq = int(next.drop_seq) + 1
								var id := int(next.drop_seq)
								next.drops.append({"id": id, "item": rule.product, "amount": int(rule.amount), "building": int(b.id),
									"animal": _free_animal(b, mine, now), "spot": _free_spot((rule.spots as Array).size(), mine, id),
									"ready_at": now + int(rule.produce_seconds) * 1000})
			"pick_up":
				var at := -1
				for i in (next.drops as Array).size():
					if int(next.drops[i].id) == int(command.drop): at = i
				if at < 0:
					failure = "NO_DROP"
					detail = {"drop": int(command.drop)}
				elif now < int(next.drops[at].ready_at):
					failure = "NOT_READY"
					detail = {"ready_at": int(next.drops[at].ready_at)}
				else:
					var d: Dictionary = next.drops[at]
					next.drops.remove_at(at)
					next.bag[d.item] = int(next.bag.get(d.item, 0)) + int(d.amount)
			"upgrade_farm":
				# At Scott's (the town keeps the key there): materials in the rules' order, then coins; no Energy.
				var up := next_level(rule_set, int(next.level))
				if up.is_empty():
					failure = "MAX_LEVEL"
					detail = {"level": int(next.level)}
				else:
					for item: String in up.items:
						var have := int(next.bag.get(item, 0))
						if have < int(up.items[item]):
							failure = "NOT_ENOUGH"
							detail = {"item": item, "have": have, "need": int(up.items[item])}
							break
					if failure.is_empty() and int(next.coins) < int(up.coins):
						failure = "NOT_ENOUGH_COINS"
						detail = {"coins": int(next.coins), "need": int(up.coins)}
					if failure.is_empty():
						for item: String in up.items: _take(next.bag, item, int(up.items[item]))
						next.coins = int(next.coins) - int(up.coins)
						for item: String in up.get("gift", {}): next.bag[item] = int(next.bag.get(item, 0)) + int(up.gift[item])
						# Energy was settled to now above, so the higher top fills from the upgrade on.
						next.level = int(up.level)
			"accept_request", "deliver_request", "drop_request":
				# At the Travel Post's board (the room keeps the drawer there); the server cannot tell where the player is.
				var outcome := _request_command(rule_set, next, command, now)
				failure = outcome.code
				detail = outcome.detail
			"claim_seed_aid":
				# At Jasmine's (the town sends it as her greeting opens); the server cannot tell where the player is.
				var refusal := seed_aid_refusal(rule_set, next, now)
				failure = refusal.code
				detail = refusal.detail
				if failure.is_empty():
					var aid: Dictionary = rule_set.seed_aid
					next.bag[aid.item] = int(next.bag.get(aid.item, 0)) + int(aid.amount)
					next.seed_aid_day = day_key(rule_set, now)
		if failure == "NO_ENERGY":
			detail = {"need": cost, "have": int(next.energy.value), "next_in": next_tick_in(rule_set, next, now)}
		if not failure.is_empty():
			var result := {"ok": false, "index": index, "code": failure}
			if not detail.is_empty(): result.detail = detail
			return result
	settle_board(rule_set, next, now)
	return {"ok": true, "state": next}

## `place_building` (and `place_house`, the cottage) on `next`, changed only on success: {code, detail}, code "" when
## built. Like the server: a known type under its limit, its blueprint, on the grid, off every other building
## (BUILDING_OVERLAP) and off tilled cells and crops (CELL_OCCUPIED), the turned footprint counting.
static func _place(rule_set: Dictionary, next: Dictionary, command: Dictionary, now: int) -> Dictionary:
	var old := str(command.type) == "place_house"
	var type: String = HOME_BUILDING if old else str(command.building)
	var rule = rule_set.buildings.get(type)
	if not rule is Dictionary: return {"code": "UNKNOWN_BUILDING", "detail": {"building": type}}
	var same := 0
	var id := 0
	for b: Dictionary in next.buildings:
		if b.type == type: same += 1
		id = maxi(id, int(b.id))
	var most := building_max(rule_set, type, farm_level(next))   # C-152: wells 2 from Lv3, 3 from Lv5
	if same >= most:
		return {"code": "HOUSE_PLACED", "detail": {}} if old else {"code": "BUILDING_LIMIT", "detail": {"building": type, "max": most}}
	if next.buildings.size() >= MAX_BUILDINGS: return {"code": "BUILDING_LIMIT", "detail": {"max": MAX_BUILDINGS}}
	if int(next.bag.get(rule.blueprint, 0)) <= 0: return {"code": "NO_BLUEPRINT", "detail": {"item": rule.blueprint}}
	# C-154: materials besides the blueprint (none by default).
	for item: String in rule.get("materials", {}):
		var need := int(rule.materials[item])
		if int(next.bag.get(item, 0)) < need:
			return {"code": "NOT_ENOUGH", "detail": {"item": item, "have": int(next.bag.get(item, 0)), "need": need}}
	var building := {"id": id + 1, "type": type, "model": rule.model, "x": int(command.x), "y": int(command.y),
		"width": int(rule.width), "depth": int(rule.depth), "rotation": int(command.get("rotation", 0)), "built_at": now}
	var far := Vector2i(building.x, building.y) + turned(Vector2i(building.width, building.depth), building.rotation) - Vector2i.ONE
	if far.x >= MAX_COORD or far.y >= MAX_COORD: return {"code": "OUT_OF_BOUNDS", "detail": {}}
	if not (rule.get("cutouts", []) as Array).is_empty(): building.cutouts = (rule.cutouts as Array).duplicate(true)
	var cells := building_footprint(building)
	var under := building_cells(next)
	var overlap: Array = []
	for at: Vector2i in cells:
		if under.has(at): overlap.append(key(at))
	if not overlap.is_empty():
		overlap.sort()
		return {"code": "BUILDING_OVERLAP", "detail": {"cells": overlap}}
	var covered: Array = []
	for k: String in next.tilled + next.crops.keys():
		if cells.has(parse_key(k)) and k not in covered: covered.append(k)
	if not covered.is_empty():
		covered.sort()
		return {"code": "CELL_OCCUPIED", "detail": {"cells": covered}}
	_take(next.bag, rule.blueprint)
	for item: String in rule.get("materials", {}): _take(next.bag, item, int(rule.materials[item]))
	if rule.has("livestock"): building.animals = (rule.livestock.animals as Array).duplicate()
	next.buildings.append(building)
	next.house = home_of(next.buildings)
	return {"code": "", "detail": {}}

static func _take(bag: Dictionary, id: String, count := 1) -> void:
	bag[id] = int(bag[id]) - count
	if bag[id] <= 0: bag.erase(id)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func whole_in(value: Variant, low: int, high: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high
