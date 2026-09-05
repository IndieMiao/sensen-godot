extends SceneTree

const FarmProps = preload("res://modules/farm/farm_props.gd")

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.87, 0.93, 0.84)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.55
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.4
	stage.add_child(camera)
	camera.position = Vector3(0.7, 4.0, 5.0)
	camera.look_at(Vector3(0.3, 0.55, 0))
	stage.add_child(FarmProps.build("house", Vector3(-1.3, 0, 0)))
	stage.add_child(FarmProps.build("storage", Vector3(0.75, 0, 0.1)))
	stage.add_child(FarmProps.build("well", Vector3(2.05, 0, 0)))
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://output/farm-ui-device")
	var result := image.save_png("res://output/farm-ui-device/farm-props.png")
	print("Farm props visual proof: error=", result, " size=", image.get_size())
	quit(result)
