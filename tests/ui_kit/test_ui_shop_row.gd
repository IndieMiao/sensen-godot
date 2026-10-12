extends GdUnitTestSuite
## UiStepper and UiShopRow (SGODOT-224; Compact/Stepper 1245:108953, Compact/ShopProduct 702:80447, FARM-6 482:46).

const SEED := preload("res://assets/p0/icons/seed_radish.svg")

func _host(c: Control) -> Control:
	var top := CanvasLayer.new()
	top.layer = 128
	add_child(auto_free(top))
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 640)
	top.add_child(host)
	host.add_child(c)
	return c

func _settle() -> void:
	for i in 3: await get_tree().process_frame

func test_stepper_stays_between_one_and_the_cap() -> void:
	var s := _host(UiStepper.new(3)) as UiStepper
	var seen := []
	s.changed.connect(func(v): seen.append(v))
	assert_bool(s._minus.disabled).is_true()
	s._plus.pressed.emit()
	s._plus.pressed.emit()
	s._plus.pressed.emit()   # capped at 3
	assert_int(s.value).is_equal(3)
	assert_bool(s._plus.disabled).is_true()
	assert_array(seen).is_equal([2, 3])
	s.max_value = 2
	assert_int(s.value).is_equal(2)
	await _settle()
	assert_vector(s.size).is_equal(Vector2(76, 44))   # 76 wide, the 44 touch row

func _spec(buttons: Array, price := {each = 4, total = 4, text = "4 coins", line = ""}) -> Dictionary:
	return {id = "seed_radish", icon = SEED, title = "Radish Seeds", info = true, facts = ["Ready in 4h", "Bag ×20"],
		price = price, buttons = buttons}

func test_available_row_has_a_stepper_and_an_outlined_buy() -> void:
	var r := _host(UiShopRow.new()) as UiShopRow
	r.show_spec(_spec([{id = &"buy", label = "Buy", kind = &"secondary", payload = {}}]), false, 5)
	await _settle()
	assert_float(r.size.y).is_equal(58.0)
	_assert_key_inside_its_touch_area(r)
	assert_object(r.stepper).is_not_null()
	assert_int(r.stepper.max_value).is_equal(5)
	assert_int(r.buy.kind).is_equal(UiCommandButton.Kind.SECONDARY)
	assert_str(r._effect.text).is_equal("Ready in 4h")
	assert_str(r._gate.text).is_equal("Bag ×20")
	assert_str(r._price.text).is_equal("4 coins")
	var got := []
	r.bought.connect(func(id, q): got.append([id, q]))
	r.stepper.value = 3
	r.buy.activated.emit()
	assert_array(got).is_equal([["seed_radish", 3]])
	# The command sits right, from y 16 (Compact/Shop action at (260, 16)).
	assert_float(r.buy.get_global_rect().end.x - r.get_global_rect().position.x).is_equal_approx(336.0, 0.5)
	assert_float(r.buy.position.y + r._actions.position.y).is_equal(16.0)

func test_more_than_one_shows_the_unit_price_line_and_keeps_the_count() -> void:
	var r := _host(UiShopRow.new()) as UiShopRow
	var buy := [{id = &"buy", label = "Buy", kind = &"secondary", payload = {}}]
	r.show_spec(_spec(buy), false, 9)
	r.stepper.value = 2
	r.show_spec(_spec(buy, {each = 4, total = 8, text = "8 coins", line = "2 × 4 coins"}), false, 9)
	assert_int(r.stepper.value).is_equal(2)   # the chosen count survives a refresh
	assert_str(r._effect.text).is_equal("2 × 4 coins")
	assert_str(r._price.text).is_equal("8 coins")

func test_unavailable_row_says_why_and_has_no_stepper() -> void:
	var r := _host(UiShopRow.new()) as UiShopRow
	r.show_spec(_spec([{id = &"buy", label = "Farming Lv8 needed", kind = &"unavailable", payload = {}}]))
	assert_object(r.stepper).is_null()
	assert_bool(r.buy.is_unavailable()).is_true()
	assert_str(r.buy.reason).is_equal("Farming Lv8 needed")

func test_one_off_items_take_no_stepper() -> void:
	var r := _host(UiShopRow.new()) as UiShopRow
	r.show_spec(_spec([{id = &"buy", label = "Buy", kind = &"secondary", payload = {}}]), true)
	assert_object(r.stepper).is_null()
	assert_object(r.buy).is_not_null()

## STALL-NEW-2 (SGODOT-233): Gate tone=New draws the gate line in newInk; any other row keeps it secondary.
func test_a_new_row_draws_its_gate_line_in_new_ink() -> void:
	var row := _host(UiShopRow.new()) as UiShopRow
	row.show_spec({id = "seed_carrot", icon = SEED, title = "Carrot Seeds", facts = ["Ready in 12h", "◆ New for you"],
		gate_tone = &"new", price = {text = "9 coins", line = ""}, buttons = []})
	assert_object(row._gate.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_NEW_INK)
	row.show_spec({id = "seed_radish", icon = SEED, title = "Radish Seeds", facts = ["Ready in 4h", "Bag ×2"],
		price = {text = "4 coins", line = ""}, buttons = []})
	assert_object(row._gate.get_theme_color(&"font_color")).is_equal(UiTokens.COLOR_SECONDARY)

## q(151) (Compact/Shop action): Buy's touch area is 76 × 44 at y 16, the key drawn in it 68 × 34 — 5 above and below,
## 4 in from each side — so it ends at 55, clear of the hairline at the row's foot (Joey on 296: it read as cut). The
## grey key and the Stepper are drawn 34 high in their 44 too.
func _drawn(c: Control, st: StringName) -> Rect2:
	var sb := c.get_theme_stylebox(st) as UiStyleBox
	var r := Rect2(Vector2.ZERO, c.size)
	r = Rect2(r.position + Vector2(sb.inset.x, sb.inset.y), r.size - Vector2(sb.inset.x + sb.inset.z, sb.inset.y + sb.inset.w))
	if sb.visual_height > 0.0 and r.size.y > sb.visual_height:
		r.position.y += (r.size.y - sb.visual_height) * 0.5
		r.size.y = sb.visual_height
	return r

func _assert_key_inside_its_touch_area(r: UiShopRow) -> void:
	var top := r.buy.get_global_rect().position - r.get_global_rect().position
	assert_vector(r.buy.size).is_equal(Vector2(76, 44))
	assert_float(top.y).is_equal(16.0)
	for st in [&"normal", &"hover", &"pressed"]:
		var d := _drawn(r.buy, st)
		assert_that([d.position, d.size]).is_equal([Vector2(4, 5), Vector2(68, 34)])
	assert_float(top.y + 5.0 + 34.0).is_less(r.size.y - UiTokens.STROKE_DEFAULT)   # 55, above the hairline

func test_the_buy_key_keeps_its_drawn_size_through_offline_and_back() -> void:
	var r := _host(UiShopRow.new()) as UiShopRow
	r.show_spec(_spec([{id = &"buy", label = "Buy", kind = &"secondary", payload = {}}]), false, 5)
	await _settle()
	UiCommandButton.set_offline(get_tree(), true)
	await _settle()
	assert_str(r.buy.text).is_equal("Offline")
	assert_that(_drawn(r.buy, &"normal").size).is_equal(Vector2(68, 34))   # the grey look, the same size
	UiCommandButton.set_offline(get_tree(), false)
	await _settle()
	assert_that(_drawn(r.buy, &"normal").size).is_equal(Vector2(68, 34))

func test_a_grey_key_and_the_stepper_are_drawn_34_high() -> void:
	var r := _host(UiShopRow.new()) as UiShopRow
	r.show_spec(_spec([{id = &"buy", label = "Farming Lv8 needed", kind = &"unavailable", payload = {}}]), false, 5)
	await _settle()
	var d := _drawn(r.buy, &"normal")
	assert_that([r.buy.size.y, d.position.y, d.size.y]).is_equal([44.0, 5.0, 34.0])
	var s := _host(UiShopRow.new()) as UiShopRow
	s.show_spec(_spec([{id = &"buy", label = "Buy", kind = &"secondary", payload = {}}]), false, 5)
	await _settle()
	var surface := s.stepper.get_child(0) as Control
	assert_that([s.stepper.size.y, surface.position.y, surface.size.y]).is_equal([44.0, 5.0, 34.0])
