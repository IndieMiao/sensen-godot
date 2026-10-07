extends SceneTree
## Real Mobile/Vulkan catalogue preview. Copy this script to a staged project root.
func _initialize() -> void:
	call_deferred("render_library")

func assign(node: Node, mat: Material) -> void:
	if node is MeshInstance3D: node.material_override = mat
	for child in node.get_children(): assign(child, mat)

func render_library() -> void:
	var output: String = OS.get_cmdline_user_args()[0]
	var view := SubViewport.new()
	view.size = Vector2i(640,640)
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_4X
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var world := Node3D.new()
	view.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("e9e5d7")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("bcd6dd")
	env.environment.ambient_light_energy = .7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff1d5")
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	world.add_child(sun)
	sun.position = Vector3(-3,5,4)
	sun.look_at(Vector3.ZERO)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(camera)
	camera.current = true
	var mat := load("res://assets/rooms/_shared/plants/material.tres") as Material
	for name in ["monstera","peace_lily","pothos","ivy_short","ivy_medium","ivy_long","flower_shrub","olive_tree","fruit_tree"]:
		var plant := (load("res://assets/rooms/_shared/plants/"+name+".glb") as PackedScene).instantiate() as Node3D
		world.add_child(plant)
		assign(plant,mat)
		var target := Vector3(0,.78,0)
		camera.size = 2.35
		if name.begins_with("ivy"):
			plant.position.y = 1.6
			target.y = 1.0
			camera.size = 2.0
		elif name == "pothos":
			plant.position.y = 1.0
		elif name == "flower_shrub":
			target.y = .2
			camera.size = 1.30
		camera.position = target + Vector3(2,1.3,4)
		camera.look_at(target)
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		assert(view.get_texture().get_image().save_png(output+"/"+name+".png") == OK)
		plant.queue_free()
		await process_frame
		print("PLANT_CAPTURE ",name)
	quit()
