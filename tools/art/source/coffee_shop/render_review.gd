extends SceneTree
## Offline still renderer, never a gameplay/benchmark scene.
var viewport: SubViewport
var camera: Camera3D
var slug: String
var layout: Dictionary
var output_dir: String
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_render")

func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func _render() -> void:
	var args := OS.get_cmdline_user_args()
	slug = args[0]
	output_dir = args[1]
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rooms/" + slug + "/layout.json"))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1400,1400)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var room := (load("res://scenes/" + slug + "/" + slug + "_art.tscn") as PackedScene).instantiate()
	world.add_child(room)
	assert(room.get_child_count() == layout.assets.size() + layout.instances.size(), "Missing module instances")
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	ground.position.y = -.36
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("c5d3bc")
	mat.roughness = 1
	ground.material_override = mat
	world.add_child(ground)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("c9dfcb")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff1dc")
	env.ambient_light_energy = .62
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff1dd")
	sun.light_energy = .95
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40
	sun.light_angular_distance = 3
	world.add_child(sun)
	sun.position = Vector3(-3,10,4)
	sun.look_at(Vector3.ZERO)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .05
	camera.far = 150
	world.add_child(camera)
	camera.current = true
	var views := [
		["godot-whole",_vec(layout.camera.position),_vec(layout.camera.target),float(layout.camera.size)],
		["model-front",Vector3(0,1.5,20),Vector3(0,1.5,0),9.8 if slug == "coffee_shop_0" else 8.0],
		["model-side",Vector3(20,1.5,0),Vector3(0,1.5,0),9.8 if slug == "coffee_shop_0" else 8.0],
		["model-top",Vector3(.001,20,0),Vector3.ZERO,9.8 if slug == "coffee_shop_0" else 8.0],
		["godot-detail",Vector3(7,6,9),Vector3(0,1.25,-1.1),5.7]
	]
	for view in views:
		camera.position = view[1]
		camera.look_at(view[2])
		camera.size = view[3]
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		assert(image.get_size() == viewport.size)
		assert(image.save_png(output_dir + "/" + view[0] + ".png") == OK)
		print("SHOP_CAPTURE ",view[0])
	var result := {"slug":slug,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"instances":room.get_child_count(),"resolution":[1400,1400],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"scope":"offline art render; no mobile/gameplay/performance acceptance"}
	var file := FileAccess.open(output_dir + "/godot-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  ")+"\n")
	print("SHOP_REVIEW_PASS ",JSON.stringify(result))
	quit()
