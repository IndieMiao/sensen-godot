extends GdUnitTestSuite
## P0 counter drawer and keeper greeting (SGODOT-224; FARM-6, NPC-2, NPC-2-2, NPC-6, NPC-7-P0, LOCK-15 / 16).
## The view is a real P0 server view (tests/p0/fixtures/counter_view.json: fresh state, 300 coins, Energy 150,
## a bag of seeds, radishes, two fish and timber).

const TACKLE_CTX := {"keeper": "Finn", "place": "Mission Tackle Shop", "nearest": {"name": "Reed Pond", "site": "pond"}}

func _view() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/p0/fixtures/counter_view.json"))

func _drawer(role: String, ctx := {}, section := "buy", v := {}) -> P0CounterDrawer:
	var top := CanvasLayer.new()
	top.layer = 128
	add_child(auto_free(top))
	var host := Control.new()
	host.theme = UiKit.theme()
	host.size = Vector2(360, 800)
	top.add_child(host)
	var d := P0CounterDrawer.new(v if not v.is_empty() else _view(), role, ctx, section)
	d.animate = false
	host.add_child(d)
	return d

func _settle() -> void:
	for i in 3: await get_tree().process_frame

func _row_ids(d: P0CounterDrawer) -> Array: return d.shelf.get_children().filter(func(c): return c.visible).map(func(r): return (r as UiShopRow).item_id)

func test_homestead_stall_has_tabs_shelf_and_the_whole_bag() -> void:
	var d := _drawer("homestead")
	await _settle()
	assert_object(d.keeper_bar).is_null()   # unattended (FARM-6)
	assert_array(_row_ids(d)).contains(["seed_radish", "seed_lettuce", "bait_worm", "fert_compost", "bag_upgrade_1"])
	assert_bool(d._bag_half.visible).is_true()
	assert_bool(d.grid.sell_mode).is_false()   # `All`: the whole bag
	assert_str(d._quota.text).is_equal("Crops & fish · no daily limit")
	# FARM-6: rows at y 188, divider at y 428; the kit's chips keep a 44 touch row (Figma 36), so 4 lower.
	assert_float(d._shelf_box.get_global_rect().position.y).is_equal(192.0)
	assert_float(d._bag_half.get_global_rect().position.y + 8.0).is_equal(432.0)

func test_selecting_a_crop_shows_sell_and_a_seed_shows_no_card() -> void:
	var d := _drawer("homestead")
	await _settle()
	d.select("crop_radish")
	assert_bool(d.sheet.is_open()).is_true()
	d.select("seed_radish")
	assert_bool(d.sheet.is_open()).is_false()

func test_tackle_counter_is_one_page_with_the_keeper_bar_and_fish_only() -> void:
	var d := _drawer("tackle", TACKLE_CTX)
	await _settle()
	assert_str(d.keeper_bar.title).is_equal("Finn's Tackle")
	assert_str(d.keeper_bar.place).is_equal("Mission Tackle Shop")
	assert_str(d.keeper_bar.keeper).is_equal("Tackle Keeper · Finn")
	assert_str(d.keeper_bar.line).is_equal("Worms are 2 coins. 30 left today.")
	assert_array(d.find_children("*", "UiFilterChip", true, false).filter(func(c): return c.text == "Buy")).is_empty()   # no tab row
	assert_array(_row_ids(d)).is_equal(["rod_reed", "bait_worm"])
	assert_object((d._rows["rod_reed"] as UiShopRow).stepper).is_null()   # one-off: no stepper
	assert_bool(d.grid.sell_mode).is_true()
	assert_array(d.grid.shown_items().map(func(it): return it.id)).contains_exactly_in_any_order(["fish_crucian", "fish_carp"])
	assert_str(d._quota.text).starts_with("Fish buy-back today 0/80\nany Tackle Shop · resets in ")

func test_market_buys_nothing_so_it_has_no_bag_half_and_specialty_is_its_own_shelf() -> void:
	var d := _drawer("market", {"keeper": "Mei", "place": "Mission Market Square"})
	await _settle()
	assert_bool(d._bag_half.visible).is_false()
	assert_str(d.keeper_bar.line).is_equal("Row Hoe's 240 coins. Farming Lv4 to use.")   # a counter line, not the card's question (#56)
	assert_array(_row_ids(d)).is_equal(["tool_row_hoe"])
	d.set_section("board")
	assert_bool(d.board.visible).is_true()
	assert_bool(d._shelf_box.visible).is_false()

func test_city_specialty_is_its_own_short_sheet() -> void:
	# MARKET-SPECIALTY 1394:92801 (李白 q(48)): no keeper bar, no tabs, no bag; the postcard row only.
	var d := _drawer("market", {"keeper": "Mei", "place": "Mission Market Square"}, "specialty")
	await _settle()
	assert_object(d.keeper_bar).is_null()
	assert_array(_row_ids(d)).is_equal(["postcard_san_francisco"])
	assert_float(d.height).is_equal(137.0)
	var row: UiShopRow = d._rows["postcard_san_francisco"]
	assert_str(row._effect.text).is_equal("Goes to your Farm Storage")
	assert_str(row._gate.text).is_equal("Stock 1/1")
	assert_float(row.get_global_rect().position.y).is_equal(714.0)

func test_buy_reports_the_item_and_stepper_count() -> void:
	var d := _drawer("homestead")
	await _settle()
	var got := []
	d.action_requested.connect(func(a, id, p): got.append([a, id, p]))
	var row: UiShopRow = d._rows["seed_radish"]
	row.stepper.value = 3
	row.stepper.changed.emit(3)
	row.buy.activated.emit()
	assert_array(got).is_equal([[&"buy", "seed_radish", {qty = 3}]])

func test_tea_page_states() -> void:
	var v := _view()
	var d := _drawer("tea", {"keeper": "Ama", "place": "Oak Tea House"}, "buy", v)
	await _settle()
	assert_str(d.keeper_bar.note).is_equal("Counts across all tea houses · 3 cups a day")
	var labels := d._drinks.find_children("*", "Label", true, false).map(func(l): return (l as Label).text)
	assert_array(labels).contains(["Cups used", "0/3", "Hot Tea · +30 Energy · 40 coins"])   # q(98) ③: counted once
	var b: UiCommandButton = d._drinks.find_children("*", "UiCommandButton", true, false)[0]
	assert_str(b.label).is_equal("Hot Tea · +30 Energy")
	v.drinks.used = 1
	v.drinks.left = 2
	d.refresh(v, true)
	await _settle()
	labels = d._drinks.find_children("*", "Label", true, false).filter(func(l): return l.is_visible_in_tree()).map(func(l): return (l as Label).text)
	assert_array(labels).contains(["1/3", "Hot Tea · +30 Energy · 40 coins"])
	v.drinks.used = 3
	v.drinks.left = 0
	d.refresh(v, true)
	await _settle()
	b = d._drinks.find_children("*", "UiCommandButton", true, false).filter(func(x): return x.visible)[0]
	assert_str(b.reason).is_equal("Tea 3/3 today · Resets in 11h")   # TEA-BLOCKED: the home-day reset, not tomorrow (q(98) ③)
	v.drinks.resets_in = 2520000
	d.refresh(v, true)
	await _settle()
	b = d._drinks.find_children("*", "UiCommandButton", true, false).filter(func(x): return x.visible)[0]
	assert_str(b.reason).is_equal("Tea 3/3 today · Resets in 42m")   # q(97)

func test_post_desk_note_and_keeper() -> void:
	var d := _drawer("post", {"keeper": "Sigrid", "place": "Union Square Travel Post"})
	await _settle()
	assert_str(d.keeper_bar.title).is_equal("Sigrid's Desk")
	assert_str(d.keeper_bar.note).is_equal("Shares the 3 cups a day with tea")
	assert_float(d.height).is_equal(P0CounterDrawer.HEIGHT_DRINKS)

## Every drawer has its handle 8–12 under the top (#196); a counter's keeper bar starts 16 under it, 4 clear of the
## handle, and what follows moves down with it; the drink counters grow by those 10 (276) so nothing inside is squeezed
## and their keeper bar stays at y 540 (不知火舞 on 265, A).
func test_the_keeper_bar_sits_under_the_handle() -> void:
	for role in ["tackle", "market", "tea", "post"]:
		var d := _drawer(role, {"keeper": "Kim", "place": "Somewhere"})
		await _settle()
		assert_bool(d.handle).override_failure_message(role).is_true()
		var top := d.get_global_rect().position.y
		var bar := d.keeper_bar.get_global_rect().position.y
		assert_float(bar - top).override_failure_message(role).is_equal(16.0)
		assert_float(bar - (top + 12.0)).override_failure_message(role + ": clear of the handle").is_equal(4.0)
		if role in P0CounterDrawer.DRINK_ROLES:
			assert_float(d.height).is_equal(276.0)
			assert_float(bar).is_equal(540.0)
	var stall := _drawer("homestead")
	await _settle()
	assert_float(stall._shelf_box.get_global_rect().position.y).is_equal(192.0)   # the stall has no keeper bar: unchanged

# ---------------------------------------------------------------- P0Ui entries

func _ui() -> P0Ui:
	var u := P0Ui.new()
	add_child(auto_free(u))
	u.layer = 128
	return u

func test_keeper_greeting_passes_ctx_and_trade_opens_the_counter() -> void:
	var ui := _ui()
	await await_idle_frame()
	ui.set_view(_view())
	ui.open_keeper_greeting("tackle", TACKLE_CTX)
	assert_str(ui.modal_kind).is_equal("greeting")
	var card: UiDialogueCard = ui._modal.find_children("*", "UiDialogueCard", true, false)[0]
	assert_str(card.title).is_equal("Tackle Keeper · Finn")
	assert_str(card.place).is_equal("Minds the tackle · Mission Tackle Shop")
	(card.content.get_child(0) as UiCommandButton).activated.emit()   # Trade · see the rods
	assert_str(ui.modal_kind).is_equal("counter")
	assert_str(ui._counter.keeper_bar.place).is_equal("Mission Tackle Shop")

func test_counter_commands_carry_the_shop_and_a_drink_changes_the_line() -> void:
	var ui := _ui()
	await await_idle_frame()
	var v := _view()
	ui.set_view(v)
	var sent := []
	ui.command.connect(func(c): sent.append(c))
	ui.open_counter("tea", {"ctx": {"keeper": "Ama", "place": "Oak Tea House"}})
	ui._counter.action_requested.emit(&"drink", "drink_hot_tea", {})
	ui._counter_action("tackle", &"sell", "fish_crucian", {qty = "all"})
	assert_array(sent).is_equal([{"type": "drink", "item": "drink_hot_tea", "shop": "tea"},
		{"type": "sell", "item": "fish_crucian", "qty": "all", "shop": "tackle"}])
	v.drinks.price = 50
	ui.set_view(v)
	ui.counter_events([{"kind": "drink", "item": "drink_hot_tea", "gain": 30, "price": 40, "left": 2}])
	assert_str(ui._counter.keeper_bar.line).is_equal("Enjoy. Next cup's 50 coins.")   # TEA-DONE

## counter_drawer(): the open counter drawer, its board sheets over it included; null once it closes (#128 review).
func test_counter_drawer_is_the_open_counter_only() -> void:
	var ui := _ui()
	await await_idle_frame()
	ui.set_view(_view())
	assert_object(ui.counter_drawer()).is_null()
	ui.open_counter("tea", {"ctx": {"keeper": "Ama", "place": "Oak Tea House"}})
	assert_object(ui.counter_drawer()).is_same(ui._counter)
	ui.modal_kind = "board_request"   # a Market Board sheet over the drawer keeps it
	assert_object(ui.counter_drawer()).is_same(ui._counter)
	ui.close_modal()
	assert_object(ui.counter_drawer()).is_null()

## q(48): the P0 market has no bag half, so its drawer is as tall as its taller page (the Buy rows or the Market
## Board's cards) and keeps that height across the tabs (不知火舞 on #56, like City Specialty).
func test_the_market_drawer_is_as_tall_as_its_taller_page_and_keeps_it_across_tabs() -> void:
	var ui := _ui()
	await await_idle_frame()
	var v := _view()
	v["boards"]["market"]["slots"] = [{"id": "req_m1", "title": "Market Basket", "kind": "crop", "items": ["crop_radish"],
		"icon": "crop_radish", "qty": 6, "have": 2, "coins": 30, "status": "open"},
		{"id": "req_m2", "title": "Dusk Haul", "kind": "fish", "items": [], "rarity": 2, "icon": "fish_crucian", "qty": 3,
		"have": 0, "coins": 45, "status": "open"}]
	ui.set_view(v)
	ui.open_counter("market", {"ctx": {"keeper": "Mei", "place": "Mission Market Square"}})
	var d := ui._counter
	await d.fitted
	assert_bool(d.is_short()).is_true()
	var h := d.height
	assert_float(h).is_less(P0CounterDrawer.HEIGHT)   # no bag half
	assert_float(h).is_greater_equal(d.get_combined_minimum_size().y - 0.5)   # the Buy page fits
	d.set_section("board")
	await _settle()
	assert_float(d.height).is_equal_approx(h, 0.5)   # no jump on the tab switch
	assert_float(h).is_greater_equal(d.get_combined_minimum_size().y - 0.5)   # the board page fits too
	assert_int(d.board.get_children().filter(func(c): return c is UiBoardCard and c.visible).size()).is_equal(2)
	ui.close_modal()
	ui.open_counter("tackle", {"ctx": TACKLE_CTX})   # a counter with a bag half keeps the full height
	assert_bool(ui._counter.is_short()).is_false()
	assert_float(ui._counter.height).is_equal(P0CounterDrawer.HEIGHT)

## The market drawer measures itself while it is still sliding in: it ends at its new height, not the first one.
func test_a_drawer_resized_while_sliding_in_lands_at_the_new_height() -> void:
	var d := _drawer("tackle", TACKLE_CTX)
	d.queue_free()
	var host: Control = d.get_parent()
	var e := P0CounterDrawer.new(_view(), "tackle", TACKLE_CTX)
	host.add_child(e)   # animate on
	await get_tree().process_frame
	e.height = 300.0
	await get_tree().create_timer(UiKit.secs(UiTokens.MOTION_DRAWER_MS) + 0.15).timeout
	assert_float(e.offset_top).is_equal_approx(-300.0, 0.5)
	assert_float(e.offset_bottom).is_equal_approx(0.0, 0.5)

## 刘邦 on #62: a market drawer closed while it is measuring itself just stops (no resume on a freed drawer), and the
## page not shown is see-through while both are laid out.
func test_a_market_drawer_closed_mid_measure_stops_quietly() -> void:
	var ui := _ui()
	await await_idle_frame()
	ui.set_view(_view())
	ui.open_counter("market", {"ctx": {"keeper": "Mei", "place": "Mission Market Square"}})
	var d := ui._counter
	assert_float(d.board.modulate.a).is_equal(0.0)   # Buy in front, the board measured behind it
	assert_bool(d._shelf_box.visible and d.board.visible).is_true()
	ui.close_modal()
	for i in 4: await get_tree().process_frame
	assert_bool(is_instance_valid(d)).is_false()
