extends GdUnitTestSuite
## AppRoutes：Tab 顺序、场景路径存在、首页是地图。

func test_tab_order_is_map_feed_im_profile() -> void:
	assert_array(AppRoutes.TABS).is_equal(["map", "feed", "im", "profile"])
	assert_str(AppRoutes.home_tab()).is_equal("map")
	assert_int(AppRoutes.tab_index("im")).is_equal(2)
	assert_int(AppRoutes.tab_index("nope")).is_equal(-1)

func test_every_tab_scene_and_stacked_page_exists() -> void:
	for tab in AppRoutes.TABS:
		assert_bool(AppRoutes.is_tab(tab)).is_true()
		assert_bool(ResourceLoader.exists(AppRoutes.tab_scene(tab))).override_failure_message("missing scene for %s" % tab).is_true()
		assert_bool(AppRoutes.tab_icon(tab).is_empty()).is_false()
		assert_bool(ResourceLoader.exists("res://assets/ui/icons/lucide/%s.svg" % AppRoutes.tab_icon(tab))).is_true()
	for path in [AppRoutes.BOOT, AppRoutes.AGE_GATE, AppRoutes.CONSENT, AppRoutes.LOGIN, AppRoutes.SHELL, AppRoutes.SETTINGS, AppRoutes.VOICE_ROOM]:
		assert_bool(ResourceLoader.exists(path)).override_failure_message("missing %s" % path).is_true()

func test_unknown_tab_is_rejected() -> void:
	assert_bool(AppRoutes.is_tab("settings")).is_false()
	assert_str(AppRoutes.tab_scene("settings")).is_empty()
	assert_str(AppRoutes.tab_title("weird")).is_equal("weird")

func test_router_constants_stay_in_sync_with_routes() -> void:
	assert_str(AppRouter.BOOT).is_equal(AppRoutes.BOOT)
	assert_str(AppRouter.LOGIN).is_equal(AppRoutes.LOGIN)
	assert_str(AppRouter.SHELL).is_equal(AppRoutes.SHELL)
