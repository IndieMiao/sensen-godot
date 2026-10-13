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

## The Market Square buys this city's climate's regional crops and fish back (SGODOT-284, 不知火舞 on 240): a bag half
## like the Tackle Shop's, listing only those (LOCK-15), with the city's 60-coin allowance.
func _market_view() -> Dictionary:
	var v := _view()
	v.items["crop_pumpkin"] = {"name": "Pumpkin", "kind": "crop", "sell": 22, "rarity": 1}
	v.items["fish_salmon"] = {"name": "Salmon", "kind": "fish", "sell": 32, "rarity": 2}
	v.bag.slots.append({"id": "crop_pumpkin", "qty": 3})
	v.bag.slots.append({"id": "fish_salmon", "qty": 1})
	return v

func test_market_lists_only_its_regional_goods_with_the_city_allowance() -> void:
	var d := _drawer("market", {"keeper": "Mei", "place": "Mission Market Square"}, "buy", _market_view())
	await _settle()
	assert_bool(d._bag_half.visible).is_true()
	assert_bool(d.is_short()).is_false()
	assert_float(d.height).is_equal(P0CounterDrawer.HEIGHT)
	assert_bool(d.grid.sell_mode).is_true()
	assert_array(d.grid.shown_items().map(func(it): return it.id)).contains_exactly_in_any_order(["crop_pumpkin", "fish_salmon"])
	assert_str(d._quota.text).starts_with("Buy-back today 0/60\nall San Francisco markets · resets in ")
	d.select("crop_pumpkin")
	assert_bool(d.sheet.is_open()).is_true()

func test_market_without_regional_goods_shows_an_empty_sell_half() -> void:
	var d := _drawer("market", {"keeper": "Mei", "place": "Mission Market Square"})
	await _settle()
	assert_bool(d._bag_half.visible).is_true()
	assert_array(d.grid.shown_items()).is_empty()   # radishes, crucians and timber are not regional here

func test_market_keeper_line_and_board_and_specialty_is_its_own_shelf() -> void:
	var d := _drawer("market", {"keeper": "Mei", "place": "Mission Market Square"})
	await _settle()
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
	# a market that buys back (SGODOT-284, this view's market sells) still shows no bag on this sheet: its height counts
	# the rows only, and a Bag row under them ran off the screen (0.2.2, Joey on 296)
	assert_bool(P0CounterDrawer.has_bag_half(_view(), "market")).is_true()
	assert_bool(d._bag_half.visible).is_false()
	assert_float(d.get_global_rect().end.y).is_less_equal(800.0)
	# its Buy page keeps the bag half and its Sell scope
	var buy := _drawer("market", {"keeper": "Mei", "place": "Mission Market Square"})
	await _settle()
	assert_bool(buy._bag_half.visible).is_true()

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
	# q(154) (LOCK-16 复议 197 e508cd27): `Trade` and the question only — no `Just passing by` — and a Close 44 8 above
	# the card's top-right corner, as on the resident's bar; it closes the card
	assert_array(card.content.get_children().map(func(b): return [b.get_class(), (b as Button).text])).is_equal(
		[["Button", "Trade"], ["Button", "Where are they biting?"]])
	assert_int(ui._modal.find_children("*", "UiDismissButton", true, false).size()).is_equal(0)
	await await_idle_frame()
	var close: UiCloseButton = ui._modal.find_children("*", "UiCloseButton", true, false)[0]
	var c := card.get_global_rect()
	var x := close.get_global_rect()
	assert_that([x.end.x, x.end.y, x.size]).is_equal([c.end.x, c.position.y - 8.0, Vector2(44, 44)])
	close.pressed.emit()
	assert_str(ui.modal_kind).is_not_equal("greeting")
	ui.open_keeper_greeting("tackle", TACKLE_CTX)
	card = ui._modal.find_children("*", "UiDialogueCard", true, false)[0]
	(card.content.get_child(0) as UiCommandButton).activated.emit()   # Trade
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
	v.shops.market.sell = []   # a market that buys nothing back (before SGODOT-284's regional buy-back)
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
	var v := _view()
	v.shops.market.sell = []   # a market with no bag half measures itself
	ui.set_view(v)
	ui.open_counter("market", {"ctx": {"keeper": "Mei", "place": "Mission Market Square"}})
	var d := ui._counter
	assert_float(d.board.modulate.a).is_equal(0.0)   # Buy in front, the board measured behind it
	assert_bool(d._shelf_box.visible and d.board.visible).is_true()
	ui.close_modal()
	for i in 4: await get_tree().process_frame
	assert_bool(is_instance_valid(d)).is_false()

## q(151) in the drawer itself: a row built before the drawer has the game's theme keeps its keys' 44 touch row (they
## stretched to 52, Buy's 34 drawn at y 25–59 over the hairline; Joey on 296), Buy drawn 68 × 34 at y 21 like the
## Stepper's surface.
func test_the_rows_keys_keep_their_44_touch_row_in_the_drawer() -> void:
	var d := _drawer("homestead")
	await _settle()
	for id in ["seed_radish", "seed_lettuce"]:
		var row: UiShopRow = d._rows[id]
		var o := row.get_global_rect().position
		var buy := Rect2(row.buy.get_global_rect().position - o, row.buy.size)
		assert_that([buy.position, buy.size, row.stepper.size.y]).is_equal([Vector2(260, 16), Vector2(76, 44), 44.0])
		var sb := row.buy.get_theme_stylebox(&"normal") as UiStyleBox
		var top := buy.position.y + (buy.size.y - sb.visual_height) * 0.5
		assert_that([top, sb.visual_height, buy.size.x - sb.inset.x - sb.inset.z]).is_equal([21.0, 34.0, 68.0])
		assert_float(top + sb.visual_height).is_less(row.size.y - UiTokens.STROKE_DEFAULT)   # 55, above the hairline

## SGODOT-300: a generated city's keeper has no painted art; the greeting card and the counter's keeper bar get a
## portrait drawn from the keeper's look preset (blank until drawn: headless tests draw nothing). The four painted
## P0 keepers keep their art.
func test_keeper_portraits_fall_back_to_the_look() -> void:
	var painted := P0CounterDrawer.keeper_portrait("Mei", true, "market_temperate_0")
	assert_object(painted).is_not_null()
	assert_bool(painted is ImageTexture).override_failure_message("Mei keeps her painted card").is_false()
	var card := P0CounterDrawer.keeper_portrait("Ezra", true, "market_temperate_0")
	var head := P0CounterDrawer.keeper_portrait("Ezra", false, "market_temperate_0")
	assert_bool(card is ImageTexture).is_true()
	assert_vector(Vector2(card.get_size())).is_equal(Vector2(300, 660))
	assert_vector(Vector2(head.get_size())).is_equal(Vector2(264, 264))
	assert_object(P0CounterDrawer.keeper_portrait("Ezra", true, "market_temperate_0")).is_same(card)   # drawn once
	assert_object(P0CounterDrawer.keeper_portrait("Ezra", true, "")).is_null()   # no look, no art: as before
	assert_object(P0CounterDrawer.keeper_portrait("Ezra", true, "no_such_look")).is_null()

func test_greeting_card_and_keeper_bar_take_the_keepers_look() -> void:
	var ui := _ui()
	await await_idle_frame()
	ui.set_view(_view())
	var ctx := {"keeper": "Ezra", "place": "Chestnut Market Square", "look": "market_temperate_1"}
	ui.open_keeper_greeting("market", ctx)
	var card: UiDialogueCard = ui._modal.find_children("*", "UiDialogueCard", true, false)[0]
	assert_object(card.portrait).is_same(P0CounterDrawer.keeper_portrait("Ezra", true, "market_temperate_1"))
	var drawer := P0CounterDrawer.new(_view(), "market", ctx)
	add_child(auto_free(drawer))
	assert_object(drawer.keeper_bar.portrait).is_same(P0CounterDrawer.keeper_portrait("Ezra", false, "market_temperate_1"))

## 上官婉儿 on #339: the drawn pictures are bounded — the most recent 8 cards and 24 heads (about 12 MB); a texture handed
## out stays valid after its entry is evicted, and asking again draws a fresh one.
func test_keeper_portrait_cache_is_bounded() -> void:
	var portraits = load("res://modules/p0/p0_keeper_portraits.gd")
	var looks: Array = P0Logic.content().get("world", {}).get("keeper_looks", {}).keys().filter(func(k): return not str(k).begins_with("_"))
	assert_int(looks.size()).is_greater(30)
	var first := P0CounterDrawer.keeper_portrait("Ezra", true, str(looks[0]))
	for look in looks: P0CounterDrawer.keeper_portrait("Ezra", true, str(look))
	for look in looks: P0CounterDrawer.keeper_portrait("Ezra", false, str(look))
	assert_int(portraits.kept(true)).is_less_equal(8)
	assert_int(portraits.kept(false)).is_less_equal(24)
	assert_object(first).is_not_null()   # still valid for whoever shows it
	assert_object(P0CounterDrawer.keeper_portrait("Ezra", true, str(looks[0]))).is_not_same(first)   # evicted: drawn again

## 不知火舞 on #339: the card's figure is 84–88 % of its height, the shoes 10–14 px (of the 220) above its foot, centred
## on its outline; a figure too wide for that (a wide hat) touches the sides instead, never cut.
func test_keeper_card_frames_the_figure_by_its_outline() -> void:
	var portraits = load("res://modules/p0/p0_keeper_portraits.gd")
	const W := 300.0
	const H := 660.0
	# a figure 400 px tall, off to the left and high in a first picture 2 m tall
	var outline := Rect2i(60, 90, 110, 400)
	var frame: Dictionary = portraits.card_frame(outline, 2.0)
	var per_px := 2.0 / H
	var at := func(frame: Dictionary, x: float, y: float) -> Vector2:   # a first-picture pixel in the final picture
		return Vector2(W * 0.5 + ((x - W * 0.5) * per_px - float(frame.right)) / float(frame.size) * H,
			H * 0.5 + ((y - H * 0.5) * per_px - float(frame.down)) / float(frame.size) * H)
	var top: Vector2 = at.call(frame, outline.position.x, outline.position.y)
	var feet: Vector2 = at.call(frame, outline.end.x, outline.end.y)
	var share := (feet.y - top.y) / H
	assert_float(share).is_between(0.84, 0.88)
	assert_float((H - feet.y) / 3.0).is_between(10.0, 14.0)   # 3× the 220 portrait
	assert_float((top.x + feet.x) * 0.5).is_equal_approx(W * 0.5, 0.5)
	# a wide hat: the width decides, the figure spans it exactly
	var wide := Rect2i(20, 150, 260, 300)
	frame = portraits.card_frame(wide, 2.0)
	var left: Vector2 = at.call(frame, wide.position.x, wide.position.y)
	var right: Vector2 = at.call(frame, wide.end.x, wide.end.y)
	assert_float(left.x).is_equal_approx(0.0, 0.5)
	assert_float(right.x).is_equal_approx(W, 0.5)
	assert_float((H - right.y) / 3.0).is_between(10.0, 14.0)
	assert_float((right.y - left.y) / H).is_less(0.84)
