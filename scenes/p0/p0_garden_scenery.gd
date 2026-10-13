extends Node3D
## Homestead garden dressing for P0, composed only from the existing farm kit (assets/farm/art/*.glb,
## the same assets and placement logic as the earlier fixed-plot garden, git c3b4204 FarmScenery):
## field path under the beds, stepping stones, a tree line behind the house, fence, sign, shrubs,
## scattered grass and flowers, daisies at the door and the chimney smoke.

const Art = preload("res://modules/farm/farm_art.gd")
const FarmScenery = preload("res://modules/farm/farm_scenery.gd")

var field_rect := Rect2()   # world xz rect covering every bed, for scatter exclusion
var rock_points: Array = []  # scattered rocks; the farm makes their cells solid

func build(bp: FarmBlueprint, style: String) -> void:
	name = "GardenScenery"
	var cell := bp.cell_m
	var first := bp.cell_to_world(P0Garden.cell_of(0))
	var last := bp.cell_to_world(P0Garden.cell_of(P0Garden.GRID_PLOTS - 1))   # the field's far corner (Lv7's 40–47 lie outside it)
	var half := 0.47
	field_rect = Rect2(Vector2(first.x - half, last.z - half), Vector2(last.x - first.x + half * 2, first.z - last.z + half * 2))
	# Sandy garden path under the beds, a little wider than the field (the old 9-plot garden used 3.1×).
	var path_size := field_rect.size + Vector2(0.7, 0.7)
	var path := Art.instance("path_tile", Vector3(field_rect.get_center().x, 0.003, field_rect.get_center().y))
	path.scale = Vector3(path_size.x / 1.26, 1, path_size.y / 1.26)
	path.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(path)
	var house := bp.cell_to_world(bp.anchor("house"))
	var spawn := bp.cell_to_world(bp.anchor("spawn"))
	# Stepping stones: field → front door, and the entrance → field.
	var stones: Array = []
	for i in 5:
		stones.append(_xf(Vector3(house.x - 0.05 + sin(i * 2.3) * 0.07, 0.011, field_rect.position.y - 0.25 - i * 0.26), 0.11 * sin(i), 1.0))
	for i in 3:
		stones.append(_xf(Vector3(spawn.x + sin(i * 1.7) * 0.06, 0.011, spawn.z - 0.15 - i * 0.27), 0.2 * i, 0.95))
	add_child(Art.batch("stepping_stone", stones, false))
	# Tree line behind the house and on the yard edges (outside the walkable yard).
	var tree_points := [Vector3(1.2, 0, -12.9), Vector3(3.5, 0, -13.6), Vector3(9.2, 0, -13.5), Vector3(11.6, 0, -12.8),
		Vector3(13.8, 0, -11.2), Vector3(-0.4, 0, -10.6), Vector3(-0.6, 0, -6.4), Vector3(13.9, 0, -6.9),
		Vector3(-0.5, 0, -2.6), Vector3(14.1, 0, -2.4), Vector3(6.6, 0, -14.6)]
	var trees: Array = []
	var tints := PackedColorArray()
	for i in tree_points.size():
		var p: Vector3 = tree_points[i]
		trees.append(_xf(p, i * 1.7, 0.92 + float(i % 3) * 0.08))
		tints.append(Color.WHITE.lerp(Color(0.58, 0.75, 0.80), smoothstep(10.0, 14.0, -p.z)))
	add_child(Art.batch("tree_0", trees, true, tints))
	# The fence depends on the Homestead level: p0_fence.gd (SGODOT-228).
	# the entrance sign left of the way in, by the spawn: (7, −1) since the yard's front moved (q(172) A); Decorate's objects hold it
	add_child(Art.instance("sign", Vector3(spawn.x - 1.35, 0, spawn.z + 0.25), 0.93))
	var shrubs: Array = []
	for p in [Vector3(house.x - 1.75, 0, house.z - 0.9), Vector3(house.x + 1.85, 0, house.z - 1.0), Vector3(12.2, 0, -6.3),
		Vector3(0.9, 0, -4.2), Vector3(12.7, 0, -1.4), Vector3(1.0, 0, -0.6)]:
		shrubs.append(_xf(p, p.x, 0.72))
	add_child(Art.batch("bush", shrubs))
	# Small foliage: dense at the woodland edge, sparse on the lawn, never on beds, paths or the yard spots.
	var rng := RandomNumberGenerator.new()
	rng.seed = 910
	var layers := {"grass_clump": [], "daisy": [], "pink_flower": [], "blue_flower": [], "rock": []}
	var keep_clear := [Rect2(field_rect.position - Vector2(0.45, 0.45), field_rect.size + Vector2(0.9, 0.9)),
		Rect2(Vector2(house.x - 0.6, field_rect.position.y - 1.8), Vector2(1.2, 1.9)),
		Rect2(Vector2(spawn.x - 0.7, spawn.z - 1.4), Vector2(1.4, 2.2))]
	for id in range(P0Garden.GRID_PLOTS, P0Garden.MAX_PLOTS):   # Homestead Lv7's beds on the field's edge (q(172)), each
		var bed := bp.cell_to_world(P0Garden.cell_of(id))
		keep_clear.append(Rect2(Vector2(bed.x, bed.z) - Vector2.ONE * (half + 0.45), Vector2.ONE * (half + 0.45) * 2))
	var spots := [house, bp.cell_to_world(bp.anchor("storage")),
		bp.cell_to_world(bp.anchor("well")), bp.cell_to_world(bp.anchor("mine"))]
	for key in P0Garden.ANCHORS:   # SGODOT-231: gathering spots and the workbench stay clear of scatter
		if str(key).begins_with("spot_") or key == "workbench": spots.append(bp.cell_to_world(bp.anchor(key)))
	for i in 420:
		# the front band reaches 2.4 m past the fence, which moved 1.3 m nearer (q(172) A; 上官婉儿 on 282 c2a5bc4f: z +2.5 → +3.8)
		var point := Vector3(rng.randf_range(-3.0, 16.0), 0.01, rng.randf_range(-16.0, -11.5) if i < 220 else rng.randf_range(-11.5, 3.8))
		var flat := Vector2(point.x, point.z)
		if keep_clear.any(func(r: Rect2): return r.has_point(flat)): continue
		if spots.any(func(s: Vector3): return Vector2(s.x, s.z).distance_to(flat) < (1.7 if s == house else 0.95)): continue
		var asset := "grass_clump"
		# a rock blocks its cell: none in the yard's front rows y −2…0 (the way in, x 9–10, runs through them; 上官婉儿 c2a5bc4f)
		var front := bp.world_to_cell(point)
		var front_row := P0Garden.WALK_RECT.has_point(front) and front.y <= 0
		if i % 11 == 0 and not front_row: asset = "rock"
		elif i % 5 == 0: asset = "daisy"
		elif i % 9 == 0: asset = "pink_flower"
		elif i % 13 == 0: asset = "blue_flower"
		layers[asset].append(_xf(point, rng.randf_range(0, TAU), rng.randf_range(0.55, 1.05)))
	for xf in layers.rock: rock_points.append((xf as Transform3D).origin)
	for asset in layers: add_child(Art.batch(asset, layers[asset], asset == "rock"))
	var flowers: Array = []
	for i in 12:
		flowers.append(_xf(house + Vector3(0.86 + sin(i * 2.4) * 0.22, 0.013, 0.48 + cos(i * 2.4) * 0.51), i, 0.64))
		flowers.append(_xf(house + Vector3(-0.95 + sin(i * 1.9) * 0.2, 0.013, 0.52 + cos(i * 1.9) * 0.45), i * 2, 0.6))
	add_child(Art.batch("daisy", flowers, false))
	# Chimney smoke: the old scenery's own five GPU puffs.
	var smoke := FarmScenery.new()
	add_child(smoke)
	smoke._smoke(house, style)

static func _xf(p: Vector3, angle: float, scale: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale), p)
