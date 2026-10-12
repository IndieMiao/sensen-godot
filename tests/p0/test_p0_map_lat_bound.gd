extends GdUnitTestSuite
## 李元芳 on 286 14c60178 (0.2.2): dragged north at the world view, the map stopped but the city bubbles went on south
## (London's point in Algeria), then off the screen. Mapbox keeps the world's top and bottom edges on the screen (its
## default HEIGHT_ONLY constraint, at z 2 about 73°); the map's centre stops there too, so what is drawn from it stays
## on the map, and a drag back moves it at once.

const P0_MAP := "res://scenes/p0/p0_map.tscn"

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var map := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(map)
	return map

## The screen y of the world's top edge (85.05°N) on the map's flat projection.
func _top_edge_y(m: Node) -> float:
	return (m.geo_to_screen(85.051129, m.center_lng) as Vector2).y

func test_dragging_north_at_the_world_view_stops_where_the_worlds_edge_meets_the_screen() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	m.center_lat = 40.0
	m.center_lng = 0.0
	m._set_zoom(2.0)
	m.pitch = 0.0
	for i in 40: m._apply_world_delta(Vector3(0, 0, -200000.0))   # far north, 8000 km
	assert_float(m.center_lat).is_less(80.0)
	assert_float(absf(_top_edge_y(m))).is_less(1.0)   # the edge sits on the screen's top, as Mapbox stops it
	var stopped: float = m.center_lat
	m._apply_world_delta(Vector3(0, 0, 50000.0))   # a drag back moves it at once
	assert_float(m.center_lat).is_less(stopped - 0.1)

func test_zooming_out_by_the_pole_moves_the_centre_off_the_edge() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	m.center_lat = 80.0
	m.center_lng = 0.0
	m._set_zoom(8.0)
	assert_float(m.center_lat).is_equal_approx(80.0, 1e-6)   # close in, 80° is on the map
	m._set_zoom(2.0)
	m.pitch = 0.0
	assert_float(m.center_lat).is_less(80.0)
	assert_float(_top_edge_y(m)).is_greater_equal(-1.0)
	assert_float(_top_edge_y(m)).is_less(1.0)
	# and in the south the same
	m.center_lat = -84.0
	m._update_cameras()
	assert_float((m.geo_to_screen(-85.051129, 0.0) as Vector2).y).is_less_equal(801.0)
	assert_float((m.geo_to_screen(-85.051129, 0.0) as Vector2).y).is_greater(799.0)
