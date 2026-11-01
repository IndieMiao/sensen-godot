extends GdUnitTestSuite
## 全球城市缓存（SGODOT-136）：服务端城市进入 FarmRegions，地图拿得到它的城市配置。

const CACHE := "user://test_city_cache.json"
const TOKYO := {"id": "gn-1850147", "name": "Tokyo", "country": "Japan", "country_code": "JP", "timezone": "Asia/Tokyo",
	"center": [35.6895, 139.69171], "radius_km": 45, "curated": false, "placement_bounds": [35.2853, 139.1953, 36.0937, 140.1881]}

var _previous := ""

func before_test() -> void:
	_previous = FarmRegions.cache_path
	FarmRegions.cache_path = CACHE
	if FileAccess.file_exists(CACHE): DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE))

func after_test() -> void:
	if FileAccess.file_exists(CACHE): DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE))
	FarmRegions.cache_path = _previous

func test_test_processes_do_not_read_the_device_cache_by_default() -> void:
	assert_str(_previous).is_empty()

func test_remembered_city_joins_the_region_directory() -> void:
	var region := FarmRegions.remember_city(TOKYO)
	assert_str(region.id).is_equal("gn-1850147")
	assert_bool(region.candidates.is_empty()).is_true()
	var regions := FarmRegions.load_default()
	assert_str(regions.region("gn-1850147").get("name", "")).is_equal("Tokyo")
	assert_str(regions.region("gn-1850147").timezone).is_equal("Asia/Tokyo")
	assert_bool(regions.region("shanghai").is_empty()).is_false()
	# Remembering again does not duplicate; curated cities never enter the cache.
	FarmRegions.remember_city(TOKYO)
	FarmRegions.remember_city({"id": "shanghai", "name": "Shanghai", "center": [31.2, 121.4], "placement_bounds": [30.67, 120.86, 31.9, 122.2]})
	assert_int(FarmRegions.cached_cities().size()).is_equal(1)

func test_malformed_city_is_ignored() -> void:
	assert_bool(FarmRegions.remember_city({"id": "gn-1", "name": "Nowhere"}).is_empty()).is_true()
	assert_int(FarmRegions.cached_cities().size()).is_equal(0)

func test_global_city_gets_a_generated_city_map_with_residents() -> void:
	assert_bool(CityMapData.has_city("gn-1850147")).is_false()
	FarmRegions.remember_city(TOKYO)
	assert_bool(CityMapData.has_city("gn-1850147")).is_true()
	var city := CityMapData.city("gn-1850147")
	assert_bool(city.generated).is_true()
	assert_float(city.overview.lat).is_equal_approx(35.6895, 0.0001)
	assert_float(city.overview.zoom).is_equal(11.0)
	assert_array(city.landmarks).is_empty()
	var ids: Array = city.residents.map(func(r): return r.id)
	assert_array(ids).contains_exactly(["nursery_keeper", "bistro_owner", "restorer"])
	for r in city.residents:
		assert_float(absf(float(r.lat) - 35.6895)).is_less(0.05)
	# Curated cities keep their hand-made configuration.
	assert_bool(CityMapData.city("los_angeles").has("generated")).is_false()
