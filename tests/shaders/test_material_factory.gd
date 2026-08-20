extends GdUnitTestSuite

func test_shader_loads_and_compiles() -> void:
	var shader: Shader = load("res://modules/avatar/shaders/avatar_toon.gdshader")
	assert_object(shader).is_not_null()
	assert_str(RenderingServer.shader_get_code(shader.get_rid())).is_not_empty()

func test_factory_sets_params() -> void:
	# Test all factory keys: texture (Texture2D) + all float params + ao_tex (String path)
	var albedo_tex := PlaceholderTexture2D.new()
	var m := AvatarMaterialFactory.create({
		"albedo_tex": albedo_tex,
		"ao_tex": "res://icon.svg",  # String path → load() conversion
		"ao_strength": 0.5,
		"shadow_value": 0.7,
		"shadow_softness": 0.2,
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
	assert_float(m.get_shader_parameter("shadow_value")).is_equal_approx(0.7, 0.001)
	assert_float(m.get_shader_parameter("shadow_softness")).is_equal_approx(0.2, 0.001)
	assert_float(m.get_shader_parameter("emission_strength")).is_equal_approx(0.4, 0.001)
	assert_float(m.get_shader_parameter("rim_strength")).is_equal_approx(0.6, 0.001)

func test_factory_ignores_unknown_keys() -> void:
	var m := AvatarMaterialFactory.create({"albedo_tex": PlaceholderTexture2D.new(), "bogus_key": 1.0})
	assert_object(m).is_not_null()
