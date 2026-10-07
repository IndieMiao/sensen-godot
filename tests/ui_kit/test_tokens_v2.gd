extends GdUnitTestSuite
## Tokens v2 -> UiTokens / gensen_theme.tres stay in sync, and kit code never hard-codes values (SGODOT-211).

const GenTheme := preload("res://tools/ui/gen_theme.gd")
const KIT_DIRS := ["res://scenes/ui_kit", "res://modules/ui/kit"]
const GENERATED := ["res://modules/ui/kit/ui_tokens.gd"]

var tokens: Dictionary
var consts: Dictionary

func before() -> void:
	tokens = GenTheme.load_tokens()
	consts = (UiTokens as Script).get_script_constant_map()

func test_version_matches_tokens_file() -> void:
	assert_str(UiTokens.VERSION).is_equal(tokens.meta.version)

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
	assert_str(th.get_color(&"font_color", &"CmdPrimary").to_html()).is_equal(UiTokens.COLOR_SURFACE_RAISED.to_html())

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
