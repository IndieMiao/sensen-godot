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
	assert_bool(DesignTokens.INK_SUB.v < 0.5).is_true()

func test_button_font_color_matches_ink_token() -> void:
	var color := _theme().get_color(&"font_color", &"Button")
	assert_bool(color.is_equal_approx(DesignTokens.INK)).is_true()

func test_label_font_color_matches_ink_token() -> void:
	var color := _theme().get_color(&"font_color", &"Label")
	assert_bool(color.is_equal_approx(DesignTokens.INK)).is_true()

func test_pill_font_size_matches_token() -> void:
	## 紧凑行动控件用专属中间字号 FONT_PILL。
	assert_int(_theme().get_font_size(&"font_size", &"PillButton")).is_equal(DesignTokens.FONT_PILL)
	assert_int(_theme().get_font_size(&"font_size", &"AccentPillButton")).is_equal(DesignTokens.FONT_PILL)

func test_selected_and_marker_colors_match_tokens() -> void:
	var selected := _theme().get_stylebox(&"normal", &"ChoiceSelectedButton") as StyleBoxFlat
	var marker := _theme().get_stylebox(&"normal", &"MarkerButton") as StyleBoxFlat
	var marker_pressed := _theme().get_stylebox(&"pressed", &"MarkerButton") as StyleBoxFlat
	assert_bool(selected.bg_color.is_equal_approx(DesignTokens.SURFACE_TINT)).is_true()
	assert_bool(marker.bg_color.is_equal_approx(DesignTokens.MARKER)).is_true()
	assert_bool(marker_pressed.bg_color.is_equal_approx(DesignTokens.MARKER_PRESSED)).is_true()

## A7：GameUi 的色板 / 字号只是 DesignTokens 的别名——改 token 就换全局风格，别处不许再写字面值。
func test_game_ui_palette_and_type_are_aliases_of_ui_tokens() -> void:
	assert_bool(GameUi.INK.is_equal_approx(DesignTokens.UI_INK)).is_true()
	assert_bool(GameUi.MUTED.is_equal_approx(DesignTokens.UI_MUTED)).is_true()
	assert_bool(GameUi.GREEN.is_equal_approx(DesignTokens.UI_GREEN)).is_true()
	assert_bool(GameUi.MINT.is_equal_approx(DesignTokens.UI_MINT)).is_true()
	assert_bool(GameUi.PAPER.is_equal_approx(DesignTokens.UI_PAPER)).is_true()
	assert_bool(GameUi.BORDER.is_equal_approx(DesignTokens.UI_BORDER)).is_true()
	var t := GameUi.theme()
	assert_int(t.default_font_size).is_equal(DesignTokens.UI_FONT_BODY)
	assert_int(t.get_font_size(&"font_size", &"TabButton")).is_equal(DesignTokens.UI_FONT_TAB)
	assert_bool((t.get_stylebox(&"disabled", &"SecondaryButton") as StyleBoxFlat).bg_color.is_equal_approx(DesignTokens.UI_SURFACE_DISABLED)).is_true()
	assert_bool((t.get_stylebox(&"normal", &"LineEdit") as StyleBoxFlat).bg_color.is_equal_approx(DesignTokens.UI_FIELD)).is_true()
	var b: Button = auto_free(GameUi.button("", "x", ""))
	assert_float(b.custom_minimum_size.x).is_equal(float(DesignTokens.UI_TOUCH_MIN))
	assert_int(DesignTokens.UI_TOUCH_MIN).is_greater_equal(44)

func test_no_hex_color_literals_left_in_game_ui() -> void:
	var src := FileAccess.get_file_as_string("res://modules/ui/game_ui.gd")
	var re := RegEx.create_from_string('Color\\("[0-9a-fA-F]{6}"\\)')
	assert_array(re.search_all(src)).is_empty()


## A7 收口：壳的代码里不许再出现字面间距与字面字号——一律走 DesignTokens。
## 0 是例外（底栏与主列故意贴合），其余都要能在 token 里找到出处。
func test_shell_code_has_no_literal_spacing_or_font_sizes() -> void:
	var dirs := ["res://modules/app", "res://scenes/app", "res://scenes/app/pages"]
	var spacing := RegEx.create_from_string('add_theme_(constant)_override\\("(separation|h_separation|v_separation|margin_[a-z]+)", ([1-9][0-9]*)\\)')
	var sizes := RegEx.create_from_string('GameUi\\.label\\([^\\n]*?, ([1-9][0-9]*)[,)]')
	var offenders: Array[String] = []
	for dir in dirs:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".gd"):
				continue
			var path := "%s/%s" % [dir, file]
			var src := FileAccess.get_file_as_string(path)
			for m in spacing.search_all(src):
				offenders.append("%s: %s" % [path, m.get_string()])
			for m in sizes.search_all(src):
				offenders.append("%s: %s" % [path, m.get_string()])
	assert_array(offenders).is_empty()
