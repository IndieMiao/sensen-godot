extends Node

const KIT := "res://assets/rooms/_shared/shell_hall/"
var vp: SubViewport
var art: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var elapsed := 0.0
var output := "res://../captures"
var report := {"checks": [], "captures": [], "light_samples": {}}

func _ready() -> void:
	run.call_deferred()

func _process(dt: float) -> void:
	elapsed += dt
	if elapsed > 180.0: get_tree().quit(2)

func check(passed: bool, label: String) -> void:
	report.checks.append({"check": label, "passed": passed})
	if not passed: push_error(label)

func run() -> void:
	if DisplayServer.get_name() == "headless": get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	vp = SubViewport.new()
	vp.size = Vector2i(1200, 1100)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var preview := TextureRect.new()
	preview.texture = vp.get_texture()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("B5A18B")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("FFF1DC")
	env.ambient_light_energy = .40
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	vp.add_child(world)
	sun = DirectionalLight3D.new()
	sun.light_color = Color("FFF2DA")
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 30
	sun.shadow_bias = .15
	sun.shadow_normal_bias = .8
	sun.light_angular_distance = .4
	vp.add_child(sun)
	sun.position = Vector3(-6, 4, -1)
	sun.look_at(Vector3.ZERO)
	art = load("res://scenes/shell_hall/shell_hall_art.tscn").instantiate()
	vp.add_child(art)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = .1
	camera.far = 40.0
	vp.add_child(camera)
	camera.make_current()
	for i in 6: await get_tree().process_frame
	await get_tree().physics_frame
	validate_scene()
	await shot("shell_full", 45, 43, 11.0, Vector3(0, 2.0, 0), Vector2i(1200, 1100))
	for direction in [["front", 0], ["right", 90], ["back", 180], ["left", 270]]:
		await shot("shell_" + direction[0], direction[1], 0, 8.0, Vector3(0, 1.75, 0), Vector2i(1000, 650))
	await shot("shell_top", 0, 89.99, 7.5, Vector3(0, 0, 0), Vector2i(1100, 1100))
	await shot("window_detail", 110, 12, 3.2, Vector3(-3.10, 2.25, 1.78), Vector2i(900, 900))
	# Lighting evidence: the floor should visibly receive sunlight through both real apertures.
	await shot("sun_on", 45, 43, 11.0, Vector3(0, 2.0, 0), Vector2i(1200, 1100))
	sun.light_energy = 0
	await shot("sun_off", 45, 43, 11.0, Vector3(0, 2.0, 0), Vector2i(1200, 1100))
	for name in ["rear_window", "front_window"]:
		var a: Array = report.light_samples.sun_on[name]
		var b: Array = report.light_samples.sun_off[name]
		var delta: float = (a[0] + a[1] + a[2] - b[0] - b[1] - b[2]) / 3.0
		check(delta > .06, name + " direct window light visible in actual rendered pixels")
	report.renderer = RenderingServer.get_current_rendering_method()
	report.adapter = RenderingServer.get_video_adapter_name()
	report.passed = report.get("physics_complete", false) and report.checks.all(func(c): return c.passed)
	FileAccess.open(output + "/godot-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("HALL_GODOT_VALIDATION ", report.passed, " checks=", report.checks.size())
	get_tree().quit(0 if report.passed else 1)

func shot(filename: String, yaw: float, pitch: float, width: float, target: Vector3, resolution: Vector2i) -> void:
	vp.size = resolution
	camera.size = width
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	camera.position = target + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * 18
	camera.look_at(target)
	for i in 4:
		await get_tree().process_frame
		RenderingServer.force_draw(true)
	var image := vp.get_texture().get_image()
	if filename == "shell_full":
		for mesh in art.find_children("*", "MeshInstance3D", true, false):
			for corner in 8:
				var pixel := camera.unproject_position(mesh.to_global(mesh.get_aabb().get_endpoint(corner)))
				check(Rect2(Vector2(8, 8), Vector2(resolution) - Vector2(16, 16)).has_point(pixel), str(mesh.name) + " full-view corner framed")
	if filename in ["sun_on", "sun_off"]:
		var samples := {}
		for sample in [["rear_window", Vector3(.26625, .081, -1.185625)], ["front_window", Vector3(.26625, .081, 2.374375)]]:
			var pixel := Vector2i(camera.unproject_position(sample[1]))
			var rgb := image.get_pixelv(pixel)
			samples[sample[0]] = [rgb.r, rgb.g, rgb.b]
		report.light_samples[filename] = samples
	check(image.get_size() == resolution, filename + " requested pixel dimensions")
	check(image.save_png(output + "/" + filename + ".png") == OK, filename + " image saved")
	report.captures.append({"name": filename, "resolution": [resolution.x, resolution.y], "camera_width": width,
		"pitch": pitch, "yaw": yaw, "camera_transform": str(camera.global_transform)})
	print("HALL_CAPTURE ", filename)

func validate_scene() -> void:
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KIT + "shell_asset_stats.json"))
	var triangles := 0
	var surfaces := 0
	var glass := 0
	for node in art.find_children("*", "MeshInstance3D", true, false):
		check(node.material_override == null, str(node.name) + " retains per-surface material")
		for index in node.mesh.get_surface_count():
			surfaces += 1
			var data: Array = node.mesh.surface_get_arrays(index)
			triangles += data[Mesh.ARRAY_INDEX].size() / 3 if data[Mesh.ARRAY_INDEX].size() > 0 else data[Mesh.ARRAY_VERTEX].size() / 3
			var material := node.get_active_material(index) as StandardMaterial3D
			check(material != null and material.albedo_texture.get_width() == 2048, str(node.name) + " 2048 atlas bound")
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				glass += 1
				check(node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "glazing does not block sun")
	check(triangles == expected.scene_triangles, "imported triangle count matches exported scene")
	check(surfaces == expected.static_draw_surfaces, "imported surface count matches scene")
	check(glass == 1, "exactly one separate glass surface for both windows")
	check(art.find_children("*", "Light3D", true, false).is_empty(), "reusable shell contains no lights")
	check(art.find_children("*", "Camera3D", true, false).is_empty(), "reusable shell contains no cameras")
	var bodies := art.find_children("*", "StaticBody3D", true, false)
	check(bodies.size() == 5, "floor, two walls and two open-edge colliders generated")
	var space := vp.find_world_3d().direct_space_state
	for point in [Vector3(0, 0, 0), Vector3(2.7, 0, 2.6), Vector3(-2.7, 0, -2.6)]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP))
		check(not hit.is_empty() and absf(hit.position.y - .08) < .001, "floor collision top matches visual .08 m")
	var capsule := CapsuleShape3D.new()
	capsule.radius = .25
	capsule.height = 1.745
	for path in [
		["spawn_to_center", Vector3(0, 0, 2.5), Vector3.ZERO, false],
		["center_to_left_window", Vector3.ZERO, Vector3(-2.7, 0, 1.78), false],
		["center_to_back", Vector3.ZERO, Vector3(0, 0, -2.5), false],
		["center_to_exit", Vector3.ZERO, Vector3(0, 0, 2.88), false],
		["right_containment", Vector3(2.8, 0, 0), Vector3(4, 0, 0), true],
		["front_containment", Vector3(0, 0, 2.8), Vector3(0, 0, 4), true],
		["left_wall_blocks", Vector3(-2.7, 0, 0), Vector3(-4, 0, 0), true],
		["back_wall_blocks", Vector3(0, 0, -2.6), Vector3(0, 0, -4), true],
	]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = path[1] + Vector3(0, .08 + 1.745 / 2 + .003, 0)
		query.motion = path[2] - path[1]
		query.margin = .001
		var result := space.cast_motion(query)
		check((result[0] < 1) == path[3], "capsule sweep " + path[0])
	report.triangles = triangles
	report.surfaces = surfaces
	report.collision_bodies = bodies.size()
	report.physics_complete = true
