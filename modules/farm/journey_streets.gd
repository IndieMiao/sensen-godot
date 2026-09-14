class_name JourneyStreets
extends RefCounted

const SCALE := 0.6
const WIDTH := 1.05
const DESTINATIONS := {"farm": Vector2(32, 32), "nursery": Vector2(14, 49),
	"bistro": Vector2(49, 47), "courtyard": Vector2(36, 13)}
var source: FarmBlueprint
var nav: FarmBlueprint
var grid: BlueprintGrid
var roads: Array[PackedVector3Array] = []
var entrances: Dictionary = {}
var buildings: Dictionary = {}
var caches: Dictionary = {}
var walk_caches: Dictionary = {}
const WALK_STOPS := {"bistro_west": "Nursery bend", "bistro_east": "Courtyard bend"}
var commons: Dictionary = {}
var gatherings: Dictionary = {}
var shortcut := PackedVector3Array()
var map_scale := 8.0
var has_farm_access := false

func _init(blueprint: FarmBlueprint, opened := false) -> void:
	source = blueprint
	for path in source.paths:
		var points := PackedVector3Array()
		for point in path.points: points.append(Vector3(point.x, 0, -point.y) * SCALE)
		roads.append(points)
	nav = FarmBlueprint.new()
	nav.grid = Vector2i(64, 64)
	nav.cell_m = SCALE
	_rasterize()
	grid = BlueprintGrid.new(nav)
	var farm := Vector3(19.2, 0, -19.2)
	var access := _entrance(DESTINATIONS.farm * SCALE)
	if road_distance(farm) > WIDTH:
		roads.append(PackedVector3Array([farm, access]))
		has_farm_access = true
		_rasterize()
		grid = BlueprintGrid.new(nav)
	entrances.farm = farm
	for id in DESTINATIONS:
		if id == "farm":
			buildings.farm = _building(farm)
			continue
		entrances[id] = _entrance(DESTINATIONS[id] * SCALE)
		buildings[id] = _building(entrances[id])
	for id in ["nursery", "bistro", "courtyard"]:
		var path := grid.point_path(entrances.farm, entrances[id])
		var point: Vector3 = entrances[id]
		var left := 4.4
		for index in range(path.size() - 2, -2, -1):
			var previous: Vector3 = entrances.farm if index < 0 else path[index]
			var distance := point.distance_to(previous)
			if distance >= left:
				point = point.move_toward(previous, left)
				break
			left -= distance
			point = previous
		var direction: Vector3 = (entrances[id] - point).normalized()
		var normal := Vector3(-direction.z, 0, direction.x)
		caches[id] = [point + normal * 1.4, point - normal * 1.4]
	shortcut = PackedVector3Array([entrances.nursery, entrances.courtyard])
	for slot in StreetCommons.PLACES:
		commons[slot] = _common(str(StreetCommons.PLACES[slot]))
	for leg in [["bistro_west", "nursery"], ["bistro_east", "courtyard"]]:
		walk_caches[leg[0]] = _walk_stop(str(leg[1]))
	for theme in JourneyGatherings.themes():
		var venue := _common(str(JourneyGatherings.themes()[theme].place), true)
		var basis := Basis(Vector3.UP, atan2(-venue.facing.x, -venue.facing.z))
		venue.approach = venue.position + basis * Vector3(0, 0, 1.85)
		venue.guests = [venue.position + basis * Vector3(-1.85, 0, 0), venue.position + basis * Vector3(1.85, 0, 0), venue.position + basis * Vector3(0, 0, -1.85)]
		gatherings[theme] = venue
	if opened: roads.append(shortcut)
	_rasterize(true)
	nav.anchors = {"spawn": nav.world_to_cell(entrances.farm)}
	grid = BlueprintGrid.new(nav)
	var center: Vector2 = source.overlay.get("center", Vector2.ZERO)
	var radius := 0.0
	for path in source.overlay.get("paths", []):
		for point in path:
			var world := MapGeoMath.geo_to_world(point.x, point.y, center.x, center.y)
			radius = maxf(radius, maxf(absf(world.x), absf(world.z)))
	if radius > 0: map_scale = radius / (32 * SCALE)

func _rasterize(free_ground := false) -> void:
	nav.masks = {"walkable": []}
	for z in nav.grid.y:
		var row := ""
		for x in nav.grid.x:
			var point := nav.cell_to_world(Vector2i(x, z))
			var walk := free_ground or road_distance(point) <= WIDTH
			for pair in all_caches():
				for cache in pair:
					if point.distance_to(cache) < 0.95: walk = true
			for venue in gatherings.values():
				if point.distance_to(venue.position) <= 3.25: walk = true
				if point.distance_to(venue.position) < 1.15: walk = false
			if free_ground:
				for building in buildings.values():
					if point.distance_to(building) < 1.65: walk = false
			row += "1" if walk else "0"
		nav.masks.walkable.append(row)

func all_caches() -> Array:
	return caches.values() + walk_caches.values()

func _walk_stop(destination: String) -> Array:
	var path := grid.point_path(entrances.bistro, entrances[destination])
	var desired: Vector3 = path[path.size() / 2] if not path.is_empty() else entrances[destination]
	var candidates: Array[Vector3] = []
	for z in range(4, 60):
		for x in range(4, 60):
			var point := nav.cell_to_world(Vector2i(x, z))
			if nav.is_walkable(Vector2i(x, z)): candidates.append(point)
	candidates.sort_custom(func(a, b): return a.distance_squared_to(desired) < b.distance_squared_to(desired))
	for center in candidates:
		if entrances.values().any(func(point): return point.distance_to(center) < 3.5): continue
		if commons.values().any(func(common): return common.position.distance_to(center) < 5 or common.approach.distance_to(center) < 3.2): continue
		if buildings.values().any(func(point): return point.distance_to(center) < 5): continue
		if all_caches().any(func(pair): return pair[0].distance_to(center) < 4 or pair[1].distance_to(center) < 4): continue
		if grid.point_path(entrances.farm, center).is_empty(): continue
		var distance := INF
		var direction := Vector3.RIGHT
		var anchor := center
		for road in roads:
			for index in road.size() - 1:
				var nearest := Geometry3D.get_closest_point_to_segment(center, road[index], road[index + 1])
				if center.distance_to(nearest) < distance:
					distance = center.distance_to(nearest)
					direction = (road[index + 1] - road[index]).normalized()
					anchor = nearest
		var normal := Vector3(-direction.z, 0, direction.x)
		var pair := [anchor + normal * 1.4, anchor - normal * 1.4]
		if pair.any(func(point): return buildings.values().any(func(building): return point.distance_to(building) < 3.6)): continue
		if pair.any(func(point): return commons.values().any(func(common): return point.distance_to(common.position) < 3.6)): continue
		return pair
	push_error("No reachable stone walk stop towards " + destination)
	return caches.bistro.duplicate()

func road_distance(point: Vector3) -> float:
	var distance := INF
	for road in roads:
		for index in road.size() - 1:
			distance = minf(distance, point.distance_to(Geometry3D.get_closest_point_to_segment(point, road[index], road[index + 1])))
	return distance

func _entrance(desired: Vector2) -> Vector3:
	var candidates: Array[Vector2i] = []
	for z in nav.grid.y:
		for x in nav.grid.x:
			var cell := Vector2i(x, z)
			if nav.is_walkable(cell): candidates.append(cell)
	candidates.sort_custom(func(a, b): return (Vector2(a) * SCALE).distance_squared_to(desired) < (Vector2(b) * SCALE).distance_squared_to(desired))
	for cell in candidates:
		var point := nav.cell_to_world(cell)
		if entrances.values().any(func(other): return point.distance_to(other) < 7): continue
		if entrances.has("farm") and grid.path(nav.world_to_cell(entrances.farm), cell).is_empty(): continue
		return point
	return nav.cell_to_world(candidates[0])

func _building(entrance: Vector3) -> Vector3:
	var best := entrance
	var clearance := -INF
	for index in 16:
		var point := entrance + Vector3(cos(index * TAU / 16), 0, sin(index * TAU / 16)) * 2.7
		var distance := road_distance(point)
		if distance > clearance:
			clearance = distance
			best = point
	return best

func _common(place: String, gathering := false) -> Dictionary:
	var desired: Vector3 = entrances.farm.lerp(entrances[place], 0.55)
	var candidates: Array[Vector3] = []
	for z in range(4, 60):
		for x in range(4, 60):
			var cell := Vector2i(x, z)
			if nav.is_walkable(cell): candidates.append(nav.cell_to_world(cell))
	candidates.sort_custom(func(a, b): return a.distance_squared_to(desired) < b.distance_squared_to(desired))
	for approach in candidates:
		if entrances.values().any(func(point): return point.distance_to(approach) < 2.4): continue
		if caches.values().any(func(pair): return pair[0].distance_to(approach) < 2.4 or pair[1].distance_to(approach) < 2.4): continue
		if grid.point_path(entrances.farm, approach).is_empty(): continue
		for index in 8:
			var facing := Vector3(cos(index * TAU / 8), 0, sin(index * TAU / 8))
			var point := approach + facing * 2.7
			if point.x < 2 or point.x > 36 or point.z < -36 or point.z > -2: continue
			if road_distance(point) < 2.1 or point.distance_to(Geometry3D.get_closest_point_to_segment(point, shortcut[0], shortcut[1])) < 2.1: continue
			if buildings.values().any(func(p): return p.distance_to(point) < 4.5): continue
			if caches.values().any(func(pair): return pair[0].distance_to(point) < 3 or pair[1].distance_to(point) < 3): continue
			if commons.values().any(func(common): return common.position.distance_to(point) < 6): continue
			if gathering:
				if buildings.values().any(func(p): return p.distance_to(point) < 5.4): continue
				if all_caches().any(func(pair): return pair[0].distance_to(point) < 3.6 or pair[1].distance_to(point) < 3.6): continue
				if gatherings.values().any(func(venue): return venue.position.distance_to(point) < 6.5): continue
			return {"position": point, "approach": approach, "facing": facing}
	push_error("No reachable street work area for " + place)
	return {"position": entrances[place], "approach": entrances[place], "facing": Vector3.FORWARD}

func offset_for(id: String) -> Vector3:
	return (entrances[id] - entrances.farm) * map_scale

func map_road(road: PackedVector3Array) -> PackedVector3Array:
	var points := PackedVector3Array()
	for point in road: points.append((point - entrances.farm) * map_scale)
	return points

static func load_for(session: FarmSession) -> FarmBlueprint:
	var id := session.layout_patch_id if not session.layout_patch_id.is_empty() else str(FarmChoice.load().get("layout_patch_id", "safe_grid"))
	var revision := session.blueprint_revision if session.blueprint_revision > 0 else 2
	var path := FarmBlueprint.asset_path(id, revision)
	if not FileAccess.file_exists(path): path = FarmBlueprint.asset_path("safe_grid", 2)
	return FarmBlueprint.load_file(path)

static func street_node(state: Dictionary, place: String) -> Dictionary:
	for node in JourneyProgress.remaining_nodes(state, place):
		if str(node.id) == place + "_east": return node
	return {}
