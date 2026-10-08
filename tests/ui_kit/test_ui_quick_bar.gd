extends GdUnitTestSuite
## UiQuickBar and UiPinMenu (SGODOT-221, LOCK-04 / 05; plan §10.3, WP7-B F-04 §3).

const T := preload("res://assets/p0/icons/seed_radish.svg")

var bar: UiQuickBar
var events: Array

func _slots() -> Array:
	return [
		{id = "seed_radish", icon = T, title = "Radish Seeds", quantity = 24, pinned = true},
		{id = "seed_carrot", icon = T, title = "Carrot Seeds", quantity = 6},
		{id = "fert_compost", icon = T, title = "Compost", quantity = 0, pinned = true},
		{id = "seed_bean", icon = T, title = "Beans", quantity = 3},
	]

func before_test() -> void:
	bar = UiQuickBar.new()
	bar.haptics = false
	bar.position = Vector2(12, 400)
	# On the top canvas layer: an earlier suite can leave a scene in the tree (tests/scenes leaks a MapPoc whose
	# HUD would take the press), and the real-input cases need the GUI routing (as #11 5809a810).
	var top := CanvasLayer.new()
	top.layer = 128
	add_child(auto_free(top))
	top.add_child(bar)
	bar.slots = _slots()
	events = []
	for sig in ["slot_tapped", "ghost_tapped", "pin_toggled", "slots_swapped", "slot_removed", "bag_requested", "close_requested", "handle_tapped"]:
		bar.connect(sig, func(a = null, b = null): events.append([sig, a, b]))
	await await_idle_frame()

func _center(i: int) -> Vector2: return bar.cells()[i].get_global_rect().get_center()

func test_slots_draw_their_states() -> void:
	bar.selected = "seed_carrot"
	var S := UiItemCell.State
	var states := bar.cells().map(func(c): return c.state)
	assert_array(states).contains_exactly([S.DEFAULT, S.SELECTED, S.ZERO, S.DEFAULT, S.EMPTY])
	assert_bool(bar.cells()[0].pinned).is_true()
	assert_str(bar.cells()[0].quantity).is_equal("×24")
	assert_str(bar.cells()[4].quantity).is_empty()   # a ghost slot has no count

func test_a_ghost_slot_shows_the_family_without_a_count_or_pin() -> void:
	bar.slots = [{id = "compost", icon = T, title = "Compost", quantity = 6},
		{ghost = true, icon = T, title = "Seeds", pinned = true}]
	var c: UiItemCell = bar.cells()[1]
	assert_int(c.state).is_equal(UiItemCell.State.GHOST)
	assert_str(c.title).is_equal("Seeds")
	assert_str(c.quantity).is_empty()
	assert_bool(c.pinned).is_false()   # never pinned (QuickSlot State=ghost, A-08)
	assert_int(bar.cells()[2].state).is_equal(UiItemCell.State.EMPTY)
	c.tapped.emit()
	assert_array(events).contains_exactly([["ghost_tapped", 1, null]])
	c.gesture.emit({kind = &"lift", pos = _center(1)})
	assert_int(c.state).is_equal(UiItemCell.State.GHOST)   # a ghost never floats

func test_bar_matches_the_figma_frame() -> void:
	assert_vector(bar.size).is_equal(Vector2(UiTokens.SIZE_QUICK_BAR_W, UiTokens.SIZE_QUICK_BAR_H))
	assert_float(bar.end_button().size.x).is_equal(float(UiTokens.SIZE_QUICK_END_W))
	# 5 × 52 + 56 + 5 gaps of 4 = 336 (BAR-1: bar at x 12, Bag end at x 292 of 360).
	assert_float(bar.end_button().position.x).is_equal(280.0)

func test_tap_selects_and_a_ghost_opens_the_bag_tab() -> void:
	bar.cells()[1].tapped.emit()
	bar.cells()[4].tapped.emit()
	assert_array(events).contains_exactly([["slot_tapped", "seed_carrot", null], ["ghost_tapped", 4, null]])

func test_long_press_floats_then_release_toggles_the_pin() -> void:
	bar.cells()[1].gesture.emit({kind = &"lift", pos = _center(1)})
	assert_int(bar.cells()[1].state).is_equal(UiItemCell.State.LIFTED)
	bar.cells()[1].gesture.emit({kind = &"pin_toggle", pos = _center(1)})
	bar.cells()[0].gesture.emit({kind = &"lift", pos = _center(0)})
	bar.cells()[0].gesture.emit({kind = &"pin_toggle", pos = _center(0)})
	assert_array(events).contains_exactly([["pin_toggled", "seed_carrot", true], ["pin_toggled", "seed_radish", false]])
	assert_int(bar.cells()[1].state).is_equal(UiItemCell.State.DEFAULT)

func test_drag_onto_another_slot_swaps_them() -> void:
	var c := bar.cells()[0]
	c.gesture.emit({kind = &"lift", pos = _center(0)})
	c.gesture.emit({kind = &"drag_start", pos = _center(0)})
	assert_bool(bar.is_dragging()).is_true()
	assert_int(c.state).is_equal(UiItemCell.State.EMPTY)   # the source shows a gap while its ghost follows the finger
	c.gesture.emit({kind = &"drag_move", pos = _center(2)})
	assert_int(bar.cells()[2].state).is_equal(UiItemCell.State.DROP_TARGET)
	c.gesture.emit({kind = &"drop", pos = _center(2)})
	assert_array(events).contains_exactly([["slots_swapped", 0, 2]])
	assert_bool(bar.is_dragging()).is_false()
	assert_int(bar.cells()[2].state).is_equal(UiItemCell.State.ZERO)

func test_drag_shows_the_remove_zone_and_dropping_on_it_removes() -> void:
	var c := bar.cells()[1]
	c.gesture.emit({kind = &"lift", pos = _center(1)})
	c.gesture.emit({kind = &"drag_start", pos = _center(1)})
	var zone := bar.remove_zone()
	assert_object(zone).is_not_null()
	var bar_top := bar.get_global_rect().position.y
	assert_vector(zone.center).is_equal(Vector2(bar.get_viewport_rect().size.x * 0.5, bar_top - 96.0))
	assert_bool(zone.hover).is_false()
	c.gesture.emit({kind = &"drag_move", pos = zone.center + Vector2(30, 20)})   # within 48
	assert_bool(zone.hover).is_true()
	assert_vector(bar._ghost.scale).is_equal(Vector2(0.8, 0.8))
	c.gesture.emit({kind = &"drop", pos = zone.center + Vector2(30, 20)})
	assert_array(events).contains_exactly([["slot_removed", "seed_carrot", null]])
	assert_bool(bar.is_dragging()).is_false()

func test_dragged_slot_rides_above_the_finger() -> void:
	var c := bar.cells()[0]
	c.gesture.emit({kind = &"lift", pos = _center(0)})
	c.gesture.emit({kind = &"drag_start", pos = Vector2(150, 600)})
	var g: UiItemCell = bar._ghost
	assert_float(g.global_position.y + g.custom_minimum_size.y).is_equal(600.0 - 24.0)
	assert_float(g.global_position.x + g.custom_minimum_size.x * 0.5).is_equal(150.0)

func test_release_anywhere_else_flies_back_and_changes_nothing() -> void:
	var c := bar.cells()[1]
	c.gesture.emit({kind = &"lift", pos = _center(1)})
	c.gesture.emit({kind = &"drag_start", pos = _center(1)})
	var top := bar.get_global_rect().position.y
	c.gesture.emit({kind = &"drop", pos = Vector2(_center(1).x, top - 41.0)})   # the old "40 above removes" is gone
	assert_array(events).is_empty()
	assert_bool(bar.is_dragging()).is_false()
	assert_int(c.state).is_equal(UiItemCell.State.DEFAULT)

func test_released_back_on_its_own_slot_toggles_the_pin() -> void:
	var c := bar.cells()[1]
	c.gesture.emit({kind = &"lift", pos = _center(1)})
	c.gesture.emit({kind = &"drag_start", pos = _center(1)})
	c.gesture.emit({kind = &"drag_move", pos = _center(3)})
	c.gesture.emit({kind = &"drop", pos = _center(1) + Vector2(0, -36)})   # out and back, within its slot +8
	assert_array(events).contains_exactly([["pin_toggled", "seed_carrot", true]])

func test_a_cancel_or_cancel_drag_flies_back() -> void:
	var c := bar.cells()[1]
	c.gesture.emit({kind = &"lift", pos = _center(1)})
	c.gesture.emit({kind = &"drag_start", pos = _center(1)})
	c.gesture.emit({kind = &"cancel"})   # a second finger
	assert_bool(bar.is_dragging()).is_false()
	c.gesture.emit({kind = &"lift", pos = _center(1)})
	c.gesture.emit({kind = &"drag_start", pos = _center(1)})
	bar.cancel_drag()   # app paused / a drawer opening
	assert_bool(bar.is_dragging()).is_false()
	assert_object(bar.remove_zone()).is_null()
	assert_array(events).is_empty()

func test_swipe_up_bag_and_close() -> void:
	bar.cells()[3].gesture.emit({kind = &"swipe_up"})
	bar.end_button().pressed.emit()
	bar.bag_open = true
	assert_str(bar.end_button().get_child(1).text).is_equal("Close")
	bar.end_button().pressed.emit()
	assert_array(events).contains_exactly([["bag_requested", null, null], ["bag_requested", null, null], ["close_requested", null, null]])

func test_collapsed_bar_shows_only_the_handle_and_bag() -> void:
	bar.collapsed = true
	await await_idle_frame()
	assert_bool(bar.cells().any(func(c): return c.visible)).is_false()
	assert_bool(bar.handle_button().visible).is_true()
	# BAR-1-2: the 120×44 target is centred on the 360 screen and rises 4 above the bar.
	assert_float(bar.handle_button().get_global_rect().get_center().x).is_equal_approx(12.0 + UiTokens.SIZE_QUICK_BAR_W * 0.5, 0.5)
	assert_float(bar.handle_button().position.y).is_equal(-4.0)
	assert_float(bar.end_button().position.x).is_equal(280.0)
	bar.handle_button().pressed.emit()
	assert_array(events).contains_exactly([["handle_tapped", null, null]])

func test_capacity_dot_only_while_the_bag_is_closed() -> void:
	bar.capacity_warning = true
	assert_bool(bar.end_button().get_child(2).visible).is_true()
	bar.bag_open = true
	assert_bool(bar.end_button().get_child(2).visible).is_false()

func test_pin_menu_reads_the_new_state_and_offers_the_reverse() -> void:
	var menu := UiPinMenu.new(true)
	add_child(auto_free(menu))
	assert_str(menu.verb()).is_equal("Unpin")
	assert_str(menu._note.text).is_equal("Pinned slots stay when the bar refills")
	assert_bool(menu._badge.visible).is_true()   # Unpin carries the slot's pin badge (§10.3)
	menu.pinned = false
	assert_str(menu.verb()).is_equal("Pin")
	assert_str(menu._note.text).is_equal("Pin to keep it when the bar refills")
	assert_bool(menu._badge.visible).is_false()
	var hits := [0]
	menu.toggled.connect(func(): hits[0] += 1)
	menu.button().activated.emit()
	assert_int(hits[0]).is_equal(1)
	await await_idle_frame()
	assert_float(menu._card.size.x).is_equal(float(UiTokens.SIZE_PIN_MENU_W))

# ---------------------------------------------------------------- real GUI routing

class _Sink extends Node:
	var n := 0
	func _unhandled_input(e: InputEvent) -> void:
		if e is InputEventMouseButton or e is InputEventScreenTouch: n += 1

func test_real_tap_selects_and_never_reaches_unhandled_input() -> void:
	# The bar sits outside any scroll container; its STOP backing keeps slot touches out of the world
	# (map_poc handles map taps in _unhandled_input, SGODOT-212 note).
	var sink := _Sink.new()
	add_child(auto_free(sink))
	await _into_view()
	var at := _center(1)
	_push(_press(at, true))
	_push(_press(at, false))
	await await_idle_frame()
	assert_array(events).contains_exactly([["slot_tapped", "seed_carrot", null]])
	assert_int(sink.n).is_equal(0)

func test_real_long_press_pins_through_the_cell_arbiter() -> void:
	var now := [0]
	for c in bar.cells(): c.clock = func() -> int: return now[0]
	await _into_view()
	var at := _center(1)
	_push(_press(at, true))
	await await_idle_frame()
	now[0] = GestureArbiter.LONG_PRESS_MS + 10
	bar.cells()[1]._process(0.0)
	assert_int(bar.cells()[1].state).is_equal(UiItemCell.State.LIFTED)
	_push(_press(at, false))
	await await_idle_frame()
	assert_array(events).contains_exactly([["pin_toggled", "seed_carrot", true]])

## The headless test viewport is small; routed presses must land inside it.
func _into_view() -> void:
	bar.position = Vector2(12, 20)
	for i in 2: await get_tree().process_frame

## Positions are viewport (canvas) coordinates; the test window is scaled 2×, so push them as local.
func _push(e: InputEvent) -> void: get_viewport().push_input(e, true)

func _press(pos: Vector2, down: bool) -> InputEvent:
	if DisplayServer.is_touchscreen_available():
		var t := InputEventScreenTouch.new()
		t.position = pos
		t.pressed = down
		return t
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_LEFT
	m.position = pos
	m.global_position = pos
	m.pressed = down
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	return m

func test_pin_menu_matches_the_main_and_the_pointer_sits_under_the_card() -> void:
	# Kit components take their fonts from UiKit.theme(); the project theme is still the old app theme.
	var host := Control.new()
	host.theme = UiKit.theme()
	add_child(auto_free(host))
	var one := UiPinMenu.new(false)
	var two := UiPinMenu.new(true)
	host.add_child(one)
	host.add_child(two)
	for i in 3: await get_tree().process_frame
	for m: UiPinMenu in [one, two]:
		# PinMenu 1141:80291 is 200 × 108 in both variants (the note box keeps two lines).
		assert_float(m._card.size.x).is_equal(float(UiTokens.SIZE_PIN_MENU_W))
		assert_float(m._card.size.y).is_equal_approx(108.0, 3.0)
		assert_float(m._pointer.position.y).is_equal(m._card.size.y)
		assert_float(m.get_combined_minimum_size().y).is_equal(m._card.size.y + UiTokens.SIZE_POINTER_H)

func test_bag_only_keeps_just_the_bag_end() -> void:
	bar.bag_only = true
	await await_idle_frame()
	assert_bool(bar.cells().any(func(c): return c.visible)).is_false()
	assert_bool(bar.handle_button().visible).is_false()
	assert_bool(bar.end_button().visible).is_true()
	assert_float(bar.end_button().position.x).is_equal(280.0)

func test_pin_menu_dismisses_after_three_seconds_or_a_press_elsewhere() -> void:
	var menu := UiPinMenu.new(true)
	menu.position = Vector2(20, 40)
	add_child(auto_free(menu))
	await await_idle_frame()
	var gone := [0]
	menu.dismissed.connect(func(): gone[0] += 1)
	menu._process(UiPinMenu.DISMISS_S - 0.1)
	assert_int(gone[0]).is_equal(0)
	menu._process(0.2)
	assert_int(gone[0]).is_equal(1)
	menu._process(5.0)
	assert_int(gone[0]).is_equal(1)   # once
	var other := UiPinMenu.new(false)
	other.position = Vector2(20, 40)
	add_child(auto_free(other))
	await await_idle_frame()
	var hits := [0, 0]
	other.dismissed.connect(func(): hits[0] += 1)
	other.toggled.connect(func(): hits[1] += 1)
	var inside := other._card.get_global_rect().get_center()
	_push(_press(inside, true))
	await await_idle_frame()
	assert_int(hits[0]).is_equal(0)   # a press on the card is not "elsewhere"
	_push(_press(inside + Vector2(0, 200), true))
	await await_idle_frame()
	assert_int(hits[0]).is_equal(1)

func test_pin_badge_sits_at_the_buttons_left_like_the_main() -> void:
	var host := Control.new()
	host.theme = UiKit.theme()
	add_child(auto_free(host))
	var menu := UiPinMenu.new(true)
	host.add_child(menu)
	for i in 3: await get_tree().process_frame
	var b := menu._badge.get_rect()
	assert_vector(b.size).is_equal(Vector2(20, 20))
	assert_float(b.position.x).is_equal(18.0)
	assert_float(b.get_center().y).is_equal(menu.button().size.y * 0.5)
	assert_float(menu._verb.get_rect().get_center().x).is_equal(menu.button().size.x * 0.5)   # verb stays centred

func test_a_drag_released_back_on_its_own_slot_pins_it() -> void:
	# LOCK-04 / 05 v1.10 (BAR-DRAG-1): the release point decides, not the movement, so a shaky drag out and back pins.
	var now := [0]
	for c in bar.cells(): c.clock = func() -> int: return now[0]
	await _into_view()
	var at := _center(1)
	_push(_press(at, true))
	await await_idle_frame()
	now[0] = GestureArbiter.LONG_PRESS_MS + 10
	bar.cells()[1]._process(0.0)
	assert_int(bar.cells()[1].state).is_equal(UiItemCell.State.LIFTED)   # the press really reached the slot
	_push(_move(at + Vector2(30, 0)))
	assert_bool(bar.is_dragging()).is_true()
	_push(_move(at))   # back over its own slot
	_push(_press(at, false))
	await await_idle_frame()
	assert_array(events.filter(func(e): return e[0] in ["pin_toggled", "slots_swapped", "slot_removed"])).is_equal([["pin_toggled", "seed_carrot", true]])

func _move(pos: Vector2) -> InputEvent:
	if DisplayServer.is_touchscreen_available():
		var d := InputEventScreenDrag.new()
		d.position = pos
		return d
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	return m

func test_collapsed_or_bag_only_bar_leaves_its_gap_to_the_world() -> void:
	# The "world" is a STOP catcher under the bar on the same top layer, so nothing an earlier suite left in the
	# tree (a MapPoc HUD) can take the press first (full runs, PR #12 review).
	var world := _World.new()
	world.set_anchors_preset(Control.PRESET_FULL_RECT)
	world.size = Vector2(720, 1280)
	bar.get_parent().add_child(world)
	bar.get_parent().move_child(world, 0)
	await _into_view()
	var gap := bar.get_global_rect().position + Vector2(40, bar.size.y * 0.5)   # where the first slot would be
	for mode in ["collapsed", "bag_only"]:
		bar.collapsed = mode == "collapsed"
		bar.bag_only = mode == "bag_only"
		await await_idle_frame()
		world.n = 0
		_push(_press(gap, true))
		_push(_press(gap, false))
		await await_idle_frame()
		assert_int(world.n).is_equal(2)
	bar.bag_only = false
	await await_idle_frame()
	world.n = 0
	_push(_press(gap, true))
	_push(_press(gap, false))
	await await_idle_frame()
	assert_int(world.n).is_equal(0)   # with cells shown the bar keeps its touches
	world.queue_free()

class _World extends Control:
	var n := 0
	func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton or e is InputEventScreenTouch: n += 1
