extends GdUnitTestSuite
## 回归（一票否决项）：定位到任何地方，自己与近处路人都必须跟着 home 锚点走。
##
## 历史缺陷：pawn 存绝对经纬度（map_poc.gd:335-341），而 _teleport() 只重投影
## 不改坐标（:222 _reposition_pawns）。定位到非上海人民广场的任何位置，近处角色
## 全部落在 CULL_FACTOR=4.0×相机距离之外被剔除，地图上空无一人——验收第一条直接挂。
##
## 洛杉矶那 10 个是跨洋剔除 + 浮动原点的压测夹具，不是演示内容，必须保持绝对坐标。

const MapPoc := preload("res://scenes/map_poc/map_poc.gd")
const TOKYO_LAT := 35.6812
const TOKYO_LNG := 139.7671

func _make() -> Node:
	var n = auto_free(MapPoc.new())
	n._rng.seed = 20260901
	return n

func test_home_cohort_follows_resolved_location() -> void:
	var n := _make()
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	var near := 0
	for spec in n._spawn_queue:
		if spec.cohort == "la":
			continue
		near += 1
		var d := MapGeoMath.geo_to_world(spec.lat, spec.lng, TOKYO_LAT, TOKYO_LNG).length()
		assert_bool(d <= MapPoc.NEAR_SPREAD_M * 1.05).is_true()
	assert_int(near).is_equal(MapPoc.PAWNS_NEAR_COUNT + 1) # 12 路人 + 自己

func test_self_is_first_out_of_queue() -> void:
	var n := _make()
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	assert_str(str(n._spawn_queue[0].cohort)).is_equal("self")

func test_la_fixture_keeps_absolute_coords() -> void:
	var n := _make()
	n._spawn_la_fixture()
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	var la := 0
	for spec in n._spawn_queue:
		if spec.cohort != "la":
			continue
		la += 1
		assert_bool(absf(spec.lat - MapPoc.LA_LAT) < 0.1).is_true()
	assert_int(la).is_equal(MapPoc.PAWNS_LA_COUNT)

func test_resolve_home_is_idempotent() -> void:
	## 首个定位或超时先到者生效；后续定位更新不得再挪锚点，
	## 否则演示中途所有角色和 marker 会整体位移。
	var n := _make()
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	var count: int = n._spawn_queue.size()
	n._resolve_home(1.0, 1.0)
	assert_int(n._spawn_queue.size()).is_equal(count)
	assert_float(n.home_lat).is_equal_approx(TOKYO_LAT, 1e-9)

func test_timeout_fallback_uses_shanghai_default() -> void:
	var n := _make()
	n._resolve_home(MapPoc.START_LAT, MapPoc.START_LNG)
	assert_float(n.home_lat).is_equal_approx(MapPoc.START_LAT, 1e-9)
	assert_bool(n._spawn_queue.size() > MapPoc.PAWNS_NEAR_COUNT).is_true()
