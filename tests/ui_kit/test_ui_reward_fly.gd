extends GdUnitTestSuite
## UiRewardFly (C-185 MS-04 / MS-05, C-186): the v3 reward flight — the item icon alone (no disc, trail or ×N), a pop
## and hold at the source, a bézier flight to the target, the landing callback; none to a hidden or missing target.

func _host() -> Control:
	var host := Control.new()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	return host

func _target(host: Control) -> Control:
	var target := Control.new()
	target.position = Vector2(20, 700)
	target.size = Vector2(52, 68)
	host.add_child(target)
	return target

func test_timing_follows_the_tokens() -> void:
	assert_float(UiRewardFly.duration_s()).is_equal_approx((UiTokens.MOTION_DURATION_BASE_MS
		+ UiTokens.MOTION_DURATION_REWARD_HOLD_MS + UiTokens.MOTION_DURATION_FLY_MS) / 1000.0, 0.001)   # 840
	assert_float(UiRewardFly.duration_s(true)).is_equal_approx((UiTokens.MOTION_DURATION_BASE_MS
		+ UiTokens.MOTION_DURATION_FLY_MS) / 1000.0, 0.001)   # a pickup does not hold: 720
	assert_float(UiRewardFly.stagger_s(2)).is_equal_approx(UiTokens.MOTION_STAGGER_MS_REWARD * 2 / 1000.0, 0.001)

func test_a_flight_is_the_icon_alone_and_lands_with_a_callback() -> void:
	var host := _host()
	var target := _target(host)
	var landed := [0]
	var icon := P0Logic.icon("fish_carp")
	var f := UiRewardFly.launch(host, Vector2(200, 300), target, icon, 0.0, func(): landed[0] += 1)
	assert_object(f).is_not_null()
	assert_int(f.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_object(f.icon()).is_same(icon)
	assert_vector(f.size).is_equal(Vector2.ONE * UiRewardFly.ICON)
	assert_int(f.get_child_count()).is_equal(1)   # the icon only: no disc, no count pill
	await get_tree().create_timer(UiRewardFly.duration_s() + 0.2).timeout
	await get_tree().process_frame
	assert_int(landed[0]).is_equal(1)
	assert_bool(is_instance_valid(f)).is_false()

func test_it_holds_at_the_source_before_flying() -> void:
	var host := _host()
	var target := _target(host)
	var f := UiRewardFly.launch(host, Vector2(200, 300), target, null)
	await get_tree().create_timer(UiRewardFly.pop_s() + 0.04).timeout
	assert_vector(f.global_position + f.size * 0.5).is_equal_approx(Vector2(200, 300), Vector2.ONE * 0.5)
	assert_vector(f.scale).is_equal_approx(Vector2.ONE, Vector2.ONE * 0.05)

func test_no_flight_to_a_hidden_or_missing_target() -> void:
	var host := _host()
	var target := _target(host)
	target.hide()
	assert_object(UiRewardFly.launch(host, Vector2.ZERO, target, null)).is_null()
	assert_object(UiRewardFly.launch(host, Vector2.ZERO, null, null)).is_null()

func test_reduced_motion_lands_without_flying() -> void:
	var host := _host()
	var target := _target(host)
	var landed := [0]
	UiMotion.reduced = true
	var f := UiRewardFly.launch(host, Vector2(200, 300), target, null, 0.0, func(): landed[0] += 1)
	await get_tree().process_frame
	await get_tree().process_frame
	UiMotion.reduced = false
	assert_int(landed[0]).is_equal(1)
	assert_bool(is_instance_valid(f)).is_false()
