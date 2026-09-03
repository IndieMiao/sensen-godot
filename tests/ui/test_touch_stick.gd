extends GdUnitTestSuite

func test_knob_vector_dead_zone_and_clamp() -> void:
	var c := Vector2(100, 100)
	assert_that(TouchStick.knob_vector(c, Vector2(104, 100), 56.0, 0.15)).is_equal(Vector2.ZERO)
	var v = TouchStick.knob_vector(c, Vector2(100, 400), 56.0, 0.15)
	assert_float(v.length()).is_equal_approx(1.0, 1e-6)
	assert_float(v.y).is_equal_approx(1.0, 1e-6)
	var half = TouchStick.knob_vector(c, Vector2(128, 100), 56.0, 0.15)
	assert_float(half.x).is_equal_approx(0.5, 1e-6)

func test_touch_sequence_updates_vector_and_emits() -> void:
	var j = auto_free(TouchStick.new())
	j.size = Vector2(140, 140)
	add_child(j)
	var got: Array = []
	j.changed.connect(func(v): got.append(v))
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.index = 0
	down.position = Vector2(70, 70)
	j._gui_input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(126, 70)
	j._gui_input(drag)
	assert_float(j.vector.x).is_equal_approx(1.0, 1e-6)
	var other := InputEventScreenDrag.new()
	other.index = 1
	other.position = Vector2(70, 130)
	j._gui_input(other) # 另一根手指不影响
	assert_float(j.vector.x).is_equal_approx(1.0, 1e-6)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.index = 0
	up.position = Vector2(126, 70)
	j._gui_input(up)
	assert_that(j.vector).is_equal(Vector2.ZERO)
	assert_bool(got.size() >= 2).is_true()
