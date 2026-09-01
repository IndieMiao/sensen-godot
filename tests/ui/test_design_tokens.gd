extends GdUnitTestSuite
## design token 与主题同源：主题里的关键取值必须能在 DesignTokens 找到对应常量。
## 下周设计会换风格时，这些断言保证"改 token + 同步主题"就够，不会有散落的硬编码。
## 注意本套断言与 tests/ui/test_app_theme.gd 是互补的：那边守 48dp 触摸目标与
## 类型变体存在性，这边守取值来源统一。

const THEME_PATH := "res://assets/ui/app_theme.tres"

func _theme() -> Theme:
	return load(THEME_PATH) as Theme

func test_accent_matches_token() -> void:
	var sb := _theme().get_stylebox(&"normal", &"AccentButton") as StyleBoxFlat
	assert_object(sb).is_not_null()
	assert_bool(sb.bg_color.is_equal_approx(DesignTokens.ACCENT)).is_true()

func test_accent_pressed_matches_deep_token() -> void:
	var sb := _theme().get_stylebox(&"pressed", &"AccentButton") as StyleBoxFlat
	assert_bool(sb.bg_color.is_equal_approx(DesignTokens.ACCENT_DEEP)).is_true()

func test_body_font_size_is_token_default() -> void:
	assert_int(_theme().default_font_size).is_equal(DesignTokens.FONT_BODY)

func test_font_scale_is_five_strictly_descending_steps() -> void:
	var steps := [DesignTokens.FONT_TITLE, DesignTokens.FONT_BODY,
		DesignTokens.FONT_LABEL, DesignTokens.FONT_CAPTION, DesignTokens.FONT_MICRO]
	for i in steps.size() - 1:
		assert_bool(steps[i] > steps[i + 1]).is_true()

func test_spacing_grid_is_4dp_multiples() -> void:
	for v in [DesignTokens.SPACE_1, DesignTokens.SPACE_2, DesignTokens.SPACE_3,
			DesignTokens.SPACE_4, DesignTokens.SPACE_6]:
		assert_int(v % 4).is_equal(0)

func test_container_separation_uses_space_2() -> void:
	var t := _theme()
	assert_int(t.get_constant(&"separation", &"HBoxContainer")).is_equal(DesignTokens.SPACE_2)
	assert_int(t.get_constant(&"separation", &"VBoxContainer")).is_equal(DesignTokens.SPACE_2)

func test_button_padding_matches_touch_target_tokens() -> void:
	var sb := _theme().get_stylebox(&"normal", &"Button") as StyleBoxFlat
	assert_float(sb.content_margin_top).is_equal(float(DesignTokens.BTN_PAD_V))
	assert_float(sb.content_margin_left).is_equal(float(DesignTokens.BTN_PAD_H))

func test_card_radius_token_applied_to_button() -> void:
	var sb := _theme().get_stylebox(&"normal", &"Button") as StyleBoxFlat
	assert_int(sb.corner_radius_top_left).is_equal(DesignTokens.RADIUS_CARD)

func test_sheet_radius_token_applied_to_drawer() -> void:
	var sb := _theme().get_stylebox(&"panel", &"PanelContainer") as StyleBoxFlat
	assert_int(sb.corner_radius_top_left).is_equal(DesignTokens.RADIUS_SHEET)

func test_ink_is_dark_enough_for_contrast() -> void:
	assert_bool(DesignTokens.INK.v < 0.5).is_true()
