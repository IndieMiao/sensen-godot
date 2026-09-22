extends GdUnitTestSuite
## 有农场之后的地图：不再选地，挂 Nearby 面板与 My Farm；服务端不可用落到随包样例。

const MAP_POC_SCENE := "res://scenes/map_poc/map_poc.tscn"

var _saved_transport: Callable

func before_test() -> void:
	FarmChoice.save("sh_a", 2)
	FarmRegions.save_choice("shanghai")

func after_test() -> void:
	while AppRouter._navigation_pending: await get_tree().process_frame
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame
	FarmChoice.clear()
	FarmRegions.clear_choice()
	UiState.clear()
	# 别把假传输留给下一个套件。
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	Net.booting = false

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
	assert_int(m.nearby_panel.card_count()).is_equal(18)
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
	assert_int(m.nearby_panel.card_count()).is_equal(18)

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
	assert_bool(m.nearby_panel.street_button.disabled).is_true()
	assert_str(m.farm_markers.selected_id).is_equal("zzz")
	assert_bool(m.farm_overlay.visible).is_false()

func test_preset_snapshots_load_per_region() -> void:
	assert_int(PresetSnapshots.entries("shanghai").size()).is_equal(18)
	assert_int(PresetSnapshots.entries("los_angeles").size()).is_equal(18)
	assert_int(PresetSnapshots.entries("mars").size()).is_equal(0)
	var sh: Array = PresetSnapshots.entries("shanghai")
	assert_array(sh.map(func(e): return str(e.avatar_ref))).contains(["preset_a", "preset_b"])


func test_cold_start_shows_characters_without_a_selected_farm() -> void:
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
	assert_str(m2.nearby_panel.focused_id).is_empty()
	assert_str(m2.farm_markers.selected_id).is_empty()
	assert_bool(m2.farm_markers.miniature.visible).is_false()

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

func test_selected_city_keeps_its_camera_and_demo_farmers_with_a_farm_abroad() -> void:
	FarmRegions.save_choice("los_angeles")
	_login_with_farm("sh_b", [{"error": "down"}])
	Net.session.state = {"journey": {"version": 1, "unlocks": [], "facts": []}}
	var m := _map()
	await get_tree().create_timer(0.7).timeout
	var city: Dictionary = FarmRegions.load_default().region("los_angeles")
	var center := {"x":34.065,"y":-118.365} # Keep geographic expectations in f64, like the camera.
	assert_float(m.center_lat).is_equal_approx(center.x, 0.000001)
	assert_float(m.center_lng).is_equal_approx(center.y, 0.000001)
	assert_str(m.region.id).is_equal("los_angeles")
	assert_str(m._nearby_region).is_equal("los_angeles")
	assert_int(m._nearby_entries.size()).is_equal(18)
	for entry in m._nearby_entries:
		assert_str(entry.region_id).is_equal("los_angeles")
	assert_str(m.farm_markers.selected_id).is_empty()
	assert_bool(m.farm_markers.miniature.visible).is_false()
	assert_str(FarmChoice.load().layout_patch_id).is_equal("sh_b")
	m._on_location_update(m.START_LAT, m.START_LNG, 10)
	m._resolve_home(m.START_LAT, m.START_LNG, true)
	m.resume()
	assert_float(m.center_lng).is_equal_approx(center.y, 0.000001)

func test_late_login_does_not_pull_selected_city_back_to_own_farm() -> void:
	FarmChoice.clear()
	FarmRegions.save_choice("los_angeles")
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	var m := _map()
	await get_tree().process_frame
	assert_object(m.select_panel).is_not_null()
	assert_float(m.center_lng).is_less(-118.0)
	_login_with_farm("sh_c", [{"error": "down"}])
	Net.session.state = {"journey": {"version": 1, "unlocks": [], "facts": []}}
	m._on_net_booted(true)
	await get_tree().create_timer(0.7).timeout
	assert_object(m.select_panel).is_null()
	assert_object(m.city_map).is_not_null()
	assert_float(m.center_lng).is_less(-118.0)
	assert_str(m._nearby_region).is_equal("los_angeles")
	assert_str(FarmChoice.load().layout_patch_id).is_equal("sh_c")

func test_explicit_home_focus_switches_both_camera_and_nearby_city() -> void:
	FarmRegions.save_choice("los_angeles")
	_login_with_farm("sh_b", [{"error": "down"}, {"error": "down"}])
	var m := _map()
	await get_tree().process_frame
	m._focus_own_farm()
	await get_tree().create_timer(0.7).timeout
	assert_float(m.center_lng).is_greater(121.0)
	assert_str(m.region.id).is_equal("shanghai")
	assert_str(m._nearby_region).is_equal("shanghai")
	assert_str(FarmRegions.load_choice()).is_equal("shanghai")
	assert_str(m.farm_markers.selected_id).is_equal("self")
	for entry in m._nearby_entries:
		assert_str(entry.region_id).is_equal("shanghai")

func test_shanghai_selection_with_la_farm_uses_shanghai_demo_neighbourhood() -> void:
	_login_with_farm("la_b", [{"error": "down"}])
	var m := _map()
	await get_tree().create_timer(0.7).timeout
	assert_float(m.center_lng).is_greater(121.0)
	assert_str(m._nearby_region).is_equal("shanghai")
	assert_str(FarmChoice.load().layout_patch_id).is_equal("la_b")

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
	_login_with_farm("sh_a", [{"error": "nearby unavailable"}])
	var m := _map()
	await get_tree().process_frame
	var sample_b := str(m._nearby_entries.filter(func(e): return e.avatar_ref == "preset_b")[0].farm_id)
	m.nearby_panel.focus(sample_b)
	await m._open_my_farm()
	while AppRouter._navigation_pending: await get_tree().process_frame
	var own := AppRouter.top_instance()
	assert_bool(own.visitor).is_false()
	assert_bool(own.snapshot.is_empty()).is_true()
	assert_str(own.bp.layout_patch_id).is_equal("homestead_a")
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
	while AppRouter._navigation_pending: await get_tree().process_frame
	var visit := AppRouter.top_instance()
	assert_bool(visit.visitor).is_true()
	assert_str(str(visit.snapshot.farm_id)).is_equal(sample_b)
	assert_str(str(visit.snapshot.avatar_ref)).is_equal("preset_b")
	# 农场地面布局对所有人是同一份；身份由 farm_id 与 avatar_ref 区分（上面两条）。
	assert_str(visit.bp.layout_patch_id).is_equal("homestead_a")

func test_cached_choice_is_not_an_owned_farm_when_server_reports_no_farm() -> void:
	var t := _login_fake([])
	Net.session.last_error_code = "NO_FARM"
	var m := _map()
	assert_object(m.select_panel).is_not_null()
	assert_object(m.my_farm_btn).is_null()
	assert_str(FarmChoice.load().layout_patch_id).is_equal("sh_a")
	assert_int(t.requests.size()).is_equal(0)

func test_late_no_farm_response_replaces_cached_home_with_selection() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	var m := _map()
	assert_object(m.my_farm_btn).is_not_null()
	Net.client.token = "tok"
	Net.session.last_error_code = "NO_FARM"
	m._on_net_booted(true)
	assert_object(m.my_farm_btn).is_null()
	assert_object(m.nearby_panel).is_null()
	assert_object(m.farm_markers).is_null()
	assert_object(m.select_panel).is_not_null()
	assert_str(FarmChoice.load().layout_patch_id).is_equal("sh_a")
	assert_int(AppRouter.instance_depth()).is_equal(0)
	await get_tree().process_frame

func test_opening_cached_farm_checks_server_before_entering() -> void:
	var t := _login_fake([
		{"status": 200, "json": {"count": 0, "entries": []}},
		{"status": 404, "json": {"code": "NO_FARM"}},
	])
	var m := _map()
	await m._open_my_farm()
	assert_int(AppRouter.instance_depth()).is_equal(0)
	assert_object(m.select_panel).is_not_null()
	assert_str(FarmChoice.load().layout_patch_id).is_equal("sh_a")
	assert_str(t.requests[-1].method).is_equal("GET")
	assert_bool(str(t.requests[-1].url).ends_with("/farms/me")).is_true()
	await get_tree().process_frame

func test_connection_failure_keeps_entry_retryable_and_recovers_server_farm() -> void:
	_login_fake([
		{"status": 200, "json": {"count": 0, "entries": []}},
		{"error": "connection failed"},
		{"status": 200, "json": {"farm_id": "f1", "version": 3, "state": {},
			"layout_patch_id": "sh_c", "blueprint_revision": 2, "region_id": "shanghai"}},
	])
	var m := _map()
	await m._open_my_farm()
	assert_int(AppRouter.instance_depth()).is_equal(0)
	assert_bool(m.my_farm_btn.disabled).is_false()
	assert_str(m.location_status.text).is_equal("Could not connect. Try again.")
	assert_str(FarmChoice.load().layout_patch_id).is_equal("sh_a")
	await m._open_my_farm()
	while AppRouter._navigation_pending: await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_object(AppRouter.top_instance().session).is_not_null()
	assert_str(AppRouter.top_instance().bp.layout_patch_id).is_equal("homestead_a")

func test_opening_during_login_waits_and_ignores_duplicate_entry() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	var m := _map()
	Net.booting = true
	m._open_my_farm()
	m._open_my_farm()
	assert_int(AppRouter.instance_depth()).is_equal(0)
	assert_bool(m.my_farm_btn.disabled).is_true()
	_login_with_farm("sh_a", [{"status": 200, "json": {"count": 0, "entries": []}}])
	Net.booting = false
	Net.booted.emit(true)
	await get_tree().process_frame
	while AppRouter._navigation_pending: await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_object(AppRouter.top_instance().session).is_not_null()

func test_private_farm_snapshot_remains_visitable_without_map_location() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	var m := _map()
	await get_tree().process_frame
	var snapshot := PresetSnapshots.snapshot(str(m._nearby_entries[0].farm_id))
	var id := str(snapshot.farm_id)
	snapshot.erase("region_id")
	snapshot.erase("location")
	m._place_farm(id, snapshot)
	assert_bool(m.farm_markers.points.has(id)).is_false()
	assert_bool(m._nearby_entries.any(func(entry): return str(entry.farm_id) == id)).is_true()

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
