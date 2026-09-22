extends Node
## Focused native proof: a physical 3x character preview with unchanged logical layout.
const Preview := preload("res://scenes/inventory/character_preview.gd")
const OUT := "res://output/ui-redesign-2026-09-21/character-density"
func _ready() -> void:
	get_tree().root.content_scale_size = Vector2i(720, 960)
	get_tree().root.size = Vector2i(720, 960)
	_run.call_deferred()
func _run() -> void:
	var before := Avatar.load_outfit().to_json_text()
	var world := Node3D.new()
	add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var background := ColorRect.new()
	background.color = Color("fffdf8")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var stage := Control.new()
	stage.position = Vector2(160, 140)
	var physical_scale := get_viewport().get_screen_transform().x.length()
	stage.scale = Vector2.ONE * (3.0 / maxf(physical_scale, 0.01))
	add_child(stage)
	var preview := Preview.new()
	stage.add_child(preview)
	preview.size = Vector2(112, 196)
	preview.set_active(true)
	for frame in 180:
		if preview.rig != null and not preview.rig.is_busy(): break
		await get_tree().process_frame
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT.path_join("portrait-physical-3x.png")))
	preview.viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT.path_join("portrait-raster.png")))
	var report := {"logical_size": [preview.size.x, preview.size.y], "render_pixels": [preview.viewport.size.x, preview.viewport.size.y],
		"world_camera_preserved": get_viewport().get_camera_3d() == camera, "saved_outfit_preserved": Avatar.load_outfit().to_json_text() == before}
	preview.hide()
	report.hidden_render_disabled = preview.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not preview.is_processing()
	report.passed = preview.viewport.size == Vector2i(336, 588) and report.world_camera_preserved and report.saved_outfit_preserved and report.hidden_render_disabled
	FileAccess.open(OUT.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CHARACTER_DENSITY_GALLERY ",JSON.stringify(report))
	get_tree().quit(0 if report.passed else 1)
