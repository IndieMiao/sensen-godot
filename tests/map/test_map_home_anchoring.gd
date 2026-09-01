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
	## 不先排一批 LA 夹具进队列的话，push_front 和 append 对空队列毫无差别，
	## 这条用例测不出"自己排队头"这条真正要守的行为。
	var n := _make()
	n._spawn_la_fixture()
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
	n._resolve_home(MapPoc.START_LAT, MapPoc.START_LNG, true)
	assert_float(n.home_lat).is_equal_approx(MapPoc.START_LAT, 1e-9)
	assert_bool(n._spawn_queue.size() > MapPoc.PAWNS_NEAR_COUNT).is_true()

## —— 回落 -> 真实定位的一次性纠正（is_fallback 参数） ——————————————————
## 场景：3 秒超时先落锁到上海默认点，随后姗姗来迟的授权对话框才放行真实
## GPS/网络定位。这条真实定位应当被采信一次，把已经排队/装配的 home 队伍
## （自己 + 近处路人）整体搬到真实位置，同时绝不打扰洛杉矶压测夹具。

func test_fallback_then_real_fix_reanchors_once_and_moves_near_cohort() -> void:
	var n := _make()
	n._resolve_home(MapPoc.START_LAT, MapPoc.START_LNG, true)
	var before_lat: float = n._spawn_queue[0].lat # push_front：self 在队头
	var before_lng: float = n._spawn_queue[0].lng
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	assert_float(n.home_lat).is_equal_approx(TOKYO_LAT, 1e-9)
	assert_float(n.home_lng).is_equal_approx(TOKYO_LNG, 1e-9)
	# 平移而非重新生成：偏移量必须等于 home 的 delta，随机布局不能被打乱。
	var d_lat := TOKYO_LAT - MapPoc.START_LAT
	var d_lng := TOKYO_LNG - MapPoc.START_LNG
	assert_float(n._spawn_queue[0].lat).is_equal_approx(before_lat + d_lat, 1e-9)
	assert_float(n._spawn_queue[0].lng).is_equal_approx(before_lng + d_lng, 1e-9)
	assert_bool(n._home_from_fallback).is_false() # 纠正机会用掉即焚

func test_second_real_fix_after_correction_does_not_reanchor_again() -> void:
	## 纠正只给一次：回落 -> 第一手真实定位（纠正生效）-> 第二手真实定位（必须忽略）。
	var n := _make()
	n._resolve_home(MapPoc.START_LAT, MapPoc.START_LNG, true)
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	n._resolve_home(1.0, 1.0)
	assert_float(n.home_lat).is_equal_approx(TOKYO_LAT, 1e-9)
	assert_float(n.home_lng).is_equal_approx(TOKYO_LNG, 1e-9)

func test_real_fix_then_real_fix_does_not_reanchor() -> void:
	## 首个定位本身就是真实定位（非回落）：后续任何定位更新都不得再挪锚点。
	## 与 test_resolve_home_is_idempotent 守住同一条不变量，这里用显式命名把
	## "两手都是真实定位"单独钉住，与上面的回落场景形成判别对照。
	var n := _make()
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	n._resolve_home(1.0, 1.0)
	assert_float(n.home_lat).is_equal_approx(TOKYO_LAT, 1e-9)
	assert_float(n.home_lng).is_equal_approx(TOKYO_LNG, 1e-9)

func test_la_fixture_stays_put_across_correction() -> void:
	## 洛杉矶夹具在纠正前后都必须保持绝对坐标——纠正只搬 home 队伍。
	var n := _make()
	n._spawn_la_fixture()
	n._resolve_home(MapPoc.START_LAT, MapPoc.START_LNG, true)
	n._resolve_home(TOKYO_LAT, TOKYO_LNG)
	var la := 0
	for spec in n._spawn_queue:
		if spec.cohort != "la":
			continue
		la += 1
		assert_bool(absf(spec.lat - MapPoc.LA_LAT) < 0.1).is_true()
	assert_int(la).is_equal(MapPoc.PAWNS_LA_COUNT)
