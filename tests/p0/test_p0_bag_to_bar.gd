extends GdUnitTestSuite
## The bag drawer and the quick bar (SGODOT-225 on #38's interface, q(61); LOCK-12 / BAR-DRAG-7…9): the drawer's first
## row is the bar itself; the card's Pin / Unpin; a long-pressed bag cell dropped on the Pin zone or on a slot.

const STORE := "user://test_p0_bag_to_bar.json"

var ui: P0Ui

func _view() -> Dictionary:
	var slots: Array = [{"id": "seed_radish", "qty": 20}, {"id": "seed_lettuce", "qty": 10}, {"id": "crop_radish", "qty": 3},
		{"id": "fert_compost", "qty": 4}, {"id": "bait_worm", "qty": 6}, {"id": "seed_carrot", "qty": 5},
		{"id": "seed_potato", "qty": 5}, {"id": "seed_herb", "qty": 5}]
	return {
		"energy": {"value": 200, "max": 200, "next_in": null, "regen_ms": 240000},
		"crops": [{"id": "crop_radish", "seed": "seed_radish", "energy": 2}],
		"names": {"seed_radish": "Radish Seeds", "seed_lettuce": "Lettuce Seeds", "fert_compost": "Compost",
			"seed_carrot": "Carrot Seeds", "seed_potato": "Potato Seeds", "seed_herb": "Herb Seeds"},
		"items": {"seed_radish": {"kind": "seed"}, "seed_lettuce": {"kind": "seed"}, "seed_carrot": {"kind": "seed"},
			"seed_potato": {"kind": "seed"}, "seed_herb": {"kind": "seed"}, "fert_compost": {"kind": "fert"},
			"crop_radish": {"kind": "crop", "sell": 5}, "bait_worm": {"kind": "bait"}},
		"bag": {"capacity": 25, "free": 15, "slots": slots},
		"plots": [], "rest": {"used": 0, "limit": 1, "resets_in": 3600000}, "coins": 40, "skills": {},
	}

func before_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	ui = P0Ui.new()
	ui.quick_store = STORE
	add_child(auto_free(ui))
	ui.layer = 128
	await await_idle_frame()
	ui.set_mode("farm")
	ui.set_surface("farm")
	ui.set_view(_view())

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func _bag() -> P0BagDrawer:
	return ui.find_children("*", "P0BagDrawer", true, false).filter(func(d): return not d.is_queued_for_deletion())[0]

func _labels(d: P0BagDrawer) -> Array:
	return d.sheet.spec().get("buttons", []).map(func(b): return str(b.label))

func _ids() -> Array: return ui._bar_ids.map(func(id): return str(id))

func test_the_drawer_row_is_the_bar_itself_and_it_goes_home_on_close() -> void:
	ui.open_bag()
	await await_idle_frame()
	var d := _bag()
	assert_bool(ui.is_bar_docked()).is_true()
	assert_object(ui._bar.get_parent()).is_same(d.quick_row)
	assert_bool(ui._bar.is_visible_in_tree()).is_true()
	assert_bool(ui._bar.bag_open).is_true()   # its end cell is Close
	ui.close_modal()
	await await_idle_frame()
	assert_bool(ui.is_bar_docked()).is_false()
	assert_object(ui._bar.get_parent()).is_same(ui._kit)

func test_no_bar_rides_along_where_there_is_no_action() -> void:
	ui.set_surface("room")   # the farmhouse: Bag only
	ui.open_bag()
	await await_idle_frame()
	assert_bool(ui.is_bar_docked()).is_false()

func test_the_card_pins_and_unpins_and_says_when_the_bar_is_full() -> void:
	ui.open_bag("seed_lettuce")
	await await_idle_frame()
	var d := _bag()
	assert_array(_labels(d)).contains(["Pin"])
	d.action_requested.emit(&"pin", "seed_lettuce", {})
	assert_bool(ui.is_pinned("seed_lettuce")).is_true()
	assert_array(_labels(d)).contains(["Unpin"])
	d.action_requested.emit(&"pin", "seed_lettuce", {})
	assert_bool(ui.is_pinned("seed_lettuce")).is_false()
	for id in ["seed_radish", "seed_lettuce", "fert_compost", "seed_carrot", "seed_potato"]: ui.pin_to(id)
	d.grid.select("seed_herb")
	assert_array(_labels(d)).contains(["Bar full · Unpin one first"])
	d.action_requested.emit(&"pin", "seed_herb", {})   # greyed: nothing pinned
	assert_bool(ui.is_pinned("seed_herb")).is_false()

func test_a_lifted_bag_cell_dropped_on_the_pin_zone_is_pinned_on_its_bar() -> void:
	ui.open_bag()
	await await_idle_frame()
	var it := {id = "seed_herb", qty = 5}
	ui._on_bag_cell(it, {kind = &"lift", pos = Vector2(100, 600)})
	assert_bool(ui._bag_drag.is_empty()).is_false()
	var zone: UiBarDropZone = ui._bag_drag.zone
	assert_int(zone.kind).is_equal(UiBarDropZone.Kind.PIN)
	assert_float(zone.center.y).is_equal_approx(ui._bar.get_global_rect().end.y + GestureArbiter.DROP_ZONE_ABOVE, 0.01)
	assert_float(_bag().grid.modulate.a).is_less(1.0)   # the grid dims while one of its cells is in the air
	var grid := _bag().grid
	var at := grid.shown_items().map(func(x): return str(x.id)).find("seed_herb")
	assert_int(grid.cells()[at].state).is_equal(UiItemCell.State.EMPTY)   # its own cell is a dashed gap
	ui._on_bag_cell(it, {kind = &"drag_move", pos = zone.center})
	assert_bool(zone.hover).is_true()
	ui._on_bag_cell(it, {kind = &"drop", pos = zone.center})
	assert_bool(ui.is_pinned("seed_herb")).is_true()
	assert_bool(_ids().has("seed_herb")).is_true()
	assert_bool(ui._bag_drag.is_empty()).is_true()
	assert_float(_bag().grid.modulate.a).is_equal(1.0)
	assert_int(grid.cells()[at].state).is_not_equal(UiItemCell.State.EMPTY)   # back in place

func test_a_bag_cell_dropped_on_a_slot_is_placed_there_without_a_pin() -> void:
	ui.open_bag()
	await await_idle_frame()
	var it := {id = "seed_herb", qty = 5}
	var slot1: Vector2 = ui._bar.cells()[1].get_global_rect().get_center()
	ui._on_bag_cell(it, {kind = &"lift", pos = Vector2(100, 600)})
	ui._on_bag_cell(it, {kind = &"drag_move", pos = slot1})
	assert_int(ui._bar.cells()[1].state).is_equal(UiItemCell.State.DROP_TARGET)
	ui._on_bag_cell(it, {kind = &"drop", pos = slot1})
	assert_str(_ids()[1]).is_equal("seed_herb")
	assert_bool(ui.is_pinned("seed_herb")).is_false()

func test_released_in_place_or_off_target_nothing_changes_and_crops_never_lift() -> void:
	ui.open_bag()
	await await_idle_frame()
	var before := _ids()
	var it := {id = "seed_herb", qty = 5}
	ui._on_bag_cell(it, {kind = &"lift", pos = Vector2(100, 600)})
	ui._on_bag_cell(it, {kind = &"long_press", pos = Vector2(100, 600)})
	assert_bool(ui._bag_drag.is_empty()).is_true()
	ui._on_bag_cell(it, {kind = &"lift", pos = Vector2(100, 600)})
	ui._on_bag_cell(it, {kind = &"drop", pos = Vector2(300, 700)})
	assert_array(_ids()).is_equal(before)
	assert_bool(ui.is_pinned("seed_herb")).is_false()
	ui._on_bag_cell({id = "crop_radish", qty = 3}, {kind = &"lift", pos = Vector2(100, 600)})
	assert_bool(ui._bag_drag.is_empty()).is_true()   # no bar takes crops

func test_closing_the_drawer_mid_drag_drops_the_lifted_cell() -> void:
	ui.open_bag()
	await await_idle_frame()
	ui._on_bag_cell({id = "seed_herb", qty = 5}, {kind = &"lift", pos = Vector2(100, 600)})
	ui.close_modal()
	assert_bool(ui._bag_drag.is_empty()).is_true()

func test_undo_shows_over_the_docked_bar_on_the_drawer_layer() -> void:
	ui.open_bag()
	await get_tree().create_timer(UiKit.secs(UiTokens.MOTION_DRAWER_MS) + 0.1).timeout   # the drawer has risen
	ui._on_slot_removed(str(ui._bar_ids[0]))
	for i in 3: await await_idle_frame()   # the message wraps, the card refits
	var toast: UiUndoToast = ui._undo_toast
	assert_object(toast.get_parent()).is_same(ui._modal)
	var r := toast.get_global_rect()
	assert_float(r.position.y).is_greater_equal(0.0)
	assert_float(r.end.y).is_equal_approx(ui._bar.get_global_rect().position.y - UiTokens.SPACE_WITHIN, 0.5)
	assert_float(r.size.y).is_less(120.0)   # two short lines, not the unwrapped height
