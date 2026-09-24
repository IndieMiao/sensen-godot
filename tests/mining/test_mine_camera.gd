extends GdUnitTestSuite

const Mine = preload("res://scenes/mine/mine.gd")
const Camera = preload("res://modules/farm/farm_camera.gd")
const Art = preload("res://modules/mining/mine_art.gd")

func _mine(size := Vector2i(390,844)) -> Node3D:
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = size
	viewport.own_world_3d = true
	add_child(viewport)
	var session := FarmSession.new(ApiClient.new("https://camera.invalid",FakeTransport.new([]).callable()))
	session.farm_id = "close-mine-camera"
	session.state = {"inventory":{"produce":{},"dishes":{}},"journey":{"materials":{}},
		"mine":{"floor":1,"run":0,"deepest_floor":1,"broken":{},"cleared_floors":[],"elevator_unlocked":false}}
	var mine := Mine.new()
	mine.setup({"session":session})
	viewport.add_child(mine)
	for frame in 4: await get_tree().process_frame
	mine.set_process(false)
	mine._update_camera()
	return mine

func _drag(mine: Node3D, from: Vector2, to: Vector2) -> void:
	var press := InputEventScreenTouch.new()
	press.position = from
	press.pressed = true
	mine._unhandled_input(press)
	var drag := InputEventScreenDrag.new()
	drag.position = to
	mine._input(drag)
	press.pressed = false
	press.position = to
	mine._input(press)
	mine.camera_pan.velocity = Vector3.ZERO
	mine._update_camera()

func test_initial_view_matches_farm_scale_and_allows_chamber_edges_offscreen() -> void:
	for size in [Vector2i(360,640),Vector2i(390,844),Vector2i(960,720)]:
		var mine := await _mine(size)
		assert_float(mine.cam.size).is_equal_approx(Camera.close_view_size(size),0.001)
		var head: Vector2 = mine.cam.unproject_position(mine.player.position+Vector3.UP*1.4)
		var feet: Vector2 = mine.cam.unproject_position(mine.player.position)
		assert_float(head.distance_to(feet)).is_greater(50)
		assert_bool(mine.world_area().has_point(feet)).is_true()
		var outside := 0
		for corner in 8:
			if not Rect2(Vector2.ZERO,Vector2(size)).has_point(mine.cam.unproject_position(Art.VIEW_BOUNDS.get_endpoint(corner))): outside += 1
		assert_int(outside).is_greater(0)
		assert_bool(mine._focus_button.visible).is_false()

func test_drag_stays_released_and_neither_walking_nor_mining_refresh_reframes() -> void:
	var mine := await _mine()
	var original: Vector3 = mine._camera_center
	var center: Vector2 = mine.world_area().get_center()
	_drag(mine,center,center+Vector2(230,110))
	var settled: Vector3 = mine._camera_center
	assert_float(settled.distance_to(original)).is_greater(3)
	for frame in 120:
		mine.camera_pan.step(1.0/60,mine.cam)
		mine._update_camera()
	assert_vector(mine._camera_center).is_equal_approx(settled,Vector3.ONE*0.001)
	mine.mover.position += Vector3(0.5,0,-2)
	mine.player.position = mine.mover.position
	mine.session.state.mine.broken = {"1":["rock_1"]}
	mine._refresh()
	await get_tree().process_frame
	mine._update_camera()
	assert_vector(mine._camera_center).is_equal_approx(settled,Vector3.ONE*0.001)

func test_two_finger_zoom_keeps_ground_anchor_and_does_not_click() -> void:
	var mine := await _mine()
	var focus: Vector2 = mine.world_area().get_center()+Vector2(22,24)
	var ground: Vector3 = mine.camera_pan._ground(mine.cam,focus)
	var old_size: float = mine.cam.size
	mine.camera_pan.begin(0,focus-Vector2(35,0))
	mine.camera_pan.begin(1,focus+Vector2(35,0))
	mine.camera_pan.motion(0,focus-Vector2(43,0),mine.cam)
	mine._update_camera()
	mine.camera_pan.motion(1,focus+Vector2(43,0),mine.cam)
	mine._update_camera()
	mine.camera_pan.end(0,focus-Vector2(43,0))
	mine.camera_pan.end(1,focus+Vector2(43,0))
	mine.camera_pan.velocity = Vector3.ZERO
	mine.camera_pan.zoom_velocity = 0
	mine._update_camera()
	assert_float(mine.cam.size).is_less(old_size)
	assert_vector(mine.cam.unproject_position(ground)).is_equal_approx(focus,Vector2.ONE*0.1)
	assert_str(mine.pending_target).is_empty()
	assert_str(mine._dig_target).is_empty()

func test_offscreen_portrait_recenters_smoothly_without_moving_player_or_zoom() -> void:
	var mine := await _mine()
	var actor: Vector3 = mine.player.position
	mine._camera_center += Vector3(8,0,0)
	mine._update_camera()
	assert_bool(mine._focus_button.visible).is_true()
	assert_bool(mine.world_area().encloses(mine._focus_button.get_global_rect())).is_true()
	var before: Vector3 = mine._camera_center
	var zoom: float = mine.camera_pan.zoom
	mine._focus_button.pressed.emit()
	assert_vector(mine._camera_center).is_equal(before)
	await get_tree().create_timer(0.1).timeout
	assert_float(mine._camera_center.distance_to(actor)).is_less(before.distance_to(actor))
	await get_tree().create_timer(0.3).timeout
	assert_vector(mine._camera_center).is_equal_approx(actor+Vector3.UP*0.7,Vector3.ONE*0.001)
	assert_vector(mine.player.position).is_equal(actor)
	assert_float(mine.camera_pan.zoom).is_equal(zoom)
	assert_bool(mine._focus_button.visible).is_false()
	assert_object(mine._focus_button._rig).is_null()

func test_manual_pan_interrupts_recenter_and_modal_suppresses_portrait() -> void:
	var mine := await _mine()
	mine._camera_center += Vector3(8,0,0)
	mine._update_camera()
	mine.recenter_on_player()
	await get_tree().create_timer(0.07).timeout
	var center: Vector2 = mine.world_area().get_center()
	_drag(mine,center,center+Vector2(-25,0))
	var stopped: Vector3 = mine._camera_center
	await get_tree().create_timer(0.4).timeout
	assert_vector(mine._camera_center).is_equal_approx(stopped,Vector3.ONE*0.001)
	assert_object(mine._camera_recenter).is_null()
	mine._camera_center += Vector3(8,0,0)
	mine._update_camera()
	assert_bool(mine._focus_button.visible).is_true()
	mine._open_bag()
	assert_bool(mine._focus_button.visible).is_false()
	mine.bag_sheet.close()
	mine._update_camera()
	assert_bool(mine._focus_button.visible).is_true()

func test_new_floor_frames_arrival_and_suspend_keeps_existing_view() -> void:
	var mine := await _mine()
	mine._camera_center += Vector3(7,0,2)
	mine._update_camera()
	var before: Vector3 = mine._camera_center
	mine.suspend()
	mine.resume()
	mine._update_camera()
	assert_vector(mine._camera_center).is_equal(before)
	mine.session.state.mine.floor = 2
	mine._refresh()
	await get_tree().process_frame
	mine._update_camera()
	assert_vector(mine._camera_center).is_equal_approx(mine.player.position+Vector3.UP*0.7,Vector3.ONE*0.001)
	assert_bool(mine._focus_button.visible).is_false()
