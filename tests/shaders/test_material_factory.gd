extends GdUnitTestSuite

func test_shader_loads_and_compiles() -> void:
	var shader: Shader = load("res://modules/avatar/shaders/avatar_toon.gdshader")
	assert_object(shader).is_not_null()
	assert_str(RenderingServer.shader_get_code(shader.get_rid())).is_not_empty()

func test_factory_sets_params() -> void:
	var tex := PlaceholderTexture2D.new()
	var m := AvatarMaterialFactory.create({
		"albedo_tex": tex,
		"ao_strength": 0.5,
		"shadow_value": 0.7,
	})
	assert_object(m).is_not_null()
	assert_object(m.shader).is_not_null()
	assert_object(m.get_shader_parameter("albedo_tex")).is_same(tex)
	assert_float(m.get_shader_parameter("ao_strength")).is_equal_approx(0.5, 0.001)
	assert_float(m.get_shader_parameter("shadow_value")).is_equal_approx(0.7, 0.001)

func test_factory_ignores_unknown_keys() -> void:
	var m := AvatarMaterialFactory.create({"albedo_tex": PlaceholderTexture2D.new(), "bogus_key": 1.0})
	assert_object(m).is_not_null()
