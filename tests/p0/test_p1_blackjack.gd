extends GdUnitTestSuite
## The card room's Blackjack (SGODOT-351, q(238)/(240)): what the page reads from the view (P0Blackjack) and the
## development mock that answers bj_* as the server contract says (351 b610f98a).

func _view(coins: int, hand = null, extra := {}) -> Dictionary:
	var bj := {"open": true, "intro": true, "floor": 40, "min_bet": 5, "step": 5, "chips": P0Blackjack.CHIPS,
		"last_bet": 0, "hand": hand, "last": null}
	bj.merge(extra, true)
	return {"coins": coins, "blackjack": bj}

func test_totals_soft_and_bust() -> void:
	assert_str(P0Blackjack.badge(["AS", "6H"])).is_equal("7 / 17")
	assert_str(P0Blackjack.badge(["AS", "KH"])).is_equal("21")
	assert_str(P0Blackjack.badge(["AS", "6H", "TD"])).is_equal("17")
	assert_str(P0Blackjack.badge(["KS", "QH", "5D"])).is_equal("Bust")
	assert_str(P0Blackjack.badge(["AS", "AH"])).is_equal("2 / 12")
	assert_str(P0Blackjack.badge(["KD", ""])).is_equal("10")   # the dealer's up card only
	assert_str(P0Blackjack.badge(["", ""])).is_equal("")

func test_copy_formats() -> void:
	assert_str(P0Blackjack.comma(1250)).is_equal("1,250")
	assert_str(P0Blackjack.comma(120)).is_equal("120")
	assert_str(P0Blackjack.comma(1000000)).is_equal("1,000,000")
	assert_str(P0Blackjack.chip_label(1000)).is_equal("1K")
	assert_str(P0Blackjack.chip_label(500)).is_equal("500")
	assert_str(P0Blackjack.float_text(7)).is_equal("+7 coins")
	assert_str(P0Blackjack.float_text(0)).is_equal("")
	assert_str(P0Blackjack.float_text(-20)).is_equal("")
	assert_str(P0Blackjack.settled_line({"net": 20})).is_equal("Last hand settled · You win +20 coins")
	assert_str(P0Blackjack.settled_line({"net": -20})).is_equal("Last hand settled · You lose")
	assert_str(P0Blackjack.rank_text("TH")).is_equal("10")

func test_chips_keep_the_floor() -> void:
	var v := _view(300)
	assert_bool(P0Blackjack.can_add(v, 120, 100)).is_true()    # 300 − 220 = 80
	assert_bool(P0Blackjack.can_add(v, 120, 500)).is_false()   # BJ-BET-CAP: 500 and 1K grey
	assert_bool(P0Blackjack.can_add(v, 255, 5)).is_true()      # 40 left
	assert_bool(P0Blackjack.can_add(v, 260, 5)).is_false()

func test_low_on_coins_is_the_only_closed_state() -> void:
	var v := _view(43)   # BJ-LOW
	assert_bool(P0Blackjack.low_on_coins(v)).is_true()
	assert_dict(P0Blackjack.deal_key(v, 0)).is_equal({"label": "Deal", "reason": "Need 2 more coins"})
	assert_bool(P0Blackjack.low_on_coins(_view(45))).is_false()

func test_deal_key() -> void:
	assert_dict(P0Blackjack.deal_key(_view(300), 0)).is_equal({"label": "Deal", "reason": "Place a bet"})
	assert_dict(P0Blackjack.deal_key(_view(300), 120)).is_equal({"label": "Deal · 120", "reason": ""})
	assert_dict(P0Blackjack.deal_key(_view(5000), 1250)).is_equal({"label": "Deal · 1,250", "reason": ""})

## q(320) (the user 11-13, 丙): the server's view.blackjack.day {net, limit, left, closed, opens_at}, at the view's clock.
const NOW := 1_800_000_000_000.0
const OPENS := NOW + (5 * 60 + 12) * 60000.0

func _day_view(coins: int, net: int, now := NOW) -> Dictionary:
	var left := maxi(0, 50 + net)
	left -= left % 5
	var v := _view(coins, null, {"day": {"net": net, "limit": 50, "left": left, "closed": left < 5, "opens_at": OPENS}})
	v["now"] = now
	return v

## What is left to lose greys the chips over it as the floor does (no words, 不知火舞 11-13) and caps the rebet; an older
## server sends no day: no limit.
func test_chips_and_the_rebet_keep_inside_the_days_loss() -> void:
	assert_int(P0Blackjack.day_left(_view(300))).is_equal(-1)
	assert_bool(P0Blackjack.can_add(_view(300), 120, 100)).is_true()   # no day: the wallet alone
	assert_bool(P0Blackjack.day_closed(_view(300))).is_false()
	var v := _day_view(300, -38)   # 10 left
	assert_bool(P0Blackjack.can_add(v, 5, 5)).is_true()
	assert_bool(P0Blackjack.can_add(v, 10, 5)).is_false()
	assert_bool(P0Blackjack.can_add(v, 0, 50)).is_false()
	assert_int(P0Blackjack.deal_again_bet(v, 120)).is_equal(10)
	assert_bool(P0Blackjack.day_closed(v)).is_false()
	var shut := _day_view(300, -46)
	assert_bool(P0Blackjack.day_closed(shut)).is_true()
	assert_int(P0Blackjack.deal_again_bet(shut, 120)).is_equal(0)
	assert_bool(P0Blackjack.can_add(shut, 0, 5)).is_false()
	assert_int(P0Blackjack.deal_again_bet(_day_view(142, 200), 120)).is_equal(100)   # 250 left: the wallet the lower
	assert_bool(P0Blackjack.can_add(_day_view(2000, 500), 0, 500)).is_true()   # up 500: the 500 lights (q(320) risk)

## `Today −20` / `Today +35` under the pill (U+2212, none at 0); `Opens in 5h 12m` to the day change; past it (the page
## left open over 04:00) a new day: nothing lost, the table open, as the next command finds it.
func test_today_and_the_day_change() -> void:
	assert_str(P0Blackjack.today_text(_day_view(300, -20))).is_equal("Today \u221220")
	assert_str(P0Blackjack.today_text(_day_view(300, 35))).is_equal("Today +35")
	assert_str(P0Blackjack.today_text(_day_view(5000, 1300))).is_equal("Today +1,300")
	assert_str(P0Blackjack.today_text(_day_view(300, 0))).is_equal("")
	assert_str(P0Blackjack.today_text(_view(300))).is_equal("")
	assert_str(P0Blackjack.opens_in(_day_view(300, -46))).is_equal("Opens in 5h 12m")
	assert_str(P0Blackjack.opens_in(_day_view(300, -46, OPENS - 30 * 1000.0))).is_equal("Opens in 1m")
	assert_str(P0Blackjack.opens_in(_view(300))).is_equal("")
	var next := _day_view(300, -46, OPENS)
	assert_bool(P0Blackjack.day_closed(next)).is_false()
	assert_int(P0Blackjack.day_left(next)).is_equal(50)
	assert_str(P0Blackjack.today_text(next)).is_equal("")
	assert_int(P0Blackjack.deal_again_bet(next, 20)).is_equal(20)

## Lou's opening line with the table closed for the day (9.18.7 ⑤), over the short-of-coins one when both hold.
func test_lou_says_the_table_is_done_for_the_day() -> void:
	var v := _day_view(300, -46)
	assert_str(str(P0Logic.keeper_lines(v, "casino").greet)).is_equal("That's enough cards for one day. Table opens in 5h 12m.")
	assert_str(str(P0Logic.keeper_lines(_day_view(43, -46), "casino").greet)).is_equal("That's enough cards for one day. Table opens in 5h 12m.")
	assert_str(str(P0Logic.keeper_lines(_day_view(300, -45), "casino").greet)).is_equal("Pull up a chair. Care for a hand?")
	assert_str(str(P0Logic.keeper_lines(_day_view(43, -45), "casino").greet)).is_equal("Keep those coins for seeds. Come back with a few more.")

func test_mock_keeps_the_days_loss_when_set() -> void:
	var m := P0BlackjackMock.new(1)
	assert_that(m.decorate({"coins": 1000}).blackjack.day).is_null()   # unset: no limit, as an older server
	m = P0BlackjackMock.new(1)
	m.day_loss = 50
	m.day_net = -38
	var st := {"coins": 1000, "now": NOW}
	var r := m.command({"type": "bj_deal", "bet": 15}, st)
	assert_str(str(r.get("code", ""))).is_equal("bj_day_cap")
	assert_dict(r.detail).is_equal({"cap": "loss", "net": -38, "resets_at": OPENS})   # the server's shape
	var day: Dictionary = m.decorate(st.duplicate()).blackjack.day
	assert_dict(day).is_equal({"net": -38, "limit": 50, "left": 10, "closed": false, "opens_at": OPENS})
	m.day_net = -46
	assert_bool(bool(m.decorate(st.duplicate()).blackjack.day.closed)).is_true()

func test_deal_again_steps_down_to_what_keeps_40() -> void:
	assert_int(P0Blackjack.deal_again_bet(_view(300), 120)).is_equal(120)
	assert_int(P0Blackjack.deal_again_bet(_view(142), 120)).is_equal(100)   # 102 → 100
	assert_int(P0Blackjack.deal_again_bet(_view(44), 120)).is_equal(0)
	assert_int(P0Blackjack.deal_again_bet(_view(300), 0)).is_equal(0)

func test_action_keys_say_why_they_are_grey() -> void:
	var hand := {"active": 0, "hands": [{"cards": ["7S", "9H"], "bet": 120, "doubled": false, "state": "playing"}],
		"dealer": ["KD", ""], "actions": ["hit", "stand"], "blocked": {"double": "coins", "split": "pairs_only"},
		"need": {"double": 20, "split": 20}}
	var keys := P0Blackjack.action_keys(_view(140, hand))
	assert_dict(keys.hit).is_equal({"label": "Hit", "reason": "", "enabled": true})
	assert_dict(keys.double).is_equal({"label": "Double · 120", "reason": "Need 20 more coins", "enabled": false})
	assert_dict(keys.split).is_equal({"label": "Split · 120", "reason": "Pairs only", "enabled": false})
	hand.blocked = {"double": "first_two", "split": "one_split"}
	keys = P0Blackjack.action_keys(_view(500, hand))
	assert_str(keys.double.reason).is_equal("First two cards only")
	assert_str(keys.split.reason).is_equal("One split per hand")
	hand.blocked = {"double": "after_split", "split": "split_aces"}
	keys = P0Blackjack.action_keys(_view(500, hand))
	assert_str(keys.double.reason).is_equal("Not after a split")
	assert_str(keys.split.reason).is_equal("Split aces get one card")

func test_chips_for_a_stake() -> void:
	assert_array(P0Blackjack.chips_for(120)).is_equal([100, 10, 10])
	assert_array(P0Blackjack.chips_for(1255)).is_equal([1000, 100, 100, 50, 5])

# ---------------------------------------------------------------- the mock, as the contract

func _mock(coins := 300) -> Array:
	var m := P0BlackjackMock.new(7)
	var v := m.decorate({"coins": coins})
	return [m, v]

## One command through the mock as P0Session does: the reply's state decorated again.
func _send(m: P0BlackjackMock, v: Dictionary, cmd: Dictionary) -> Dictionary:
	var r := m.command(cmd, v)
	if r.has("state"): r.state = m.decorate(r.state)
	return r

func test_mock_deal_takes_the_stake_and_hides_the_hole() -> void:
	var mv := _mock()
	var m: P0BlackjackMock = mv[0]
	m.next_deck = ["9S", "7D", "8H", "TC", "2S"]
	var r := _send(m, mv[1], {"type": "bj_deal", "bet": 120})
	assert_bool(r.ok).is_true()
	assert_int(r.state.coins).is_equal(180)
	var h: Dictionary = r.state.blackjack.hand
	assert_array(h.dealer).is_equal(["7D", ""])
	assert_array(h.hands[0].cards).is_equal(["9S", "8H"])
	assert_array(r.events.map(func(e): return e.kind)).is_equal(["coins", "bj_dealt"])
	r = _send(m, r.state, {"type": "bj_act", "action": "stand"})
	var res: Dictionary = r.events.filter(func(e): return e.kind == "bj_result")[0]
	assert_str(res.hands[0].result).is_equal("push")   # 17 against the dealer's 17
	assert_int(r.state.coins).is_equal(300)
	assert_object(r.state.blackjack.hand).is_null()

func test_mock_blackjack_pays_3_to_2_rounded_down() -> void:
	var mv := _mock()
	var m: P0BlackjackMock = mv[0]
	m.next_deck = ["AS", "7D", "KH", "9C"]
	var r := _send(m, mv[1], {"type": "bj_deal", "bet": 5})
	var res: Dictionary = r.events.filter(func(e): return e.kind == "bj_result")[0]
	assert_str(res.why).is_equal("blackjack")
	assert_int(res.hands[0].payout).is_equal(12)   # 5 + floor(7.5)
	assert_int(res.net).is_equal(7)
	assert_int(r.state.coins).is_equal(307)

func test_mock_refuses_under_the_floor_and_bad_bets() -> void:
	var mv := _mock(100)
	var m: P0BlackjackMock = mv[0]
	var r := _send(m, mv[1], {"type": "bj_deal", "bet": 65})
	assert_str(r.code).is_equal("bj_no_coins")
	assert_int(r.detail.need).is_equal(5)
	assert_int(r.state.coins).is_equal(100)
	assert_str(_send(m, mv[1], {"type": "bj_deal", "bet": 7}).code).is_equal("bj_bad_bet")

func test_mock_split_makes_two_hands() -> void:
	var mv := _mock(500)
	var m: P0BlackjackMock = mv[0]
	m.next_deck = ["8S", "6D", "8H", "TC", "3S", "2H", "TD"]
	var r := _send(m, mv[1], {"type": "bj_deal", "bet": 50})
	r = _send(m, r.state, {"type": "bj_act", "action": "split"})
	assert_bool(r.ok).is_true()
	var h: Dictionary = r.state.blackjack.hand
	assert_int(h.hands.size()).is_equal(2)
	assert_array(h.hands[0].cards).is_equal(["8S", "3S"])
	assert_array(h.hands[1].cards).is_equal(["8H", "2H"])
	assert_int(r.state.coins).is_equal(400)
	assert_str(h.blocked.get("split", "")).is_equal("one_split")

func test_the_mock_never_runs_in_an_exported_package() -> void:
	var exported := func(f: String) -> bool: return f in ["android", "template", "template_release"]
	var editor := func(f: String) -> bool: return f == "editor"
	assert_bool(P0BlackjackMock.allowed(exported, true)).is_false()
	assert_bool(P0BlackjackMock.allowed(editor, true)).is_true()
	assert_bool(P0BlackjackMock.allowed(editor, false)).is_false()
