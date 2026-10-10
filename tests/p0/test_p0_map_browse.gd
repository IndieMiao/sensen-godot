extends GdUnitTestSuite
## SGODOT-275 (plan v2 §11.8.1, Browse): every city cluster can be browsed on the P0 map. Its bubble shows at the
## country zoom (the large cities only, kept apart), a bubble flies the camera there, and the camera city follows the
## camera over any cluster. Browsing moves only the camera: where the player is, the homestead and the old app's saved
## city choice stay as they were (LOCK-06: the place chip writes where the player actually is).

const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Map := preload("res://scenes/p0/p0_map.gd")
const SF := "gn-5391959"
const TOKYO := "gn-1850147"

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}

func after_test() -> void:
	for key in WaterShore._pending.keys(): WorkerThreadPool.wait_for_task_completion(WaterShore._pending[key])
	WaterShore._pending.clear()

func after() -> void:
	P0Runtime.free_instance_for_tests()

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var map := (load(P0_MAP) as PackedScene).instantiate() as Node
	viewport.add_child(map)
	return map

func _look(m: Node, lat: float, lng: float, z: float) -> void:
	m.center_lat = lat
	m.center_lng = lng
	m._set_zoom(z)
	m.pitch = 0.0
	m._zoom_elastic = 0.0

func _choice() -> String:
	return FileAccess.get_file_as_string(FarmRegions.CHOICE_PATH) if FileAccess.file_exists(FarmRegions.CHOICE_PATH) else ""

func test_clusters_are_map_regions_and_curated_cities_keep_theirs() -> void:
	assert_str(P0Clusters.cluster_of_region("san_francisco")).is_equal(SF)
	assert_str(P0Clusters.cluster_of_region(TOKYO)).is_equal(TOKYO)
	assert_str(P0Clusters.cluster_of_region("nowhere")).is_empty()
	assert_str(str(P0Clusters.region(SF).id)).is_equal("san_francisco")   # the curated region, its own city file
	var tokyo := P0Clusters.region(TOKYO)
	assert_str(str(tokyo.name)).is_equal("Tokyo")
	assert_float(float(tokyo.radius_km)).is_equal(45.0)
	var b: Array = tokyo.placement_bounds
	assert_bool(float(b[0]) < 35.68 and float(b[2]) > 35.68 and float(b[1]) < 139.69 and float(b[3]) > 139.69).is_true()
	assert_int(P0Map.city_min_population(2.0)).is_greater(P0Map.city_min_population(5.0))
	assert_int(P0Map.city_min_population(7.5)).is_equal(0)

func test_the_country_zoom_shows_large_cities_apart_and_any_of_them_is_a_city() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	_look(m, 36.0, 138.0, 4.5)   # over Japan
	var ids: Array = m.city_regions().map(func(r): return str(r.id))
	assert_array(ids).contains(["san_francisco", TOKYO])
	assert_int(ids.size()).is_less_equal(P0Map.CITY_BUBBLES)
	assert_bool(CityMapData.has_city(TOKYO)).is_true()
	assert_float(float(CityMapData.city(TOKYO).overview.lat)).is_equal_approx(35.6895, 0.01)
	var shown: Array = []
	for r in m.city_regions():
		if str(r.id) == "san_francisco" or str(r.id) == str(m.region.get("id", "")): continue
		var p = m.geo_to_screen(float(r.center[0]), float(r.center[1]))
		for q in shown: assert_float((p as Vector2).distance_to(q)).is_greater_equal(P0Map.BUBBLE_GAP)
		shown.append(p)
	assert_int(shown.size()).is_greater(3)

func test_another_citys_bubble_browses_there_and_moves_only_the_camera() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var rt: P0Runtime = m.rt
	var here: Dictionary = rt.here.duplicate()
	var choice := _choice()
	var home := Vector2(m.home_lat, m.home_lng)
	rt.ui.clear_toast()
	m.fly_to_city("los_angeles")
	assert_str(str(m.region.get("id", ""))).is_equal("los_angeles")
	assert_str(rt.ui.toast_text()).is_empty()        # no more "P0 is set in San Francisco"
	assert_dict(rt.here).is_equal(here)              # the player has not moved
	assert_str(_choice()).is_equal(choice)           # the old app's saved city is not written
	assert_float(float(m.home_lat)).is_equal(home.x)
	assert_float(float(m.home_lng)).is_equal(home.y)

func test_the_camera_city_follows_the_camera_over_any_cluster() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var here: Dictionary = (m.rt as P0Runtime).here.duplicate()
	var choice := _choice()
	_look(m, 35.68, 139.69, 9.5)   # Tokyo, past the camera-city zoom
	m._update_active_city(true)
	assert_str(str(m.region.get("id", ""))).is_equal(TOKYO)
	assert_bool(m.in_active_city()).is_true()
	assert_dict((m.rt as P0Runtime).here).is_equal(here)
	assert_str(_choice()).is_equal(choice)
	_look(m, 37.7558, -122.4345, 12.0)   # back home
	m._update_active_city(true)
	assert_str(str(m.region.get("id", ""))).is_equal("san_francisco")

func test_leaving_the_map_hands_journey_its_cities_back() -> void:
	var m := _map()
	for i in 2: await get_tree().process_frame
	assert_bool(CityMapData.region_provider.is_valid()).is_true()
	m.get_parent().remove_child(m)
	m.queue_free()
	await get_tree().process_frame
	assert_bool(CityMapData.region_provider.is_valid()).is_false()
	assert_bool(CityMapData.has_city(TOKYO)).is_false()   # Journey's own cities only (its server cache)
