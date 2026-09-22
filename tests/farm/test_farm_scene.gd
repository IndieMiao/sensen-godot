extends GdUnitTestSuite
## 农场场景：蓝图 → 地表/道具/玩家/相机；点田自动做下一步；先走过去再干活；服务端对账。

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

signal release_farm_command

var _saved_navigation_pending: bool

func before_test() -> void:
	_saved_navigation_pending = AppRouter._navigation_pending

func after_test() -> void:
	AppRouter._navigation_pending = _saved_navigation_pending
	FarmChoice.clear()

func _farm() -> Node:
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FIX)})
	add_child(auto_free(scene))
	await get_tree().process_frame   # RigActivity 用 call_deferred 挂通知节点，不给一帧会留孤儿
	return scene

## 带服务端会话的农场：fixture 蓝图的 9 格 + 3 预留格全 wild，第 0 章种子。
func _session_with_farm(t: FakeTransport, layout := "", cells := {}) -> FarmSession:
	var s := FarmSession.new(ApiClient.new("https://example.test/v1", t.callable()))
	s.client.token = "tok"
	s.farm_id = "f1"
	s.layout_patch_id = layout
	s.blueprint_revision = 2
	s.state = {"cells": cells, "beds_unlocked": 3, "wallet": 180,
		"inventory": {"seeds": {"R": {"bought": 0, "bound": 6}, "L": {"bought": 0, "bound": 3},
			"C": {"bought": 0, "bound": 0}, "H": {"bought": 0, "bound": 0}}, "produce": {"R": 0, "L": 0, "C": 0, "H": 0}},
		"clock": {"chapter_index": 0, "field_condition": "sunny"}, "xp": {"total": 0, "first_harvest_crops": []},
		"chapters": [{"status": "active", "step_flags": {"farm_created": true}}],
		"stall": {"settled": 0}, "sales_facts": {}}
	return s

## 自由格子种田：荒地不进状态，所以「未开垦的农场」就是一个空 cells。
func _wild_cells(_bp: FarmBlueprint) -> Dictionary:
	return {}

## 一小片已开垦的地，代替过去写死的 12 格田畦。
func _soil(bp: FarmBlueprint, count := 9) -> Array:
	var out: Array = []
	for j in bp.grid.y:
		for i in bp.grid.x:
			if out.size() >= count: return out
			if bp.mask_has("cultivable", Vector2i(i, j)): out.append(Vector2i(i, j))
	return out

func _online_farm(t: FakeTransport) -> Node:
	var bp := FarmBlueprint.load_file(FIX)
	var s := _session_with_farm(t, "", _wild_cells(bp))
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": bp, "session": s})
	add_child(auto_free(scene))
	await get_tree().process_frame
	return scene

func test_suspended_farm_defers_scene_rebuild_until_latest_state_is_resumed() -> void:
	var farm := await _online_farm(FakeTransport.new([]))
	var original_grid: BlueprintGrid = farm.grid
	var old_version: int = farm.predictor.version
	farm.suspend()
	for version in [2, 3, 4]:
		farm.session.version = version
		farm.session.state.wallet = 180 + version
		farm.session.state_changed.emit(farm.session.state, version)
		assert_object(farm.grid).is_equal(original_grid)
		assert_int(farm.predictor.version).is_equal(old_version)
	assert_bool(farm._pending_state_refresh).is_true()
	farm.resume()
	assert_bool(farm._pending_state_refresh).is_false()
	assert_int(farm.predictor.version).is_equal(4)
	# 寻路图不再随每次回包整张重建：开垦过的地照旧可通行，地面属性是静态的。
	# （只有木本作物与道具会动态阻挡，那走 BlueprintGrid.set_solid 的增量路径。）
	assert_object(farm.grid).is_equal(original_grid)
	assert_int(farm.session.state.wallet).is_equal(184)

func test_mine_entrance_is_pickable_from_its_model_without_a_floating_button() -> void:
	var farm := await _online_farm(FakeTransport.new([]))
	farm.set_process(false)
	for frame in 4: await get_tree().process_frame
	assert_object(farm.find_child("MineEntranceButton", true, false)).is_null()
	# 相机只框玩家附近：32m 场地上矿洞在出生点 20m 外，不再被硬塞进画面（那会把视野
	# 拉远一倍、格子小到按不准）。所以先站到矿口，再验证矿洞模型本身可点。
	farm.mover.position = farm.mine_approach()
	farm.player.position = farm.mover.position
	for zoom in [0.9, 1.0, 1.2]:
		farm.camera_pan.zoom = zoom
		farm._update_camera()
		var rect: Rect2 = farm._mine_pick_rect()
		assert_bool(rect.has_area()).is_true()
		assert_bool(farm._pick_mine(rect.get_center())).is_true()
		for local in [Vector3(-0.6, 0.6, 0), Vector3(0.6, 0.6, 0), Vector3(0, 1.3, 0.4), Vector3(0, 0.03, 0.7)]:
			var point: Vector2 = farm.cam.unproject_position(farm.mine_entrance.global_transform * local)
			if farm._camera_play_area().has_point(point): assert_bool(farm._pick_mine(point)).is_true()
		assert_bool(farm._pick_mine(rect.position - Vector2.ONE)).is_false()

func test_mine_model_tap_walks_to_the_entrance_and_respects_modal_and_visitor_guards() -> void:
	var transport := FakeTransport.new([])
	var farm := await _online_farm(transport)
	farm.set_process(false)
	for frame in 4: await get_tree().process_frame
	# 站在矿口外几米：矿洞要在画面里才点得到，同时留出距离让点击真的触发一段行走。
	farm.mover.position = farm.mine_approach() + Vector3(1.2, 0, 0)   # 往东：南边 1m 就是池塘
	farm.player.position = farm.mover.position
	farm._update_camera()
	var point: Vector2 = farm._mine_pick_rect().get_center()
	farm._tap_scene(point)
	assert_bool(farm._mine_pending).is_true()
	assert_bool(farm.mover.is_moving()).is_true()
	assert_array(transport.requests).is_empty()
	farm._mine_pending = false
	farm.visitor = true
	assert_bool(farm._pick_mine(point)).is_false()
	farm.visitor = false
	farm._open_stall()
	assert_bool(farm._pick_mine(point)).is_false()
	farm.hud.close_modal()
	farm.mine_entrance.hide()
	assert_bool(farm._mine_pick_rect().has_area()).is_false()
	assert_bool(farm._pick_mine(point)).is_false()

func test_seed_destination_opens_requested_goods_even_with_other_crops_ready() -> void:
	var transport := FakeTransport.new([])
	var bp := FarmBlueprint.load_file(FIX)
	var s := _session_with_farm(transport, "", _wild_cells(bp))
	s.state.journey = {"version": 1, "facts": ["first_harvest", "shared_meal"],
		"unlocks": ["crop_C", "crop_H"], "exploration": {"round": 1, "collected": []}}
	s.state.xp.first_harvest_crops = ["R"]
	var cell: Vector2i = _soil(bp, 1)[0]
	s.state.cells["%d,%d" % [cell.x, cell.y]] = {"state": "growing", "crop": "C", "ready_at": 1}
	var original := s.state.duplicate(true)
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": bp, "session": s, "seed_crop": "H"})
	add_child(auto_free(scene))
	for frame in 10: await get_tree().process_frame
	assert_str(scene._last_bulk.action).is_equal("harvest")
	assert_bool(scene.stall.visible).is_true()
	assert_bool(scene.hud.modal_open()).is_true()
	assert_bool(scene.stall._scroll.get_global_rect().encloses(scene.stall._seed_rows.H.box.get_global_rect())).is_true()
	assert_array(transport.requests).is_empty()
	assert_dict(s.state).is_equal(original)
	assert_bool(scene.is_back_navigation_locked()).is_true()
	assert_bool(scene.stall.visible).is_false()
	assert_bool(scene.hud.modal_open()).is_false()

## 出生点附近一格可开垦的土。不写死偏移：出生点正东就是贯穿南北的主路，
## 取 (2,2) 会落在路上——点上去只是走过去、不会开垦，断言会莫名其妙地红。
func _soil_near_spawn(f: Node, ring := 2) -> Vector2i:
	var spawn: Vector2i = f.bp.anchor("spawn")
	for dj in range(-ring, ring + 1):
		for di in range(-ring, ring + 1):
			if absi(di) != ring and absi(dj) != ring: continue
			var c: Vector2i = spawn + Vector2i(di, dj)
			if f.bp.mask_has("cultivable", c): return c
	return spawn

## 推进到某条件成立或超时（秒）。
func _run_until(f: Node, cond: Callable, seconds := 20.0) -> bool:
	var t := 0.0
	while t < seconds:
		f._process(0.1)
		t += 0.1
		if cond.call():
			return true
	return false

func _finished_first_chapter(state: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	next.chapters = [{"status": "done", "step_flags": {
		"farm_created": true, "first_harvest": true, "next_batch_sown_and_cared": true}}]
	return next


func test_seed_button_intent_survives_refresh_but_not_automatic_seed_fallback() -> void:
	var f := await _online_farm(FakeTransport.new([]))
	f.set_process(false)
	f.session.state.journey = {"version": 1, "facts": ["met_nursery", "met_bistro", "shared_meal"],
		"unlocks": ["bistro", "kitchen", "crop_C"], "exploration": {"round": 1, "collected": []}}
	f.session.state.xp.first_harvest_crops = ["R"]
	var cells: Dictionary = f.session.state.cells
	var ids: Array = _soil(f.bp, 2).map(func(c): return f._id(c))
	cells[ids[0]] = {"crop": "R", "state": "growing", "ready_at": f._now() + 100000}
	cells[ids[1]] = {"state": "tilled", "crop": null}
	f.predictor.commit(cells, f.session.version)
	f._refresh_hud()
	assert_str(f._last_bulk.action).is_equal("explore")
	f.hud._seed_buttons.L.pressed.emit()
	assert_str(f._last_bulk.crop).is_equal("L")
	f._refresh_hud()
	assert_str(f._last_bulk.crop).is_equal("L")
	f.session.state.inventory.seeds.L.bound = 0
	f._refresh_hud()
	assert_str(f.hud.selected_crop).is_equal("R")
	assert_str(f._explicit_crop).is_empty()
	assert_str(f._last_bulk.action).is_equal("explore")

func _salad_farm(transport: FakeTransport) -> Node:
	var f := await _online_farm(transport)
	f.set_process(false)
	f.session.state.journey = {"version": 1, "facts": ["met_nursery", "workbench"],
		"unlocks": ["bistro", "kitchen", "crop_C"], "exploration": {"round": 1, "collected": []}}
	f.session.state.xp.first_harvest_crops = ["R"]
	f.session.state.inventory.seeds.C.bound = 2
	for cell in _soil(f.bp, 3):
		f.session.state.cells[f._id(cell)] = {"state": "tilled", "crop": null}
	f.predictor.commit(f.session.state.cells, f.session.version)
	return f

func test_recommended_crop_is_selected_and_sent_from_a_world_plot_after_work_finishes() -> void:
	var transport := FakeTransport.new([])
	var f := await _salad_farm(transport)
	f.hud.set_cta_busy(1)
	f._refresh_hud()
	assert_str(f.hud._cta.text).is_equal("Sow 1 Carrot")
	assert_str(f.hud.selected_crop).is_equal("C")
	assert_bool(f.hud._seed_row.visible).is_false()
	f._set_work_mode(true)
	assert_bool(f.hud._seed_row.visible).is_true()
	assert_bool(f.hud._seed_buttons.C.disabled).is_false()
	assert_str(str(f.hud._seed_buttons.C.theme_type_variation)).is_equal("ChoiceSelectedButton")
	var next: Dictionary = f.session.state.duplicate(true)
	var cell: Vector2i = _soil(f.bp, 1)[0]
	next.cells[f._id(cell)] = {"state": "sown", "crop": "C", }
	next.inventory.seeds.C.bound -= 1
	transport.responses.append({"status": 200, "json": {"version": 1, "state": next}})
	f._set_work_mode(true)
	f._tap_cell(cell)
	assert_bool(_run_until(f, func(): return transport.requests.size() == 1)).is_true()
	assert_str(transport.requests[0].body.type).is_equal("sow_cells")
	assert_str(transport.requests[0].body.payload.crop).is_equal("C")
	assert_str(transport.requests[0].body.payload.lot).is_equal("bound")

func test_manual_sow_queue_keeps_its_crop_when_recommendations_or_seed_counts_change() -> void:
	var f := await _salad_farm(FakeTransport.new([]))
	f._refresh_hud()
	f.hud._seed_buttons.L.pressed.emit()
	assert_str(f.hud._cta.text).is_equal("Sow 3 Lettuce")
	f._on_cta()
	assert_int(f.runner.pending_count()).is_equal(3)
	f._explicit_crop = ""
	f._refresh_hud()
	assert_str(f._last_bulk.crop).is_equal("C")
	assert_str(f._payload_for("sow", ["4,6"]).crop).is_equal("L")
	f.session.state.inventory.seeds.L.bound = 0
	f._refresh_hud()
	assert_str(f.hud.selected_crop).is_equal("L")
	f.runner.cancel_pending()
	f._refresh_hud()
	assert_str(f.hud.selected_crop).is_equal("C")

func test_journey_bag_opens_inventory_in_the_farm_and_back_only_closes_it() -> void:
	var transport := FakeTransport.new([])
	var f := await _salad_farm(transport)
	var original: Dictionary = f.session.state.duplicate(true)
	f.hud._life_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(f.hud.modal_open()).is_true()
	assert_bool(f.life_sheet.visible).is_true()
	assert_str(f.life_sheet._title.text).is_equal("Your bag")
	assert_str(f.life_sheet.active.target).is_equal("supplies")
	assert_bool(f.life_sheet.active is BagPanel).is_true()
	assert_bool(f.life_sheet._journey_button.visible).is_false()
	assert_bool(f.life_sheet._tabs_row.visible).is_false()
	assert_bool(f.is_back_navigation_locked()).is_true()
	assert_bool(f.hud.modal_open()).is_false()
	assert_bool(f.hud._bottom.visible).is_true()
	assert_int(transport.requests.size()).is_equal(0)
	assert_that(f.session.state).is_equal(original)

func test_authoritative_chapter_response_updates_goals_weather_and_completion_feedback_once() -> void:
	var f := await _online_farm(FakeTransport.new([]))
	f.set_process(false)
	var finished := _finished_first_chapter(f.session.state)
	f.session._adopt({"version": 1, "state": finished, "server_time": 1000,
		"derived": {"chapter_index": 0, "next_chapter_opens_at": 100000}})
	assert_str(f.hud._goals_header.text).is_equal("Goals · 5/5")
	assert_str(f.hud._toast_label.text).is_equal("Chapter 1 complete")
	f.hud._toast_left = 0.5
	f._refresh_hud()
	assert_float(f.hud._toast_left).is_equal(0.5)
	var next := finished.duplicate(true)
	next.clock.chapter_index = 1
	next.clock.field_condition = "rain"
	next.chapters.append({"status": "active", "step_flags": {}})
	f.session._adopt({"version": 2, "state": next, "server_time": 100000,
		"derived": {"chapter_index": 1, "next_chapter_opens_at": null}})
	assert_str(f.hud._goals_header.text).is_equal("Goals · 0/1")
	assert_str(f.hud._goals_title.text).is_equal("Chapter 2 · A rainy day")
	assert_str(f.hud._toast_label.text).is_equal("Chapter 2 · A rainy day")
	assert_int(f.hud.goal_labels().size()).is_equal(1)

func test_next_chapter_deadline_refreshes_the_server_before_changing_the_chapter() -> void:
	var transport := FakeTransport.new([])
	var f := await _online_farm(transport)
	f.set_process(false)
	var finished := _finished_first_chapter(f.session.state)
	var next := finished.duplicate(true)
	next.clock.chapter_index = 1
	next.clock.field_condition = "rain"
	next.chapters.append({"status": "active", "step_flags": {}})
	transport.responses.append({"status": 200, "json": {"version": 1, "state": next, "server_time": 1000,
		"derived": {"chapter_index": 1, "next_chapter_opens_at": null}}})
	f.session._adopt({"version": 1, "state": finished, "server_time": 1000,
		"derived": {"chapter_index": 0, "next_chapter_opens_at": 999}})
	assert_int(f.session.state.clock.chapter_index).is_equal(0)
	assert_str(f.hud._goals_feedback.text).is_equal("Checking next chapter...")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(1)
	assert_str(transport.requests[0].method).is_equal("GET")
	assert_int(f.session.state.clock.chapter_index).is_equal(1)
	assert_str(f.hud._goals_header.text).is_equal("Goals · 0/1")
	for attempt in 3:
		f._refresh_hud()
		await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(1)

func test_failed_chapter_refresh_is_throttled_and_offline_never_advances_the_chapter() -> void:
	var transport := FakeTransport.new([{"error": "timeout"}, {"error": "timeout"}])
	var f := await _online_farm(transport)
	f.set_process(false)
	f.session._adopt({"version": 1, "state": _finished_first_chapter(f.session.state), "server_time": 1000,
		"derived": {"chapter_index": 0, "next_chapter_opens_at": 999}})
	for attempt in 3:
		f._refresh_hud()
		await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(1)
	assert_int(f.session.state.clock.chapter_index).is_equal(0)
	f._next_chapter_refresh_ticks = 0
	f._refresh_hud()
	await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(2)
	assert_bool(f.session.offline).is_true()
	f._next_chapter_refresh_ticks = 0
	f._refresh_hud()
	await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(2)
	assert_int(f.session.state.clock.chapter_index).is_equal(0)

func test_builds_ground_props_and_player_at_spawn() -> void:
	var f: Node = await _farm()
	assert_object(f.get_node("Ground").mesh).is_not_null()
	# 房子 + 仓库 + 水井。12 个田畦模型随自由格子种田退役：开垦状态改由地面表达。
	assert_int(f.prop_count()).is_equal(3)
	assert_that(f.mover.cell()).is_equal(f.bp.anchor("spawn"))
	assert_bool(f.get_node("Player").get_child_count() >= 1).is_true()
	assert_str(f.title.text).is_not_empty()

func test_watering_needs_no_weather_agreement() -> void:
	# 天气三选一的照料退役：浇水就是浇水，不再按播种当日的田况分岔。
	var f := await _online_farm(FakeTransport.new([]))
	var cell: Vector2i = _soil(f.bp, 1)[0]
	var id: String = f._id(cell)
	f.session.state.clock.field_condition = "rain"
	f.session.state.cells[id] = {"state": "sown", "crop": "R"}
	f._on_server_state(f.session.state, f.session.version)
	assert_str(NextStep.step_for(f._cells_view()[id], f._now())).is_equal("water")
	assert_bool(f._payload_for("water", [id]).has("kind")).is_false()


func test_ground_click_has_a_destination_and_rejects_unreachable_land() -> void:
	var f := await _farm()
	f._on_ground_tapped(f.bp.cell_to_world(Vector2i(3, 6)))
	assert_bool(f.hints._destination_visible).is_true()
	assert_bool(f.hints._reachable).is_true()
	f._on_ground_tapped(f.bp.cell_to_world(Vector2i(-100, -100)))
	assert_bool(f.hints._reachable).is_false()
	assert_bool(f.hud._toast.visible).is_true()

func test_modals_hide_actions_and_consume_back_before_leaving() -> void:
	var f := await _online_farm(FakeTransport.new([]))
	f._open_stall()
	assert_bool(f.hud.modal_open()).is_true()
	assert_bool(f.hud._bottom.visible).is_false()
	f.hud.show_modal(f.hud._goals)
	assert_bool(f.stall.visible).is_false()
	assert_bool(f.hud._goals.visible).is_true()
	assert_bool(f.is_back_navigation_locked()).is_true()
	assert_bool(f.hud.modal_open()).is_false()
	assert_bool(f.hud._bottom.visible).is_true()

func test_process_moves_player_without_automatic_camera_follow() -> void:
	var f: Node = await _farm()
	var cam := f.get_node("Camera3D") as Camera3D
	var cam_before := cam.position
	# 目标取相对出生点的近格：写死坐标会在布局挪动家园后变成 27m 的长途，
	# 240 帧（4 秒）根本走不到，测试就变成在考寻路距离。
	var target: Vector2i = f.bp.anchor("spawn") + Vector2i(-4, -4)
	f._on_ground_tapped(f.bp.cell_to_world(target))
	for i in 240:
		f._process(1.0 / 60.0)
	var player := f.get_node("Player") as Node3D
	assert_that(f.mover.cell()).is_equal(target)
	assert_that(player.position).is_equal(f.mover.position)
	# Walking remains server/navigation driven; the manually framed camera stays still.
	f.mover.position = f._field_center + Vector3(12, 0, 0)
	f._process(0.0)
	assert_vector(cam.position).is_equal(cam_before)
	assert_bool(cam.is_position_behind(f.player.position)).is_false()

func test_rig_faces_forward_and_keeps_animating_at_farm_camera_distance() -> void:
	# 2026-09-04 晚真机：走路背朝前（rig 脸在 +Z）；动画全丢（RigActivity 16 m 休眠，相机 18 m）。
	var f: Node = await _farm()
	assert_float(f._rig.rotation.y).is_equal_approx(PI, 0.001)
	var act: RigActivity = null
	for c in f._rig.get_children():
		if c is RigActivity:
			act = c
	assert_object(act).is_not_null()
	var cam := f.get_node("Camera3D") as Camera3D
	var dist := cam.position.distance_to(f.player.position)
	assert_bool(act.sleep_distance > dist + 5.0).override_failure_message(
		"相机离玩家 %.1f m，休眠阈值 %.1f m 不够" % [dist, act.sleep_distance]).is_true()

func test_exit_button_wired_to_router() -> void:
	var f: Node = await _farm()
	assert_int((f.exit_btn as Button).pressed.get_connections().size()).is_equal(1)

func test_tap_ground_walks_there() -> void:
	var f: Node = await _farm()
	# 离出生点有一段距离的一块可开垦地：点它应该先走过去。
	var target: Vector2i = f.bp.anchor("spawn") + Vector2i(0, -4)
	f._tap_cell(target)
	assert_bool(f.mover.is_moving()).is_true()

func test_missing_blueprint_bails_without_crashing() -> void:
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"layout_patch_id": "no_such_id", "revision": 1})
	add_child(auto_free(scene))
	await get_tree().process_frame
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = Vector2(10, 10)
	scene._unhandled_input(down)
	scene._on_ground_tapped(Vector3.ZERO)
	assert_that(scene.mover).is_null()

func test_title_and_exit_button_do_not_overlap_on_phone_width() -> void:
	var f: Node = await _farm()
	var safe := f.get_node("HUD/SafeArea") as SafeAreaMargin
	safe.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	safe.size = Vector2(360, 800)
	safe.apply_margins(Rect2i(), Vector2i(360, 800), Vector2(360, 800))
	await get_tree().process_frame
	await get_tree().process_frame
	var title_rect: Rect2 = (f.title as Control).get_global_rect()
	var exit_rect: Rect2 = (f.exit_btn as Control).get_global_rect()
	assert_bool(title_rect.intersects(exit_rect)).is_false()
	var root_rect: Rect2 = (f.get_node("HUD/SafeArea/Root") as Control).get_global_rect()
	assert_bool(root_rect.grow(0.5).encloses(title_rect)).is_true()

func test_crops_render_outside_props() -> void:
	var f: Node = await _farm()
	var before: int = f.prop_count()
	var cells := {}
	for bed in [{"cells": _soil(f.bp, 9)}]:
		for c in bed.cells:
			cells["%d,%d" % [c.x, c.y]] = {"state": "growing", "crop": "R", "watered_at": 0, "ready_at": 400}
	f.render_cells(cells, 400)
	assert_int(f.prop_count()).is_equal(before)
	assert_int(int(f.crop_field.cell_counts()["R"])).is_equal(9)
	await get_tree().process_frame

func test_without_farm_in_session_stays_offline_greybox() -> void:
	var s := FarmSession.new(ApiClient.new("https://example.test/v1", FakeTransport.new([]).callable()))
	s.client.token = "tok"
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FIX), "session": s})
	add_child(auto_free(scene))
	await get_tree().process_frame
	assert_object(scene.session).is_null()
	assert_object(scene.predictor).is_null()
	assert_str(scene.hud._cta.text).is_equal("Offline — farm not connected")
	assert_bool(scene.hud._cta.disabled).is_true()

func test_servers_blueprint_beats_the_locally_chosen_one() -> void:
	var bp_c := FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_c", 2))
	var s := _session_with_farm(FakeTransport.new([]), "sh_c", _wild_cells(bp_c))
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_b", 2)), "session": s})
	add_child(auto_free(scene))
	await get_tree().process_frame
	# 旧存档继续以服务端的地理身份和原地形为准；合并后标题统一叫农场。
	assert_str(scene.geo_blueprint.layout_patch_id).is_equal("sh_c")
	assert_str(scene.bp.layout_patch_id).is_equal("homestead_a")
	assert_str(scene.title.text).is_equal(L10n.text("My Farm"))
	assert_str(FarmChoice.load().layout_patch_id).is_equal("sh_c")

func test_work_mode_walks_to_wild_ground_then_tills_it_and_tells_the_server() -> void:
	# 明确选择劳作后才开垦；先走到地头，干完仍由服务端结算。
	var t := FakeTransport.new([{"status": 200, "json": {"version": 1, "state": {"cells": {}}}}])
	var f: Node = await _online_farm(t)
	# 出生点旁边一块**可开垦**的地：够近能走到，又不在脚下。
	# 方向不能随便取：出生点正东就是那条贯穿南北的主路，(2,2) 会落在路上，
	# 点上去只是走过去、不会开垦，断言就会莫名其妙地红。
	var cell: Vector2i = f.bp.anchor("spawn") + Vector2i(-2, -2)
	assert_bool(f.bp.mask_has("cultivable", cell)).override_failure_message(
		"测试选的目标格 %s 不可开垦——布局改过了，挑一格新的" % cell).is_true()
	f._set_work_mode(true)
	f._tap_cell(cell)
	assert_bool(f.runner.is_busy()).is_true()
	f._process(0.0)
	assert_bool(f.runner.paused).override_failure_message("应先走到地头再开工").is_true()
	assert_bool(f.mover.is_moving()).is_true()
	assert_bool(f._action_locked()).override_failure_message("走路时不能锁动画").is_false()
	assert_bool(_run_until(f, func(): return t.requests.size() == 1)).is_true()
	assert_str(str(t.requests[0].body.type)).is_equal("till_cells")
	assert_str(str(t.requests[0].body.payload.cell_ids[0])).is_equal(f._id(cell))
	assert_bool(f.player.position.distance_to(f.bp.cell_to_world(cell)) < 1.6).override_failure_message(
		"干活时人应该站在那格旁边").is_true()

func test_normal_in_flight_plot_command_does_not_flash_the_reconnect_control() -> void:
	var f := await _online_farm(FakeTransport.new([]))
	f.set_process(false)
	var next: Dictionary = f.session.state.duplicate(true)
	f.session.client.transport = func(_method, _url, _headers, _body):
		await release_farm_command
		return ApiClient.Response.new(true, 200, {"version": 1, "state": next})
	f._on_cell_done(_soil(f.bp, 1)[0], "till")
	assert_int(f._in_flight).is_equal(1)
	assert_bool(f.session.has_unconfirmed_command()).is_true()
	f._refresh_hud()
	assert_bool(f.hud._reconnect.visible).is_false()
	release_farm_command.emit()
	await get_tree().process_frame
	assert_int(f._in_flight).is_equal(0)
	assert_bool(f.session.has_unconfirmed_command()).is_false()
	assert_bool(f.hud._reconnect.visible).is_false()

func test_unresolved_plot_reply_shows_recovery_only_after_the_request_finishes() -> void:
	var f := await _online_farm(FakeTransport.new([]))
	f.set_process(false)
	var calls := [0]
	f.session.client.transport = func(_method, _url, _headers, _body):
		calls[0] += 1
		await release_farm_command
		return ApiClient.Response.new(true, 504, {})
	f._on_cell_done(_soil(f.bp, 1)[0], "till")
	f._refresh_hud()
	assert_bool(f.hud._reconnect.visible).is_false()
	release_farm_command.emit()
	await get_tree().process_frame
	assert_int(f._in_flight).is_equal(0)
	assert_bool(f.session.offline).is_false()
	assert_bool(f.hud._reconnect.visible).is_true()
	assert_bool(await f.session.send("buy_seeds", {"crop": "R", "qty": 1})).is_false()
	assert_str(f.session.last_error_code).is_equal("PENDING_ACTION")
	assert_int(calls[0]).is_equal(1)
	var body := {"version": 1, "state": f.session.state.duplicate(true)}
	f.session.client.transport = FakeTransport.new([
		{"status": 200, "json": body}, {"status": 200, "json": body}]).callable()
	await f._recover_connection()
	assert_bool(f.session.has_unconfirmed_command()).is_false()
	assert_bool(f.hud._reconnect.visible).is_false()

func test_batch_queues_each_plots_own_next_step() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	var bed: Array = _soil(f.bp, 3)
	# 第二格已开垦：它的下一步是播种，不是开垦
	f.predictor.cells["%d,%d" % [bed[1].x, bed[1].y]] = {"state": "tilled", "crop": null}
	assert_int(f._queue_plots(bed)).is_equal(3)
	assert_str(f.runner.current_action()).is_equal("")
	f._process(0.0)
	assert_str(f.runner.current_action()).is_equal("till")

func test_tapping_a_growing_plot_shows_the_countdown_instead_of_acting() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	var cell: Vector2i = _soil(f.bp, 1)[0]
	var id := "%d,%d" % [cell.x, cell.y]
	f.predictor.cells[id] = {"state": "growing", "crop": "R", "watered_at": 0, "ready_at": f._now() + 90_000}
	f._set_work_mode(true)
	f._tap_cell(cell)
	assert_bool(f.runner.is_busy()).is_false()
	assert_object(f._work_label).is_not_null()
	assert_str(f._work_label.text).starts_with("Growing · 01:")

func test_cta_names_the_next_step_and_does_it_for_every_plot() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	# 开局一格未开垦：CTA 先让玩家挑地下锄，而不是列出一堆固定田畦。
	for cell in _soil(f.bp, 4):
		f.predictor.cells[f._id(cell)] = {"state": "tilled", "crop": null}
	f._refresh_hud()
	assert_str(f.hud._cta.text).is_equal("Sow 4 Radish")
	f._on_cta()
	assert_int(f.runner.pending_count()).is_equal(4)



func test_cta_switches_to_sow_only_when_seeds_exist() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	f.session.state.chapters[0].step_flags.first_harvest = true
	for cell in _soil(f.bp, 3):
		f.predictor.cells[f._id(cell)] = {"state": "tilled", "crop": null}
	f.session.state.inventory.seeds.R.bound = 0
	f.session.state.inventory.seeds.L.bound = 0
	f._refresh_hud()
	assert_str(f.hud._cta.text).is_equal("Buy seeds at the stall")
	f.session.state.inventory.seeds.L.bound = 3
	f._refresh_hud()
	assert_str(f.hud._cta.text).is_equal("Sow 3 Lettuce")
	assert_bool(f.hud._seed_row.visible).is_false()
	f._set_work_mode(true)
	assert_bool(f.hud._seed_row.visible).is_true()

func test_locally_invalid_action_is_aborted_and_explained_without_a_request() -> void:
	var t := FakeTransport.new([])
	var f: Node = await _online_farm(t)
	# 已经开垦过的地再开垦一次：本地就能判定不合法（WRONG_STATE），根本不该发请求。
	var cell: Vector2i = _soil(f.bp, 1)[0]
	f.predictor.cells[f._id(cell)] = {"state": "tilled", "crop": null}
	f.runner.enqueue([cell], "till")
	f._process(0.0)
	assert_bool(f.hud._toast.visible).is_true()
	assert_str(f.hud._toast_label.text).is_equal("That plot isn't ready for this step")
	assert_bool(f.runner.is_busy()).is_false()
	f._process(ActionRunner.ACTION_S + 0.1)
	assert_int(t.requests.size()).is_equal(0)

func test_server_rejection_is_shown_and_prediction_rolled_back() -> void:
	var t := FakeTransport.new([{"status": 422, "json": {"code": "WRONG_STATE", "detail": "x"}}])
	var f: Node = await _online_farm(t)
	var cell: Vector2i = _soil(f.bp, 1)[0]
	var id := "%d,%d" % [cell.x, cell.y]
	f._set_work_mode(true)
	f._tap_cell(cell)
	assert_bool(_run_until(f, func(): return t.requests.size() == 1)).is_true()
	await get_tree().process_frame
	assert_str(f.hud._toast_label.text).is_equal("That plot isn't ready for this step")
	# 回滚后这块地回到荒地——稀疏存储下就是从视图里消失。
	assert_bool(f.predictor.view().has(id)).is_false()

func test_goals_and_coins_follow_server_state() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	assert_str(f.hud._goals_header.text).is_equal("Goals · 1/5")
	f.session.state.xp.first_harvest_crops = ["R"]
	f.session.state.chapters[0].step_flags.first_harvest = true
	f.session.state.wallet = 204
	f.session.state_changed.emit(f.session.state, 3)
	assert_str(f.hud._goals_header.text).is_equal("Goals · 5/5")
	assert_str(f.hud._coins.text).is_equal("204")

func test_stall_sells_and_toasts_the_coins() -> void:
	var t := FakeTransport.new([{"status": 200, "json": {"version": 2,
		"state": {"cells": {}, "wallet": 196, "inventory": {"produce": {"R": 0}, "seeds": {}}}}}])
	var f: Node = await _online_farm(t)
	f.session.state.inventory.produce.R = 2
	f._open_stall()
	assert_bool(f.stall.visible).is_true()
	await f._on_sell([{"kind": "produce", "id": "R", "qty": 2}])
	assert_str(str(t.requests[0].body.type)).is_equal("sell_at_stall")
	assert_str(f.hud._toast_label.text).is_equal("+16 coins")
	assert_str(f.hud._coins.text).is_equal("196")

func test_action_status_shows_walking_then_the_verb() -> void:
	var f: Node = await _online_farm(FakeTransport.new([{"status": 200, "json": {"version": 1, "state": {"cells": {}}}}]))
	f._set_work_mode(true)
	f._tap_cell(_soil_near_spawn(f))
	f._process(0.0)
	f._process(0.1)
	assert_str(f.hud._cta.text).starts_with("Walking...")
	assert_bool(_run_until(f, func(): return not f.runner.paused and f.runner.is_busy())).is_true()
	f._process(0.1)
	assert_str(f.hud._cta.text).starts_with("Tilling…")

## 队列停住有两种原因：人还在路上，和命令还挂在网络上。两种都显示「正在前往」时，
## 一次回包变慢看起来就像人走不动了——真机验收时正是被这条误导，查错了方向。
func test_action_status_distinguishes_walking_from_waiting_on_the_server() -> void:
	var f: Node = await _online_farm(FakeTransport.new([{"status": 200, "json": {"version": 1, "state": {"cells": {}}}}]))
	f._set_work_mode(true)
	f._tap_cell(_soil_near_spawn(f))
	f._process(0.0)
	f._process(0.1)
	assert_str(f.hud._cta.text).starts_with("Walking...")
	f.mover.stop()          # 已经站定……
	f._in_flight = 1        # ……但上一条命令还没回来
	f._process(0.1)
	assert_str(f.hud._cta.text).starts_with("Syncing...")

func test_cta_goes_busy_while_the_queue_runs_and_pressing_it_again_adds_nothing() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	for cell in _soil(f.bp, 4):
		f.predictor.cells[f._id(cell)] = {"state": "tilled", "crop": null}
	f._refresh_hud()
	f._on_cta()
	f._process(0.0)
	assert_bool(f.hud._cta.disabled).is_true()
	assert_str(f.hud._status_label.text).is_equal("4 plots remaining")
	f._on_cta()                                   # 再按一下：什么都不会多排
	assert_int(f.runner.pending_count()).is_equal(4)

func test_goals_stay_in_the_modal_after_the_first_goal_completes() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	assert_bool(f.hud._goals.visible).is_false()
	f.session.state_changed.emit(f.session.state, 2)
	assert_bool(f.hud._goals.visible).is_false()
	assert_str(f.hud._goals_header.text).is_equal("Goals · 1/5")
	f.hud._goals_header.pressed.emit()
	assert_bool(f.hud._goals.visible).is_true()

func test_ripening_flips_the_cta_and_the_crop_without_any_input() -> void:
	# 成熟是时间派生的：没有回包、没有输入，也必须靠每秒一次的刷新自己变过来。
	var f: Node = await _online_farm(FakeTransport.new([]))
	var cell: Vector2i = _soil(f.bp, 1)[0]
	var id := "%d,%d" % [cell.x, cell.y]
	for other in _soil(f.bp, 9):
		f.predictor.cells[f._id(other)] = {"state": "tilled", "crop": null, "ready_at": null}
	f.predictor.cells[id] = {"state": "growing", "crop": "R", "watered_at": f._now() - 1000, "ready_at": f._now() + 800}
	f._refresh_hud()
	assert_str(f.hud._cta.text).is_equal("Sow 6 Radish")
	f.session.clock_offset_ms += 1000            # 服务端时间走过成熟点
	f._process(f.TICK_S + 0.01)                   # 一个节拍
	assert_str(f.hud._cta.text).is_equal("Harvest 1 plot")
	assert_str(f.hud._timer_label.text).is_equal("Harvest ready")
	var mm: MultiMesh = f.crop_field._mm["R"].multimesh
	# Godot 4.7's dummy headless renderer returns identity for every MultiMesh transform.
	# Check the growth decision here; native rendering probes cover the actual instance scale.
	if DisplayServer.get_name() == "headless":
		assert_int(CropField.stage_of(f.predictor.cells[id], f._now())).is_equal(3)
	else:
		assert_float(mm.get_instance_transform(0).basis.get_scale().y).is_equal_approx(CropField.STAGE_SIZE[3].y * f.bp.cell_m, 0.001)

func test_periodic_refresh_does_not_unbusy_the_cta() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	for cell in _soil(f.bp, 4):
		f.predictor.cells[f._id(cell)] = {"state": "tilled", "crop": null}
	f._refresh_hud()
	f._on_cta()
	f._process(0.0)
	f._process(f.TICK_S + 0.01)
	assert_bool(f.hud._cta.disabled).is_true()
	assert_bool(f.hud._cancel.visible).is_true()
	assert_str(f.hud._status_label.text).contains("remaining")

## 赶路途中 mover 被冻住，队列会永久停在「正在前往…」：paused 只在到站时清除，而到站
## 完全依赖 mover 推进。真机 2026-09-17 两次复现（掉线重连时 travel_busy 那支提前返回，
## 跳过了 mover.step）。看门狗负责兜底，不管冻结出自哪条路径。
func test_a_frozen_walk_recovers_instead_of_hanging_the_queue_forever() -> void:
	var f: Node = await _online_farm(FakeTransport.new([{"status": 200, "json": {"version": 1, "state": {"cells": {}}}}]))
	f._set_work_mode(true)
	f._tap_cell(_soil_near_spawn(f, 6))
	f._process(0.0)
	f._process(0.1)
	assert_bool(f.runner.paused).is_true()
	assert_bool(f.mover.is_moving()).is_true()
	# 模拟「mover 不再被推进」：位置钉住不动（_process 每帧会用 CharacterModel 覆写
	# speed，所以调速度没用），看门狗应当在阈值后自己停表。
	var frozen: Vector3 = f.mover.position
	f._walk_stall_pos = frozen
	var ticks := 0
	while f.mover.is_moving() and ticks < 100:
		f.mover.position = frozen
		f._watch_walk_stall(0.1)
		ticks += 1
	assert_bool(f.mover.is_moving()).override_failure_message("走不动时必须自己停表").is_false()
	f._process(0.1)
	assert_bool(f.runner.paused).override_failure_message("停表后队列应当解开、就地开工，而不是无限等待").is_false()

## travel_busy 的提前返回不能把人冻在半路——它只该跳过劳作与 HUD 的处理。
func test_travel_busy_still_advances_the_walk() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	assert_bool(f.mover.set_target_cell(f.bp.anchor("spawn") + Vector2i(0, -4))).is_true()
	var before: Vector3 = f.mover.position
	f.online = preload("res://modules/net/online_space.gd").new()
	auto_free(f.online)
	f.online.travel_busy = true
	f._process(0.1)
	assert_vector(f.mover.position).is_not_equal(before)

func test_default_taps_walk_across_wild_tilled_and_ripe_ground_without_commands() -> void:
	var transport := FakeTransport.new([])
	var farm := await _online_farm(transport)
	farm.set_process(false)
	assert_bool(farm.work_mode).is_false()
	assert_bool(farm.camera_pan.hold_enabled).is_false()
	var spawn: Vector2i = farm.bp.anchor("spawn")
	var offsets := [Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1)]
	for index in offsets.size():
		var offset: Vector2i = offsets[index]
		var cell: Vector2i = spawn + offset
		if index == 1: farm.session.state.cells[farm._id(cell)] = {"state": "tilled"}
		if index == 2: farm.session.state.cells[farm._id(cell)] = {"state": "growing", "crop": "R", "ready_at": 0, "watered_at": -1000}
		farm._on_server_state(farm.session.state, 1)
		farm._tap_cell(cell)
		assert_bool(farm.runner.is_busy()).is_false()
		for frame in 180: farm._process(1.0 / 60.0)
		assert_that(farm.mover.cell()).is_equal(cell)
	assert_array(transport.requests).is_empty()

func test_walking_hold_and_working_touch_cancel_never_queue_farming() -> void:
	var transport := FakeTransport.new([])
	var farm := await _online_farm(transport)
	farm.set_process(false)
	var point: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(farm.bp.anchor("spawn") + Vector2i(-1, 0)))
	farm.camera_pan.begin(0, point)
	farm.camera_pan.step(0.4, farm.cam)
	assert_array(farm._brush_cells).is_empty()
	farm.camera_pan.end(0, point)
	assert_bool(farm.runner.is_busy()).is_false()
	farm.hud._mode_toggle.set_pressed(true)
	assert_bool(farm.work_mode).is_true()
	for interruption in ["cancel", "pinch", "background", "walk"]:
		farm._set_work_mode(true)
		farm.camera_pan.begin(0, point)
		farm.camera_pan.step(0.4, farm.cam)
		assert_bool(farm._brush_cells.is_empty()).is_false()
		match interruption:
			"cancel": farm.camera_pan.end(0, point, true)
			"pinch":
				farm.camera_pan.begin(1, point + Vector2(50, 0))
				farm.camera_pan.end(0, point)
				farm.camera_pan.end(1, point + Vector2(50, 0))
			"background": farm._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
			"walk": farm.hud._mode_toggle.set_pressed(false)
		assert_array(farm._brush_cells).is_empty()
		assert_bool(farm.runner.is_busy()).is_false()
	assert_array(transport.requests).is_empty()

func test_explicit_working_hold_release_queues_and_walking_cancels_pending_work() -> void:
	var farm := await _online_farm(FakeTransport.new([]))
	farm.set_process(false)
	farm.hud._mode_toggle.set_pressed(true)
	var cell: Vector2i = farm.bp.anchor("spawn") + Vector2i(-1, 0)
	var point: Vector2 = farm.cam.unproject_position(farm.bp.cell_to_world(cell))
	farm.camera_pan.begin(0, point)
	farm.camera_pan.step(0.4, farm.cam)
	farm.camera_pan.end(0, point)
	assert_bool(farm.runner.contains(cell)).is_true()
	farm.hud._mode_toggle.set_pressed(false)
	assert_bool(farm.runner.is_busy()).is_false()
	assert_bool(farm.camera_pan.hold_enabled).is_false()
