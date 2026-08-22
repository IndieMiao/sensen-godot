extends GdUnitTestSuite
## SafeAreaMargin 是薄胶水：验证它把算出的边距真正写进 theme constant override 并广播信号。

func _make() -> SafeAreaMargin:
	var c := SafeAreaMargin.new()
	c.min_margin = 16.0
	add_child(auto_free(c))
	return c

func test_apply_margins_writes_theme_constant_overrides() -> void:
	var c := _make()
	c.apply_margins(Rect2i(Vector2i(0, 90), Vector2i(1080, 2250)), Vector2i(1080, 2400), Vector2(360, 800))
	assert_int(c.get_theme_constant(&"margin_top")).is_equal(30)
	assert_int(c.get_theme_constant(&"margin_bottom")).is_equal(20)
	assert_int(c.get_theme_constant(&"margin_left")).is_equal(16)
	assert_int(c.get_theme_constant(&"margin_right")).is_equal(16)

func test_apply_margins_emits_signal() -> void:
	var c := _make()
	var got: Array[Vector4] = []
	c.margins_applied.connect(func(m: Vector4): got.append(m))
	c.apply_margins(Rect2i(Vector2i.ZERO, Vector2i(1080, 2400)), Vector2i(1080, 2400), Vector2(360, 800))
	assert_int(got.size()).is_equal(1)
	assert_float(got[0].y).is_equal_approx(16.0, 0.01)

func test_apply_margins_never_goes_below_min() -> void:
	var c := _make()
	c.apply_margins(Rect2i(), Vector2i(1080, 2400), Vector2(360, 800))
	assert_int(c.get_theme_constant(&"margin_left")).is_equal(16)
	assert_int(c.get_theme_constant(&"margin_right")).is_equal(16)
	assert_int(c.get_theme_constant(&"margin_top")).is_equal(16)
	assert_int(c.get_theme_constant(&"margin_bottom")).is_equal(16)
