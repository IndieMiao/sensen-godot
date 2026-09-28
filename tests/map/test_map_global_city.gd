extends GdUnitTestSuite
## 全球城市（SGODOT-136）：非精品城市也进入城市地图框架，镜头、标题、选址框都来自服务端城市数据。

const CACHE := "user://test_map_global_city_cache.json"
const TOKYO := {"id": "gn-1850147", "name": "Tokyo", "country": "Japan", "country_code": "JP", "timezone": "Asia/Tokyo",
	"center": [35.6895, 139.69171], "radius_km": 45, "curated": false, "placement_bounds": [35.2853, 139.1953, 36.0937, 140.1881]}
var _previous := ""

func before_test() -> void:
	_previous = FarmRegions.cache_path
	FarmRegions.cache_path = CACHE
	FarmChoice.clear()
	FarmRegions.remember_city(TOKYO)
	FarmRegions.save_choice("gn-1850147")

func after_test() -> void:
	FarmChoice.clear()
	FarmRegions.clear_choice()
	if FileAccess.file_exists(CACHE): DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE))
	FarmRegions.cache_path = _previous

func test_new_player_in_a_global_city_starts_placing_there() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	var m := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	add_child(auto_free(m))
	for frame in 3: await get_tree().process_frame
	assert_str(str(m.region.get("id", ""))).is_equal("gn-1850147")
	# Like curated cities, a player without a farm starts by choosing a spot; the city map follows the farm.
	assert_bool(m._placement_mode).is_true()
	assert_object(m.select_panel).is_not_null()
	assert_float(m.center_lat).is_between(35.2, 36.1)
	assert_float(m.center_lng).is_between(139.1, 140.2)
	assert_bool(FarmPlacement.generated_contains(m.region, {"lat": 35.68, "lng": 139.77})).is_true()
	assert_bool(FarmPlacement.generated_contains(m.region, {"lat": 34.69, "lng": 135.50})).is_false()
	assert_bool(m.city_regions().any(func(r): return str(r.id) == "gn-1850147")).is_true()
	assert_object(m.find_child("AccountButton", true, false)).is_not_null()

func test_guest_confirming_a_farm_meets_the_login_wall() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = "guest"
	var m := load("res://scenes/map_poc/map_poc.tscn").instantiate() as Node
	add_child(auto_free(m))
	for frame in 3: await get_tree().process_frame
	var pending := {"choice": null}
	var run := func(): pending.choice = await m._resolve_confirmed_farm("map_selection")
	run.call()
	await get_tree().process_frame
	var panel := m.find_children("*", "AccountPanel", true, false)
	assert_int(panel.size()).is_equal(1)
	assert_str((panel[0] as AccountPanel).mode).is_equal("sign_up")
	(panel[0] as AccountPanel).dismiss()
	for frame in 3: await get_tree().process_frame
	assert_that(pending.choice).is_equal({})
	assert_str(m.location_status.text).is_equal("Sign in to create your farm.")
