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

func test_other_finger_release_does_not_zero_vector() -> void:
	var j = auto_free(TouchStick.new())
	j.size = Vector2(140, 140)
	add_child(j)
	var got: Array = []
	j.changed.connect(func(v): got.append(v))
	# Finger 0 down and drag
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
	# Finger 1 release (should NOT affect vector)
	var other_up := InputEventScreenTouch.new()
	other_up.pressed = false
	other_up.index = 1
	other_up.position = Vector2(70, 130)
	j._gui_input(other_up)
	# Vector should still be non-zero
	assert_float(j.vector.x).is_equal_approx(1.0, 1e-6)

func test_hiding_mid_drag_releases_and_emits_zero() -> void:
	var j = auto_free(TouchStick.new())
	j.size = Vector2(140, 140)
	add_child(j)
	var got: Array = []
	j.changed.connect(func(v): got.append(v))
	# Finger down and drag to non-zero
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
	# Hide the control mid-drag
	j.visible = false
	# Vector should be reset to zero
	assert_that(j.vector).is_equal(Vector2.ZERO)
	# A zero emission should have been sent
	assert_bool(got.size() > 0 and got[got.size() - 1] == Vector2.ZERO).is_true()
	# Show it again and verify the index slot is freed (new press with same index is accepted)
	j.visible = true
	var new_down := InputEventScreenTouch.new()
	new_down.pressed = true
	new_down.index = 0
	new_down.position = Vector2(70, 70)
	j._gui_input(new_down)
	# If the index slot was not freed, this press would be ignored and _touch_index would still be -1
	# If it was freed, _touch_index should now be 0
	assert_int(j._touch_index).is_equal(0)

func test_exit_tree_mid_drag_resets() -> void:
	var j = auto_free(TouchStick.new())
	j.size = Vector2(140, 140)
	add_child(j)
	var got: Array = []
	j.changed.connect(func(v): got.append(v))
	# Finger down and drag
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
	# Remove from scene tree mid-drag
	remove_child(j)
	# Vector should be reset to zero
	assert_that(j.vector).is_equal(Vector2.ZERO)
	# Add back so orphan cleanup works
	add_child(j)
