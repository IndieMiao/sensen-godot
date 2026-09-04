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
		if (b as Button).text == "Buy 3 · 12 coins":
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
