extends GdUnitTestSuite
## P0 toasts through the kit ToastLayer (SGODOT-233; §4.8.6, q(49) ⑤, Toast R1): one at a time in the tone of what
## happened, over the quick bar's top edge left of the main action key, above the bag's docked bar while the bag is
## open, and over any drawer. FISH-4's full creel is an Error with `Open bag ›`.

const STORE := "user://test_p0_toasts.json"

var ui: P0Ui

func _view() -> Dictionary:
	return {
		"energy": {"value": 150, "max": 200}, "coins": 40,
		"skills": {"fishing": {"level": 3, "xp": 100, "floor": 75, "next": 130}, "farming": {"level": 1, "xp": 0, "floor": 0, "next": 40},
			"cooking": {"level": 1, "xp": 0, "floor": 0, "next": 40}},
		"names": {"fish_crucian": "Pond Crucian"},
		"fishing": {"cast_energy": 5, "dex": []},
		"bag": {"capacity": 25, "slots": [{"id": "fish_crucian", "qty": 2}]},
	}

func before_test() -> void:
	ui = P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.set_view(_view())
	ui.set_surface("farm")
	await await_idle_frame()

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _panel() -> Control: return ui._toasts._panel

func test_a_refusal_replaces_the_info_toast_in_the_error_tone() -> void:
	ui.toast("Room 1 is full · you're in Room 2")
	assert_int(ui._toasts.current_severity()).is_equal(ToastLayer.Severity.INFO)
	ui.toast_error("Not ready yet")
	assert_str(ui.toast_text()).is_equal("Not ready yet")
	assert_int(ui._toasts.current_severity()).is_equal(ToastLayer.Severity.ERROR)
	assert_int(ui.root.find_children("*", "ToastLayer", true, false).size()).is_equal(1)
	ui.toast_success("Floor 2 cleared · Elevator stop")
	assert_int(ui._toasts.current_severity()).is_equal(ToastLayer.Severity.SUCCESS)

func test_it_sits_on_the_quick_bar_left_of_the_main_action_key() -> void:
	ui.toast("Buy at Homestead Stall")
	await await_idle_frame()
	var bar := ui._bar.get_global_rect()
	var r := _panel().get_global_rect()
	assert_float(r.end.y).is_equal_approx(bar.position.y - UiTokens.SPACE_OVERLAY_BODY, 0.5)
	assert_float(r.position.x).is_equal_approx(ui.root.global_position.x + UiTokens.SPACE_PAGE, 0.5)
	assert_float(r.end.x).is_less_equal(ui._keys.get_global_rect().position.x)

func test_in_the_bag_it_sits_above_the_docked_bar_over_the_drawer() -> void:
	ui.open_bag()
	await get_tree().create_timer(UiTokens.MOTION_DRAWER_MS / 1000.0 + 0.1).timeout
	assert_bool(ui.is_bar_docked()).is_true()
	ui.toast("Find a resident at an outpost to gift this dish")
	await await_idle_frame()
	assert_int(ui._toasts.get_index()).is_equal(ui.root.get_child_count() - 1)   # over the drawer and its veil
	assert_float(_panel().get_global_rect().end.y).is_equal_approx(ui._bar.get_global_rect().position.y - UiTokens.SPACE_OVERLAY_BODY, 0.5)

func test_a_full_creel_says_so_and_its_action_opens_the_bag() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	add_child(rt)
	await get_tree().process_frame
	rt.session.view = _view()
	rt.ui.set_view(_view())
	rt._on_refused("creel_full", {}, {"type": "cast"})
	assert_str(rt.ui.toast_text()).is_equal("Creel full · 0 free slots · Sell or cook first")
	assert_int(rt.ui._toasts.current_severity()).is_equal(ToastLayer.Severity.ERROR)
	assert_str(rt.ui._toasts.current_action()).is_equal("Open bag")
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = false
	rt.ui._toasts._action.gui_input.emit(tap)
	assert_str(rt.ui.modal_kind).is_equal("bag")
	assert_str(rt.ui.toast_text()).is_empty()

## 周瑜 (int, a05-reason): over a drawer without the quick bar (the workbench), the reason toast is whole, over the
## drawer, just above its top edge — not on its rows or its Close key; and every toast keeps Toast R1's 232 width.
func test_over_a_drawer_without_the_bar_it_sits_above_the_drawer() -> void:
	var wb := UiDrawer.new(300.0)   # the workbench's way: a drawer opened without the bar (hide_controls)
	wb.animate = false
	ui._open_modal(wb, UiTokens.OPACITY_SCRIM_DRAWER, true)
	await await_idle_frame()
	ui.toast_error("Need 1 more Copper Ore")
	await await_idle_frame()
	var r := _panel().get_global_rect()
	assert_float(r.size.x).is_equal(float(ToastLayer.WIDTH))
	assert_int(ui._toasts.get_index()).is_equal(ui.root.get_child_count() - 1)
	assert_float(r.end.y).is_equal_approx(wb.get_global_rect().position.y - UiTokens.SPACE_OVERLAY_BODY, 0.5)
