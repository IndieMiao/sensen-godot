extends GdUnitTestSuite

const FARM := preload("res://scenes/farm/farm.tscn")
const BLUEPRINT := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

func after_test() -> void:
	FarmChoice.clear()

func _farm(size: Vector2i, beds := 4, chapter := 3) -> Node:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(auto_free(viewport))
	var blueprint := FarmBlueprint.load_file(BLUEPRINT)
	var cells := {}
	var all_beds := blueprint.beds().duplicate()
	all_beds.append(blueprint.reserved_bed())
	for bed in all_beds:
		for cell in bed.cells:
			cells["%d,%d" % [cell.x, cell.y]] = {"state": "tilled", "crop": null, "ready_at": null}
	var session := FarmSession.new(ApiClient.new("https://camera-test.invalid/v1", FakeTransport.new([]).callable()))
	session.farm_id = "camera-test"
	session.state = {"cells": cells, "beds_unlocked": beds, "wallet": 180,
		"inventory": {"seeds": {"R": {"bought": 12}, "L": {"bought": 12}, "C": {"bought": 12}, "H": {"bought": 12}}, "produce": {}},
		"clock": {"chapter_index": chapter, "field_condition": "sunny"}, "chapters": [],
		"xp": {"total": 0, "first_harvest_crops": ["R"]}}
	var farm := FARM.instantiate()
	farm.setup({"blueprint": blueprint, "session": session})
	viewport.add_child(farm)
	farm.set_process(false)
	var safe := farm.get_node("HUD/SafeArea") as SafeAreaMargin
	safe.apply_margins(Rect2i(0, 40, size.x, size.y - 64), size, size)
	await _layout(farm)
	return farm

func _layout(farm: Node) -> void:
	for frame in 4: await get_tree().process_frame
	farm._update_camera()

func _assert_plots_clear(farm: Node, beds: int) -> void:
	var header := farm.hud.get_node("StatusBacking") as Control
	var bottom := farm.hud._bottom as Control
	var area := Rect2(16, header.get_global_rect().end.y + 4, farm.get_viewport().size.x - 32,
		bottom.global_position.y - header.get_global_rect().end.y - 8)
	var all_beds: Array = farm.bp.beds().duplicate()
	if beds == 4: all_beds.append(farm.bp.reserved_bed())
	for bed in all_beds:
		for cell in bed.cells:
			var world: Vector3 = farm.bp.cell_to_world(cell)
			var tap: Vector2 = farm.cam.unproject_position(world + Vector3(0, 0.15, 0))
			assert_bool(area.encloses(Rect2(tap - Vector2(22, 22), Vector2(44, 44)))).override_failure_message(
				"Plot %s touch target at %s overlaps HUD; clear area %s" % [cell, tap, area]).is_true()
			var hint: Vector2 = farm.cam.unproject_position(world + Vector3(0, 0.7, 0))
			assert_bool(area.encloses(Rect2(hint - Vector2(12, 12), Vector2(24, 24)))).is_true()
			var left: Vector2 = farm.cam.unproject_position(world + Vector3(-0.45, 0.15, 0))
			var right: Vector2 = farm.cam.unproject_position(world + Vector3(0.45, 0.15, 0))
			assert_float(left.distance_to(right)).override_failure_message("Plot %s became too small: %.2f" % [cell, left.distance_to(right)]).is_greater_equal(44)

func test_four_beds_fit_above_two_seed_rows_on_tall_phone() -> void:
	var farm := await _farm(Vector2i(360, 781))
	assert_bool(farm.hud._seed_row.visible).is_true()
	assert_int(farm.hud._seed_buttons.values().filter(func(button): return button.visible).size()).is_equal(4)
	_assert_plots_clear(farm, 4)

func test_four_beds_fit_above_compact_seed_row_on_short_phone_and_receive_touch() -> void:
	var farm := await _farm(Vector2i(360, 640))
	assert_int(farm.hud._seed_row.columns).is_equal(4)
	_assert_plots_clear(farm, 4)
	var cell: Vector2i = farm.bp.reserved_bed().cells[0]
	var point: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(cell) + Vector3(0, 0.15, 0))
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = pressed
		farm.get_viewport().push_input(event, true)
	assert_bool(farm.runner.contains(cell)).override_failure_message("The fourth bed must receive the tap instead of the seed chooser").is_true()

func test_nine_plot_layout_keeps_large_accessible_plots_with_four_seed_choices() -> void:
	var farm := await _farm(Vector2i(360, 781), 3)
	_assert_plots_clear(farm, 3)
	var center: Vector3 = farm.bp.cell_to_world(farm.bp.beds()[1].cells[1])
	var width: float = farm.cam.unproject_position(center + Vector3(0.45, 0.15, 0)).distance_to(
		farm.cam.unproject_position(center + Vector3(-0.45, 0.15, 0)))
	assert_int(roundi(width)).is_greater_equal(50)

func test_hiding_seed_choices_while_working_does_not_move_the_camera() -> void:
	var farm := await _farm(Vector2i(360, 640))
	var before: Transform3D = farm.cam.global_transform
	farm.hud.set_cta_busy(3)
	await _layout(farm)
	assert_bool(farm.hud._seed_row.visible).is_false()
	assert_bool(farm.cam.global_transform.is_equal_approx(before)).is_true()
	farm.hud.set_cta({"action": "sow", "label": "Sow 3 Radish", "enabled": true})
	farm.hud.set_seeds(farm.session.state.inventory, CropInfo.ORDER, true)
	await _layout(farm)
	assert_bool(farm.cam.global_transform.is_equal_approx(before)).is_true()

func test_expansion_and_crop_unlocks_reframe_without_reopening_the_scene() -> void:
	var farm := await _farm(Vector2i(360, 640), 3, 0)
	_assert_plots_clear(farm, 3)
	farm.session.state.beds_unlocked = 4
	farm.session.state.clock.chapter_index = 3
	farm._on_server_state(farm.session.state, 2)
	await _layout(farm)
	_assert_plots_clear(farm, 4)

func test_dragging_from_a_plot_pans_without_starting_work_and_clamps_for_visitors() -> void:
	var farm := await _farm(Vector2i(360, 781))
	var point: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(farm.bp.beds()[1].cells[1]))
	var original: Vector3 = farm.player.position
	for visiting in [false, true]:
		farm.visitor = visiting
		var down := InputEventScreenTouch.new()
		down.position = point
		down.pressed = true
		farm.get_viewport().push_input(down, true)
		var drag := InputEventScreenDrag.new()
		drag.position = point + Vector2(130, 60)
		drag.relative = Vector2(130, 60)
		farm.get_viewport().push_input(drag, true)
		var up := InputEventScreenTouch.new()
		up.position = drag.position
		farm.get_viewport().push_input(up, true)
		assert_float(farm.camera_pan.offset.length()).is_greater(0.5)
		assert_float(farm.camera_pan.offset.length()).is_less_equal(2.15001)
		assert_bool(farm.runner.is_busy()).is_false()
		assert_bool(farm.mover.is_moving()).is_false()
		assert_vector(farm.player.position).is_equal(original)
		assert_bool(farm.camera_pan.active()).is_false()
		for frame in 180: farm.camera_pan.step(1.0 / 60, farm.cam)
		farm._update_camera()
		assert_float(farm.camera_pan.offset.length()).is_less_equal(1.60001)
		var transform: Transform3D = farm.cam.transform
		farm._update_camera()
		assert_bool(farm.cam.transform.is_equal_approx(transform)).is_true()

func test_house_roof_and_spawn_fit_with_the_field_on_short_phone_and_desktop() -> void:
	for size in [Vector2i(360, 640), Vector2i(1280, 720)]:
		var farm := await _farm(size)
		var area: Rect2 = farm._camera_play_area()
		var house := farm.props.get_node("House") as MeshInstance3D
		for vertex in house.mesh.create_convex_shape(true, true).points:
			var point: Vector3 = house.transform * vertex
			assert_bool(area.has_point(farm.cam.unproject_position(point))).is_true()
		var feet: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(farm.bp.anchor("spawn")))
		assert_bool(area.has_point(feet)).is_true()
		_assert_plots_clear(farm, 4)

func test_shadow_clip_volume_covers_visible_ground_and_canopy_through_pan_zoom_and_follow() -> void:
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(1280, 720)]:
		var farm := await _farm(size)
		var camera := farm.cam as Camera3D
		for zoom in [0.71, 1.0, 1.58]:
			farm.camera_pan._log_zoom = log(zoom)
			farm.camera_pan.offset = Vector3(1.5, 0, -1.5)
			farm.player.position = farm.bp.cell_to_world(farm.bp.anchor("spawn")) + Vector3(0, 0, 6)
			farm._update_camera()
			assert_float(camera.far).is_less(60.0)
			assert_float(camera.far - camera.near).is_less(40.0)
			var inverse := camera.global_transform.affine_inverse()
			for point in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), Vector2(size)]:
				for height in [-0.008, 4.0]:
					var hit = Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
					assert_bool(hit is Vector3).is_true()
					if hit is not Vector3: continue
					var depth: float = -(inverse * hit).z
					assert_float(depth).override_failure_message("Near plane clips the canopy at %s, zoom %s" % [size, zoom]).is_greater(camera.near)
					assert_float(depth).override_failure_message("Far plane clips the ground at %s, zoom %s" % [size, zoom]).is_less(camera.far)
