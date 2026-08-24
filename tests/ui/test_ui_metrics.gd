extends GdUnitTestSuite
## UIMetrics 纯函数边界覆盖。全部无节点依赖。

const VP := Vector2(360, 800)
const WIN := Vector2i(1080, 2400)

func test_safe_margins_converts_physical_insets_to_viewport_units() -> void:
	# 顶部 90px 刘海、底部 60px 手势条，换算系数 360/1080 = 1/3
	var safe := Rect2i(Vector2i(0, 90), Vector2i(1080, 2250))
	var m := UIMetrics.safe_margins(safe, WIN, VP, 16.0)
	assert_float(m.y).is_equal_approx(30.0, 0.01)   # 90/3
	assert_float(m.w).is_equal_approx(20.0, 0.01)   # (2400-2340)/3
	assert_float(m.x).is_equal_approx(16.0, 0.01)   # 实际 0，被 min_margin 抬到 16
	assert_float(m.z).is_equal_approx(16.0, 0.01)

func test_safe_margins_falls_back_to_min_when_no_inset() -> void:
	var safe := Rect2i(Vector2i.ZERO, WIN)
	var m := UIMetrics.safe_margins(safe, WIN, VP, 16.0)
	assert_float(m.x).is_equal_approx(16.0, 0.01)
	assert_float(m.y).is_equal_approx(16.0, 0.01)
	assert_float(m.z).is_equal_approx(16.0, 0.01)
	assert_float(m.w).is_equal_approx(16.0, 0.01)

func test_safe_margins_treats_empty_rect_as_full_window() -> void:
	# 系统未上报安全区时返回空矩形，不能因此算出整屏宽的右/下边距
	var m := UIMetrics.safe_margins(Rect2i(), WIN, VP, 16.0)
	assert_float(m.z).is_equal_approx(16.0, 0.01)
	assert_float(m.w).is_equal_approx(16.0, 0.01)

func test_safe_margins_handles_zero_window() -> void:
	var m := UIMetrics.safe_margins(Rect2i(), Vector2i.ZERO, VP, 16.0)
	assert_float(m.x).is_equal_approx(16.0, 0.01)
	assert_float(m.w).is_equal_approx(16.0, 0.01)

func test_free_ratios_typical_phone() -> void:
	# 296 是历史值，保留只是为了让这条纯函数算术用例的输入/期望值不必跟着改。
	# 出货配置的抽屉实际高度是 312（见 dressing_room.tscn 与 spec 第 4 节），此时
	# ratio ≈ 0.55，而非本用例算出的 0.57。这里仅验证 free_ratios() 的算术是否正确，
	# 不代表当前真实的抽屉高度。
	# 视口 800 高，上下安全区各 24，抽屉 296（历史值）→ 可用 456
	var r := UIMetrics.free_ratios(800.0, 24.0, 24.0, 296.0)
	assert_float(r.x).is_equal_approx(0.57, 0.01)
	assert_float(r.y).is_equal_approx(0.315, 0.01)

func test_free_ratios_returns_zero_when_drawer_eats_screen() -> void:
	assert_vector(UIMetrics.free_ratios(800.0, 24.0, 24.0, 800.0)).is_equal(Vector2.ZERO)
	assert_vector(UIMetrics.free_ratios(0.0, 16.0, 16.0, 296.0)).is_equal(Vector2.ZERO)

func test_frame_distance_uses_height_for_tall_subject() -> void:
	var subject := AABB(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4))
	var d := UIMetrics.frame_distance(subject, 0.45, 0.57, 35.0, 1.12)
	# visible_h = 1.6*1.12/0.57 = 3.144; dist_h = 3.144/2/tan(17.5°) = 4.986
	assert_float(d).is_equal_approx(4.99, 0.05)

func test_frame_distance_switches_to_width_for_wide_subject() -> void:
	# 超宽挂件（路障帽）：宽度约束应压过高度约束
	var wide := AABB(Vector3(-1.5, 0.0, -0.2), Vector3(3.0, 1.6, 0.4))
	var tall := AABB(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4))
	assert_float(UIMetrics.frame_distance(wide, 0.45, 0.57, 35.0, 1.12)) \
		.is_greater(UIMetrics.frame_distance(tall, 0.45, 0.57, 35.0, 1.12))

func test_frame_distance_guards_degenerate_input() -> void:
	var zero := AABB(Vector3.ZERO, Vector3.ZERO)
	assert_float(UIMetrics.frame_distance(zero, 0.45, 0.57, 35.0, 1.12)).is_equal(0.0)
	var subject := AABB(Vector3.ZERO, Vector3(0.4, 1.6, 0.4))
	assert_float(UIMetrics.frame_distance(subject, 0.0, 0.57, 35.0, 1.12)).is_equal(0.0)
	assert_float(UIMetrics.frame_distance(subject, 0.45, 0.0, 35.0, 1.12)).is_equal(0.0)

func test_frame_v_offset_is_negative_to_raise_subject() -> void:
	var subject := AABB(Vector3.ZERO, Vector3(0.4, 1.6, 0.4))
	var v := UIMetrics.frame_v_offset(subject, 0.57, 0.315, 1.12)
	# visible_h = 3.144; v = -3.144*(0.5-0.315) = -0.582
	assert_float(v).is_equal_approx(-0.58, 0.02)
	assert_bool(v < 0.0).is_true()

func test_frame_v_offset_is_zero_when_centered() -> void:
	var subject := AABB(Vector3.ZERO, Vector3(0.4, 1.6, 0.4))
	assert_float(UIMetrics.frame_v_offset(subject, 0.57, 0.5, 1.12)).is_equal_approx(0.0, 0.001)

func test_frame_v_offset_guards_degenerate_input() -> void:
	var zero := AABB(Vector3.ZERO, Vector3.ZERO)
	assert_float(UIMetrics.frame_v_offset(zero, 0.57, 0.315, 1.12)).is_equal(0.0)
	var subject := AABB(Vector3.ZERO, Vector3(0.4, 1.6, 0.4))
	assert_float(UIMetrics.frame_v_offset(subject, 0.0, 0.315, 1.12)).is_equal(0.0)
