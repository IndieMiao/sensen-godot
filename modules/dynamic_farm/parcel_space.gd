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
## Rest at the cottage (C-148): once a player day, nothing to gain when full.
const RESTED := "rested"
const FULL := "full"
## The pail (C-151): none in the bag, nothing left in it to water with, or already full at the well.
const NO_PAIL := "no_pail"
const PAIL_EMPTY := "pail_empty"
const PAIL_FULL := "pail_full"

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
## C-151: a well's cell fills the pail there (only beside the well: the server cannot tell where the player stands);
## a sown, unwatered crop is watered from the pail.
static func action(rules: Dictionary, data: Dictionary, path: Dictionary, obstacles: Dictionary,
		state: Dictionary, cell: Vector2i, now: int) -> Dictionary:
	if not data.by_cell.has(cell): return {}
	if door_row(state).has(cell): return rest_action(rules, state, now)
	var well = well_cells(rules, state).get(cell)
	if well != null: return fill_action(rules, state, well)
	var key := ParcelFarm.key(cell)
	if obstacles.has(cell):
		var anchor := ParcelFarm.key(obstacles[cell])
		if anchor not in state.cleared:
			return {"verb": "clear", "refusal": "", "command": {"type": "clear_obstacle", "cell": anchor}}
	var crop = state.crops.get(key)
	if crop is Dictionary and ParcelFarm.is_dry(crop): return water_action(rules, state, key)
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

## The cottage's cells along its door (C-148: Rest is at the door). The cottage is the first of the save's buildings
## of type ParcelFarm.HOME_BUILDING (C-150). The model's +Z, the door, turns a quarter per rotation step
## (FarmBuilding.transform): rotation 0 faces −y on the grid, 1 +x, 2 +y, 3 −x. {} without a cottage.
static func door_row(state: Dictionary) -> Dictionary:
	var row := {}
	var home := ParcelFarm.home_building(state)
	if home.is_empty(): return row
	var turn := int(home.rotation) % 4
	var cells := ParcelFarm.building_footprint(home)
	var at := Vector2i(int(home.x), int(home.y))
	var last := at
	for cell: Vector2i in cells: last = Vector2i(maxi(last.x, cell.x), maxi(last.y, cell.y))
	for cell: Vector2i in cells:
		if (turn == 0 and cell.y == at.y) or (turn == 2 and cell.y == last.y) or (turn == 1 and cell.x == last.x) \
				or (turn == 3 and cell.x == at.x):
			row[cell] = true
	return row

## The middle of the door row: where a Rest press walks the player to (they stand just outside it).
static func door_cell(state: Dictionary) -> Variant:
	var row := door_row(state).keys()
	if row.is_empty(): return null
	row.sort()
	return row[row.size() / 2]

## The key at the cottage's door: Rest with what it gives now (`gain`), refused once rested today or when full.
static func rest_action(rules: Dictionary, state: Dictionary, now: int) -> Dictionary:
	var probe := state.duplicate()
	var energy := ParcelFarm.settle_energy(rules, probe, now)
	var gain := mini(int(rules.energy.rest_amount), ParcelFarm.max_energy(rules, probe) - int(energy.value))
	var refusal := RESTED if ParcelFarm.rested_today(rules, probe, now) else FULL if gain <= 0 else ""
	return {"verb": "rest", "refusal": refusal, "command": {"type": "rest"} if refusal.is_empty() else {}, "gain": maxi(0, gain)}

## The cells under the wells (C-151), as {Vector2i: the well's building id}.
static func well_cells(rules: Dictionary, state: Dictionary) -> Dictionary:
	var cells := {}
	for well: Dictionary in ParcelFarm.wells(rules, state):
		for at in ParcelFarm.building_footprint(well): cells[at] = int(well.id)
	return cells

## The key at a well: Fill draws a full pail (`draw_water`), refused without a pail or with the pail full.
static func fill_action(rules: Dictionary, state: Dictionary, well: int) -> Dictionary:
	var water: Dictionary = rules.watering
	var refusal := NO_PAIL if int(state.bag.get(water.pail, 0)) <= 0 \
		else PAIL_FULL if int(state.get("pail_water", 0)) >= int(water.pail_uses) else ""
	return {"verb": "fill", "refusal": refusal, "building": well,
		"command": {"type": "draw_water", "building": well} if refusal.is_empty() else {}}

## The key on a sown, unwatered crop: Water uses one from the pail, refused without a pail or with it empty.
static func water_action(rules: Dictionary, state: Dictionary, key: String) -> Dictionary:
	var refusal := NO_PAIL if int(state.bag.get(rules.watering.pail, 0)) <= 0 \
		else PAIL_EMPTY if int(state.get("pail_water", 0)) <= 0 else ""
	return {"verb": "water", "refusal": refusal, "command": {"type": "water", "cell": key} if refusal.is_empty() else {}}
