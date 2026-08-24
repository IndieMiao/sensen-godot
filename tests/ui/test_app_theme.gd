extends GdUnitTestSuite
## 守护缩放基准与主题尺寸基线：这两项一旦被改回默认值，真机 UI 会重新变得点不到。

const THEME_PATH := "res://assets/ui/app_theme.tres"

func test_stretch_settings_are_canvas_items_at_360x640() -> void:
	assert_str(str(ProjectSettings.get_setting("display/window/stretch/mode"))).is_equal("canvas_items")
	assert_str(str(ProjectSettings.get_setting("display/window/stretch/aspect"))).is_equal("expand")
	assert_int(int(ProjectSettings.get_setting("display/window/size/viewport_width"))).is_equal(360)
	assert_int(int(ProjectSettings.get_setting("display/window/size/viewport_height"))).is_equal(640)

func test_desktop_window_override_keeps_720x1280() -> void:
	assert_int(int(ProjectSettings.get_setting("display/window/size/window_width_override"))).is_equal(720)
	assert_int(int(ProjectSettings.get_setting("display/window/size/window_height_override"))).is_equal(1280)

func test_theme_is_registered_and_loads() -> void:
	assert_str(str(ProjectSettings.get_setting("gui/theme/custom"))).is_equal(THEME_PATH)
	assert_object(load(THEME_PATH)).is_not_null()

func test_button_reaches_48_unit_touch_target() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_object(theme).is_not_null()
	assert_int(theme.default_font_size).is_equal(16)
	var sb := theme.get_stylebox(&"normal", &"Button")
	assert_object(sb).is_not_null()
	# 16 号字约 19 单位高，上下各 14 → 约 47~48，达到 48dp 触摸标准
	assert_float(sb.content_margin_top).is_equal(14.0)
	assert_float(sb.content_margin_bottom).is_equal(14.0)
	assert_float(sb.content_margin_left).is_equal(16.0)
	assert_float(sb.content_margin_right).is_equal(16.0)

func test_container_separation_is_8() -> void:
	var theme := load(THEME_PATH) as Theme
	assert_int(theme.get_constant(&"separation", &"HBoxContainer")).is_equal(8)
	assert_int(theme.get_constant(&"separation", &"VBoxContainer")).is_equal(8)
	assert_int(theme.get_constant(&"h_separation", &"GridContainer")).is_equal(8)
	assert_int(theme.get_constant(&"v_separation", &"GridContainer")).is_equal(8)
