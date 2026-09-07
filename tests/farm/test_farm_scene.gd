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
		"chapters": [{"status": "active", "step_flags": {"farm_created": true}}],
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

func _finished_first_chapter(state: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	next.chapters = [{"status": "done", "step_flags": {
		"farm_created": true, "first_harvest": true, "next_batch_sown_and_cared": true}}]
	return next

func test_purchased_row_tool_expands_only_matching_actions_in_the_same_bed() -> void:
	var f := await _online_farm(FakeTransport.new([]))
	f.set_process(false)
	var row: Array = f.bp.beds()[0].cells
	var view: Dictionary = f._cells_view()
	for cell in row: view[f._id(cell)] = {"state": "cleared", "ready_at": null}
	view[f._id(row[2])] = {"state": "tilled", "ready_at": null}
	var expanded: Array = f._expand_tool_plots([row[0]], view, f._now(), 3)
	assert_array(expanded).is_equal([row[0], row[1]])
	assert_array(f._expand_tool_plots([row[2]], view, f._now(), 3)).is_equal([row[2]])
	for cell in row: view[f._id(cell)] = {"state": "wild", "ready_at": null}
	assert_array(f._expand_tool_plots([row[0]], view, f._now(), 3)).is_equal([row[0]])

func test_authoritative_chapter_response_updates_goals_weather_and_completion_feedback_once() -> void:
	var f := await _online_farm(FakeTransport.new([]))
	f.set_process(false)
	var finished := _finished_first_chapter(f.session.state)
	f.session._adopt({"version": 1, "state": finished, "server_time": 1000,
		"derived": {"chapter_index": 0, "next_chapter_opens_at": 100000}})
	assert_str(f.hud._goals_header.text).is_equal("Goals · 7/7")
	assert_str(f.hud._toast_label.text).is_equal("Chapter 1 complete")
	f.hud._toast_left = 0.5
	f._refresh_hud()
	assert_float(f.hud._toast_left).is_equal(0.5)
	var next := finished.duplicate(true)
	next.clock.chapter_index = 1
	next.clock.field_condition = "rain"
	next.chapters.append({"status": "active", "step_flags": {"rain_care_done": true}})
	f.session._adopt({"version": 2, "state": next, "server_time": 100000,
		"derived": {"chapter_index": 1, "next_chapter_opens_at": null}})
	assert_str(f.hud._goals_header.text).is_equal("Goals · 1/2")
	assert_str(f.hud._goals_title.text).is_equal("Chapter 2 · A rainy day")
	assert_str(f.hud._condition.text).is_equal("Rain · drain today")
	assert_str(f.hud._toast_label.text).is_equal("Chapter 2 · A rainy day")
	assert_int(f.hud.goal_labels().size()).is_equal(2)

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
	assert_str(f.hud._goals_header.text).is_equal("Goals · 0/2")
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
	# house + storage + well + exit + 9 田格 + 3 预留格
	assert_int(f.prop_count()).is_equal(4 + 9 + 3)
	assert_that(f.mover.cell()).is_equal(f.bp.anchor("spawn"))
	assert_bool(f.get_node("Player").get_child_count() >= 1).is_true()
	assert_str(f.title.text).is_equal("Fixture Grid")

func test_care_uses_the_weather_recorded_at_sowing() -> void:
	var f := await _online_farm(FakeTransport.new([]))
	var cell: Vector2i = f.bp.beds()[0].cells[0]
	var id: String = f._id(cell)
	f.session.state.clock.field_condition = "rain"
	f.session.state.cells[f.interior.source_id(id)] = {"state": "sown", "crop": "R", "care_weather": "sunny"}
	f._on_server_state(f.session.state, f.session.version)
	assert_str(f._payload_for("care", [id]).kind).is_equal("water")
	assert_str(f._care_condition(cell)).is_equal("sunny")

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
	# Nearby work keeps a stable view; walking beyond the farm starts following.
	f.mover.position = f._field_center + Vector3(12, 0, 0)
	f._process(0.0)
	assert_bool(cam.position != cam_before).is_true()
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
	assert_int(int(scene.crop_field.cell_counts()["weed"])).is_equal(9)
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
	assert_str(str(t.requests[0].body.payload.cell_ids[0])).is_equal(f.interior.source_id(f._id(cell)))
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

func test_first_batch_seed_choices_and_single_plot_actions_follow_the_same_tutorial_rule() -> void:
	var transport := FakeTransport.new([])
	var f: Node = await _online_farm(transport)
	f.set_process(false)
	var cell: Vector2i = f.bp.beds()[0].cells[0]
	f.predictor.cells[f._id(cell)].state = "tilled"
	f._refresh_hud()
	assert_bool(f.hud._seed_buttons.R.visible).is_true()
	assert_bool(f.hud._seed_buttons.L.visible).is_false()
	f.hud.selected_crop = "L"
	f._tap_cell(cell)
	assert_bool(f.runner.is_busy()).is_false()
	assert_str(f.hud._toast_label.text).is_equal("First harvest starts with radishes")
	f.runner.enqueue([cell], "sow")
	f.runner.step(0.0)
	assert_bool(f.runner.is_busy()).is_false()
	assert_int(transport.requests.size()).is_equal(0)
	f._refresh_hud()
	assert_str(f.hud.selected_crop).is_equal("R")
	f._tap_cell(cell)
	assert_int(f.runner.pending_count()).is_equal(1)
	f.runner.cancel_pending()
	f.session.state.chapters[0].step_flags.first_harvest = true
	f._refresh_hud()
	assert_bool(f.hud._seed_buttons.L.visible).is_true()
	f.hud.selected_crop = "L"
	f._tap_cell(cell)
	assert_int(f.runner.pending_count()).is_equal(1)
	assert_str(f._payload_for("sow", [f._id(cell)]).crop).is_equal("L")

func test_first_batch_clicks_and_brushes_reserve_no_more_than_six_sowing_slots() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	f.set_process(false)
	var plots: Array = []
	for bed in f.bp.beds(): plots.append_array(bed.cells)
	for cell in plots: f.predictor.cells[f._id(cell)].state = "tilled"
	f.session.state.inventory.seeds.R.bound = 12
	f._refresh_hud()
	assert_int(f._queue_plots(plots.slice(0, 4))).is_equal(4)
	assert_int(f._queue_plots(plots.slice(4))).is_equal(2)
	assert_int(f.runner.pending_count()).is_equal(6)
	assert_int(f._queue_plots([plots[8]])).is_equal(0)
	assert_str(f.hud._toast_label.text).is_equal("Harvest the first batch before sowing more")
	f.runner.cancel_pending()
	for cell in plots.slice(0, 6):
		f.predictor.cells[f._id(cell)] = {"state": "growing", "crop": "R", "ready_at": f._now() + 180_000}
	f._refresh_hud()
	assert_bool(f.hud._seed_row.visible).is_false()
	assert_str(f.hud._cta.text).is_equal("First harvest is growing")
	f.render_cells(f.predictor.view(), f._now())
	for cell in plots.slice(6): assert_bool(f.hints.cells.has(f._id(cell))).is_false()
	f._tap_cell(plots[8])
	assert_bool(f.runner.is_busy()).is_false()
	f.runner.enqueue([plots[8]], "sow")
	f.runner.step(0.0)
	assert_bool(f.runner.is_busy()).is_false()

func test_cta_switches_to_sow_only_when_seeds_exist() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	f.session.state.chapters[0].step_flags.first_harvest = true
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
	assert_str(f.hud._goals_header.text).is_equal("Goals · 1/7")
	f.session.state.xp.first_harvest_crops = ["R"]
	f.session.state.chapters[0].step_flags.first_harvest = true
	f.session.state.wallet = 204
	f.session.state_changed.emit(f.session.state, 3)
	assert_str(f.hud._goals_header.text).is_equal("Goals · 6/7")
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
	f._tap_cell(f.bp.beds()[0].cells[0])
	f._process(0.0)
	f._process(0.1)
	assert_str(f.hud._cta.text).starts_with("Walking…")
	assert_bool(_run_until(f, func(): return not f.runner.paused and f.runner.is_busy())).is_true()
	f._process(0.5)
	assert_str(f.hud._cta.text).starts_with("Clearing…")

func test_cta_goes_busy_while_the_queue_runs_and_pressing_it_again_adds_nothing() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	f._on_cta()
	f._process(0.0)
	assert_bool(f.hud._cta.disabled).is_true()
	assert_str(f.hud._status_label.text).is_equal("9 plots remaining")
	f._on_cta()                                   # 再按一下：什么都不会多排
	assert_int(f.runner.pending_count()).is_equal(9)

func test_goals_stay_in_the_modal_after_the_first_goal_completes() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	assert_bool(f.hud._goals.visible).is_false()
	f.session.state.xp.first_clear_cells = ["1,1"]
	f.session.state_changed.emit(f.session.state, 2)
	assert_bool(f.hud._goals.visible).is_false()
	assert_str(f.hud._goals_header.text).is_equal("Goals · 2/7")
	f.hud._goals_header.pressed.emit()
	assert_bool(f.hud._goals.visible).is_true()

func test_ripening_flips_the_cta_and_the_crop_without_any_input() -> void:
	if DisplayServer.get_name() == "headless":
		return # 依赖真实渲染（出帖 / 着色器 / 布局尺寸）：headless CI 跳过，本地开窗跑测照常覆盖
	# 成熟是时间派生的：没有回包、没有输入，也必须靠每秒一次的刷新自己变过来。
	var f: Node = await _online_farm(FakeTransport.new([]))
	var cell: Vector2i = f.bp.beds()[0].cells[0]
	var id := "%d,%d" % [cell.x, cell.y]
	for k in f.predictor.cells:
		f.predictor.cells[k] = {"state": "cleared", "crop": null, "ready_at": null}
	f.predictor.cells[id] = {"state": "growing", "crop": "R", "care_done_at": f._now() - 1000, "ready_at": f._now() + 800}
	f._refresh_hud()
	assert_str(f.hud._cta.text).is_equal("Till 8 plots")
	f.session.clock_offset_ms += 1000            # 服务端时间走过成熟点
	f._process(f.TICK_S + 0.01)                   # 一个节拍
	assert_str(f.hud._cta.text).is_equal("Harvest 1 plot")
	assert_str(f.hud._timer_label.text).is_equal("Harvest ready")
	var mm: MultiMesh = f.crop_field._mm["R"].multimesh
	assert_float(mm.get_instance_transform(0).basis.get_scale().y).is_equal_approx(CropField.STAGE_SIZE[3].y, 0.001)

func test_periodic_refresh_does_not_unbusy_the_cta() -> void:
	var f: Node = await _online_farm(FakeTransport.new([]))
	f._on_cta()
	f._process(0.0)
	f._process(f.TICK_S + 0.01)
	assert_bool(f.hud._cta.disabled).is_true()
	assert_bool(f.hud._cancel.visible).is_true()
	assert_str(f.hud._status_label.text).contains("remaining")
