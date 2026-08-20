extends GdUnitTestSuite

func test_project_boots() -> void:
	assert_bool(true).is_true()

func test_renderer_is_mobile() -> void:
	assert_str(str(ProjectSettings.get_setting("rendering/renderer/rendering_method"))).is_equal("mobile")
