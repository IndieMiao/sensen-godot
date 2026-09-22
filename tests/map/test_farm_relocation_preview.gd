extends GdUnitTestSuite

var _locale := ""

func before_test() -> void:
	_locale = TranslationServer.get_locale()

func after_test() -> void:
	TranslationServer.set_locale(_locale)

func _preview() -> Dictionary:
	return {"preview_id": "preview", "base_version": 8, "expires_at": 123456,
		"farm_terrain": JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_farm_terrain.json")),
		"moved_cells": 2, "moved_decorations": 3}

func test_preview_uses_authoritative_terrain_and_requires_explicit_confirmation() -> void:
	var panel := auto_free(FarmRelocationPreview.new()) as FarmRelocationPreview
	add_child(panel)
	assert_bool(panel.configure(_preview(), "shanghai")).is_true()
	assert_object(panel.terrain_image.texture).is_not_null()
	assert_str(panel.summary.text).contains("2")
	assert_str(panel.summary.text).contains("3")
	var image := panel.terrain_image.texture.get_image()
	var colors := {}
	for y in image.get_height():
		for x in image.get_width(): colors[image.get_pixel(x, y).to_html()] = true
	assert_int(colors.size()).is_greater(3)
	assert_bool(panel.confirm_button.disabled).is_false()
	panel.set_busy(false, true)
	assert_bool(panel.cancel_button.disabled).is_true()
	assert_bool(panel.reselect_button.disabled).is_true()
	assert_bool(panel.confirm_button.disabled).is_false()
	assert_str(panel.confirm_button.text).is_equal("Check relocation result")

func test_preview_fits_360_phone_safe_area_in_both_languages() -> void:
	var host := auto_free(Control.new()) as Control
	host.size = Vector2(328, 580)
	add_child(host)
	var panel := FarmRelocationPreview.new()
	panel.theme = GameUi.theme()
	host.add_child(panel)
	assert_bool(panel.configure(_preview(), "shanghai")).is_true()
	for locale in ["en", "zh_CN"]:
		TranslationServer.set_locale(locale)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_float(panel.get_combined_minimum_size().x).is_less_equal(328.0)
		assert_float(panel.size.x).is_less_equal(328.0)
		assert_float(panel.confirm_button.get_global_rect().end.y).is_less_equal(host.get_global_rect().end.y)

func test_relocation_selection_never_calls_creation_action() -> void:
	var panel := auto_free(SelectPanel.new()) as SelectPanel
	add_child(panel)
	panel.set_relocation_mode()
	assert_bool(panel.generation_mode).is_true()
	assert_bool(panel.relocation_mode).is_true()
	assert_str(panel.confirm_button.text).is_equal("Preview this location")
	panel.set_saving(true)
	assert_bool(panel.confirm_button.disabled).is_true()
	panel.set_saving(false, "Invalid location")
	assert_str(panel.confirm_button.text).is_equal("Preview this location")
	assert_str(panel._capacity.text).is_equal("Invalid location")
