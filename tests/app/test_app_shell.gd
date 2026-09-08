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

## 真机截图（2026-09-07）：壳和页各套一层安全区，Tab 页标题比压栈页低 40 px。壳内页面不再用 SafeAreaMargin。
func test_pages_inside_shell_do_not_apply_a_second_safe_area() -> void:
	var shell := (load(AppRoutes.SHELL) as PackedScene).instantiate()
	add_child(auto_free(shell))
	await get_tree().process_frame
	var page: AppPage = shell.page(AppRoutes.home_tab())
	assert_bool(page.in_shell).is_true()
	assert_bool(page.get_node("SafeArea") is SafeAreaMargin).is_false()
	var standalone := (load(AppRoutes.SETTINGS) as PackedScene).instantiate()
	add_child(auto_free(standalone))
	await get_tree().process_frame
	assert_bool(standalone.get_node("SafeArea") is SafeAreaMargin).is_true()

## 地图手势：壳与页面宿主不能吃触摸，否则 map_poc 的 _unhandled_input 收不到（2026-09-08 真机地图拖不动）。
func test_shell_and_page_host_let_touches_fall_through() -> void:
	var s := _shell()
	assert_int(s.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(s._page_host.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((s.get_node("Backdrop") as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(s.page(AppRoutes.TAB_MAP).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	var safe := s.get_node("SafeArea") as Control
	assert_int(safe.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((s._page_host.get_parent() as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# Tab 按钮必须照常吃点击。
	assert_int(s.tab_button(AppRoutes.TAB_IM).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)

## 压栈 3D 场景（换装房）时壳必须整个隐藏：否则壳的满屏纸色底盖住 3D 预览（2D 永远在 3D 之上）。
func test_suspend_hides_the_shell_so_a_pushed_3d_scene_is_visible() -> void:
	var s := _shell()
	assert_bool(s.visible).is_true()
	s.suspend()
	assert_bool(s.visible).is_false()
	assert_int(s.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	s.resume()
	assert_bool(s.visible).is_true()
	assert_int(s.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)

