extends GdUnitTestSuite
## iOS 地图桥：原生 POI 回包分多包发送，收齐后合并成一次 pois_received（2026-09-29）。

func _bridge() -> MapBridgeIOS:
	return MapBridgeIOS.new()

func test_multi_part_answers_are_joined_in_order() -> void:
	var b := _bridge()
	var got := []
	b.pois_received.connect(func(id: int, payload: String): got.append([id, JSON.parse_string(payload)]))
	b._on_pois_packet('POIS|7|1|2|{"features":[{"id":"tile:2","name":"B"}]}')
	assert_array(got).is_empty()
	b._on_pois_packet('POIS|7|0|2|{"features":[{"id":"tile:1","name":"A"}]}')
	assert_int(got.size()).is_equal(1)
	assert_int(got[0][0]).is_equal(7)
	var names: Array = got[0][1].features.map(func(f): return f.name)
	assert_array(names).is_equal(["A", "B"])
	assert_bool(got[0][1].has("error")).is_false()

func test_errors_pass_through_and_older_partials_are_dropped() -> void:
	var b := _bridge()
	var got := []
	b.pois_received.connect(func(id: int, payload: String): got.append([id, JSON.parse_string(payload)]))
	b._on_pois_packet('POIS|3|0|2|{"features":[{"id":"x","name":"old"}]}')
	b._on_pois_packet('POIS|4|0|1|{"features":[],"error":"loading"}')
	assert_int(got.size()).is_equal(1)
	assert_str(got[0][1].error).is_equal("loading")
	assert_bool(b._poi_parts.has(3)).is_false()
	b._on_pois_packet('garbage')
	b._on_pois_packet('POIS|5|0|1|not json')
	assert_int(got.size()).is_equal(1)
