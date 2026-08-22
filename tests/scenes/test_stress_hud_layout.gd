extends GdUnitTestSuite
## HUD 回归：不再零边距贴边（压状态栏），滑条高度达到可拖尺寸。

const SCENE := "res://scenes/stress_test/stress_test.tscn"

func _instantiate() -> Node:
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		return null
	var scene := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	return scene

func test_hud_is_wrapped_in_safe_area() -> void:
	var s := _instantiate()
	if s == null:
		push_warning("转换产物缺失，跳过")
		return
	assert_object(s.get_node("HUD/SafeArea") as SafeAreaMargin).is_not_null()
	assert_object(s.get_node("HUD/SafeArea/VBox")).is_not_null()

func test_slider_is_tall_enough_to_drag() -> void:
	var s := _instantiate()
	if s == null:
		push_warning("转换产物缺失，跳过")
		return
	var slider := s.get_node("HUD/SafeArea/VBox/CountSlider") as HSlider
	assert_object(slider).is_not_null()
	assert_float(slider.custom_minimum_size.y).is_greater_equal(48.0)
	assert_int(slider.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)
