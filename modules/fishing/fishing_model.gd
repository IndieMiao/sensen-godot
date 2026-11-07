class_name FishingModel
extends RefCounted

static var _data: Dictionary = {}
## q(219): a sure bite's reel (tier.sure) keeps at least this much progress and has no step limit, so it can't escape.
const SURE_FLOOR := 0.05

static func data() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/fishing.json"))
	return _data

static func site(id: String, pond: Dictionary = {}) -> Dictionary:
	return pond if not pond.is_empty() and (id == "farm_pond" or pond.get("space") == "pond") else data().sites.get(id, {})

## The fishing site of the farm being visited. Every farm keeps the original coordinates (the generated compact
## farms that derived their pond from server terrain are retired, SGODOT-342).
static func site_for_plot(id: String, _bp: FarmBlueprint) -> Dictionary:
	return site(id)

static func stand(id: String, pond: Dictionary = {}) -> Vector3:
	var point: Array = site(id, pond).stand
	return Vector3(float(point[0]), 0, float(point[1]))

static func fish(id: String) -> Dictionary:
	return data().fish.get(id, {})

static func tier_name(id: String) -> String:
	return L10n.text(str(data().tiers[str(int(fish(id).tier))].name)) if not fish(id).is_empty() else ""

static func contains(id: String, point: Vector3, padding := 0.0, pond: Dictionary = {}) -> bool:
	var spec := site(id, pond)
	if spec.has("polygon"):
		var p := Vector2(point.x, point.z)
		var polygon := _polygon(spec)
		return Geometry2D.is_point_in_polygon(p, polygon) or p.distance_to(_nearest_polygon(p, polygon)) <= maxf(padding, 0.0000001)
	if spec.has("center"):
		var center := Vector2(float(spec.center[0]), float(spec.center[1]))
		var radius := Vector2(float(spec.radii[0]), float(spec.radii[1])) + Vector2.ONE * padding
		return ((Vector2(point.x, point.z) - center) / radius).length_squared() <= 1.0
	for index in spec.get("path", []).size() - 1:
		var a: Array = spec.path[index]
		var b: Array = spec.path[index + 1]
		var nearest := Geometry2D.get_closest_point_to_segment(Vector2(point.x, point.z), Vector2(a[0], a[1]), Vector2(b[0], b[1]))
		if nearest.distance_to(Vector2(point.x, point.z)) <= float(spec.width) * 0.5 + padding: return true
	return false

static func water_at(space: String, point: Vector3, padding := 0.0, pond: Dictionary = {}) -> bool:
	for id in data().sites:
		if site(id, pond).space == space and contains(id, point, padding, pond): return true
	return false

static func initial(seed_value: int) -> Dictionary:
	return {"step": 0, "bar": 0.5, "velocity": 0.0, "fish": 0.5, "target": 0.5, "rng": seed_value,
		"progress": float(data().initial_progress), "outcome": "playing"}

static func step(model: Dictionary, held: bool, tier: Dictionary) -> void:
	if model.outcome != "playing": return
	var config := data()
	var dt := float(config.step_ms) / 1000.0
	if int(model.step) % int(tier.turn_steps) == 0:
		model.rng = (int(model.rng) * 1664525 + 1013904223) & 0xffffffff
		model.target = 0.1 + float(model.rng) / 4294967296.0 * 0.8
	model.fish = move_toward(float(model.fish), float(model.target), float(tier.fish_speed) * dt)
	model.velocity = clampf(float(model.velocity) + (1.0 if held else -1.0) * float(config.bar_acceleration) * dt, -float(config.bar_max_speed), float(config.bar_max_speed))
	var half := float(tier.bar_size) * 0.5
	model.bar = clampf(float(model.bar) + float(model.velocity) * dt, half, 1.0 - half)
	if model.bar == half or model.bar == 1.0 - half: model.velocity = 0.0
	var inside := absf(float(model.fish) - float(model.bar)) <= half
	var sure := bool(tier.get("sure", false))
	model.progress = clampf(float(model.progress) + (float(tier.gain) if inside else -float(tier.loss)) * dt, SURE_FLOOR if sure else 0.0, 1)
	model.step = int(model.step) + 1
	if float(model.progress) >= 1: model.outcome = "caught"
	elif not sure and (float(model.progress) <= 0 or int(model.step) >= int(config.max_steps)): model.outcome = "escaped"

## Closest water point; ellipse bisection matches the authoritative geometry.
static func nearest_water(id: String, point: Vector3, pond: Dictionary = {}) -> Vector3:
	if contains(id, point, 0.0, pond): return Vector3(point.x, 0, point.z)
	var spec := site(id, pond)
	var p := Vector2(point.x, point.z)
	if spec.has("polygon"):
		var q := _nearest_polygon(p, _polygon(spec))
		return Vector3(q.x, 0, q.y)
	if spec.has("center"):
		var center := Vector2(spec.center[0], spec.center[1])
		var a := Vector2(spec.radii[0], spec.radii[1])
		var q := p - center
		var low := 0.0
		var high := maxf(a.x, a.y) * q.length()
		for i in 40:
			var t := (low + high) * 0.5
			var v := Vector2(a.x * q.x / (t + a.x * a.x), a.y * q.y / (t + a.y * a.y))
			if v.length_squared() > 1: low = t
			else: high = t
		return Vector3(center.x + a.x * a.x * q.x / (high + a.x * a.x), 0, center.y + a.y * a.y * q.y / (high + a.y * a.y))
	var nearest := Vector2(spec.path[0][0], spec.path[0][1])
	for i in spec.path.size() - 1:
		var candidate := Geometry2D.get_closest_point_to_segment(p, Vector2(spec.path[i][0], spec.path[i][1]), Vector2(spec.path[i + 1][0], spec.path[i + 1][1]))
		if candidate.distance_squared_to(p) < nearest.distance_squared_to(p): nearest = candidate
	nearest += (p - nearest).normalized() * float(spec.width) * 0.5
	return Vector3(nearest.x, 0, nearest.y)

static var _polygons := {}   # spec.polygon → its PackedVector2Array: contains() runs hundreds of times per plan (周瑜 on #593)
static var _polygons_lock := Mutex.new()   # WaterShore builds banks on worker threads
static func _polygon(spec: Dictionary) -> PackedVector2Array:
	_polygons_lock.lock()
	var hit = _polygons.get(spec.polygon)
	_polygons_lock.unlock()
	if hit != null: return hit
	var polygon := PackedVector2Array()
	for p in spec.polygon: polygon.append(Vector2(p[0], p[1]))
	_polygons_lock.lock()
	_polygons[spec.polygon] = polygon
	_polygons_lock.unlock()
	return polygon

static func _nearest_polygon(p: Vector2, polygon: PackedVector2Array) -> Vector2:
	var nearest := polygon[0]
	for i in polygon.size():
		var q := Geometry2D.get_closest_point_to_segment(p, polygon[i], polygon[(i + 1) % polygon.size()])
		if p.distance_squared_to(q) < p.distance_squared_to(nearest): nearest = q
	return nearest

## The Cast key's landing: past the nearest bank, POND_REACH into a pond (q(267) ③: open water in front of the rod),
## backing off in steps until the whole run from the bank, and FAR_CLEAR past the float, stays wet; 0.55 m (half a
## river's width) elsewhere.
const POND_REACH := 2.5
const SHORE_REACH := 0.55
const FAR_CLEAR := 0.25
static func default_target(id: String, origin: Vector3, pond: Dictionary = {}) -> Vector3:
	var edge := nearest_water(id, origin, pond)
	var dir := (edge - origin).normalized()
	var spec := site(id, pond)
	if spec.has("polygon"):
		var reach := POND_REACH
		while reach > SHORE_REACH:
			var wet := true
			for i in range(1, ceili((reach + FAR_CLEAR) / 0.1) + 1):
				if not contains(id, edge + dir * minf(i * 0.1, reach + FAR_CLEAR), 0.0, pond):
					wet = false
					break
			if wet: return edge + dir * reach
			reach -= 0.25
	return edge + dir * minf(SHORE_REACH, float(spec.get("width", 1.1)) * 0.5)

static func dry_walkable(grid: BlueprintGrid, point: Vector3) -> bool:
	var cell := grid.bp.world_to_cell(point)
	return grid.bp.in_bounds(cell) and not grid.astar.is_point_solid(cell)

static func valid_cast(id: String, origin: Vector3, target: Vector3, grid: BlueprintGrid, pond: Dictionary = {}) -> bool:
	if pond.is_empty(): pond = site_for_plot(id, grid.bp)
	if contains(id, origin, 0.0, pond) or not dry_walkable(grid, origin) or origin.distance_to(nearest_water(id, origin, pond)) > float(data().shore_range): return false
	if not contains(id, target, 0.0, pond) or origin.distance_to(target) > float(data().max_cast) or origin.distance_to(target) < 0.45: return false
	var wet := false
	var steps := ceili(origin.distance_to(target) / 0.1)
	for i in range(1, steps + 1):
		var p := origin.lerp(target, float(i) / steps)
		if contains(id, p, 0.0, pond): wet = true
		elif wet or (not dry_walkable(grid, p) and p.distance_to(nearest_water(id, p, pond)) > 0.55): return false
	return true

## The water's box (x, z): a polygon's points, an ellipse's centre ± radii; an empty Rect2 for a path site (no filter).
static func water_rect(id: String, pond: Dictionary = {}) -> Rect2:
	var spec := site(id, pond)
	if spec.has("polygon"):
		var r := Rect2()
		var first := true
		for p in _polygon(spec):
			if first: r = Rect2(p, Vector2.ZERO)
			else: r = r.expand(p)
			first = false
		return r
	if spec.has("center"):
		var c := Vector2(float(spec.center[0]), float(spec.center[1]))
		var a := Vector2(float(spec.radii[0]), float(spec.radii[1]))
		return Rect2(c - a, a * 2.0)
	return Rect2()

## Every cell of a blueprint's grid, from its first (grid_origin: a P0 pond's walk starts below zero, PondWalk; read from
## (0, 0) the AStar was asked out of its region on every Fish, 周瑜 on #855).
static func grid_cells(bp: FarmBlueprint) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in bp.grid.y:
		for x in bp.grid.x: out.append(bp.grid_origin + Vector2i(x, y))
	return out

## Existing shore position is continuous; only automatic walking uses navigation cells.
static func plan(id: String, from: Vector3, clicked: Vector3, grid: BlueprintGrid, pond: Dictionary = {}) -> Dictionary:
	if pond.is_empty(): pond = site_for_plot(id, grid.bp)
	var target := clicked if clicked.is_finite() else default_target(id, from, pond)
	if valid_cast(id, from, target, grid, pond): return {"origin": from, "target": target}
	# no shore spot lies further than shore_range from the water's box: cells past it are not measured (周瑜 on #855: the
	# walk to the meadow made a far-off Fish read 1.5× the cells)
	var near := water_rect(id, pond).grow(float(data().shore_range) + 0.01)
	var shore: Array[Vector3] = []
	for cell in grid_cells(grid.bp):
		if grid.astar.is_point_solid(cell): continue
		var origin := grid.bp.cell_to_world(cell)
		if near.has_area() and not near.has_point(Vector2(origin.x, origin.z)): continue
		if contains(id, origin, 0.0, pond) or origin.distance_to(nearest_water(id, origin, pond)) > float(data().shore_range): continue
		shore.append(origin)
	if not clicked.is_finite():
		# the Fish key: the nearest shore spot that casts and is walked to — nearest first, the rest never cast-checked
		# (the check is most of the cost: 575 shore cells, 235 of 280 ms on a desktop)
		shore.sort_custom(func(a, b): return a.distance_to(from) < b.distance_to(from))
		for origin in shore:
			var t := default_target(id, origin, pond)
			if valid_cast(id, origin, t, grid, pond) and not grid.point_path(from, origin).is_empty():
				return {"origin": origin, "target": t}
		return {}
	# A tap on the water: a spot scores 4 × its line's miss + its distance to the tap + 0.15 × the walk to it, so the last two
	# are a floor under its score. Spots are cast-checked lowest floor first, until the next floor is no better than the
	# best spot found that is walked to: none after it can beat that — the same spot as checking them all.
	var floor_of := func(o: Vector3) -> float: return o.distance_to(clicked) + o.distance_to(from) * 0.15
	shore.sort_custom(func(a, b): return floor_of.call(a) < floor_of.call(b))
	var best := {}
	for origin in shore:
		if not best.is_empty() and floor_of.call(origin) >= float(best.score): break
		target = clicked
		if not valid_cast(id, origin, target, grid, pond): target = default_target(id, origin, pond)
		if not valid_cast(id, origin, target, grid, pond): continue
		var score: float = target.distance_to(clicked) * 4.0 + float(floor_of.call(origin))
		if (best.is_empty() or score < float(best.score)) and not grid.point_path(from, origin).is_empty():
			best = {"origin": origin, "target": target, "score": score}
	return best
