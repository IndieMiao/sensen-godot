extends GdUnitTestSuite
## 不知火舞's stick-slide spec v1 on a landmark's navigation (P0LandmarkVisit.slide_on, 恶魔岛 / 格里菲斯): a step off
## its edge slides along it at sin θ, square-on it stops, a corner stops it still, an edge's end close by is stepped
## round, a slope is not an edge.

const P0LandmarkVisit := preload("res://modules/p0/p0_landmark_visit.gd")

var _maps: Array[RID] = []

func after_test() -> void:
	for m in _maps: NavigationServer3D.free_rid(m)
	_maps.clear()

## A navigation of `polys` (each a list of x, z corners, counter-clockwise from above; `heights` the y of a vertex by
## its index, 0 when not given), synced.
func _nav(polys: Array, heights := {}) -> RID:
	var mesh := NavigationMesh.new()
	var verts := PackedVector3Array()
	for poly in polys:
		var idx := PackedInt32Array()
		for c in poly:
			idx.append(verts.size())
			verts.append(Vector3(c.x, float(heights.get(verts.size(), 0.0)), c.y))
		idx.reverse()   # Godot's navigation polygons wind clockwise seen from above
		mesh.add_polygon(idx)
	mesh.vertices = verts
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(map, mesh.cell_height)
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, mesh)
	_maps.append(region)
	_maps.append(map)
	return map

func _square() -> RID:
	return _nav([[Vector2(0, 0), Vector2(0, 10), Vector2(10, 10), Vector2(10, 0)]])

## Until the region is in the map (a sync or two after it is set): a point on it is its own nearest.
func _synced(map: RID, inside := Vector3(2, 0, 2)) -> void:
	for i in 120:
		if NavigationServer3D.map_get_closest_point(map, inside).distance_to(inside) < 0.01: return
		await get_tree().process_frame
	fail("the navigation never synced")

## A step of `length` at `deg` off square-on into the north edge (z = 0), turned toward +x.
func _into_north(deg: float, length := 0.1) -> Vector3:
	return Vector3(sin(deg_to_rad(deg)), 0.0, -cos(deg_to_rad(deg))) * length

func test_off_an_edge_it_slides_at_sin_theta_and_stops_square_on() -> void:
	var map := _square()
	await _synced(map)
	var p := Vector3(5, 0, 0.02)
	for theta in [30.0, 60.0, 89.0]:
		var to: Vector3 = P0LandmarkVisit.slide_on(map, p, _into_north(theta))
		var why := "theta %d" % theta
		assert_float(Vector2(to.x - p.x, to.z - p.z).length()).override_failure_message(why).is_equal_approx(0.1 * sin(deg_to_rad(theta)), 0.004)
		assert_float(to.x - p.x).override_failure_message(why).is_greater(0.0)   # along it, the way the push leans
		assert_float(to.z).override_failure_message(why).is_greater_equal(0.0)
	assert_vector(P0LandmarkVisit.slide_on(map, p, _into_north(10.0))).is_equal(p)   # square-on: stays, no snap

## Into a corner of the square, square-on and at a slant: once there, it stays where it is.
func test_a_corner_stops_it_still() -> void:
	var map := _square()
	await _synced(map)
	for deg in [0.0, 20.0, -25.0]:
		var p := Vector3(0.6, 0, 0.6)
		var want := Vector3(-1, 0, -1).normalized().rotated(Vector3.UP, deg_to_rad(deg)) * 0.06
		for i in 60: p = P0LandmarkVisit.slide_on(map, p, want)
		var still := p
		for i in 60: p = P0LandmarkVisit.slide_on(map, p, want)
		assert_float(still.distance_to(p)).override_failure_message("%d°" % deg).is_less(0.01)

## An edge's end (an L: the square and a strip north of its west half, x 0–4): pushed square-on into the square's north
## edge within 0.25 m of where the strip opens, it steps round into the strip; half a metre off, it stays.
func test_an_edges_end_close_by_is_stepped_round() -> void:
	var map := _nav([[Vector2(0, 0), Vector2(0, 10), Vector2(10, 10), Vector2(10, 0)],
		[Vector2(0, -6), Vector2(0, 0), Vector2(4, 0), Vector2(4, -6)]])
	await _synced(map)
	var p := Vector3(4.2, 0, 0.01)
	for i in 120: p = P0LandmarkVisit.slide_on(map, p, Vector3(0, 0, -0.06))
	assert_float(p.z).is_less(-0.5)   # round the end, on up the strip
	p = Vector3(4.5, 0, 0.01)
	var from := p
	for i in 60: p = P0LandmarkVisit.slide_on(map, p, Vector3(0, 0, -0.06))
	assert_float(from.distance_to(p)).is_less(0.01)

## A slope (y 0 at z 10 up to 5 at z 0) is ground, not an edge: a step up it goes the whole way, at its height.
func test_a_slope_is_not_an_edge() -> void:
	var map := _nav([[Vector2(0, 0), Vector2(0, 10), Vector2(10, 10), Vector2(10, 0)]], {0: 5.0, 3: 5.0})
	await _synced(map, Vector3(5, 2.5, 5))
	var p := NavigationServer3D.map_get_closest_point(map, Vector3(5, 2.5, 5))
	var to: Vector3 = P0LandmarkVisit.slide_on(map, p, Vector3(0, 0, -0.1))
	assert_float(Vector2(to.x - p.x, to.z - p.z).length()).is_equal_approx(0.1, 0.002)
	assert_float(to.y).is_greater(p.y)
