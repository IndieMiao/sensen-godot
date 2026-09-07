extends GdUnitTestSuite

const SCENE := "res://scenes/city_select/city_select.tscn"

## 定位桥测试替身：不接入任何平台插件（Android/iOS 桥不进测试），只用来
## 手动控制/触发 location_update，验证超时取消订阅、重新定位不重复 connect。
class StubBridge extends MapBridge:
	var start_calls := 0
	func start_location() -> void:
		start_calls += 1

func after_test() -> void:
	FarmRegions.clear_choice()

func test_one_button_per_region() -> void:
	var s := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(s))
	assert_int(s.region_buttons().size()).is_equal(FarmRegions.load_default().ids().size())
	assert_object(s.get_node("%UseCurrent")).is_not_null()

func test_pick_region_pure() -> void:
	var regions := FarmRegions.load_default().regions
	assert_str(s_pick(regions, 34.0, -118.2, true)).is_equal("los_angeles")
	assert_str(s_pick(regions, 0.0, 0.0, false, "shanghai")).is_equal("shanghai")
	assert_str(s_pick(regions, 0.0, 0.0, false)).is_equal("")

func s_pick(regions: Array, lat: float, lng: float, has_fix: bool, fallback := "") -> String:
	var script := load("res://scenes/city_select/city_select.gd")
	return script.pick_region(regions, lat, lng, has_fix, fallback)

func test_city_select_reachable_via_qa_scene_argument() -> void:
	# A1 起主场景是 boot.tscn（社交主线）；农场分支的城市选择页保留为 --qa-scene=city 入口。
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=city"]))).is_equal(SCENE)

func test_timeout_cancels_pending_subscription() -> void:
	var s := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(s))
	var stub := StubBridge.new()
	s._bridge = stub
	s.locate()
	s._on_locate_timeout() # 直接触发超时回调，不等 3 秒真实计时器
	assert_bool(stub.location_update.is_connected(s._on_location)).is_false()
	stub.location_update.emit(34.0, -118.2, 5.0) # 迟到的定位：不应再被接住
	assert_bool(s._located).is_false()

func test_relocate_after_timeout_does_not_double_connect() -> void:
	# 断言按状态转换分三步查：Godot 的 connect() 会静默拒绝重复连接（只打一条
	# ERROR，返回值被 locate() 忽略），末态连接数在 bug 版和修复版都恰好是 1，
	# 不能只看最后一步——中间「超时后必须归零」才是真正有判别力的一步。
	var s := (load(SCENE) as PackedScene).instantiate()
	add_child(auto_free(s))
	var stub := StubBridge.new()
	s._bridge = stub
	s.locate()
	assert_int(stub.location_update.get_connections().size()).is_equal(1)
	s._on_locate_timeout()
	assert_int(stub.location_update.get_connections().size()).is_equal(0)
	s.locate() # 超时收回后重新点按「使用当前城市」：应该干净地重新订阅一次
	assert_int(stub.location_update.get_connections().size()).is_equal(1)
