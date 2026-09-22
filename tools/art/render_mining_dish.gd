extends Node
## Render the same soup mesh used at the bistro into its inventory thumbnail.

func _enter_tree() -> void:
	Net.booting = true
	Net.booted_once = true

func _ready() -> void:
	call_deferred("_render")

func _render() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Dish rendering requires a graphical renderer")
		get_tree().quit(2)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	var place := JourneyPlace.new()
	var dish: MeshInstance3D = place._dish_mesh("vegetable_soup", "SoupThumbnail")
	place.free()
	viewport.add_child(dish)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.72
	viewport.add_child(camera)
	camera.position = Vector3(0.65, 0.8, 1.0)
	camera.look_at(Vector3(0, 0.07, 0))
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.TRANSPARENT
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 1.1
	viewport.add_child(light)
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	var output := "res://assets/ui/farm/dishes/vegetable_soup.png"
	var result := pixels.save_png(output)
	print("MINING_DISH_RENDER ", output, " error=", result)
	viewport.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if result == OK else 1)
