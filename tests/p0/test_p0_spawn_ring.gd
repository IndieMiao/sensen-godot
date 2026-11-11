extends GdUnitTestSuite
## q(311) ② (SGODOT-470): the newcomer's places round the spawn — the order the server tries them, the rings' radii, none
## straight ahead or behind, and the screen checks (a person kept 8 px from a rect on the 360-wide screen, on screen).

const SPAWN := Vector3(2, 1, 3)

func test_the_rings_go_right_left_then_behind_then_in_front() -> void:
	var right := Vector3.RIGHT
	var behind := Vector3.FORWARD   # −z: further from a camera looking north
	var r := P0SpawnRing.ring(SPAWN, right, behind)
	assert_int(r.size()).is_equal(12)
	var want := [Vector2(0.75, 0), Vector2(-0.75, 0), Vector2(0.375, -0.6495), Vector2(-0.375, -0.6495),
		Vector2(0.375, 0.6495), Vector2(-0.375, 0.6495)]
	for i in 12:
		var d := r[i] - SPAWN
		var w: Vector2 = want[i % 6] * (2.0 if i >= 6 else 1.0)
		assert_float(d.x).override_failure_message("place %d" % (i + 2)).is_equal_approx(w.x, 0.001)
		assert_float(d.z).override_failure_message("place %d" % (i + 2)).is_equal_approx(w.y, 0.001)
		assert_float(d.y).is_equal(0.0)
		assert_float(absf(d.normalized().dot(behind))).is_less(0.9)   # never straight ahead or behind (cos 30° ≈ 0.87)

func test_places_start_at_the_spawn_and_keep_what_the_room_lets_through() -> void:
	var odd := 0
	var ok := func(p: Vector3) -> bool: return p.x > SPAWN.x   # the room: only the right half
	var p := P0SpawnRing.places(SPAWN, Vector3.RIGHT, Vector3.FORWARD, ok)
	assert_vector(p[0]).is_equal(Vector2(SPAWN.x, SPAWN.z))
	assert_int(p.size()).is_equal(7)   # the spawn, and right, right-behind, right-in-front in each ring
	assert_float(p[1].x - SPAWN.x).is_equal_approx(0.75, 0.001)
	assert_int(p.size()).is_less_equal(P0SpawnRing.MAX)

func test_a_person_keeps_clear_of_rects_and_on_screen() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 800)
	vp.own_world_3d = true
	add_child(auto_free(vp))
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.72
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 10, 10), Vector3.ZERO)
	cam.make_current()
	await get_tree().process_frame
	var me := P0SpawnRing.person_rect(cam, Vector3.ZERO)
	assert_bool(P0SpawnRing.clear_of(cam, Vector3.ZERO, [])).is_true()
	# a key 6 px right of the person: too near; 9 px: clear
	assert_bool(P0SpawnRing.clear_of(cam, Vector3.ZERO, [Rect2(me.end.x + 6, me.position.y, 40, 40)])).is_false()
	assert_bool(P0SpawnRing.clear_of(cam, Vector3.ZERO, [Rect2(me.end.x + 9, me.position.y, 40, 40)])).is_true()
	assert_bool(P0SpawnRing.clear_of(cam, Vector3(50, 0, 0), [])).is_false()   # off screen
	assert_float(me.size.y).is_greater(me.size.x)   # taller than wide
