extends RefCounted
## Client copy of the parcel farm state (v1, C-31 server/src/parcels/farm.ts) and its
## commands. The server is authoritative; the local fake store replays the same rules.
## Numbers come from assets/farm/data/dynamic_farm.json (owner decision Q-39, C-34#14),
## shared with the server and separate from the main farm.
const RULES_PATH := "res://assets/farm/data/dynamic_farm.json"
const STATE_VERSION := 1
const MAX_COORD := 1024
const MAX_CELLS := 8192
const MAX_BATCH := 50
const COMMANDS := ["place_house", "clear_obstacle", "till", "sow", "harvest"]

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
	if not raw.get("house") is Dictionary or not raw.house.get("model") is String or not raw.house.get("blueprint") is String \
			or not whole_in(raw.house.get("width"), 1, 16) or not whole_in(raw.house.get("depth"), 1, 16):
		return {}
	for id in raw.welcome_gift:
		if not id is String or not whole_in(raw.welcome_gift[id], 1, 999): return {}
	if raw.crops.is_empty(): return {}
	for id in raw.crops:
		var crop = raw.crops[id]
		if not crop is Dictionary or not crop.get("seed") is String or not whole_in(crop.get("grow_seconds"), 1, 30 * 24 * 3600) or not whole_in(crop.get("yield"), 1, 99):
			return {}
	var parsed: Dictionary = raw.duplicate(true)
	for id in parsed.welcome_gift: parsed.welcome_gift[id] = int(parsed.welcome_gift[id])
	for id in parsed.crops:
		parsed.crops[id].grow_seconds = int(parsed.crops[id].grow_seconds)
		parsed.crops[id]["yield"] = int(parsed.crops[id]["yield"])
	parsed.house.width = int(parsed.house.width)
	parsed.house.depth = int(parsed.house.depth)
	return parsed

static func empty_state() -> Dictionary:
	return {"v": STATE_VERSION, "house": null, "cleared": [], "tilled": [], "crops": {}, "bag": {}, "welcomed_at": null}

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
	for id in raw.bag:
		if not id is String or not whole_in(raw.bag[id], 0, 1 << 30): return {}
		if int(raw.bag[id]) > 0: state.bag[id] = int(raw.bag[id])
	var house = raw.get("house")
	if house is Dictionary:
		for field in ["x", "y", "width", "depth", "rotation"]:
			if not whole_in(house.get(field), 0, MAX_COORD): return {}
		state.house = {"model": str(house.get("model", "")), "x": int(house.x), "y": int(house.y),
			"width": int(house.width), "depth": int(house.depth), "rotation": int(house.rotation),
			"built_at": int(house.get("built_at", 0)) if _number(house.get("built_at")) else 0}
	elif house != null:
		return {}
	var welcomed = raw.get("welcomed_at")
	if welcomed != null and not _number(welcomed): return {}
	state.welcomed_at = int(welcomed) if welcomed != null else null
	return state

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

## Cells under the house; 90°/270° swap width and depth.
static func house_cells(state: Dictionary) -> Dictionary:
	var cells := {}
	var house = state.get("house")
	if not house is Dictionary: return cells
	var size := Vector2i(house.depth, house.width) if int(house.rotation) % 2 else Vector2i(house.width, house.depth)
	for y in size.y:
		for x in size.x:
			cells[Vector2i(int(house.x) + x, int(house.y) + y)] = true
	return cells

## All commands succeed or none do, like the server: {ok, state} or {ok:false, index, code, detail}.
static func apply(rule_set: Dictionary, state: Dictionary, commands: Array, now: int) -> Dictionary:
	if commands.is_empty() or commands.size() > MAX_BATCH:
		return {"ok": false, "index": 0, "code": "SCHEMA"}
	var next := state.duplicate(true)
	for index in commands.size():
		var command = commands[index]
		if not command is Dictionary or command.get("type") not in COMMANDS:
			return {"ok": false, "index": index, "code": "SCHEMA"}
		if command.type == "place_house":
			if not whole_in(command.get("x"), 0, MAX_COORD - 1) or not whole_in(command.get("y"), 0, MAX_COORD - 1) \
					or (command.has("rotation") and not whole_in(command.rotation, 0, 3)):
				return {"ok": false, "index": index, "code": "SCHEMA"}
		elif parse_key(command.get("cell")) == null:
			return {"ok": false, "index": index, "code": "SCHEMA"}
		var cell: String = command.get("cell", "")
		var failure := ""
		var detail := {}
		match command.type:
			"place_house":
				var house := {"model": rule_set.house.model, "x": int(command.x), "y": int(command.y),
					"width": int(rule_set.house.width), "depth": int(rule_set.house.depth),
					"rotation": int(command.get("rotation", 0)), "built_at": now}
				var footprint := house_cells({"house": house})
				var covered: Array = []
				for key: String in next.tilled + next.crops.keys():
					if footprint.has(parse_key(key)) and key not in covered: covered.append(key)
				covered.sort()
				var far := false
				for at: Vector2i in footprint: far = far or at.x >= MAX_COORD or at.y >= MAX_COORD
				if next.house != null: failure = "HOUSE_PLACED"
				elif int(next.bag.get(rule_set.house.blueprint, 0)) <= 0:
					failure = "NO_BLUEPRINT"
					detail = {"item": rule_set.house.blueprint}
				elif far: failure = "OUT_OF_BOUNDS"
				elif not covered.is_empty():
					failure = "CELL_OCCUPIED"
					detail = {"cells": covered}
				else:
					_take(next.bag, rule_set.house.blueprint)
					next.house = house
			"clear_obstacle":
				if cell in next.cleared: failure = "ALREADY_CLEARED"
				elif next.cleared.size() >= MAX_CELLS: failure = "TOO_MANY_CELLS"
				else: next.cleared.append(cell)
			"till":
				if int(next.bag.get(rule_set.till_tool, 0)) <= 0:
					failure = "NO_TOOL"
					detail = {"item": rule_set.till_tool}
				elif house_cells(next).has(parse_key(cell)):
					failure = "CELL_OCCUPIED"
					detail = {"cells": [cell]}
				elif cell in next.tilled: failure = "ALREADY_TILLED"
				elif next.tilled.size() >= MAX_CELLS: failure = "TOO_MANY_CELLS"
				else: next.tilled.append(cell)
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
				else:
					_take(next.bag, crop_rule.seed)
					next.crops[cell] = {"crop": crop, "planted_at": now, "ripe_at": now + int(crop_rule.grow_seconds) * 1000}
			"harvest":
				var planted = next.crops.get(cell)
				if planted == null: failure = "NO_CROP"
				elif now < int(planted.ripe_at):
					failure = "NOT_RIPE"
					detail = {"ripe_at": planted.ripe_at}
				else:
					next.crops.erase(cell)
					var amount := int(rule_set.crops[planted.crop]["yield"]) if rule_set.crops.has(planted.crop) else 1
					next.bag[planted.crop] = int(next.bag.get(planted.crop, 0)) + amount
		if not failure.is_empty():
			var result := {"ok": false, "index": index, "code": failure}
			if not detail.is_empty(): result.detail = detail
			return result
	return {"ok": true, "state": next}

static func _take(bag: Dictionary, id: String) -> void:
	bag[id] = int(bag[id]) - 1
	if bag[id] <= 0: bag.erase(id)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func whole_in(value: Variant, low: int, high: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high
