extends GdUnitTestSuite
## UiInfoSheet + P0ItemInfo interface contract (SGODOT-224 day 0 stub; F-07 confirmed table on SGODOT-207).

var sheet: UiInfoSheet
var calls: Array

func _view() -> Dictionary:
	return {
		"names": {"crop_radish": "Radish"},
		"items": {"crop_radish": {"name": "Radish", "kind": "crop", "sell": 5, "rarity": 1}},
		"rarity_names": ["Common", "Fine", "Rare", "Legendary"],
		"bag": {"capacity": 25, "slots": [{"id": "crop_radish", "qty": 12}]},
	}

func before_test() -> void:
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(336, 400)
	add_child(auto_free(host))
	sheet = UiInfoSheet.new()
	host.add_child(sheet)
	calls = []
	sheet.rules = func(id: String, ctx: StringName, opts: Dictionary) -> Dictionary:
		calls.append([id, ctx, opts])
		var s := P0ItemInfo.spec(_view(), id, ctx, opts)
		s.facts = ["12 · Harvested at home", "Sells for 5"]
		s.buttons = [{id = &"sell", label = "Sell", kind = &"secondary", payload = {qty = 1}},
			{id = &"sell_all", label = "Sell All · 60 coins", kind = &"primary", payload = {}},
			{id = &"gift", label = "Sell at home", kind = &"unavailable", payload = {}}]
		return s

func test_spec_contract_fills_the_title_area_from_the_view() -> void:
	var s := P0ItemInfo.spec(_view(), "crop_radish", &"bag")
	for key in ["id", "icon", "title", "quantity", "info", "rarity", "rarity_text", "quality", "region", "badge", "facts", "buttons", "lock", "quota"]:
		assert_bool(s.has(key)).override_failure_message("spec lacks %s" % key).is_true()
	assert_str(s.title).is_equal("Radish")
	assert_int(s.quantity).is_equal(12)
	assert_str(s.rarity_text).is_equal("Common")
	assert_array(P0ItemInfo.CONTEXTS).contains_exactly([&"bag", &"gear", &"counter_buy", &"counter_sell", &"gift", &"storage"])

func test_open_asks_the_rules_and_draws_the_spec() -> void:
	assert_bool(sheet.visible).is_false()
	sheet.open("crop_radish", &"counter_sell", {counter = "homestead"})
	assert_bool(sheet.is_open()).is_true()
	assert_array(calls).is_equal([["crop_radish", &"counter_sell", {counter = "homestead"}]])
	assert_str(sheet._title.text).is_equal("Radish")
	assert_str(sheet._qty.text).is_equal("×12")
	assert_str(sheet._state.text).is_equal("Common")
	await await_idle_frame()
	# Beside three buttons "Sells for 5" doesn't fit the effect slot, so it takes its own fact line.
	sheet.size = Vector2(336, 0)
	await get_tree().process_frame
	assert_array(sheet._facts.get_children().filter(func(c): return c.visible).map(func(c): return c.text)).is_equal(["12 · Harvested at home", "Sells for 5"])
	assert_str(sheet._effect.text).is_empty()
	assert_int(sheet._buttons.get_child_count()).is_equal(3)

func test_buttons_emit_their_action_and_unavailable_ones_stay_silent() -> void:
	var got := []
	sheet.action_requested.connect(func(a, id, p): got.append([a, id, p]))
	sheet.open("crop_radish", &"counter_sell")
	await await_idle_frame()
	var b: Array = sheet._buttons.get_children()
	b[0].activated.emit()
	b[1].activated.emit()
	(b[2] as UiCommandButton)._on_pressed()   # a reason button reports unavailable_pressed, never activated
	assert_array(got).is_equal([[&"sell", "crop_radish", {qty = 1}], [&"sell_all", "crop_radish", {}]])
	assert_bool((b[2] as UiCommandButton).is_unavailable()).is_true()

func test_open_again_switches_and_close_fires_once() -> void:
	var n := [0]
	sheet.closed.connect(func(): n[0] += 1)
	sheet.open("crop_radish", &"bag")
	sheet.open("crop_radish", &"counter_buy", {qty = 2})
	assert_str(sheet.context()).is_equal("counter_buy")
	assert_int(n[0]).is_equal(0)   # switching is not closing
	sheet.close()
	sheet.close()
	assert_int(n[0]).is_equal(1)
	assert_str(sheet.item_id()).is_empty()

func test_refresh_rebuilds_from_the_rules_while_open_only() -> void:
	sheet.refresh()
	assert_array(calls).is_empty()
	sheet.open("crop_radish", &"bag")
	sheet.refresh()
	assert_int(calls.size()).is_equal(2)

func test_card_matches_the_selected_item_main() -> void:
	sheet.rules = func(id, ctx, o): return {id = id, title = "Grilled Crucian", quantity = 3, info = true, rarity_text = "Common",
		facts = ["+20 Energy"], buttons = [{id = &"gift", label = "Gift ›", kind = &"nav"}, {id = &"eat", label = "Eat · +20 Energy", kind = &"primary"}],
		lock = {shown = false, locked = false}}
	sheet.open("dish_grilled_crucian", &"bag")
	for i in 3: await get_tree().process_frame
	# Compact/SelectedItem 633:41257 is 336 × 82: title row, state line, then the effect and buttons on one 44 row.
	sheet.size = Vector2(336, 0)
	for i in 2: await get_tree().process_frame
	assert_float(sheet.get_combined_minimum_size().y).is_equal(82.0)
	var row: Control = sheet._effect.get_parent()
	assert_float(row.global_position.y - sheet.global_position.y).is_equal(38.0)   # the 44 row at y 38 of the card
	assert_bool(sheet._buttons.get_child(0) is UiNavButton).is_true()
	assert_str(sheet._effect.text).is_equal("+20 Energy")   # a short last fact stays beside the buttons
	assert_bool(sheet._lock.visible).is_false()
	var hits := []
	sheet.info_requested.connect(func(id): hits.append(id))
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	sheet._title.get_parent().gui_input.emit(up)   # the title area is the details touch target
	assert_array(hits).is_equal(["dish_grilled_crucian"])

func test_lock_icon_toggles_lock_and_unlock() -> void:
	var locked := [false]
	sheet.rules = func(id, ctx, o): return {id = id, title = "Radish", lock = {shown = true, locked = locked[0]}, badge = &"locked" if locked[0] else &""}
	var got := []
	sheet.action_requested.connect(func(a, id, p): got.append(a))
	sheet.open("crop_radish", &"bag")
	assert_bool(sheet._lock.visible).is_true()
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	sheet._lock.get_child(1).gui_input.emit(up)
	assert_vector(sheet._lock.get_child(1).size).is_equal(Vector2(44, 44))   # F-07: 44 touch area
	locked[0] = true
	sheet.refresh()
	assert_bool(sheet._badge.visible).is_true()   # the locked badge replaces the lock icon
	assert_array(got).is_equal([&"lock"])
