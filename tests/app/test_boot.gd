extends GdUnitTestSuite
## 启动页只做一个决定：有会话进壳，没有进登录。主场景必须是它。

const BootScript := preload("res://scenes/app/boot.gd")

func test_decide_routes_by_first_run_then_session() -> void:
	var fresh := FirstRun.new()
	assert_str(BootScript.decide(true, fresh)).is_equal(AppRoutes.AGE_GATE)
	var ready := FirstRun.new()
	ready.age_gate_passed = true
	ready.consent_version = LegalLinks.CONSENT_VERSION
	assert_str(BootScript.decide(true, ready)).is_equal(AppRoutes.SHELL)
	assert_str(BootScript.decide(false, ready)).is_equal(AppRoutes.LOGIN)
	ready.consent_version = "old"
	assert_str(BootScript.decide(true, ready)).is_equal(AppRoutes.CONSENT)

func test_boot_is_main_scene_and_qa_entries_still_reach_farm_scenes() -> void:
	assert_str(ProjectSettings.get_setting("application/run/main_scene", "")).is_equal(AppRoutes.BOOT)
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=city"]))).is_equal(AppRouter.CITY_SELECT)
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=login"]))).is_equal(AppRoutes.LOGIN)
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=shell"]))).is_equal(AppRoutes.SHELL)
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=home"]))).is_equal(AppRoutes.SHELL)
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=agegate"]))).is_equal(AppRoutes.AGE_GATE)
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=consent"]))).is_equal(AppRoutes.CONSENT)

func test_back_from_boot_login_or_shell_leaves_app() -> void:
	for path in [AppRoutes.BOOT, AppRoutes.AGE_GATE, AppRoutes.CONSENT, AppRoutes.LOGIN, AppRoutes.SHELL]:
		assert_int(AppRouter.back_action_for_scene(path)).is_equal(AppRouter.BACK_LEAVE_APP)

func test_farm_anonymous_boot_only_when_farm_qa_scene_requested() -> void:
	assert_bool(Net.farm_boot_requested(PackedStringArray())).is_false()
	assert_bool(Net.farm_boot_requested(PackedStringArray(["--qa-scene=login"]))).is_false()
	assert_bool(Net.farm_boot_requested(PackedStringArray(["--qa-scene=shell"]))).is_false()
	assert_bool(Net.farm_boot_requested(PackedStringArray(["--qa-scene=city"]))).is_true()
	assert_bool(Net.farm_boot_requested(PackedStringArray(["--qa-scene=farm"]))).is_true()
