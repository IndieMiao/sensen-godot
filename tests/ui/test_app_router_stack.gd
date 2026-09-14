extends GdUnitTestSuite
## 场景栈：push 挂到 root 并 suspend 前一层；pop 释放顶层并 resume 新顶层；返回键先 pop。

const PROBE := "res://tests/fixtures/scenes/stack_probe.tscn"

func test_loading_navigation_blocks_duplicate_requests_and_back_until_ready() -> void:
	AppRouter.open_instance(PROBE, {"loading": true})
	assert_bool(AppRouter._navigation_pending).is_true()
	assert_bool(AppRouter._loading.visible).is_true()
	AppRouter.open_instance(PROBE)
	AppRouter.handle_back()
	while AppRouter._navigation_pending: await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_that(AppRouter.top_instance().args).is_equal({"loading": true})
	assert_that(AppRouter._loading).is_null()

func after_test() -> void:
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame

func test_push_passes_args_and_suspends_previous_top() -> void:
	var a := AppRouter.push_instance(PROBE, {"k": 1})
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_that(a.args).is_equal({"k": 1})
	assert_bool(a.get_parent() == get_tree().root).is_true()
	var b := AppRouter.push_instance(PROBE)
	assert_int(AppRouter.instance_depth()).is_equal(2)
	assert_int(a.suspended).is_equal(1)
	assert_int(b.suspended).is_equal(0)
	assert_bool(AppRouter.top_instance() == b).is_true()

func test_pop_frees_top_and_resumes_previous() -> void:
	var a := AppRouter.push_instance(PROBE)
	var b := AppRouter.push_instance(PROBE)
	AppRouter.pop_instance()
	await get_tree().process_frame
	assert_bool(is_instance_valid(b)).is_false()
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_int(a.resumed).is_equal(1)

func test_back_pops_when_stack_not_empty() -> void:
	var a := AppRouter.push_instance(PROBE)
	AppRouter.handle_back()
	await get_tree().process_frame
	assert_bool(is_instance_valid(a)).is_false()
	assert_int(AppRouter.instance_depth()).is_equal(0)

func test_back_respects_top_instance_lock() -> void:
	var a := AppRouter.push_instance(PROBE)
	a.back_locked = true
	AppRouter.handle_back()
	await get_tree().process_frame
	assert_bool(is_instance_valid(a)).is_true() # 锁住时不得弹栈
	assert_int(AppRouter.instance_depth()).is_equal(1)
	a.back_locked = false
	AppRouter.handle_back()
	await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(0)

## C1（2026-09-04 终审）：压栈场景必须真的接管视口的当前相机，光隐藏节点不够——
## Godot 4 里 Camera3D 只有 current==true 或是视口里第一台相机时才会被选中。
func test_push_makes_probe_camera_current_and_pop_restores_previous() -> void:
	var a := AppRouter.push_instance(PROBE)
	assert_bool(get_viewport().get_camera_3d() == a.cam).is_true()
	var b := AppRouter.push_instance(PROBE)
	assert_bool(get_viewport().get_camera_3d() == b.cam).is_true()
	AppRouter.pop_instance()
	await get_tree().process_frame
	assert_bool(get_viewport().get_camera_3d() == a.cam).is_true()

func test_back_action_table_includes_city_select() -> void:
	assert_int(AppRouter.back_action_for_scene(AppRouter.CITY_SELECT)).is_equal(AppRouter.BACK_LEAVE_APP)
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=city"]))).is_equal(AppRouter.CITY_SELECT)
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=farm"]))).is_equal(AppRouter.FARM)
