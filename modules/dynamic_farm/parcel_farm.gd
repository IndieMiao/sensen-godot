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
## Watering (C-151, owner SEN-C-137#6, #15) mirrors server/src/parcels/farm.ts: a sown crop is dry and counts no time
## (`watered_at` null, `ripe_at` NEVER); `draw_water` at a built well (the rules' `watering.well`) fills the pail to
## `watering.pail_uses` for 2 Energy, `water` uses one on a sown, unwatered cell and starts it growing then. A crop sown
## before watering (no `watered_at`) counts as watered. The rules' `grants` (the well blueprint and the pail) are given
## once per farm on entering; the save keeps the pail's water (`pail_water`) and what was granted (`grants`).
const RULES_PATH := "res://assets/farm/data/dynamic_farm.json"
const STATE_VERSION := 1
const MAX_COORD := 1024
const MAX_CELLS := 8192
const MAX_BATCH := 50
const COMMANDS := ["place_house", "place_building", "clear_obstacle", "till", "sow", "harvest", "sell", "buy", "claim_blueprint",
	"gather", "rest", "draw_water", "water"]
## Commands priced by `energy.costs` (sowing is priced on the crop).
const PRICED := ["clear_obstacle", "till", "gather", "draw_water"]
## A dry crop's `ripe_at` (C-151): the latest time a JS Date holds, never reached (server farm.ts NEVER).
const NEVER := 8640000000000000
const DAY_MS := 86400000
## The first house's building type: an old save's `house` and `place_house` are cottages (server rules.ts HOME_BUILDING).
const HOME_BUILDING := "cottage"
## Most buildings on one parcel, all types together; most cells along a building's side (server rules.ts).
const MAX_BUILDINGS := 64
const MAX_BUILDING_SIDE := 16
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
	parsed["economy"] = _parse_economy(raw.get("economy"))
	return parsed

## C-58 `economy`: sell prices and one-off blueprints; C-149 buy prices (Jasmine's shelf).
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
					and whole_in(rule.get("min_sales"), 0, 1000):
				out.blueprints[id] = {"item": rule.item, "amount": int(rule.amount), "min_sales": int(rule.min_sales)}
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
		"coins": 0, "sales": 0, "gathered": {}, "blueprints_claimed": {}, "pail_water": 0, "grants": {}}

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
	# C-148 Energy: kept when well formed; without it (or malformed, as the server reads it) the farm is at full Energy.
	var energy = raw.get("energy")
	if energy is Dictionary and whole_in(energy.get("value"), 0, 1 << 30) and _number(energy.get("at")) \
			and (energy.get("rested_on") == null or _is_day(energy.get("rested_on"))):
		state.energy = {"value": int(energy.value), "at": int(energy.at), "rested_on": energy.get("rested_on")}
	return state

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

## Farm level (C-152 brings levels; level 1 until then).
static func farm_level(_state: Dictionary) -> int:
	return 1

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

static func _is_day(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(value) != null

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

## A footprint's size: `base` is width × depth unturned; a quarter or three-quarter turn swaps them.
static func turned(base: Vector2i, rotation: int) -> Vector2i:
	return Vector2i(base.y, base.x) if rotation % 2 else base

## The cells of a footprint whose lowest-x, lowest-y cell is `at`.
static func footprint(at: Vector2i, base: Vector2i, rotation: int) -> Array[Vector2i]:
	var s := turned(base, rotation)
	var out: Array[Vector2i] = []
	for dy in s.y:
		for dx in s.x: out.append(at + Vector2i(dx, dy))
	return out

## A saved building's cells.
static func building_footprint(b: Dictionary) -> Array[Vector2i]:
	return footprint(Vector2i(int(b.x), int(b.y)), Vector2i(int(b.width), int(b.depth)), int(b.rotation))

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
	for field in ["coins", "sales", "gathered", "blueprints_claimed", "pail_water", "grants"]:
		if not next.has(field): next[field] = blank[field]
	next.buildings = buildings_of(next).duplicate(true)
	settle_energy(rule_set, next, now)
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
		elif command.type == "rest":
			pass
		elif command.type == "draw_water":
			if not whole_in(command.get("building"), 1, 1 << 30): return {"ok": false, "index": index, "code": "SCHEMA"}
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
				else:
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
		if failure == "NO_ENERGY":
			detail = {"need": cost, "have": int(next.energy.value), "next_in": next_tick_in(rule_set, next, now)}
		if not failure.is_empty():
			var result := {"ok": false, "index": index, "code": failure}
			if not detail.is_empty(): result.detail = detail
			return result
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
	if same >= int(rule.max):
		return {"code": "HOUSE_PLACED", "detail": {}} if old else {"code": "BUILDING_LIMIT", "detail": {"building": type, "max": int(rule.max)}}
	if next.buildings.size() >= MAX_BUILDINGS: return {"code": "BUILDING_LIMIT", "detail": {"max": MAX_BUILDINGS}}
	if int(next.bag.get(rule.blueprint, 0)) <= 0: return {"code": "NO_BLUEPRINT", "detail": {"item": rule.blueprint}}
	var building := {"id": id + 1, "type": type, "model": rule.model, "x": int(command.x), "y": int(command.y),
		"width": int(rule.width), "depth": int(rule.depth), "rotation": int(command.get("rotation", 0)), "built_at": now}
	var cells := building_footprint(building)
	for at: Vector2i in cells:
		if at.x >= MAX_COORD or at.y >= MAX_COORD: return {"code": "OUT_OF_BOUNDS", "detail": {}}
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
