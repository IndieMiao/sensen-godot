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
	assert_bool(markers.miniature.visible).is_false()
	var hidden_events := []
	markers._badges.self.visibility_changed.connect(func(): hidden_events.append(true))
	markers.sync(camera, bp.overlay.center.x, bp.overlay.center.y, area)
	assert_array(hidden_events).is_empty()
	var seen := []
	markers.cluster_focused.connect(func(ids): seen.assign(ids))
	markers._badges.self.pressed.emit()
	assert_array(seen).contains(["self", "a", "b"])
	markers.sync(camera, bp.overlay.center.x, bp.overlay.center.y, area)
	assert_int(markers.visible_farm_ids.size()).is_equal(3)
	assert_float(markers._avatar_targets.a.position.distance_to(markers._avatar_targets.b.position)).is_greater(70)
	markers._badges.self.pressed.emit()
	markers.selected_id = "b"
	markers.sync(camera, bp.overlay.center.x, bp.overlay.center.y, area)
	assert_array(markers.visible_farm_ids).is_equal(["b"])
	assert_bool(markers._show_ring).is_true()
	assert_int(markers.points.size()).is_equal(3)
	assert_int(markers.get_children().filter(func(node): return node is SubViewportContainer).size()).is_equal(0)
	assert_bool(markers.miniature is Node3D).is_true()
	assert_str(markers.miniature._key).is_equal("cottage:9")
	markers.selected_id = ""
	assert_bool(markers.miniature.visible).is_false()
	assert_bool(markers._show_ring).is_false()
	markers.sync(camera, bp.overlay.center.x, bp.overlay.center.y, area)
	assert_bool(markers.miniature.visible).is_false()

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

func test_selected_farm_stays_to_the_right_and_within_map_bounds() -> void:
	var markers := auto_free(FarmMarkers.new()) as FarmMarkers
	for size in [Vector2(320, 350), Vector2(390, 600), Vector2(960, 500)]:
		var area := Rect2(Vector2(12, 110), size)
		for requested in [area.position, area.get_center(), area.end, Vector2(area.end.x, area.get_center().y)]:
			var owner := markers._selected_layout_anchor(requested, area)
			var farm := owner + FarmMarkers.MINIATURE_OFFSET
			assert_float(farm.x - FarmMarkers.MINIATURE_HALF_WIDTH).is_greater(owner.x + 44)
			assert_float(farm.x + FarmMarkers.MINIATURE_HALF_WIDTH).is_less_equal(area.end.x)
			assert_float(farm.y - 62).is_greater_equal(area.position.y)
			assert_float(farm.y + 24).is_less_equal(area.end.y)
	assert_float(FarmMarkers.MINIATURE_SCALE).is_equal(0.195)

func test_right_side_preview_avoids_a_neighbour_name_by_moving_vertically() -> void:
	var markers := auto_free(FarmMarkers.new()) as FarmMarkers
	markers._clusters = {"self": ["self"], "neighbour": ["neighbour"]}
	var owner := Vector2(180, 360)
	var neighbour := owner + Vector2(156, -45)
	var area := Rect2(0, 110, 390, 500)
	var preview := markers._model_anchor(owner, {"self": owner, "neighbour": neighbour}, area)
	assert_float(preview.x).is_equal(owner.x + FarmMarkers.MINIATURE_OFFSET.x)
	var bounds := Rect2(preview - Vector2(54, 62), Vector2(108, 86))
	assert_bool(bounds.intersects(Rect2(neighbour - Vector2(44, 100), Vector2(88, 144)))).is_false()
