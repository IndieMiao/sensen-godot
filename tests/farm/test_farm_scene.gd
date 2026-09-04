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
