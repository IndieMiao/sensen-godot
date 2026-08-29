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

func test_design_system_type_variations_exist() -> void:
	## 守护统一设计语言（2026-08-29 白色浮层+薄荷绿主行动色）：三个场景共用这些
	## 类型变体，误删任意一个都会让对应场景静默回退到默认灰按钮。
	var theme := load(THEME_PATH) as Theme
	for variation in [&"AccentButton", &"AccentPillButton", &"PillButton", &"RoundButton"]:
		assert_str(String(theme.get_type_variation_base(variation))).is_equal("Button")
		assert_object(theme.get_stylebox(&"normal", variation)).is_not_null()
		assert_object(theme.get_stylebox(&"pressed", variation)).is_not_null()
	assert_str(String(theme.get_type_variation_base(&"ChipPanel"))).is_equal("PanelContainer")
	assert_object(theme.get_stylebox(&"panel", &"ChipPanel")).is_not_null()

func test_accent_color_is_mint() -> void:
	## 主行动色取自角色短裤的薄荷绿；按钮文字用墨色保证对比度。
	var theme := load(THEME_PATH) as Theme
	var sb := theme.get_stylebox(&"normal", &"AccentButton") as StyleBoxFlat
	assert_object(sb).is_not_null()
	assert_float(sb.bg_color.g).is_greater(sb.bg_color.r) # 绿 > 红：确实是绿色系
	assert_float(theme.get_color(&"font_color", &"Button").v).is_less(0.5) # 墨色文字
