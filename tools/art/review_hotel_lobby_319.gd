extends Node

const KIT := "res://assets/rooms/poi_hotel_lobby/"
var vp: SubViewport
var art: Node3D
var camera: Camera3D
var elapsed := 0.0
var out := "res://../captures"
var report := {"checks": [], "captures": []}

func _ready() -> void: run.call_deferred()
func _process(dt: float) -> void:
	elapsed += dt
	if elapsed > 180: get_tree().quit(2)

func check(ok: bool, label: String) -> void:
	report.checks.append({"check": label, "passed": ok})
	if not ok: push_error(label)

func run() -> void:
	if DisplayServer.get_name() == "headless": get_tree().quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	vp = SubViewport.new()
	vp.size = Vector2i(1440, 1320)
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
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.environment = env
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
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
	art = load("res://scenes/poi_hotel_lobby/poi_hotel_lobby_art.tscn").instantiate()
	vp.add_child(art)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = .1
	camera.far = 40
	vp.add_child(camera)
	camera.make_current()
	for i in 8: await get_tree().process_frame
	await get_tree().physics_frame
	validate()
	await shot("full", Vector3(0, 2.0, 0), 11.0, 45, 43, Vector2i(1440, 1320))
	await shot("top", Vector3(0, 0, 0), 7.6, 0, 89.99, Vector2i(1200, 1200))
	await shot("hearth", Vector3(-2.25, 1.35, .10), 3.6, 100, 22, Vector2i(1200, 1000))
	await shot("keys", Vector3(.37, 2.20, -2.65), 4.2, 10, 16, Vector2i(1200, 1000))
	await shot("sofa", Vector3(1.10, .85, .58), 5.2, 45, 36, Vector2i(1200, 1100))
	await native_entry()
	await shot("fire_a", Vector3(-2.25, .6, .10), 1.65, 90, 14, Vector2i(720, 720))
	for i in 20:
		await get_tree().process_frame
		RenderingServer.force_draw(true)
	await shot("fire_b", Vector3(-2.25, .6, .10), 1.65, 90, 14, Vector2i(720, 720))
	await shot("local_lights_on", Vector3(0, 2.0, 0), 11.0, 45, 43, Vector2i(1440, 1320))
	for light in art.find_children("*", "Light3D", true, false): light.visible = false
	await shot("local_lights_off", Vector3(0, 2.0, 0), 11.0, 45, 43, Vector2i(1440, 1320))
	report.renderer = RenderingServer.get_current_rendering_method()
	report.adapter = RenderingServer.get_video_adapter_name()
	report.passed = report.checks.all(func(c): return c.passed)
	FileAccess.open(out + "/godot-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("N1_GODOT_VALIDATION ", report.passed, " checks=", report.checks.size())
	get_tree().quit(0 if report.passed else 1)

func shot(name_: String, target: Vector3, width: float, yaw: float, pitch: float, size_: Vector2i) -> void:
	vp.size = size_
	camera.size = width
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	camera.position = target + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * 18
	camera.look_at(target)
	for i in 6:
		await get_tree().process_frame
		RenderingServer.force_draw(true)
	var image := vp.get_texture().get_image()
	check(image.save_png(out + "/" + name_ + ".png") == OK, name_ + " saved")
	report.captures.append({"name": name_, "size": [size_.x, size_.y], "width": width, "yaw": yaw, "pitch": pitch, "camera_transform": str(camera.global_transform)})
	print("N1_CAPTURE ", name_)

func native_entry() -> void:
	var native: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://native-camera.json"))
	var columns: Array = native.basis
	var vector := func(a: Array): return Vector3(a[0], a[1], a[2])
	camera.transform = Transform3D(Basis(vector.call(columns[0]), vector.call(columns[1]), vector.call(columns[2])), vector.call(native.origin))
	camera.size = float(native.width_m)
	check(absf(camera.rotation_degrees.x + 43.0) < .001 and absf(camera.size - 6.72) < .001, "native P0 opening pitch and width")
	for size_ in [Vector2i(360, 800), Vector2i(720, 1600)]:
		vp.size = size_
		for i in 6:
			await get_tree().process_frame
			RenderingServer.force_draw(true)
		var image := vp.get_texture().get_image()
		var filename := "entry_%d" % size_.x
		check(image.save_png(out + "/" + filename + ".png") == OK, filename + " saved at native aspect")
		report.captures.append({"name": filename, "size": [size_.x, size_.y], "width": camera.size, "pitch": camera.rotation_degrees.x,
			"native_framing": native, "camera_transform": str(camera.transform), "art_clip": [.1, 40]})
		print("N1_CAPTURE ", filename)

func validate() -> void:
	var stats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KIT + "asset_stats.json"))
	var triangles := 0
	var surfaces := 0
	var glass := 0
	var ao := 0
	report.materials = []
	for mesh in art.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var arrays: Array = mesh.mesh.surface_get_arrays(surface)
			triangles += arrays[Mesh.ARRAY_INDEX].size() / 3 if arrays[Mesh.ARRAY_INDEX].size() else arrays[Mesh.ARRAY_VERTEX].size() / 3
			surfaces += 1
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			report.materials.append({"node": str(mesh.get_path()), "name": material.resource_name, "shading": material.shading_mode,
				"alpha": material.transparency, "vertex_color": material.vertex_color_use_as_albedo, "texture": material.albedo_texture.resource_path})
			if material.resource_name == "HallWindowGlass":
				glass += 1
				check(material.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS], "imported glass alpha mode preserved")
			if arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR].size() > 0:
				ao += 1
				check(material.vertex_color_use_as_albedo, str(mesh.name) + " scalar AO enabled")
	check(triangles == stats.scene_triangles, "actual assembly triangle budget")
	check(surfaces == stats.static_draw_surfaces, "actual assembly surface budget")
	check(glass == 1, "one shared shell glazing surface")
	check(ao > 20, "N1 modules carry local AO")
	check(art.find_children("seat_*", "Marker3D", true, false).size() == 8, "eight seats")
	check(art.get_node("sign_name").get_meta("size") == [2.28, .145], "blank runtime name marker size")
	check(art.get_node("cam_default").get_meta("role") == "camera_follow_target" and art.get_node("cam_default").position == art.get_node("spawn").position, "default camera marker identifies the spawn follow target")
	var nav: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://navigation.json"))
	var space := vp.find_world_3d().direct_space_state
	for route in nav.paths:
		var capsule := CapsuleShape3D.new()
		capsule.radius = float(route.radius)
		capsule.height = 1.745
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.margin = .0001
		var clear := true
		for i in range(1, route.path_xz.size()):
			var a: Array = route.path_xz[i - 1]
			var b: Array = route.path_xz[i]
			query.transform.origin = Vector3(a[0], .08 + 1.745 / 2 + .003, a[1])
			query.motion = Vector3(b[0] - a[0], 0, b[1] - a[1])
			if space.cast_motion(query)[0] < .999: clear = false; break
		check(clear, "actual scene capsule " + str(route.name))
	report.triangles = triangles
	report.surfaces = surfaces
	report.local_ao_surfaces = ao
