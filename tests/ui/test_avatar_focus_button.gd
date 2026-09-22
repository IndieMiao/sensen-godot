extends GdUnitTestSuite

const FocusButton := preload("res://modules/ui/avatar_focus_button.gd")

func _show_offscreen(button: Button) -> void:
	button.update_indicator(Vector2(500, 422), Rect2(0, 0, 390, 844), Rect2(16, 110, 358, 660))

func _wait_for_portrait(button: Button) -> void:
	for frame in 180:
		if not button._rendering and button._shown_key == button._desired_key: return
		await get_tree().process_frame
	assert_bool(button._rendering).is_false()
	assert_str(button._shown_key).is_equal(button._desired_key)

func _different_outfit() -> AvatarConfig:
	var original := Avatar.load_outfit()
	var alternate := original.duplicate_config()
	for part in Avatar.catalog.parts_for_slot(&"hairHat"):
		if str(part.id) != str(original.slots.get(&"hairHat", "")):
			alternate.slots[&"hairHat"] = str(part.id)
			break
	return alternate

func _assert_idle_portrait(button: Button) -> void:
	assert_bool(button._rendering).is_false()
	assert_object(button._rig).is_null()
	if button._viewport:
		assert_int(button._viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)

func test_portrait_uses_current_saved_outfit_without_changing_world_camera_or_save() -> void:
	var source := Avatar.load_outfit().to_json_text()
	var camera := get_viewport().get_camera_3d()
	var button := auto_free(FocusButton.new()) as Button
	button.theme = GameUi.theme()
	add_child(button)
	assert_bool(button.visible).is_false()
	_show_offscreen(button)
	await _wait_for_portrait(button)
	assert_str(button._shown_key).is_equal(source.sha256_text())
	assert_str(Avatar.load_outfit().to_json_text()).is_equal(source)
	assert_object(get_viewport().get_camera_3d()).is_equal(camera)
	assert_float(button.custom_minimum_size.x).is_greater_equal(44)
	assert_float(button.custom_minimum_size.y).is_greater_equal(44)
	assert_object(button.portrait.texture).is_not_null()
	if button._viewport:
		assert_bool(button._viewport.own_world_3d).is_true()
		assert_int(button._viewport.render_target_update_mode).is_equal(SubViewport.UPDATE_DISABLED)
		assert_object(button._rig).is_null()
	if DisplayServer.get_name() != "headless":
		var image: Image = button.portrait.texture.get_image()
		assert_int(image.get_width()).is_greater_equal(256)
		assert_int(image.get_height()).is_equal(image.get_width())
		assert_float(image.get_pixel(0, 0).a).is_zero()
		var colors := {}
		for y in range(image.get_height() / 10, image.get_height() * 9 / 10, 8):
			for x in range(image.get_width() / 10, image.get_width() * 9 / 10, 8):
				var pixel := image.get_pixel(x, y)
				if pixel.a > 0.1: colors[pixel.to_html()] = true
		assert_int(colors.size()).is_greater(30)

func test_identical_outfit_reuses_portrait_and_changed_appearance_refreshes_it() -> void:
	var button := auto_free(FocusButton.new()) as Button
	add_child(button)
	_show_offscreen(button)
	await _wait_for_portrait(button)
	var first: Texture2D = button.portrait.texture
	var renders: int = button.renders
	var original := Avatar.load_outfit()
	button.set_outfit(original)
	await get_tree().process_frame
	assert_object(button.portrait.texture).is_same(first)
	assert_int(button.renders).is_equal(renders)
	var alternate := _different_outfit()
	assert_str(str(alternate.slots[&"hairHat"])).is_not_equal(str(original.slots[&"hairHat"]))
	button.set_outfit(alternate)
	await _wait_for_portrait(button)
	assert_str(button._shown_key).is_equal(alternate.to_json_text().sha256_text())
	assert_str(Avatar.load_outfit().to_json_text()).is_equal(original.to_json_text())
	if DisplayServer.get_name() != "headless": assert_object(button.portrait.texture).is_not_same(first)

func test_saved_outfit_defers_assembly_until_scene_and_canvas_are_visible_and_enabled() -> void:
	var saved := Avatar.load_outfit().to_json_text()
	var camera := get_viewport().get_camera_3d()
	var scene := auto_free(Node3D.new()) as Node3D
	add_child(scene)
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	var button := FocusButton.new()
	layer.add_child(button)
	_show_offscreen(button)
	await _wait_for_portrait(button)
	var shown: String = button._shown_key
	var render_count: int = button.renders
	var alternate := _different_outfit()
	var key := alternate.to_json_text().sha256_text()
	FocusButton._cache.erase(key)
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	scene.hide()
	layer.hide()
	# Saving in a different visible scene still emits into the suspended farm.
	Avatar.outfit_saved.emit(alternate)
	for frame in 6: await get_tree().process_frame
	_assert_idle_portrait(button)
	assert_str(button._desired_key).is_equal(key)
	assert_str(button._shown_key).is_equal(shown)
	assert_int(button.renders).is_equal(render_count)
	scene.process_mode = Node.PROCESS_MODE_INHERIT
	for frame in 3: await get_tree().process_frame
	_assert_idle_portrait(button)
	assert_str(button._shown_key).is_equal(shown)
	scene.show()
	for frame in 3: await get_tree().process_frame
	_assert_idle_portrait(button)
	assert_str(button._shown_key).is_equal(shown)
	layer.show()
	await _wait_for_portrait(button)
	assert_str(button._shown_key).is_equal(key)
	_assert_idle_portrait(button)
	# Enabling a still-visible branch must also resume without a visibility toggle.
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	FocusButton._cache.erase(saved.sha256_text())
	Avatar.outfit_saved.emit(Avatar.load_outfit())
	for frame in 3: await get_tree().process_frame
	_assert_idle_portrait(button)
	assert_str(button._shown_key).is_equal(key)
	scene.process_mode = Node.PROCESS_MODE_INHERIT
	await _wait_for_portrait(button)
	assert_str(button._shown_key).is_equal(saved.sha256_text())
	assert_str(Avatar.load_outfit().to_json_text()).is_equal(saved)
	assert_object(get_viewport().get_camera_3d()).is_equal(camera)

func test_hidden_scene_and_background_cancel_in_flight_portrait_then_resume_latest_outfit() -> void:
	var saved := Avatar.load_outfit().to_json_text()
	var camera := get_viewport().get_camera_3d()
	var scene := auto_free(Node3D.new()) as Node3D
	add_child(scene)
	var button := FocusButton.new()
	scene.add_child(button)
	_show_offscreen(button)
	await _wait_for_portrait(button)
	var alternate := _different_outfit()
	var key := alternate.to_json_text().sha256_text()
	FocusButton._cache.erase(key)
	button.set_outfit(alternate)
	# Start the asynchronous assembly before hiding the ancestor.
	button._render_portrait()
	assert_bool(button._rendering).is_true()
	assert_object(button._rig).is_not_null()
	var discarded: AvatarRig = button._rig
	scene.hide()
	_assert_idle_portrait(button)
	assert_bool(is_instance_valid(discarded)).is_false()
	for frame in 3: await get_tree().process_frame
	assert_bool(FocusButton._cache.has(key)).is_false()
	button.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	scene.show()
	Avatar.outfit_saved.emit(alternate)
	for frame in 3: await get_tree().process_frame
	_assert_idle_portrait(button)
	assert_bool(FocusButton._cache.has(key)).is_false()
	button.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await _wait_for_portrait(button)
	assert_str(button._shown_key).is_equal(key)
	_assert_idle_portrait(button)
	assert_str(Avatar.load_outfit().to_json_text()).is_equal(saved)
	assert_object(get_viewport().get_camera_3d()).is_equal(camera)

func test_indicator_is_hidden_inside_real_viewport_even_under_hud_and_for_modals() -> void:
	var button := auto_free(FocusButton.new()) as Button
	add_child(button)
	var screen := Rect2(0, 0, 400, 800)
	var allowed := Rect2(20, 120, 360, 580)
	assert_bool(button.visible).is_false()
	for point in [screen.get_center(), Vector2(2, 400), Vector2(200, 20), Vector2(398, 790)]:
		button.update_indicator(point, screen, allowed)
		assert_bool(button.visible).is_false()
		assert_bool(button._offscreen).is_false()
	button.update_indicator(Vector2(600, 400), screen, allowed)
	assert_bool(button.visible).is_true()
	button.update_indicator(Vector2(600, 400), screen, allowed, false, true)
	assert_bool(button.visible).is_false()
	button.update_indicator(screen.get_center(), screen, allowed)
	assert_bool(button.visible).is_false()

func test_cardinal_and_diagonal_indicators_intersect_the_inset_edge_and_point_outward() -> void:
	var button := auto_free(FocusButton.new()) as Button
	add_child(button)
	var screen := Rect2(0, 0, 400, 800)
	var allowed := Rect2(20, 120, 360, 580)
	var centers := [Vector2(348, 400), Vector2(52, 400), Vector2(200, 152), Vector2(200, 668)]
	var cardinal := [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	for index in cardinal.size():
		button.update_indicator(screen.get_center() + cardinal[index] * 1000, screen, allowed)
		assert_bool(button.visible).is_true()
		assert_vector(button.get_global_rect().get_center()).is_equal_approx(centers[index], Vector2.ONE * 0.01)
		assert_float(Vector2.RIGHT.rotated(button._direction_arrow.rotation).dot(cardinal[index])).is_greater(0.999)
	for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		button.update_indicator(screen.get_center() + direction * 1000, screen, allowed)
		var rect: Rect2 = button.get_global_rect()
		var offset := rect.get_center() - screen.get_center()
		assert_bool(allowed.encloses(rect)).is_true()
		assert_float(absf(offset.cross(direction.normalized()))).is_less(0.01)
		assert_float(Vector2.RIGHT.rotated(button._direction_arrow.rotation).dot(direction.normalized())).is_greater(0.999)
		assert_float(minf(rect.position.x - allowed.position.x, allowed.end.x - rect.end.x)).is_equal_approx(4, 0.01)
		assert_vector(rect.size).is_equal(Vector2(56, 56))
	# Nearby angles move continuously along the same edge, rather than snapping
	# between eight fixed screen locations.
	button.update_indicator(screen.get_center() + Vector2(1000, -490), screen, allowed)
	var before: Vector2 = button.global_position
	button.update_indicator(screen.get_center() + Vector2(1000, -500), screen, allowed)
	assert_float(button.global_position.distance_to(before)).is_greater(0.1)
	assert_float(button.global_position.distance_to(before)).is_less(3)

func test_indicator_repositions_for_resized_safe_area_and_handles_directly_behind_camera() -> void:
	var button := auto_free(FocusButton.new()) as Button
	add_child(button)
	button.update_indicator(Vector2(600, 400), Rect2(0, 0, 400, 800), Rect2(20, 120, 360, 580))
	var before: Vector2 = button.global_position
	var screen := Rect2(0, 0, 800, 400)
	var allowed := Rect2(44, 100, 700, 236)
	button.update_indicator(Vector2(1000, 200), screen, allowed)
	assert_bool(button.visible).is_true()
	assert_bool(allowed.encloses(button.get_global_rect())).is_true()
	assert_bool(button.global_position.is_equal_approx(before)).is_false()
	assert_float(button.get_global_rect().end.x).is_equal_approx(allowed.end.x - 4, 0.01)
	button.update_indicator(screen.get_center(), screen, allowed, true)
	assert_bool(button.visible).is_true()
	assert_bool(button.global_position.is_finite()).is_true()
	assert_bool(allowed.encloses(button.get_global_rect())).is_true()
	assert_float(Vector2.RIGHT.rotated(button._direction_arrow.rotation).dot(Vector2.DOWN)).is_greater(0.999)
	button.update_indicator(Vector2(INF, 0), screen, allowed, true)
	assert_bool(button.visible).is_false()
