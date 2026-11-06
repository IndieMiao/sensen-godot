extends GdUnitTestSuite
const P0CookTimer := preload("res://scenes/p0/kitchen/p0_cook_timer.gd")
## SGODOT-419 (q(288); 不知火舞's spec v1 419 cd072712 §2): the watch's countdown in the middle — `m:ss` on its plate, a
## 200 × 8 bar 8 px under it filling with the time gone, a dot at each heat ring's time in the ring's result colours.

func _timer() -> P0CookTimer:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	var t := P0CookTimer.new()
	host.add_child(t)
	return t

func test_the_countdown_writes_minutes_and_seconds_left() -> void:
	assert_str(P0CookTimer.clock(65_400)).is_equal("1:05")
	assert_str(P0CookTimer.clock(999)).is_equal("0:00")
	assert_str(P0CookTimer.clock(-5)).is_equal("0:00")

func test_the_plate_is_centred_and_the_bar_sits_under_it_with_a_dot_a_ring() -> void:
	var t := _timer()
	t.total_ms = 20_000
	t.elapsed_ms = 5_000
	t.heat_at = [4_000, 12_000]
	t.results = {0: true}
	t.place(180, 362)
	await await_idle_frame()
	assert_str(t.time_label.text).is_equal("0:15")
	assert_float(t.plate.get_rect().get_center().x).is_equal_approx(180.0, 0.5)
	assert_float(t.plate.get_rect().get_center().y).is_equal_approx(362.0, 0.5)
	assert_float(t.plate.size.y).is_equal(44.0)
	assert_object(t.bar_rect()).is_equal(Rect2(80, 392, 200, 8))   # 不知火舞's x 80–280, y 392–400
	assert_float(t.dot_point(0).x).is_equal_approx(80.0 + 200.0 * 0.2, 0.01)
	assert_float(t.dot_point(1).x).is_equal_approx(80.0 + 200.0 * 0.6, 0.01)
	assert_float(t.dot_point(1).y).is_equal(396.0)
