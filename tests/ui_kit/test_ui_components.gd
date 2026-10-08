extends GdUnitTestSuite
## Behaviour of the SGODOT-212 atomic components. Layout is covered by the gallery snapshots
## (test_gallery_snapshot.gd); this suite checks states, signals and hit areas.

func _host(c: Control) -> Control:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	add_child(auto_free(host))
	host.add_child(c)
	return c

func _settle() -> void:
	for i in 2: await get_tree().process_frame

func _quick(fields: Dictionary = {}) -> UiItemCell:
	var c := UiItemCell.new(UiItemCell.Density.QUICK)
	c.icon = load("res://assets/p0/icons/seed_radish.svg")
	c.title = "Radish Seeds"
	c.quantity = "×24"
	for k in fields: c.set(k, fields[k])
	return _host(c)

func _surface(c: UiItemCell) -> Panel: return c.get_child(0)

func _visible_named(c: Control, cls: String) -> Array:
	return c.find_children("*", cls, true, false).filter(func(n): return n.is_visible_in_tree())

# ---------------------------------------------------------------- UiItemCell

func test_item_cell_sizes_follow_the_density_tokens() -> void:
	var expect := {
		UiItemCell.Density.INVENTORY: Vector2(UiTokens.SIZE_INVENTORY_CELL, UiTokens.SIZE_INVENTORY_CELL),
		UiItemCell.Density.QUICK: Vector2(UiTokens.SIZE_QUICK_SLOT_W, UiTokens.SIZE_QUICK_SLOT_H),
		UiItemCell.Density.KITCHEN: Vector2(UiTokens.SIZE_KITCHEN_CELL_W, UiTokens.SIZE_KITCHEN_CELL_H),
		UiItemCell.Density.GEAR: Vector2(UiTokens.SIZE_GEAR_SLOT_W, UiTokens.SIZE_GEAR_SLOT_H),
	}
	var cells := {}
	for d in expect: cells[d] = _host(UiItemCell.new(d))
	await _settle()
	for d in expect:
		assert_vector((cells[d] as Control).size).is_equal(expect[d])
		assert_bool((cells[d] as Control).size.x >= UiTokens.SIZE_TOUCH and (cells[d] as Control).size.y >= UiTokens.SIZE_TOUCH).is_true()

func test_quick_slot_lifts_when_selected_and_more_when_lifted() -> void:
	var c := _quick()
	await _settle()
	var rest := UiTokens.SIZE_QUICK_SLOT_H - UiTokens.SIZE_QUICK_SLOT_SURFACE_H
	assert_float(_surface(c).position.y).is_equal(float(rest))
	assert_float(_surface(c).size.y).is_equal(float(UiTokens.SIZE_QUICK_SLOT_SURFACE_H))
	c.state = UiItemCell.State.SELECTED
	await _settle()
	assert_float(_surface(c).position.y).is_equal(float(rest - UiTokens.SIZE_QUICK_SLOT_LIFT))
	c.state = UiItemCell.State.LIFTED
	await _settle()
	assert_float(_surface(c).position.y).is_equal(float(rest - UiTokens.SIZE_QUICK_SLOT_LIFT_DRAG))
	assert_float((_surface(c).get_theme_stylebox(&"panel") as UiStyleBox).shadow_size).is_greater(0.0)

func test_quick_slot_shows_only_icon_name_and_quantity() -> void:
	# LOCK-04: no Energy price, no scene chip inside the slot.
	var c := _quick()
	await _settle()
	var texts := _visible_named(c, "Label").map(func(l): return (l as Label).text)
	assert_array(texts).contains_exactly_in_any_order(["Radish Seeds", "×24"])
	assert_int(_visible_named(c, "TextureRect").size()).is_equal(1)

func test_pin_adds_warm_fill_strip_and_badge_and_stacks_with_selected() -> void:
	# LOCK-05: amber pin badge over the top centre, amber strip inside the top edge, warm fill;
	# selected keeps its green outline outside the strip.
	var c := _quick({pinned = true, state = UiItemCell.State.SELECTED})
	await _settle()
	var box := _surface(c).get_theme_stylebox(&"panel") as UiStyleBox
	assert_str(box.bg_color.to_html()).is_equal(UiTokens.COLOR_PIN_WARM.to_html())
	assert_str(box.border_color.to_html()).is_equal(UiTokens.COLOR_PRIMARY.to_html())
	var amber := _visible_named(c, "Panel").filter(func(p):
		var b := (p as Panel).get_theme_stylebox(&"panel") as UiStyleBox
		return b != null and b.bg_color.to_html() == UiTokens.COLOR_PIN_AMBER.to_html())
	assert_int(amber.size()).is_equal(2)   # strip + badge
	var strip: Panel = amber.filter(func(p): return (p as Panel).size.y == UiTokens.SIZE_PIN_STRIP_H)[0]
	assert_float(strip.position.y).is_equal(box.border_width)   # inside the 2 px outline
	var badge: Panel = amber.filter(func(p): return (p as Panel).size.x == UiTokens.SIZE_PIN_BADGE)[0]
	assert_float(badge.get_global_rect().get_center().x).is_equal_approx(c.get_global_rect().get_center().x, 0.01)
	assert_float(badge.get_global_rect().get_center().y).is_equal_approx(_surface(c).get_global_rect().position.y, 0.01)

func test_empty_quick_slot_draws_nothing_but_the_dashed_outline() -> void:
	var c := _quick({pinned = true, state = UiItemCell.State.EMPTY})
	await _settle()
	assert_array(_visible_named(c, "Label")).is_empty()
	assert_array(_visible_named(c, "TextureRect")).is_empty()
	var box := _surface(c).get_theme_stylebox(&"panel") as UiStyleBox
	assert_bool(box.dashed).is_true()
	assert_float(box.dash).is_equal(float(UiTokens.DASH_QUICK[0]))

func test_zero_quick_slot_dims_the_icon_and_greys_the_count() -> void:
	var c := _quick({pinned = true, state = UiItemCell.State.ZERO, quantity = "×0"})
	await _settle()
	var icon: TextureRect = _visible_named(c, "TextureRect").filter(func(t): return (t as TextureRect).texture != UiItemCell.PIN_GLYPH)[0]
	assert_float(icon.modulate.a).is_equal_approx(UiTokens.OPACITY_ZERO_ICON, 0.001)
	var count: Label = _visible_named(c, "Label").filter(func(l): return (l as Label).text == "×0")[0]
	assert_str(count.get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_SECONDARY.to_html())

func test_ghost_quick_slot_is_dashed_with_a_dimmed_icon_and_a_grey_family_name() -> void:
	var c := _quick({state = UiItemCell.State.GHOST, title = "Seeds", quantity = "×5", pinned = true})
	await _settle()
	var icon: TextureRect = _visible_named(c, "TextureRect").filter(func(t): return (t as TextureRect).texture != UiItemCell.PIN_GLYPH)[0]
	assert_float(icon.modulate.a).is_equal_approx(UiTokens.OPACITY_ZERO_ICON, 0.001)
	var labels := _visible_named(c, "Label")
	assert_array(labels.map(func(l): return (l as Label).text)).contains_exactly(["Seeds"])   # no count
	assert_str((labels[0] as Label).get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_SECONDARY.to_html())
	assert_bool(_visible_named(c, "TextureRect").any(func(t): return (t as TextureRect).texture == UiItemCell.PIN_GLYPH)).is_false()
	var box := _surface(c).get_theme_stylebox(&"panel") as UiStyleBox
	assert_bool(box.dashed).is_true()
	assert_float(box.dash).is_equal(float(UiTokens.DASH_QUICK[0]))

func test_quick_only_states_fall_back_to_default_on_other_mains() -> void:
	for d in [UiItemCell.Density.INVENTORY, UiItemCell.Density.KITCHEN, UiItemCell.Density.GEAR]:
		var c: UiItemCell = auto_free(UiItemCell.new(d))
		for s in [UiItemCell.State.LIFTED, UiItemCell.State.DROP_TARGET, UiItemCell.State.ZERO]:
			c.state = s
			assert_int(c.drawn_state()).is_equal(UiItemCell.State.DEFAULT)
		c.state = UiItemCell.State.GHOST
		assert_int(c.drawn_state()).is_equal(UiItemCell.State.EMPTY)

func test_inventory_cell_quantity_pill_and_rarity_dot() -> void:
	var c: UiItemCell = _host(UiItemCell.new(UiItemCell.Density.INVENTORY))
	c.icon = load("res://assets/p0/icons/fish_trout.svg")
	await _settle()
	assert_int(_visible_named(c, "Label").size()).is_equal(0)
	c.quantity = "×3"
	c.rarity = 3
	await _settle()
	var dots := _visible_named(c, "Panel").filter(func(p): return (p as Panel).size.x == UiTokens.SIZE_RARITY_DOT)
	assert_int(dots.size()).is_equal(1)
	assert_str(((dots[0] as Panel).get_theme_stylebox(&"panel") as UiStyleBox).bg_color.to_html()).is_equal(UiTokens.COLOR_RARITY_RARE.to_html())
	c.state = UiItemCell.State.EMPTY
	await _settle()
	assert_array(_visible_named(c, "Label")).is_empty()
	assert_array(_visible_named(c, "TextureRect")).is_empty()

func test_kitchen_mark_shows_when_selected_or_cooked() -> void:
	var c: UiItemCell = _host(UiItemCell.new(UiItemCell.Density.KITCHEN))
	c.icon = load("res://assets/p0/icons/dish_fish_soup.svg")
	await _settle()
	var mark := func() -> bool:
		return _visible_named(c, "TextureRect").any(func(t): return (t as TextureRect).texture == UiItemCell.CHECK_GLYPH)
	assert_bool(mark.call()).is_false()
	c.state = UiItemCell.State.SELECTED
	await _settle()
	assert_bool(mark.call()).is_true()
	c.state = UiItemCell.State.DEFAULT
	c.marked = true
	await _settle()
	assert_bool(mark.call()).is_true()
	c.state = UiItemCell.State.EMPTY
	await _settle()
	assert_bool(mark.call()).is_false()

# Touches fed straight into a cell with a fake clock (SGODOT-212 review: a touch is exactly one outcome).
func _record(c: UiItemCell) -> Dictionary:
	var rec := {taps = 0, gestures = [], now = 0}
	c.clock = func() -> int: return rec.now
	c.tapped.connect(func(): rec.taps += 1)
	c.gesture.connect(func(g: Dictionary): rec.gestures.append(String(g.kind)))
	return rec

func _touch(c: UiItemCell, rec: Dictionary, at_ms: int, pos: Vector2, down: bool) -> void:
	rec.now = at_ms
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.pressed = down
	c._gui_input(e)

func _drag(c: UiItemCell, rec: Dictionary, at_ms: int, pos: Vector2) -> void:
	rec.now = at_ms
	var e := InputEventScreenDrag.new()
	e.position = pos
	c._gui_input(e)

func _hold(c: UiItemCell, rec: Dictionary, at_ms: int) -> void:
	rec.now = at_ms
	c._process(0.0)

func test_short_press_taps_once() -> void:
	for d in [UiItemCell.Density.QUICK, UiItemCell.Density.INVENTORY]:
		var c: UiItemCell = _host(UiItemCell.new(d))
		var rec := _record(c)
		_touch(c, rec, 0, Vector2(26, 30), true)
		_hold(c, rec, 100)
		_touch(c, rec, 120, Vector2(28, 31), false)
		assert_int(rec.taps).is_equal(1)
		assert_array(rec.gestures).is_empty()

func test_long_press_pins_without_a_tap() -> void:
	# LOCK-05 (quick slot: release after the lift toggles the pin) and LOCK-12 (bag cell: long press).
	var expect := {UiItemCell.Density.QUICK: "pin_toggle", UiItemCell.Density.INVENTORY: "long_press"}
	for d in expect:
		var c: UiItemCell = _host(UiItemCell.new(d))
		var rec := _record(c)
		_touch(c, rec, 0, Vector2(26, 30), true)
		_hold(c, rec, GestureArbiter.LONG_PRESS_MS + 150)
		_touch(c, rec, GestureArbiter.LONG_PRESS_MS + 150, Vector2(26, 30), false)
		assert_int(rec.taps).is_equal(0)
		assert_array(rec.gestures).is_equal(["lift", expect[d]])

func test_swipe_up_in_a_quick_slot_opens_the_bag_without_a_tap() -> void:
	var c: UiItemCell = _host(UiItemCell.new(UiItemCell.Density.QUICK))
	var rec := _record(c)
	_touch(c, rec, 0, Vector2(26, 50), true)
	_drag(c, rec, 40, Vector2(27, 35))
	_drag(c, rec, 80, Vector2(27, 20))
	_touch(c, rec, 100, Vector2(27, 20), false)
	assert_int(rec.taps).is_equal(0)
	assert_array(rec.gestures).is_equal(["swipe_up"])

func test_gesture_positions_are_global() -> void:
	var box := MarginContainer.new()
	box.add_theme_constant_override(&"margin_left", 40)
	box.add_theme_constant_override(&"margin_top", 30)
	_host(box)
	var c := UiItemCell.new(UiItemCell.Density.QUICK)
	box.add_child(c)
	await _settle()
	var seen := []
	var now := [0]
	c.clock = func() -> int: return now[0]
	c.gesture.connect(func(g: Dictionary): seen.append(g))
	var e := InputEventScreenTouch.new()
	e.position = Vector2(10, 12)
	e.pressed = true
	c._gui_input(e)
	now[0] = GestureArbiter.LONG_PRESS_MS
	c._process(0.0)
	assert_vector(seen[0].pos).is_equal(c.get_global_rect().position + Vector2(10, 12))

func test_vertical_drag_in_a_touch_scroll_is_not_a_tap() -> void:
	# Real GUI routing: events pushed into the viewport reach the cell inside a TouchScrollContainer.
	var scroll := TouchScrollContainer.new()
	scroll.custom_minimum_size = Vector2(360, 120)
	# On the top canvas layer: an earlier suite can leave a scene in the tree (tests/scenes leaks a MapPoc whose
	# HUD would take the press), and this case needs the real GUI routing.
	var top := CanvasLayer.new()
	top.layer = 128
	add_child(auto_free(top))
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	top.add_child(host)
	host.add_child(scroll)
	var col := VBoxContainer.new()
	scroll.add_child(col)
	var cells: Array[UiItemCell] = []
	for i in 6:
		var c := UiItemCell.new(UiItemCell.Density.INVENTORY)
		col.add_child(c)
		cells.append(c)
	await _settle()
	var c := cells[1]   # not the first cell: a window-coordinate mix-up would land on another one
	assert_int(c.mouse_filter).is_equal(Control.MOUSE_FILTER_PASS)
	var taps := [0]
	var kinds := []
	c.tapped.connect(func(): taps[0] += 1)
	c.gesture.connect(func(g: Dictionary): kinds.append(String(g.kind)))
	var at := c.get_global_rect().get_center()
	# Control: a still press and release is one tap.
	_push(_press(at, true))
	_push(_press(at, false))
	await _settle()
	assert_int(taps[0]).is_equal(1)
	# A vertical drag that starts on the cell belongs to the scroll container.
	_push(_press(at, true))
	for step in range(1, 5): _push(_motion(at + Vector2(0, -10 * step)))
	_push(_press(at + Vector2(0, -40), false))
	await _settle()
	assert_int(taps[0]).is_equal(1)
	assert_array(kinds).contains(["cancel"])

## Viewport coordinates: the test window is 720×1280 over a 360×640 viewport, so window coordinates would be halved.
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

func _motion(pos: Vector2) -> InputEvent:
	if DisplayServer.is_touchscreen_available():
		var t := InputEventScreenDrag.new()
		t.position = pos
		return t
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	return m

# ---------------------------------------------------------------- UiCommandButton

func _signals(b: UiCommandButton) -> Array:
	var seen := []
	b.activated.connect(func(): seen.append("activated"))
	b.unavailable_pressed.connect(func(r): seen.append("unavailable:" + r))
	return seen

func test_command_activates_only_when_available_and_idle() -> void:
	var b: UiCommandButton = _host(UiCommandButton.new("Craft"))
	var seen := _signals(b)
	b.pressed.emit()
	assert_array(seen).is_equal(["activated"])
	assert_str(String(b.theme_type_variation)).is_equal(String(UiTokens.BUTTON_CMD_PRIMARY))

func test_unavailable_command_shows_the_reason_and_stays_tappable() -> void:
	# LOCK-10: the gap is written on the button; Figma Kind=unavailable is still tappable (short toast).
	var b: UiCommandButton = _host(UiCommandButton.new("Craft"))
	var seen := _signals(b)
	b.reason = "Need 6 more Timber"
	assert_str(b.text).is_equal("Need 6 more Timber")
	assert_str(String(b.theme_type_variation)).is_equal(String(UiTokens.BUTTON_CMD_BLOCKED))
	assert_bool(b.disabled).is_false()
	b.pressed.emit()
	assert_array(seen).is_equal(["unavailable:Need 6 more Timber"])
	b.reason = ""
	assert_str(b.text).is_equal("Craft")

func test_command_in_flight_ignores_repeats_and_dims_only_when_pending() -> void:
	var b: UiCommandButton = _host(UiCommandButton.new("Buy"))
	var seen := _signals(b)
	b.phase = CommandLifecycle.State.SUBMITTING
	b.pressed.emit()
	assert_float(b.modulate.a).is_equal(1.0)
	b.phase = CommandLifecycle.State.PENDING
	b.pressed.emit()
	assert_float(b.modulate.a).is_equal_approx(UiTokens.OPACITY_PENDING, 0.001)
	assert_str(b.text).is_equal("Buy")
	assert_array(seen).is_empty()
	b.phase = CommandLifecycle.State.IDLE
	assert_float(b.modulate.a).is_equal(1.0)

func test_command_follows_its_lifecycle_key() -> void:
	var lc: CommandLifecycle = auto_free(CommandLifecycle.new())
	var b: UiCommandButton = _host(UiCommandButton.new("Sell"))
	b.track(lc, "sell:radish")
	lc.start("sell:fish", 0)
	assert_int(b.phase).is_equal(CommandLifecycle.State.IDLE)
	lc.start("sell:radish", 0)
	assert_int(b.phase).is_equal(CommandLifecycle.State.SUBMITTING)
	lc.tick(UiTokens.MOTION_PENDING_DELAY_MS)
	assert_int(b.phase).is_equal(CommandLifecycle.State.PENDING)
	lc.settle("sell:radish")
	assert_int(b.phase).is_equal(CommandLifecycle.State.IDLE)

func test_compact_command_uses_compact_variations() -> void:
	var b: UiCommandButton = _host(UiCommandButton.new("Eat", UiCommandButton.Kind.SECONDARY, true))
	assert_str(String(b.theme_type_variation)).is_equal(String(UiTokens.BUTTON_CMD_SECONDARY_COMPACT))
	b.reason = "Sell at home"
	assert_str(String(b.theme_type_variation)).is_equal(String(UiTokens.BUTTON_CMD_BLOCKED_COMPACT))

# ---------------------------------------------------------------- hit areas and selection controls

func test_interactive_components_keep_a_44_hit_area() -> void:
	var controls: Array[Control] = [
		UiCommandButton.new("Eat", UiCommandButton.Kind.PRIMARY, true), UiCommandButton.new("Craft"),
		UiNavButton.new("Gift", true), UiNavButton.new("View details"), UiDismissButton.new(), UiCloseButton.new(),
		UiFilterChip.new("All"), UiSegmentTab.new(["Bag", "Gear"]),
	]
	var box := VBoxContainer.new()
	_host(box)
	for c in controls: box.add_child(c)
	await _settle()
	for b in box.find_children("*", "BaseButton", true, false):
		var size: Vector2 = (b as Control).size
		assert_bool(size.x >= UiTokens.SIZE_TOUCH and size.y >= UiTokens.SIZE_TOUCH) \
			.override_failure_message("%s is %s" % [b.get_class(), size]).is_true()

func test_segment_tab_keeps_exactly_one_selected() -> void:
	var seg: UiSegmentTab = _host(UiSegmentTab.new([{label = "Cookbook", count = "4/48"}, "Experiment"], 0))
	var picked := []
	seg.changed.connect(func(i): picked.append(i))
	seg.tabs()[1].button_pressed = true
	assert_array(picked).is_equal([1])
	assert_int(seg.selected).is_equal(1)
	assert_bool(seg.tabs()[0].button_pressed).is_false()
	var titles := seg.find_children("Title", "Label", true, false)
	assert_str((titles[1] as Label).get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_PRIMARY.to_html())
	assert_str((titles[0] as Label).get_theme_color(&"font_color").to_html()).is_equal(UiTokens.COLOR_SECONDARY.to_html())

func test_selecting_a_segment_in_code_releases_the_others_silently() -> void:
	# Reopening the bag on Gear and switching back to Bag in code must leave exactly one tab pressed.
	var seg: UiSegmentTab = _host(UiSegmentTab.new(["Bag", "Gear", "Inbox"], 0))
	var picked := []
	seg.changed.connect(func(i): picked.append(i))
	seg.selected = 2
	assert_array(seg.tabs().map(func(t): return (t as Button).button_pressed)).is_equal([false, false, true])
	seg.selected = 0
	assert_array(seg.tabs().map(func(t): return (t as Button).button_pressed)).is_equal([true, false, false])
	assert_array(picked).is_empty()

func test_segment_tab_selected_look_is_not_the_command_green() -> void:
	# LOCK-13: a mode switch never uses the primary command fill.
	var th := UiKit.theme()
	var selected := th.get_stylebox(&"pressed", UiTokens.BUTTON_SEGMENT_TAB) as UiStyleBox
	assert_str(selected.bg_color.to_html()).is_not_equal(UiTokens.COLOR_PRIMARY.to_html())

func test_filter_row_reports_the_picked_chip() -> void:
	var picked := []
	var row: HBoxContainer = _host(UiFilterChip.row(PackedStringArray(["All", "Seeds", "Fish"]), 0, func(i): picked.append(i)))
	(row.get_child(2) as UiFilterChip).button_pressed = true
	assert_array(picked).is_equal([2])
	assert_bool((row.get_child(0) as UiFilterChip).button_pressed).is_false()

# ---------------------------------------------------------------- display components

func test_object_header_and_item_row_hide_empty_fields() -> void:
	var h: UiObjectHeader = _host(UiObjectHeader.new({title = "Starter Rod"}))
	var r: UiItemRow = _host(UiItemRow.new({title = "Herb"}))
	await _settle()
	assert_array(_visible_named(h, "Label").map(func(l): return (l as Label).text)).is_equal(["Starter Rod"])
	assert_array(_visible_named(r, "Label").map(func(l): return (l as Label).text)).is_equal(["Herb"])
	h.quantity = "7"
	h.quantity_label = "fish"
	h.effect = "A simple pond fish."
	await _settle()
	assert_array(_visible_named(h, "Label").map(func(l): return (l as Label).text)).is_equal(["Starter Rod", "7", "fish", "A simple pond fish."])

func test_fact_and_cost_rows_use_their_value_styles() -> void:
	var fact := UiFactRow.new("Progress", "2/8")
	var cost := UiFactRow.new("Cost", "120 coins", UiFactRow.Kind.COST)
	assert_str(String((fact.find_children("*", "Label", true, false)[1] as Label).theme_type_variation)).is_equal(String(UiTokens.STYLE_BODY_XB14))
	assert_str(String((cost.find_children("*", "Label", true, false)[1] as Label).theme_type_variation)).is_equal(String(UiTokens.STYLE_ROW_TITLE_XB15))
	fact.free()
	cost.free()

func test_empty_state_navigation_row_is_optional() -> void:
	var e: UiEmptyState = _host(UiEmptyState.new("No fish yet"))
	var hits := []
	e.navigate.connect(func(): hits.append(true))
	await _settle()
	assert_array(_visible_named(e, "Button")).is_empty()
	e.action = "Show on map"
	await _settle()
	var nav: Array = _visible_named(e, "Button")
	assert_int(nav.size()).is_equal(1)
	(nav[0] as Button).pressed.emit()
	assert_array(hits).is_equal([true])

func test_empty_state_follows_the_panel_and_row_mains() -> void:
	# EmptyState 1234:87237: Panel = icon in a 56 grey disc + Bold 14 line; Row = 20 icon + Bold 13 line.
	var panel: UiEmptyState = _host(UiEmptyState.new("Your bag is empty", load("res://assets/p0/icons/bag.svg")))
	var row: UiEmptyState = _host(UiEmptyState.new("No open requests · next in 3h 12m", load("res://assets/p0/icons/board.svg"), "", UiEmptyState.Kind.ROW))
	await _settle()
	var disc: Panel = panel.find_children("*", "Panel", true, false)[0]
	assert_vector(disc.size).is_equal(Vector2(UiTokens.SIZE_EMPTY_DISC, UiTokens.SIZE_EMPTY_DISC))
	assert_str((disc.get_theme_stylebox(&"panel") as UiStyleBox).bg_color.to_html()).is_equal(UiTokens.COLOR_DISABLED.to_html())
	var icon: TextureRect = disc.get_child(0)
	assert_float(icon.size.x).is_equal(float(UiTokens.SIZE_EMPTY_ICON))
	assert_float(icon.modulate.a).is_equal_approx(UiTokens.OPACITY_EMPTY_ICON, 0.001)
	var line: Label = row.find_children("*", "Label", true, false)[0]
	assert_str(String(line.theme_type_variation)).is_equal(String(UiTokens.STYLE_C13_B))
	var row_icon: TextureRect = row.find_children("*", "TextureRect", true, false)[0]
	assert_float(row_icon.size.x).is_equal(float(UiTokens.SIZE_EMPTY_ROW_ICON))

func test_badge_hugs_its_text() -> void:
	var b: UiBadge = _host(UiBadge.new("Ready"))
	await _settle()
	assert_float(b.size.y).is_equal(float(UiTokens.SIZE_STATE_BADGE_H))
	assert_float(b.size.x).is_less((360.0 - UiTokens.SPACE_PAGE * 2.0) * 0.5)

func test_every_gallery_section_fits_the_328_column() -> void:
	# Registry contract (gallery_sections.gd): a wider section would widen the whole gallery column and
	# shift every layout snapshot.
	var column := 360.0 - UiTokens.SPACE_PAGE * 2.0   # 360 base width minus the gallery page margins
	for sec in UiKitGallerySections.all():
		var body: Control = _host(sec.build.call())
		var title := UiKit.label(sec.title, UiTokens.STYLE_ROW_TITLE_XB15)
		_host(title)
		await _settle()
		assert_float(body.get_combined_minimum_size().x).override_failure_message("%s body" % sec.id).is_less_equal(column)
		assert_float(title.get_combined_minimum_size().x).override_failure_message("%s title" % sec.id).is_less_equal(column)
