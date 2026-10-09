extends GdUnitTestSuite
## GuidePulse 1407:113987 (SGODOT-232 U6, 不知火舞 on 232): 2 px color/primary ring, edge → +10 px, 100 → 0 %,
## 600 ms ease-out, once, no touches, frame = target + 4 px each side.

func _target() -> Control:
	var c := Control.new()
	c.size = Vector2(170, 44)
	add_child(auto_free(c))
	return c

func test_plays_once_takes_no_touches_and_frees_itself() -> void:
	var t := _target()
	var p := UiGuidePulse.play(t)
	assert_int(p.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_vector(p.frame_size()).is_equal(Vector2(178, 52))           # the main's Shape=Pill frame for a 170 × 44 target
	assert_float(p.progress).is_equal(0.0)
	await await_millis(UiTokens.MOTION_NEW_UNLOCK_FLASH_MS / 2)
	assert_float(p.progress).is_greater(0.5)                            # ease-out: past halfway at half time
	await await_millis(UiTokens.MOTION_NEW_UNLOCK_FLASH_MS / 2 + 120)
	assert_bool(is_instance_valid(p)).is_false()

func test_the_ring_has_room_to_grow_around_the_given_rect() -> void:
	var t := _target()
	var p := UiGuidePulse.play(t, Rect2(Vector2(0, 6), Vector2(170, 32)), UiGuidePulse.Shape.PILL)
	assert_vector(p.position).is_equal(Vector2(-12, -6))               # 10 px growth + 2 px stroke outside the rect
	assert_vector(p.size).is_equal(Vector2(194, 56))

## A caller may thicken the ring and lower its opening opacity (the mine mouth's main key, 不知火舞 on #156); the main
## stays 2 px from full for everyone else.
func test_a_caller_may_thicken_the_ring_without_changing_the_main() -> void:
	var t := _target()
	var main := UiGuidePulse.play(t)
	assert_float(main.stroke).is_equal(2.0)
	assert_float(main.start_alpha).is_equal(1.0)
	var key := UiGuidePulse.play(t, Rect2(), UiGuidePulse.Shape.CIRCLE, 16.0, 3.0, 0.8)
	assert_float(key.stroke).is_equal(3.0)
	assert_float(key.start_alpha).is_equal(0.8)
	assert_vector(key.position).is_equal(Vector2(-13, -13))            # 10 px growth + 3 px stroke outside the target
	assert_vector(key.size).is_equal(Vector2(196, 70))
