extends SceneTree
## Run against resources extracted from the APK, using the APK's compiled scripts.

func _initialize() -> void:
	_verify.call_deferred()

func _verify() -> void:
	var report_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--farm-app-report="): report_path = arg.trim_prefix("--farm-app-report=")
	var art = load("res://modules/farm/farm_art.gd")
	var styles: Array = []
	for style in art.STYLES:
		var mesh: Mesh = art.mesh_for("house_" + style)
		assert(mesh != null and mesh.get_surface_count() == 1)
		styles.append({"style": style, "house_surfaces": mesh.get_surface_count()})
	assert(styles.size() == 7)
	assert(art.style_for("shanghai", "sh_b") == "east_asian")
	assert(art.style_for("los_angeles", "la_a") == "barn")
	for style in art.STYLES:
		assert(load("res://assets/farm/art/previews/" + str(style) + ".png") is Texture2D)
	for region in ["shanghai", "los_angeles"]:
		assert(PresetSnapshots.entries(region).size() == 6)
	assert(load("res://scenes/select/select_panel.gd").CAPACITY_TEXT == "4 plots · unlock 6, then 9")
	for resource in ["res://modules/farm/field_growth.gd", "res://modules/ui/loading_overlay.gd", "res://modules/ui/entry_confirmation.gd", "res://scenes/map/farm_miniature.gd"]:
		assert(ResourceLoader.exists(resource))
	var assets: Array = []
	for entry in ResourceLoader.list_directory("res://assets/farm/art/"):
		if not entry.ends_with(".glb"): continue
		var asset := entry.trim_suffix(".glb")
		var mesh: Mesh = art.mesh_for(asset)
		assert(mesh != null and mesh.get_surface_count() == 1)
		assets.append(asset)
	assert(assets.size() == 24)
	assert(art.ground_material("path_tile").shader != null)
	assert(art.ground_material("plot").shader != null)
	assert(art.ground_material("plot").get_shader_parameter("meadow_texture") is Texture2D)
	assert(ResourceLoader.exists("res://scenes/farm/farm.tscn"))
	assert(ResourceLoader.exists("res://modules/farm/farm_scenery.gd"))
	var scene_state := (load("res://scenes/farm/farm.tscn") as PackedScene).get_state()
	var scene_settings := {}
	for node in scene_state.get_node_count():
		var name := str(scene_state.get_node_name(node))
		if name not in ["Sun", "Camera3D"]: continue
		scene_settings[name] = {}
		for property in scene_state.get_node_property_count(node):
			scene_settings[name][str(scene_state.get_node_property_name(node, property))] = scene_state.get_node_property_value(node, property)
	assert(scene_settings.Sun.shadow_enabled)
	assert(scene_settings.Sun.directional_shadow_mode == 0)
	assert(scene_settings.Camera3D.near == 1.0 and scene_settings.Camera3D.far == 32.0)
	var snapshot: Dictionary = PresetSnapshots.snapshot(PresetSnapshots.entries("shanghai")[0].farm_id)
	var blueprint := FarmBlueprint.load_file(FarmBlueprint.asset_path(str(snapshot.layout_patch_id), int(snapshot.blueprint_revision)))
	var runtime: Array = []
	for style in art.STYLES:
		var farm := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
		farm.setup({"visitor": true, "snapshot": snapshot, "blueprint": blueprint, "farm_style": style})
		root.add_child(farm)
		await process_frame
		farm._update_camera()
		assert(farm.cam.far < 60.0)
		assert(farm.scenery.get_child_count() > 10)
		assert(farm.ground.material_override is ShaderMaterial)
		assert(farm.scenery._garden_path.material_override is ShaderMaterial)
		runtime.append({"style": style, "camera_near": farm.cam.near, "camera_far": farm.cam.far,
			"scenery_batches": farm.scenery.get_child_count()})
		root.remove_child(farm)
		farm.queue_free()
		await process_frame
	assert(not root.get_node("Net").booted_once)
	assert(not ResourceLoader.exists("res://tools/dev/farm_art_preview.tscn"))
	assert(not FileAccess.file_exists("res://tools/art/source/farm_reference_kit.blend"))
	var report := {"passed": true, "styles": styles, "assets": assets, "scene_settings": scene_settings, "runtime": runtime,
		"main_scene": ProjectSettings.get_setting("application/run/main_scene"),
		"user_directory": ProjectSettings.get_setting("application/config/custom_user_dir_name", ""),
		"validation": "Extracted APK resources and seven initialized visitor farms, headless; Android pixels and touch verified separately",
		"art_preview_excluded": true, "blender_source_excluded": true}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("FARM_APP_RESOURCES ", JSON.stringify(report))
	quit()
