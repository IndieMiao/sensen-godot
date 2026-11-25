extends RefCounted
## Where the owner may farm inside their own parcel (Q-39, C-34#14). The server holds no
## parcel geometry (C-31), so these spatial rules are the client's: tilling only on free
## core cells, never under a building (C-150; the refusal still reads "House here"), on the protected path or outside the core.
##
## Schema 4 marks every core cell "no solid decor", so the protected path inside the core
## is derived here: the shortest walk from the entry to the spawn, widened by
## PATH_HALF_WIDTH cells, plus the spawn clearance core obstacles already keep free.
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const PATH_HALF_WIDTH := 1
const SPAWN_CLEARANCE := 1
const NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

## Refusals, in the order they are checked for an empty cell.
const OUTSIDE := "outside"
const PATH := "path"
const HOUSE := "house"
const NO_TOOL := "no_tool"
const NO_SEED := "no_seed"
const NOT_RIPE := "not_ripe"

## Core cells of the protected path, as {Vector2i: true}.
static func protected_path(data: Dictionary) -> Dictionary:
	var previous := {data.entry: data.entry}
	var queue: Array[Vector2i] = [data.entry]
	var index := 0
	while index < queue.size() and not previous.has(data.spawn):
		var at := queue[index]
		index += 1
		for offset: Vector2i in NEIGHBORS:
			var next := at + offset
			if data.by_cell.has(next) and not previous.has(next):
				previous[next] = at
				queue.append(next)
	var line: Array[Vector2i] = []
	if previous.has(data.spawn):
		var at: Vector2i = data.spawn
		while at != data.entry:
			line.append(at)
			at = previous[at]
		line.append(data.entry)
	var path := {}
	for at in line:
		_mark_core(data, path, at, PATH_HALF_WIDTH)
	_mark_core(data, path, data.spawn, SPAWN_CLEARANCE)
	return path

static func _mark_core(data: Dictionary, into: Dictionary, center: Vector2i, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var at := center + Vector2i(dx, dy)
			if data.by_cell.has(at) and data.by_cell[at].zone == "core":
				into[at] = true

## Why an empty cell cannot be tilled, or "" when it can (the hoe is checked separately).
static func till_refusal(data: Dictionary, path: Dictionary, state: Dictionary, cell: Vector2i) -> String:
	if not Data.permits(data, cell, "till"): return OUTSIDE
	if ParcelFarm.building_cells(state).has(cell): return HOUSE
	if path.has(cell): return PATH
	return ""

## The main key for one cell: {verb, refusal, command, ripe_in_ms}. `command` is {} when the key
## does nothing; `refusal` names why. `obstacles` maps every cell an uncleared core obstacle covers
## to its anchor cell, which names the obstacle in `clear_obstacle` and `cleared` (a tree covers
## a block of cells). Returns {} for a cell off the parcel.
static func action(rules: Dictionary, data: Dictionary, path: Dictionary, obstacles: Dictionary,
		state: Dictionary, cell: Vector2i, now: int) -> Dictionary:
	if not data.by_cell.has(cell): return {}
	var key := ParcelFarm.key(cell)
	if obstacles.has(cell):
		var anchor := ParcelFarm.key(obstacles[cell])
		if anchor not in state.cleared:
			return {"verb": "clear", "refusal": "", "command": {"type": "clear_obstacle", "cell": anchor}}
	var crop = state.crops.get(key)
	if crop is Dictionary:
		var left := int(crop.ripe_at) - now
		if left > 0:
			return {"verb": "harvest", "refusal": NOT_RIPE, "command": {}, "ripe_in_ms": left}
		return {"verb": "harvest", "refusal": "", "command": {"type": "harvest", "cell": key}}
	if key in state.tilled:
		for crop_id: String in rules.crops:
			if int(state.bag.get(rules.crops[crop_id].seed, 0)) > 0:
				return {"verb": "sow", "refusal": "", "command": {"type": "sow", "cell": key, "crop": crop_id}}
		return {"verb": "sow", "refusal": NO_SEED, "command": {}}
	var refusal := till_refusal(data, path, state, cell)
	if refusal.is_empty() and int(state.bag.get(rules.till_tool, 0)) <= 0: refusal = NO_TOOL
	return {"verb": "till", "refusal": refusal,
		"command": {"type": "till", "cell": key} if refusal.is_empty() else {}}
