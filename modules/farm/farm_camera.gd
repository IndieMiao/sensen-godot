extends RefCounted

static func fit(camera: Camera3D, bounds: AABB, area: Rect2) -> void:
	if area.size.x < 48 or area.size.y < 48:
		return
	var inverse := camera.global_transform.affine_inverse()
	var top_left := inverse * camera.project_position(area.position, 1.0)
	var bottom_right := inverse * camera.project_position(area.end, 1.0)
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for index in 8:
			var point := inverse * bounds.get_endpoint(index)
			low = low.min(Vector2(point.x, point.y))
			high = high.max(Vector2(point.x, point.y))
		var zoom_out := maxf(1, maxf((high.x - low.x) / (bottom_right.x - top_left.x),
			(high.y - low.y) / (top_left.y - bottom_right.y)))
		camera.size *= zoom_out
		var shift := Vector3(clampf(0, high.x - bottom_right.x * zoom_out, low.x - top_left.x * zoom_out),
			clampf(0, high.y - top_left.y * zoom_out, low.y - bottom_right.y * zoom_out), 0)
		camera.global_position += camera.global_basis * shift
		return
	var min_shift := Vector2(-INF, -INF)
	var max_shift := Vector2(INF, INF)
	# At depth d, each frustum edge is slope * d. Moving back widens both intervals;
	# their first intersection gives the least zoom-out, then the nearest translation.
	for index in 8:
		var point := inverse * bounds.get_endpoint(index)
		var depth := -point.z
		min_shift.x = maxf(min_shift.x, point.x - bottom_right.x * depth)
		max_shift.x = minf(max_shift.x, point.x - top_left.x * depth)
		min_shift.y = maxf(min_shift.y, point.y - top_left.y * depth)
		max_shift.y = minf(max_shift.y, point.y - bottom_right.y * depth)
	var back := maxf(0, maxf((min_shift.x - max_shift.x) / (bottom_right.x - top_left.x),
		(min_shift.y - max_shift.y) / (top_left.y - bottom_right.y)))
	var horizontal := clampf(0, min_shift.x - bottom_right.x * back, max_shift.x - top_left.x * back)
	var vertical := clampf(0, min_shift.y - top_left.y * back, max_shift.y - bottom_right.y * back)
	camera.global_position += camera.global_basis * Vector3(horizontal, vertical, back)
