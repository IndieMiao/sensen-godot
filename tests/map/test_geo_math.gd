extends GdUnitTestSuite
## MapGeoMath 单元测试：等距换算往返、跨日界线环绕、地面分辨率、相机距离。

func test_roundtrip_near_anchor() -> void:
	## 容差 1e-4°（≈10m）：Vector2/Vector3 分量是 float32，经度 121° 量级下
	## 分辨率只有 ~7.6e-6°≈0.7m——所以权威中心在 map_poc 里用 f64 标量保存，
	## 本往返仅用于非权威路径（角色摆位/剔除），float32 精度足够。
	var w := MapGeoMath.geo_to_world(31.24, 121.48, 31.2304, 121.4737)
	var geo := MapGeoMath.world_to_geo(w, 31.2304, 121.4737)
	assert_float(geo.x).is_equal_approx(31.24, 1e-4)
	assert_float(geo.y).is_equal_approx(121.48, 1e-4)

func test_north_east_signs() -> void:
	var w := MapGeoMath.geo_to_world(31.2404, 121.4837, 31.2304, 121.4737)
	assert_bool(w.x > 0.0).is_true() # 东 = +x
	assert_bool(w.z < 0.0).is_true() # 北 = -z
	assert_float(-w.z).is_equal_approx(0.01 * MapGeoMath.M_PER_DEG_LAT, 1.0)

func test_dateline_wrap_shanghai_to_la() -> void:
	## 上海→洛杉矶最短方向是向东跨日界线：x 必须为正（约 1.15 万公里向东）。
	## 若不做经度环绕，naive 相减会得到向西 2.3 万公里的错误坐标。
	var w := MapGeoMath.geo_to_world(34.0522, -118.2437, 31.2304, 121.4737)
	assert_bool(w.x > 0.0).is_true()
	assert_bool(w.x < 1.3e7).is_true()

func test_wrap_dlng() -> void:
	assert_float(MapGeoMath.wrap_dlng(-239.7)).is_equal_approx(120.3, 1e-9)
	assert_float(MapGeoMath.wrap_dlng(200.0)).is_equal_approx(-160.0, 1e-9)
	assert_float(MapGeoMath.wrap_dlng(10.0)).is_equal_approx(10.0, 1e-9)

func test_meters_per_px_reference() -> void:
	## z0 赤道：40075016.686/512 ≈ 78271.517 米/逻辑像素；每 +1 zoom 减半
	assert_float(MapGeoMath.meters_per_logical_px(0.0, 0.0)).is_equal_approx(78271.5169, 0.01)
	assert_float(MapGeoMath.meters_per_logical_px(0.0, 1.0)).is_equal_approx(78271.5169 / 2.0, 0.01)

func test_cam_distance_monotonic() -> void:
	var d16 := MapGeoMath.cam_distance_m(800.0, 36.87, 31.0, 16.0)
	var d17 := MapGeoMath.cam_distance_m(800.0, 36.87, 31.0, 17.0)
	assert_bool(d17 < d16).is_true()
	assert_float(d16 / d17).is_equal_approx(2.0, 1e-3)
