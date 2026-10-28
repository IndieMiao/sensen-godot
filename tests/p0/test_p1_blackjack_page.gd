extends GdUnitTestSuite
## The Blackjack page (SGODOT-351, q(240) §9.18.7) driven through P0BlackjackMock as P0Runtime drives it with the
## server: a command goes out, the reply's view then its events come back. Motion off: every step lands at once.

var page: P0BlackjackPage
var bj: P0BlackjackMock
var sent: Array = []
var toasts: Array = []

func _open(coins: int, intro := true, last_bet := 0) -> void:
	bj = P0BlackjackMock.new(5)
	bj.intro = intro
	bj.last_bet = last_bet
	sent = []
	toasts = []
	page = auto_free(P0BlackjackPage.new(bj.decorate({"coins": coins})))
	page.theme = UiKit.theme()
	page.animate = false
	page.toast = func(t: String): toasts.append(t)
	page.size = Vector2(360, 800)
	page.command.connect(_send)
	add_child(page)
	page._layout()

func _send(cmd: Dictionary) -> void:
	sent.append(cmd)
	var r := bj.command(cmd, page.view)
	page.refresh(bj.decorate(r.state))
	if bool(r.ok): page.on_events(r.events)
	else: page.refused(str(r.code), r.get("detail", {}))

func _frames() -> void:
	await await_idle_frame()
	await await_idle_frame()

func _deal(deck: Array, bet: int) -> void:
	bj.next_deck = deck
	page.deal(bet)
	await _frames()

func _codes(cards: Array) -> Array: return cards.map(func(c): return (c as UiPlayingCard).card)

func test_tapping_chips_builds_the_bet_and_greys_what_would_break_the_floor() -> void:
	_open(300)
	assert_bool(page.deal_key.enabled).is_false()   # empty: the circle says Place a bet
	assert_str(page.deal_key.reason).is_equal("")
	assert_bool(page.empty_label.visible).is_true()
	page.tap_chip(3)   # 100
	page.tap_chip(1)
	page.tap_chip(1)
	assert_int(page.bet).is_equal(120)
	assert_str(page.deal_key.text).is_equal("Deal")   # no amount on the action (C13)
	assert_bool(page.deal_key.enabled).is_true()
	assert_str(page.bet_label.text).is_equal("120")
	assert_int(page.stacks[4].state).is_equal(UiChipToken.State.DISABLED)   # 500: 300 − 620 < 40
	assert_int(page.stacks[5].state).is_equal(UiChipToken.State.DISABLED)
	assert_int(page.stacks[3].state).is_equal(UiChipToken.State.DEFAULT)
	page.tap_chip(4)   # grey: nothing
	assert_int(page.bet).is_equal(120)
	page.tap_chip(3)   # 220 on: 100 more would leave 0, so 100 greys too
	assert_int(page.stacks[3].state).is_equal(UiChipToken.State.DISABLED)
	page.circle.tapped.emit()   # tapping the stake takes it all back (no Clear)
	assert_int(page.bet).is_equal(0)
	assert_int(page.stacks[3].state).is_equal(UiChipToken.State.DEFAULT)   # back at once
	assert_int(page.stacks[4].state).is_equal(UiChipToken.State.DISABLED)   # 500 never fits a 300 wallet

func _vp(local: Vector2) -> Vector2:
	return page.get_viewport().get_canvas_transform() * page.get_global_transform() * local

func _mouse(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = _vp(pos)
	return e

func _motion(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = _vp(pos)
	return e

func _chip_centre(i: int) -> Vector2:
	return page.stack_top(i)

func test_drag_into_the_circle_adds_and_outside_returns() -> void:
	_open(300)
	var from := _chip_centre(2)   # 50
	_push(_mouse(from, true))
	_push(_motion(from + Vector2(0, -30)))   # past the tap slop: a drag
	assert_object(page._ghost).is_not_null()
	assert_int(page.stacks[2].state).is_equal(UiChipToken.State.DEFAULT)   # the rail's stack stays
	var over := page.circle_center() + Vector2(0, UiChipToken.SIZE * 0.6 * page.table.scale.x)   # the ghost rides above the finger
	_push(_motion(over))
	assert_bool(page.circle.lit).is_true()
	_push(_mouse(over, false))
	assert_int(page.bet).is_equal(50)
	assert_bool(page.circle.lit).is_false()
	# outside: back to the rail, nothing added
	_push(_mouse(from, true))
	_push(_motion(from + Vector2(0, -30)))
	_push(_motion(Vector2(40, 200)))
	assert_bool(page.circle.lit).is_false()
	_push(_mouse(Vector2(40, 200), false))
	assert_int(page.bet).is_equal(50)
	assert_object(page._ghost).is_null()

func test_a_quick_press_without_moving_is_a_tap() -> void:
	_open(300)
	var at := _chip_centre(0)
	_push(_mouse(at, true))
	_push(_motion(at + Vector2(4, 0)))   # within the slop
	_push(_mouse(at + Vector2(4, 0), false))
	assert_int(page.bet).is_equal(5)

## Through the real dispatch (Viewport.push_input): the stack's gui_input gets its own local position, the finger's
## moves reach _input in window space. A press, a 4 px wobble inside the slop and a release is a tap (周瑜 on #525).
func _push(e: InputEvent) -> void:
	page.get_viewport().push_input(e, true)   # viewport coordinates (the runner window may be stretched)

func test_a_real_tap_with_a_small_wobble_still_adds() -> void:
	_open(300)
	var at := _chip_centre(3)   # 100
	_push(_mouse(at, true))
	assert_bool(page._press.is_empty()).is_false()
	_push(_motion(at + Vector2(4, 0)))
	assert_object(page._ghost).is_null()   # not a drag
	_push(_mouse(at + Vector2(4, 0), false))
	assert_int(page.bet).is_equal(100)

func test_a_real_drag_into_the_circle_adds() -> void:
	_open(300)
	var from := _chip_centre(2)   # 50
	_push(_mouse(from, true))
	_push(_motion(from + Vector2(0, -30)))
	assert_object(page._ghost).is_not_null()
	var over := page.circle_center() + Vector2(0, UiChipToken.SIZE * 0.6 * page.table.scale.x)
	_push(_motion(over))
	assert_bool(page.circle.lit).is_true()
	_push(_mouse(over, false))
	assert_int(page.bet).is_equal(50)

func test_a_double_shows_the_doubled_stake() -> void:
	_open(500)
	await _deal(["6S", "9D", "5H", "TC", "KD"], 50)   # 11 against 9: double → 21; dealer 19
	page.act("double")
	await _frames()
	var tag := (page._hands[0].tag as UiBadge).text
	assert_str(tag).is_equal("You win")
	assert_int(page._hands[0].bet).is_equal(100)   # the stake as settled, doubled
	assert_str(page.coins_label.text).is_equal("600")

func test_a_grey_chip_takes_neither_tap_nor_drag() -> void:
	_open(300)
	page.tap_chip(3)
	page.tap_chip(3)   # 200 on: 50 is the most that keeps 40 (300 − 260 = 40)
	assert_int(page.stacks[3].state).is_equal(UiChipToken.State.DISABLED)
	var at := _chip_centre(3)
	_push(_mouse(at, true))
	assert_bool(page._press.is_empty()).is_true()

func test_deal_stand_and_result() -> void:
	_open(500)
	await _deal(["9S", "7D", "8H", "TC"], 120)
	assert_dict(sent[-1]).is_equal({"type": "bj_deal", "bet": 120})
	assert_int(page.phase).is_equal(P0BlackjackPage.Phase.PLAY)
	assert_array(_codes(page._hands[0].cards)).is_equal(["9S", "8H"])
	assert_array(_codes(page._dealer_cards)).is_equal(["7D", ""])
	assert_str(page.coins_label.text).is_equal("380")
	assert_str(page.double_key.text).is_equal("Double")
	assert_bool(page.split_key.enabled).is_false()
	assert_str(page.split_key.reason).is_equal("Pairs only")
	page.act("stand")
	await _frames()
	assert_array(_codes(page._dealer_cards)).is_equal(["7D", "TC"])   # the cards stay until the next deal
	assert_str((page._hands[0].tag as UiBadge).text).is_equal("Push")
	_assert_tone(page._hands[0].tag, UiTokens.COLOR_TILE_CORE, UiTokens.COLOR_SECONDARY)   # StateBadge Stranger, 192:170359
	assert_str(page.coins_label.text).is_equal("500")
	# then last hand's stake sets itself in the circle and Deal deals again
	assert_int(page.phase).is_equal(P0BlackjackPage.Phase.BET)
	assert_int(page.bet).is_equal(120)
	assert_bool(page.deal_key.visible and page.deal_key.enabled).is_true()
	page.deal_key.press()
	assert_dict(sent[-1]).is_equal({"type": "bj_deal", "bet": 120})

func test_blackjack_settles_in_the_deal() -> void:
	_open(500)
	await _deal(["AS", "7D", "KH", "9C"], 5)
	assert_str((page._hands[0].tag as UiBadge).text).is_equal("Blackjack")
	_assert_tone(page._hands[0].tag, UiTokens.COLOR_GOLD, UiTokens.COLOR_TEXT)   # StateBadge Kindred, 191:169997
	_assert_tone(page._hands[0].badge, UiTokens.COLOR_PRIMARY_TINT, UiTokens.COLOR_PRIMARY)   # points: Default
	assert_str(page.coins_label.text).is_equal("507")

func test_the_rebet_steps_down_when_short() -> void:
	_open(200)
	await _deal(["9S", "KD", "8H", "TC"], 120)   # 17 against 20: lose, 80 left
	page.act("stand")
	await _frames()
	assert_str(page.coins_label.text).is_equal("80")
	assert_int(page.bet).is_equal(40)   # 120 stepped down to keep 40, never back up on its own
	assert_str((page._hands[0].tag as UiBadge).text).is_equal("You lose")
	_assert_tone(page._hands[0].tag, UiTokens.COLOR_DANGER_TINT, UiTokens.COLOR_DANGER)   # StateBadge Danger, 183:166912

func test_split_lays_two_hands_and_plays_left_first() -> void:
	_open(600)
	await _deal(["8S", "6D", "8H", "TC", "3S", "2H", "TD", "9C"], 120)
	page.act("split")
	await _frames()
	assert_int(page._hands.size()).is_equal(2)
	assert_array(_codes(page._hands[0].cards)).is_equal(["8S", "3S"])
	assert_array(_codes(page._hands[1].cards)).is_equal(["8H", "2H"])
	assert_int(page._active).is_equal(0)
	assert_bool(page._hands[0].outline.visible).is_true()
	assert_str(page.double_key.reason).is_equal("Not after a split")
	page.act("stand")
	await _frames()
	assert_int(page._active).is_equal(1)
	assert_bool(page._hands[1].outline.visible).is_true()

func test_low_on_coins_is_the_closed_table() -> void:
	_open(43)
	assert_bool(page.low_label.visible).is_true()
	assert_bool(page.circle.visible).is_false()
	assert_bool(page.low_need.visible).is_true()
	assert_str(page.low_need.text).is_equal("Need 2 more coins")
	assert_bool(page.deal_key.enabled).is_false()
	for c in page.stacks: assert_int((c as UiChipStack).state).is_equal(UiChipToken.State.DISABLED)

func test_a_hand_in_play_comes_back_as_it_was() -> void:
	bj = P0BlackjackMock.new(5)
	bj.next_deck = ["9S", "7D", "8H", "TC"]
	var v := bj.decorate({"coins": 500})
	var r := bj.command({"type": "bj_deal", "bet": 50}, v)
	page = auto_free(P0BlackjackPage.new(bj.decorate(r.state)))
	page.theme = UiKit.theme()
	page.animate = false
	page.size = Vector2(360, 800)
	add_child(page)
	page._layout()
	assert_int(page.phase).is_equal(P0BlackjackPage.Phase.PLAY)
	assert_array(_codes(page._hands[0].cards)).is_equal(["9S", "8H"])
	assert_bool(page.hit_key.visible).is_true()

func test_an_expired_hand_settles_on_open_with_the_notice() -> void:
	_open(500)
	await _deal(["9S", "7D", "8H", "TC"], 50)
	bj.expire()
	page.refresh(bj.decorate(bj.command({"type": "bj_intro"}, page.view).state))   # a view showing it expired
	await _frames()
	assert_bool(page.hit_key.visible).is_false()
	_send({"type": "bj_open"})
	await _frames()
	assert_int(page.phase).is_equal(P0BlackjackPage.Phase.BET)
	assert_bool(page.settled_pill.visible).is_true()
	assert_str(page.settled_label.text).starts_with("Last hand settled · ")

func test_first_open_shows_the_card_and_got_it_records_it() -> void:
	_open(300, false)
	page.opened()
	assert_dict(sent[-1]).is_equal({"type": "bj_open"})
	assert_bool(page.intro_layer.visible).is_true()
	# BJ-INTRO-T 193:171383: title and two paragraphs left-aligned, the body Regular 14 grey; `least 40` kept together
	assert_int(page.intro_card.title.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_LEFT)
	assert_int(page.intro_card.body.horizontal_alignment).is_equal(HORIZONTAL_ALIGNMENT_LEFT)
	assert_str(str(page.intro_card.body.theme_type_variation)).is_equal(str(UiTokens.STYLE_BODY_R14))
	assert_str(page.intro_card.body.text).is_equal("Tap or drag chips onto the circle, then tap Deal.")
	assert_str(page.intro_floor.text).ends_with("least" + P0BlackjackPage.NBSP + "40.")
	assert_object(page.intro_floor.get_parent()).is_same(page.intro_card.body.get_parent())
	page.intro_card.primary_pressed.emit()
	assert_bool(page.intro_layer.visible).is_false()
	assert_dict(sent[-1]).is_equal({"type": "bj_intro"})
	assert_bool(bj.intro).is_true()

func test_rules_sheet_and_back() -> void:
	_open(300)
	page.open_rules()
	assert_bool(page.rules_layer.visible).is_true()
	# RULES-T 193:171390: a sheet over the table's lower half (454 there), never the whole screen (its rules were
	# measured at width 0 while the layer was hidden); numbered, Close at the foot
	assert_float(page.rules_sheet.height).is_between(300.0, 560.0)
	var texts: Array = page.rules_sheet.body.get_children().filter(func(c): return c is Label).map(func(l): return l.text)
	assert_str(str(texts[1])).starts_with("1. Get closer to 21")
	var close := page.rules_sheet.body.get_children().filter(func(c): return c is UiDismissButton)[0] as UiDismissButton
	assert_str(close.text).is_equal("Close")
	close.pressed.emit()
	assert_bool(page.rules_layer.visible).is_false()
	page.open_rules()
	assert_bool(page.back_inner()).is_true()
	assert_bool(page.rules_layer.visible).is_false()
	assert_bool(page.back_inner()).is_false()

func test_a_refusal_says_what_is_short() -> void:
	_open(300)
	page.refused("bj_no_coins", {"need": 15})
	assert_array(toasts).is_equal(["Need 15 more coins"])

## 0.2.13's client can go out before the card room's server (奕星 / 后裔 on 351): an older server sends no
## view.blackjack and answers a bj_ command with unknown_command. Its pin keeps the table out of reach (#523); were the
## page opened all the same (a dev step), it lays out on the defaults, says nothing and stays in the bet, no error.
func test_an_older_server_without_the_table_breaks_nothing() -> void:
	sent = []
	toasts = []
	page = auto_free(P0BlackjackPage.new({"coins": 300}))
	page.theme = UiKit.theme()
	page.animate = false
	page.toast = func(t: String): toasts.append(t)
	page.size = Vector2(360, 800)
	page.command.connect(func(cmd: Dictionary): sent.append(cmd))
	add_child(page)
	page._layout()
	page.opened()
	assert_dict(sent[-1]).is_equal({"type": "bj_open"})
	assert_bool(page.intro_layer.visible).is_false()   # nothing says it is unseen
	page.refused("unknown_command", {})
	page.refresh({"coins": 300, "seq": 2})
	await _frames()
	page.tap_chip(1)
	assert_int(page.bet).is_equal(10)
	page.deal(page.bet)
	assert_dict(sent[-1]).is_equal({"type": "bj_deal", "bet": 10})
	page.refused("unknown_command", {})
	page.refresh({"coins": 300, "seq": 3})
	await _frames()
	assert_int(page.phase).is_equal(P0BlackjackPage.Phase.BET)
	assert_int(page.bet).is_equal(10)
	assert_bool(page._waiting).is_false()
	assert_array(toasts).is_empty()

## A result plate / points badge is the StateBadge in its frame's tone (不知火舞 351 ed79b57c): fill and ink.
func _assert_tone(b: UiBadge, fill: Color, ink: Color) -> void:
	assert_bool(b.visible).is_true()
	assert_object((b.get_theme_stylebox(&"panel") as UiStyleBox).bg_color).is_equal(fill)
	var l := b.find_children("*", "Label", true, false)[0] as Label
	assert_object(l.get_theme_color(&"font_color")).is_equal(ink)

## 不知火舞 351 ed79b57c ①: back, coins and Rules are one row under the safe area, centred on one line (BJ-BET-T
## 187:167298 at y 50), on a phone with a notch and on a wider screen whose table crops from the top.
func test_back_coins_and_rules_share_a_row_under_the_safe_area() -> void:
	for case in [[Vector2(360, 800), 0.0], [Vector2(360, 800), 40.0], [Vector2(412, 860), 32.0]]:
		var bj2 := P0BlackjackMock.new(5)
		var p: P0BlackjackPage = auto_free(P0BlackjackPage.new(bj2.decorate({"coins": 300}), case[1]))
		p.theme = UiKit.theme()
		p.animate = false
		p.size = case[0]
		add_child(p)
		p._layout()
		var row: float = case[1] + 50.0
		var why := "%s safe %d" % [case[0], case[1]]
		assert_float(p.back_key.get_global_rect().get_center().y).append_failure_message(why).is_equal_approx(row, 0.5)
		assert_float(p.coins_pill.get_global_rect().get_center().y).append_failure_message(why).is_equal_approx(row, 0.5)
		assert_float(p.rules_key.get_global_rect().get_center().y).append_failure_message(why).is_equal_approx(row, 0.5)
		assert_float(p.rules_key.get_global_rect().get_center().x).append_failure_message(why) \
			.is_equal_approx(p.on_page(Vector2(173, 0)).x, 0.5)

# ---- settling the circle (不知火舞 351 d1969a60, a): motion on, polled in real time

func _until(cond: Callable, ms := 4000) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > ms: return false
		await await_millis(16)
	return true

func _pile_values() -> Array: return page.circle.piles().map(func(p): return p.values)

func test_a_win_clears_the_circle_to_the_rail_then_the_stake_flies_back() -> void:
	_open(500)
	await _deal(["TS", "7D", "KH", "TC"], 100)   # 20 against 17: stand wins
	page.animate = true
	page.act("stand")
	assert_bool(await _until(func(): return page.phase == P0BlackjackPage.Phase.RESULT)).is_true()
	assert_str((page._hands[0].tag as UiBadge).text).is_equal("You win")
	assert_array(_pile_values()).is_empty()   # the stake left the circle, with the winnings beside it
	assert_bool(page._leaving.any(func(n): return is_instance_valid(n) and n is UiChipStack and (n as UiChipStack).values == P0Blackjack.chips_for(100))).is_true()
	assert_bool(is_instance_valid(page._winnings)).is_true()
	# nothing is printed or takes a tap until the stake is back
	assert_bool(page.deal_key.visible or page.empty_label.visible).is_false()
	page.tap_chip(1)
	page.circle.tapped.emit()
	assert_int(page.bet).is_equal(100)
	assert_bool(await _until(func(): return page.bet_label.modulate.a < 0.05, 2000)).is_true()   # the amount fades
	assert_bool(await _until(func(): return page.phase == P0BlackjackPage.Phase.BET)).is_true()
	assert_array(_pile_values()).is_equal([P0Blackjack.chips_for(100)])
	assert_str(page.bet_label.text).is_equal("100")
	assert_float(page.bet_label.modulate.a).is_equal(1.0)
	assert_bool(page.deal_key.visible and page.deal_key.enabled).is_true()

func test_a_loss_slides_to_the_dealer_and_a_win_waits_for_its_winnings() -> void:
	_open(500)
	page.animate = true
	page._set_stack(50)
	assert_float(page._clear_circle([{"net": -50}], false)).is_equal_approx(0.8, 0.001)   # PENDING 300 + DRAWER × 2
	var lost: UiChipStack = page._leaving[-1]
	assert_array(_pile_values()).is_empty()
	page._set_stack(50)
	assert_float(page._clear_circle([{"net": 50}], true)).is_equal_approx(1.05, 0.001)   # winnings in 500 + 300, DRAWER
	page.circle.set_split([[50], [50]])
	assert_float(page._clear_circle([{"net": 50}, {"net": -50}], true)).is_equal_approx(1.05, 0.001)   # both at once
	assert_int(page._leaving.size()).is_equal(4)
	await await_millis(1000)
	assert_bool(is_instance_valid(lost)).is_false()   # gone toward the dealer, faded

func test_a_push_on_one_hand_stays_in_the_circle() -> void:
	_open(500)
	await _deal(["9S", "7D", "8H", "TC"], 120)   # 17 against 17
	page.animate = true
	page.act("stand")
	assert_bool(await _until(func(): return page.phase == P0BlackjackPage.Phase.BET)).is_true()
	assert_str((page._hands[0].tag as UiBadge).text).is_equal("Push")
	assert_array(page._leaving).is_empty()   # no clearing, no flight back
	assert_array(_pile_values()).is_equal([P0Blackjack.chips_for(120)])

func test_a_doubled_push_goes_to_the_rail_and_last_bet_comes_back() -> void:
	_open(500)
	await _deal(["6S", "7D", "5H", "TC", "6C"], 50)   # 11 doubles to 17 against 17
	page.animate = true
	page.act("double")
	assert_bool(await _until(func(): return page.phase == P0BlackjackPage.Phase.RESULT)).is_true()
	assert_str((page._hands[0].tag as UiBadge).text).is_equal("Push")
	assert_array(_pile_values()).is_empty()
	assert_bool(await _until(func(): return page.phase == P0BlackjackPage.Phase.BET)).is_true()
	assert_int(page.bet).is_equal(50)   # the bet dealt, not the doubled stake
	assert_array(_pile_values()).is_equal([P0Blackjack.chips_for(50)])

func test_a_loss_that_leaves_too_little_ends_on_low_on_coins_after_the_beat() -> void:
	_open(90)
	await _deal(["9S", "KD", "8H", "TC"], 50)   # 17 against 20: 40 left, not even 5 above the floor
	page.animate = true
	page.act("stand")
	assert_bool(await _until(func(): return page.phase == P0BlackjackPage.Phase.RESULT and page.circle.piles().is_empty())).is_true()
	await await_millis(900)   # the stake has gone (800 ms); the empty beat runs to ~1.4 s: nothing printed yet
	assert_bool(page.low_label.visible).is_false()
	assert_bool(await _until(func(): return page.phase == P0BlackjackPage.Phase.BET)).is_true()
	assert_int(page.bet).is_equal(0)
	assert_bool(page.low_label.visible).is_true()
	assert_bool(page._leaving.any(func(n): return is_instance_valid(n) and n is UiChipToken)).is_false()   # nothing flew in

func test_opening_on_last_bet_draws_the_stake_in_the_circle() -> void:
	bj = P0BlackjackMock.new(5)
	bj.last_bet = 50
	page = auto_free(P0BlackjackPage.new(bj.decorate({"coins": 500})))
	page.theme = UiKit.theme()
	page.animate = false
	page.size = Vector2(360, 800)
	page._layout()   # laid out before it is in the tree, as P0Ui sizes it
	add_child(page)
	var at: Vector2 = page.circle.piles()[0].at
	assert_vector(at).is_equal((page.circle.size - Vector2(UiChipToken.SIZE, UiChipToken.SIZE)) * 0.5)

func test_a_big_stake_flies_in_as_the_chips_the_circle_draws() -> void:
	_open(5000)
	page.animate = true
	page.phase = P0BlackjackPage.Phase.RESULT
	page._step_rebet(1785)   # 1K 500 100 100 100 50 10 10 10 5: more than the circle draws
	var flown: Array = page._leaving.filter(func(n): return is_instance_valid(n) and n is UiChipToken).map(func(n): return (n as UiChipToken).value)
	var chips := P0Blackjack.chips_for(1785)
	assert_array(flown).is_equal(chips.slice(chips.size() - P0Blackjack.CIRCLE_MAX))
