extends GdUnitTestSuite
## Shared panel parts of SGODOT-225: the bottom drawer and the bag grid with its counter hooks.

func _host(c: Control, size := Vector2(360, 800)) -> Control:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = size
	add_child(auto_free(host))
	host.add_child(c)
	return c

func _settle() -> void:
	for i in 2: await get_tree().process_frame

func _drawer(h := 546.0) -> UiDrawer:
	var d := UiDrawer.new(h)
	d.animate = false
	return _host(d)

# ---------------------------------------------------------------- UiDrawer

func test_drawer_sits_on_the_bottom_with_the_bag_proportions() -> void:
	var d := _drawer()
	await _settle()
	assert_vector(d.position).is_equal(Vector2(0, 800 - 546))
	assert_vector(d.size).is_equal(Vector2(360, 546))
	var box := d.get_theme_stylebox(&"panel") as UiStyleBox
	assert_that(box.corner_radius).is_equal(Vector4(UiTokens.RADIUS_SHEET, UiTokens.RADIUS_SHEET, 0, 0))
	assert_str(box.bg_color.to_html()).is_equal(UiTokens.COLOR_SURFACE.to_html())
	# content starts where the Bag layout does: x 12, y 12 inside the drawer
	assert_vector(d.body.position).is_equal(Vector2(12, 12))
	assert_float(d.body.size.x).is_equal(336.0)

func test_drawer_keeps_content_above_the_safe_inset_and_never_exceeds_the_host() -> void:
	var d := _drawer(900.0)
	d.safe_bottom = 24.0
	await _settle()
	assert_float(d.size.y).is_equal(800.0)
	assert_float(d.body.get_rect().end.y).is_equal(800.0 - 12.0 - 24.0)

func test_drawer_slides_up_when_animated() -> void:
	var d := UiDrawer.new(546.0)
	_host(d)
	await _settle()
	assert_float(d.position.y).is_greater(800.0 - 546.0)   # still on the way up
	await get_tree().create_timer(UiKit.secs(UiTokens.MOTION_DRAWER_MS) + 0.1).timeout
	assert_float(d.position.y).is_equal_approx(800.0 - 546.0, 0.5)

# Real viewport input (SGODOT-265, 不知火舞's spec): the handle band moves the drawer, a scroll at its top does from its
# top, other content does not; 1:1, closed past a quarter (≥ 80 px) or by a fling, else back into place.

func _mouse(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	get_viewport().push_input(e, true)

func _motion(at: Vector2, rel: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(m, true)

## Press at `from`, move by `by` in `steps` (a frame each, `ms` on the fake clock `now` each when given), release.
func _swipe(from: Vector2, by: Vector2, steps := 8, now: Array = [], ms := 40, release := true, press := true) -> void:
	if press:
		_mouse(from, true)
		await get_tree().process_frame
	for i in steps:
		if not now.is_empty(): now[0] += ms
		_motion(from + by * float(i + 1) / steps, by / steps)
		await get_tree().process_frame
	if release:
		_mouse(from + by, false)
		await get_tree().process_frame

func _fake_clock(d: UiDrawer) -> Array:
	var now := [1000]
	d.clock = func() -> int: return now[0]
	return now

## A drawer like the Bag: a tab row in the handle band, a second row under it, a scrolling grid, a kept row (the
## docked quick bar) at the bottom.
func _bag_like() -> Dictionary:
	var d := UiDrawer.new(500.0)
	d.animate = false
	var early := Button.new()   # built before the drawer enters the tree, as P0BagDrawer does
	early.custom_minimum_size = Vector2(120, 30)
	d.body.add_child(early)
	_host(d)
	var tab := Button.new()     # added later, on a refresh
	tab.custom_minimum_size = Vector2(120, 34)
	var row := HBoxContainer.new()
	row.add_child(tab)
	d.body.add_child(row)
	var grid := TouchScrollContainer.new()
	grid.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid.custom_minimum_size.y = 200
	d.body.add_child(grid)
	var cell := Button.new()
	cell.custom_minimum_size = Vector2(100, 600)
	grid.add_child(cell)
	var kept := PanelContainer.new()
	kept.set_meta(UiDrawer.KEEP_INPUT, true)
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(60, 44)
	kept.add_child(slot)
	d.body.add_child(kept)
	return {drawer = d, early = early, tab = tab, grid = grid, cell = cell, slot = slot}

func _count(sig: Signal) -> Array:
	var n := [0]
	sig.connect(func(): n[0] += 1)
	return n

func _band(d: UiDrawer) -> Vector2: return d.get_global_rect().position + Vector2(180, 24)   # mid handle band

func test_every_drawer_has_a_handle_that_shows_a_press_in_its_band() -> void:
	if DisplayServer.is_touchscreen_available(): return   # synthetic mouse input below
	var d := _drawer(500.0)
	await _settle()
	assert_bool(d.handle).is_true()
	_mouse(_band(d), true)
	await get_tree().process_frame
	assert_bool(d._band_down).is_true()   # color/secondary while pressed
	_mouse(_band(d), false)
	await get_tree().process_frame
	assert_bool(d._band_down).is_false()
	_mouse(d.get_global_rect().position + Vector2(180, 200), true)   # under the band: no
	await get_tree().process_frame
	assert_bool(d._band_down).is_false()
	_mouse(d.get_global_rect().position + Vector2(180, 200), false)

func test_a_drag_on_the_handle_band_follows_and_springs_back_when_short() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var d := _drawer(546.0)
	await _settle()
	var now := _fake_clock(d)
	var veil := ColorRect.new()   # behind the drawer, as a host's scrim
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.get_parent().add_child(veil)
	d.get_parent().move_child(veil, 0)
	d.scrim = veil
	var closes := _count(d.close_requested)
	var top := d.position.y
	await _swipe(_band(d), Vector2(0, 110), 10, now, 60, false)   # slow, 110 px: under a quarter (136.5)
	assert_float(d.position.y - top).is_equal_approx(110.0, 1.0)   # 1:1 with the finger from the press
	assert_float(veil.modulate.a).is_equal_approx(1.0 - 110.0 / 546.0, 0.01)
	_mouse(_band(d) + Vector2(0, 110), false)
	await get_tree().create_timer(0.3).timeout
	assert_float(d.position.y).is_equal_approx(top, 0.5)   # back into place
	assert_float(veil.modulate.a).is_equal_approx(1.0, 0.01)
	assert_int(closes[0]).is_zero()

func test_a_drag_past_a_quarter_closes_from_where_it_is() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var d := _drawer(546.0)
	await _settle()
	var now := _fake_clock(d)
	var closes := _count(d.close_requested)
	await _swipe(_band(d), Vector2(0, 160), 8, now, 80)   # slow, 150 px past the slop
	assert_int(closes[0]).is_zero()   # on its way down first
	await get_tree().create_timer(0.25).timeout
	assert_int(closes[0]).is_equal(1)
	assert_float(d.position.y).is_equal_approx(800.0, 1.0)   # all the way down

func test_a_fling_closes_and_a_slow_short_drag_does_not() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var d := _drawer(546.0)
	await _settle()
	var now := _fake_clock(d)
	var closes := _count(d.close_requested)
	await _swipe(_band(d), Vector2(0, 40), 4, now, 60)   # 30 px past the slop at ~170 px/s: back
	await get_tree().create_timer(0.3).timeout
	assert_int(closes[0]).is_zero()
	await _swipe(_band(d), Vector2(0, 50), 4, now, 10)   # 40 px at ~1250 px/s: a fling
	await get_tree().create_timer(0.25).timeout
	assert_int(closes[0]).is_equal(1)

func test_a_drag_up_or_sideways_on_the_band_does_not_move_it() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var d := _drawer(546.0)
	await _settle()
	var top := d.position.y
	await _swipe(_band(d), Vector2(0, -60), 6, [], 40, false)
	assert_float(d.position.y).is_equal_approx(top, 0.5)
	_mouse(_band(d) + Vector2(0, -60), false)
	await _swipe(_band(d) + Vector2(-80, 0), Vector2(120, 40), 6, [], 40, false)   # 18° off horizontal
	assert_float(d.position.y).is_equal_approx(top, 0.5)
	_mouse(_band(d) + Vector2(40, 40), false)

func test_a_tap_on_a_title_button_taps_and_a_drag_from_it_moves_the_drawer_without_firing_it() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var p := _bag_like()
	await _settle()
	var d: UiDrawer = p.drawer
	assert_int(p.early.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	var at: Vector2 = p.early.get_global_rect().get_center()
	assert_float(at.y - d.get_global_rect().position.y).is_less(UiDrawer.HANDLE_H)   # in the band
	var closes := _count(d.close_requested)
	var taps := _count(p.early.pressed)
	_mouse(at, true)
	await get_tree().process_frame
	_mouse(at, false)
	await get_tree().process_frame
	assert_int(taps[0]).is_equal(1)
	await _swipe(at, Vector2(0, 200), 8, _fake_clock(d), 60)
	await get_tree().create_timer(0.25).timeout
	assert_int(closes[0]).is_equal(1)
	assert_int(taps[0]).is_equal(1)   # the drag fired nothing

func test_other_content_does_not_close_it_and_a_drag_there_fires_nothing() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var p := _bag_like()
	await _settle()
	var d: UiDrawer = p.drawer
	var top := d.position.y
	var closes := _count(d.close_requested)
	var taps := _count(p.tab.pressed)
	var at: Vector2 = p.tab.get_global_rect().get_center()   # the second row, under the band
	assert_float(at.y - d.get_global_rect().position.y).is_greater(UiDrawer.HANDLE_H)
	await _swipe(at, Vector2(0, 20), 4)   # a short drag ending on the tab
	await _swipe(at, Vector2(0, 200), 8)
	await get_tree().create_timer(0.3).timeout
	assert_float(d.position.y).is_equal_approx(top, 0.5)
	assert_int(closes[0]).is_zero()
	assert_int(taps[0]).is_zero()

func test_a_scroll_at_its_top_moves_the_drawer_from_its_top_and_one_lower_only_scrolls() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var p := _bag_like()
	await _settle()
	var d: UiDrawer = p.drawer
	var grid: ScrollContainer = p.grid
	var now := _fake_clock(d)
	var closes := _count(d.close_requested)
	var top := d.position.y
	grid.scroll_vertical = 120   # scrolled down: a drag down scrolls back to the top and stops there
	await get_tree().process_frame
	await _swipe(grid.get_global_rect().get_center(), Vector2(0, 260), 10, now, 60)
	await get_tree().create_timer(0.3).timeout
	assert_float(d.position.y).is_equal_approx(top, 0.5)
	assert_int(closes[0]).is_zero()
	grid.scroll_vertical = 0   # at the top as the press starts: the drawer follows and closes
	await get_tree().process_frame
	await _swipe(grid.get_global_rect().get_center(), Vector2(0, 220), 8, now, 60)
	await get_tree().create_timer(0.25).timeout
	assert_int(closes[0]).is_equal(1)

func test_a_long_press_in_a_scroll_lifts_before_a_drag_counts() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var p := _bag_like()
	await _settle()
	var d: UiDrawer = p.drawer
	var now := _fake_clock(d)
	var top := d.position.y
	var at: Vector2 = p.grid.get_global_rect().get_center()
	_mouse(at, true)
	await get_tree().process_frame
	now[0] += GestureArbiter.LONG_PRESS_MS + 10   # held: the cell lifts (LOCK-12 v1.11)
	await _swipe(at, Vector2(0, 200), 8, now, 30, false, false)
	assert_float(d.position.y).is_equal_approx(top, 0.5)
	_mouse(at + Vector2(0, 200), false)
	await get_tree().process_frame

func test_kept_rows_keep_their_drags() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var p := _bag_like()
	await _settle()
	var closes := _count(p.drawer.close_requested)
	assert_int(p.slot.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)   # untouched
	await _swipe(p.slot.get_global_rect().get_center(), Vector2(0, 60))
	await get_tree().create_timer(0.25).timeout
	assert_int(closes[0]).is_zero()

## 亚瑟 on #196: a fast 60 px drag that rests 500 ms before the lift springs back (60 < a quarter of 546; the finger has
## no speed left), where the speed of the drag 100 ms earlier closed it.
func test_a_fast_drag_that_rests_before_the_lift_springs_back() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var d := _drawer()
	await _settle()
	var now := _fake_clock(d)
	var closes := _count(d.close_requested)
	var at := _band(d)
	await _swipe(at, Vector2(0, 60), 4, now, 10, false)
	now[0] += 500   # the finger rests
	await get_tree().process_frame
	_mouse(at + Vector2(0, 60), false)   # where the finger is, not _band(d): the drawer has moved down with it
	await get_tree().create_timer(0.35).timeout
	assert_int(closes[0]).is_zero()
	assert_float(d.offset_bottom).is_equal_approx(0.0, 0.5)

## A filter strip in a drawer, flung sideways, coasts after the lift as one outside a drawer does, and a move with no
## button down does not drag it afterwards (亚瑟 on #196: the eaten release left it dragging, with no inertia).
func test_a_strip_flung_in_a_drawer_coasts_and_ends_its_drag() -> void:
	var emulate := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true
	var d := _drawer()
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 60   # below the handle band
	d.body.add_child(spacer)
	var strip := TouchScrollContainer.new()
	strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip.custom_minimum_size = Vector2(336, 40)
	var row := HBoxContainer.new()
	for i in 12:
		var b := Button.new()
		b.text = "Filter %d" % i
		b.custom_minimum_size = Vector2(90, 36)
		row.add_child(b)
	strip.add_child(row)
	d.body.add_child(strip)
	for i in 3: await get_tree().process_frame
	var at := strip.get_global_rect().get_center()
	_touch_and_mouse(at, true)
	await get_tree().physics_frame
	for i in 8:
		_drag_and_motion(at + Vector2(-20 * (i + 1), 0), Vector2(-20, 0))
		await get_tree().physics_frame
	var lifted := strip.scroll_horizontal
	_touch_and_mouse(at + Vector2(-160, 0), false)
	for i in 3: await get_tree().physics_frame
	var coasted := strip.scroll_horizontal - lifted
	# The coast lasts as long as it lasts (in a full run it outlasted 20 ticks short of the strip's end): the move with
	# no button down comes once the strip is still — by the scroll bar's float value: near the end of a coast the whole
	# pixels can hold for 3 ticks while it still moves (刘邦 on #203).
	var bar := strip.get_h_scroll_bar()
	var last := bar.value
	var still := 0
	for i in 300:
		await get_tree().physics_frame
		still = still + 1 if bar.value == last else 0
		last = bar.value
		if still >= 3: break
	var before := strip.scroll_horizontal
	for i in 4:
		var m := InputEventMouseMotion.new()
		m.position = at + Vector2(-160 + 15 * (i + 1), 0)
		m.global_position = m.position
		m.relative = Vector2(15, 0)
		get_viewport().push_input(m, true)
		await get_tree().physics_frame
	Input.emulate_touch_from_mouse = emulate
	assert_int(lifted).is_greater(0)
	assert_int(coasted).is_greater(0)
	assert_int(strip.scroll_horizontal - before).is_zero()

## A title button the drag began on is not left drawn pressed once the drawer springs back (亚瑟 on #196).
func test_a_band_button_is_not_left_pressed_after_a_drag_springs_back() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var d := _drawer()
	var b := Button.new()
	b.custom_minimum_size = Vector2(120, 30)
	d.body.add_child(b)
	await _settle()
	var now := _fake_clock(d)
	var fired := _count(b.pressed)
	var at := b.get_global_rect().get_center()
	await _swipe(at, Vector2(0, 60), 4, now, 60)
	await get_tree().create_timer(0.35).timeout
	assert_int(b.get_draw_mode()).is_not_equal(BaseButton.DRAW_PRESSED)
	assert_int(fired[0]).is_zero()

# ---------------------------------------------------------------- UiInventoryGrid

func _items(n: int) -> Array:
	var out := []
	var icons := ["seed_radish", "fish_crucian", "dish_grilled_fish", "wood", "crop_radish"]
	for i in n:
		out.append({id = "it%d" % i, icon = load("res://assets/p0/icons/%s.svg" % icons[i % icons.size()]), qty = i + 1,
			kind = ["seed", "fish", "dish", "material", "crop"][i % 5]})
	return out

func _grid(n := 7, cap := 25) -> UiInventoryGrid:
	var g := UiInventoryGrid.new()
	g.custom_minimum_size = Vector2(336, 240)
	g.capacity = cap
	g.items = _items(n)
	return _host(g)

## int10c 256 ④ (不知火舞): five columns spread edge to edge, gap (width − 260) / 4, rows 12 apart.
func test_grid_spreads_five_columns_edge_to_edge_with_12_between_rows() -> void:
	for w in [328, 336]:
		var g := UiInventoryGrid.new()
		g.custom_minimum_size = Vector2(w, 240)
		g.items = _items(7)
		_host(g)
		await _settle()
		var cells := g.cells()
		var gap: int = (int(w) - 5 * UiTokens.SIZE_INVENTORY_CELL) / 4   # 17 in the bag drawer, 19 in the kitchen drawer
		assert_int(g.column_gap()).is_equal(gap)
		for i in UiInventoryGrid.COLUMNS:
			assert_float(cells[i].position.x).is_equal(float(i * (UiTokens.SIZE_INVENTORY_CELL + gap)))
		assert_float(cells[4].get_global_rect().end.x).is_equal(g.get_global_rect().end.x)   # flush right, scrolling or not
		assert_float(cells[5].position.y - cells[0].position.y).is_equal(UiTokens.SIZE_INVENTORY_CELL + 12.0)
		assert_vector(cells[0].size).is_equal(Vector2(UiTokens.SIZE_INVENTORY_CELL, UiTokens.SIZE_INVENTORY_CELL))

func test_grid_follows_its_host_when_the_width_narrows() -> void:
	var box: VBoxContainer = _host(VBoxContainer.new())
	box.size = Vector2(336, 400)
	var g := UiInventoryGrid.new()
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	g.items = _items(7)
	box.add_child(g)
	await _settle()
	assert_int(g.column_gap()).is_equal(19)
	box.size = Vector2(328, 400)
	await _settle()
	assert_float(g.size.x).is_equal(328.0)
	assert_int(g.column_gap()).is_equal(17)
	assert_float(g.cells()[4].get_global_rect().end.x).is_equal(g.get_global_rect().end.x)

func test_grid_lists_items_then_dashed_empties_up_to_capacity() -> void:
	var g := _grid(7, 25)
	await _settle()
	var shown := g.cells().filter(func(c): return c.visible)
	assert_int(shown.size()).is_equal(25)
	assert_int(shown[6].state).is_equal(UiItemCell.State.DEFAULT)
	assert_str(shown[6].quantity).is_equal("×7")
	assert_int(shown[7].state).is_equal(UiItemCell.State.EMPTY)
	g.capacity = 30   # the bag grows: five more empty cells
	assert_int(g.cells().filter(func(c): return c.visible).size()).is_equal(30)

func test_tapping_a_filled_cell_selects_it_and_runs_the_select_hook() -> void:
	var g := _grid(7)
	await _settle()
	var got := []
	g.on_select = func(it: Dictionary): got.append(it.id)
	var cleared := [0]
	g.selection_cleared.connect(func(): cleared[0] += 1)
	g.cells()[2].tapped.emit()
	assert_array(got).is_equal(["it2"])
	assert_int(g.cells()[2].state).is_equal(UiItemCell.State.SELECTED)
	g.cells()[4].tapped.emit()   # another cell switches
	assert_array(got).is_equal(["it2", "it4"])
	assert_int(g.cells()[2].state).is_equal(UiItemCell.State.DEFAULT)
	g.cells()[10].tapped.emit()  # an empty cell clears
	assert_str(g.selected_id).is_equal("")
	assert_int(cleared[0]).is_equal(1)
	assert_int(g.cells()[4].state).is_equal(UiItemCell.State.DEFAULT)

## Setting selected_id (the page a drawer opens on, a refresh keeping the choice) marks its cell in the same frame and
## emits nothing; only a tap's select() / clear_selection() emit (刘邦 on the kitchen drawer's first frame).
func test_setting_selected_id_marks_the_cell_at_once_without_a_signal() -> void:
	var g := _grid(10)
	await _settle()
	var got := []
	var cleared := [0]
	g.item_selected.connect(func(it): got.append(it.id))
	g.selection_cleared.connect(func(): cleared[0] += 1)
	g.items = _items(10)
	g.selected_id = "it3"
	assert_int(g.cell_for("it3").state).is_equal(UiItemCell.State.SELECTED)
	g.selected_id = "it5"
	assert_int(g.cell_for("it3").state).is_equal(UiItemCell.State.DEFAULT)
	assert_int(g.cell_for("it5").state).is_equal(UiItemCell.State.SELECTED)
	g.selected_id = ""
	assert_int(g.cell_for("it5").state).is_equal(UiItemCell.State.DEFAULT)
	assert_array(got).is_empty()
	assert_int(cleared[0]).is_equal(0)

func test_sell_mode_lists_only_what_this_counter_takes() -> void:
	var g := _grid(10)
	await _settle()
	g.select("it0")   # a seed: never sold
	g.can_sell = func(it: Dictionary) -> bool: return it.kind in ["crop", "fish"]
	g.sell_mode = true
	assert_that(g.shown_items().map(func(it): return it.id)).is_equal(["it1", "it4", "it6", "it9"])
	assert_str(g.selected_id).is_equal("")   # the seed left the view, so its selection went too
	g.select("it4")
	g.items = _items(10)                      # a refresh keeps a selection that is still listed
	assert_str(g.selected_id).is_equal("it4")
	assert_int(g.cell_for("it4").state).is_equal(UiItemCell.State.SELECTED)
	g.sell_mode = false
	assert_int(g.shown_items().size()).is_equal(10)

func test_filter_and_cell_gestures_pass_through_with_the_item() -> void:
	var g := _grid(10)
	await _settle()
	g.filter = func(it: Dictionary) -> bool: return it.kind == "fish"
	assert_that(g.shown_items().map(func(it): return it.id)).is_equal(["it1", "it6"])
	var got := []
	g.cell_gesture.connect(func(it: Dictionary, o: Dictionary): got.append([it.id, String(o.kind)]))
	g.cells()[1].gesture.emit({kind = &"long_press", pos = Vector2.ZERO})
	g.cells()[5].gesture.emit({kind = &"long_press", pos = Vector2.ZERO})   # an empty cell: nothing
	assert_array(got).is_equal([["it6", "long_press"]])

func test_kitchen_density_draws_kitchen_cells_with_status() -> void:
	var g := UiInventoryGrid.new()
	g.custom_minimum_size = Vector2(336, 240)
	g.density = UiItemCell.Density.KITCHEN
	var it := _items(2)
	it[0]["status"] = "In pot"
	it[1]["status"] = "Not for cooking"
	g.items = it
	_host(g)
	await _settle()
	var c0 := g.cells()[0]
	assert_int(c0.density).is_equal(UiItemCell.Density.KITCHEN)
	assert_vector(c0.size).is_equal(Vector2(UiTokens.SIZE_KITCHEN_CELL_W, UiTokens.SIZE_KITCHEN_CELL_H))
	assert_str(c0.status).is_equal("In pot")
	assert_str(g.cells()[1].status).is_equal("Not for cooking")
	assert_float(g.cells()[5].position.y - c0.position.y).is_equal(float(UiTokens.SIZE_KITCHEN_CELL_H) + UiInventoryGrid.ROW_GAP)   # 256 ④: rows 12 apart

func test_grid_scrolls_vertically_only() -> void:
	var g := _grid(25)
	await _settle()
	assert_int(g.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_float(g.get_v_scroll_bar().max_value).is_greater(g.size.y)

# ---------------------------------------------------------------- UiDialogueCard / UiResidentBar

const PIP := preload("res://assets/p0/art/pip-portrait.jpg")

func _pip(fields := {}) -> Dictionary:
	var d := {portrait = PIP, name = "Pip", role = "Courier", stage = "Familiar", have = 52, need = 90, next = "Trusted",
		line = "Got anything from the pond today?"}
	d.merge(fields, true)
	return d

func _texts(c: Node) -> Array:
	return c.find_children("*", "Label", true, false).filter(func(l): return l.is_visible_in_tree()).map(func(l): return l.text)

func _navs(c: Node) -> Array:
	return c.find_children("*", "UiNavButton", true, false).map(func(n): return n.label)

func _click(c: Control, at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		c._gui_input(e)

func test_keeper_head_has_a_place_line_and_no_profile_link() -> void:
	var c: UiDialogueCard = _host(UiDialogueCard.new(PIP, "Tackle Keeper · Finn", "", "Pick a rod, I'll string it."))
	c.portrait_size = UiDialogueCard.KEEPER_PORTRAIT
	c.place = "Rods and bait · Mission Tackle Shop"
	await _settle()
	assert_array(_texts(c)).contains(["Tackle Keeper · Finn", "Rods and bait · Mission Tackle Shop", "Pick a rod, I'll string it."])
	assert_array(_texts(c)).not_contains(["›"])
	assert_vector(c._portrait.size).is_equal(UiDialogueCard.KEEPER_PORTRAIT)
	var hits := [0]
	c.identity_pressed.connect(func(): hits[0] += 1)
	if not DisplayServer.is_touchscreen_available(): _click(c._identity, Vector2(4, 4))
	assert_int(hits[0]).is_equal(0)

func test_resident_bar_greets_first_then_offers_gift_and_request() -> void:
	var b: UiResidentBar = _host(UiResidentBar.new(_pip()))
	await _settle()
	assert_array(_texts(b)).contains(["Pip", "· Courier", "›", "Familiar", "52/90 · next Trusted", "Got anything from the pond today?"])
	assert_float(b.progress()).is_equal_approx(0.5, 0.0001)   # 52/90 floored to 10 %
	assert_bool(b.gift_button().get_parent() is HBoxContainer).is_true()   # Choices=Row
	assert_float(b.gift_button().get_global_rect().position.y).is_greater(b._bubble.get_global_rect().end.y)
	var got := []
	b.gift_pressed.connect(func(): got.append("gift"))
	b.request_pressed.connect(func(): got.append("request"))
	b.identity_pressed.connect(func(): got.append("profile"))
	b.gift_button().activated.emit()
	b.request_button().activated.emit()
	if not DisplayServer.is_touchscreen_available():
		_click(b._portrait, Vector2(10, 10))
		_click(b._identity, Vector2(4, -8))   # the 18 px name row still takes a tap 8 px above it (44 hit area)
	assert_array(got).is_equal(["gift", "request"] + ([] if DisplayServer.is_touchscreen_available() else ["profile", "profile"]))
	assert_array(_navs(b)).is_empty()   # Today’s meal / Recipe lesson only when available

func test_resident_bar_stacks_the_choices_when_one_carries_a_reason() -> void:
	var b: UiResidentBar = _host(UiResidentBar.new(_pip({gift_reason = "Gift already given today", meal = true, lesson = true})))
	await _settle()
	assert_bool(b.gift_button().get_parent() is VBoxContainer).is_true()   # Choices=Stacked
	assert_str(b.gift_button().text).is_equal("Gift already given today")
	assert_float(b.gift_button().size.x).is_equal_approx(b.request_button().size.x, 0.5)
	var got := []
	b.gift_pressed.connect(func(): got.append("gift"))
	b.gift_button().unavailable_pressed.emit("Gift already given today")
	assert_array(got).is_empty()
	assert_array(_navs(b)).is_equal(["Today’s meal", "Recipe lesson"])
	var deliver: UiResidentBar = _host(UiResidentBar.new(_pip({request_label = "Deliver"})))
	assert_str(deliver.request_button().text).is_equal("Deliver")

## q(222) ②: on the player's farm Request is left out; Gift takes the row alone, full width, still Primary, and
## greys with its reason as anywhere (LOCK-10). A Request reason alone does not stack the row.
func test_resident_bar_without_request_gives_gift_the_full_row() -> void:
	var b: UiResidentBar = _host(UiResidentBar.new(_pip({request = false, request_reason = "No more requests"})))
	await _settle()
	assert_object(b.request_button()).is_null()
	assert_bool(b.gift_button().get_parent() is HBoxContainer).is_true()
	assert_int(b.gift_button().get_parent().get_child_count()).is_equal(1)
	assert_int(b.gift_button().kind).is_equal(UiCommandButton.Kind.PRIMARY)
	assert_float(b.gift_button().size.x).is_equal_approx(b.gift_button().get_parent().size.x, 0.5)
	assert_array(_texts(b)).not_contains(["Request", "No more requests"])
	var busy: UiResidentBar = _host(UiResidentBar.new(_pip({request = false, gift_reason = "No dishes in your bag"})))
	await _settle()
	assert_object(busy.request_button()).is_null()
	assert_str(busy.gift_button().text).is_equal("No dishes in your bag")
	assert_int(busy.gift_button().get_parent().get_child_count()).is_equal(1)
	assert_float(busy.gift_button().size.x).is_equal_approx(busy.gift_button().get_parent().size.x, 0.5)

# ---------------------------------------------------------------- UiBagHeader / UiGearRow

func test_bag_header_count_sort_and_capacity_bar() -> void:
	var h: UiBagHeader = _host(UiBagHeader.new(19, 25))
	await _settle()
	assert_array(_texts(h)).contains(["Bag 19/25"])
	assert_str(h.sort_button().label).is_equal("Sort · Type")
	assert_str(h.sort_button().text).is_equal("Sort · Type")   # a toggle, so no ›
	assert_str(h.sort_button().get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_INFO.to_html())
	assert_bool(h.sort_shown()).is_true()
	assert_float(h.tabs().size.y).is_equal(34.0)   # SegmentedTabs track 34, segments 28
	assert_float(h.tabs().tabs()[0].size.y).is_equal(28.0)
	assert_bool(h.is_nearly_full()).is_false()
	h.used = 23   # 92 %: amber (§10.4.1)
	assert_bool(h.is_nearly_full()).is_true()
	var got := []
	h.side_changed.connect(func(s: int): got.append(s))
	var bag_h := h.size.y
	var tabs_y := h.tabs().global_position.y
	h.tabs().tabs()[1].pressed.emit()
	h.tabs().tabs()[1].button_pressed = true
	await _settle()
	assert_array(got).contains([1])
	assert_bool(h.sort_shown()).is_false()   # Sort is a Bag-side control …
	assert_float(h.sort_button().modulate.a).is_equal(0.0)
	assert_int(h.sort_button().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_bool(h.bar_shown()).is_false()
	assert_float(h.size.y).is_equal(bag_h)   # … but both keep their place: the header doesn't shrink (256 ③)
	assert_float(h.tabs().global_position.y).is_equal(tabs_y)
	h.side = UiBagHeader.Pane.BAG
	h.show_tabs = false                               # the gift drawer: just the count
	assert_bool(h.tabs().visible).is_false()
	assert_bool(h.sort_shown()).is_false()
	assert_bool(h._title.visible).is_true()

func test_gear_row_states() -> void:
	var rod := load("res://assets/p0/icons/rod_starter.svg")
	var eq: UiGearRow = _host(UiGearRow.new({icon = rod, title = "Starter Rod", state = &"equipped", effect = "Lands up to Fine fish"}))
	var owned: UiGearRow = _host(UiGearRow.new({icon = rod, title = "Reed Rod", state = &"owned", effect = "Lands up to Rare fish",
		action = {id = &"equip", label = "Equip", kind = &"secondary"}}))
	var locked: UiGearRow = _host(UiGearRow.new({icon = rod, title = "Carbon Rod", state = &"Fishing Lv5 · Tackle Shop", effect = "Lands up to Legendary fish",
		note = "Legendary needs Fishing Lv7–9"}))
	await _settle()
	assert_array(_texts(eq)).contains(["✓ Equipped"])
	assert_object(eq.action_button()).is_null()
	assert_array(_texts(owned)).contains(["Owned"])
	var got := []
	owned.action_pressed.connect(func(a: StringName): got.append(a))
	owned.action_button().activated.emit()
	assert_array(got).is_equal([&"equip"])
	assert_array(_texts(locked)).contains(["Fishing Lv5 · Tackle Shop"])
	# q(278): the note its own line under the effect, as muted (the tier a rod lands)
	var effect: Label = locked.find_child("Effect", true, false)
	var tier: Label = locked.find_child("Note", true, false)
	assert_str(tier.text).is_equal("Legendary needs Fishing Lv7–9")
	assert_int(tier.get_index()).is_equal(effect.get_index() + 1)
	assert_str(str(tier.theme_type_variation)).is_equal(str(effect.theme_type_variation))
	assert_object(eq.find_child("Note", true, false)).is_null()
	assert_object(locked.action_button()).is_null()
	assert_float(locked._icon.modulate.a).is_equal_approx(UiTokens.OPACITY_UNAVAILABLE_ICON, 0.001)

# ---------------------------------------------------------------- profile parts (LOCK-22)

func test_profile_top_bar_self_and_other() -> void:
	var me: UiProfileTopBar = _host(UiProfileTopBar.new(UiProfileTopBar.Kind.SELF, "Profile"))
	var other: UiProfileTopBar = _host(UiProfileTopBar.new(UiProfileTopBar.Kind.OTHER, "Ann"))
	await _settle()
	assert_array(_texts(me)).contains(["Profile"])
	assert_array(_texts(other)).contains(["Ann"])
	var got := []
	me.back_pressed.connect(func(): got.append("back"))
	me.settings_pressed.connect(func(): got.append("settings"))
	other.more_pressed.connect(func(_r: Rect2): got.append("more"))
	me.get_child(0).pressed.emit()
	me.right_button().pressed.emit()
	other.right_button().pressed.emit()
	assert_array(got).is_equal(["back", "settings", "more"])
	assert_vector(me.right_button().size).is_equal(Vector2(UiTokens.SIZE_CLOSE, UiTokens.SIZE_CLOSE))
	me.show_settings = false   # P0: no Settings page; the slot stays so the title does not move
	assert_float(me.right_button().modulate.a).is_equal(0.0)
	assert_int(me.right_button().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)

func test_more_menu_rows_follow_the_relation() -> void:
	for case in [[&"default", ["Unfollow", "Block", "Report"]], [&"close_friend", ["Unfollow", "Remove Close Friend", "Block", "Report"]],
			[&"blocked", ["Report"]]]:
		var menu: UiProfileMoreMenu = auto_free(UiProfileMoreMenu.new(case[0]))
		assert_array(menu.labels()).is_equal(case[1])
	var m: UiProfileMoreMenu = _host(UiProfileMoreMenu.new())
	var got := []
	m.picked.connect(func(id: StringName): got.append(id))
	(m.get_child(0).get_child(1) as Button).pressed.emit()
	assert_array(got).is_equal([&"block"])

func test_skill_card_ring_floors_to_ten_percent_and_reads_the_level() -> void:
	var c: UiSkillCard = _host(UiSkillCard.new("Farming", 3, 0.67, load("res://assets/p0/icons/hoe.svg")))
	await _settle()
	assert_array(_texts(c)).contains(["Farming", "Lv3"])
	assert_float(c.shown_progress()).is_equal_approx(0.6, 0.0001)
	assert_vector(c.size).is_equal(Vector2(107, 56))
	var hits := [0]
	c.pressed.connect(func(): hits[0] += 1)
	c.pressed.emit()
	assert_int(hits[0]).is_equal(1)

func test_farm_card_lines() -> void:
	var f: UiFarmCard = _host(UiFarmCard.new("Farmer's Homestead", "Level 1", "Radishes ready in 3h 32m", load("res://assets/p0/art/homestead-thumb.jpg")))
	await _settle()
	assert_array(_texts(f)).contains(["Farmer's Homestead", "Level 1", "Radishes ready in 3h 32m"])
	f.status = ""
	assert_array(_texts(f)).not_contains(["Radishes ready in 3h 32m"])
	assert_float(f.size.y).is_equal(76.0)

func _request(fields := {}) -> Dictionary:
	var d := {portrait = PIP, title = "Pip's First Fish", who = "Pip · Courier Kid · personal request",
		line = "Could you catch me a fish? Any kind is fine.", needs = [{name = "Common fish", have = 0, need = 1,
		icon = load("res://assets/p0/icons/fish_crucian.svg")}], reward = "+5 Friendship · 20 coins", deliver_to = "Pip · Travel Post"}
	d.merge(fields, true)
	return d

func test_request_card_reads_the_request_and_offers_accept_or_not_now() -> void:
	var c: UiRequestCard = _host(UiRequestCard.new(_request()))
	await _settle()
	assert_array(_texts(c)).contains(["Pip's First Fish", "Pip · Courier Kid · personal request", "Could you catch me a fish? Any kind is fine.",
		"Bring", "Reward", "+5 Friendship · 20 coins", "Deliver to", "Pip · Travel Post"])
	assert_int(c.find_children("*", "UiNeedTile", true, false).size()).is_equal(1)
	var got := []
	c.action_pressed.connect(func(): got.append("accept"))
	c.dismissed.connect(func(): got.append("later"))
	assert_str(c.action_button().text).is_equal("Accept")
	c.action_button().activated.emit()
	(c.find_children("*", "UiDismissButton", true, false)[0] as Button).pressed.emit()
	assert_array(got).is_equal(["accept", "later"])

func test_request_card_short_of_items_puts_the_gap_on_the_button() -> void:
	var c: UiRequestCard = _host(UiRequestCard.new(_request({action = "Deliver", reason = "Need 1 more Common fish"})))
	await _settle()
	assert_str(c.action_button().text).is_equal("Need 1 more Common fish")
	assert_bool(c.action_button().is_unavailable()).is_true()

func test_request_rewards_wrap_at_a_dot_and_keep_the_reset_note_below_and_the_bottom_fixed() -> void:
	var short := "+5 Friendship · 80 coins · New title"
	var long := "+5 Friendship · 90 coins · New recipe · New title"
	var bottom := 0.0
	var single_height := 0.0
	for i in 3:
		var c: UiRequestCard = _host(UiRequestCard.new(_request({"reward": short if i == 0 else long,
			"bonus_note": "Bonus resets in 23h 59m" if i == 2 else ""})))
		c.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		c.offset_left = 12
		c.offset_right = -12
		c.offset_top = -20
		c.offset_bottom = -20
		c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		for frame in 8: await get_tree().process_frame
		assert_float(c.size.x).is_equal(336.0)
		assert_str(c._reward.text).is_equal(short if i == 0 else "+5 Friendship · 90 coins · New recipe\nNew title")
		assert_int(c._reward.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_RIGHT)
		assert_str(str(c._reward.theme_type_variation)).is_equal(str(UiTokens.STYLE_C12_XB))
		var label := c.find_children("*", "Label", true, false).filter(func(l): return l.text == "Reward")[0] as Label
		var values := c._reward.get_parent() as Control
		assert_float(label.get_global_rect().get_center().y).is_equal_approx(values.get_global_rect().get_center().y, 1.0)
		for line in c._reward.text.split("\n"):
			var width := c._reward.get_theme_font(&"font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			assert_float(width).is_less_equal(c._reward.size.x)
		if i == 0:
			bottom = c.get_global_rect().end.y
			single_height = c.size.y
		else:
			assert_float(c.get_global_rect().end.y).is_equal(bottom)
			assert_float(c.size.y).is_greater(single_height)
		if i == 2:
			var note := c.find_children("*", "Label", true, false).filter(func(l): return l.text.begins_with("Bonus resets"))[0] as Label
			assert_str(str(note.theme_type_variation)).is_equal(str(UiTokens.STYLE_C11_B))
			assert_that(note.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)
			assert_int(note.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_RIGHT)
			assert_float(note.get_global_rect().position.y).is_greater_equal(c._reward.get_global_rect().end.y)
		# A wider host must unwrap the reward instead of retaining the old two-line height.
		c.get_parent().size.x = 440
		for frame in 8: await get_tree().process_frame
		assert_str(c._reward.text).is_equal(short if i == 0 else long)

func test_stored_stack_shows_the_house_badge() -> void:
	var g := UiInventoryGrid.new()
	g.custom_minimum_size = Vector2(336, 240)
	var it := _items(2)
	it[1]["stored"] = true
	g.items = it
	_host(g)
	await _settle()
	assert_bool(g.cells()[0]._home.visible).is_false()
	assert_bool(g.cells()[1]._home.visible).is_true()
	assert_vector(g.cells()[1]._home.position).is_equal(Vector2(4, 38))
	assert_bool(g.cells()[5]._home.visible).is_false()   # empty cells never

# ---------------------------------------------------------------- resident profile, notice row, float text

func test_drawer_pad_sets_the_sheet_inset() -> void:
	var d := _drawer(443)
	d.pad = UiTokens.SPACE_PAGE
	await _settle()
	assert_vector(d.body.position).is_equal(Vector2(16, 16))

func test_resident_profile_lists_identity_stage_friendship_and_likes() -> void:
	var p: UiResidentProfile = _host(UiResidentProfile.new({name = "Pip", role = "Courier Kid", stage = "Familiar",
		friendship = "52/90", likes = "Dessert"}))
	p.size = Vector2(328, 411)
	await _settle()
	var texts := p.find_children("*", "Label", true, false).filter(func(l): return l.is_visible_in_tree()).map(func(l): return l.text)
	for t in ["Pip", "Courier Kid", "Familiar", "Friendship", "52/90", "Favorite dishes", "Dessert"]:
		assert_bool(t in texts).override_failure_message("missing %s in %s" % [t, texts]).is_true()
	assert_bool(p.details_button().visible).is_false()   # no page behind Details in P0: never a dead end
	var back := [false]
	p.back_pressed.connect(func(): back[0] = true)
	var dismiss := p.find_children("*", "UiDismissButton", true, false)[0] as UiDismissButton
	assert_str(dismiss.text).is_equal("Back")
	dismiss.pressed.emit()
	assert_bool(back[0]).is_true()

## 225 验收 / 不知火舞: each stage has its tone, shared by the profile's StateBadge and the bar's stage pill; out of range
## reads as Stranger; the bar's meter fill and UiBadge's own default (Ready etc.) stay as they were.
const _TONES := [
	[UiTokens.COLOR_TILE_CORE, UiTokens.COLOR_SECONDARY],
	[UiTokens.COLOR_PRIMARY_TINT, UiTokens.COLOR_PRIMARY],
	[UiTokens.COLOR_ROLE_TACKLE_TINT, UiTokens.COLOR_ROLE_TACKLE],
	[UiTokens.COLOR_ROLE_MARKET_TINT, UiTokens.COLOR_ROLE_MARKET],
	[UiTokens.COLOR_GOLD, UiTokens.COLOR_TEXT],
]

func _fill(c: Control) -> Color:
	return (c.get_theme_stylebox(&"panel") as UiStyleBox).bg_color

func _ink(c: Node, text: String) -> Color:
	var l := c.find_children("*", "Label", true, false).filter(func(x): return x.text == text)[0] as Label
	return l.get_theme_color(&"font_color")

func test_each_affinity_stage_has_its_tone_on_the_profile_and_the_bar() -> void:
	var names := ["Stranger", "Acquainted", "Familiar", "Trusted", "Kindred"]
	for i in names.size():
		var p: UiResidentProfile = _host(UiResidentProfile.new({name = "Pip", stage = names[i], stage_index = i}))
		var b: UiResidentBar = _host(UiResidentBar.new(_pip({stage = names[i], stage_index = i})))
		await _settle()
		var badge := p.find_children("*", "UiBadge", true, false)[0] as UiBadge
		assert_object(_fill(badge)).is_equal(_TONES[i][0])
		assert_object(_ink(badge, names[i])).is_equal(_TONES[i][1])
		var label := b.find_children("*", "Label", true, false).filter(func(x): return x.text == names[i])[0] as Label
		assert_object(_fill(label.get_parent() as Control)).is_equal(_TONES[i][0])
		assert_object(label.get_theme_color(&"font_color")).is_equal(_TONES[i][1])
		assert_float(badge.size.y).is_equal(float(UiTokens.SIZE_STATE_BADGE_H))   # size as it was
		var box := badge.get_theme_stylebox(&"panel") as UiStyleBox
		var theme_box := UiKit.theme().get_stylebox(&"panel", UiTokens.PANEL_BADGE) as UiStyleBox
		assert_float(box.border_width).is_equal(0.0)   # no edge
		assert_object(box.corner_radius).is_equal(theme_box.corner_radius)   # the theme Badge's shape and padding
		assert_float(box.content_margin_left).is_equal(theme_box.content_margin_left)
		assert_float(box.content_margin_top).is_equal(theme_box.content_margin_top)
	assert_array(UiResidentBar.stage_tone(-1)).is_equal(_TONES[0])
	assert_array(UiResidentBar.stage_tone(9)).is_equal(_TONES[0])

func test_the_top_stage_writes_only_the_points_with_a_full_meter() -> void:
	var b: UiResidentBar = _host(UiResidentBar.new(_pip({stage = "Kindred", stage_index = 4, have = 157, need = 157, next = ""})))
	await _settle()
	assert_array(_texts(b)).contains(["Kindred", "157"])   # 李白 q(91): no denominator, no `· next`
	assert_bool(_texts(b).any(func(t): return "/" in t or "next" in t)).is_false()
	assert_float(b.progress()).is_equal(1.0)
	var mid: UiResidentBar = _host(UiResidentBar.new(_pip()))
	await _settle()
	assert_array(_texts(mid)).contains(["52/90 · next Trusted"])

func test_a_plain_state_badge_keeps_its_own_tone() -> void:
	var ready: UiBadge = _host(UiBadge.new("Ready"))
	await _settle()
	assert_object(_fill(ready)).is_equal(UiTokens.COLOR_PRIMARY_TINT)
	assert_object(_ink(ready, "Ready")).is_equal(UiTokens.COLOR_PRIMARY)

func test_notice_row_reads_one_line_with_a_chevron() -> void:
	var r: UiNoticeRow = _host(UiNoticeRow.new("Bag full · +5 slots at Homestead Lv3"))
	r.size = Vector2(336, 44)
	await _settle()
	assert_str(r.notice()).is_equal("Bag full · +5 slots at Homestead Lv3")
	assert_float(r.size.y).is_equal(44.0)

func test_float_text_affinity_has_the_heart_and_rose_ink() -> void:
	var f: UiFloatText = _host(UiFloatText.new("+2 · first chat today", UiFloatText.Tone.AFFINITY))
	await _settle()
	var label := f.find_children("*", "Label", true, false)[0] as Label
	assert_str(label.get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_FLOAT_AFFINITY.to_html())
	assert_bool((f.find_children("*", "TextureRect", true, false)[0] as TextureRect).visible).is_true()
	# laid out at the ×1.3 peak and shown at ×1.0
	assert_float(f.shown_size().x).is_equal_approx(f.size.x / 1.3, 0.01)
	assert_float(f.scale.x).is_equal_approx(1.0 / 1.3, 0.001)

func test_float_text_plays_bottom_centre_and_frees_itself() -> void:
	var f: UiFloatText = _host(UiFloatText.new("+5 XP", UiFloatText.Tone.XP))
	await _settle()
	var done := [false]
	f.finished.connect(func(): done[0] = true)
	f.play(Vector2(180, 400))
	assert_vector(f.position + f.pivot_offset).is_equal(Vector2(180, 400))
	assert_float(f.scale.x).is_equal_approx(0.5 / 1.3, 0.001)
	await get_tree().create_timer(1.25).timeout
	assert_bool(done[0]).is_true()
	assert_bool(is_instance_valid(f) and not f.is_queued_for_deletion()).is_false()

func test_float_text_stacks_and_caps_the_peak_width() -> void:
	var a: UiFloatText = _host(UiFloatText.new("+48 XP · 12 plants", UiFloatText.Tone.XP))
	var b: UiFloatText = _host(UiFloatText.new("−2 Energy", UiFloatText.Tone.ENERGY_COST))
	await _settle()
	a.play(Vector2(180, 400))
	b.play(Vector2(180, 400), 1)
	assert_float((a.position.y + a.pivot_offset.y) - (b.position.y + b.pivot_offset.y)).is_equal(28.0)
	var wide: UiFloatText = _host(UiFloatText.new("Granny Wu shared a meal with you and it was very good indeed · +20 Energy",
		UiFloatText.Tone.ENERGY_GAIN, null, UiFloatText.Layout.WRAP))
	await _settle()
	assert_float(wide.shown_size().x).is_less_equal(320.0 + 0.5)
	assert_float(wide.shown_size().x * wide._peak).is_less_equal(336.0 + 0.5)

## With bounds (the screen's side margins; 不知火舞 on #284, 289 46e61588) a wide pill from near a side moves in at rest
## and stays inside them through the pop: at ×0.5, ×1.0 and the peak, and its peak no wider than the span. Without
## bounds it grows from its bottom centre as before.
func test_float_text_stays_inside_its_bounds_through_the_pop() -> void:
	for at_x in [345.0, 15.0, 180.0]:
		var f: UiFloatText = _host(UiFloatText.new("River Perch ×1 · Common Carp ×1", UiFloatText.Tone.ITEM))
		f.bounds = Vector2(16, 344)
		await _settle()
		f.play(Vector2(at_x, 400))
		var w := f.shown_size().x
		for k in [0.5, 1.0, f._peak]:
			f.scale = Vector2.ONE * k / 1.3
			var left: float = f.position.x + f.pivot_offset.x * (1.0 - k / 1.3)
			assert_float(left).is_greater_equal(16.0 - 0.5)
			assert_float(left + f.size.x * k / 1.3).is_less_equal(344.0 + 0.5)
		f.scale = Vector2.ONE / 1.3   # at rest: pushed against a side, it sits on it
		var rest_left := f.position.x + f.pivot_offset.x * (1.0 - 1.0 / 1.3)
		if at_x > 300.0: assert_float(rest_left + w).is_equal_approx(344.0, 0.5)
		elif at_x < 50.0: assert_float(rest_left).is_equal_approx(16.0, 0.5)
		else: assert_float(rest_left + w * 0.5).is_equal_approx(180.0, 0.5)
		assert_float(w * f._peak).is_less_equal(328.0 + 0.5)
	var free: UiFloatText = _host(UiFloatText.new("River Perch ×1 · Common Carp ×1", UiFloatText.Tone.ITEM))
	await _settle()
	free.play(Vector2(345, 400))
	assert_float(free.pivot_offset.x).is_equal_approx(free.size.x * 0.5, 0.01)
	assert_vector(free.position + free.pivot_offset).is_equal(Vector2(345, 400))

func test_float_text_bump_updates_in_place() -> void:
	var f: UiFloatText = _host(UiFloatText.new("+12 XP", UiFloatText.Tone.XP))
	await _settle()
	f.play(Vector2(180, 400))
	await get_tree().create_timer(0.9).timeout
	f.bump("+24 XP · 2 plants")
	var y := f.position.y
	await get_tree().create_timer(0.5).timeout
	assert_bool(is_instance_valid(f)).is_true()   # the fade restarted 650 ms after the bump
	assert_float(f.position.y).is_equal(y)        # it holds its height
	assert_str((f.find_children("*", "Label", true, false)[0] as Label).text).is_equal("+24 XP · 2 plants")

func test_float_text_static_pill_is_the_same_look_at_one_x() -> void:
	var p: PanelContainer = _host(UiFloatText.pill("+20 Cooking XP", UiFloatText.Tone.XP))
	await _settle()
	var label := p.find_children("*", "Label", true, false)[0] as Label
	assert_str(label.text).is_equal("+20 Cooking XP")
	assert_str(label.get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_FLOAT_XP.to_html())
	assert_int(label.get_theme_font_size(&"font_size")).is_equal(15)
	assert_float((p.get_theme_stylebox(&"panel") as UiStyleBox).content_margin_left).is_equal(8.0)

# ---------------------------------------------------------------- a lifted bag cell keeps its drag (225 / BAR-DRAG-9)

func test_inventory_cell_lifted_keeps_the_default_look_under_the_lift_shadow() -> void:
	var c: UiItemCell = auto_free(UiItemCell.new(UiItemCell.Density.INVENTORY))
	add_child(c)
	c.state = UiItemCell.State.LIFTED
	assert_int(c.drawn_state()).is_equal(UiItemCell.State.LIFTED)
	var box := c._surface.get_theme_stylebox(&"panel") as UiStyleBox
	assert_str(box.border_color.to_html()).is_equal(UiTokens.COLOR_BORDER.to_html())
	assert_str(box.shadow_color.to_html()).is_equal(UiTokens.COLOR_LIFT_SHADOW.to_html())
	var k: UiItemCell = auto_free(UiItemCell.new(UiItemCell.Density.KITCHEN))
	k.state = UiItemCell.State.LIFTED
	assert_int(k.drawn_state()).is_equal(UiItemCell.State.DEFAULT)

## A phone sends the touch and its emulated mouse twin; the scroll drags on the mouse, the cell reads the touch.
func _touch_and_mouse(at: Vector2, down: bool) -> void:
	var t := InputEventScreenTouch.new()
	t.position = at
	t.pressed = down
	get_viewport().push_input(t, true)
	_mouse(at, down)

func _drag_and_motion(at: Vector2, rel: Vector2) -> void:
	var d := InputEventScreenDrag.new()
	d.position = at
	d.relative = rel
	get_viewport().push_input(d, true)
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	m.relative = rel
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(m, true)

func test_a_lifted_cell_in_a_scroll_keeps_the_drag_from_the_scroll() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var emulate := Input.emulate_touch_from_mouse
	Input.emulate_touch_from_mouse = true   # as on a phone: the scroll container drags on the (emulated) mouse
	var scroll := TouchScrollContainer.new()
	scroll.position = Vector2(20, 100)
	scroll.size = Vector2(300, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(auto_free(scroll))
	var col := VBoxContainer.new()
	scroll.add_child(col)
	var cell := UiItemCell.new(UiItemCell.Density.INVENTORY)
	var now := [0]
	cell.clock = func() -> int: return now[0]
	col.add_child(cell)
	var filler := Control.new()
	filler.custom_minimum_size = Vector2(10, 600)
	col.add_child(filler)
	for i in 3: await get_tree().process_frame
	var kinds := []
	cell.gesture.connect(func(o: Dictionary): kinds.append(o.kind))
	var at := cell.get_global_rect().get_center()
	_touch_and_mouse(at, true)
	now[0] = GestureArbiter.LONG_PRESS_MS + 20
	await get_tree().process_frame
	await get_tree().process_frame
	assert_array(kinds).contains([&"lift"])
	for step in 6:
		_drag_and_motion(at + Vector2(0, 20.0 * (step + 1)), Vector2(0, 20))
		await get_tree().process_frame
	_touch_and_mouse(at + Vector2(0, 120), false)
	await get_tree().process_frame
	Input.emulate_touch_from_mouse = emulate
	assert_int(scroll.scroll_vertical).is_equal(0)   # the grid did not scroll under the lifted cell
	assert_array(kinds).contains([&"drag_start", &"drop"])
