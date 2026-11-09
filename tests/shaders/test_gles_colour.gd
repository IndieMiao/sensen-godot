extends GdUnitTestSuite
## SGODOT-458 (周瑜's spec): Compatibility (GLES3) wants ALBEDO / EMISSION sRGB-encoded and hands source_color inputs over
## as stored; the RD renderers give and want linear. gles_colour.gdshaderinc converts under Compatibility only, so Mobile
## draws pixel for pixel as before (measured: 0 pixels) and a shader doing arithmetic on colour reads alike on both.

const INC := "res://modules/render/gles_colour.gdshaderinc"
const TOON := "res://modules/avatar/shaders/avatar_toon.gdshader"

static func _code(path: String) -> String: return FileAccess.get_file_as_string(path)

## The conversions only under Compatibility; elsewhere both are the identity.
func test_the_include_converts_under_compatibility_only() -> void:
	var inc := _code(INC)
	assert_str(inc).contains("#if CURRENT_RENDERER == RENDERER_COMPATIBILITY")
	var at_else := inc.find("#else")
	assert_int(at_else).is_greater(0)
	var rd := inc.substr(at_else, inc.find("#endif") - at_else)
	assert_str(rd).contains("vec3 src_linear(vec3 c) { return c; }")
	assert_str(rd).contains("vec3 albedo_out(vec3 c) { return c; }")
	var gles := inc.substr(0, at_else)
	for f in ["vec3 src_linear(vec3 c)", "vec3 albedo_out(vec3 c)", "max(c, vec3(0.0))"]: assert_str(gles).contains(f)

## Every character and NPC (AvatarMaterialFactory builds only this shader): the albedo texture to linear before its
## weights, ALBEDO and EMISSION back out — a weight k had read as k^2.2 on GLES, people a shade too dark.
func test_avatar_toon_works_out_its_colour_in_linear() -> void:
	var toon := _code(TOON)
	assert_str(toon).contains('#include "%s"' % INC)
	assert_str(toon).contains("vec3 a = src_linear(alb.rgb);")
	assert_str(toon).contains("ALBEDO = albedo_out(a * lit_w);")
	assert_str(toon).contains("EMISSION = albedo_out(a * (flat_w + rim * rim_strength));")
	assert_str(toon).not_contains("ALBEDO = alb.rgb")
	assert_str(toon).not_contains("EMISSION = alb.rgb")
	assert_object(load(TOON) as Shader).is_not_null()   # it compiling is test_material_factory's (with a renderer)
