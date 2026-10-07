extends GdUnitTestSuite
## WorldAnchor: projection, edge clamping, occlusion and overlap avoidance (SGODOT-211).

func test_place_keeps_inside_markers_and_hides_or_clamps_outside_ones() -> void:
	var view := Rect2(0, 0, 360, 800)
	var inside := WorldAnchor.place(Vector2(100, 40), Vector2(180, 300), view, 6, false)
	assert_vector(inside.position).is_equal(Vector2(130, 260))
	assert_bool(WorldAnchor.place(Vector2(100, 40), Vector2(20, 300), view, 6, false).has_area()).is_false()
	var clamped := WorldAnchor.place(Vector2(100, 40), Vector2(20, 300), view, 6, true)
	assert_float(clamped.position.x).is_equal(6.0)

func test_lower_priority_marker_moves_above_the_higher_one() -> void:
	var a := Rect2(100, 300, 100, 40)
	var b := Rect2(120, 310, 100, 40)
	var out := WorldAnchor.resolve_overlaps([a, b], [0, 1], 4.0)
	assert_object(out[1]).is_equal(b)   # higher priority stays
	assert_float((out[0] as Rect2).end.y).is_less_equal(b.position.y - 4.0 + 0.001)

func test_projection_and_occlusion_with_a_real_camera() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 800)
	add_child(auto_free(vp))
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	var front := Node3D.new()
	vp.add_child(front)
	front.position = Vector3(0, 0, -5)
	var behind := Node3D.new()
	vp.add_child(behind)
	behind.position = Vector3(0, 0, 5)
	assert_bool(WorldAnchor.project(cam, behind.global_position).visible).is_false()
	var p: Dictionary = WorldAnchor.project(cam, front.global_position)
	assert_vector(p.pos).is_equal_approx(Vector2(180, 400), Vector2(0.5, 0.5))
	var layer := WorldAnchor.new()
	vp.add_child(layer)
	layer.camera = cam
	var marker := Label.new()
	marker.text = "Tap to cook"
	layer.track(marker, front)
	layer.update_now()
	assert_bool(marker.visible).is_true()
	assert_float(marker.position.y + marker.size.y).is_less_equal(400.0)
	layer.occluders = [Rect2(0, 300, 360, 500)]   # an open drawer covers the anchor point
	layer.update_now()
	assert_bool(marker.visible).is_false()
	layer.occluders = []
	layer.track(marker, behind)
	layer.update_now()
	assert_bool(marker.visible).is_false()
