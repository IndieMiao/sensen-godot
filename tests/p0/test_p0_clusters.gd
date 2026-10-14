extends GdUnitTestSuite
## SGODOT-275: the client reads the same frozen city clusters as the server (plan v2 §11.1) and gives the same trip
## tiers (§11.2.1, §11.2.3; the San Francisco row of table 11-4). Mirrors server/test/p0/p0_clusters.test.ts.

const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const SF := "gn-5391959"
const TOKYO := "gn-1850147"
const LA := "gn-5368361"
const FARM := Vector2(37.7558, -122.4345)   # the San Francisco homestead

func test_the_cluster_table_matches_the_server() -> void:
	assert_int(P0Clusters.count()).is_equal(12493)   # SPLIT_OUT: San Diego (SGODOT-280), Ganghwa-gun and Ji'an (SGODOT-305)
	var sf := P0Clusters.get_cluster(SF)
	assert_str(str(sf.name)).is_equal("San Francisco")
	assert_str(str(sf.climate)).is_equal("temperate")
	assert_str(str(sf.continent)).is_equal("north_america")
	assert_str(str(P0Clusters.get_cluster("gn-524901").continent)).is_equal("europe")   # Moscow (§11.9.3)
	assert_dict(P0Clusters.get_cluster("gn-nope")).is_empty()
	assert_str(str(P0Clusters.all()[0].name)).is_equal("Shanghai")   # most populous first

func test_trip_tiers_follow_the_bounds_and_the_fallback_lists() -> void:
	var by_km := [29, 30, 31, 100, 101, 500, 1600, 1601, 4000, 10000, 10001].map(func(k): return P0Clusters.trip_by_km(k))
	assert_array(by_km).is_equal([1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7])
	assert_dict(P0Clusters.trip(SF, SF, FARM)).is_equal({km = 0, trip = 1, name = "Local"})
	assert_int(int(P0Clusters.trip(LA, SF, FARM).trip)).is_equal(4)      # table 11-4: SF → LA Trip 4
	assert_int(int(P0Clusters.trip(TOKYO, SF, FARM).trip)).is_equal(6)   # SF → Tokyo Trip 6
	var fb := {near3 = [TOKYO], near10 = [TOKYO, LA]}
	assert_int(int(P0Clusters.trip(TOKYO, SF, FARM, fb).trip)).is_equal(1)
	assert_int(int(P0Clusters.trip(LA, SF, FARM, fb).trip)).is_equal(2)
	assert_dict(P0Clusters.trip("gn-nope", SF, FARM)).is_empty()

func test_nearest_finds_the_cluster_under_the_camera() -> void:
	assert_str(P0Clusters.nearest(37.80, -122.27)).is_equal(SF)          # Oakland is in San Francisco's cluster
	assert_str(P0Clusters.nearest(35.68, 139.69)).is_equal(TOKYO)
	assert_str(P0Clusters.nearest(0.0, -150.0)).is_equal("")            # the open Pacific
