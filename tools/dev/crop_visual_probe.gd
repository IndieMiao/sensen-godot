extends SceneTree
## Deterministic render proof for the four crop stages, weeds and tilled soil.

func _init() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1280, 900)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.86, 0.91, 0.83)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.55
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -24, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.5
	stage.add_child(camera)
	var center := Vector3(3.0, 0, -2.0)
	camera.position = center + Vector3(0, 8.5, 5.0)
	camera.look_at(center)
	var bp := FarmBlueprint.load_file("res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json")
	var field := CropField.new(bp)
	field.ground_y = 0.15
	stage.add_child(field)
	var cells := {}
	for row in 4:
		for column in 6:
			var cell := Vector2i(column, row)
			var position := bp.cell_to_world(cell)
			var bed := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.92, 0.15, 0.92)
			bed.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.53, 0.35, 0.22)
			material.roughness = 1.0
			bed.material_override = material
			bed.position = position + Vector3(0, 0.075, 0)
			stage.add_child(bed)
			var id := "%d,%d" % [column, row]
			if column < 4:
				cells[id] = {"state": "growing", "crop": CropField.CROPS[column],
					"care_done_at": -row * 100, "ready_at": 300 - row * 100}
			else:
				cells[id] = {"state": "wild" if column == 4 else "tilled"}
	field.sync(cells, 0)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://output/farm-ui-device")
	var path := "res://output/farm-ui-device/crop-plants.png"
	var result := image.save_png(path)
	print("Crop visual proof: ", path, " error=", result, " size=", image.get_size())
	quit(result)
