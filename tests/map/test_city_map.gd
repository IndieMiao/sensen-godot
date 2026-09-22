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
	assert_array(CityMapData.landmarks("shanghai")).is_empty()
	var points := CityMapData.landmarks("los_angeles")
	assert_int(points.size()).is_equal(5)
	for point in points:
		assert_float(float(point.lat)).is_between(33.9, 34.2)
		assert_float(float(point.lng)).is_between(-118.6, -118.2)
		assert_str(str(point.source)).starts_with("https://")

func test_residents_follow_existing_unlock_rules() -> void:
	assert_array(CityMapData.residents("los_angeles", {})).is_empty()
	assert_array(CityMapData.residents("shanghai", {"clock":{"chapter_index":6}})).is_empty()
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
