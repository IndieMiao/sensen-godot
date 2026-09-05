extends GdUnitTestSuite
## 有农场之后的地图：不再选地，挂 Nearby 面板与 My Farm；服务端不可用落到随包样例。

const MAP_POC_SCENE := "res://scenes/map_poc/map_poc.tscn"

var _saved_transport: Callable

func before_test() -> void:
	FarmChoice.save("sh_a", 2)
	FarmRegions.save_choice("shanghai")

func after_test() -> void:
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame
	FarmChoice.clear()
	FarmRegions.clear_choice()
	UiState.clear()
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

func test_late_login_replaces_the_initial_offline_nearby_list() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	var m := _map()
	await get_tree().process_frame
	assert_bool(m._nearby_from_presets).is_true()
	_login_fake([{"status": 200, "json": {"region_id": "shanghai", "count": 0, "entries": []}}])
	m._on_net_booted(true)
	await get_tree().process_frame
	assert_bool(m._nearby_from_presets).is_false()
	assert_int(m.nearby_panel.card_count()).is_equal(0)
	assert_bool(m.nearby_panel._subtitle.text.contains("Offline")).is_false()

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
	await get_tree().create_timer(0.65).timeout
	var center: Vector2 = m.farm_markers.points[id].center
	assert_float(m.center_lat).is_equal_approx(center.x, 0.000001)
	assert_float(m.center_lng).is_equal_approx(center.y, 0.000001)
	assert_str(m.farm_markers.selected_id).is_equal(id)
	assert_bool(m.farm_markers._buttons[id].visible).is_true()
	m._focus_own_farm()
	assert_bool(m.nearby_panel._preview.visible).is_false()
	assert_str(m.nearby_panel.focused_id).is_empty()
	assert_str(m.farm_markers.selected_id).is_equal("self")

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
	assert_str(m.farm_markers.selected_id).is_equal("zzz")
	assert_bool(m.farm_overlay.visible).is_false()

func test_preset_snapshots_load_per_region() -> void:
	assert_int(PresetSnapshots.entries("shanghai").size()).is_equal(2)
	assert_int(PresetSnapshots.entries("los_angeles").size()).is_equal(2)
	assert_int(PresetSnapshots.entries("mars").size()).is_equal(0)
	var sh: Array = PresetSnapshots.entries("shanghai")
	assert_array(sh.map(func(e): return str(e.avatar_ref))).contains(["preset_a", "preset_b"])


func test_focus_is_remembered_and_restored_on_cold_start() -> void:
	# PRD §3.3：返回时恢复角色选择。同一次运行地图不销毁天然保留；这里管冷启动。
	_login_fake([{"error": "down"}])
	var m := _map()
	await get_tree().process_frame
	var second := str(m.nearby_panel.cards()[1].get_meta("farm_id"))
	m.nearby_panel.focus(second)
	assert_str(str(UiState.read().get("selected_farm_id", ""))).is_equal(second)
	# 「重启」：新地图实例
	_login_fake([{"error": "down"}])
	var m2 := _map()
	await get_tree().process_frame
	assert_str(m2.nearby_panel.focused_id).is_equal(second)

func test_remembered_farm_no_longer_listed_is_ignored() -> void:
	UiState.write({"selected_farm_id": "gone"})
	_login_fake([{"error": "down"}])
	var m := _map()
	await get_tree().process_frame
	assert_str(m.nearby_panel.focused_id).is_equal("")

func _login_with_farm(layout: String, extra_responses: Array = []) -> FakeTransport:
	var t := FakeTransport.new(extra_responses)
	Net.use_transport(t.callable())
	Net.client.token = "tok"
	Net.session.farm_id = "f1"
	Net.session.layout_patch_id = layout
	Net.session.blueprint_revision = 2
	return t

func test_server_farm_puts_map_in_home_mode_even_without_local_choice() -> void:
	# 换手机 / 清过数据：本地没记录，但服务端有农场 → 直接进家，并把本地缓存补上。
	FarmChoice.clear()
	_login_with_farm("sh_c", [{"status": 200, "json": {"region_id": "shanghai", "count": 0, "entries": []}}])
	var m := _map()
	await get_tree().process_frame
	assert_object(m.select_panel).is_null()
	assert_object(m.nearby_panel).is_not_null()
	assert_str(FarmChoice.load().layout_patch_id).is_equal("sh_c")

func test_confirming_a_candidate_yields_to_the_servers_existing_farm() -> void:
	# 2026-09-04 真机：服务端已有 sh_c，玩家在选地页点了 Old Town(sh_b) → 必须进 sh_c。
	FarmChoice.clear()
	var t := FakeTransport.new([
		{"status": 200, "json": {"farm_id": "f1", "version": 3, "state": {},
			"layout_patch_id": "sh_c", "blueprint_revision": 2, "region_id": "shanghai"}},  # GET /farms/me
	])
	Net.use_transport(t.callable())
	Net.client.token = "tok"
	var m := _map()
	await get_tree().process_frame
	var choice: Dictionary = await m._resolve_confirmed_farm("sh_b")
	assert_str(str(choice.layout_patch_id)).is_equal("sh_c")
	assert_str(FarmChoice.load().layout_patch_id).is_equal("sh_c")
	assert_str(m.location_status.text).is_equal("You already have a farm at Yuyuan Road")

func test_late_login_with_a_farm_switches_candidates_to_home() -> void:
	# Net 在地图 _ready 之后才 boot 完：登录一到，选地面板要让位给家模式。
	FarmChoice.clear()
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	var m := _map()
	await get_tree().process_frame
	assert_object(m.select_panel).is_not_null()
	_login_with_farm("sh_c", [{"status": 200, "json": {"region_id": "shanghai", "count": 0, "entries": []}}])
	m._on_net_booted(true)
	await get_tree().process_frame
	assert_object(m.select_panel).is_null()
	assert_object(m.candidate_overlay).is_null()
	assert_object(m.nearby_panel).is_not_null()

func test_my_farm_then_sample_b_opens_two_distinct_farm_identities() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	var m := _map()
	await get_tree().process_frame
	var sample_b := str(m.nearby_panel.entries.filter(func(e): return e.avatar_ref == "preset_b")[0].farm_id)
	m.nearby_panel.focus(sample_b)
	m._open_my_farm()
	var own := AppRouter.top_instance()
	assert_bool(own.visitor).is_false()
	assert_bool(own.snapshot.is_empty()).is_true()
	assert_str(own.bp.layout_patch_id).is_equal("sh_a")
	assert_str(m.nearby_panel.focused_id).is_empty()
	AppRouter.pop_instance()
	await get_tree().process_frame
	m.resume()
	var card: Button = m.nearby_panel.cards().filter(func(c): return str(c.get_meta("farm_id")) == sample_b)[0]
	card.pressed.emit()
	assert_str(m.nearby_panel.focused_id).is_equal(sample_b)
	assert_str(m.farm_markers.selected_id).is_equal(sample_b)
	assert_bool(m.nearby_panel.visit_button.disabled).is_false()
	m.nearby_panel.visit_button.pressed.emit()
	var visit := AppRouter.top_instance()
	assert_bool(visit.visitor).is_true()
	assert_str(str(visit.snapshot.farm_id)).is_equal(sample_b)
	assert_str(str(visit.snapshot.avatar_ref)).is_equal("preset_b")
	assert_str(visit.bp.layout_patch_id).is_not_equal("sh_a")

func test_private_farm_snapshot_remains_visitable_without_map_location() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	var m := _map()
	await get_tree().process_frame
	var snapshot := PresetSnapshots.snapshot(str(m.nearby_panel.entries[0].farm_id))
	var id := str(snapshot.farm_id)
	snapshot.erase("region_id")
	snapshot.erase("location")
	m._place_farm(id, snapshot)
	assert_bool(m.farm_markers.points.has(id)).is_false()
	assert_bool(m.nearby_panel.entries.any(func(entry): return str(entry.farm_id) == id)).is_true()

func test_suspended_gesture_cannot_block_returned_map_selection() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	var m := _map()
	m._touch_count = 2
	m._gesture_multi = true
	m._fling_vel = Vector3(10, 0, 10)
	m.suspend()
	m.resume()
	assert_int(m._touch_count).is_equal(0)
	assert_bool(m._gesture_multi).is_false()
	assert_vector(m._fling_vel).is_equal(Vector3.ZERO)
