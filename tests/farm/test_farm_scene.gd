extends GdUnitTestSuite
## 农场灰盒：加载蓝图 → 地表 + 锚点道具 + 玩家 + 相机；出口按钮接到场景栈。

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

var _saved_navigation_pending: bool

func before_test() -> void:
	_saved_navigation_pending = AppRouter._navigation_pending

func after_test() -> void:
	AppRouter._navigation_pending = _saved_navigation_pending

func _farm() -> Node:
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FIX)})
	add_child(auto_free(scene))
	return scene

func test_builds_ground_props_and_player_at_spawn() -> void:
	var f := _farm()
	assert_object(f.get_node("Ground").mesh).is_not_null()
	# house + storage + well + exit + 9 田格 + 3 预留格
	assert_int(f.prop_count()).is_equal(4 + 9 + 3)
	assert_that(f.mover.cell()).is_equal(Vector2i(3, 3))
	assert_bool(f.get_node("Player").get_child_count() >= 1).is_true()
	assert_str(f.title.text).is_equal("Fixture Grid")

func test_process_moves_player_and_camera_follows() -> void:
	var f := _farm()
	var cam := f.get_node("Camera3D") as Camera3D
	var cam_before := cam.position # _ready() 已跑过一次 _update_camera()，这是出生点锚定的相机位
	f.mover.set_target_cell(Vector2i(3, 6))
	for i in 90:
		f._process(1.0 / 60.0)
	var player := f.get_node("Player") as Node3D
	assert_that(f.mover.cell()).is_equal(Vector2i(3, 6))
	assert_that(player.position).is_equal(f.mover.position)
	# 判别性断言：相机必须真的跟着玩家挪动过（而不是停在出生点的旧值仍恰好满足符号判断），
	# 且精确钉在 45° 俯角 * CAM_DIST 的公式上——相机在南侧看向北。
	assert_bool(cam.position != cam_before).is_true()
	var phi := deg_to_rad(45.0) # CAM_PITCH_DEG
	var expected := player.position + Vector3(0.0, 16.0 * sin(phi), 16.0 * cos(phi)) # CAM_DIST
	assert_vector(cam.position).is_equal_approx(expected, Vector3(0.001, 0.001, 0.001))

func test_exit_button_wired_to_router() -> void:
	var f := _farm()
	var btn := f.exit_btn as Button
	assert_int(btn.pressed.get_connections().size()).is_equal(1)

func test_tap_ground_sets_target() -> void:
	var f := _farm()
	var target: Vector3 = f.bp.cell_to_world(Vector2i(1, 5))
	f._on_ground_tapped(target)
	assert_bool(f.mover.is_moving()).is_true()

func test_missing_blueprint_bails_without_crashing() -> void:
	# 缺蓝图退场帧：_ready() 里 call_deferred("_leave") 要到本帧末才生效，这期间
	# 输入/直接调用不能在 null mover/bp 上崩溃。拦住真实换场（同
	# tests/integration/test_dressing_flow.gd 的惯例），只验证退场路径本身不炸，
	# 不依赖 AppRouter 真的弹栈/跳地图（本场景不是经 push_instance 挂上去的，
	# _leave() 落到空栈分支会尝试 go_to_map()，与本用例无关，须拦住）。
	AppRouter._navigation_pending = true
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"layout_patch_id": "no_such_id", "revision": 1})
	add_child(auto_free(scene))
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = Vector2(10, 10)
	scene._unhandled_input(down)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = Vector2(10, 10)
	scene._unhandled_input(up)
	scene._on_ground_tapped(Vector3.ZERO)
	assert_that(scene.mover).is_null()

## 2026-09-04 真机（360×800）：标题按屏幕中心 ±120 的固定偏移摆放，左上「Leave Farm」按钮
## 占 12..132，两者在 328 宽的 Root 里必然相交（44..132 那一段），路名前半被按钮盖住、只剩
## 「…ngshan Road」。桌面宽视口下两者不相交，所以必须把 HUD 压到手机宽度才能复现。
func test_title_and_exit_button_do_not_overlap_on_phone_width() -> void:
	var f := _farm()
	var safe := f.get_node("HUD/SafeArea") as SafeAreaMargin
	safe.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	safe.size = Vector2(360, 800)
	safe.apply_margins(Rect2i(), Vector2i(360, 800), Vector2(360, 800))
	await get_tree().process_frame
	await get_tree().process_frame
	var title_rect: Rect2 = (f.title as Control).get_global_rect()
	var exit_rect: Rect2 = (f.exit_btn as Control).get_global_rect()
	assert_bool(title_rect.intersects(exit_rect)).is_false()
	# 不是靠把标题挤出屏幕来"消除"重叠：两者都必须仍在 Root 里
	var root_rect: Rect2 = (f.get_node("HUD/SafeArea/Root") as Control).get_global_rect()
	assert_bool(root_rect.grow(0.5).encloses(title_rect)).is_true()
	assert_bool(root_rect.grow(0.5).encloses(exit_rect)).is_true()

func test_crops_render_outside_props() -> void:
	# 作物必须挂 Crops（Props 的同级）。挪进 Props 会污染 prop_count() 的精确断言。
	var f := _farm()
	var before: int = f.prop_count()
	var cells := {}
	for bed in f.bp.beds():
		for c in bed.cells:
			cells["%d,%d" % [c.x, c.y]] = {"state": "growing", "crop": "R",
				"care_done_at": 0, "ready_at": 400, "careful": false, "tutorial": false}
	f.render_cells(cells, 400)
	assert_int(f.prop_count()).is_equal(before)
	assert_int(int(f.crop_field.cell_counts()["R"])).is_equal(9)

func test_no_tool_selected_means_tap_moves_the_player() -> void:
	var f := _farm()
	var bed: Array = f.bp.beds()[0].cells
	assert_int(f._enqueue_cells(bed)).is_equal(0)
	assert_bool(f.runner.is_busy()).is_false()

func test_brush_over_three_cells_queues_three_actions() -> void:
	var f := _farm()
	f.tool = "clear"
	var bed: Array = f.bp.beds()[0].cells
	assert_int(f._enqueue_cells(bed)).is_equal(3)
	assert_int(f.runner.pending_count()).is_equal(3)

func test_row_tool_expands_a_single_cell_to_the_whole_bed() -> void:
	# 少划两下，不是效率道具：仍是 3 格逐格播放（PRD §6.3 L408）。
	var f := _farm()
	f.tool = "till"
	f.row_tool = true
	assert_int(f._enqueue_cells([f.bp.beds()[0].cells[1]])).is_equal(3)

func test_locked_reserved_bed_is_filtered_out() -> void:
	var f := _farm()
	f.tool = "clear"
	assert_int(f._enqueue_cells(f.bp.reserved_bed().cells)).is_equal(0)

func test_action_lock_stops_process_from_stealing_the_animation() -> void:
	# farm.gd::_process 每帧无条件用 walk/idle 覆盖动画；不锁就永远看不到劳作动作。
	var f := _farm()
	f.tool = "clear"
	f._enqueue_cells([f.bp.beds()[0].cells[0]])
	assert_bool(f._action_locked()).is_true()
	f._process(0.0)
	f._process(ActionRunner.ACTION_S)
	assert_bool(f._action_locked()).is_false()

func test_works_without_a_server_session() -> void:
	# 没有服务端时农场退化成 G0 灰盒：照旧能进能出能走动，不崩。
	var f := _farm()
	assert_object(f.session).is_null()
	f.tool = "clear"
	f._enqueue_cells([f.bp.beds()[0].cells[0]])
	f._process(0.0)
	f._process(ActionRunner.ACTION_S)
	assert_bool(f.runner.is_busy()).is_false()

func test_attaches_injected_session_and_sends_commands_on_cell_done() -> void:
	# 有农场的会话 → 挂 predictor，动作收工时真的发命令并对账。
	var t := FakeTransport.new([
		{"status": 200, "json": {"version": 1, "state": {"cells": {"1,1": {"state": "cleared"}}}}},
	])
	var s := FarmSession.new(ApiClient.new("https://example.test/v1", t.callable()))
	s.client.token = "tok"
	s.farm_id = "f1"
	s.version = 0
	s.state = {"cells": {"1,1": {"state": "wild"}}, "beds_unlocked": 3, "wallet": 5}
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FIX), "session": s})
	add_child(auto_free(scene))
	assert_object(scene.predictor).is_not_null()
	assert_that(scene.session).is_same(s)
	scene.tool = "clear"
	scene._on_cell_started(Vector2i(1, 1), "clear")
	assert_str(str(scene.predictor.view()["1,1"].state)).is_equal("cleared")   # 本地预测先到
	await scene._on_cell_done(Vector2i(1, 1), "clear")
	assert_int(t.requests.size()).is_equal(1)
	assert_str(str(t.requests[0].body.type)).is_equal("clear_cells")
	assert_int(scene.predictor.version).is_equal(1)

func test_without_farm_in_session_stays_offline_greybox() -> void:
	var s := FarmSession.new(ApiClient.new("https://example.test/v1", FakeTransport.new([]).callable()))
	s.client.token = "tok"      # 登录了但还没建场
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FIX), "session": s})
	add_child(auto_free(scene))
	assert_object(scene.session).is_null()
	assert_object(scene.predictor).is_null()


func test_action_progress_and_hint_are_visible_in_hud() -> void:
	# 2 秒一格的劳作必须有可见反馈，否则就是「点了没反应」。
	var f := _farm()
	f.hud._on_tool("clear")
	assert_bool(f.hud._status.visible).is_true()
	assert_str(f.hud._status_label.text).is_equal("Tap or drag across plots")
	f._enqueue_cells(f.bp.beds()[0].cells)
	f._process(0.0)
	f._process(1.0)
	assert_str(f.hud._status_label.text).starts_with("Clearing… 50%")
	assert_bool(f.hud._status_label.text.contains("(+2 queued)")).is_true()
	# 队列每步只结一格：三格要走三个 ACTION_S，再一帧让 HUD 收起
	for i in 3:
		f._process(ActionRunner.ACTION_S)
	f._process(0.016)
	assert_bool(f.hud._status.visible).is_false()

func test_server_rejection_is_shown_not_swallowed() -> void:
	var t := FakeTransport.new([{"status": 422, "json": {"code": "WRONG_STATE", "detail": "x"}}])
	var s := FarmSession.new(ApiClient.new("https://example.test/v1", t.callable()))
	s.client.token = "tok"
	s.farm_id = "f1"
	s.state = {"cells": {"1,1": {"state": "wild"}}, "beds_unlocked": 3}
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": FarmBlueprint.load_file(FIX), "session": s})
	add_child(auto_free(scene))
	scene.tool = "clear"
	scene._on_cell_started(Vector2i(1, 1), "clear")
	await scene._on_cell_done(Vector2i(1, 1), "clear")
	assert_bool(scene.hud._toast.visible).is_true()
	assert_str(scene.hud._toast_label.text).is_equal("That plot isn't ready for this step")
	assert_str(str(scene.predictor.view()["1,1"].state)).is_equal("wild")   # 预测已回滚
