extends GdUnitTestSuite
## Tokens v2 + v3 -> UiTokens / gensen_theme.tres stay in sync, and kit code never hard-codes values (SGODOT-211;
## v3 since C-105: the v2 names hold their v3 alias values, every v3 token has its own constant).

const GenTheme := preload("res://tools/ui/gen_theme.gd")
const KIT_DIRS := ["res://scenes/ui_kit", "res://modules/ui/kit"]
const GENERATED := ["res://modules/ui/kit/ui_tokens.gd"]

var tokens: Dictionary
var v3: Dictionary
var consts: Dictionary

func before() -> void:
	tokens = GenTheme.merged_tokens()
	v3 = GenTheme.load_tokens_v3()
	consts = (UiTokens as Script).get_script_constant_map()

func test_version_matches_tokens_file() -> void:
	assert_str(UiTokens.VERSION).is_equal(v3.meta.version)
	assert_str(UiTokens.VERSION_V2).is_equal(tokens.meta.version)

## v3 colours by path; a name a v2 token holds with another value carries `_V3`.
func test_every_v3_token_has_its_constant() -> void:
	for k in v3.color:
		var name := "COLOR_" + GenTheme.const_name(k)
		if consts.has(name + "_V3"): name += "_V3"
		assert_bool(consts.has(name)).override_failure_message("missing " + name).is_true()
		assert_str((consts[name] as Color).to_html()).override_failure_message(name).is_equal(Color.html(v3.color[k].value).to_html())
	for group in ["radius", "space", "size"]:
		for k in v3[group]:
			var name: String = group.to_upper() + "_" + GenTheme.const_name(k)
			if consts.has(name + "_V3"): name += "_V3"
			assert_bool(consts.has(name)).override_failure_message("missing " + name).is_true()
			assert_float(float(consts[name])).override_failure_message(name).is_equal_approx(float(v3[group][k].value), 0.0001)
	for k in v3.motion.duration:
		assert_float(float(consts["MOTION_DURATION_%s_MS" % GenTheme.const_name(k)])).is_equal(float(v3.motion.duration[k].ms))
	assert_array(UiTokens.MOTION_EASING_POP).is_equal([Tween.TRANS_BACK, Tween.EASE_OUT])
	assert_array(UiTokens.MOTION_EASING_LINEAR).is_equal([Tween.TRANS_LINEAR, Tween.EASE_IN_OUT])

## The v2 names that follow v3 (README §2.6): the action colour, paper, ink, the modal scrim and the radii.
func test_v2_aliases_hold_v3_values() -> void:
	assert_str(UiTokens.COLOR_PRIMARY.to_html()).is_equal(UiTokens.COLOR_ACTION_PRIMARY.to_html())
	assert_str(UiTokens.COLOR_SURFACE.to_html()).is_equal(UiTokens.COLOR_SURFACE_PAPER.to_html())
	assert_str(UiTokens.COLOR_TEXT.to_html()).is_equal(UiTokens.COLOR_TEXT_PRIMARY.to_html())
	assert_float(UiTokens.OPACITY_SCRIM_MODAL).is_equal_approx(0.6, 0.001)
	assert_float(float(UiTokens.RADIUS_CARD)).is_equal(float(UiTokens.RADIUS_LG))
	assert_float(float(UiTokens.RADIUS_SHEET)).is_equal(float(UiTokens.RADIUS_XL))
	assert_float(float(UiTokens.SIZE_HUD_AVATAR)).is_equal(38.0)   # the v2 HUD keeps its layout
	assert_float(float(UiTokens.SIZE_HUD_AVATAR_V3)).is_equal(52.0)

func test_v3_type_styles_and_white_variants() -> void:
	var th := UiKit.theme()
	for path in GenTheme.TYPE_STYLES:
		var name: String = GenTheme.TYPE_STYLES[path][0]
		var st: Dictionary = v3.font.styles["body" if path == "bodyBold" else path]
		assert_str(String(th.get_type_variation_base(name))).is_equal("Label")
		assert_int(th.get_font_size(&"font_size", name)).override_failure_message(name).is_equal(int(st.size))
	assert_str(th.get_color(&"font_color", UiTokens.STYLE_TYPE_LABEL_ON_DARK).to_html()).is_equal(Color.WHITE.to_html())
	# §2.1 exception (Q-121 item 1): white on lime carries the 1.5 dark outline
	assert_int(th.get_constant(&"outline_size", &"CmdPrimary")).is_equal(GenTheme.ON_ACTION_OUTLINE)
	assert_int(th.get_constant(&"outline_size", &"CtaBar")).is_equal(GenTheme.ON_ACTION_OUTLINE)
	assert_str(th.get_color(&"font_outline_color", &"CtaBar").to_html()).is_equal(UiTokens.COLOR_ON_ACTION_OUTLINE.to_html())
	assert_int(th.get_constant(&"outline_size", UiTokens.STYLE_TYPE_FLOAT)).is_equal(GenTheme.FLOAT_OUTLINE)

func test_every_colour_token_has_a_matching_constant() -> void:
	for k in tokens.color:
		var name := "COLOR_" + GenTheme.const_name(k)
		assert_bool(consts.has(name)).override_failure_message("missing " + name).is_true()
		assert_str((consts[name] as Color).to_html()).is_equal(Color.html(tokens.color[k]).to_html())

func test_every_numeric_token_has_a_matching_constant() -> void:
	for group in ["opacity", "space", "radius", "stroke", "size", "motion"]:
		for k in tokens[group]:
			var name: String = group.to_upper() + "_" + GenTheme.const_name(k)
			assert_bool(consts.has(name)).override_failure_message("missing " + name).is_true()
			assert_float(float(consts[name])).is_equal_approx(float(tokens[group][k]), 0.0001)

func test_dash_patterns_are_dash_gap_pairs() -> void:
	for k in tokens.dash:
		var name := "DASH_" + GenTheme.const_name(k)
		assert_bool(consts.has(name)).override_failure_message("missing " + name).is_true()
		assert_int((consts[name] as Array).size()).is_equal(2)
		assert_float(float(consts[name][0])).is_equal_approx(float(tokens.dash[k][0]), 0.001)

func test_group_path_keys_become_valid_constants() -> void:
	assert_str(GenTheme.const_name("role/marketTint")).is_equal("ROLE_MARKET_TINT")
	assert_bool(consts.has("COLOR_RARITY_COMMON")).is_true()

func test_unavailable_command_keeps_secondary_ink_and_primary_press_uses_figma_fill() -> void:
	var th := UiKit.theme()
	assert_str(th.get_color(&"font_color", &"CmdBlocked").to_html()).is_equal(UiTokens.COLOR_SECONDARY.to_html())
	assert_str(th.get_stylebox(&"pressed", &"CmdPrimary").bg_color.to_html()).is_equal(UiTokens.COLOR_PRIMARY_PRESSED.to_html())

func test_theme_has_every_text_style_with_its_size_and_weight() -> void:
	var th := UiKit.theme()
	for name in tokens.font.styles:
		var st: Dictionary = tokens.font.styles[name]
		assert_str(String(th.get_type_variation_base(name))).is_equal("Label")
		assert_int(th.get_font_size(&"font_size", name)).is_equal(int(st.size))
		var fv := th.get_font(&"font", name) as FontVariation
		var weight: int = fv.variation_opentype.values()[0]
		assert_int(weight).is_equal(int(tokens.font.weights[st.weight]))

func test_theme_has_button_and_panel_variations() -> void:
	var th := UiKit.theme()
	for name in GenTheme.BUTTONS:
		assert_str(String(th.get_type_variation_base(name))).override_failure_message(name).is_equal("Button")
	for name in GenTheme.PANELS:
		assert_str(String(th.get_type_variation_base(name))).override_failure_message(name).is_equal("PanelContainer")

func test_command_colours_follow_tokens() -> void:
	var th := UiKit.theme()
	assert_str(th.get_stylebox(&"normal", &"CmdPrimary").bg_color.to_html()).is_equal(UiTokens.COLOR_PRIMARY.to_html())
	assert_str(th.get_stylebox(&"disabled", &"CmdPrimary").bg_color.to_html()).is_equal(UiTokens.COLOR_DISABLED.to_html())
	assert_str(th.get_color(&"font_color", &"CmdPrimary").to_html()).is_equal(UiTokens.COLOR_TEXT_ON_DARK.to_html())

func test_compact_command_draws_34_inside_a_44_hit_area() -> void:
	var box: UiStyleBox = UiKit.theme().get_stylebox(&"normal", &"CmdPrimaryCompact")
	for h in [UiTokens.SIZE_TOUCH, UiTokens.SIZE_TOUCH * 2]:
		var drawn := box.visible_rect(Rect2(0, 0, 68, h))
		assert_float(drawn.size.y).is_equal_approx(UiTokens.SIZE_COMMAND_COMPACT, 0.01)
		assert_float(drawn.get_center().y).is_equal_approx(h * 0.5, 0.01)

func test_default_font_is_regular_not_the_thin_default_instance() -> void:
	var fv := UiKit.theme().default_font as FontVariation
	assert_int(fv.variation_opentype.values()[0]).is_equal(int(tokens.font.weights.regular))

func test_kit_code_has_no_colour_literals_or_numeric_font_sizes() -> void:
	var colour := RegEx.create_from_string("Color\\(\\s*\"|Color\\(\\s*[0-9.]+\\s*,|Color\\.html\\(")
	var size := RegEx.create_from_string("font_size\"?\\s*,\\s*[0-9]")
	var offenders := []
	for dir in KIT_DIRS:
		for path in _scripts(dir):
			if path in GENERATED: continue
			var src := FileAccess.get_file_as_string(path)
			if colour.search(src) != null or size.search(src) != null: offenders.append(path)
	assert_array(offenders).is_empty()

func _scripts(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null: return out
	for f in d.get_files():
		if f.ends_with(".gd"): out.append(dir.path_join(f))
	for sub in d.get_directories(): out.append_array(_scripts(dir.path_join(sub)))
	return out
