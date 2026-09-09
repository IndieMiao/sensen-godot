class_name StreetResidents
extends Node3D

const CLEARANCE := 0.65
var layout: JourneyStreets
var moments: Dictionary = {}
var waits: Dictionary = {}
var player_position := Vector3.ZERO
var gathering := ""

func setup(value: JourneyStreets, state: Dictionary) -> void:
	layout = value
	for slot in StreetCommons.PLACES:
		if not StreetCommons.available(state, slot): continue
		var common: Dictionary = layout.commons[slot]
		var home: Vector3 = common.approach
		var candidates := nearby(home, 4)
		var home_grid := navigation([layout.entrances.farm])
		for point in candidates:
			if point.distance_to(home) < 1.8 or point.distance_to(home) > 3.0: continue
			if layout.entrances.values().any(func(p): return p.distance_to(point) < 1.5): continue
			if layout.caches.values().any(func(pair): return pair[0].distance_to(point) < 2.4 or pair[1].distance_to(point) < 2.4): continue
			if positions().any(func(p): return p.distance_to(point) < 2.0): continue
			if layout.commons.keys().any(func(other): return other != slot and layout.commons[other].approach.distance_to(point) < 1.5): continue
			if not home_grid.point_path(home, point).is_empty():
				home = point
				break
		var rig := Avatar.create_rig()
		rig.assembler = AvatarAssemblerMerged.new()
		for child in rig.get_children():
			if child is RigActivity:
				child.reduced_distance = 50
				child.sleep_distance = 80
		rig.name = StreetCommons.RESIDENTS[slot]
		rig.position = home
		rig.config_applied.connect(ResidentCast._play_idle.bind(rig))
		add_child(rig)
		rig.apply_config(ResidentCast.outfit(str(rig.name)))
		moments[slot] = ResidentMoment.new(rig, Vector3.ZERO)
		waits[slot] = 1.0 + moments.size() * 1.2
	set_gathering(JourneyGatherings.current(state))

func set_gathering(theme: String) -> void:
	if gathering == theme: return
	gathering = theme
	for slot in moments:
		if theme.is_empty(): moments[slot].finish()
		else: _join_gathering(str(slot))

func _join_gathering(slot: String) -> void:
	var venue: Dictionary = layout.gatherings[gathering]
	var index := StreetCommons.PLACES.keys().find(slot)
	moments[slot].start(venue.guests[index], venue.position, "idle", INF)

func nearby(point: Vector3, radius: int) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var cell := layout.nav.world_to_cell(point)
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var next := cell + Vector2i(x, z)
			if layout.nav.is_walkable(next): result.append(layout.nav.cell_to_world(next))
	result.sort_custom(func(a, b): return a.distance_squared_to(point) < b.distance_squared_to(point))
	return result

func positions(except := "") -> Array[Vector3]:
	var result: Array[Vector3] = []
	for slot in moments:
		if slot != except: result.append(moments[slot].actor.position)
	return result

func navigation(blockers: Array[Vector3], departure: Variant = null) -> BlueprintGrid:
	var blueprint := FarmBlueprint.new()
	blueprint.grid = layout.nav.grid
	blueprint.cell_m = layout.nav.cell_m
	blueprint.masks = layout.nav.masks.duplicate(true)
	for point in blockers:
		var cell := blueprint.world_to_cell(point)
		for z in range(cell.y - 2, cell.y + 3):
			for x in range(cell.x - 2, cell.x + 3):
				var c := Vector2i(x, z)
				if not blueprint.in_bounds(c) or blueprint.cell_to_world(c).distance_to(point) > CLEARANCE + 0.2: continue
				var row: String = blueprint.masks.walkable[z]
				blueprint.masks.walkable[z] = row.substr(0, x) + "0" + row.substr(x + 1)
	# A nearby actor can cover the departure cell after a route was planned.
	# Permit leaving that cell; step_clear still enforces the physical separation.
	if departure is Vector3:
		var cell := blueprint.world_to_cell(departure)
		if layout.nav.is_walkable(cell):
			var row: String = blueprint.masks.walkable[cell.y]
			blueprint.masks.walkable[cell.y] = row.substr(0, cell.x) + "1" + row.substr(cell.x + 1)
	return BlueprintGrid.new(blueprint)

func route(destination: Vector3, slot: String) -> PlayerMover:
	var blockers := positions(slot)
	blockers.append(player_position)
	var grid := navigation(blockers, moments[slot].actor.position)
	var movement := PlayerMover.new(grid.bp, grid)
	movement.position = moments[slot].actor.position
	if movement.set_target_position(destination): return movement
	# A conversation can leave the player on the work spot. Work beside it when reachable.
	if moments[slot].phase == "approaching" and destination.is_equal_approx(layout.commons[slot].approach):
		for point in nearby(destination, 3):
			if point.distance_to(destination) <= 1.5 and movement.set_target_position(point): return movement
	return null

func step_clear(from: Vector3, to: Vector3, slot: String) -> bool:
	var blockers := positions(slot)
	blockers.append(player_position)
	for point in blockers:
		if Geometry3D.get_closest_point_to_segment(point, from, to).distance_to(point) < CLEARANCE: return false
	return true

func step(dt: float, paused: bool, player: Vector3) -> void:
	player_position = player
	for slot in moments:
		var moment: ResidentMoment = moments[slot]
		moment.step(dt, paused, route.bind(slot), step_clear.bind(slot))
		if paused or moment.active(): continue
		if not gathering.is_empty():
			_join_gathering(str(slot))
			continue
		waits[slot] -= dt
		if waits[slot] > 0: continue
		waits[slot] = 6.0
		var common: Dictionary = layout.commons[slot]
		moment.start(common.approach, common.position, {"nursery": "labour_water", "restorer": "labour_clear", "bistro": "labour_sow"}[slot], 5.0)

func respond(slot: String) -> void:
	if not moments.has(slot): return
	if not gathering.is_empty():
		_join_gathering(slot)
		return
	var common: Dictionary = layout.commons[slot]
	moments[slot].start(common.approach, common.position, {"nursery": "labour_water", "restorer": "labour_clear", "bistro": "labour_sow"}[slot], 6.0)
