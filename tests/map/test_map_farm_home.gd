extends GdUnitTestSuite
## 有农场之后的地图：不再选地，挂 Nearby 面板与 My Farm；服务端不可用落到随包样例。

const MAP_POC_SCENE := "res://scenes/map_poc/map_poc.tscn"

var _saved_transport: Callable

func before_test() -> void:
	FarmChoice.save("sh_a", 2)
	FarmRegions.save_choice("shanghai")

func after_test() -> void:
	FarmChoice.clear()
	FarmRegions.clear_choice()
	# 别把假传输留给下一个套件。
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""

func _map() -> Node:
	var scene := (load(MAP_POC_SCENE) as PackedScene).instantiate()
	add_child(auto_free(scene))
	# before_test 已存了城市选择，_ready() 自己就会进街区模式并拉一次 nearby；
	# 这里再调一次会把假传输的回包用光，落到随包兜底，测的就不是在线路径了。
	if not scene.street_mode:
		scene.enter_street_mode(FarmRegions.load_default().region("shanghai"))
	return scene

func _login_fake(responses: Array) -> FakeTransport:
	var t := FakeTransport.new(responses)
	Net.use_transport(t.callable())
	Net.client.token = "tok"     # 视作已登录
	return t

func test_with_a_farm_the_map_shows_home_not_candidates() -> void:
	_login_fake([{"status": 200, "json": {"region_id": "shanghai", "count": 0, "entries": []}}])
	var m := _map()
	await get_tree().process_frame
	assert_object(m.select_panel).is_null()
	assert_object(m.candidate_overlay).is_null()
	assert_object(m.nearby_panel).is_not_null()
	assert_object(m.my_farm_btn).is_not_null()
	assert_str(m.my_farm_btn.text).is_equal("My Farm")

func test_nearby_entries_come_from_server_when_online() -> void:
	var t := _login_fake([{"status": 200, "json": {"region_id": "shanghai", "count": 5, "entries": [
		{"farm_id": "a", "avatar_ref": "seed:aaaaaaaa", "nursery_stage": "derelict"},
		{"farm_id": "b", "avatar_ref": "seed:bbbbbbbb", "nursery_stage": "cleared"},
	]}}])
	var m := _map()
	await get_tree().process_frame
	assert_int(m.nearby_panel.card_count()).is_equal(2)
	assert_str(m.nearby_panel._title.text).is_equal("Nearby Farmers · 5")
	assert_bool(str(t.requests[0].url).ends_with("/nearby?region_id=shanghai")).is_true()
	assert_bool(m._nearby_from_presets).is_false()

func test_server_down_falls_back_to_bundled_sample_farms() -> void:
	# PRD §11.2：远端不可用自动用本地快照，D4 不能被断网卡住。
	_login_fake([{"error": "down"}])
	var m := _map()
	await get_tree().process_frame
	assert_bool(m._nearby_from_presets).is_true()
	assert_int(m.nearby_panel.card_count()).is_equal(2)          # sh_b + sh_c
	assert_str(m.nearby_panel._subtitle.text).is_equal("Offline · sample farms")
	# 随包条目按 farm_id 排序，预置 id 是确定的
	for c in m.nearby_panel.cards():
		assert_bool(PresetSnapshots.snapshot(str(c.get_meta("farm_id"))).is_empty()).is_false()

func test_not_logged_in_also_falls_back() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	var m := _map()
	await get_tree().process_frame
	assert_bool(m._nearby_from_presets).is_true()
	assert_int(m.nearby_panel.card_count()).is_equal(2)

func test_focusing_a_sample_farm_shows_its_bundled_preview() -> void:
	_login_fake([{"error": "down"}])
	var m := _map()
	await get_tree().process_frame
	var id := str(m.nearby_panel.cards()[0].get_meta("farm_id"))
	m.nearby_panel.focus(id)
	await get_tree().process_frame
	assert_bool(m.nearby_panel._preview.visible).is_true()
	assert_bool(m.nearby_panel.visit_button.disabled).is_false()
	assert_bool(m._snapshots.has(id)).is_true()

func test_focusing_online_farm_fetches_snapshot_and_unavailable_disables_visit() -> void:
	_login_fake([
		{"status": 200, "json": {"region_id": "shanghai", "count": 1, "entries": [
			{"farm_id": "zzz", "avatar_ref": "seed:zzzzzzzz", "nursery_stage": "derelict"}]}},
		{"status": 404, "json": {"code": "NOT_FOUND"}},
	])
	var m := _map()
	await get_tree().process_frame
	m.nearby_panel.focus("zzz")
	await get_tree().process_frame
	assert_bool(m.nearby_panel.visit_button.disabled).is_true()

func test_preset_snapshots_load_per_region() -> void:
	assert_int(PresetSnapshots.entries("shanghai").size()).is_equal(2)
	assert_int(PresetSnapshots.entries("los_angeles").size()).is_equal(2)
	assert_int(PresetSnapshots.entries("mars").size()).is_equal(0)
	var sh: Array = PresetSnapshots.entries("shanghai")
	assert_array(sh.map(func(e): return str(e.avatar_ref))).contains(["preset_a", "preset_b"])
