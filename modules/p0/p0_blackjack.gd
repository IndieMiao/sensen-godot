class_name P0Blackjack
extends RefCounted
## What the Barbary Card Room's Blackjack page shows, from the P0 server view (SGODOT-351; plan v4.3 §3 / §6,
## 不知火舞 on 351 7cdf40a9; server contract 后裔 on 351 b610f98a). Pure functions, unit-tested; P0BlackjackPage only
## draws them. Bets are coins drawn as chips (no chip currency); after a bet, a double or a split the wallet keeps at
## least the floor (40), so a wallet under floor + 5 cannot open a hand. Test phase: no bet or daily limit.
## Cards are two characters, rank A 2–9 T J Q K and suit S H D C ("TH", "QS"); a face-down card is "".

const CHIPS := [5, 10, 50, 100, 500, 1000]
const FLOOR := 40
const MIN_BET := 5
const STEP := 5
## The deepest stack the bet circle draws (7cdf40a9 ②: more only adds to the total beside it).
const CIRCLE_MAX := 8

static func info(view: Dictionary) -> Dictionary:
	var b = view.get("blackjack", null)
	return b if b is Dictionary else {}

static func floor_of(view: Dictionary) -> int: return int(info(view).get("floor", FLOOR))
static func min_bet_of(view: Dictionary) -> int: return int(info(view).get("min_bet", MIN_BET))
static func step_of(view: Dictionary) -> int: return maxi(1, int(info(view).get("step", STEP)))
static func chips_of(view: Dictionary) -> Array:
	var c = info(view).get("chips", null)
	return c if c is Array and not c.is_empty() else CHIPS
static func coins_of(view: Dictionary) -> int: return int(view.get("coins", 0))

## The hand in play, or {} (none, or settled: the server sets it back to null).
static func hand(view: Dictionary) -> Dictionary:
	var h = info(view).get("hand", null)
	return h if h is Dictionary else {}

static func last(view: Dictionary) -> Dictionary:
	var l = info(view).get("last", null)
	return l if l is Dictionary else {}

# ---------------------------------------------------------------- cards

static func rank(card: String) -> String: return card.substr(0, 1)
static func suit(card: String) -> String: return card.substr(1, 1)
static func is_red(card: String) -> bool: return suit(card) in ["H", "D"]
## The rank as printed on the card: T is 10.
static func rank_text(card: String) -> String: return "10" if rank(card) == "T" else rank(card)

static func rank_value(card: String) -> int:
	var r := rank(card)
	if r == "A": return 1
	if r in ["T", "J", "Q", "K"]: return 10
	return int(r)

## Best total of the face-up cards: {total, soft} — soft when an A counts 11 without going over.
static func total(cards: Array) -> Dictionary:
	var sum := 0
	var aces := 0
	for c in cards:
		if str(c) == "": continue
		sum += rank_value(str(c))
		if rank(str(c)) == "A": aces += 1
	if aces > 0 and sum + 10 <= 21: return {"total": sum + 10, "soft": true}
	return {"total": sum, "soft": false}

## The points badge (§6 通用): soft `7 / 17`, `Bust` over 21, else the total; "" with no face-up card.
static func badge(cards: Array) -> String:
	if cards.all(func(c): return str(c) == ""): return ""
	var t := total(cards)
	if int(t.total) > 21: return "Bust"
	if bool(t.soft) and int(t.total) != 21: return "%d / %d" % [int(t.total) - 10, int(t.total)]
	return str(int(t.total))

static func is_bust(cards: Array) -> bool: return int(total(cards).total) > 21

# ---------------------------------------------------------------- copy

## 1,250: thousands with commas (§6: `Deal again · 1,250`).
static func comma(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## A chip's face: 1000 reads `1K` (7cdf40a9 ①: `1,000` is too tight in 48).
static func chip_label(value: int) -> String:
	return "%dK" % (value / 1000) if value >= 1000 and value % 1000 == 0 else str(value)

const RESULT_WORDS := {"blackjack": "Blackjack", "win": "You win", "push": "Push", "lose": "You lose",
	"bust": "Bust", "dealer_bust": "Dealer busts"}
static func result_word(result: String) -> String: return str(RESULT_WORDS.get(result, ""))

## The win float (§6 ④): `+30 coins` for a hand that won; none for a push or a loss (no negative floats).
static func float_text(net: int) -> String: return "+%s coins" % comma(net) if net > 0 else ""

## The 3-second line over the table for a hand the server settled while the player was away (§6 ⑦):
## `Last hand settled · You win +20 coins` / `· You lose`; a push says `· Push`.
static func settled_line(result: Dictionary) -> String:
	var net := int(result.get("net", 0))
	if net > 0: return "Last hand settled · You win +%s coins" % comma(net)
	if net < 0: return "Last hand settled · You lose"
	return "Last hand settled · Push"

## Coins short of keeping the floor after putting `stake` on the table (q(10)'s counter algorithm): 0 = enough.
static func need(coins: int, stake: int, floor_: int) -> int: return maxi(0, stake + floor_ - coins)
static func need_text(n: int) -> String: return "Need %s more coins" % comma(n)

## Low on coins (§6 ⑤): not even the smallest bet keeps the floor.
static func low_on_coins(view: Dictionary) -> bool:
	return coins_of(view) - min_bet_of(view) < floor_of(view)

## A chip can go on the bet only if the wallet still keeps the floor (7cdf40a9 ③).
static func can_add(view: Dictionary, bet: int, value: int) -> bool:
	return coins_of(view) - bet - value >= floor_of(view)

## The bet `Deal again` puts down (§3): the last bet, or the most the wallet allows above the floor, in steps of 5;
## it does not climb back on its own. 0 when not even the smallest bet fits.
static func deal_again_bet(view: Dictionary, last_bet: int) -> int:
	var b := mini(last_bet, coins_of(view) - floor_of(view))
	b -= posmod(b, step_of(view))
	return b if b >= min_bet_of(view) else 0

## The bet state's main key: `Deal · 120`, `Place a bet` at 0, `Need N more coins` when low (N = floor + 5 − wallet).
static func deal_key(view: Dictionary, bet: int) -> Dictionary:
	if low_on_coins(view) and bet == 0:
		return {"label": "Deal", "reason": need_text(need(coins_of(view), min_bet_of(view), floor_of(view)))}
	if bet <= 0: return {"label": "Deal", "reason": "Place a bet"}
	var short := need(coins_of(view), bet, floor_of(view))
	if short > 0: return {"label": "Deal · " + comma(bet), "reason": need_text(short)}
	return {"label": "Deal · " + comma(bet), "reason": ""}

## The server's blocked reasons (351 b610f98a / 9cb4e561) in 不知火舞's words (b2482379): `One split per hand` only for
## splitting again; a double after a split and anything after split aces (they stand on their own) say their own line.
const BLOCK_WORDS := {"first_two": "First two cards only", "pairs_only": "Pairs only", "one_split": "One split per hand",
	"split_aces": "Split aces get one card", "after_split": "Not after a split"}

## The four action keys for the hand in play (§6 ③): Hit / Stand, and `Double · 120` / `Split · 120` always there,
## grey with the reason when the server blocks them (blocked.{double|split}, need.{…} for coins). An expired hand has
## no keys at all (the page hides them).
static func action_keys(view: Dictionary) -> Dictionary:
	var h := hand(view)
	var acts: Array = h.get("actions", [])
	var blocked: Dictionary = h.get("blocked", {}) if h.get("blocked", {}) is Dictionary else {}
	var needs: Dictionary = h.get("need", {}) if h.get("need", {}) is Dictionary else {}
	var hands: Array = h.get("hands", [])
	var i := int(h.get("active", 0))
	var bet := int((hands[i] as Dictionary).get("bet", 0)) if i < hands.size() and hands[i] is Dictionary else 0
	if i < hands.size() and bool(hands[i].get("doubled", false)): bet /= 2
	var keys := {}
	for a in ["hit", "stand", "double", "split"]:
		var label: String = {"hit": "Hit", "stand": "Stand", "double": "Double · " + comma(bet), "split": "Split · " + comma(bet)}[a]
		var reason := ""
		var enabled: bool = a in acts
		if not enabled:
			var why := str(blocked.get(a, ""))
			if why == "coins": reason = need_text(int(needs.get(a, need(coins_of(view), bet, floor_of(view)))))
			elif BLOCK_WORDS.has(why): reason = str(BLOCK_WORDS[why])
			elif a in ["double", "split"]: reason = str(BLOCK_WORDS.first_two)
		# Hit / Stand missing only while no decision is open (a hand the server is settling): inert, no words.
		keys[a] = {"label": label, "reason": reason, "enabled": enabled}
	return keys

## The chips that draw a bet in the circle when the player did not stack it themselves (Deal again, a resumed hand):
## largest first, at most CIRCLE_MAX drawn.
static func chips_for(bet: int, chips: Array = CHIPS) -> Array:
	var out: Array = []
	var left := bet
	var desc := chips.duplicate()
	desc.sort()
	desc.reverse()
	for c in desc:
		while left >= int(c):
			out.append(int(c))
			left -= int(c)
	return out
