extends RefCounted

const DATA_PATH := "res://assets/farm/data/mining.json"
const SIZE := Vector2i(20, 18)
const SPAWN := Vector3(4.75, 0, -0.75)
const UP := Vector3(1.0, 0, -0.75)
const DOWN := Vector3(8.25, 0, -6.75)
const ELEVATOR := Vector3(1.25, 0, -6.75)
const LAYOUT_VERSION := 1
const MIN_ROCK_SPACING := 1.8
const ANCHOR_CLEARANCE := 1.6
const ROCK_BOUNDS := Rect2(1.4, -6.05, 7.0, 4.5)
const LAYOUT_ATTEMPTS := 16
const POSITION_ATTEMPTS := 80
const CACHE_LIMIT := 32
const LEGACY_POSITIONS := [Vector3(2.0, 0, -2.15), Vector3(4.5, 0, -2.4),
	Vector3(7.0, 0, -2.0), Vector3(2.5, 0, -4.55), Vector3(4.8, 0, -5.6), Vector3(7.35, 0, -4.5)]
## q(292), #775 6659631244: N1–2, S1–2, W1–2; remove the cropped right column, leaving that side for monsters.
## Counts and rock indices still come from the server; no candidate names or combinations cross the wire.
const FALLBACK_POSITIONS := [Vector3(2.9, 0, -1.9), Vector3(6.8, 0, -1.9), Vector3(3.5, 0, -6.6), Vector3(6.0, 0, -6.6),
	Vector3(1.9, 0, -2.6), Vector3(1.9, 0, -4.6)]
const ROCK_SIDES := [0, 0, 2, 2, 3, 3]
const ROCK_SCALE := 1.3
const ROCK_RADIUS := 0.85

static var _layouts: Dictionary = {}

## q(292): shuffle by mine:floor:day, then take the first valid combination in that order. Looking ahead avoids a
## greedy first pair stranding the third rock. Never reorder after breaking one: view rock i stays position i.
## A server before #772 (including rollback) gives 4–6 rocks: keep its old indexed layout and size.
static func p0_rocks(count: int, key: String) -> Array:
	if count <= 0: return []
	if count > 3:
		return _shuffled(LEGACY_POSITIONS.size(), key).slice(0, mini(count, LEGACY_POSITIONS.size())).map(func(i): return LEGACY_POSITIONS[i])
	var order := _shuffled(FALLBACK_POSITIONS.size(), key)
	if count == 1: return [FALLBACK_POSITIONS[order[0]]]
	var spacing := 4.5 if count == 2 else 3.5
	for a in order.size():
		for b in range(a + 1, order.size()):
			if not _separate(order[a], order[b], spacing): continue
			if count == 2: return [FALLBACK_POSITIONS[order[a]], FALLBACK_POSITIONS[order[b]]]
			for c in range(b + 1, order.size()):
				if _separate(order[a], order[c], spacing) and _separate(order[b], order[c], spacing):
					return [FALLBACK_POSITIONS[order[a]], FALLBACK_POSITIONS[order[b]], FALLBACK_POSITIONS[order[c]]]
	push_error("Mine rock candidates have no valid separated combination")
	return []

static func _separate(a: int, b: int, spacing: float) -> bool:
	return ROCK_SIDES[a] != ROCK_SIDES[b] and FALLBACK_POSITIONS[a].distance_to(FALLBACK_POSITIONS[b]) >= spacing

static func _shuffled(count: int, key: String) -> Array:
	var order := range(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = key.sha256_text().substr(0, 15).hex_to_int()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	return order

static func data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))

static func rocks(floor_number: int, run: int = 0, farm_id: String = "") -> Array:
	if data().rockless_floors.any(func(number): return int(number) == floor_number): return []
	var key := "%d:%d:%d:%s" % [LAYOUT_VERSION, floor_number, run, farm_id]
	if not _layouts.has(key):
		var rng := RandomNumberGenerator.new()
		# Integer inputs and a digest keep saves stable after JSON numeric conversion.
		rng.seed = key.sha256_text().substr(0, 15).hex_to_int()
		var nodes := _generate_rocks(rng, data().rocks)
		if _layouts.size() >= CACHE_LIMIT: _layouts.erase(_layouts.keys()[0])
		_layouts[key] = nodes
	return _layouts[key].duplicate(true)

static func rock_count(floor_number: int) -> int:
	var config := data()
	return 0 if config.rockless_floors.any(func(number): return int(number) == floor_number) else config.rocks.size()

static func _generate_rocks(rng: RandomNumberGenerator, sources: Array) -> Array:
	for attempt in LAYOUT_ATTEMPTS:
		var result: Array = []
		for index in sources.size():
			for candidate in POSITION_ATTEMPTS:
				var point := Vector3(rng.randf_range(ROCK_BOUNDS.position.x, ROCK_BOUNDS.end.x), 0,
					rng.randf_range(ROCK_BOUNDS.position.y, ROCK_BOUNDS.end.y))
				if not _position_is_clear(point, result): continue
				result.append({"id": str(sources[index].id), "position": point})
				break
			if result.size() < index + 1: break
		if result.size() == sources.size() and _layout_is_reachable(result): return result
	var fallback: Array = []
	for index in sources.size():
		fallback.append({"id": str(sources[index].id), "position": LEGACY_POSITIONS[index]})
	return fallback

static func _position_is_clear(point: Vector3, nodes: Array) -> bool:
	for anchor in [SPAWN, UP, DOWN, ELEVATOR]:
		if point.distance_to(anchor) < ANCHOR_CLEARANCE: return false
	for rock in nodes:
		if point.distance_to(rock.position) < MIN_ROCK_SPACING: return false
	return true

static func _layout_is_reachable(nodes: Array) -> bool:
	var bp := _navigation(nodes, [])
	var grid := BlueprintGrid.new(bp)
	var spawn := bp.world_to_cell(SPAWN)
	if not bp.is_walkable(spawn): return false
	# Reject isolated walkable pockets as well as blocked interaction approaches.
	for y in SIZE.y:
		for x in SIZE.x:
			var cell := Vector2i(x, y)
			if bp.is_walkable(cell) and grid.path(spawn, cell).is_empty(): return false
	var targets: Array = [UP, DOWN, ELEVATOR]
	for rock in nodes: targets.append(rock.position)
	for target in targets:
		var nearby := bp.world_to_cell(target)
		var has_approach := false
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				var cell := nearby + Vector2i(dx, dz)
				var distance := bp.cell_to_world(cell).distance_to(target)
				if bp.is_walkable(cell) and distance >= 0.75 and distance <= 1.55:
					has_approach = true
		if not has_approach: return false
	return true

static func navigation(floor_number: int, broken: Array, run: int = 0, farm_id: String = "") -> FarmBlueprint:
	return _navigation(rocks(floor_number, run, farm_id), broken)

static func _navigation(nodes: Array, broken: Array, rock_radius := 0.65) -> FarmBlueprint:
	var bp := FarmBlueprint.new()
	bp.grid = SIZE
	bp.cell_m = 0.5
	bp.anchors = {"spawn": bp.world_to_cell(SPAWN)}
	bp.masks = {"walkable": []}
	for y in SIZE.y:
		var row := ""
		for x in SIZE.x:
			var point := bp.cell_to_world(Vector2i(x, y))
			var blocked := x < 1 or x > 18 or y < 1 or y > 15
			for rock in nodes:
				if not broken.has(rock.id) and point.distance_to(rock.position) < rock_radius: blocked = true
			if point.distance_to(ELEVATOR) < 0.85: blocked = true
			row += "0" if blocked else "1"
		bp.masks.walkable.append(row)
	return bp

static func approach(mover: PlayerMover, target: Vector3) -> Vector3:
	var best := mover.position
	var best_score := INF
	var cell := mover.bp.world_to_cell(target)
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var candidate := cell + Vector2i(dx, dz)
			if not mover.bp.is_walkable(candidate): continue
			var point := mover.bp.cell_to_world(candidate)
			var distance := point.distance_to(target)
			if distance < 0.75 or distance > 1.55: continue
			var path := mover.grid.point_path(mover.position, point)
			if path.is_empty(): continue
			var score := distance * 5 + mover.position.distance_to(point)
			if score < best_score:
				best_score = score
				best = point
	return best
