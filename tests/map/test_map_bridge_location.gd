extends GdUnitTestSuite
## MapBridge 定位契约：接口必须存在且默认空转。
## iOS/桌面没有定位实现，直接继承基类空转，场景靠 3 秒超时回落默认点——
## 抽象层不能因为某个平台没实现就在场景里写 if platform。

func test_base_bridge_exposes_location_contract() -> void:
	var b := MapBridge.new()
	assert_bool(b.has_signal("location_update")).is_true()
	assert_bool(b.has_method("start_location")).is_true()
	b.start_location() # 默认实现必须安全空转，不抛错

func test_ios_bridge_inherits_noop_location() -> void:
	## iOS 桥不覆写定位：继承基类空转即可，别在 iOS 侧写半吊子实现
	var b := MapBridgeIOS.new()
	assert_bool(b.has_signal("location_update")).is_true()
	b.start_location()
