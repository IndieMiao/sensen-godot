extends Node3D
## Homestead garden dressing for P0, composed only from the existing farm kit (assets/farm/art/*.glb,
## the same assets and placement logic as the earlier fixed-plot garden, git c3b4204 FarmScenery):
## field path under the beds, stepping stones, a tree line behind the house, fence, sign, shrubs,
## scattered grass and flowers, daisies at the door and the chimney smoke.

const Art = preload("res://modules/farm/farm_art.gd")
const FarmScenery = preload("res://modules/farm/farm_scenery.gd")

var field_rect := Rect2()   # world xz rect covering every bed, for scatter exclusion
var rock_points: Array = []  # scattered rocks; the farm makes their cells solid
var _sand: Node3D            # the sand under the field
## The dressing on the Kitchen Wing's cells and the bush beside them (6, 17) (q(303), 后裔): drawn on its own, out of
## sight while the wing's model stands there (show_wing) — the same points as ever, the random scatter's draws unchanged.
var _wing_dress: Node3D

static func wing_dress_cells() -> Array: return P0Decor.wing_cells() + [Vector2i(6, 17)]

## The wing's model on its cells (P0Looks.wing_model_shown): its grass, flowers and bush not drawn; gone, back again.
func show_wing(on: bool) -> void:
	if _wing_dress and _wing_dress.visible == on: _wing_dress.visible = not on

## [kept, on the wing's cells] of a layer's transforms.
static func _split(bp: FarmBlueprint, xfs: Array) -> Array:
	var cells := wing_dress_cells()
	var kept: Array = []
	var wing: Array = []
	for xf in xfs: (wing if cells.has(bp.world_to_cell((xf as Transform3D).origin)) else kept).append(xf)
	return [kept, wing]

func _add_split(bp: FarmBlueprint, asset: String, xfs: Array, shadows := true) -> void:
	var parts := _split(bp, xfs)
	add_child(Art.batch(asset, parts[0], shadows))
	if not (parts[1] as Array).is_empty(): _wing_dress.add_child(Art.batch(asset, parts[1], shadows))

## The sand under the beds open now (SGODOT-355 b1: the first `count` of the grid's order), one patch over them and the
## walkways between (不知火舞 282 bf7c124b); the beds still to open stay grass.
func fit_sand(bp: FarmBlueprint, count: int) -> void:
	var r := beds_rect(bp, count)
	var size := r.size + Vector2(0.7, 0.7)
	_sand.position = Vector3(r.get_center().x, 0.003, r.get_center().y)
	_sand.scale = Vector3(size.x / 1.26, 1, size.y / 1.26)

func build(bp: FarmBlueprint, style: String) -> void:
	name = "GardenScenery"
	_wing_dress = Node3D.new()
	_wing_dress.name = "WingDressing"
	add_child(_wing_dress)
	field_rect = beds_rect(bp, P0Garden.max_plots())   # the whole grid: kept clear of scatter, stones lead to it
	# Sandy garden path under the beds, a little wider than the field (the old 9-plot garden used 3.1×).
	_sand = Art.instance("path_tile", Vector3.ZERO)
	_sand.name = "FieldSand"
	_sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sand)
	fit_sand(bp, P0Garden.max_plots())
	var house := bp.cell_to_world(bp.anchor("house"))
	var spawn := bp.cell_to_world(bp.anchor("spawn"))
	# Stepping stones: field → front door, and the entrance → field.
	var stones: Array = []
	for i in 5:
		stones.append(_xf(Vector3(house.x - 0.05 + sin(i * 2.3) * 0.07, 0.011, field_rect.position.y - 0.25 - i * 0.26), 0.11 * sin(i), 1.0))
	for i in 3:
		stones.append(_xf(Vector3(spawn.x + sin(i * 1.7) * 0.06, 0.011, spawn.z - 0.15 - i * 0.27), 0.2 * i, 0.95))
	add_child(Art.batch("stepping_stone", stones, false))
	# The trees round the yard: p0_farm_woods.gd (the pine woods, SGODOT-422 0.3.5), no tree line here.
	# The fence depends on the Homestead level: p0_fence.gd (SGODOT-228).
	# the entrance sign left of the way in, by the spawn: (7, −1) since the yard's front moved (q(172) A); Decorate's objects hold it
	add_child(Art.instance("sign", Vector3(spawn.x - 1.35, 0, spawn.z + 0.25), 0.93))
	var shrubs: Array = []
	for p in [Vector3(house.x - 1.75, 0, house.z - 0.9), Vector3(house.x + 1.85, 0, house.z - 1.0), Vector3(12.2, 0, -6.3),
		Vector3(12.7, 0, -1.4)]:
		shrubs.append(_xf(p, p.x, 0.72))
	_add_split(bp, "bush", shrubs)
	# The yard's west edge and the west end of its front (SGODOT-371, 不知火舞 59ea8ecc): a loose hedge just outside the
	# walk line (x 0.65 / z +1.3) and the Lv3+ ring (x 0.38), every level the same — it shows the edge, the walk rect stops you.
	for layer in [["bush", true, [
		[Vector3(3.5, 0, 1.97), 2.57, 0.7],
		[Vector3(2.62, 0, 1.88), 6.03, 0.94],
		[Vector3(1.58, 0, 1.92), 0.26, 0.96],
		[Vector3(0.73, 0, 1.89), 4.27, 0.81],
		[Vector3(0.08, 0, 1.92), 6.1, 0.84],
		[Vector3(0.02, 0, 1.06), 0.11, 0.87],
		[Vector3(0.08, 0, 0.14), 1.88, 0.83],
		[Vector3(0.02, 0, -0.62), 1.06, 0.93],
		[Vector3(0.1, 0, -0.98), 0.42, 0.71],
		[Vector3(0.05, 0, -1.99), 6.27, 0.98],
		[Vector3(0.01, 0, -3.08), 2.35, 0.9],
		[Vector3(0.01, 0, -4.06), 2.15, 0.89],
		[Vector3(0.01, 0, -4.9), 1.84, 0.86],
		[Vector3(0.08, 0, -5.83), 2.29, 0.82],
		[Vector3(0.01, 0, -6.87), 3.49, 0.81],
		[Vector3(0.03, 0, -7.93), 3.78, 0.84],
		[Vector3(0.09, 0, -8.29), 2.58, 0.71],
		[Vector3(-0.0, 0, -9.3), 2.04, 0.84],
		[Vector3(0.09, 0, -10.36), 0.41, 0.89],
		[Vector3(0.04, 0, -11.21), 5.48, 0.75],
		[Vector3(0.1, 0, -12.22), 6.22, 0.79]]],
		["daisy", false, [
		[Vector3(2.5, 0.01, 1.69), 0.0, 0.82],
		[Vector3(0.3, 0.01, -0.08), 2.6, 0.82],
		[Vector3(0.31, 0.01, -3.88), 5.2, 0.82],
		[Vector3(0.33, 0.01, -8.18), 7.8, 0.82],
		[Vector3(0.29, 0.01, -11.88), 10.4, 0.82],
		[Vector3(3.66, 0.01, 1.72), 11.7, 0.82],
		[Vector3(3.52, 0.01, 2.14), 14.3, 0.82]]],
		["pink_flower", false, [
		[Vector3(0.4, 0.01, 1.63), 0.9, 0.78],
		[Vector3(0.31, 0.01, -1.98), 2.7, 0.78],
		[Vector3(0.3, 0.01, -6.08), 4.5, 0.78],
		[Vector3(0.34, 0.01, -10.08), 6.3, 0.78],
		[Vector3(3.8, 0.01, 1.98), 9.0, 0.78]]],
		["rock", true, [
		[Vector3(0.28, 0, 0.45), 1.71, 0.57],
		[Vector3(0.24, 0, -4.4), 5.04, 0.58],
		[Vector3(0.3, 0, -8.3), 5.75, 0.68],
		[Vector3(0.28, 0, -11.6), 4.37, 0.61],
		[Vector3(1.95, 0, 1.7), 1.1, 0.6]]]]:
		var xfs: Array = []
		for e in layer[2]: xfs.append(_xf(e[0], e[1], e[2]))
		add_child(Art.batch(layer[0], xfs, layer[1]))
	# Small foliage: dense at the woodland edge, sparse on the lawn, never on beds, paths or the yard spots.
	var rng := RandomNumberGenerator.new()
	rng.seed = 910
	var layers := {"grass_clump": [], "daisy": [], "pink_flower": [], "blue_flower": [], "rock": []}
	var keep_clear := [Rect2(field_rect.position - Vector2(0.45, 0.45), field_rect.size + Vector2(0.9, 0.9)),
		Rect2(Vector2(house.x - 0.6, field_rect.position.y - 1.8), Vector2(1.2, 1.9)),
		Rect2(Vector2(spawn.x - 0.7, spawn.z - 1.4), Vector2(1.4, 2.2))]
	var spots := [house, bp.cell_to_world(bp.anchor("storage")),
		bp.cell_to_world(bp.anchor("well")),
		bp.cell_to_world(bp.anchor("workbench"))]   # SGODOT-231: the workbench stays clear of scatter
	var no_decor := {"decor": {"placed": []}}
	for i in 420:
		# the front band reaches 2.4 m past the fence, which moved 1.3 m nearer (q(172) A; 上官婉儿 on 282 c2a5bc4f: z +2.5 → +3.8)
		var point := Vector3(rng.randf_range(-3.0, 16.0), 0.01, rng.randf_range(-16.0, -11.5) if i < 220 else rng.randf_range(-11.5, 3.8))
		var flat := Vector2(point.x, point.z)
		if keep_clear.any(func(r: Rect2): return r.has_point(flat)): continue
		if spots.any(func(s: Vector3): return Vector2(s.x, s.z).distance_to(flat) < (1.7 if s == house else 0.95)): continue
		var asset := "grass_clump"
		# a rock blocks its cell: none in the yard's front rows y −2…0 (the way in, x 9–10, runs through them; 上官婉儿 c2a5bc4f),
		# nor on a cell Decorate may take (the gathering spots kept two clear until they left the farm, SGODOT-355 b1)
		var front := bp.world_to_cell(point)
		var front_row := P0Garden.WALK_RECT.has_point(front) and front.y <= 0
		var decor_cell := P0Garden.WALK_RECT.has_point(front) and P0Decor.reason(no_decor, "deco_planter", front) == ""
		if i % 11 == 0 and not front_row and not decor_cell: asset = "rock"
		elif i % 5 == 0: asset = "daisy"
		elif i % 9 == 0: asset = "pink_flower"
		elif i % 13 == 0: asset = "blue_flower"
		var xf := _xf(point, rng.randf_range(0, TAU), rng.randf_range(0.55, 1.05))
		# the grass and flowers outside the fence ring are under the woods (p0_farm_woods.gd); the rocks stay: they block
		if asset != "rock" and not Rect2(0.38, -12.35, 12.57, 13.75).has_point(flat): continue
		layers[asset].append(xf)
	for xf in layers.rock: rock_points.append((xf as Transform3D).origin)
	for asset in layers: _add_split(bp, asset, layers[asset], asset == "rock")
	var flowers: Array = []
	for i in 12:
		flowers.append(_xf(house + Vector3(0.86 + sin(i * 2.4) * 0.22, 0.013, 0.48 + cos(i * 2.4) * 0.51), i, 0.64))
		flowers.append(_xf(house + Vector3(-0.95 + sin(i * 1.9) * 0.2, 0.013, 0.52 + cos(i * 1.9) * 0.45), i * 2, 0.6))
	_add_split(bp, "daisy", flowers, false)
	# Chimney smoke: the old scenery's own five GPU puffs.
	var smoke := FarmScenery.new()
	add_child(smoke)
	smoke._smoke(house, style)

static func _xf(p: Vector3, angle: float, scale: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale), p)

## The world rect (x, z) over the first `count` beds of the grid, each bed's half (0.47 m) round its middle.
static func beds_rect(bp: FarmBlueprint, count: int) -> Rect2:
	var half := 0.47
	var r := Rect2()
	for id in maxi(1, count):
		var at := bp.cell_to_world(P0Garden.cell_of(id))
		var bed := Rect2(Vector2(at.x, at.z) - Vector2.ONE * half, Vector2.ONE * half * 2)
		r = bed if id == 0 else r.merge(bed)
	return r
