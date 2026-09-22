extends RefCounted

const Art = preload("res://modules/farm/farm_art.gd")
const Layout = preload("res://modules/mining/mine_layout.gd")
const FLOOR_COLORS := [Color("a8b8ad"), Color("a8b7ba"), Color("b7bbaa"), Color("afbac5"), Color("9cb9ae")]
const STONE := Color("71857e")
const TIMBER := Color("ae9173")
const METAL := Color("456d70")

static func _surface() -> SurfaceTool:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	return surface

static func _mesh(surface: SurfaceTool, node_name: String) -> MeshInstance3D:
	surface.index()
	var result := MeshInstance3D.new()
	result.name = node_name
	result.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	result.material_override = material
	return result

static func entrance() -> Node3D:
	var result := Node3D.new()
	result.name = "MineEntrance"
	var surface := _surface()
	for side in [-1.0, 1.0]:
		PlaceScenery._oval(surface, Vector3(0.8, 1.4, 0.65), Vector3(side * 0.6, 0.6, 0), STONE)
		PlaceScenery._box(surface, Vector3(0.16, 1.25, 0.18), Vector3(side * 0.43, 0.63, 0.39), TIMBER)
	PlaceScenery._oval(surface, Vector3(1.9, 0.65, 0.9), Vector3(0, 1.35, -0.1), STONE.lightened(0.08))
	PlaceScenery._box(surface, Vector3(0.9, 1.2, 0.05), Vector3(0, 0.61, 0.05), Color("243e39"))
	PlaceScenery._box(surface, Vector3(1.12, 0.2, 0.2), Vector3(0, 1.3, 0.4), TIMBER)
	for x in [-0.22, 0.22]:
		PlaceScenery._box(surface, Vector3(0.035, 0.04, 1.3), Vector3(x, 0.03, 0.76), METAL)
	for i in 5:
		PlaceScenery._box(surface, Vector3(0.63, 0.025, 0.1), Vector3(0, 0.018, 0.3 + i * 0.25), TIMBER)
	result.add_child(_mesh(surface, "MineArch"))
	return result

static func floor_scenery(floor_number: int, elevator_unlocked: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "MineScenery"
	var surface := _surface()
	var color: Color = FLOOR_COLORS[clampi(floor_number - 1, 0, 4)]
	PlaceScenery._box(surface, Vector3(10, 0.26, 8.6), Vector3(4.75, -0.16, -4.0), color)
	PlaceScenery._box(surface, Vector3(9.8, 0.16, 0.35), Vector3(4.75, -0.03, 0.25), STONE)
	for side in [-0.2, 9.7]:
		for i in 8:
			PlaceScenery._oval(surface, Vector3(0.9, 0.6 + (i % 3) * 0.2, 1.05), Vector3(side, 0.2, -0.45 - i), STONE)
	for i in 10:
		PlaceScenery._oval(surface, Vector3(1.1, 1.1, 0.85), Vector3(float(i), 0.37, -8.0), STONE.lightened(0.08))
	for x in [3.5, 6.5]:
		PlaceScenery._box(surface, Vector3(0.2, 1.75, 0.2), Vector3(x, 0.8, -7.45), TIMBER)
	PlaceScenery._box(surface, Vector3(3.3, 0.23, 0.24), Vector3(5.0, 1.72, -7.45), TIMBER)
	for i in 5:
		var p := Vector3(3.9 + sin(i * 1.7) * 2, 0.012, -0.8 - i * 1.25)
		PlaceScenery._oval(surface, Vector3(0.5, 0.03, 0.35), p, color.lightened(0.08))
	root.add_child(_mesh(surface, "Cavern"))
	for point in [Vector3(3.5, 1.45, -7.1), Vector3(6.5, 1.45, -7.1)]:
		var lamp := OmniLight3D.new()
		lamp.position = point
		lamp.light_color = Color("f4df9a")
		lamp.light_energy = 0.7
		lamp.omni_range = 4.0
		root.add_child(lamp)
	if floor_number in [1, 5]:
		root.add_child(elevator(elevator_unlocked))
	root.add_child(ladder(Layout.UP, true))
	return root

static func elevator(unlocked: bool) -> MeshInstance3D:
	var surface := _surface()
	var p := Layout.ELEVATOR
	PlaceScenery._box(surface, Vector3(1.45, 0.16, 1.25), p + Vector3(0, 0.04, 0), METAL)
	for x in [-0.64, 0.64]:
		PlaceScenery._box(surface, Vector3(0.12, 1.7, 0.12), p + Vector3(x, 0.85, -0.45), METAL)
	PlaceScenery._box(surface, Vector3(1.45, 0.13, 0.17), p + Vector3(0, 1.68, -0.45), METAL)
	for i in 6:
		PlaceScenery._box(surface, Vector3(0.045, 1.35, 0.045), p + Vector3(-0.53 + i * 0.21, 0.76, -0.45), METAL.lightened(0.2))
	PlaceScenery._box(surface, Vector3(0.22, 0.32, 0.16), p + Vector3(0.8, 0.65, 0.3), TIMBER)
	PlaceScenery._oval(surface, Vector3(0.10, 0.10, 0.05), p + Vector3(0.8, 0.68, 0.4), Color("9adebb") if unlocked else Color("ca7770"))
	return _mesh(surface, "MineElevator")

static func ladder(position: Vector3, upward: bool) -> MeshInstance3D:
	var surface := _surface()
	PlaceScenery._box(surface, Vector3(1.0, 0.06, 0.9), position + Vector3(0, 0.02, 0), Color("344f49"))
	var height := 0.9 if upward else 0.16
	for x in [-0.32, 0.32]:
		PlaceScenery._beam(surface, position + Vector3(x, 0.07, 0.3), position + Vector3(x, height, -0.3), 0.07, TIMBER)
	for i in 5:
		var t := float(i) / 4
		PlaceScenery._box(surface, Vector3(0.68, 0.07, 0.07), position + Vector3(0, lerpf(0.07, height, t), lerpf(0.3, -0.3, t)), TIMBER.lightened(0.15))
	return _mesh(surface, "UpLadder" if upward else "DownLadder")

static func rock(position: Vector3, index: int, floor_number: int) -> Node3D:
	var result := Node3D.new()
	result.position = position
	var stone := Art.instance("rock", Vector3.ZERO, 2.4)
	stone.rotation.y = index * 1.7 + floor_number
	result.add_child(stone)
	var surface := _surface()
	var tint := Color("ce9474") if index % 2 == 0 else Color("e0efe5")
	for i in 3:
		PlaceScenery._oval(surface, Vector3(0.13, 0.1, 0.1), Vector3(-0.21 + i * 0.16, 0.26 + float(i % 2) * 0.07, 0.13), tint)
	result.add_child(_mesh(surface, "MineralVeins"))
	return result
