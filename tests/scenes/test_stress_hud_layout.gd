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

func test_safe_area_and_vbox_pass_touches_through_for_camera_orbit() -> void:
	## 回归：全屏容器 SafeArea 和它直属 VBox 若不是 IGNORE，会吞掉所有触摸事件，
	## 压测场景完全无法转动镜头。变异测试证实了这条真实回归向量，而现有测试
	## 对此全部失明。同时反向断言可交互控件不能被误设成 IGNORE（那样会点不了）。
	var s := _instantiate()
	if s == null:
		push_warning("转换产物缺失，跳过")
		return
	var safe_area := s.get_node("HUD/SafeArea") as Control
	var vbox := s.get_node("HUD/SafeArea/VBox") as Control
	assert_object(safe_area).is_not_null()
	assert_object(vbox).is_not_null()
	assert_int(safe_area.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(vbox.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	for path in ["Card/CardVBox/CountSlider", "Row/StrategyButton", "Row/MapButton"]:
		var ctrl := s.get_node("HUD/SafeArea/VBox/" + path) as Control
		assert_object(ctrl).is_not_null()
		assert_int(ctrl.mouse_filter).is_not_equal(Control.MOUSE_FILTER_IGNORE)

func test_slider_is_tall_enough_to_drag() -> void:
	var s := _instantiate()
	if s == null:
		push_warning("转换产物缺失，跳过")
		return
	var slider := s.get_node("HUD/SafeArea/VBox/Card/CardVBox/CountSlider") as HSlider
	assert_object(slider).is_not_null()
	assert_float(slider.custom_minimum_size.y).is_greater_equal(48.0)
	assert_int(slider.size_flags_horizontal).is_equal(Control.SIZE_EXPAND_FILL)


func test_internal_tool_has_one_clear_product_exit() -> void:
	var s := _instantiate()
	if s == null:
		push_warning("转换产物缺失，跳过")
		return
	var root := s.get_node("HUD/SafeArea/VBox")
	assert_str((root.get_node("Card/CardVBox/HeaderRow/Title") as Label).text).is_equal("Performance Monitor")
	assert_str((root.get_node("Card/CardVBox/HeaderRow/Badge") as Label).text).is_equal("INTERNAL")
	assert_str((root.get_node("Row/MapButton") as Button).text).is_equal("Back to Map")
	assert_object(root.get_node_or_null("Row/SceneButton")).is_null()


func test_hud_resolves_current_design_tokens_and_semantic_variations() -> void:
	var s := _instantiate()
	if s == null:
		push_warning("转换产物缺失，跳过")
		return
	var card := s.get_node("HUD/SafeArea/VBox/Card") as PanelContainer
	var card_vbox := s.get_node("HUD/SafeArea/VBox/Card/CardVBox") as VBoxContainer
	var title := card_vbox.get_node("HeaderRow/Title") as Label
	var badge := card_vbox.get_node("HeaderRow/Badge") as Label
	var stats := card_vbox.get_node("StatsLabel") as Label
	var load_label := card_vbox.get_node("LoadRow/LoadLabel") as Label
	var count_value := card_vbox.get_node("LoadRow/CountValue") as Label
	var strategy := s.get_node("HUD/SafeArea/VBox/Row/StrategyButton") as Button
	var map_button := s.get_node("HUD/SafeArea/VBox/Row/MapButton") as Button

	assert_str(String(card.theme_type_variation)).is_equal("ChipPanel")
	assert_str(String(strategy.theme_type_variation)).is_equal("SecondaryButton")
	assert_str(String(map_button.theme_type_variation)).is_equal("AccentButton")
	assert_int(card_vbox.get_theme_constant(&"separation")).is_equal(DesignTokens.SPACE_2)
	assert_int(title.get_theme_font_size(&"font_size")).is_equal(DesignTokens.FONT_TITLE)
	assert_int(badge.get_theme_font_size(&"font_size")).is_equal(DesignTokens.FONT_MICRO)
	assert_int(stats.get_theme_font_size(&"font_size")).is_equal(DesignTokens.FONT_LABEL)
	assert_int(load_label.get_theme_font_size(&"font_size")).is_equal(DesignTokens.FONT_LABEL)
	assert_int(count_value.get_theme_font_size(&"font_size")).is_equal(DesignTokens.FONT_LABEL)
	assert_bool(badge.get_theme_color(&"font_color").is_equal_approx(
		DesignTokens.INK_SUB)).is_true()
	assert_bool(stats.get_theme_color(&"font_color").is_equal_approx(
		GameUi.INK)).is_true()   # theme Label ink, GameUi.INK since c1d0d261 (09-23 restyle)
	assert_bool(count_value.get_theme_color(&"font_color").is_equal_approx(
		DesignTokens.ACCENT_DEEP)).is_true()
