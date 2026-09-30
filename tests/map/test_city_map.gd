extends GdUnitTestSuite

func test_poi_categories_do_not_guess_cuisine_from_a_name() -> void:
	assert_str(CityMapData.art_key({"name":"China Cafe", "maki":"restaurant", "class":"food_and_drink"})).is_equal("restaurant")
	assert_str(CityMapData.art_key({"category":"Chinese restaurant", "maki":"restaurant"})).is_equal("chinese_restaurant")
	assert_str(CityMapData.art_key({"maki":"cafe"})).is_equal("cafe")
	assert_str(CityMapData.art_key({"class":"unknown"})).is_equal("place")

func test_poi_art_covers_more_provider_categories() -> void:
	assert_str(CityMapData.art_key({"maki":"fast-food"})).is_equal("restaurant")
	assert_str(CityMapData.art_key({"maki":"bar"})).is_equal("restaurant")
	assert_str(CityMapData.art_key({"maki":"ice-cream"})).is_equal("cafe")
	assert_str(CityMapData.art_key({"maki":"jewelry-store"})).is_equal("shop")
	assert_str(CityMapData.art_key({"maki":"attraction"})).is_equal("theme_park")
	assert_str(CityMapData.art_key({"maki":"art-gallery"})).is_equal("museum")
	assert_str(CityMapData.art_key({"maki":"zoo"})).is_equal("park")
	assert_str(CityMapData.art_key({"maki":"beach"})).is_equal("beach")
	assert_str(CityMapData.art_key({"class":"park_like"})).is_equal("park")
	assert_str(CityMapData.art_key({"class":"store_like"})).is_equal("shop")
	assert_str(CityMapData.art_key({"class":"food_and_drink_stores"})).is_equal("shop")

func test_provider_results_validate_coordinates_and_deduplicate() -> void:
	var good := {"id":"1", "name":"Park", "lat":34.1, "lng":-118.3, "maki":"park"}
	var points := CityMapData.normalize([good, good, {"id":"2", "name":"Invalid", "lat":99, "lng":2}, {"id":"3", "lat":0, "lng":0}, {"id":"4", "name":"Bad", "lat":"oops", "lng":1}])
	assert_int(points.size()).is_equal(1)
	assert_str(points[0].art).is_equal("park")
	assert_bool(points[0].has("address")).is_false()

func test_landmark_coordinates_are_independent_of_player_save() -> void:
	assert_array(CityMapData.landmarks("tokyo")).is_empty()
	for sh in CityMapData.landmarks("shanghai"):
		assert_float(float(sh.lat)).is_between(31.1, 31.35)
		assert_float(float(sh.lng)).is_between(121.35, 121.6)
		assert_bool(ResourceLoader.exists("res://assets/map/poi/%s.png" % sh.art)).override_failure_message("missing art " + str(sh.art)).is_true()
	assert_int(CityMapData.landmarks("shanghai").size()).is_equal(5)
	var points := CityMapData.landmarks("los_angeles")
	assert_int(points.size()).is_equal(5)
	for point in points:
		assert_float(float(point.lat)).is_between(33.9, 34.2)
		assert_float(float(point.lng)).is_between(-118.6, -118.2)
		assert_str(str(point.source)).starts_with("https://")

func test_residents_follow_existing_unlock_rules() -> void:
	assert_array(CityMapData.residents("los_angeles", {})).is_empty()
	assert_array(CityMapData.residents("tokyo", {"clock":{"chapter_index":0}})).is_empty()
	var state := {"clock":{"chapter_index":0}}
	var actual := CityMapData.residents("los_angeles", state).map(func(p): return str(p.id))
	var expected := []
	for place in ["nursery", "bistro", "courtyard"]: expected.append_array(ResidentCast.present(place, state))
	assert_array(actual).contains_exactly(expected)

func test_city_zoom_does_not_expand_relocation_or_change_home() -> void:
	FarmChoice.save("la_c", 2)
	FarmRegions.save_choice("los_angeles")
	Net.use_transport(FakeTransport.new([]).callable())
	var m := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	add_child(auto_free(m))
	await get_tree().process_frame
	assert_object(m.city_map).is_not_null()
	var saved := FarmChoice.load()
	var home := Vector2(m.home_lat, m.home_lng)
	m._set_zoom(10.7)
	assert_float(m.zoom).is_equal_approx(10.7, 0.01)
	m.city_map.focus_requested.emit(CityMapData.landmarks("los_angeles")[0])
	assert_vector(Vector2(m.home_lat, m.home_lng)).is_equal(home)
	assert_that(FarmChoice.load()).is_equal(saved)
	m._focus_own_farm(false)
	await get_tree().create_timer(0.65).timeout
	assert_float(m.center_lat).is_equal_approx(m.home_lat, 0.00001)
	assert_float(m.center_lng).is_equal_approx(m.home_lng, 0.00001)
	assert_int(m._pawns.filter(func(p): return p.cohort != "self").size()).is_equal(0)
	m.enter_relocation_mode(FarmRegions.load_default().region("los_angeles"))
	assert_object(m.city_map).is_null()
	assert_float(m._minimum_zoom()).is_equal(m.STREET_ZOOM_MIN)
	FarmChoice.clear()
	FarmRegions.clear_choice()

func test_place_card_fits_above_navigation_and_refreshed_list_keeps_ids() -> void:
	FarmChoice.save("la_c", 2)
	FarmRegions.save_choice("los_angeles")
	Net.use_transport(FakeTransport.new([]).callable())
	var m := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	add_child(auto_free(m))
	await get_tree().process_frame
	var city: CityMapView = m.city_map
	city.select(CityMapData.landmarks("los_angeles")[1])
	for frame in 5: await get_tree().process_frame
	assert_float(city.info.size.y).is_less(160)
	assert_float(city.info.get_rect().end.y).is_less_equal(city.dock.position.y)
	city._last_state = ""
	city.refresh_content()
	await get_tree().process_frame
	assert_object(city.list_rows.get_node_or_null("MapPlace_griffith_observatory")).is_not_null()
	assert_int(city.list_rows.get_child_count()).is_equal(5)
	FarmChoice.clear()
	FarmRegions.clear_choice()

func test_city_has_no_neighbour_list_or_jump_entry_at_any_size() -> void:
	FarmChoice.save("la_c", 2)
	FarmRegions.save_choice("los_angeles")
	Net.use_transport(FakeTransport.new([]).callable())
	var saved := FarmChoice.load()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 780)
	add_child(auto_free(viewport))
	var m := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	viewport.add_child(m)
	for viewport_size in [Vector2i(360,640), Vector2i(390,844), Vector2i(480,640), Vector2i(844,390)]:
		viewport.size = viewport_size
		for frame in 8: await get_tree().process_frame
		assert_object(m.nearby_panel).is_null()
		assert_array(m.find_children("MapNav_nearby", "", true, false)).is_empty()
		assert_array(m.find_children("NearbyToggle", "", true, false)).is_empty()
		m._set_nearby_open(true)
		assert_object(m.nearby_panel).is_null()
		m.city_map.select(CityMapData.landmarks("los_angeles")[0])
		assert_bool(m.city_map.info.visible).is_true()
		m.city_map._toggle_places()
		assert_bool(m.city_map.info.visible).is_false()
		assert_bool(m.city_map.list_panel.visible).is_true()
		m._city_action("map")
		assert_bool(m.city_map.list_panel.visible).is_false()
	assert_that(FarmChoice.load()).is_equal(saved)
	FarmChoice.clear()
	FarmRegions.clear_choice()

func test_shanghai_uses_the_same_city_map_framework() -> void:
	FarmChoice.save("sh_a", 2)
	FarmRegions.save_choice("shanghai")
	Net.use_transport(FakeTransport.new([]).callable())
	var m := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	add_child(auto_free(m))
	await get_tree().process_frame
	# 有城市配置就装城市地图，不再走旧的附近列表/旅程地图。
	assert_object(m.city_map).is_not_null()
	assert_object(m.nearby_panel).is_null()
	assert_str(m.city_map.get_node("MapCity").text).is_equal(L10n.text("Shanghai"))
	var ids: Array = m.city_map.entries.filter(func(e): return e.kind == "landmark").map(func(e): return str(e.id))
	assert_array(ids).contains(["oriental_pearl_tower", "the_bund", "yu_garden"])
	# 城市地图可无缝缩放到国家级、自由拖到任何地方：不钳平移范围；总览飞到上海市区。
	m._city_bounds()
	assert_that(m.pan_bounds).is_equal(Rect2())
	m._city_action("map")
	await get_tree().create_timer(0.7).timeout
	assert_float(m.center_lat).is_between(31.1, 31.35)
	assert_float(m.center_lng).is_between(121.35, 121.6)
	FarmChoice.clear()
	FarmRegions.clear_choice()

func _boot_la_map() -> Node:
	FarmChoice.save("la_c", 2)
	FarmRegions.save_choice("los_angeles")
	Net.use_transport(FakeTransport.new([]).callable())
	var m := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	add_child(auto_free(m))
	await get_tree().process_frame
	return m

## 2026-09-29 Joey 真机：在旧金山漫游一个地标都没有——地标只按激活 region（自己农场的城市）取。
## 现在地图中心 reach_km 内的设计地标随中心一起出现，本城地标照旧保留、不重复。
func test_landmarks_follow_the_map_center_beyond_the_active_city() -> void:
	var m := await _boot_la_map()
	var view: CityMapView = m.city_map
	view._last_state = ""
	view.refresh_content()
	var ids := view.entries.map(func(e): return str(e.id))
	assert_array(ids).contains(["hollywood_sign", "griffith_observatory"])
	assert_array(ids).not_contains(["golden_gate_bridge"])
	m.center_lat = 37.7749
	m.center_lng = -122.4194
	view.refresh_content()
	ids = view.entries.map(func(e): return str(e.id))
	assert_array(ids).contains(["hollywood_sign", "golden_gate_bridge", "alcatraz_island", "painted_ladies"])
	assert_int(ids.count("golden_gate_bridge")).is_equal(1)
	for e in view.entries:
		if str(e.id) == "golden_gate_bridge": assert_str(str(e.kind)).is_equal("landmark")
	m.center_lat = 34.0522
	m.center_lng = -118.2437
	view.refresh_content()
	assert_array(view.entries.map(func(e): return str(e.id))).not_contains(["golden_gate_bridge"])
	FarmChoice.clear()
	FarmRegions.clear_choice()

## 2026-09-29 用户真机：在纽约点博物馆，卡片写“博物馆 · 上海”——城市名一律取激活 region。
## 现在按地点坐标：本城 → 城市名；设计地标 → 素材表里的城市；未开通城市 → 标题栏瓦片地名；没地名只留类别。
func test_place_card_names_the_city_under_the_place() -> void:
	var m := await _boot_la_map()
	var view: CityMapView = m.city_map
	view.places = {"settlement": "New York"}
	view.select({"id": "poi:1", "kind": "poi", "name": "Fire Museum", "category": "Museum", "lat": 40.7128, "lng": -74.0060, "art": "museum"})
	assert_str(view.info_category.text).is_equal("Museum · New York")
	view.select({"id": "poi:2", "kind": "poi", "name": "Grand Central Market", "category": "Shop", "lat": 34.0508, "lng": -118.2489, "art": "shop"})
	assert_str(view.info_category.text).is_equal("Shop · Los Angeles")
	view.select({"id": "golden_gate_bridge", "kind": "landmark", "name": "Golden Gate Bridge", "category": "Bridge", "lat": 37.8199, "lng": -122.4783, "city": "San Francisco", "art": "landmarks/golden_gate_bridge"})
	assert_str(view.info_category.text).is_equal("Bridge · San Francisco")
	view.places = {}
	view.select({"id": "poi:3", "kind": "poi", "name": "Fire Museum", "category": "Museum", "lat": 40.7128, "lng": -74.0060, "art": "museum"})
	assert_str(view.info_category.text).is_equal("Museum")
	view.select_player({"id": "player:f1", "farm_id": "f1", "kind": "player", "name": "Sam", "lat": 40.7, "lng": -74.0}, null)
	assert_str(view.info_category.text).is_equal("Farm")
	view.places = {"settlement": "New York"}
	view.select_player({"id": "player:f1", "farm_id": "f1", "kind": "player", "name": "Sam", "lat": 40.7, "lng": -74.0}, null)
	assert_str(view.info_category.text).is_equal("Farm · New York")
	view.clear_selection()
	FarmChoice.clear()
	FarmRegions.clear_choice()

## 水塘目录按地图中心所在的 0.5° 网格取（3×3），不再按激活城市：从洛杉矶漫游到旧金山能看到旧金山的水塘。
func test_ponds_follow_the_map_center_by_cells() -> void:
	var m := await _boot_la_map()
	var view: CityMapView = m.city_map
	var sf := SystemPonds.accept({"id": "pond_san_francisco_01", "region_id": "gn-5391959", "name": "Willow Pond",
		"lat": 37.7695, "lng": -122.4863, "template_id": "gourd", "decoration_seed": 7, "layout_revision": 1, "enabled": true})
	view._pond_cells["75:-245"] = {"at": Time.get_ticks_msec(), "entries": [sf]}
	m.zoom = 12.0
	m.center_lat = 37.7749
	m.center_lng = -122.4194
	view._refresh_pond_directory()
	assert_array(view.entries.map(func(e): return str(e.id))).contains(["pond_san_francisco_01"])
	m.zoom = 6.0
	view._refresh_pond_directory()
	assert_array(view.pond_locations).is_empty()
	m.zoom = 12.0
	m.center_lat = 34.0522
	m.center_lng = -118.2437
	view._refresh_pond_directory()
	assert_array(view.entries.map(func(e): return str(e.id))).not_contains(["pond_san_francisco_01"])
	FarmChoice.clear()
	FarmRegions.clear_choice()
