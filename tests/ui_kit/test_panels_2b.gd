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

## Press at `from`, move to `to`, release there after `ms` on the drawer's fake clock `now`.
func _drag(d: UiDrawer, from: Vector2, to: Vector2, now: Array, ms := 600) -> void:
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.pressed = true
	p.position = from
	d._gui_input(p)
	var m := InputEventMouseMotion.new()
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	m.position = to
	d._gui_input(m)
	now[0] += ms
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.pressed = false
	r.position = to
	d._gui_input(r)

func test_drawer_swipe_down_48_closes_and_short_or_sideways_drags_do_not() -> void:
	if DisplayServer.is_touchscreen_available(): return   # synthetic mouse input below
	var d := _drawer()
	await _settle()
	var now := [0]
	d.clock = func() -> int: return now[0]
	var closes := [0]
	d.close_requested.connect(func(): closes[0] += 1)
	_drag(d, Vector2(100, 10), Vector2(100, 40), now)       # 30 px, slow: stays
	_drag(d, Vector2(100, 10), Vector2(160, 70), now, 50)   # diagonal, even fast: stays
	assert_int(closes[0]).is_equal(0)
	_drag(d, Vector2(100, 10), Vector2(104, 60), now)       # 50 px down: closes once
	assert_int(closes[0]).is_equal(1)

func test_drawer_quick_flick_closes() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var d := _drawer()
	await _settle()
	var now := [0]
	d.clock = func() -> int: return now[0]
	var closes := [0]
	d.close_requested.connect(func(): closes[0] += 1)
	var p := InputEventMouseButton.new()
	p.button_index = MOUSE_BUTTON_LEFT
	p.pressed = true
	p.position = Vector2(100, 10)
	d._gui_input(p)
	now[0] = 100
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.position = Vector2(100, 30)
	d._gui_input(r)
	assert_int(closes[0]).is_equal(1)

# Real viewport input: header content passes the swipe on, the grid and KEEP_INPUT subtrees keep theirs.

func _mouse(at: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	get_viewport().push_input(e, true)

func _swipe(from: Vector2, by: Vector2, steps := 8) -> void:
	_mouse(from, true)
	for i in steps:
		var m := InputEventMouseMotion.new()
		m.position = from + by * float(i + 1) / steps
		m.global_position = m.position
		m.relative = by / steps
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(m, true)
		await get_tree().process_frame
	_mouse(from + by, false)
	await get_tree().process_frame

## A drawer like the Bag: a tab row on top, a scrolling grid, a kept row (the docked quick bar) at the bottom.
func _bag_like() -> Dictionary:
	var d := UiDrawer.new(500.0)
	d.animate = false
	var early := Button.new()   # built before the drawer enters the tree, as P0BagDrawer does
	early.custom_minimum_size = Vector2(120, 34)
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
	cell.custom_minimum_size = Vector2(100, 400)
	grid.add_child(cell)
	var kept := PanelContainer.new()
	kept.set_meta(UiDrawer.KEEP_INPUT, true)
	var slot := Button.new()
	slot.custom_minimum_size = Vector2(60, 44)
	kept.add_child(slot)
	d.body.add_child(kept)
	return {drawer = d, early = early, tab = tab, cell = cell, slot = slot}

func _count(sig: Signal) -> Array:
	var n := [0]
	sig.connect(func(): n[0] += 1)
	return n

func test_drawer_swipe_from_a_header_tab_closes_without_firing_the_tab() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var p := _bag_like()
	await _settle()
	var d: UiDrawer = p.drawer
	assert_int(p.early.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	assert_int(p.tab.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	var closes := _count(d.close_requested)
	var taps := _count(p.tab.pressed)
	await _swipe(p.tab.get_global_rect().get_center(), Vector2(0, 60))
	assert_int(closes[0]).is_equal(1)
	assert_int(taps[0]).is_zero()

func test_drawer_tap_on_a_header_tab_still_taps_and_does_not_close() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var p := _bag_like()
	await _settle()
	var closes := _count(p.drawer.close_requested)
	var taps := _count(p.tab.pressed)
	var at: Vector2 = p.tab.get_global_rect().get_center()
	_mouse(at, true)
	await get_tree().process_frame
	_mouse(at, false)
	await get_tree().process_frame
	assert_int(taps[0]).is_equal(1)
	assert_int(closes[0]).is_zero()

func test_drawer_flick_from_a_tab_closes_and_eats_the_release() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var p := _bag_like()
	await _settle()
	var d: UiDrawer = p.drawer
	var now := [0]
	d.clock = func() -> int: return now[0]
	var closes := _count(d.close_requested)
	var taps := _count(p.tab.pressed)
	var at: Vector2 = p.tab.get_global_rect().get_center()
	_mouse(at, true)
	await get_tree().process_frame
	now[0] = 100
	_mouse(at + Vector2(0, 20), false)   # 20 px within 100 ms: the release still lands on the tab
	await get_tree().process_frame
	assert_int(closes[0]).is_equal(1)
	assert_int(taps[0]).is_zero()

func test_drawer_swipe_that_ends_on_the_same_tall_row_does_not_fire_it() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var d := _drawer(500.0)
	var row := Button.new()   # a gear row or notice taller than the swipe
	row.custom_minimum_size = Vector2(300, 120)
	d.body.add_child(row)
	await _settle()
	var closes := _count(d.close_requested)
	var taps := _count(row.pressed)
	var top := row.get_global_rect().position + Vector2(150, 10)
	await _swipe(top, Vector2(0, 60))   # closes on the way; the release is still inside the row
	assert_bool(row.get_global_rect().has_point(top + Vector2(0, 60))).is_true()
	assert_int(closes[0]).is_equal(1)
	assert_int(taps[0]).is_zero()

func test_drawer_grid_and_kept_rows_keep_their_drags() -> void:
	if DisplayServer.is_touchscreen_available(): return
	var p := _bag_like()
	await _settle()
	var closes := _count(p.drawer.close_requested)
	await _swipe(p.cell.get_global_rect().get_center(), Vector2(0, 60))
	assert_int(p.slot.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)   # untouched
	await _swipe(p.slot.get_global_rect().get_center(), Vector2(0, 60))
	assert_int(closes[0]).is_zero()

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

func test_grid_has_five_columns_on_the_quick_bar_pitch_and_58_row_pitch() -> void:
	var g := _grid(7)
	await _settle()
	var cells := g.cells()
	for i in UiInventoryGrid.COLUMNS:
		assert_float(cells[i].position.x).is_equal(float(i * (UiTokens.SIZE_INVENTORY_CELL + UiTokens.SPACE_QUICK_BAR_GAP)))
	assert_float(cells[5].position.y - cells[0].position.y).is_equal(58.0)
	assert_vector(cells[0].size).is_equal(Vector2(UiTokens.SIZE_INVENTORY_CELL, UiTokens.SIZE_INVENTORY_CELL))

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

func test_kitchen_density_draws_kitchen_cells_with_status_and_mark() -> void:
	var g := UiInventoryGrid.new()
	g.custom_minimum_size = Vector2(336, 240)
	g.density = UiItemCell.Density.KITCHEN
	var it := _items(2)
	it[0]["status"] = "In pot"
	it[1]["status"] = "Not for cooking"
	it[1]["marked"] = true
	g.items = it
	_host(g)
	await _settle()
	var c0 := g.cells()[0]
	assert_int(c0.density).is_equal(UiItemCell.Density.KITCHEN)
	assert_vector(c0.size).is_equal(Vector2(UiTokens.SIZE_KITCHEN_CELL_W, UiTokens.SIZE_KITCHEN_CELL_H))
	assert_str(c0.status).is_equal("In pot")
	assert_bool(g.cells()[1].marked).is_true()
	assert_float(g.cells()[5].position.y - c0.position.y).is_equal(float(UiTokens.SIZE_KITCHEN_CELL_H) + 6.0)

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
	c.place = "Rods and bait · Xuhui Tackle Shop"
	await _settle()
	assert_array(_texts(c)).contains(["Tackle Keeper · Finn", "Rods and bait · Xuhui Tackle Shop", "Pick a rod, I'll string it."])
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

# ---------------------------------------------------------------- UiBagHeader / UiGearRow

func test_bag_header_count_sort_and_capacity_bar() -> void:
	var h: UiBagHeader = _host(UiBagHeader.new(19, 25))
	await _settle()
	assert_array(_texts(h)).contains(["Bag 19/25"])
	assert_str(h.sort_button().label).is_equal("Sort · Type")
	assert_str(h.sort_button().text).is_equal("Sort · Type")   # a toggle, so no ›
	assert_str(h.sort_button().get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_INFO.to_html())
	assert_bool(h.sort_button().visible).is_true()
	assert_float(h.tabs().size.y).is_equal(34.0)   # SegmentedTabs track 34, segments 28
	assert_float(h.tabs().tabs()[0].size.y).is_equal(28.0)
	assert_bool(h.is_nearly_full()).is_false()
	h.used = 23   # 92 %: amber (§10.4.1)
	assert_bool(h.is_nearly_full()).is_true()
	var got := []
	h.side_changed.connect(func(s: int): got.append(s))
	h.tabs().tabs()[1].pressed.emit()
	h.tabs().tabs()[1].button_pressed = true
	assert_array(got).contains([1])
	assert_bool(h.sort_button().visible).is_false()   # Sort is a Bag-side control
	h.side = UiBagHeader.Pane.BAG
	h.show_tabs = false                               # the gift drawer: just the count
	assert_bool(h.tabs().visible).is_false()
	assert_bool(h.sort_button().visible).is_false()
	assert_bool(h._title.visible).is_true()

func test_gear_row_states() -> void:
	var rod := load("res://assets/p0/icons/rod_starter.svg")
	var eq: UiGearRow = _host(UiGearRow.new({icon = rod, title = "Starter Rod", state = &"equipped", effect = "Lands up to Fine fish"}))
	var owned: UiGearRow = _host(UiGearRow.new({icon = rod, title = "Reed Rod", state = &"owned", effect = "Lands up to Rare fish",
		action = {id = &"equip", label = "Equip", kind = &"secondary"}}))
	var locked: UiGearRow = _host(UiGearRow.new({icon = rod, title = "Carbon Rod", state = &"Fishing Lv5 · Tackle Shop", effect = "Lands up to Legendary fish"}))
	await _settle()
	assert_array(_texts(eq)).contains(["✓ Equipped"])
	assert_object(eq.action_button()).is_null()
	assert_array(_texts(owned)).contains(["Owned"])
	var got := []
	owned.action_pressed.connect(func(a: StringName): got.append(a))
	owned.action_button().activated.emit()
	assert_array(got).is_equal([&"equip"])
	assert_array(_texts(locked)).contains(["Fishing Lv5 · Tackle Shop"])
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
	var f: UiFarmCard = _host(UiFarmCard.new("Farmer's Homestead", "Level 1", "Radishes ready 3h 32m", load("res://assets/p0/art/homestead-thumb.jpg")))
	await _settle()
	assert_array(_texts(f)).contains(["Farmer's Homestead", "Level 1", "Radishes ready 3h 32m"])
	f.status = ""
	assert_array(_texts(f)).not_contains(["Radishes ready 3h 32m"])
	assert_float(f.size.y).is_equal(76.0)

func _request(fields := {}) -> Dictionary:
	var d := {portrait = PIP, title = "Pip's request", who = "Pip · Courier Kid · personal request",
		line = "Could you catch me a fish? Any kind is fine.", needs = [{name = "Common fish", have = 0, need = 1,
		icon = load("res://assets/p0/icons/fish_crucian.svg")}], reward = "+5 Friendship · 20 coins", deliver_to = "Pip · Travel Post"}
	d.merge(fields, true)
	return d

func test_request_card_reads_the_request_and_offers_accept_or_not_now() -> void:
	var c: UiRequestCard = _host(UiRequestCard.new(_request()))
	await _settle()
	assert_array(_texts(c)).contains(["Pip's request", "Pip · Courier Kid · personal request", "Could you catch me a fish? Any kind is fine.",
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
	for t in ["Pip", "Courier Kid", "Familiar", "Friendship", "52/90", "Favourite dishes", "Dessert"]:
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
