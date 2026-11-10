extends GdUnitTestSuite

func test_shader_loads_and_compiles() -> void:
	var shader: Shader = load("res://modules/avatar/shaders/avatar_toon.gdshader")
	assert_object(shader).is_not_null()
	assert_str(shader.code).is_not_empty()
	# The dummy headless renderer keeps no shader code (the freeze's --headless run, SGODOT-460).
	if DisplayServer.get_name() != "headless":
		assert_str(RenderingServer.shader_get_code(shader.get_rid())).is_not_empty()

func test_factory_sets_params() -> void:
	# Test all factory keys: texture (Texture2D) + all float params + ao_tex (String path)
	var albedo_tex := PlaceholderTexture2D.new()
	var m := AvatarMaterialFactory.create({
		"albedo_tex": albedo_tex,
		"ao_tex": "res://icon.svg",  # String path → load() conversion
		"ao_strength": 0.5,
		"smoothness": 0.7,
		"diffuse_strength": 0.9,
		"emission_strength": 0.4,
		"rim_strength": 0.6,
	})

	# Material object and shader
	assert_object(m).is_not_null()
	assert_object(m.shader).is_not_null()

	# Texture keys: albedo_tex (direct Texture2D)
	assert_object(m.get_shader_parameter("albedo_tex")).is_same(albedo_tex)

	# Texture keys: ao_tex (String path → loaded Texture2D)
	var ao_tex_param = m.get_shader_parameter("ao_tex")
	assert_object(ao_tex_param).is_not_null()
	assert_bool(ao_tex_param is Texture2D).is_true()

	# Float keys: all should match assigned non-default values
	assert_float(m.get_shader_parameter("ao_strength")).is_equal_approx(0.5, 0.001)
	assert_float(m.get_shader_parameter("smoothness")).is_equal_approx(0.7, 0.001)
	assert_float(m.get_shader_parameter("diffuse_strength")).is_equal_approx(0.9, 0.001)
	assert_float(m.get_shader_parameter("emission_strength")).is_equal_approx(0.4, 0.001)
	assert_float(m.get_shader_parameter("rim_strength")).is_equal_approx(0.6, 0.001)

## 回归：shader 必须走引擎标准光照，不能再自带 light()。
## 2026-09-01 真机比对发现，一期那个自定义两段 ramp（配 SPECULAR=0 / ROUGHNESS=1）
## 与 Unity 原版（URP Lit）根本不是同一个光照模型，画面因此完全没有体积感。
func test_shader_uses_engine_lighting_not_custom_ramp() -> void:
	var src := FileAccess.get_file_as_string("res://modules/avatar/shaders/avatar_toon.gdshader")
	assert_bool(src.contains("void light()")).is_false()
	assert_bool(src.contains("SPECULAR = 0.0")).is_false()
	assert_bool(src.contains("ROUGHNESS = 1.0;")).is_false()
	# Smoothness 必须真的接到 ROUGHNESS 上
	assert_bool(src.contains("ROUGHNESS")).is_true()
	assert_bool(src.contains("smoothness")).is_true()

func test_factory_ignores_unknown_keys() -> void:
	var m := AvatarMaterialFactory.create({"albedo_tex": PlaceholderTexture2D.new(), "bogus_key": 1.0})
	assert_object(m).is_not_null()
