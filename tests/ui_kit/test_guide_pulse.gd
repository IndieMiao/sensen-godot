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

## A caller may tune the ring — width, opening opacity, growth, when the fade starts (the mine mouth's main key, 不知火舞
## on #156 / #160); the main stays 2 px from full out to +10, fading all the way, for everyone else.
func test_a_caller_may_tune_the_ring_without_changing_the_main() -> void:
	var t := _target()
	var main := UiGuidePulse.play(t)
	assert_float(main.stroke).is_equal(2.0)
	assert_float(main.grow_px).is_equal(10.0)
	main.progress = 0.5
	assert_float(main.ring_alpha()).is_equal_approx(0.5, 0.0001)     # the main fades from the start
	var key := UiGuidePulse.play(t, Rect2(), UiGuidePulse.Shape.CIRCLE, 16.0, 3.0, 1.0, 12.0, 0.75)
	assert_vector(key.position).is_equal(Vector2(-15, -15))            # 12 px growth + 3 px stroke outside the target
	assert_vector(key.size).is_equal(Vector2(200, 74))
	key.progress = 0.75                                                # 0.3 s into the 0.6 s ease-out
	assert_float(key.ring_alpha()).is_equal_approx(1.0, 0.0001)        # still full
	key.progress = 0.875
	assert_float(key.ring_alpha()).is_equal_approx(0.5, 0.0001)
	key.progress = 1.0
	assert_float(key.ring_alpha()).is_equal_approx(0.0, 0.0001)
