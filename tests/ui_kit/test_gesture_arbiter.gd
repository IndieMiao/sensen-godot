extends GdUnitTestSuite
## GestureArbiter against the WP7-B F-04 decision tables, one test per table row, driven by synthetic
## InputEventScreenTouch / InputEventScreenDrag with injected timestamps (SGODOT-211).

func _touch(i: int, pos: Vector2, pressed: bool) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = pos
	e.pressed = pressed
	return e

func _drag(i: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = i
	e.position = pos
	return e

func _kinds(out: Array) -> Array:
	return out.map(func(o): return String(o.kind))

# ---------------------------------------------------------------- §1 zones

func test_zones_split_hud_scene_action_bar_and_open_sheet() -> void:
	var layout := {hud_bottom = 106.0, bar_top = 708.0, actions = [Rect2(256, 580, 88, 88), Rect2(278, 524, 44, 44)]}
	assert_int(GestureArbiter.zone_at(Vector2(50, 60), layout)).is_equal(GestureArbiter.Zone.HUD)
	assert_int(GestureArbiter.zone_at(Vector2(80, 400), layout)).is_equal(GestureArbiter.Zone.SCENE)
	assert_int(GestureArbiter.zone_at(Vector2(300, 620), layout)).is_equal(GestureArbiter.Zone.ACTION)
	assert_int(GestureArbiter.zone_at(Vector2(80, 740), layout)).is_equal(GestureArbiter.Zone.BAR)
	layout.sheet = Rect2(0, 254, 360, 546)
	assert_int(GestureArbiter.zone_at(Vector2(80, 400), layout)).is_equal(GestureArbiter.Zone.SHEET)
	assert_int(GestureArbiter.zone_at(Vector2(80, 120), layout)).is_equal(GestureArbiter.Zone.SCRIM)

# ---------------------------------------------------------------- §2 scene band

func test_scene_press_shows_the_joystick_at_the_press_point() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	var out := a.feed(_touch(0, Vector2(100, 400), true), 0)
	assert_array(_kinds(out)).contains_exactly(["joystick_show"])
	assert_vector(out[0].pos).is_equal(Vector2(100, 400))

func test_scene_move_drives_the_joystick_and_keeps_tracking() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	a.feed(_touch(0, Vector2(100, 400), true), 0)
	# Inside the dead zone the vector is zero; past it the stick already steers, even within the tap slop.
	assert_vector(a.feed(_drag(0, Vector2(104, 400)), 10)[0].vector).is_equal(Vector2.ZERO)
	assert_float(a.feed(_drag(0, Vector2(108, 400)), 20)[0].vector.x).is_greater(0.0)
	assert_bool(a.is_joystick()).is_false()
	var out := a.feed(_drag(0, Vector2(100 + a.stick_radius, 400)), 40)
	assert_bool(a.is_joystick()).is_true()
	assert_array(_kinds(out)).contains_exactly(["joystick_move"])
	assert_vector(out[0].vector).is_equal_approx(Vector2(1, 0), Vector2(0.001, 0.001))
	# Far outside the scene band the vector stays clamped to full speed.
	out = a.feed(_drag(0, Vector2(100, 900)), 60)
	assert_float(out[0].vector.length()).is_equal_approx(1.0, 0.001)
	assert_array(_kinds(a.feed(_touch(0, Vector2(100, 900), false), 80))).contains_exactly(["joystick_end"])

func test_scene_short_still_release_is_a_tap() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	a.feed(_touch(0, Vector2(100, 400), true), 0)
	a.feed(_drag(0, Vector2(105, 404)), 100)
	var out := a.feed(_touch(0, Vector2(105, 404), false), 300)
	assert_array(_kinds(out)).contains_exactly(["joystick_end", "tap"])
	assert_bool(out[1].double).is_false()

func test_scene_long_still_press_is_not_a_tap() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	a.feed(_touch(0, Vector2(100, 400), true), 0)
	assert_array(_kinds(a.feed(_touch(0, Vector2(100, 400), false), GestureArbiter.TAP_MAX_MS + 1))).contains_exactly(["joystick_end"])

func test_scene_second_tap_within_window_is_a_double_tap() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	a.feed(_touch(0, Vector2(100, 400), true), 0)
	a.feed(_touch(0, Vector2(100, 400), false), 80)
	a.feed(_touch(0, Vector2(102, 401), true), 200)
	var out := a.feed(_touch(0, Vector2(102, 401), false), 280)
	assert_bool(out[1].double).is_true()
	# The chain ends: a third quick tap is a plain tap again.
	a.feed(_touch(0, Vector2(102, 401), true), 330)
	assert_bool(a.feed(_touch(0, Vector2(102, 401), false), 380)[1].double).is_false()

func test_scene_tap_that_hit_a_facility_cannot_start_a_double_tap() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	a.feed(_touch(0, Vector2(100, 400), true), 0)
	a.feed(_touch(0, Vector2(100, 400), false), 80)
	a.consume_tap()
	a.feed(_touch(0, Vector2(100, 400), true), 200)
	assert_bool(a.feed(_touch(0, Vector2(100, 400), false), 280)[1].double).is_false()

func test_scene_tap_outside_the_window_is_single() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	a.feed(_touch(0, Vector2(100, 400), true), 0)
	a.feed(_touch(0, Vector2(100, 400), false), 80)
	a.feed(_touch(0, Vector2(100, 400), true), 500)
	assert_bool(a.feed(_touch(0, Vector2(100, 400), false), 560)[1].double).is_false()

func test_scene_second_finger_ends_the_joystick_and_pinches_until_both_lift() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	a.feed(_touch(0, Vector2(100, 400), true), 0)
	a.feed(_drag(0, Vector2(140, 400)), 30)
	var out := a.feed(_touch(1, Vector2(240, 400), true), 60)
	assert_array(_kinds(out)).contains_exactly(["joystick_end", "pinch_start"])
	assert_bool(a.is_steering()).is_false()   # _TouchPad stops drawing the stick
	out = a.feed(_drag(1, Vector2(340, 400)), 90)
	assert_array(_kinds(out)).contains_exactly(["pinch"])
	assert_float(out[0].factor).is_equal_approx(100.0 / 200.0, 0.001)
	assert_array(a.feed(_touch(1, Vector2(340, 400), false), 120)).is_empty()
	assert_array(a.feed(_drag(0, Vector2(150, 420)), 140)).is_empty()   # the remaining finger does not walk
	assert_array(_kinds(a.feed(_touch(0, Vector2(150, 420), false), 160))).contains_exactly(["pinch_end"])

func test_stick_vector_has_the_shipped_dead_zone() -> void:
	assert_vector(GestureArbiter.stick_vector(Vector2(5, 0), 43.0)).is_equal(Vector2.ZERO)
	assert_vector(GestureArbiter.stick_vector(Vector2(43, 0), 43.0)).is_equal(Vector2(1, 0))

# ---------------------------------------------------------------- §3 quick bar slot

func test_slot_quick_still_release_is_a_tap() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SLOT)
	a.feed(_touch(0, Vector2(40, 740), true), 0)
	assert_array(a.tick(200)).is_empty()
	assert_array(_kinds(a.feed(_touch(0, Vector2(44, 742), false), 400))).contains_exactly(["tap"])

func test_slot_hold_still_lifts_on_time_alone() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SLOT)
	a.feed(_touch(0, Vector2(40, 740), true), 0)
	assert_array(a.tick(GestureArbiter.LONG_PRESS_MS - 1)).is_empty()
	assert_array(_kinds(a.tick(GestureArbiter.LONG_PRESS_MS))).contains_exactly(["lift"])
	assert_array(a.tick(GestureArbiter.LONG_PRESS_MS + 100)).is_empty()

func test_slot_lift_then_release_in_place_toggles_pin() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SLOT)
	a.feed(_touch(0, Vector2(40, 740), true), 0)
	a.tick(500)
	assert_array(_kinds(a.feed(_touch(0, Vector2(42, 741), false), 700))).contains_exactly(["pin_toggle"])

func test_slot_lift_then_move_drags_and_drops() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SLOT)
	a.feed(_touch(0, Vector2(40, 740), true), 0)
	a.tick(500)
	assert_array(_kinds(a.feed(_drag(0, Vector2(100, 742)), 550))).contains_exactly(["drag_start", "drag_move"])
	assert_array(_kinds(a.feed(_drag(0, Vector2(150, 742)), 600))).contains_exactly(["drag_move"])
	var out := a.feed(_touch(0, Vector2(150, 742), false), 650)
	assert_array(_kinds(out)).contains_exactly(["drop"])
	var bar := Rect2(12, 708, 336, 68)
	var slots := [Rect2(12, 708, 52, 68), Rect2(68, 708, 52, 68), Rect2(124, 708, 52, 68)]
	assert_dict(GestureArbiter.drop_on_bar(out[0].pos, bar, slots)).is_equal({kind = &"swap", index = 2})

func test_slot_drop_far_above_the_bar_removes_and_near_it_cancels() -> void:
	var bar := Rect2(12, 708, 336, 68)
	assert_str(String(GestureArbiter.drop_on_bar(Vector2(100, 708 - 41), bar, []).kind)).is_equal("remove")
	assert_str(String(GestureArbiter.drop_on_bar(Vector2(100, 708 - 20), bar, []).kind)).is_equal("cancel")

func test_slot_upward_swipe_before_lift_opens_the_bag() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SLOT)
	a.feed(_touch(0, Vector2(40, 740), true), 0)
	assert_array(a.feed(_drag(0, Vector2(42, 725)), 50)).is_empty()
	assert_array(_kinds(a.feed(_drag(0, Vector2(44, 712)), 90))).contains_exactly(["swipe_up"])
	assert_array(a.feed(_touch(0, Vector2(44, 712), false), 120)).is_empty()

func test_slot_diagonal_move_is_neither_swipe_nor_tap() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.SLOT)
	a.feed(_touch(0, Vector2(40, 740), true), 0)
	assert_array(a.feed(_drag(0, Vector2(80, 710)), 60)).is_empty()
	assert_array(a.tick(600)).is_empty()   # moved: no lift either
	assert_array(_kinds(a.feed(_touch(0, Vector2(80, 710), false), 700))).contains_exactly(["cancel"])

# ---------------------------------------------------------------- §4 bag grid and drawer

func test_cell_vertical_drag_before_lift_belongs_to_the_scroll() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.CELL)
	a.feed(_touch(0, Vector2(40, 500), true), 0)
	assert_array(_kinds(a.feed(_drag(0, Vector2(40, 470)), 60))).contains_exactly(["cancel"])
	assert_array(a.tick(600)).is_empty()
	assert_array(a.feed(_touch(0, Vector2(40, 470), false), 700)).is_empty()

func test_cell_tap_shows_details() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.CELL)
	a.feed(_touch(0, Vector2(40, 500), true), 0)
	assert_array(_kinds(a.feed(_touch(0, Vector2(40, 500), false), 150))).contains_exactly(["tap"])

func test_cell_long_press_in_place_is_a_quick_pin() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.CELL)
	a.feed(_touch(0, Vector2(40, 500), true), 0)
	assert_array(_kinds(a.tick(450))).contains_exactly(["lift"])
	assert_array(_kinds(a.feed(_touch(0, Vector2(41, 500), false), 600))).contains_exactly(["long_press"])

func test_cell_lift_then_move_drags_toward_the_quick_bar_row() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.CELL)
	a.feed(_touch(0, Vector2(40, 500), true), 0)
	a.tick(450)
	assert_array(_kinds(a.feed(_drag(0, Vector2(40, 300)), 520))).contains_exactly(["drag_start", "drag_move"])
	assert_array(_kinds(a.feed(_touch(0, Vector2(40, 300), false), 600))).contains_exactly(["drop"])

func test_autoscroll_near_grid_edges() -> void:
	var area := Rect2(0, 300, 360, 400)
	assert_float(GestureArbiter.autoscroll(500, area)).is_equal(0.0)
	assert_float(GestureArbiter.autoscroll(300, area)).is_equal(-1.0)
	assert_float(GestureArbiter.autoscroll(700 - 12, area)).is_equal_approx(0.5, 0.001)

func test_handle_drag_down_far_enough_closes() -> void:
	var a := GestureArbiter.new(GestureArbiter.Mode.HANDLE)
	a.feed(_touch(0, Vector2(180, 260), true), 0)
	a.feed(_drag(0, Vector2(180, 300)), 200)
	assert_array(_kinds(a.feed(_touch(0, Vector2(180, 310), false), 400))).contains_exactly(["close"])

func test_handle_short_slow_drag_cancels_and_fast_fling_closes() -> void:
	var slow := GestureArbiter.new(GestureArbiter.Mode.HANDLE)
	slow.feed(_touch(0, Vector2(180, 260), true), 0)
	slow.feed(_drag(0, Vector2(180, 280)), 400)
	assert_array(_kinds(slow.feed(_touch(0, Vector2(180, 280), false), 500))).contains_exactly(["cancel"])
	var fast := GestureArbiter.new(GestureArbiter.Mode.HANDLE)
	fast.feed(_touch(0, Vector2(180, 260), true), 0)
	fast.feed(_drag(0, Vector2(180, 290)), 30)
	assert_array(_kinds(fast.feed(_touch(0, Vector2(180, 290), false), 40))).contains_exactly(["close"])

# ---------------------------------------------------------------- desktop

func test_left_mouse_button_acts_as_the_first_finger_without_a_touchscreen() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var a := GestureArbiter.new(GestureArbiter.Mode.SCENE)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(100, 400)
	assert_array(_kinds(a.feed(down, 0))).contains_exactly(["joystick_show"])
	var up := down.duplicate()
	up.pressed = false
	assert_array(_kinds(a.feed(up, 100))).contains_exactly(["joystick_end", "tap"])
