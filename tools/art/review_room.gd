extends SceneTree
## Art-only import/render inspection. No player, network, UI or saved data.
var slug: String
var output_dir: String

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	slug = args[0]
	output_dir = args[1]
	call_deferred("capture")

func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

func capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440,1080)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var kit := load("res://scenes/%s/%s_art.tscn" % [slug,slug]) as PackedScene
	assert(kit != null)
	var room := kit.instantiate()
	world.add_child(room)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/%s/layout.json" % slug))
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e8e4c8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff0dc")
	environment.ambient_light_energy = .70
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	var env := WorldEnvironment.new()
	env.environment = environment
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe6c2")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 35
	sun.shadow_bias = .045
	sun.shadow_normal_bias = .40
	sun.light_angular_distance = 1.4
	world.add_child(sun)
	sun.position = Vector3(-6,7,1.5)
	sun.look_at(Vector3.ZERO)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	ground.position.y = -.36
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("eae4c8")
	mat.roughness = 1
	ground.material_override = mat
	world.add_child(ground)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Manifest size is Blender's horizontal orthographic span at 4:3.
	camera.size = float(layout.camera.size) * .75
	world.add_child(camera)
	camera.position = vec(layout.camera.position)
	camera.look_at(vec(layout.camera.target))
	camera.current = true
	for i in range(20): await process_frame
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	assert(img.save_png(output_dir + "/godot.png") == OK)
	var stats := {"scene":slug,"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"resolution":[1440,1080],
		"mesh_instances":0,"surfaces":0,"triangles":0,"colliders":0,"finite_aabbs":true}
	inspect(room,stats)
	assert(stats.mesh_instances == layout.assets.size() + layout.instances.size())
	assert(stats.finite_aabbs)
	var file := FileAccess.open(output_dir + "/godot-validation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(stats,"\t"))
	print("ROOM_RENDER_VERIFIED ",JSON.stringify(stats))
	quit()

func inspect(node: Node, stats: Dictionary) -> void:
	if node is MeshInstance3D:
		stats.mesh_instances += 1
		assert(node.material_override != null)
		assert(node.material_override.albedo_texture != null)
		var box: AABB = node.get_aabb()
		stats.finite_aabbs = stats.finite_aabbs and box.position.is_finite() and box.size.is_finite() and box.size.length()>0
		for i in node.mesh.get_surface_count():
			stats.surfaces += 1
			var arrays: Array = node.mesh.surface_get_arrays(i)
			stats.triangles += arrays[Mesh.ARRAY_INDEX].size()/3 if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()/3
	if node is CollisionShape3D: stats.colliders += 1
	for child in node.get_children():inspect(child,stats)
