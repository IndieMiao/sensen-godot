extends GdUnitTestSuite
## marker 必须相对 home 锚点摆放，不能写死经纬度——写死的话用户定位到任何
## 非上海的位置，marker 会全部落到屏幕外（与 pawn 同一个坑，见 test_map_home_anchoring）。

const TOKYO_LAT := 35.6812
const TOKYO_LNG := 139.7671

func test_specs_load_with_at_least_three_markers() -> void:
	var specs := MarkerLayer.load_specs()
	assert_bool(specs.size() >= 3).is_true()
	for s in specs:
		assert_bool(s.has("east_m") and s.has("north_m")).is_true()
		assert_bool(str(s.get("text", "")).length() > 0).is_true()
		assert_bool(str(s.get("author", "")).length() > 0).is_true()
		for byte in (str(s.author) + str(s.text)).to_utf8_buffer():
			assert_bool(byte < 128).is_true()

func test_offsets_stay_within_first_screen_range() -> void:
	## 超出 400m 的 marker 在 z16 首屏就看不见了，演示时等于不存在
	for s in MarkerLayer.load_specs():
		var d := Vector2(float(s.east_m), float(s.north_m)).length()
		assert_bool(d <= 400.0).is_true()

func test_markers_follow_home_not_absolute_coords() -> void:
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	assert_bool(layer.markers.size() >= 3).is_true()
	# 以东京为锚点时，每个 marker 的世界坐标都应在 home 附近（几百米内）
	for i in layer.markers.size():
		var w: Vector3 = layer.world_position(i, TOKYO_LAT, TOKYO_LNG)
		assert_bool(w.length() < 500.0).is_true()

func test_east_north_map_to_world_axes() -> void:
	## 世界系：x = 东，-z = 北（与 MapGeoMath 一致）
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	layer.markers[0].east_m = 100.0
	layer.markers[0].north_m = 50.0
	var w: Vector3 = layer.world_position(0, TOKYO_LAT, TOKYO_LNG)
	assert_float(w.x).is_equal_approx(100.0, 0.5)
	assert_float(w.z).is_equal_approx(-50.0, 0.5)

func test_toggle_opens_one_bubble_at_a_time() -> void:
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	layer._toggle(0)
	assert_bool((layer.markers[0].bubble as Control).visible).is_true()
	layer._toggle(1)
	assert_bool((layer.markers[0].bubble as Control).visible).is_false()
	assert_bool((layer.markers[1].bubble as Control).visible).is_true()
	layer._toggle(1) # 再点一次收起
	assert_bool((layer.markers[1].bubble as Control).visible).is_false()

func test_markers_use_dedicated_style_and_48_unit_touch_targets() -> void:
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	for marker in layer.markers:
		var pin := marker.pin as Button
		var face := marker.face as Panel
		# 留言气泡字形，不是文字。曾经是墨色的 "!"：珊瑚底 + 近黑感叹号在地图上
		# 读起来是"警告/出错"，而这些 marker 是别人留下的留言。回退成 Label 就
		# 又变回警示牌，所以这里断言它必须是带纹理的图形。
		var mark := face.get_child(0) as TextureRect
		assert_object(mark).is_not_null()
		assert_object(mark.texture).is_not_null()
		assert_str(pin.text).is_empty()
		assert_bool(face.get_child(0) is Label).is_false()
		assert_str(pin.tooltip_text).is_equal("Open note")
		assert_bool(pin.custom_minimum_size.x >= 48.0).is_true()
		assert_bool(pin.custom_minimum_size.y >= 48.0).is_true()
		assert_vector(face.size).is_equal_approx(Vector2(36, 36), Vector2(0.1, 0.1))
		assert_bool(pin.get_theme_stylebox(&"normal") is StyleBoxEmpty).is_true()

func test_marker_face_uses_coral_press_feedback() -> void:
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	var pin := layer.markers[0].pin as Button
	var face := layer.markers[0].face as Panel
	var normal := face.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_bool(normal.bg_color.is_equal_approx(DesignTokens.MARKER)).is_true()
	pin.emit_signal(&"button_down")
	var pressed := face.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_bool(pressed.bg_color.is_equal_approx(DesignTokens.MARKER_PRESSED)).is_true()
	assert_bool(pressed.bg_color.is_equal_approx(normal.bg_color)).is_false()
	pin.emit_signal(&"button_up")
	var released := face.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_bool(released.bg_color.is_equal_approx(DesignTokens.MARKER)).is_true()
	pin.emit_signal(&"button_down")
	pin.emit_signal(&"mouse_exited")
	var cancelled := face.get_theme_stylebox(&"panel") as StyleBoxFlat
	assert_bool(cancelled.bg_color.is_equal_approx(DesignTokens.MARKER)).is_true()

func test_pin_center_rect_keeps_the_full_touch_target_inside_safe_content() -> void:
	var rect := MarkerLayer.pin_center_rect(
		Rect2(0, 0, 360, 640), Vector4(16, 120, 16, 100))
	assert_vector(rect.position).is_equal(Vector2(40, 144))
	assert_vector(rect.end).is_equal(Vector2(320, 516))
	assert_bool(rect.has_point(Vector2(39, 200))).is_false()
	assert_bool(rect.has_point(Vector2(40, 200))).is_true()

func test_bubble_position_is_clamped_inside_safe_viewport() -> void:
	var viewport := Rect2(Vector2.ZERO, Vector2(360, 640))
	var margins := Vector4(16, 24, 16, 20)
	var size := Vector2(208, 96)
	var p := MarkerLayer.bubble_position(Vector2(4, 180), size, viewport, margins)
	assert_bool(p.x >= 16.0).is_true()
	assert_bool(p.y >= 24.0).is_true()
	assert_bool(p.x + size.x <= 344.0).is_true()
	assert_bool(p.y + size.y <= 620.0).is_true()

func test_bubble_flips_below_marker_when_top_space_is_tight() -> void:
	var p := MarkerLayer.bubble_position(
		Vector2(180, 40), Vector2(208, 96), Rect2(0, 0, 360, 640),
		Vector4(16, 24, 16, 20))
	assert_bool(p.y > 40.0).is_true()
