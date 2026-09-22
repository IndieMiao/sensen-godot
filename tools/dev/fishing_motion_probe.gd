extends "res://tools/dev/free_farm_probe.gd"
## Isolated rendering/animation evidence. This probe does not claim HTTP or player validation.

func _ready() -> void:
	super._ready()
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 60
	for frame in 100: await get_tree().process_frame
	var outfit_path := OS.get_environment("FISHING_AVATAR_CONFIG")
	if not outfit_path.is_empty():
		farm._rig.apply_config(AvatarConfig.from_json_text(FileAccess.get_file_as_string(outfit_path)))
		for frame in 180:
			await get_tree().process_frame
			if not farm._rig.is_busy(): break
	var directory := ProjectSettings.globalize_path("res://output/fishing-presentation-2026-09-18/native")
	var override := OS.get_environment("FISHING_PRESENTATION_CAPTURE")
	if not override.is_empty(): directory = override
	DirAccess.make_dir_recursive_absolute(directory)
	farm.mover.stop()
	farm.mover.position = FishingModel.stand("farm_pond")
	farm.player.position = farm.mover.position
	farm.session.state.fishing = {"sequence": 1, "active": {"fish_id": "fish_crucian", "seed": 123456789},
		"last": {"sequence": 1, "outcome": "caught", "fish_id": "fish_crucian"}}
	var panel: FishingPanel = farm.fishing_panel
	panel.open(farm.session, "farm_pond")
	panel.set_process(false)
	for frame in 12: await get_tree().process_frame
	var metrics := {}
	for stage in ["ready", "casting", "waiting", "hook", "playing", "pulling", "landed"]:
		panel.phase = "playing" if stage == "pulling" else "result" if stage == "landed" else stage
		panel.model = FishingModel.initial(123456789)
		panel.model.fish = 0.68
		panel.model.progress = 0.58
		panel.model.bar = 0.58
		if stage == "landed": panel.model.outcome = "caught"
		panel._gauge.model = panel.model
		panel._gauge.fish_texture = ItemCatalog.texture("fish_crucian")
		panel._status.text = L10n.text("Keep the fish inside the green bar.") if stage in ["playing", "pulling"] else L10n.text("Watch the float. Tap when a fish bites!")
		panel._refresh_button()
		panel.held = stage == "pulling"
		for frame in (8 if stage == "casting" else 25): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join(stage + ".png"))
		var view: FishingPresentation = farm.fishing_view
		metrics[stage] = {"pull": view.pull, "hand": _xyz(view.hand_position), "tip": _xyz(view.rod_tip), "float": _xyz(view.bobber_position),
			"avatar": _rect_bounds(farm.cam.unproject_position(farm.player.position + Vector3.UP)),
			"gauge": _rect(panel._gauge), "action": _rect(panel._primary), "notice": _rect(panel._message_card),
			"viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
			"hud_visible": farm.get_node("HUD/SafeArea/Root").visible}
	panel.phase = "ready"
	farm.session.state.fishing.active = null
	await panel.close()
	await get_tree().process_frame
	metrics.restored = {"hud_visible": farm.get_node("HUD/SafeArea/Root").visible, "panel_visible": panel.visible,
		"animation_playing": farm._rig.get_node("AnimationPlayer").is_playing()}
	FileAccess.open(directory.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify(metrics, "\t"))
	get_tree().quit()

func _xyz(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

func _rect_bounds(point: Vector2) -> Array:
	return [point.x, point.y]
