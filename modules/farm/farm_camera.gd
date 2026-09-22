extends RefCounted

static func fit_ground_depth(camera: Camera3D, ground_y := -0.02, canopy_y := 4.0) -> void:
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL: return
	var forward := -camera.global_basis.z
	if forward.y >= -0.1: return
	var half := camera.get_camera_projection().get_viewport_half_extents()
	var vertical_span := absf(camera.global_basis.x.y) * half.x + absf(camera.global_basis.y.y) * half.y
	# Orthographic directional shadows ignore max_distance and use these clip planes.
	# Include the full visible ground and overhead canopy, even while panning/zooming.
	var closest := (camera.global_position.y - vertical_span - canopy_y) / -forward.y
	var furthest := (camera.global_position.y + vertical_span - ground_y) / -forward.y
	# Moving along the view axis preserves orthographic framing when a wide view
	# would otherwise put foreground treetops behind the near plane.
	var back := maxf(0.0, 1.0 - closest)
	camera.global_position -= forward * back
	closest += back
	furthest += back
	camera.near = maxf(0.05, floorf((closest - 0.5) * 2.0) * 0.5)
	camera.far = maxf(camera.near + 1.0, ceilf((furthest + 0.5) * 2.0) * 0.5)

static func fit(camera: Camera3D, bounds: AABB, area: Rect2, features := PackedVector3Array()) -> void:
	if area.size.x < 48 or area.size.y < 48:
		return
	var inverse := camera.global_transform.affine_inverse()
	var top_left := inverse * camera.project_position(area.position, 1.0)
	var bottom_right := inverse * camera.project_position(area.end, 1.0)
	# Project separate silhouettes so empty space above the foreground does not force a zoom-out.
	var corners := features.duplicate()
	for index in 8: corners.append(bounds.get_endpoint(index))
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for corner in corners:
			var point := inverse * corner
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
	for corner in corners:
		var point := inverse * corner
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

## The tracking box is centred in the full viewport. HUD clearance is mirrored
## across the opposite edge instead of moving the box toward the bottom.
static func symmetric_area(view: Vector2, visible: Rect2) -> Rect2:
	if visible.size.x < 48 or visible.size.y < 48:
		return Rect2(view * 0.3, view * 0.4)
	var margin := visible.position.max(view - visible.end).max(Vector2.ZERO)
	var size := (view - margin * 2).max(Vector2(48, 48))
	return Rect2((view - size) * 0.5, size)

static func follow_shift(camera: Camera3D, focus: Vector3, zone: Rect2) -> Vector3:
	var screen := camera.unproject_position(focus)
	var limited := screen.clamp(zone.position, zone.end)
	if screen.is_equal_approx(limited): return Vector3.ZERO
	# An off-screen orthographic origin may lie below the focus plane after a
	# teleport or large drag. Intersect the full line, including negative t.
	var normal_a := camera.project_ray_normal(screen)
	var normal_b := camera.project_ray_normal(limited)
	if absf(normal_a.y) < 0.0001 or absf(normal_b.y) < 0.0001: return Vector3.ZERO
	var a := camera.project_ray_origin(screen)
	var b := camera.project_ray_origin(limited)
	a += normal_a * ((focus.y - a.y) / normal_a.y)
	b += normal_b * ((focus.y - b.y) / normal_b.y)
	return a - b
