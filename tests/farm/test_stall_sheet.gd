extends GdUnitTestSuite
## 路边摊：卖产出、买种子，按钮上的数字是服务端会给的数。

func _sheet() -> StallSheet:
	var s := StallSheet.new()
	add_child(auto_free(s))
	return s

func _state(produce: Dictionary, wallet := 180, settled := 0) -> Dictionary:
	return {"wallet": wallet, "stall": {"settled": settled},
		"inventory": {"produce": produce, "seeds": {"R": {"bought": 0, "bound": 6}, "L": {"bought": 0, "bound": 3}}}}

func test_sell_row_shows_count_price_and_total() -> void:
	var s := _sheet()
	s.refresh(_state({"R": 2}), ["R", "L"])
	var texts := s.row_buttons().map(func(b): return b.text)
	assert_bool(texts.has("Sell all · +16")).is_true()        # 2 × 8
	assert_str(s._budget.text).is_equal("Today's sales 0 / 100 coins")

func test_nothing_to_sell_says_so() -> void:
	var s := _sheet()
	s.refresh(_state({}), ["R", "L"])
	assert_bool(s._empty.visible).is_true()
	s.refresh(_state({"R": 1}), ["R", "L"])
	assert_bool(s._empty.visible).is_false()

func test_sell_button_emits_all_of_that_produce() -> void:
	var s := _sheet()
	s.refresh(_state({"L": 3}), ["R", "L"])
	var got := []
	s.sell_requested.connect(func(items): got.append(items))
	for b in s.row_buttons():
		if (b as Button).text.begins_with("Sell all"):
			(b as Button).pressed.emit()
	assert_that(got[0]).is_equal([{"kind": "produce", "id": "L", "qty": 3}])

func test_stall_budget_caps_the_sell_total() -> void:
	# 已结算 90，预算 100：只剩 10 → 一颗 8 的萝卜卖得掉一颗
	var s := _sheet()
	s.refresh(_state({"R": 5}, 180, 90), ["R"])
	var texts := s.row_buttons().map(func(b): return b.text)
	assert_bool(texts.has("Sell all · +8")).is_true()

func test_one_sale_contains_all_crops_and_respects_shared_budget_and_reservations() -> void:
	var s := _sheet()
	var state := _state({"R": 3, "L": 3}, 180, 60)
	state.engineering = {"reserved": {"R": 1}}
	s.refresh(state, ["R", "L"])
	assert_str(s._sell_all.text).is_equal("Sell all · +40")
	var got := []
	s.sell_requested.connect(func(items): got.append(items))
	s._sell_all.pressed.emit()
	assert_that(got[0]).is_equal([
		{"kind": "produce", "id": "R", "qty": 2},
		{"kind": "produce", "id": "L", "qty": 3}])
	assert_str(s._produce_rows.L.total.text).is_equal("24")

func test_buy_buttons_need_coins_and_only_show_unlocked_crops() -> void:
	var s := _sheet()
	s.refresh(_state({}, 10), ["R", "L"])
	var buys := s.row_buttons().filter(func(b): return (b as Button).text.begins_with("Buy"))
	assert_int(buys.size()).is_equal(2)                        # R、L；C/H 锁着不出现
	assert_bool((buys[0] as Button).disabled).is_true()         # 12 > 10 买不起
	var got := []
	s.buy_requested.connect(func(c, q): got.append([c, q]))
	s.refresh(_state({}, 180), ["R", "L"])
	for b in s.row_buttons():
		if (b as Button).text == "Buy 3 · 12":
			(b as Button).pressed.emit()
	assert_array(got).is_equal([["R", 3]])

func test_all_text_is_english() -> void:
	var s := _sheet()
	s.refresh(_state({"R": 1}), ["R", "L"])
	var stack: Array = [s]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var text := ""
		if n is Button:
			text = (n as Button).text
		elif n is Label:
			text = (n as Label).text
		for ch in text:
			assert_bool(ch.unicode_at(0) < 0x2E80).override_failure_message("含非英文: %s" % text).is_true()

func test_seed_quantity_can_buy_the_exact_remaining_seed_count() -> void:
	var s := _sheet()
	s.refresh(_state({}, 10), ["R", "L"])
	s.set_buy_quantity(1)
	assert_str(s._seed_rows.R.button.text).is_equal("Buy 1 · 4")
	assert_bool(s._seed_rows.R.button.disabled).is_false()
	var got := []
	s.buy_requested.connect(func(crop, quantity): got.append([crop, quantity]))
	s._seed_rows.R.button.pressed.emit()
	assert_that(got).is_equal([["R", 1]])
	s.set_buy_quantity(100)
	assert_int(s._buy_qty).is_equal(12)
	s.set_buy_quantity(0)
	assert_int(s._buy_qty).is_equal(1)

func test_single_sales_keep_project_reservations_and_include_dishes() -> void:
	var s := _sheet()
	var state := _state({"C": 2})
	state.engineering = {"reserved": {"C": 2}}
	state.inventory.dishes = {"salad": 2, "tea": 1}
	s.refresh(state, ["R", "L", "C", "H"])
	assert_bool(s._produce_rows.C.button.disabled).is_true()
	assert_bool(s._produce_rows.C.box.visible).is_true()
	assert_bool(s._dish_rows.salad.box.visible).is_true()
	var got := []
	s.sell_requested.connect(func(items): got.append(items))
	s._dish_rows.salad.button.pressed.emit()
	assert_that(got).is_equal([[{"kind": "dish", "id": "salad", "qty": 1}]])
	assert_str(s._sell_all.text).is_equal("Sell all · +96")

func test_mine_soup_appears_with_its_own_name_price_and_sale_id() -> void:
	var sheet := _sheet()
	var state := _state({})
	state.journey = {"version": 1, "facts": ["shared_meal"], "unlocks": ["kitchen"]}
	state.inventory.dishes = {"vegetable_soup": 2}
	sheet.refresh(state, ["R", "L"])
	var row: Dictionary = sheet._dish_rows.vegetable_soup
	assert_bool(row.box.visible).is_true()
	assert_str(row.label.text).contains("Rock-salt vegetable soup")
	assert_str(row.price.text).is_equal("16 each")
	assert_str(sheet._sell_all.text).is_equal("Sell surplus - +32")
	var sales := []
	sheet.sell_requested.connect(func(items): sales.append(items))
	row.button.pressed.emit()
	assert_array(sales).is_equal([[{"kind": "dish", "id": "vegetable_soup", "qty": 1}]])

func test_waiting_for_server_disables_all_trade_actions() -> void:
	var s := _sheet()
	s.refresh(_state({"R": 3}), ["R"])
	s.set_busy(true)
	assert_bool(s._sell_all.disabled).is_true()
	assert_bool(s._produce_rows.R.button.disabled).is_true()
	assert_bool(s._seed_rows.R.button.disabled).is_true()
	assert_bool(s._quantity_plus.disabled).is_true()
	s.set_busy(false)
	assert_bool(s._sell_all.disabled).is_false()

func test_uncertain_trade_offers_reload_without_resending_the_purchase() -> void:
	var s := _sheet()
	s.refresh(_state({"R": 3}), ["R"])
	s.set_uncertain(true)
	assert_bool(s.is_busy()).is_false()
	assert_bool(s._sell_all.disabled).is_true()
	assert_bool(s._seed_rows.R.button.disabled).is_true()
	assert_bool(s._retry.visible).is_true()
	var retries := []
	var purchases := []
	s.retry_requested.connect(func(): retries.append(true))
	s.buy_requested.connect(func(crop, quantity): purchases.append([crop, quantity]))
	s._retry.pressed.emit()
	assert_array(retries).is_equal([true])
	assert_array(purchases).is_empty()
	s.set_uncertain(false)
	assert_bool(s._retry.visible).is_false()
	assert_bool(s._seed_rows.R.button.disabled).is_false()
