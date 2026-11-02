extends GdUnitTestSuite
const MapPocScript = preload("res://scenes/map_poc/map_poc.gd")
## 地图首页无缝缩放到国家级 + 城市自动切换 + 城市跳转（spec 2026-09-23-map-seamless-zoom-city-switch）。

func before_test() -> void:
	FarmChoice.save("la_c", 2)
	FarmRegions.save_choice("los_angeles")
	Net.use_transport(FakeTransport.new([]).callable())

func after_test() -> void:
	FarmChoice.clear()
	FarmRegions.clear_choice()
	UiState.clear()

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(390, 844)
	add_child(auto_free(viewport))
	var map := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	viewport.add_child(map)
	return map

func _look(m: Node, lat: float, lng: float, z: float) -> void:
	m.center_lat = lat
	m.center_lng = lng
	m._set_zoom(z)
	m._update_cameras()

func test_mercator_reference_values() -> void:
	assert_float(MapGeoMath.mercator_x(0.0)).is_equal_approx(0.5, 1e-12)
	assert_float(MapGeoMath.mercator_y(0.0)).is_equal_approx(0.5, 1e-12)
	assert_float(MapGeoMath.mercator_y(85.051129)).is_equal_approx(0.0, 1e-6)
	assert_float(MapGeoMath.mercator_y(-85.051129)).is_equal_approx(1.0, 1e-6)

func test_flat_mercator_projection_matches_the_camera_near_center() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	m.center_lat = 34.05
	m.center_lng = -118.25
	m.zoom = 16.0
	m.bearing = 30.0
	m.pitch = 0.0
	m._update_cameras()
	# 东北 150m：精确 Mercator 与局部等距相机在城市尺度应重合（<1px）。
	var lat := 34.05 + 150.0 / MapGeoMath.M_PER_DEG_LAT
	var lng := -118.25 + 150.0 / (MapGeoMath.M_PER_DEG_LAT * cos(deg_to_rad(34.05)))
	var expected: Vector2 = m.cam.unproject_position(MapGeoMath.geo_to_world(lat, lng, m.anchor_lat, m.anchor_lng))
	assert_float((m.geo_to_screen(lat, lng) as Vector2).distance_to(expected)).is_less(1.0)
	# 中心永远落在视口正中。
	var center: Vector2 = m.geo_to_screen(34.05, -118.25)
	assert_float(center.distance_to(m.get_viewport().get_visible_rect().size * 0.5)).is_less(0.01)

func test_city_map_zooms_out_to_country_level_and_flattens() -> void:
	var m := _map()
	await get_tree().process_frame
	m.set_process(false)
	m._set_zoom(0.5)
	assert_float(m.zoom).is_equal(m.CITY_MIN_ZOOM)
	assert_float(m.pitch).is_equal(0.0)
	assert_bool(m.city_detail_visible()).is_false()
	m._set_zoom(9.5)
	assert_float(m.pitch).is_between(0.1, m.CITY_PITCH - 0.1)
	m._set_zoom(12.0)
	assert_float(m.pitch).is_equal(m.CITY_PITCH)
	assert_bool(m.city_detail_visible()).is_true()
	# 城市视角的旋转在国家级回正为正北朝上，放大回城市恢复。
	m._city_action("map")
	var city_bearing: float = m.city_bearing
	assert_float(absf(city_bearing)).is_greater(1.0)
	m._set_zoom(3.0)
	assert_float(m.bearing).is_equal(0.0)
	m._set_zoom(12.0)
	assert_float(m.bearing).is_equal_approx(city_bearing, 1e-6)
	# 城市地图不再钳平移：拖到上海也可以。
	_look(m, 31.23, 121.47, 12.0)
	assert_float(m.center_lat).is_equal_approx(31.23, 1e-9)
	assert_float(m.center_lng).is_equal_approx(121.47, 1e-9)

func test_country_view_shows_only_city_bubbles_and_own_portrait() -> void:
	var m := _map()
	for frame in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var la: Dictionary = CityMapData.city("los_angeles").overview
	_look(m, float(la.lat), float(la.lng), 3.0)
	m._update_city_detail()
	city._update_markers()
	city._update_bubbles()
	m._sync_farm_markers()
	assert_array(city.displayed).is_empty()
	assert_bool(city.bubbles.los_angeles.node.visible).is_true()
	# 上海在太平洋对岸，不在 z3 的视野里。
	assert_bool(city.bubbles.shanghai.node.visible).is_false()
	var fm: FarmMarkers = m.farm_markers
	assert_bool(fm.low_detail).is_true()
	assert_array(fm.visible_farm_ids).is_equal(["self"])
	# 自己用 2D 头像（不是 3D 全身）；3D 角色全部隐藏。
	assert_float(fm._avatar_targets.self.size.y).is_equal(44.0)
	for p in m._pawns: assert_bool((p.node as Node3D).visible).is_false()
	# 气泡挂在城市点正下方（精确 Mercator 投影）。
	var anchor: Vector2 = (m.geo_to_screen(float(la.lat), float(la.lng)) as Vector2) - city.global_position
	var node: Control = city.bubbles.los_angeles.node
	assert_float(node.position.x + node.size.x * 0.5).is_equal_approx(anchor.x, 0.5)
	assert_float(node.position.y).is_equal_approx(anchor.y + 6.0, 0.5)
	# 点气泡 = 请求飞往该城。
	var requested := []
	city.city_requested.connect(func(id): requested.append(id))
	assert_bool(city.activate_at(node.global_position + node.size * 0.5)).is_true()
	assert_array(requested).is_equal(["los_angeles"])

func test_city_at_uses_hysteresis_for_the_current_city() -> void:
	var regions: Array = FarmRegions.load_default().regions
	assert_str(MapPocScript.city_at(regions, 31.23, 121.47, "")).is_equal("shanghai")
	assert_str(MapPocScript.city_at(regions, 34.05, -118.25, "shanghai")).is_equal("los_angeles")
	assert_str(MapPocScript.city_at(regions, 0.0, 0.0, "")).is_equal("")
	# 洛杉矶 north=34.35：刚出界 0.02° 仍算当前城市，但不会因此被判进洛杉矶。
	assert_str(MapPocScript.city_at(regions, 34.37, -118.4, "los_angeles")).is_equal("los_angeles")
	assert_str(MapPocScript.city_at(regions, 34.37, -118.4, "")).is_equal("")

func test_dragging_into_another_city_switches_lightly_and_saves_choice() -> void:
	var m := _map()
	for frame in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	var cam_before := Vector3(31.23, 121.47, 11.0)
	_look(m, cam_before.x, cam_before.y, 11.0)
	# 低于切城门槛时不切。
	m._set_zoom(6.5)
	m._update_active_city(true)
	assert_str(str(m.region.id)).is_equal("los_angeles")
	m._set_zoom(11.0)
	m._update_active_city(true)
	assert_str(str(m.region.id)).is_equal("shanghai")
	assert_str(FarmRegions.load_choice()).is_equal("shanghai")
	# 相机不动，地标换成上海的，标题跟着换。
	assert_float(m.center_lat).is_equal(cam_before.x)
	assert_float(m.center_lng).is_equal(cam_before.y)
	assert_array(city.entries.filter(func(e): return e.kind == "landmark").map(func(e): return str(e.id))).contains(["oriental_pearl_tower"])
	city._update_header()
	assert_str(city.city_button.text).is_equal(L10n.text("Shanghai"))
	# 标题宽度要装得下整个城市名（真机曾只显示首字）。
	var font := city.city_button.get_theme_font("font")
	assert_float(city.city_button.size.x).is_greater(font.get_string_size(city.city_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x)
	# 自己的农场仍在（在洛杉矶），城市间切换不删除。
	assert_bool(m.farm_markers.points.has("self")).is_true()

func test_header_names_unopened_places_from_tiles() -> void:
	var places := {"country": "United States", "state": "Nevada", "settlement": "Las Vegas"}
	assert_array(CityMapView.header_for(true, "Los Angeles", 12.0, places)).is_equal([L10n.text("Los Angeles"), "Los Angeles"])
	assert_array(CityMapView.header_for(false, "Los Angeles", 10.0, places)).is_equal(["Las Vegas", L10n.text("No farms here yet")])
	assert_array(CityMapView.header_for(false, "Los Angeles", 5.0, places)).is_equal(["Nevada", L10n.text("Zoom in to explore")])
	assert_array(CityMapView.header_for(false, "Los Angeles", 2.5, places)).is_equal(["United States", L10n.text("Zoom in to explore")])
	# 城市名缺失时退到省州/国家；毫无数据（iOS/桌面）显示 Explore。
	assert_array(CityMapView.header_for(false, "Los Angeles", 10.0, {"country": "China"})).is_equal(["China", L10n.text("No farms here yet")])
	assert_str(str(CityMapView.header_for(false, "Los Angeles", 10.0, {})[0])).is_equal(L10n.text("Explore"))

func test_leaving_the_city_updates_the_header_but_keeps_city_content() -> void:
	var m := _map()
	for frame in 3: await get_tree().process_frame
	m.set_process(false)
	var city: CityMapView = m.city_map
	city.places = {"settlement": "Las Vegas", "state": "Nevada", "country": "United States"}
	_look(m, 36.17, -115.14, 11.0)
	m._update_active_city(true)
	city._update_header()
	assert_str(str(m.region.id)).is_equal("los_angeles")
	assert_str(city.city_button.text).is_equal("Las Vegas")
	assert_str(city.subtitle.text).is_equal(L10n.text("No farms here yet"))

func test_flight_zooms_out_between_distant_cities_and_lands_exactly() -> void:
	var f := MapFlight.plan(34.05, -118.25, 12.0, 31.23, 121.47, 12.2, 360.0)
	var start := f.sample(0.0)
	assert_float(start.x).is_equal_approx(34.05, 1e-4)
	assert_float(start.y).is_equal_approx(-118.25, 1e-4)
	assert_float(start.z).is_equal_approx(12.0, 1e-4)
	var mid := f.sample(0.5)
	assert_float(mid.z).is_less(5.0)
	# 最短方向跨日界线（太平洋），不绕过大西洋。
	assert_bool(mid.y > 121.47 or mid.y < -118.25).is_true()
	var end := f.sample(1.0)
	assert_float(end.x).is_equal_approx(31.23, 1e-4)
	assert_float(end.y).is_equal_approx(121.47, 1e-4)
	assert_float(end.z).is_equal_approx(12.2, 1e-4)
	assert_float(f.duration()).is_between(MapFlight.MIN_DURATION, MapFlight.MAX_DURATION)
	# 同点只改 zoom 也要平滑（退化路径）。
	var zoom_only := MapFlight.plan(31.0, 121.0, 12.0, 31.0, 121.0, 6.0, 360.0)
	assert_float(zoom_only.sample(0.5).z).is_between(6.0, 12.0)
	assert_float(zoom_only.sample(1.0).z).is_equal_approx(6.0, 1e-4)

func test_city_panel_lists_open_cities_and_flies_there() -> void:
	var m := _map()
	for frame in 3: await get_tree().process_frame
	var city: CityMapView = m.city_map
	m._city_action("city")
	assert_bool(city.city_panel.visible).is_true()
	var row := city.city_rows.get_node_or_null("MapCityRow_shanghai") as Button
	assert_object(row).is_not_null()
	assert_object(city.city_rows.get_node_or_null("MapCityRow_los_angeles")).is_not_null()
	assert_bool(city.consume_back()).is_true()
	assert_bool(city.city_panel.visible).is_false()
	m._city_action("city")
	row = city.city_rows.get_node_or_null("MapCityRow_shanghai") as Button
	row.pressed.emit()
	assert_bool(city.city_panel.visible).is_false()
	assert_str(str(m.region.id)).is_equal("shanghai")
	var overview: Dictionary = CityMapData.city("shanghai").overview
	await get_tree().create_timer(MapFlight.MAX_DURATION + 0.3).timeout
	assert_float(m.center_lat).is_equal_approx(float(overview.lat), 1e-6)
	assert_float(m.center_lng).is_equal_approx(float(overview.lng), 1e-6)
	assert_float(m.zoom).is_equal_approx(float(overview.zoom), 1e-3)
	assert_float(m.bearing).is_equal_approx(float(overview.bearing), 1e-3)
	assert_str(FarmRegions.load_choice()).is_equal("shanghai")

func test_geocoder_parses_containing_places_and_shortens_country_names() -> void:
	var body := JSON.stringify({"features": [
		{"properties": {"feature_type": "place", "name": "Los Angeles"}},
		{"properties": {"feature_type": "region", "name": "California"}},
		{"properties": {"feature_type": "country", "name": "United States", "context": {"country": {"country_code": "US"}}}}]})
	assert_dict(PlaceGeocoder.parse(body, false)).is_equal({"settlement": "Los Angeles", "state": "California", "country": "United States"})
	var china := JSON.stringify({"features": [
		{"properties": {"feature_type": "place", "name": "北京市"}},
		{"properties": {"feature_type": "country", "name": "中华人民共和国", "context": {"country": {"country_code": "CN"}}}}]})
	assert_dict(PlaceGeocoder.parse(china, true)).is_equal({"settlement": "北京市", "country": "中国"})
	# 海上没有结果；坏数据不崩。
	assert_dict(PlaceGeocoder.parse('{"features":[]}', false)).is_empty()
	assert_dict(PlaceGeocoder.parse("not json", false)).is_empty()

func test_geocoder_cells_coarsen_with_zoom() -> void:
	# 城市档 0.05° 内移动命中同一格，国家档 2° 内也是。
	assert_str(PlaceGeocoder.cell_key(34.051, -118.241, 12.0, "en")).is_equal(PlaceGeocoder.cell_key(34.049, -118.239, 12.0, "en"))
	assert_str(PlaceGeocoder.cell_key(34.0, -118.0, 12.0, "en")).is_not_equal(PlaceGeocoder.cell_key(34.2, -118.0, 12.0, "en"))
	assert_str(PlaceGeocoder.cell_key(34.0, -118.0, 3.0, "en")).is_equal(PlaceGeocoder.cell_key(34.6, -118.6, 3.0, "en"))
	assert_str(PlaceGeocoder.cell_key(34.0, -118.0, 3.0, "zh_CN")).ends_with("|zh")
