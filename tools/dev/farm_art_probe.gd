extends Node
## Render the actual farm UI at native viewport sizes with isolated, in-memory state.

const FARM = preload("res://scenes/farm/farm.tscn")
var _failures: Array[String] = []
var _results: Array = []
var _out := "res://output/farm-art-2026-09-10/gameplay"

func _ready() -> void:
	if not OS.get_environment("FARM_ART_CAPTURE").is_empty():
		_out = OS.get_environment("FARM_ART_CAPTURE")
	if not OS.get_environment("FARM_ART_SHADOW_SIZE").is_empty():
		RenderingServer.directional_shadow_atlas_set_size(maxi(256, int(OS.get_environment("FARM_ART_SHADOW_SIZE"))), true)
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(1280, 720)]:
		for beds in [3, 4]: await _check(size, beds)
	_expect(_results.size() == 6, "Not all viewport checks completed")
	var file := FileAccess.open(_out.path_join("checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"results": _results, "failures": _failures}, "\t") + "\n")
	print("FARM_ART_PROBE ", JSON.stringify({"results": _results, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check(size: Vector2i, beds: int) -> void:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var source := FarmBlueprint.load_file("res://assets/blueprints/sh_a/r2/farm_blueprint.json")
	var cells := {}
	var all_beds := source.beds() + [source.reserved_bed()]
	var now := int(Time.get_unix_time_from_system() * 1000)
	for row in all_beds.size():
		for column in all_beds[row].cells.size():
			var cell: Vector2i = all_beds[row].cells[column]
			cells["%d,%d" % [cell.x, cell.y]] = {
				"state": "growing" if column == 0 else "tilled" if row == 0 else "sown",
				"crop": "R" if column == 0 else null if row == 0 else "L",
				"ready_at": now - 1 if column == 0 else null,
				"care_done_at": now - 90000 if column == 0 else null}
	var session := FarmSession.new(ApiClient.new("https://art-probe.invalid/v1", FakeTransport.new([]).callable()))
	session.farm_id = "art-probe"
	# Blank layout_patch_id avoids the production FarmChoice persistence branch.
	session.state = {"cells": cells, "beds_unlocked": beds, "wallet": 180,
		"inventory": {"seeds": {"R": {"bought": 12}, "L": {"bought": 12}, "C": {"bought": 12}, "H": {"bought": 12}}, "produce": {}},
		"clock": {"chapter_index": 3, "field_condition": "sunny"}, "chapters": [],
		"xp": {"total": 0, "first_harvest_crops": ["R"]}}
	var farm := FARM.instantiate()
	farm.setup({"blueprint": source, "session": session})
	viewport.add_child(farm)
	for frame in 120: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var name := "%dx%d-%d-plots" % [size.x, size.y, beds * 3]
	image.save_png(_out.path_join(name + ".png"))
	var variations := {}
	for y in range(image.get_height() / 4, image.get_height() * 3 / 4, 7):
		for x in range(0, image.get_width(), 7): variations[image.get_pixel(x, y).to_html()] = true
	_expect(variations.size() > 200, name + ": blank or flat render")
	var play_area: Rect2 = farm._camera_play_area()
	var active_beds: Array = farm.bp.beds().duplicate()
	if beds == 4: active_beds.append(farm.bp.reserved_bed())
	var min_width := INF
	for bed in active_beds:
		for cell in bed.cells:
			var point: Vector3 = farm.bp.cell_to_world(cell)
			var tap: Vector2 = farm.cam.unproject_position(point + Vector3(0, 0.15, 0))
			_expect(play_area.has_point(tap), name + ": plot overlaps HUD " + str(cell))
			var width: float = farm.cam.unproject_position(point + Vector3(0.45, 0.15, 0)).distance_to(
				farm.cam.unproject_position(point + Vector3(-0.45, 0.15, 0)))
			min_width = minf(min_width, width)
	_expect(min_width >= 44, name + ": plot width below 44 pixels: " + str(min_width))
	var cell: Vector2i = active_beds[-1].cells[0]
	var tap: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(cell) + Vector3(0, 0.15, 0))
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = tap
		event.pressed = pressed
		viewport.push_input(event, true)
	_expect(farm.runner.contains(cell), name + ": visible plot did not receive touch")
	farm._cancel_work()
	var previous: Vector3 = farm.player.position
	farm._on_ground_tapped(farm.bp.cell_to_world(Vector2i(3, 1)))
	for frame in 30: farm._process(1.0 / 60)
	_expect(farm.player.position.distance_to(previous) > 0.2, name + ": player did not move")
	var before: Transform3D = farm.cam.transform
	farm.camera_pan.drag(farm.cam, tap, tap + Vector2(55, 30))
	farm._update_camera()
	_expect(not farm.cam.transform.is_equal_approx(before), name + ": drag did not move camera")
	farm.suspend()
	_expect(not farm.scenery.is_visible_in_tree(), name + ": scenery remained visible while suspended")
	farm.resume()
	_expect(farm.scenery.is_visible_in_tree(), name + ": scenery did not resume")
	_results.append({"viewport": size, "plots": beds * 3, "unique_sample_colors": variations.size(), "min_plot_width_px": min_width,
		"camera_near": farm.cam.near, "camera_far": farm.cam.far})
	viewport.queue_free()
	await get_tree().process_frame

func _expect(ok: bool, detail: String) -> void:
	if not ok: _failures.append(detail)
