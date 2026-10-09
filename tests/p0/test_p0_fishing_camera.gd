extends GdUnitTestSuite
## The P0 fishing camera (用户 via 奕星, 不知火舞 on 231, 2026-10-09): no side close-up — the walking camera (43°, farm
## size, yaw 0) only pans to frame the player and the float between the bite notice and the guide line over the key;
## the float 1.6× with an ink ring drawn over everything and a 1.5 px ink line; the reel gauge on the side away from
## the player, clear of the screen edges and the player's box. Maths and a 360 × 800 SubViewport, so headless runs
## the same.

const P0Pond := preload("res://scenes/p0/p0_pond.gd")
const PHONE := Vector2(360, 800)
const FISH_BAND := Rect2(0, 260, 360, 345)   # bite notice bottom … guide line top at 360 × 800
const ROWS := Vector2(278, 371)              # the gauge's top edge range there (FishingPanel._gauge_rows)
const GAUGE := Vector2(64, 210)

func test_the_gauge_takes_the_side_away_from_the_player() -> void:
	var body := Rect2(120, 380, 40, 90)
	assert_int(P0FishingPanel.gauge_side(220, body, 360)).is_equal(1)    # cast east: player left, gauge right
	assert_int(P0FishingPanel.gauge_side(60, body, 360)).is_equal(-1)    # cast west
	assert_int(P0FishingPanel.gauge_side(140, body, 360)).is_equal(1)    # north–south: the side with more room
	assert_int(P0FishingPanel.gauge_side(140, Rect2(100, 380, 200, 90), 360)).is_equal(1)
	assert_int(P0FishingPanel.gauge_side(250, Rect2(200, 380, 80, 90), 360)).is_equal(-1)

func test_the_gauge_keeps_its_gap_the_edges_and_clear_of_the_player() -> void:
	for c in [[Vector2(220, 420), Rect2(120, 370, 48, 100)], [Vector2(140, 420), Rect2(210, 370, 48, 100)],
			[Vector2(180, 400), Rect2(156, 392, 48, 90)], [Vector2(330, 420), Rect2(220, 370, 48, 100)],
			[Vector2(100, 420), Rect2(140, 370, 48, 100)]]:   # the framing keeps ≥ 100 px on the gauge's side
		var anchor: Vector2 = c[0]
		var body: Rect2 = c[1]
		var at := P0FishingPanel.gauge_spot(anchor, body, GAUGE, PHONE.x, ROWS)
		var r := Rect2(at, GAUGE)
		assert_bool(r.intersects(body)).is_false()
		assert_float(r.position.x).is_greater_equal(P0FishingPanel.GAUGE_EDGE)
		assert_float(r.end.x).is_less_equal(PHONE.x - P0FishingPanel.GAUGE_EDGE)
		assert_float(at.y).is_between(ROWS.x, ROWS.y)
	# beside the float with room: exactly the old 28 px gap, on the far side from the player
	var east := P0FishingPanel.gauge_spot(Vector2(220, 420), Rect2(120, 370, 48, 100), GAUGE, PHONE.x, ROWS)
	assert_float(east.x).is_equal(220.0 + P0FishingPanel.GAUGE_GAP)
	var west := P0FishingPanel.gauge_spot(Vector2(140, 420), Rect2(210, 370, 48, 100), GAUGE, PHONE.x, ROWS)
	assert_float(west.x + GAUGE.x).is_equal(140.0 - P0FishingPanel.GAUGE_GAP)
	# north–south with the roomier side just touching the player: beside on the other side, not above the player, so
	# the gauge stays put when the bite notice folds away mid-reel (rows from 62 then)
	var body := Rect2(158, 387, 48, 86)
	for rows in [ROWS, Vector2(62, 371)]:
		var ns := P0FishingPanel.gauge_spot(Vector2(177.4, 400), body, GAUGE, PHONE.x, rows)
		assert_float(ns.x + GAUGE.x).is_equal_approx(177.4 - P0FishingPanel.GAUGE_GAP, 0.001)
	var edge := P0FishingPanel.gauge_spot(Vector2(100, 420), Rect2(140, 370, 48, 100), GAUGE, PHONE.x, ROWS)
	assert_float(edge.x).is_equal(P0FishingPanel.GAUGE_EDGE)   # 100 − 28 − 64 = 8: flush with the edge margin

## Through a real camera: the midpoint lands in the middle of the fishing band, the float keeps 100 px on the gauge's
## side, and the camera stays the walking camera.
func test_fishing_pans_the_walking_camera_to_frame_player_and_float() -> void:
	var cam := _phone_camera()
	var player := Vector3(6, 0.1, -2.6)
	for landing in [Vector3(6, 0.11, -4.4), Vector3(9.9, 0.11, -3.5), Vector3(2.1, 0.11, -3.5), Vector3(7, 0.11, -6.5)]:
		var focus := P0Pond.fishing_focus(player, landing, player.y, cam.size, PHONE, FISH_BAND)
		P0Pond.place(cam, focus)
		var f := cam.unproject_position(landing)
		var p := cam.unproject_position(player)
		var mid := cam.unproject_position((player + landing) * 0.5)
		assert_float(mid.y).is_equal_approx(FISH_BAND.get_center().y, 0.01)
		assert_bool(FISH_BAND.has_point(f) and FISH_BAND.has_point(p)).is_true()
		var body := Rect2(p.x - 16, p.y - 70, 32, 70)
		if P0FishingPanel.gauge_side(f.x, body, PHONE.x) > 0: assert_float(f.x).is_less_equal(PHONE.x - P0Pond.FLOAT_ROOM + 0.01)
		else: assert_float(f.x).is_greater_equal(P0Pond.FLOAT_ROOM - 0.01)
	var fwd := -cam.global_basis.z
	assert_float(rad_to_deg(asin(-fwd.y))).is_equal_approx(43.0, 0.01)
	assert_float(cam.size).is_equal_approx(6.72, 0.001)

## The pond's presentation keeps the camera (no close-up, nothing to restore) and draws the float 1.6× with a ring and a
## 1.5 px line; Journey's defaults stay the side close-up and the 12 mm cream line.
func test_the_presentation_leaves_the_camera_and_reads_at_the_walking_scale() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	add_child(auto_free(vp))
	var root := Node3D.new()
	vp.add_child(root)
	var actor := Node3D.new()
	actor.position = FishingModel.stand("farm_pond")
	root.add_child(actor)
	var rig := preload("res://assets/avatar/base/base_rig.tscn").instantiate() as AvatarRig
	actor.add_child(rig)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = P0Pond.view_size(PHONE, 1.0)
	root.add_child(cam)
	cam.make_current()
	P0Pond.place(cam, actor.position)
	var before := cam.global_transform
	var panel := FishingPanel.new()
	root.add_child(panel)
	var session := FarmSession.new(null)
	session.farm_id = "camera-test"
	panel.open(session, "farm_pond")
	panel.set_process(false)
	panel.phase = "waiting"
	var view := FishingPresentation.new()
	view.close_up = false
	view.float_scale = P0Pond.FLOAT_SCALE
	view.line_px = P0Pond.LINE_PX
	view.line_color = P0Pond.LINE_INK
	root.add_child(view)
	view.configure(panel, actor, rig, cam, [])
	view.set_process(false)
	view._cast_age = 10
	for i in 5: view.step(0.05)
	assert_that(cam.global_transform).is_equal(before)
	assert_float(cam.size).is_equal_approx(6.72, 0.001)
	assert_vector(view._bobber.scale).is_equal_approx(Vector3.ONE * 1.6, Vector3.ONE * 0.0001)
	assert_object(view._ring).is_null()   # no ink ring: the user read it as a black ring (SGODOT-263 ①)
	assert_float(view._line_half() * 2.0 * PHONE.x / cam.size).is_equal_approx(1.5, 0.0001)   # 1.5 px on screen
	assert_that(view._line_material.albedo_color).is_equal(P0Pond.LINE_INK)
	view.finish()
	assert_that(cam.global_transform).is_equal(before)
	var journey := FishingPresentation.new()
	assert_bool(journey.close_up).is_true()
	assert_float(journey.float_scale).is_equal(1.0)
	assert_bool(journey.float_ring).is_false()
	assert_float(journey.line_px).is_equal(0.0)
	journey.free()
	await get_tree().process_frame

func _phone_camera() -> Camera3D:
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	add_child(auto_free(vp))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = P0Pond.view_size(PHONE, 1.0)
	vp.add_child(cam)
	cam.make_current()
	return cam
