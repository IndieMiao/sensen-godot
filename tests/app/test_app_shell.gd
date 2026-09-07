extends GdUnitTestSuite
## AppShell：Tab 懒实例化、切换显隐、返回语义、持久化、压栈协议。

func before_test() -> void:
	UiState.clear()

func after_test() -> void:
	UiState.clear()

func _shell() -> AppShell:
	var s := (load(AppRoutes.SHELL) as PackedScene).instantiate() as AppShell
	add_child(auto_free(s))
	return s

func test_starts_on_map_with_only_map_page_instantiated() -> void:
	var s := _shell()
	assert_str(s.current_tab).is_equal("map")
	assert_bool(s.has_page("map")).is_true()
	assert_bool(s.has_page("feed")).is_false()
	assert_bool(s.page("map").visible).is_true()
	assert_int(s.page("map").shown_count).is_equal(1)
	assert_int(s.tab_button("map").get_parent().get_child_count()).is_equal(4)

func test_switching_tab_hides_previous_and_disables_its_processing() -> void:
	var s := _shell()
	var changes: Array = []
	s.tab_changed.connect(func(t): changes.append(t))
	s.show_tab("feed")
	assert_str(s.current_tab).is_equal("feed")
	assert_bool(s.page("feed").visible).is_true()
	assert_bool(s.page("map").visible).is_false()
	assert_int(s.page("map").process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	assert_int(s.page("feed").process_mode).is_equal(Node.PROCESS_MODE_INHERIT)
	assert_int(s.page("map").hidden_count).is_equal(1)
	assert_int(s.page("feed").shown_count).is_equal(1)
	assert_array(changes).is_equal(["feed"])
	assert_str(String(s.tab_button("feed").theme_type_variation)).is_equal("TabSelectedButton")
	assert_str(String(s.tab_button("map").theme_type_variation)).is_equal("TabButton")

func test_pages_are_instantiated_once_and_keep_identity() -> void:
	var s := _shell()
	s.show_tab("im")
	var im_page := s.page("im")
	s.show_tab("profile")
	s.show_tab("im")
	assert_bool(s.page("im") == im_page).is_true()
	assert_int(im_page.shown_count).is_equal(2)

func test_same_tab_and_unknown_tab_are_no_ops() -> void:
	var s := _shell()
	var changes: Array = []
	s.tab_changed.connect(func(t): changes.append(t))
	s.show_tab("map")
	s.show_tab("settings")
	assert_array(changes).is_empty()
	assert_str(s.current_tab).is_equal("map")

func test_back_returns_to_map_first_then_yields_to_router() -> void:
	var s := _shell()
	s.show_tab("profile")
	assert_bool(s.handle_back()).is_true()
	assert_str(s.current_tab).is_equal("map")
	assert_bool(s.handle_back()).is_false()

func test_current_tab_is_persisted_and_restored_on_cold_start() -> void:
	var s := _shell()
	s.show_tab("im")
	assert_str(str(UiState.read().get(AppShell.UI_STATE_KEY, ""))).is_equal("im")
	s.free()
	var again := _shell()
	assert_str(again.current_tab).is_equal("im")
	assert_bool(again.has_page("map")).is_true() # 地图页常驻，即使冷启动落在别的 Tab

func test_suspend_resume_notify_current_page_and_toggle_processing() -> void:
	var s := _shell()
	s.suspend()
	assert_int(s.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	assert_int(s.page("map").hidden_count).is_equal(1)
	s.resume()
	assert_int(s.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)
	assert_int(s.page("map").shown_count).is_equal(2)

func test_stacked_pages_carry_back_button_and_tab_pages_do_not() -> void:
	var settings := (load(AppRoutes.SETTINGS) as PackedScene).instantiate() as AppPage
	add_child(auto_free(settings))
	assert_object(settings.find_child("Back", true, false)).is_not_null()
	var feed := (load(AppRoutes.tab_scene("feed")) as PackedScene).instantiate() as AppPage
	add_child(auto_free(feed))
	assert_object(feed.find_child("Back", true, false)).is_null()
	assert_str(feed.title_label.text).is_equal("Feed")

func test_login_page_keeps_idp_buttons_disabled_until_c1() -> void:
	var login := (load(AppRoutes.LOGIN) as PackedScene).instantiate() as AppPage
	add_child(auto_free(login))
	for n in ["Apple", "Google"]:
		var b := login.find_child(n, true, false) as Button
		assert_object(b).override_failure_message("missing %s" % n).is_not_null()
		assert_bool(b.disabled).is_true()
	for n in ["Email", "Password", "SignIn", "SignUp", "Forgot", "Status"]:
		assert_object(login.find_child(n, true, false)).override_failure_message("missing %s" % n).is_not_null()
