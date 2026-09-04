extends GdUnitTestSuite

const RouterScript := preload("res://modules/ui/app_router.gd")


class BackNavigationFixture extends Node:
	var locked := false

	func is_back_navigation_locked() -> bool:
		return locked


func test_router_is_the_single_autoload_and_disables_automatic_android_quit() -> void:
	assert_str(ProjectSettings.get_setting("autoload/AppRouter", "")).is_equal(
		"*res://modules/ui/app_router.gd")
	assert_bool(ProjectSettings.get_setting(
		"application/config/quit_on_go_back", true)).is_false()
	assert_bool(get_tree().quit_on_go_back).is_false()


func test_scene_constants_are_stable() -> void:
	assert_str(RouterScript.MAP).is_equal("res://scenes/map_poc/map_poc.tscn")
	assert_str(RouterScript.DRESS).is_equal("res://scenes/dressing_room/dressing_room.tscn")
	assert_str(RouterScript.STRESS).is_equal("res://scenes/stress_test/stress_test.tscn")


func test_qa_scene_argument_resolves_each_supported_destination() -> void:
	assert_str(RouterScript.qa_scene_path(
		PackedStringArray(["--qa-scene=map"]))).is_equal(RouterScript.MAP)
	assert_str(RouterScript.qa_scene_path(
		PackedStringArray(["--qa-scene=dressing"]))).is_equal(RouterScript.DRESS)
	assert_str(RouterScript.qa_scene_path(
		PackedStringArray(["--qa-scene=stress"]))).is_equal(RouterScript.STRESS)


func test_qa_scene_argument_ignores_unknown_or_unrelated_values() -> void:
	assert_str(RouterScript.qa_scene_path(
		PackedStringArray(["--remote-debug", "--qa-scene=unknown"]))).is_empty()
	assert_str(RouterScript.qa_scene_path(PackedStringArray())).is_empty()


func test_back_from_secondary_scenes_returns_to_map() -> void:
	assert_int(RouterScript.back_action_for_scene(
		RouterScript.DRESS)).is_equal(RouterScript.BACK_TO_MAP)
	assert_int(RouterScript.back_action_for_scene(
		RouterScript.STRESS)).is_equal(RouterScript.BACK_TO_MAP)
	assert_int(RouterScript.back_action_for_scene(
		RouterScript.DRESS, true)).is_equal(RouterScript.BACK_IGNORE)


func test_scene_can_declare_back_navigation_locked() -> void:
	var fixture = auto_free(BackNavigationFixture.new())
	assert_bool(RouterScript.scene_locks_back_navigation(fixture)).is_false()
	fixture.locked = true
	assert_bool(RouterScript.scene_locks_back_navigation(fixture)).is_true()
	assert_bool(RouterScript.scene_locks_back_navigation(null)).is_false()
	assert_bool(RouterScript.scene_locks_back_navigation(
		auto_free(Node.new()))).is_false()


func test_back_from_map_leaves_the_app_and_unknown_scene_is_ignored() -> void:
	assert_int(RouterScript.back_action_for_scene(
		RouterScript.MAP)).is_equal(RouterScript.BACK_LEAVE_APP)
	assert_int(RouterScript.back_action_for_scene(
		"res://tests/runner.tscn")).is_equal(RouterScript.BACK_IGNORE)


func test_android_root_back_uses_move_task_to_back() -> void:
	var router_source := FileAccess.get_file_as_string("res://modules/ui/app_router.gd")
	var plugin_source := FileAccess.get_file_as_string(
		"res://tools/android/overlay/GodotMapPlugin.kt")
	assert_bool(router_source.contains("host.moveTaskToBack()")).is_true()
	assert_bool(plugin_source.contains("fun moveTaskToBack()")).is_true()
	assert_bool(plugin_source.contains("moveTaskToBack(true)")).is_true()


func test_android_stress_qa_entry_is_debug_only_and_keeps_city_select_as_default() -> void:
	# main_scene 自 Task 13 起是城市选择页（PRD §4.3 第 1 条），不再是地图；
	# 本断言只守护「QA 压测入口不会悄悄顶替默认场景」这条不变量。
	assert_str(ProjectSettings.get_setting(
		"application/run/main_scene", "")).is_equal(RouterScript.CITY_SELECT)
	var plugin_source := FileAccess.get_file_as_string(
		"res://tools/android/overlay/GodotMapPlugin.kt")
	assert_bool(plugin_source.contains(
		"private const val QA_SCENE_EXTRA = \"com.sensen.qa.SCENE\"")).is_true()
	assert_bool(plugin_source.contains("ApplicationInfo.FLAG_DEBUGGABLE")).is_true()
	assert_bool(plugin_source.contains("scene == QA_STRESS_SCENE")).is_true()
	assert_bool(plugin_source.contains(
		"listOf(\"++\", \"--qa-scene=stress\")")).is_true()
