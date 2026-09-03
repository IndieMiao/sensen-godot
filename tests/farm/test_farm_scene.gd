extends GdUnitTestSuite
## 农场灰盒：加载蓝图 → 地表 + 锚点道具 + 玩家 + 相机；出口按钮接到场景栈。

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const FIX := "res://tests/fixtures/blueprints/fix_grid/r1/farm_blueprint.json"

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
	assert_str(f.get_node("HUD/SafeArea/Root/Title").text).is_equal("Fixture Grid")

func test_process_moves_player_and_camera_follows() -> void:
	var f := _farm()
	f.mover.set_target_cell(Vector2i(3, 6))
	for i in 90:
		f._process(1.0 / 60.0)
	var player := f.get_node("Player") as Node3D
	assert_that(f.mover.cell()).is_equal(Vector2i(3, 6))
	assert_that(player.position).is_equal(f.mover.position)
	var cam := f.get_node("Camera3D") as Camera3D
	assert_bool(cam.position.y > player.position.y).is_true()
	assert_bool(cam.position.z > player.position.z).is_true() # 相机在南侧看向北

func test_exit_button_wired_to_router() -> void:
	var f := _farm()
	var btn := f.get_node("HUD/SafeArea/Root/ExitButton") as Button
	assert_int(btn.pressed.get_connections().size()).is_equal(1)

func test_tap_ground_sets_target() -> void:
	var f := _farm()
	var target: Vector3 = f.bp.cell_to_world(Vector2i(1, 5))
	f._on_ground_tapped(target)
	assert_bool(f.mover.is_moving()).is_true()
