extends SceneTree

var stage: Node3D
var checks: Array = []
var data: Dictionary
var output: String

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks.append({"check": label, "passed": ok})
	if not ok: push_error(label)

func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func add_shape(name_: String, at: Vector3, volume: Shape3D, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.name = name_
	body.position = at
	body.rotation_degrees.y = yaw
	var collider := CollisionShape3D.new()
	collider.shape = volume
	body.add_child(collider)
	stage.add_child(body)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1)
	output = args[0].get_base_dir()
	data = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	stage = Node3D.new()
	root.add_child(stage)
	for row in data.plan.placements:
		if row.has("contained_by"): continue
		var volume: Shape3D
		var height: float
		if row.shape == "circle":
			var circle := CylinderShape3D.new()
			circle.radius = float(row.radius)
			circle.height = float(row.height)
			height = circle.height
			volume = circle
		else:
			var box := BoxShape3D.new()
			box.size = vec(row.size)
			height = box.size.y
			volume = box
		var yaw: float = row.get("yaw_degrees", 0)
		var offset := vec(row.get("shape_offset", [0, 0, 0])).rotated(Vector3.UP, deg_to_rad(yaw))
		add_shape(row.name, vec(row.position) + offset + Vector3.UP * height * .5, volume, yaw)
	for i in 3: await physics_frame
	var space := stage.get_world_3d().direct_space_state
	var grid_data: Dictionary = data.grid
	var paths := []
	for mode in grid_data.modes:
		var radius := float(mode.radius)
		var grid := AStarGrid2D.new()
		grid.region = Rect2i(0, 0, int(grid_data.width), int(grid_data.depth))
		grid.cell_size = Vector2.ONE * float(grid_data.step)
		grid.offset = Vector2(grid_data.origin[0], grid_data.origin[1])
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.update()
		for index in mode.blocked:
			grid.set_point_solid(Vector2i(int(index) % int(grid_data.width), int(index) / int(grid_data.width)))
		var shape := CapsuleShape3D.new()
		shape.radius = radius
		shape.height = 1.745
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.margin = 0.0001
		var targets := []
		if radius < .3:
			for seat in data.analysis.seats: targets.append([seat.name, vec(seat.stand)])
			for i in data.analysis.standing_16.size(): targets.append(["standing_%02d" % (i + 1), vec(data.analysis.standing_16[i])])
			targets.append(["exit", vec(data.plan.exit)])
		else:
			targets.append(["main_passage_to_back", vec(data.analysis.main_target)])
		var spawn := vec(data.plan.spawn)
		var start := Vector2i(((Vector2(spawn.x, spawn.z) - grid.offset) / grid.cell_size).round())
		for target in targets:
			var endpoint := Vector2i(((Vector2(target[1].x, target[1].z) - grid.offset) / grid.cell_size).round())
			var route := grid.get_point_path(start, endpoint)
			check(not route.is_empty(), target[0] + " connected on native AStarGrid2D")
			if not route.is_empty():
				route.insert(0, Vector2(spawn.x, spawn.z))
				route.append(Vector2(target[1].x, target[1].z))
			var clear := not route.is_empty()
			for i in range(1, route.size()):
				query.transform.origin = Vector3(route[i - 1].x, .08 + 1.745 / 2, route[i - 1].y)
				query.motion = Vector3(route[i].x - route[i - 1].x, 0, route[i].y - route[i - 1].y)
				if space.cast_motion(query)[0] < .999: clear = false; break
			check(clear, target[0] + " native capsule sweep radius=%.2f" % radius)
			paths.append({"name": target[0], "radius": radius, "clear": clear, "path_xz": Array(route).map(func(q): return [q.x, q.y])})
	var passed := checks.all(func(c): return c.passed)
	FileAccess.open(output + "/godot-navigation.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "paths": paths, "passed": passed}, "\t") + "\n")
	print("N1_EARLY_NAVIGATION ", passed, " checks=", checks.size())
	quit(0 if passed else 1)
