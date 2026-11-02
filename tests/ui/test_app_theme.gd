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
	## 场景只引用语义化 variation，误删会静默回退到默认控件。
	var theme := load(THEME_PATH) as Theme
	for variation in [&"AccentButton", &"AccentPillButton", &"SecondaryButton", &"GhostButton",
			&"PillButton", &"RailButton", &"RoundButton", &"TabButton", &"TabSelectedButton",
			&"ChoiceButton", &"ChoiceSelectedButton", &"MarkerButton"]:
		assert_str(String(theme.get_type_variation_base(variation))).is_equal("Button")
		assert_object(theme.get_stylebox(&"normal", variation)).is_not_null()
		assert_object(theme.get_stylebox(&"pressed", variation)).is_not_null()
	for variation in [&"BottomSheet", &"ChipPanel", &"TopPanel", &"ToastPanel"]:
		assert_str(String(theme.get_type_variation_base(variation))).is_equal("PanelContainer")
		assert_object(theme.get_stylebox(&"panel", variation)).is_not_null()

func test_text_button_variations_keep_touch_padding() -> void:
	var theme := load(THEME_PATH) as Theme
	for variation in [&"AccentButton", &"SecondaryButton", &"GhostButton", &"TabButton",
			&"TabSelectedButton", &"ChoiceButton", &"ChoiceSelectedButton"]:
		var sb := theme.get_stylebox(&"normal", variation)
		assert_float(sb.content_margin_top).is_greater_equal(14.0)
		assert_float(sb.content_margin_bottom).is_greater_equal(14.0)

func test_accent_color_is_mint() -> void:
	## 主行动色取自角色短裤的薄荷绿；按钮文字用墨色保证对比度。
	var theme := load(THEME_PATH) as Theme
	var sb := theme.get_stylebox(&"normal", &"AccentButton") as StyleBoxFlat
	assert_object(sb).is_not_null()
	assert_float(sb.bg_color.g).is_greater(sb.bg_color.r) # 绿 > 红：确实是绿色系
	assert_float(theme.get_color(&"font_color", &"Button").v).is_less(0.5) # 墨色文字

func test_toggle_button_keeps_dark_text_after_touch() -> void:
	## Android 会在抬手后保留 hover；toggle 的 hover+pressed 也必须保持可读。
	var theme := load(THEME_PATH) as Theme
	## The ink is GameUi.INK since c1d0d261 (09-23 restyle); DesignTokens.INK kept the old one.
	for state in [&"font_pressed_color", &"font_hover_pressed_color"]:
		assert_bool(theme.get_color(state, &"SecondaryButton").is_equal_approx(
			GameUi.INK)).is_true()

func test_button_icons_are_tinted_dark_not_left_at_engine_white() -> void:
	## assets/ui/icons/*.svg 全是白色描边，靠主题的 icon_*_color 乘法调制成墨色。
	## Godot 默认主题的 icon_normal_color 是纯白——这几项一旦被删，图标回落成
	## 白×白，在白色 rail/圆钮上彻底看不见，而且不报任何错。
	var theme := load(THEME_PATH) as Theme
	for state in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color",
			&"icon_hover_pressed_color", &"icon_focus_color"]:
		assert_bool(theme.has_color(state, &"Button")).is_true()
		assert_float(theme.get_color(state, &"Button").v).is_less(0.5)
	# 图标按 24 单位画布绘制，用 icon_max_width 收口，避免 4x 栅格化的纹理原尺寸铺满按钮
	assert_int(theme.get_constant(&"icon_max_width", &"Button")).is_between(16, 32)

func test_rail_tiles_share_one_surface_and_mark_the_active_one() -> void:
	## 地图侧栏统一成 RailButton 后，"当前视图模式"只剩底色一条线索：
	## normal 与 pressed 必须真的不同色，否则 3D/2D 按下去看不出变化。
	var theme := load(THEME_PATH) as Theme
	var normal := theme.get_stylebox(&"normal", &"RailButton") as StyleBoxFlat
	var active := theme.get_stylebox(&"pressed", &"RailButton") as StyleBoxFlat
	assert_object(normal).is_not_null()
	assert_object(active).is_not_null()
	assert_bool(normal.bg_color.is_equal_approx(active.bg_color)).is_false()
	# Android 抬手后会保留 hover；toggle 按住态必须显式定义，否则回落到引擎默认灰
	assert_object(theme.get_stylebox(&"hover_pressed", &"RailButton")).is_not_null()
	assert_bool((theme.get_stylebox(&"hover_pressed", &"RailButton") as StyleBoxFlat)
		.bg_color.is_equal_approx(active.bg_color)).is_true()
	# 图标与文案上下叠放，四边内边距必须小于普通按钮的 16/14，否则 56 方块塞不下
	assert_float(normal.content_margin_top).is_less(14.0)
	assert_float(normal.content_margin_left).is_less(16.0)

func test_marker_uses_non_accent_signal_color() -> void:
	var theme := load(THEME_PATH) as Theme
	var accent := (theme.get_stylebox(&"normal", &"AccentButton") as StyleBoxFlat).bg_color
	var marker := (theme.get_stylebox(&"normal", &"MarkerButton") as StyleBoxFlat).bg_color
	assert_bool(marker.is_equal_approx(accent)).is_false()
	# The selected game palette uses a pale violet marker with dark text.
	assert_float(marker.b).is_greater(marker.g)
	assert_bool(theme.get_color(&"font_color", &"MarkerButton").is_equal_approx(
		GameUi.INK)).is_true()   # GameUi.INK since c1d0d261 (09-23 restyle)
