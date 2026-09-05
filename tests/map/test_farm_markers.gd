extends GdUnitTestSuite

func test_overlapping_owners_form_a_selectable_cluster_with_one_avatar() -> void:
	var camera := Camera3D.new()
	add_child(auto_free(camera))
	camera.position = Vector3(0, 500, 500)
	camera.look_at(Vector3.ZERO)
	var markers := FarmMarkers.new()
	add_child(auto_free(markers))
	var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2))
	for id in ["self", "a", "b"]:
		markers.put(id, bp, id, id == "self")
	var area := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	markers.sync(camera, bp.overlay.center.x, bp.overlay.center.y, area)
	assert_array(markers.visible_farm_ids).is_equal(["self"])
	assert_int(markers._clusters.self.size()).is_equal(3)
	assert_bool(markers._badges.self.visible).is_true()
	var seen := []
	markers.cluster_focused.connect(func(ids): seen.assign(ids))
	markers._badges.self.pressed.emit()
	assert_array(seen).contains(["self", "a", "b"])
	markers.selected_id = "b"
	markers.sync(camera, bp.overlay.center.x, bp.overlay.center.y, area)
	assert_array(markers.visible_farm_ids).is_equal(["b"])
	assert_bool(markers._show_ring).is_true()
	assert_int(markers.points.size()).is_equal(3)

func test_cluster_filter_keeps_all_farms_and_each_card_identity() -> void:
	var panel := NearbyPanel.new()
	add_child(auto_free(panel))
	panel.set_entries([
		{"farm_id": "a", "avatar_ref": "preset_a"},
		{"farm_id": "b", "avatar_ref": "preset_b"},
		{"farm_id": "c", "avatar_ref": "seed:cccc"}], 3)
	panel.show_group(["a", "b"])
	assert_int(panel.cards().filter(func(card): return card.visible).size()).is_equal(2)
	panel.cards()[1].pressed.emit()
	assert_str(panel.focused_id).is_equal("b")
	panel._group_back.pressed.emit()
	assert_int(panel.cards().filter(func(card): return card.visible).size()).is_equal(3)
	assert_str(panel.focused_id).is_equal("b")
