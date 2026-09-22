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
	var cells := {"27,35": {"state": "tilled", "crop": null, "ready_at": null}}
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

func _place_player_at_screen(farm: Node, point: Vector2) -> void:
	var direction: Vector3 = farm.cam.project_ray_normal(point)
	# Offscreen orthographic rays can begin beyond the ground plane. Extend the
	# same line backwards so the fixture can place the actor in all eight directions.
	var origin: Vector3 = farm.cam.project_ray_origin(point) - direction * 1000
	var hit = Plane(Vector3.UP, 0.7).intersects_ray(origin, direction)
	assert_bool(hit is Vector3).is_true()
	if hit is Vector3: farm.player.position = hit - Vector3.UP * 0.7
	farm._update_camera()

func _assert_plots_clear(farm: Node, beds: int) -> void:
	var header := farm.hud.get_node("StatusBacking") as Control
	var bottom := farm.hud._bottom as Control
	var area := Rect2(16, header.get_global_rect().end.y + 4, farm.get_viewport().size.x - 32,
		bottom.global_position.y - header.get_global_rect().end.y - 8)
	# 田畦退役：检查出生点附近这一小片耕地都落在可点区域内。
	var spawn: Vector2i = farm.bp.anchor("spawn")
	var patch: Array = []
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var c := spawn + Vector2i(di, dj)
			if farm.bp.mask_has("cultivable", c): patch.append(c)
	for bed in [{"cells": patch}]:
		for cell in bed.cells:
			var world: Vector3 = farm.bp.cell_to_world(cell)
			var tap: Vector2 = farm.cam.unproject_position(world + Vector3(0, 0.15, 0))
			assert_bool(area.encloses(Rect2(tap - Vector2(22, 22), Vector2(44, 44)))).override_failure_message(
				"Plot %s touch target at %s overlaps HUD; clear area %s" % [cell, tap, area]).is_true()
			var hint: Vector2 = farm.cam.unproject_position(world + Vector3(0, 0.7, 0))
			assert_bool(area.encloses(Rect2(hint - Vector2(12, 12), Vector2(24, 24)))).is_true()
			# 量**一格**的宽度，并折算到 1080 宽的手机。原先量的是 ±0.45m（0.9m 跨度）
			# 要 ≥44px，那是 1.3m 田畦时代的尺子；0.5m 格下 0.9m 已经跨了近两格，
			# 等价于要求视野收到 4.9m，没有意义。
			var half: float = farm.bp.cell_m * 0.5
			var left: Vector2 = farm.cam.unproject_position(world + Vector3(-half, 0.15, 0))
			var right: Vector2 = farm.cam.unproject_position(world + Vector3(half, 0.15, 0))
			var cell_px := left.distance_to(right) * 1080.0 / float(farm.get_viewport().size.x)
			assert_float(cell_px).override_failure_message(
				"格 %s 折算到 1080 屏只有 %.1f px，低于 40px 的可点下限" % [cell, cell_px]).is_greater_equal(40.0)


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


## 相机框的是玩家附近，不是整个农庄。这条测试原先要求房顶每个顶点都入画——那是 13m
## 场地的契约，那时房子就在出生点旁边。32m 场地上房子在 20m 外，硬要一起入画会把视野
## 拉远一倍，0.5m 的格小到按不准（真机反馈：默认 view 太大）。
## Initial framing keeps the nearby cells readable; later movement does not steer the camera.
func test_initial_camera_centers_the_player_without_framing_the_whole_homestead() -> void:
	for size in [Vector2i(360, 640), Vector2i(1280, 720)]:
		var farm := await _farm(size)
		var area: Rect2 = farm._camera_play_area()
		var feet: Vector2 = farm.cam.unproject_position(farm.player.position)
		assert_bool(area.has_point(feet)).override_failure_message("玩家必须留在可操作区内").is_true()
		# 一格在屏幕上有多宽：量相邻两格投影点的距离，再折算到 1080 宽的手机。
		var spawn: Vector2i = farm.bp.anchor("spawn")
		var near: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(spawn))
		var next: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(spawn + Vector2i(1, 0)))
		var cell_px := near.distance_to(next) * 1080.0 / float(size.x)
		assert_float(cell_px).override_failure_message(
			"一格折算到 1080 屏只有 %.1f px，低于 40px 的可点下限" % cell_px).is_greater(40.0)
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
			# 视野从「框住 12 格田」变成「出生点附近 13m 固定视野」，场地也从 13m 涨到 32m，
			# 裁剪体跟着变大是预期的；守的是它仍然有界、不会随农场铺开无限膨胀。
			assert_float(camera.far).is_less(100.0)
			assert_float(camera.far - camera.near).is_less(110.0)
			var inverse := camera.global_transform.affine_inverse()
			for point in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), Vector2(size)]:
				for height in [-0.008, 4.0]:
					var hit = Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))
					assert_bool(hit is Vector3).is_true()
					if hit is not Vector3: continue
					var depth: float = -(inverse * hit).z
					assert_float(depth).override_failure_message("Near plane clips the canopy at %s, zoom %s" % [size, zoom]).is_greater(camera.near)
					assert_float(depth).override_failure_message("Far plane clips the ground at %s, zoom %s" % [size, zoom]).is_less(camera.far)

func test_default_avatar_scale_is_readable_and_walking_does_not_steer_the_camera() -> void:
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(1280, 720)]:
		var farm := await _farm(size)
		var initial_size: float = farm.cam.size
		var initial_pose: Transform3D = farm.cam.global_transform
		var initial_height := 0.0
		for travel in [Vector3.ZERO, Vector3(0, 0, 14), Vector3(10, 0, 8)]:
			farm.player.position = farm._field_center + travel
			farm._update_camera()
			var feet: Vector2 = farm.cam.unproject_position(farm.player.position)
			var head: Vector2 = farm.cam.unproject_position(farm.player.position + Vector3.UP * 1.4)
			var height := feet.distance_to(head)
			assert_float(height).is_greater(50.0)
			if initial_height == 0: initial_height = height
			assert_float(height).is_equal_approx(initial_height, 0.01)
			assert_float(farm.cam.size).is_equal_approx(initial_size, 0.001)
			assert_that(farm.cam.global_transform).is_equal(initial_pose)

func test_player_can_walk_offscreen_and_only_portrait_action_recenters_smoothly() -> void:
	var farm := await _farm(Vector2i(390, 844))
	assert_bool(farm._focus_button.visible).is_false()
	var original_center: Vector3 = farm._camera_center
	farm.player.position += Vector3(9, 0, 11)
	farm._update_camera(1.0 / 60.0)
	assert_vector(farm._camera_center).is_equal(original_center)
	var viewport := Rect2(Vector2.ZERO, Vector2(390, 844))
	assert_bool(viewport.has_point(farm.cam.unproject_position(farm.player.position))).is_false()
	assert_bool(farm._focus_button.visible).is_true()
	var actor_position: Vector3 = farm.player.position
	var zoom: float = farm.camera_pan.zoom
	var target := actor_position + Vector3.UP * 0.7
	farm._focus_button.pressed.emit()
	assert_vector(farm._camera_center).is_equal(original_center)
	await get_tree().create_timer(0.10).timeout
	assert_float(farm._camera_center.distance_to(target)).is_less(original_center.distance_to(target))
	assert_float(farm._camera_center.distance_to(target)).is_greater(0.001)
	await get_tree().create_timer(0.35).timeout
	assert_vector(farm._camera_center).is_equal_approx(target, Vector3.ONE * 0.001)
	assert_vector(farm.player.position).is_equal(actor_position)
	assert_float(farm.camera_pan.zoom).is_equal(zoom)
	assert_vector(farm.cam.unproject_position(target)).is_equal_approx(viewport.get_center(), Vector2.ONE * 0.1)
	assert_bool(farm._focus_button.visible).is_false()
	assert_bool(farm._focus_button._rendering).is_false()
	assert_object(farm._focus_button._rig).is_null()

func test_offscreen_portrait_tracks_eight_directions_while_camera_and_player_stay_free() -> void:
	var farm := await _farm(Vector2i(390, 844))
	var screen := farm.get_viewport().get_visible_rect() as Rect2
	var camera: Transform3D = farm.cam.global_transform
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT,
			Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_place_player_at_screen(farm, screen.get_center() + direction * 1000)
		assert_bool(farm._focus_button.visible).is_true()
		var rect: Rect2 = farm._focus_button.get_global_rect()
		var area: Rect2 = farm._camera_play_area()
		assert_bool(area.encloses(rect)).is_true()
		assert_vector(rect.size).is_equal(Vector2(56, 56))
		assert_float((rect.get_center() - screen.get_center()).normalized().dot(direction.normalized())).is_greater(0.999)
		assert_float(Vector2.RIGHT.rotated(farm._focus_button._direction_arrow.rotation).dot(direction.normalized())).is_greater(0.999)
		assert_bool(rect.intersects(farm.get_node("HUD/SafeArea/Root/TopBar").get_global_rect())).is_false()
		assert_bool(rect.intersects(farm.hud._bottom.get_global_rect())).is_false()
		assert_that(farm.cam.global_transform).is_equal(camera)
	# The inset HUD area is not the visibility boundary: a player behind the top
	# HUD remains in the actual viewport, so the direction indicator stays hidden.
	_place_player_at_screen(farm, Vector2(screen.get_center().x, 12))
	assert_bool(farm._focus_button.visible).is_false()
	assert_that(farm.cam.global_transform).is_equal(camera)

func test_offscreen_indicator_hides_for_modal_fishing_and_navigation_then_returns() -> void:
	var farm := await _farm(Vector2i(390, 844))
	_place_player_at_screen(farm, Vector2(600, 422))
	var camera: Transform3D = farm.cam.global_transform
	assert_bool(farm._focus_button.visible).is_true()
	farm.hud.show_modal(farm.hud._quick_actions)
	farm._update_focus_indicator()
	assert_bool(farm._focus_button.visible).is_false()
	assert_that(farm.cam.global_transform).is_equal(camera)
	farm.hud.close_modal()
	farm._update_focus_indicator()
	assert_bool(farm._focus_button.visible).is_true()
	farm.fishing_panel.show()
	farm._update_focus_indicator()
	assert_bool(farm._focus_button.visible).is_false()
	farm.fishing_panel.hide()
	var loading := Control.new()
	farm.add_child(loading)
	GameUi.register_modal(loading)
	farm._update_focus_indicator()
	assert_bool(farm._focus_button.visible).is_false()
	loading.queue_free()
	farm._update_focus_indicator()
	assert_bool(farm._focus_button.visible).is_true()
	farm._focus_button.pressed.emit()
	await get_tree().create_timer(0.4).timeout
	assert_bool(farm._focus_button.visible).is_false()
	assert_vector(farm.cam.unproject_position(farm.player.position + Vector3.UP * 0.7)).is_equal_approx(Vector2(195, 422), Vector2.ONE * 0.1)

func test_indicator_rechecks_actual_viewport_after_zoom_and_resize_and_handles_behind_lens() -> void:
	var farm := await _farm(Vector2i(390, 844))
	farm.camera_pan._log_zoom = log(1.4)
	farm._update_camera()
	_place_player_at_screen(farm, Vector2(430, 422))
	assert_bool(farm._focus_button.visible).is_true()
	farm.camera_pan._log_zoom = log(0.8)
	farm._update_camera()
	assert_bool(farm._focus_button.visible).is_false()
	farm.get_viewport().size = Vector2i(844, 390)
	farm.get_node("HUD/SafeArea").apply_margins(Rect2i(32, 16, 780, 358), Vector2i(844, 390), Vector2i(844, 390))
	await _layout(farm)
	_place_player_at_screen(farm, Vector2(1100, 195))
	assert_bool(farm._focus_button.visible).is_true()
	assert_bool(farm._camera_play_area().encloses(farm._focus_button.get_global_rect())).is_true()
	var camera: Transform3D = farm.cam.global_transform
	farm.player.position = farm.cam.global_position + farm.cam.global_basis.z * 4 + farm.cam.global_basis.x * 2 - Vector3.UP * 0.7
	farm._update_focus_indicator()
	assert_bool(farm._focus_button.visible).is_true()
	assert_bool(farm._focus_button.global_position.is_finite()).is_true()
	assert_float(farm._focus_button.get_global_rect().get_center().x).is_greater(422)
	assert_that(farm.cam.global_transform).is_equal(camera)

func test_manual_touch_interrupts_recenter_without_resuming_automatic_follow() -> void:
	var farm := await _farm(Vector2i(390, 844))
	farm._camera_center += Vector3(8, 0, 0)
	farm._update_camera()
	farm.recenter_on_player()
	await get_tree().create_timer(0.08).timeout
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(150, 350)
	farm._unhandled_input(touch)
	var stopped: Vector3 = farm._camera_center
	touch.pressed = false
	touch.canceled = true
	farm._input(touch)
	await get_tree().create_timer(0.4).timeout
	farm.player.position += Vector3(0, 0, 8)
	farm._update_camera(1.0 / 60.0)
	assert_vector(farm._camera_center).is_equal(stopped)
	assert_object(farm._camera_recenter).is_null()

func test_tile_projection_is_one_and_a_half_old_tiles_while_avatar_scale_is_unchanged() -> void:
	var farm := await _farm(Vector2i(390, 844))
	var world: Vector3 = farm.player.position
	var origin: Vector2 = farm.cam.unproject_position(world)
	var old_end: Vector2 = farm.cam.unproject_position(world + Vector3.RIGHT * 0.5)
	var new_end: Vector2 = farm.cam.unproject_position(world + Vector3.RIGHT * farm.bp.cell_m)
	assert_float(origin.distance_to(new_end) / origin.distance_to(old_end)).is_equal_approx(1.5, 0.001)
	assert_vector(farm.player.scale).is_equal(Vector3.ONE)
	assert_float(farm.cam.size).is_equal(6.0)

func test_home_mine_well_and_storage_are_visible_on_the_first_portrait_screen() -> void:
	for size in [Vector2i(360, 640), Vector2i(390, 844)]:
		var farm := await _farm(size)
		var viewport := Rect2(Vector2.ZERO, Vector2(size))
		for key in ["house", "mine", "well", "storage"]:
			var point: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(farm.bp.anchor(key)))
			assert_bool(viewport.grow(-12).has_point(point)).override_failure_message(key + " must be visible from the initial view").is_true()

func test_manual_panning_can_move_avatar_offscreen_in_every_direction() -> void:
	var farm := await _farm(Vector2i(390, 844))
	var center: Vector3 = farm._camera_center
	var viewport: Vector2 = farm.get_viewport().get_visible_rect().size
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		farm.camera_pan.reset()
		farm._camera_center = center
		farm._place_camera(center)
		for stroke in 3:
			farm.camera_pan.drag(farm.cam, viewport * 0.5, viewport * 0.5 + direction * viewport * 0.45)
			farm._update_camera()
		var projected: Vector2 = farm.cam.unproject_position(farm.player.position + Vector3.UP * 0.7)
		assert_bool(Rect2(Vector2.ZERO, viewport).has_point(projected)).is_false()
		assert_bool(farm.camera_pan.free_pan).is_true()

func test_fishing_side_camera_refits_its_clip_volume_for_every_bank() -> void:
	for size in [Vector2i(390, 844), Vector2i(1280, 720)]:
		var viewport := auto_free(SubViewport.new()) as SubViewport
		viewport.size = size
		add_child(viewport)
		var root := Node3D.new()
		viewport.add_child(root)
		var actor := Node3D.new()
		actor.position = Vector3(9, 0, -28)
		root.add_child(actor)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		root.add_child(camera)
		var view := FishingPresentation.new()
		root.add_child(view)
		view.set_process(false)
		view.actor = actor
		view.camera = camera
		for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			view._forward = direction
			view._side = Vector3.UP.cross(direction)
			view._landing = actor.position + direction * 2.0
			camera.near = 1.0
			camera.far = 5.0
			view._frame_camera(1.0)
			var inverse := camera.global_transform.affine_inverse()
			for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), Vector2(size)]:
				for height in [-0.008, 4.0]:
					var hit = Plane(Vector3.UP, height).intersects_ray(camera.project_ray_origin(corner), camera.project_ray_normal(corner))
					assert_bool(hit is Vector3).is_true()
					if hit is Vector3:
						var depth: float = -(inverse * hit).z
						assert_float(depth).is_greater(camera.near)
						assert_float(depth).is_less(camera.far)
		view._finished = true
