extends GdUnitTestSuite
## Pinch zoom rubber band (user hand test 2026-10-08): past a limit by at most ZOOM_ELASTIC, back once lifted.

const ElasticZoom := preload("res://modules/p0/p0_elastic_zoom.gd")

class ZoomWorld extends Node:
	var zooms: Array = []
	var ends := 0
	func p0_surface() -> String: return "farm"
	func p0_zoom(f: float) -> void: zooms.append(f)
	func p0_zoom_end() -> void: ends += 1

func _settle(z, seconds := 1.0) -> void:
	var t := 0.0
	while t < seconds:
		z.step(1.0 / 60.0)
		t += 1.0 / 60.0

func test_inside_the_range_it_follows_the_fingers_and_stays_put() -> void:
	var z = ElasticZoom.new(0.8, 1.4)
	z.pinch(1.0 / 1.2)   # fingers apart: 20 % closer
	assert_float(z.value).is_equal_approx(1.2, 0.0001)
	z.release()
	assert_bool(z.step(1.0 / 60.0)).is_false()
	assert_float(z.value).is_equal_approx(1.2, 0.0001)

func test_past_a_limit_it_stretches_less_and_less_but_never_beyond_the_band() -> void:
	var z = ElasticZoom.new(0.8, 1.4)
	var last: float = z.value
	for i in 30:
		z.pinch(0.8)   # keep spreading
		assert_float(z.value).is_greater_equal(last)
		last = z.value
	assert_float(z.value).is_greater(1.4)
	assert_float(z.value).is_less(1.4 * exp(ElasticZoom.ZOOM_ELASTIC))   # held short of the full band
	z.pinch(1.0 / 0.8)   # one step back in: it gives way at once (no dead zone past the limit)
	assert_float(z.value).is_less(last)

func test_lifting_springs_back_to_the_limit_within_half_a_second() -> void:
	for limits in [[0.8, 1.4, 0.5], [0.8, 1.4, 2.0]]:
		var z = ElasticZoom.new(limits[0], limits[1])
		for i in 10: z.pinch(limits[2])
		var past: float = z.value
		assert_bool(past < 0.8 or past > 1.4).is_true()
		assert_bool(z.step(1.0 / 60.0)).is_false()   # still held: it waits for the lift
		z.release()
		_settle(z, 0.5)
		var bound := 0.8 if past < 0.8 else 1.4
		assert_float(z.value).is_equal_approx(bound, 0.005)   # visibly home by 0.5 s
		_settle(z, 0.5)
		assert_bool(z.step(1.0 / 60.0)).is_false()   # and at rest soon after
		assert_float(z.value).is_equal_approx(bound, 0.0001)

func test_a_wheel_tick_at_a_limit_bounces_and_a_lost_lift_still_springs_back() -> void:
	var z = ElasticZoom.new(0.5, 1.4, 1.4)
	z.nudge(0.9)   # wheel up at the max
	assert_float(z.value).is_greater(1.4)
	_settle(z, 0.5)
	assert_float(z.value).is_equal_approx(1.4, 0.005)
	z.pinch(0.5)   # held past the max, the pinch_end never comes
	_settle(z, 0.8)
	assert_float(z.value).is_equal_approx(1.4, 0.005)

func test_the_farm_springs_back_after_the_fingers_lift() -> void:
	# Through P0Ui's pad: the pinch goes to p0_zoom, pinch_end to p0_zoom_end (P0Runtime wires both).
	var farm = preload("res://scenes/p0/p0_farm.gd").new()
	farm.set("_pinch", ElasticZoom.new(0.8, 1.4))
	for i in 10: farm.p0_zoom(0.8)
	assert_float(farm._zoom).is_greater(1.4)
	farm.p0_zoom_end()
	for i in 40:
		if farm._pinch.step(1.0 / 60.0): farm._zoom = farm._pinch.value
	assert_float(farm._zoom).is_equal_approx(1.4, 0.005)
	farm.free()

func _touch(pad: Control, index: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = down
	pad._gui_input(e)

func _drag(pad: Control, index: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	pad._gui_input(e)

func test_two_fingers_on_the_scene_pad_reach_the_world_as_zoom_then_zoom_end() -> void:
	# The real path: P0Ui's scene pad (GestureArbiter SCENE mode) → zoom / zoom_end → P0Runtime → the world.
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var world: ZoomWorld = auto_free(ZoomWorld.new())
	rt.attach(world)
	var pad: Control = rt.ui.pad
	_touch(pad, 0, Vector2(100, 300), true)
	_touch(pad, 1, Vector2(140, 300), true)
	_drag(pad, 1, Vector2(180, 300))   # spread 40 → 80: factor 0.5, closer
	_drag(pad, 0, Vector2(60, 300))    # 80 → 120
	assert_int(world.zooms.size()).is_equal(2)
	assert_float(world.zooms[0]).is_equal_approx(0.5, 0.0001)
	assert_int(world.ends).is_equal(0)
	_touch(pad, 1, Vector2(180, 300), false)
	assert_int(world.ends).is_equal(0)   # one finger still down: still pinching
	_touch(pad, 0, Vector2(60, 300), false)
	assert_int(world.ends).is_equal(1)
	rt.detach(world)

