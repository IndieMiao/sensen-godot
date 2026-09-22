class_name FishingModel
extends RefCounted

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/fishing.json"))
	return _data

static func site(id: String, pond: Dictionary = {}) -> Dictionary:
	return pond if id == "farm_pond" and not pond.is_empty() else data().sites.get(id, {})

## Geometry belongs to the farm being visited, never a process-wide mutable setting.
## Legacy farms retain the original fishing coordinates. Generated compact farms
## derive the pond from the same cell geometry that supplies ground and navigation.
static func site_for_plot(id: String, bp: FarmBlueprint) -> Dictionary:
	var original := site(id)
	if id != "farm_pond" or bp == null or not bp.layout_patch_id.begins_with("geo_"):
		return original
	if bp.grid != Vector2i(40, 40) or bp.cell_mm != 800: return original
	for region in FarmPlot.source_for(bp.layout_patch_id).get("regions", []):
		if region.get("kind") != "water" or not region.has("ellipse"): continue
		var ellipse: Array = region.ellipse
		var result := original.duplicate(true)
		result.center = [float(ellipse[0]) * bp.cell_m, -float(ellipse[1]) * bp.cell_m]
		result.radii = [float(ellipse[2]) * bp.cell_m, float(ellipse[3]) * bp.cell_m]
		result.stand = [result.center[0] + (float(original.stand[0]) - float(original.center[0])) / 0.75 * bp.cell_m,
			result.center[1] + (float(original.stand[1]) - float(original.center[1])) / 0.75 * bp.cell_m]
		return result
	return original

static func stand(id: String, pond: Dictionary = {}) -> Vector3:
	var point: Array = site(id, pond).stand
	return Vector3(float(point[0]), 0, float(point[1]))

static func fish(id: String) -> Dictionary:
	return data().fish.get(id, {})

static func tier_name(id: String) -> String:
	return L10n.text(str(data().tiers[str(int(fish(id).tier))].name)) if not fish(id).is_empty() else ""

static func contains(id: String, point: Vector3, padding := 0.0, pond: Dictionary = {}) -> bool:
	var spec := site(id, pond)
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
	model.progress = clampf(float(model.progress) + (float(tier.gain) if inside else -float(tier.loss)) * dt, 0, 1)
	model.step = int(model.step) + 1
	if float(model.progress) >= 1: model.outcome = "caught"
	elif float(model.progress) <= 0 or int(model.step) >= int(config.max_steps): model.outcome = "escaped"

## Closest water point; ellipse bisection matches the authoritative geometry.
static func nearest_water(id: String, point: Vector3, pond: Dictionary = {}) -> Vector3:
	if contains(id, point, 0.0, pond): return Vector3(point.x, 0, point.z)
	var spec := site(id, pond)
	var p := Vector2(point.x, point.z)
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

static func default_target(id: String, origin: Vector3, pond: Dictionary = {}) -> Vector3:
	var edge := nearest_water(id, origin, pond)
	return edge + (edge - origin).normalized() * minf(0.55, float(site(id, pond).get("width", 1.1)) * 0.5)

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

## Existing shore position is continuous; only automatic walking uses navigation cells.
static func plan(id: String, from: Vector3, clicked: Vector3, grid: BlueprintGrid, pond: Dictionary = {}) -> Dictionary:
	if pond.is_empty(): pond = site_for_plot(id, grid.bp)
	var target := clicked if clicked.is_finite() else default_target(id, from, pond)
	if valid_cast(id, from, target, grid, pond): return {"origin": from, "target": target}
	var candidates: Array[Dictionary] = []
	for y in grid.bp.grid.y:
		for x in grid.bp.grid.x:
			var cell := Vector2i(x, y)
			if grid.astar.is_point_solid(cell): continue
			var origin := grid.bp.cell_to_world(cell)
			if contains(id, origin, 0.0, pond) or origin.distance_to(nearest_water(id, origin, pond)) > float(data().shore_range): continue
			target = clicked if clicked.is_finite() else default_target(id, origin, pond)
			if not valid_cast(id, origin, target, grid, pond): target = default_target(id, origin, pond)
			if not valid_cast(id, origin, target, grid, pond): continue
			var score := origin.distance_to(from) if not clicked.is_finite() else target.distance_to(clicked) * 4.0 + origin.distance_to(clicked) + origin.distance_to(from) * 0.15
			candidates.append({"origin": origin, "target": target, "score": score})
	candidates.sort_custom(func(a, b): return a.score < b.score)
	for candidate in candidates:
		if not grid.point_path(from, candidate.origin).is_empty(): return candidate
	return {}
