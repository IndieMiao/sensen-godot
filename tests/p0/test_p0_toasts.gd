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
	assert_str(rt.ui._bag.category).is_equal("Fish")   # the creel is the bag: its Fish page (q(83))
	assert_str(rt.ui.toast_text()).is_empty()

## q(83) (不知火舞 on 235 B1): no pills over the switch; the creel badge full or the greyed Cast · Creel full says the
## sentence with Open bag ›; the badge not full opens the bag on its Fish page.
func test_the_creel_badge_and_the_greyed_cast_say_the_creel_is_full() -> void:
	var v := _view()
	v.bag["free"] = 0
	ui.set_surface("pond")
	ui.set_mode("fish")
	ui.set_view(v)
	ui.set_action(P0Logic.fish_action(v, ""))
	await await_idle_frame()
	assert_bool(ui._creel.visible).is_true()
	assert_int(ui._creel.state).is_equal(UiCreelBadge.State.FULL)
	assert_str(ui._creel.text).is_equal("Creel 2 · 0 free")
	assert_int(ui.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text in ["Open Bag", "Go home"]).size()).is_equal(0)
	ui._creel.pressed.emit()
	assert_str(ui.toast_text()).is_equal(P0Ui.CREEL_FULL)
	assert_int(ui._toasts.current_severity()).is_equal(ToastLayer.Severity.ERROR)
	assert_str(ui._toasts.current_action()).is_equal("Open bag")
	ui.clear_toast()
	ui._fab_pressed()   # the greyed Cast · Creel full
	assert_str(ui.toast_text()).is_equal(P0Ui.CREEL_FULL)
	ui._on_toast_action("Open bag")
	assert_str(ui.modal_kind).is_equal("bag")
	assert_str(ui._bag.category).is_equal("Fish")

func test_the_creel_badge_not_full_opens_the_fish_page() -> void:
	var v := _view()
	v.bag["free"] = 1
	ui.set_surface("pond")
	ui.set_mode("fish")
	ui.set_view(v)
	await await_idle_frame()
	assert_int(ui._creel.state).is_equal(UiCreelBadge.State.LOW)
	ui._creel.pressed.emit()
	assert_str(ui.toast_text()).is_empty()
	assert_str(ui.modal_kind).is_equal("bag")
	assert_str(ui._bag.category).is_equal("Fish")

## 周瑜 (int, a05-reason): over a drawer without the quick bar (the workbench), the reason toast is whole, over the
## drawer, just above its top edge — not on its rows or its Close key; and every toast keeps Toast R1's 232 width.
## q(16) (不知火舞 on #86): a drawer with no decision area (the Workbench) puts the toast at its foot — bottom edge 16
## over the drawer's bottom and the safe inset, 232 wide — never above the drawer, never at the bar's spot over it.
func test_in_a_drawer_with_no_decision_area_it_sits_at_the_foot() -> void:
	for h in [300.0, ui.root.size.y - 60.0]:   # a short drawer and one reaching up to the HUD (李元芳 int7)
		var wb := UiDrawer.new(h)   # the workbench's way: a drawer opened without the bar (hide_controls)
		wb.animate = false
		ui._open_modal(wb, UiTokens.OPACITY_SCRIM_DRAWER, true)
		await await_idle_frame()
		ui.toast_error("Need 5 more Copper Ore")
		await await_idle_frame()
		var r := _panel().get_global_rect()
		assert_float(r.size.x).is_equal(ToastLayer.NARROW_WIDTH)
		assert_float(r.position.x).is_equal(float(UiTokens.SPACE_PAGE))
		assert_float(r.end.y).is_equal_approx(ui.root.size.y - 16.0 - ui.safe_bottom(), 0.5)
		assert_int(ui._toasts.get_index()).is_equal(ui.root.get_child_count() - 1)
		ui.close_modal()
		ui.clear_toast()

## q(16): a drawer with a fixed decision area (the counter's Sell card, the kitchen's Cook row) has the toast 8 above it.
class _Decided extends UiDrawer:
	var area := Control.new()
	func _init() -> void:
		super(500.0)
		area.custom_minimum_size = Vector2(300, 48)
		body.add_child(Control.new())
		body.add_child(area)
	func action_area() -> Control: return area

func test_in_a_drawer_with_a_decision_area_it_sits_above_it() -> void:
	var d := _Decided.new()
	d.animate = false
	ui._open_modal(d, UiTokens.OPACITY_SCRIM_DRAWER, true)
	await await_idle_frame()
	ui.toast_error("Need 12 more coins")
	await await_idle_frame()
	var r := _panel().get_global_rect()
	assert_float(r.size.x).is_equal(float(ToastLayer.WIDTH))
	assert_float(r.end.y).is_equal_approx(d.area.get_global_rect().position.y - UiTokens.SPACE_OVERLAY_BODY, 0.5)
	ui.close_modal()
	ui.toast("Back on the farm")   # with no drawer it sits on the bar again, full width
	await await_idle_frame()
	assert_float(_panel().get_global_rect().size.x).is_equal(float(ToastLayer.WIDTH))
	assert_float(_panel().get_global_rect().end.y).is_greater(ui.root.size.y * 0.6)

func test_the_counter_and_kitchen_name_their_decision_areas() -> void:
	var k := P0KitchenDrawer.new()
	assert_object(k.action_area()).is_null()   # not in the tree yet: nothing shows
	k.free()
	var c := P0CounterDrawer.new({}, "homestead")
	assert_object(c.action_area()).is_null()
	c.free()

## E-04 FARM-3-RESULT-2: the bag fills mid-harvest — the run's count floats, the Error toast points at the stall with
## Open bag, and the hold stops.
func test_a_harvest_that_fills_the_bag_says_how_far_it_got() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	add_child(rt)
	await get_tree().process_frame
	var slots := []
	for i in 25: slots.append({"id": "crop_radish", "qty": 50})
	var v := {"energy": {"value": 140, "max": 200}, "coins": 52, "bag": {"capacity": 25, "slots": slots},
		"skills": {"farming": {"level": 1, "xp": 20}}, "names": {"crop_radish": "Radish"},
		"plots": [{"id": 1, "state": "ready", "crop": "crop_radish"}, {"id": 2, "state": "ready", "crop": "crop_radish"}, {"id": 3, "state": "tilled"}]}
	for c in rt.session.connection_failed.get_connections(): rt.session.connection_failed.disconnect(c.callable)   # no server here
	rt.session.view = v
	rt.ui.set_view(v)
	rt.ui.fab_held = true
	for i in 12:   # one reply a labour beat apart
		rt._on_state(v, [{"kind": "xp", "skill": "farming", "amount": 2, "percent": 100}, {"kind": "item", "id": "crop_radish", "delta": 1}])
		await get_tree().process_frame
	rt._on_refused("bag_full", {"need": 1}, {"type": "harvest", "plot": 1})
	await get_tree().process_frame
	var texts := rt.ui.root.get_children().filter(func(c): return c is UiFloatText and not c.is_queued_for_deletion()).map(func(f): return f.text)
	assert_array(texts).contains(["Harvest 12 of 14 · bag full"])
	assert_str(rt.ui.toast_text()).is_equal("Bag 25/25 · Sell at Homestead Stall")
	assert_str(rt.ui._toasts.current_action()).is_equal("Open bag")
	assert_bool(rt.ui.fab_held).is_false()
