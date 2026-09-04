extends GdUnitTestSuite
## 农场场景：蓝图 → 地表/道具/玩家/相机；点田自动做下一步；先走过去再干活；服务端对账。

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

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
		"clock": {"chapter_index": 0, "field_condition": "sunny"}, "xp": {"total": 0, "first_clear_cells": [], "first_harvest_crops": []},
		"stall": {"settled": 0}, "sales_facts": {}}
	return s

func _wild_cells(bp: FarmBlueprint) -> Dictionary:
	var cells := {}
	for bed in bp.beds():
		for c in bed.cells:
			cells["%d,%d" % [c.x, c.y]] = {"state": "wild", "crop": null, "ready_at": null}
	for c in bp.reserved_bed().get("cells", []):
		cells["%d,%d" % [c.x, c.y]] = {"state": "wild", "crop": null, "ready_at": null}
	return cells

func _online_farm(t: FakeTransport) -> Node:
	var bp := FarmBlueprint.load_file(FIX)
	var s := _session_with_farm(t, "", _wild_cells(bp))
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": bp, "session": s})
	add_child(auto_free(scene))
	await get_tree().process_frame
	return scene

## 推进到某条件成立或超时（秒）。
func _run_until(f: Node, cond: Callable, seconds := 20.0) -> bool:
	var t := 0.0
	while t < seconds:
		f._process(0.1)
		t += 0.1
		if cond.call():
			return true
	return false

func test_builds_ground_props_and_player_at_spawn() -> void:
	var f: Node = await _farm()
	assert_object(f.get_node("Ground").mesh).is_not_null()
	# house + storage + well + exit + 9 田格 + 3 预留格
	assert_int(f.prop_count()).is_equal(4 + 9 + 3)
	assert_that(f.mover.cell()).is_equal(Vector2i(3, 3))
	assert_bool(f.get_node("Player").get_child_count() >= 1).is_true()
	assert_str(f.title.text).is_equal("Fixture Grid")

func test_process_moves_player_and_camera_follows() -> void:
	var f: Node = await _farm()
	var cam := f.get_node("Camera3D") as Camera3D
	var cam_before := cam.position
	f._on_ground_tapped(f.bp.cell_to_world(Vector2i(3, 6)))
	for i in 240:
		f._process(1.0 / 60.0)
	var player := f.get_node("Player") as Node3D
	assert_that(f.mover.cell()).is_equal(Vector2i(3, 6))
	assert_that(player.position).is_equal(f.mover.position)
	# 相机必须真的跟着挪，且精确钉在 45° 俯角 × CAM_DIST、跟随点南移 CAM_AHEAD 的公式上。
	assert_bool(cam.position != cam_before).is_true()
	var phi := deg_to_rad(45.0)
	var expected := player.position + Vector3(0.0, 16.0 * sin(phi), 16.0 * cos(phi) + f.CAM_AHEAD)
	assert_vector(cam.position).is_equal_approx(expected, Vector3(0.001, 0.001, 0.001))

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
	f._tap_cell(Vector2i(3, 6))
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
	for bed in f.bp.beds():
		for c in bed.cells:
			cells["%d,%d" % [c.x, c.y]] = {"state": "growing", "crop": "R", "care_done_at": 0, "ready_at": 400}
	f.render_cells(cells, 400)
	assert_int(f.prop_count()).is_equal(before)
	assert_int(int(f.crop_field.cell_counts()["R"])).is_equal(9)

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
	assert_str(scene.bp.layout_patch_id).is_equal("sh_c")
	assert_str(scene.title.text).is_equal(bp_c.display_name)
	assert_int(int(scene.crop_field.cell_counts()["weed"])).is_equal(12)
	assert_str(FarmChoice.load().layout_patch_id).is_equal("sh_c")

func test_tapping_a_wild_plot_walks_over_then_clears_it_and_tells_the_server() -> void:
	# 没有工具：点草地就是清理。先走到地头（计时暂停），到了才干 2 秒，干完发命令。
	var t := FakeTransport.new([{"status": 200, "json": {"version": 1, "state": {"cells": {}}}}])
	var f: Node = await _online_farm(t)
	var cell: Vector2i = f.bp.beds()[0].cells[0]
	f._tap_cell(cell)
	assert_bool(f.runner.is_busy()).is_true()
	f._process(0.0)
	assert_bool(f.runner.paused).override_failure_message("应先走到地头再开工").is_true()
	assert_bool(f.mover.is_moving()).is_true()
	assert_bool(f._action_locked()).override_failure_message("走路时不能锁动画").is_false()
	assert_bool(_run_until(f, func(): return t.requests.size() == 1)).is_true()
	assert_str(str(t.requests[0].body.type)).is_equal("clear_cells")
	assert_str(str(t.requests[0].body.payload.cell_ids[0])).is_equal("%d,%d" % [cell.x, cell.y])
	assert_bool(f.player.position.distance_to(f.bp.cell_to_world(cell)) < 1.6).override_failure_message(
		"干活时人应该站在那格旁边").is_true()

func test_dragging_across_plots_queues_each_plots_own_next_step() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	var bed: Array = f.bp.beds()[0].cells
	# 第二格已翻土：它的下一步是播种，不是清理
	f.predictor.cells["%d,%d" % [bed[1].x, bed[1].y]].state = "tilled"
	assert_int(f._queue_plots(bed)).is_equal(3)
	assert_str(f.runner.current_action()).is_equal("")
	f._process(0.0)
	assert_str(f.runner.current_action()).is_equal("clear")

func test_tapping_a_growing_plot_shows_the_countdown_instead_of_acting() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	var cell: Vector2i = f.bp.beds()[0].cells[0]
	var id := "%d,%d" % [cell.x, cell.y]
	f.predictor.cells[id] = {"state": "growing", "crop": "R", "care_done_at": 0, "ready_at": f._now() + 90_000}
	f._tap_cell(cell)
	assert_bool(f.runner.is_busy()).is_false()
	assert_object(f._work_label).is_not_null()
	assert_str(f._work_label.text).starts_with("Growing · 01:")

func test_cta_names_the_next_step_and_does_it_for_every_plot() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	assert_str(f.hud._cta.text).is_equal("Clear 9 plots")
	f._on_cta()
	assert_int(f.runner.pending_count()).is_equal(9)

func test_cta_switches_to_sow_only_when_seeds_exist() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	for id in f.predictor.cells:
		f.predictor.cells[id].state = "tilled"
	f.session.state.inventory.seeds.R.bound = 0
	f.session.state.inventory.seeds.L.bound = 0
	f._refresh_hud()
	assert_str(f.hud._cta.text).is_equal("Buy seeds at the stall")
	f.session.state.inventory.seeds.L.bound = 3
	f._refresh_hud()
	assert_str(f.hud._cta.text).is_equal("Sow 3 Lettuce")
	assert_bool(f.hud._seed_row.visible).is_true()

func test_locally_invalid_action_is_aborted_and_explained_without_a_request() -> void:
	var t := FakeTransport.new([])
	var f: Node = await _online_farm(t)
	var cell: Vector2i = f.bp.beds()[0].cells[0]
	f.runner.enqueue([cell], "till")             # 荒地上翻土：本地就能判定不合法（WRONG_STATE）
	f._process(0.0)
	assert_bool(f.hud._toast.visible).is_true()
	assert_str(f.hud._toast_label.text).is_equal("That plot isn't ready for this step")
	assert_bool(f.runner.is_busy()).is_false()
	f._process(ActionRunner.ACTION_S + 0.1)
	assert_int(t.requests.size()).is_equal(0)

func test_server_rejection_is_shown_and_prediction_rolled_back() -> void:
	var t := FakeTransport.new([{"status": 422, "json": {"code": "WRONG_STATE", "detail": "x"}}])
	var f: Node = await _online_farm(t)
	var cell: Vector2i = f.bp.beds()[0].cells[0]
	var id := "%d,%d" % [cell.x, cell.y]
	f._tap_cell(cell)
	assert_bool(_run_until(f, func(): return t.requests.size() == 1)).is_true()
	await get_tree().process_frame
	assert_str(f.hud._toast_label.text).is_equal("That plot isn't ready for this step")
	assert_str(str(f.predictor.view()[id].state)).is_equal("wild")

func test_goals_and_coins_follow_server_state() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	assert_bool(f.hud._goals_header.text.begins_with("Goals · 0/7")).is_true()
	f.session.state.xp.first_harvest_crops = ["R"]
	f.session.state.wallet = 204
	f.session.state_changed.emit(f.session.state, 3)
	assert_bool(f.hud._goals_header.text.begins_with("Goals · 5/7")).is_true()
	assert_str(f.hud._coins.text).is_equal("Coins 204")

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
	assert_str(f.hud._coins.text).is_equal("Coins 196")

func test_action_status_shows_walking_then_the_verb() -> void:
	var f: Node = await _online_farm(FakeTransport.new([{"status": 200, "json": {"version": 1, "state": {"cells": {}}}}]))
	f._tap_cell(f.bp.beds()[0].cells[0])
	f._process(0.0)
	f._process(0.1)
	assert_str(f.hud._status_label.text).starts_with("Walking…")
	assert_bool(_run_until(f, func(): return not f.runner.paused and f.runner.is_busy())).is_true()
	f._process(0.5)
	assert_str(f.hud._status_label.text).starts_with("Clearing…")

func test_cta_goes_busy_while_the_queue_runs_and_pressing_it_again_adds_nothing() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	f._on_cta()
	f._process(0.0)
	assert_bool(f.hud._cta.disabled).is_true()
	assert_str(f.hud._cta.text).is_equal("Working… 9 plots left")
	f._on_cta()                                   # 再按一下：什么都不会多排
	assert_int(f.runner.pending_count()).is_equal(9)

func test_goals_collapse_after_the_first_goal_completes() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	assert_bool(f.hud._goals_list.visible).is_true()
	f.session.state.xp.first_clear_cells = ["1,1"]
	f.session.state_changed.emit(f.session.state, 2)
	assert_bool(f.hud._goals_list.visible).is_false()
	assert_str(f.hud._goals_header.text).is_equal("Goals · 1/7 ▸")
	f.hud._goals_header.pressed.emit()
	assert_bool(f.hud._goals_list.visible).is_true()
