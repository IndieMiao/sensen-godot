extends Node
## Isolated art review; no gameplay/autoload other than the fixed avatar fixture.
const KIT = "res://assets/rooms/_shared/shell_hall/"
const H = 1.745
var report = {"checks": [], "assets": {}, "captures": [], "author": "Huang Zhong"}
var vp: SubViewport
var world: Node3D
var camera: Camera3D
var assets: Dictionary = {}
var stats: Dictionary
var rig
var floor_mesh: MeshInstance3D
var mounts: Array[Node3D] = []
var output: String

func _ready():
	run.call_deferred()

func xyz(p):
	return [p.x, p.y, p.z]

func vec(p):
	return Vector3(p[0], p[1], p[2])

func check(ok, label):
	report.checks.append({"passed": bool(ok), "check": label})
	if not ok: push_error(label)

func material(colour):
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(colour)
	mat.roughness = .9
	return mat

func box(name, size, at, colour):
	var mesh = MeshInstance3D.new()
	mesh.name = name
	var shape = BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(colour)
	world.add_child(mesh)
	mesh.position = at
	return mesh

func setup():
	vp = SubViewport.new()
	vp.size = Vector2i(3200, 800)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("e4e9ea")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff6e8")
	env.ambient_light_energy = .35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var environment = WorldEnvironment.new()
	environment.environment = env
	world.add_child(environment)
	var sun = DirectionalLight3D.new()
	world.add_child(sun)
	sun.rotation_degrees = Vector3(-48, -30, 0)
	sun.light_color = Color("fff6e8")
	sun.light_energy = .85
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 70
	sun.shadow_bias = .1
	sun.shadow_normal_bias = .4
	sun.light_angular_distance = 3
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.near = .05
	camera.far = 100
	world.add_child(camera)
	camera.current = true
	floor_mesh = box("ReviewFloor", Vector3(100, .06, 50), Vector3(10, -.03, 0), "b9c6c8")
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func audit_and_place():
	var x = 0.0
	var shared = load(KIT + "hall_opaque.tres")
	var glass = load(KIT + "hall_glass.tres")
	for item in stats.assets:
		var node = load(KIT + item.file).instantiate()
		world.add_child(node)
		var bounds = AABB()
		var first = true
		var triangles = 0
		var surfaces = 0
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = glass if mesh.name == "Glass" else shared
			if mesh.name == "Glass": mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for s in mesh.mesh.get_surface_count():
				var data = mesh.mesh.surface_get_arrays(s)
				surfaces += 1
				triangles += data[Mesh.ARRAY_INDEX].size()/3
				for vertex in data[Mesh.ARRAY_VERTEX]:
					var point = node.global_transform.affine_inverse()*mesh.global_transform*vertex
					if first:
						bounds = AABB(point, Vector3.ZERO)
						first = false
					else: bounds = bounds.expand(point)
		check(triangles == item.triangles, item.name + " imported triangles match")
		check(surfaces == item.surfaces, item.name + " imported surfaces match")
		check(bounds.size.distance_to(vec(item.dimensions_xyz_m)) < .00001, item.name + " actual imported dimensions match")
		if item.family == "frames":
			var art = node.find_child("Artwork", true, false)
			check(art != null and art.mesh.get_surface_count() == 1, item.name + " independently replaceable Artwork node")
		if item.family == "display":
			check(node.find_child("Glass", true, false) != null, item.name + " independent transparent Glass node")
		x += bounds.size.x/2
		node.position.x = x
		if item.family in ["frames", "sconce"]:
			node.position.y = 1.50
			var mount = box("ReviewMount_"+item.name, Vector3(bounds.size.x+.22, bounds.size.y+.25, .05),
				Vector3(x, 1.50, -.025), "e4e3df")
			mounts.append(mount)
			if item.family == "sconce":
				var light = OmniLight3D.new()
				node.add_child(light)
				light.position = Vector3(0, 0, .23)
				light.light_color = Color("ffc87d")
				light.light_energy = .55
				light.omni_range = .75
		assets[item.name] = node
		report.assets[item.name] = {"bounds": [xyz(bounds.position), xyz(bounds.end)],
			"triangles": triangles, "surfaces": surfaces, "placement": xyz(node.position)}
		x += bounds.size.x/2 + .65
	return x

func add_avatar(x):
	rig = Avatar.create_rig()
	for child in rig.get_children():
		if child is RigActivity: child.free()
	rig.assembler = AvatarAssemblerMerged.new()
	world.add_child(rig)
	rig.apply_config(Avatar.slot_table.default_config())
	var ticks = 0
	while rig.is_busy() and ticks < 900:
		await get_tree().process_frame
		ticks += 1
	check(not rig.is_busy(), "Basic Room fixture avatar assembled")
	rig.play_motion("idle")
	var anim = rig.get_node("AnimationPlayer")
	anim.seek(.3, true)
	anim.pause()
	# Bound the actual posed skin, including the fixture hair and shoes.
	var lo = INF
	var hi = -INF
	for mesh in rig.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var posed = mesh.bake_mesh_from_current_skeleton_pose() if mesh.skin != null else mesh.mesh
		if posed == null: continue
		for s in posed.get_surface_count():
			for v in posed.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var point = rig.global_transform.affine_inverse()*mesh.global_transform*v
				lo = minf(lo, point.y)
				hi = maxf(hi, point.y)
	check(is_finite(lo) and hi > lo, "actual avatar posed vertices measured")
	var factor = H/(hi-lo)
	rig.scale = Vector3.ONE*factor
	rig.position = Vector3(x, -lo*factor, 0)
	report.avatar = {"fixture": "Basic Room defaults", "source_height_m": hi-lo,
		"uniform_scale": factor, "displayed_height_m": H, "floor_offset_m": -lo*factor}

func pose(focus, width, pitch, yaw):
	camera.size = width
	camera.rotation_degrees = Vector3(-pitch, yaw, 0)
	camera.position = focus + camera.basis.z*40

func capture(name):
	for i in 12: await RenderingServer.frame_post_draw
	var image = vp.get_texture().get_image()
	check(image.save_png(output + "/" + name + ".png") == OK, "saved " + name)
	var positions = {}
	for key in assets:
		positions[key] = [camera.unproject_position(assets[key].position).x, camera.unproject_position(assets[key].position).y]
	report.captures.append({"id": name, "size": [image.get_width(), image.get_height()],
		"pitch": -camera.rotation_degrees.x, "yaw": camera.rotation_degrees.y, "width_m": camera.size,
		"screen_origins": positions, "draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)})
	print("HALLKIT_CAPTURE ", name)

func run():
	output = ProjectSettings.globalize_path("res://../captures")
	DirAccess.make_dir_recursive_absolute(output)
	stats = JSON.parse_string(FileAccess.get_file_as_string(KIT + "asset_stats.json"))
	setup()
	var length = audit_and_place()
	await add_avatar(length + .15)
	pose(Vector3(length/2, .8, 0), length+2.8, 20, 0)
	await capture("lineup")
	var initial_positions = {}
	for key in assets: initial_positions[key] = assets[key].position
	vp.size = Vector2i(1000, 850)
	for family in ["sofa", "armchair", "bench", "table", "stool", "sconce", "frames", "display"]:
		var members = []
		for item in stats.assets:
			assets[item.name].visible = item.family == family
			if item.family == family: members.append(item)
		for mount in mounts: mount.visible = false
		var start = assets[members[0].name].position.x
		var end = assets[members[-1].name].position.x + members[-1].dimensions_xyz_m[0]/2
		var width = end-start+members[0].dimensions_xyz_m[0]/2
		rig.position.x = end+.65
		pose(Vector3((start+end)/2, .75, 0), maxf(3.4, width+2.3), 28, 15)
		await capture("detail_"+family)
	for key in assets:
		assets[key].visible = true
		assets[key].position = initial_positions[key]
	report.renderer = {"method": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "api": RenderingServer.get_video_adapter_api_version()}
	check(report.renderer.method == "mobile", "actual target renderer is Mobile")
	var failed = report.checks.filter(func(c): return not c.passed)
	report.passed = failed.is_empty()
	var file = FileAccess.open(output+"/godot-validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")+"\n")
	print("HALLKIT_VALIDATION ", report.passed, " checks=", report.checks.size())
	get_tree().quit(0 if report.passed else 1)
