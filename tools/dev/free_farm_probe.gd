extends Node
## Native farm art / input evidence with an isolated, in-memory farm; never opens a real account.

var farm: Node3D
var requests: Array = []
var elapsed := 0.0
const OUTPUT := "user://free-farm-proof"

func _ready() -> void:
	Localization.select_language("zh_CN")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if FileAccess.file_exists(OUTPUT.path_join("command")):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUTPUT.path_join("command")))
	var session := FarmSession.new(ApiClient.new("https://free-farm.invalid/v1", func(method, path, _headers, body):
		requests.append({"method": method, "path": path, "body": body})
		return ApiClient.Response.new(true, 409, {"error": "WRONG_STATE"})))
	session.farm_id = "free-farm-art"
	var cells := {}
	var now := int(Time.get_unix_time_from_system() * 1000)
	for row in 2:
		for col in 2:
			for dj in 2:
				for di in 2:
					var cell := Vector2i(26 + col * 2 + di, 30 + row * 3 + dj)
					if not FarmPlot.blueprint_for().mask_has("cultivable", cell): continue
					cells["%d,%d" % [cell.x, cell.y]] = {"state": "growing" if col == 0 else "sown" if col == 1 else "tilled",
						"crop": "R" if col == 0 else "L" if col == 1 else null,
						"watered_at": now - 180000 if col == 0 else null, "ready_at": now - 1 if col == 0 else null}
	session.state = {"cells": cells, "wallet": 180,
		"inventory": {"seeds": {"R": {"bought": 12}, "L": {"bought": 12}, "C": {"bought": 12}, "H": {"bought": 12}}, "produce": {}},
		"clock": {"chapter_index": 3, "field_condition": "sunny"}, "chapters": [],
		"xp": {"total": 0, "first_harvest_crops": ["R"]}}
	farm = preload("res://scenes/farm/farm.tscn").instantiate()
	farm.setup({"blueprint": FarmBlueprint.load_file("res://assets/blueprints/sh_a/r2/farm_blueprint.json"), "session": session})
	add_child(farm)
	if not OS.get_environment("FREE_FARM_CAPTURE").is_empty(): _capture.call_deferred()

func _capture() -> void:
	for frame in 100: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var directory := OS.get_environment("FREE_FARM_CAPTURE")
	DirAccess.make_dir_recursive_absolute(directory)
	get_viewport().get_texture().get_image().save_png(directory.path_join("farm.png"))
	FileAccess.open(directory.path_join("state.json"), FileAccess.WRITE).store_string(JSON.stringify(_state(), "\t"))
	get_tree().quit()

func _rect(control: Control) -> Array:
	var rect := get_viewport().get_screen_transform() * control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]

func _point(world: Vector3) -> Array:
	var point: Vector2 = get_viewport().get_screen_transform() * farm.cam.unproject_position(world)
	return [point.x, point.y]

func _state() -> Dictionary:
	var data := {"requests": requests, "position": [farm.player.position.x, farm.player.position.z],
		"camera_size": farm.cam.size, "cell_m": farm.bp.cell_m,
		"dead_zone": [farm.camera_dead_zone().position.x, farm.camera_dead_zone().position.y, farm.camera_dead_zone().size.x, farm.camera_dead_zone().size.y], "feet": _point(farm.player.position),
		"head": _point(farm.player.position + Vector3.UP * 1.4),
		"wild": _point(farm.bp.cell_to_world(Vector2i(29, 35))),
		"crop": _point(farm.bp.cell_to_world(Vector2i(26, 38))),
		"busy": farm.runner.is_busy(), "queue": farm.runner.pending_count(),
		"hold_enabled": farm.camera_pan.hold_enabled, "brush": farm._brush_cells.size(),
		"seed_strip": _rect(farm.hud._seed_scroll), "seed_visible": farm.hud._seed_scroll.visible,
		"seed_scroll": farm.hud._seed_scroll.scroll_horizontal, "selected_crop": farm.hud.selected_crop,
		"first_seed": _rect(farm.hud._seed_buttons.R),
		"cta": _rect(farm.hud._cta),
		"mine": _point(farm.mine_position()), "well": _point(farm.props.get_node("Well").position),
		"house": _point(farm.props.get_node("House").position), "storage": _point(farm.props.get_node("Storage").position)}
	if "work_mode" in farm:
		data.work_mode = farm.work_mode
		data.mode_button = _rect(farm.hud._mode_toggle)
	return data

func _process(delta: float) -> void:
	elapsed += delta
	if farm == null or elapsed < 0.1: return
	elapsed = 0
	if FileAccess.file_exists(OUTPUT.path_join("command")):
		var command := FileAccess.get_file_as_string(OUTPUT.path_join("command")).strip_edges()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUTPUT.path_join("command")))
		if command == "reset":
			farm.camera_pan.reset()
			farm.mover.stop()
			farm.mover.position = farm.bp.cell_to_world(farm.bp.anchor("spawn"))
			farm.player.position = farm.mover.position
			farm._camera_initialized = false
			farm._update_camera()
		if command == "seeds":
			farm.session.state.cells["27,36"] = {"state": "tilled", "crop": null, "ready_at": null}
			farm._on_server_state(farm.session.state, farm.predictor.version + 1)
	FileAccess.open(OUTPUT.path_join("state.json"), FileAccess.WRITE).store_string(JSON.stringify(_state()))
