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
	c.place = "Rods and bait · Shanghai Tackle Shop"
	await _settle()
	assert_array(_texts(c)).contains(["Tackle Keeper · Finn", "Rods and bait · Shanghai Tackle Shop", "Pick a rod, I'll string it."])
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
	assert_str(h.sort_button().label).is_equal("Sort · Recent")
	assert_bool(h.sort_button().visible).is_true()
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
	for case in [[&"default", ["Unfollow", "Block", "Report"]], [&"close_friend", ["Remove Close Friend", "Unfollow", "Block", "Report"]],
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
