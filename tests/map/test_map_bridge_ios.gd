extends GdUnitTestSuite
## iOS UDP 桥：定位消息解析（B5）。真 UDP 收发不在单测里跑。

func test_parse_location_accepts_lat_lng_acc_and_rejects_junk() -> void:
	assert_array(MapBridgeIOS.parse_location("LOC|31.2304|121.4737|12.5")).is_equal([31.2304, 121.4737, 12.5])
	assert_array(MapBridgeIOS.parse_location("LOC|31.2304|121.4737|nan?")).is_equal([31.2304, 121.4737, -1.0])
	assert_array(MapBridgeIOS.parse_location("LOC|31.2304|121.4737")).is_empty()
	assert_array(MapBridgeIOS.parse_location("LOC|x|121.4737|1")).is_empty()
	assert_array(MapBridgeIOS.parse_location("READY|3")).is_empty()

func test_format_cam_unchanged() -> void:
	assert_str(MapBridgeIOS.format_cam(31.0, 121.0, 16.0, 0.0, 45.0)).is_equal("CAM|31.0000000|121.0000000|16.000|0.00|45.00")
