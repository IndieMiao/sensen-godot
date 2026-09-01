extends GdUnitTestSuite
## marker 必须相对 home 锚点摆放，不能写死经纬度——写死的话用户定位到任何
## 非上海的位置，marker 会全部落到屏幕外（与 pawn 同一个坑，见 test_map_home_anchoring）。

const TOKYO_LAT := 35.6812
const TOKYO_LNG := 139.7671

func test_specs_load_with_at_least_three_markers() -> void:
	var specs := MarkerLayer.load_specs()
	assert_bool(specs.size() >= 3).is_true()
	for s in specs:
		assert_bool(s.has("east_m") and s.has("north_m")).is_true()
		assert_bool(str(s.get("text", "")).length() > 0).is_true()
		assert_bool(str(s.get("author", "")).length() > 0).is_true()

func test_offsets_stay_within_first_screen_range() -> void:
	## 超出 400m 的 marker 在 z16 首屏就看不见了，演示时等于不存在
	for s in MarkerLayer.load_specs():
		var d := Vector2(float(s.east_m), float(s.north_m)).length()
		assert_bool(d <= 400.0).is_true()

func test_markers_follow_home_not_absolute_coords() -> void:
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	assert_bool(layer.markers.size() >= 3).is_true()
	# 以东京为锚点时，每个 marker 的世界坐标都应在 home 附近（几百米内）
	for i in layer.markers.size():
		var w: Vector3 = layer.world_position(i, TOKYO_LAT, TOKYO_LNG)
		assert_bool(w.length() < 500.0).is_true()

func test_east_north_map_to_world_axes() -> void:
	## 世界系：x = 东，-z = 北（与 MapGeoMath 一致）
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	layer.markers[0].east_m = 100.0
	layer.markers[0].north_m = 50.0
	var w: Vector3 = layer.world_position(0, TOKYO_LAT, TOKYO_LNG)
	assert_float(w.x).is_equal_approx(100.0, 0.5)
	assert_float(w.z).is_equal_approx(-50.0, 0.5)

func test_toggle_opens_one_bubble_at_a_time() -> void:
	var layer = auto_free(MarkerLayer.new())
	layer.set_home(TOKYO_LAT, TOKYO_LNG)
	layer._toggle(0)
	assert_bool((layer.markers[0].bubble as Control).visible).is_true()
	layer._toggle(1)
	assert_bool((layer.markers[0].bubble as Control).visible).is_false()
	assert_bool((layer.markers[1].bubble as Control).visible).is_true()
	layer._toggle(1) # 再点一次收起
	assert_bool((layer.markers[1].bubble as Control).visible).is_false()
