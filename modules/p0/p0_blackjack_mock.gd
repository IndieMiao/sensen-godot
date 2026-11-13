class_name P0BlackjackMock
extends RefCounted
## Development stand-in for the server's Blackjack (SGODOT-351, contract 后裔 on 351 b610f98a), so the page, its
## gestures and its motion can be built before the server branch runs. Off unless P0_BJ_MOCK=1 or user://p0_bj_mock
## exists (or a test turns it on), and only in the editor binary: an exported package (debug or release template) has
## no "editor" feature, so the mock can never answer there. P0Session hands it the bj_* commands and every view it receives: it answers the
## commands locally ({ok, state, events} or a refusal, the contract's shapes) and lays its own `blackjack` and the coins
## it moved over the real view. Rules as §3: 4 decks reshuffled each hand, S17, peek on A / 10, 3:2 rounded down,
## double on the first two, one split (split aces one card each). Never ships enabled: nothing here is persisted.

const FILE := "user://p0_bj_mock"

static func wanted() -> bool:
	return allowed(OS.has_feature, OS.get_environment("P0_BJ_MOCK") == "1" or FileAccess.file_exists(FILE))

## The switch counts only where `has_feature("editor")` (development runs); exported builds ignore it.
static func allowed(has_feature: Callable, switched_on: bool) -> bool:
	return switched_on and bool(has_feature.call("editor"))

var floor_coins := 40
## q(320) (the user 11-13, v3 丙) as the server holds it, when set (50): no deal past the day's loss by its own stake;
## this run's net stands for the day's (the mock keeps no day). -1, the default: no cap — the page's other states are
## built and shot with larger stakes; a test or a shot of the cap sets it.
var day_loss := -1
var day_net := 0
var intro := false
var n := 0
var last_bet := 0
var last = null
## Coins the mock has taken or paid, laid over the real view's coins.
var delta := 0
## The next hand's cards in dealing order (player, dealer up, player, dealer hole, then draws); [] shuffles.
var next_deck: Array = []
## Wallet to use when the real view has none (offline shots).
var seed_coins := 300
var rng := RandomNumberGenerator.new()

var _hand := {}   # {hands:[{cards, bet, doubled, state, split}], dealer:[up, hole], deck, active, expired}

func _init(seed_ := 0) -> void:
	if seed_ != 0: rng.seed = seed_
	else: rng.randomize()

## The real (or projected) view with the mock's Blackjack laid on it. Marks it so it is decorated once.
func decorate(state: Dictionary) -> Dictionary:
	if state.get("_bj_mock", false): return state
	state["coins"] = int(state.get("coins", seed_coins)) + delta
	state["blackjack"] = _view(int(state.coins))
	state["_bj_mock"] = true
	return state

## Expire the hand in play (换日 / 24 h): the next bj_open settles it as all standing.
func expire() -> void:
	if not _hand.is_empty(): _hand.expired = true

## One bj_* command against the decorated view `state`; the reply as the server would send it.
func command(cmd: Dictionary, state: Dictionary) -> Dictionary:
	# the real coins under the overlay: the reply carries them bare and decorate() lays the new delta on again
	_base = int(state.get("coins", seed_coins)) - (delta if state.get("_bj_mock", false) else 0)
	var coins := _base + delta
	var events: Array = []
	var type := str(cmd.get("type", ""))
	if not _hand.is_empty() and bool(_hand.get("expired", false)) and type in ["bj_open", "bj_act"]:
		events.append_array(_settle("expired", coins))
		if type == "bj_act": return _reply(state, events)
	match type:
		"bj_open":
			if last is Dictionary:
				var r: Dictionary = last
				r["why"] = "expired"
				events.append({"kind": "bj_result"}.merged(r))
				last = null
		"bj_intro":
			intro = true
		"bj_deal":
			var bet = cmd.get("bet", 0)
			if typeof(bet) != TYPE_INT and typeof(bet) != TYPE_FLOAT or int(bet) < 5 or int(bet) % 5 != 0:
				return _refuse(state, "bj_bad_bet", {})
			if not _hand.is_empty(): return _refuse(state, "bj_in_hand", {})
			if day_loss >= 0 and int(bet) > _max_deal():
				return _refuse(state, "bj_day_cap", {"cap": "loss", "net": day_net, "loss": day_loss, "win": null, "left": _max_deal()})
			if coins - int(bet) < floor_coins:
				return _refuse(state, "bj_no_coins", {"need": int(bet) + floor_coins - coins, "have": coins, "floor": floor_coins})
			events.append_array(_deal(int(bet)))
			coins -= int(bet)
			events.append_array(_after_deal(coins))
		"bj_act":
			if _hand.is_empty(): return _refuse(state, "bj_no_hand", {})
			var r := _act(str(cmd.get("action", "")), coins)
			if r.has("code"): return _refuse(state, str(r.code), r.get("detail", {}))
			events.append_array(r.events)
	return _reply(state, events)

var _base := 0

func _reply(state: Dictionary, events: Array) -> Dictionary:
	return {"ok": true, "state": _strip(state), "events": events}

func _refuse(state: Dictionary, code: String, detail: Dictionary) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail, "state": _strip(state)}

func _strip(state: Dictionary) -> Dictionary:
	var s := state.duplicate(true)
	s.erase("_bj_mock")
	s.erase("blackjack")
	s["coins"] = _base
	return s

# ---------------------------------------------------------------- the game

func _draw() -> String:
	var d: Array = _hand.deck
	return str(d.pop_front()) if not d.is_empty() else "2C"

func _shoe() -> Array:
	if not next_deck.is_empty():
		var forced := next_deck.duplicate()
		next_deck = []
		return forced
	var cards: Array = []
	for i in 4:
		for s in ["S", "H", "D", "C"]:
			for r in ["A", "2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K"]: cards.append(r + s)
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = cards[i]
		cards[i] = cards[j]
		cards[j] = t
	return cards

func _deal(bet: int) -> Array:
	n += 1
	last_bet = bet
	last = null   # a new hand clears a result not seen (be266ee4)
	delta -= bet
	_hand = {"deck": _shoe(), "hands": [], "dealer": [], "active": 0, "expired": false}
	var p := [_draw()]
	var up := _draw()
	p.append(_draw())
	var hole := _draw()
	_hand.hands = [{"cards": p, "bet": bet, "doubled": false, "state": "playing", "split": false}]
	_hand.dealer = [up, hole]
	return [{"kind": "coins", "delta": -bet}, {"kind": "bj_dealt", "n": n, "bet": bet, "hand": _hand_view()}]

## Peek and naturals settle in the deal (§3).
func _after_deal(coins: int) -> Array:
	var up: String = _hand.dealer[0]
	var dealer_bj: bool = int(P0Blackjack.total(_hand.dealer).total) == 21
	var player_bj: bool = int(P0Blackjack.total(_hand.hands[0].cards).total) == 21
	if P0Blackjack.rank_value(up) in [1, 10] and dealer_bj: return _settle("peek", coins)
	if player_bj: return _settle("blackjack", coins)
	return []

func _act(action: String, coins: int) -> Dictionary:
	var i := int(_hand.active)
	var h: Dictionary = _hand.hands[i]
	var events: Array = []
	match action:
		"hit":
			h.cards.append(_draw())
			events.append({"kind": "bj_card", "to": "player", "hand_index": i, "card": h.cards[-1]})
			var t := int(P0Blackjack.total(h.cards).total)
			if t > 21: h.state = "bust"
			elif t == 21: h.state = "stood"
		"stand":
			h.state = "stood"
		"double":
			var why := _blocked_double(h)
			if why != "": return {"code": "bj_bad_action", "detail": {"why": why}}
			if coins - int(h.bet) < floor_coins: return {"code": "bj_no_coins", "detail": {"need": int(h.bet) + floor_coins - coins}}
			delta -= int(h.bet)
			coins -= int(h.bet)
			events.append({"kind": "coins", "delta": -int(h.bet)})
			h.bet = int(h.bet) * 2
			h.doubled = true
			h.cards.append(_draw())
			events.append({"kind": "bj_card", "to": "player", "hand_index": i, "card": h.cards[-1]})
			h.state = "bust" if P0Blackjack.is_bust(h.cards) else "stood"
		"split":
			var why := _blocked_split(h)
			if why != "": return {"code": "bj_bad_action", "detail": {"why": why}}
			if coins - int(h.bet) < floor_coins: return {"code": "bj_no_coins", "detail": {"need": int(h.bet) + floor_coins - coins}}
			delta -= int(h.bet)
			coins -= int(h.bet)
			events.append({"kind": "coins", "delta": -int(h.bet)})
			var aces: bool = P0Blackjack.rank(h.cards[0]) == "A"
			var b := {"cards": [h.cards[1]], "bet": h.bet, "doubled": false, "state": "playing", "split": true}
			h.cards = [h.cards[0]]
			h.split = true
			_hand.hands.append(b)
			for k in 2:
				var hk: Dictionary = _hand.hands[k]
				hk.cards.append(_draw())
				events.append({"kind": "bj_card", "to": "player", "hand_index": k, "card": hk.cards[-1]})
				if aces: hk.state = "stood"
		_:
			return {"code": "bj_bad_action", "detail": {"why": "first_two"}}
	while int(_hand.active) < _hand.hands.size() and str(_hand.hands[_hand.active].state) != "playing":
		_hand.active = int(_hand.active) + 1
	if int(_hand.active) >= _hand.hands.size():
		_hand.active = _hand.hands.size() - 1
		events.append_array(_settle("played", coins))
	return {"events": events}

func _blocked_double(h: Dictionary) -> String:
	if bool(h.get("split", false)): return "after_split"
	if h.cards.size() != 2: return "first_two"
	return ""

func _blocked_split(h: Dictionary) -> String:
	if _hand.hands.size() > 1: return "split_aces" if P0Blackjack.rank(h.cards[0]) == "A" else "one_split"
	if h.cards.size() != 2: return "first_two"
	if P0Blackjack.rank_value(h.cards[0]) != P0Blackjack.rank_value(h.cards[1]): return "pairs_only"
	return ""

## Stand every hand still open, play the dealer, pay. `why` as the contract: played, peek, blackjack, expired.
func _settle(why: String, coins: int) -> Array:
	var events: Array = []
	var dealer: Array = _hand.dealer
	events.append({"kind": "bj_card", "to": "dealer", "hand_index": 0, "card": dealer[1], "hole": true})
	var all_bust := (_hand.hands as Array).all(func(h): return P0Blackjack.is_bust(h.cards))
	if why in ["played", "expired"] and not all_bust:
		while int(P0Blackjack.total(dealer).total) < 17:
			dealer.append(_draw())
			events.append({"kind": "bj_card", "to": "dealer", "hand_index": 0, "card": dealer[-1]})
	var d := int(P0Blackjack.total(dealer).total)
	var dealer_bj := d == 21 and dealer.size() == 2
	var out: Array = []
	var paid := 0
	var net := 0
	for h in _hand.hands:
		var t := int(P0Blackjack.total(h.cards).total)
		var natural: bool = t == 21 and h.cards.size() == 2 and not bool(h.get("split", false))
		var bet := int(h.bet)
		var result := "lose"
		var payout := 0
		if t > 21: result = "bust"
		elif natural and dealer_bj: result = "push"; payout = bet
		elif natural: result = "blackjack"; payout = bet + int(floor(bet * 1.5))
		elif dealer_bj: result = "lose"
		elif d > 21: result = "dealer_bust"; payout = bet * 2
		elif t > d: result = "win"; payout = bet * 2
		elif t == d: result = "push"; payout = bet
		paid += payout
		net += payout - bet
		out.append({"cards": h.cards.duplicate(), "result": result, "bet": bet, "payout": payout, "net": payout - bet})
	delta += paid
	day_net += net
	if paid > 0: events.append({"kind": "coins", "delta": paid})
	var result := {"n": n, "why": why, "dealer": dealer.duplicate(), "dealer_total": d, "hands": out, "net": net,
		"coins_after": coins + paid}
	events.append({"kind": "bj_result"}.merged(result))
	_hand = {}
	return events

# ---------------------------------------------------------------- view

## What a deal may stake now: what the day's loss has left, in fives (0 under the minimum: the table is closed).
func _max_deal() -> int:
	var room := maxi(0, day_loss + day_net)
	return room - room % 5

func _view(coins: int) -> Dictionary:
	var capped := day_loss >= 0
	return {"open": true, "intro": intro, "floor": floor_coins, "min_bet": 5, "step": 5,
		"chips": P0Blackjack.CHIPS, "max_bet": null, "max_deal": _max_deal() if capped else null,
		"day": {"net": day_net, "loss": day_loss if capped else null, "win": null, "capped": "loss" if capped and _max_deal() < 5 else null},
		"last_bet": mini(last_bet, _max_deal()) if capped else last_bet, "hand": null if _hand.is_empty() else _hand_view(coins),
		"last": last}

func _hand_view(coins := -1) -> Dictionary:
	var i := int(_hand.active)
	var hands: Array = []
	for h in _hand.hands:
		var t := P0Blackjack.total(h.cards)
		hands.append({"cards": h.cards.duplicate(), "total": t.total, "soft": t.soft, "bet": h.bet,
			"doubled": h.doubled, "state": h.state})
	var expired := bool(_hand.get("expired", false))
	var actions: Array = []
	var blocked := {}
	var needs := {}
	var h: Dictionary = _hand.hands[i]
	if not expired and str(h.state) == "playing":
		actions = ["hit", "stand"]
		var short := int(h.bet) + floor_coins - coins if coins >= 0 else 0
		for a in ["double", "split"]:
			var why := _blocked_double(h) if a == "double" else _blocked_split(h)
			if why == "" and short > 0:
				why = "coins"
				needs[a] = short
			if why == "": actions.append(a)
			else: blocked[a] = why
	var up: String = _hand.dealer[0]
	return {"n": n, "expired": expired, "active": i, "hands": hands, "dealer": [up, ""],
		"dealer_total": P0Blackjack.rank_value(up) if P0Blackjack.rank(up) != "A" else 11, "actions": actions,
		"blocked": blocked, "need": needs}
