extends GdUnitTestSuite
## 全国地标（设计部门 Figma Landmark_icons，2026-09-29）：任何城市按地图中心 reach_km 显示。

func _ids(list: Array) -> Array:
	return list.map(func(p): return str(p.id))

func test_catalog_has_art_names_and_valid_coordinates() -> void:
	var all := CityMapData.global_landmarks()
	assert_int(all.size()).is_equal(47)
	for g in all:
		assert_bool(ResourceLoader.exists("res://assets/map/poi/" + str(g.art) + ".png")).override_failure_message(str(g.id)).is_true()
		assert_str(str(g.name)).is_not_empty()
		assert_str(str(g.zh)).is_not_empty()
		assert_float(float(g.lat)).is_between(20.0, 50.0)
		assert_float(float(g.lng)).is_between(-125.0, -66.0)

func test_san_francisco_shows_its_four_landmarks() -> void:
	var sf := _ids(CityMapData.landmarks_near(37.7749, -122.4194))
	assert_array(sf).contains(["golden_gate_bridge", "fishermans_wharf", "alcatraz_island", "painted_ladies"])
	assert_array(sf).not_contains(["space_needle", "grand_canyon"])

func test_city_sights_stay_local_while_parks_reach_nearby_towns() -> void:
	var nyc := _ids(CityMapData.landmarks_near(40.7128, -74.0060))
	assert_array(nyc).contains(["statue_of_liberty", "times_square", "brooklyn_bridge"])
	assert_array(nyc).not_contains(["liberty_bell", "independence_hall"])
	# Flagstaff is ~110 km from the South Rim.
	assert_array(_ids(CityMapData.landmarks_near(35.1983, -111.6513))).contains(["grand_canyon"])

func test_los_angeles_keeps_its_own_landmarks_without_duplicates() -> void:
	var la := CityMapData.landmarks("los_angeles")
	var ids := _ids(la)
	assert_array(ids).contains(["hollywood_sign", "griffith_observatory"])
	for id in ids: assert_int(ids.count(id)).is_equal(1)
	for p in la: assert_str(str(p.kind)).is_equal("landmark")

func test_distance_is_roughly_right() -> void:
	# San Francisco to Oakland is about 13 km.
	assert_float(CityMapData.distance_km(37.7749, -122.4194, 37.8044, -122.2712)).is_between(12.0, 15.0)
