class_name P0ItemInfo
extends RefCounted
## Item detail rules for the InfoSheet (SGODOT-224; F-07 confirmed table, SGODOT-207 comment 168a4cc3, revisions 1–2;
## product wording 李白 25f3cb4c; K-3 = A, crops can't be gifted). Every condition is computed here from the server
## view; the card only draws the spec it is given. The table itself is item_info_rules.json (keyed "kind/context").
##
## Contexts (the F-07 columns that show a detail card; cooking picks put the cell straight into the pot, no card):
##   &"bag"           bag drawer detail (LOCK-12 / 13)
##   &"gear"          Gear side slot rows (LOCK-13; rods and tools)
##   &"counter_buy"   a counter's Buy list row (LOCK-15)
##   &"counter_sell"  a counter's Sell here selection (LOCK-15)
##   &"gift"          the gift drawer, Bag side only
##   &"storage"       a Farm Storage stack in the bag drawer (Take 10 / Take all; take_out {item, qty})
##   &"workbench"     a recipe's item on the workbench (B2-06, 不知火舞 231 walkthrough): what it does, read only — the
##                    blueprint card itself has Craft / Equip; no item page behind it (no ›)
##
## opts (all optional):
##   place: String     "home" (own farm / farmhouse), "pond", "outpost" — at-home rules (Store, Sell at home)
##   counter: String   counter role: "homestead", "tackle", "tea", "market", "post" (same ids as open_counter)
##   qty: int          stepper count on a buy row (price column shows the total, line 2 "2 × 15 coins")
##   target: Dictionary gift recipient {kind: "resident" | "player", id} or a delivery request {request: id}
##   pinned: bool      the stack is pinned on the current action's quick bar (pins are kept by the client)
##
## Spec (Dictionary) returned by spec():
##   card: bool (false = this kind shows no card in this context), id, kind, icon: Texture2D, title: String,
##   quantity: int (0 hides ×N), info: bool (title shows ›)
##   rarity: int (0 = none), rarity_text: String, quality: int (dish ★ count), region: String
##   badge: StringName   &"" / &"locked" / &"pinned" / &"new" (one at most: Locked > Pinned > New)
##   facts: Array[String]   at most what fits 6 card rows with title and buttons (q(10) wording)
##   buttons: Array of {id: StringName, label: String, kind: StringName, payload: Dictionary}
##            kind: &"primary" (at most one) / &"secondary" / &"nav" (Gift ›) / &"unavailable" (label = the reason)
##   lock: {shown: bool, locked: bool}   the title-area lock icon (not a button slot)
##   price: Dictionary   counter_buy only: {each, total, text, line} ("15 coins", "2 × 15 coins"); {} hides it
##   quota: Dictionary   counter_sell only: {text, note, have, total} for the buy-back line; {} hides it
##
## Server facts not in the P0 view yet (SGODOT-228 PR-A: shops[role], quotas, bag stack locked / gifted / expires_in,
## residents) are read defensively: without them the homestead stall buys crops and fish at full price with no limit,
## nothing is locked or gifted, and nobody is a mutual friend. Actions the server can't do yet are gated by capability
## (can_store = view.storage, can_lock = bag stacks carry `locked`, can_gift = view.residents / view.social): no
## button, no grey text and no lock icon until the field appears (刘邦 / 奕星 2026-10-08).

const CONTEXTS: Array[StringName] = [&"bag", &"gear", &"counter_buy", &"counter_sell", &"gift", &"storage", &"workbench"]
const RULES_PATH := "res://modules/p0/item_info_rules.json"
const KINDS := ["seed", "crop", "fish", "dish", "bait", "rod", "pick", "tool", "trap", "weapon", "potion"]
const SEP := " · "
const _P0Travel := preload("res://modules/p0/p0_travel.gd")   # grouped(): a panel's coin price from 1,000 has its commas (不知火舞 on #409)
const _MYSTERY := "dish_mystery"
const _TAKE_SOME := 10   # F-07 storage: Take 10 + Take all
## Server kinds the card treats as another kind's rules (刘邦 / 周瑜: torches are materials here).
const _KIND_ALIAS := {"torch": "material"}

static var _rules: Dictionary = {}

static func rules() -> Dictionary:
	if _rules.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
		_rules = parsed if parsed is Dictionary else {}
	return _rules

static func kind_of(view: Dictionary, item_id: String) -> String:
	if item_id.begins_with("potion_"): return "potion"   # server may label it consumable; never material rules.
	if item_id.begins_with("weapon_"): return "weapon"
	if P0Decor.is_decor(item_id): return "decor"   # Decorate (SGODOT-284): yard pieces live in Farm Storage
	if is_card(item_id): return "card"   # a Recipe Card on a counter (§9.11.1 / §9.11.2): it turns its page Tasted
	var k := str(P0Logic.item(view, item_id).get("kind", ""))
	if k == "":
		var head := item_id.split("_")[0]
		k = head if head in KINDS + ["fert"] else "material"
	return str(_KIND_ALIAS.get(k, k))

## The bag drawer Tab an item sits on (§10.4.2): seeds and fertilizer on Seeds, crops on Produce, bait and rods on
## Tackle, torches and the rest on Materials (周瑜 / 刘邦).
## Kinds the plan doesn't put on a Tab (postcards, décor; §10.4.8 keepsakes go to storage) get &"": All only (刘邦).
static func tab_of(view: Dictionary, item_id: String) -> StringName:
	if P0Decor.is_decor(item_id): return &"decor"   # STORE-DECOR (Figma 2189:33113): Farm Storage's own Decor tab
	var k := str(P0Logic.item(view, item_id).get("kind", ""))
	if k == "": k = item_id.split("_")[0]
	var tab = {"seed": &"seeds", "fert": &"seeds", "fish": &"fish", "crop": &"produce", "dish": &"dishes", "bait": &"tackle",
		"trap": &"tackle", "rod": &"tackle", "pick": &"tackle", "material": &"materials", "torch": &"materials"}.get(k, null)
	if item_id.begins_with("potion_"): return &"materials"
	if tab != null: return tab
	return &"materials" if P0Logic.content().get("materials", {}).has(item_id) else &""

static func spec(view: Dictionary, item_id: String, context: StringName, opts := {}) -> Dictionary:
	assert(context in CONTEXTS, "P0ItemInfo: unknown context %s" % context)
	var kind := kind_of(view, item_id)
	var it := P0Logic.item(view, item_id)
	var rarity := int(it.get("rarity", 0))
	var f := flags(view, item_id, context, opts)
	var t := tokens(view, item_id, context, opts)
	var rule: Dictionary = rules().get("%s/%s" % [kind, context], rules().get("any/%s" % context, {}))
	# The generic buy row (postcards, Bag Upgrade I) only stands for goods this counter actually sells.
	if context == &"counter_buy" and not rules().has("%s/%s" % [kind, context]) and _offer(view, item_id, opts).is_empty(): rule = {}
	# The workbench card stands only for what the workbench makes.
	if context == &"workbench" and not P0MaterialLogic.EFFECTS.has(item_id) and P0Logic.GearLogic.weapon(item_id).is_empty(): rule = {}
	var badge: StringName = &"locked" if f.locked else (&"pinned" if f.pinned else &"")
	var out := {
		card = not rule.is_empty(),
		id = item_id,
		kind = kind,
		icon = P0Logic.icon(item_id),
		title = P0Logic.item_name(view, item_id),
		quantity = _stored(view, item_id) if kind == "decor" else P0Logic.bag_count(view, item_id),
		info = context != &"workbench",   # no item page for a workbench item in P0: no dead-end ›
		rarity = rarity,
		rarity_text = P0Logic.rarity_name(view, rarity) if rarity > 0 else "",
		quality = int(it.get("quality", 0)),
		region = "",
		badge = badge,
		facts = [],
		buttons = [],
		lock = {shown = bool(rule.get("lock", false)) and f.can_lock, locked = f.locked},
		price = {},
		quota = {},
	}
	if kind == "card":   # the dish it teaches on the title (the server names it), the card's own icon (282, P1 exit ⑦)
		out.title = str(_offer(view, item_id, opts).get("name", P0Logic.item_name(view, card_page(item_id))))
		out.icon = P0Logic.icon("recipe_card")
		out.quantity = 0
	# Gift Clues (Fishing Lv7, q(167); 302 b308ee14): who of the residents met likes this dish, under the rarity line.
	if kind == "dish": out.liked_by = P0Logic.liked_by_line(view, item_id)
	if context == &"counter_buy":   # the › card's NeedTiles: what the buy takes (Bag Upgrades), however far the gate is
		out.needs = (_offer(view, item_id, opts).get("materials", []) as Array).map(func(m): return {id = str(m.get("id", "")), name = str(m.get("name", "")),
			have = int(m.get("have", 0)), need = int(m.get("need", 0)), icon = P0Logic.icon(str(m.get("id", "")))})
	if rule.is_empty(): return out
	for line in rule.get("facts", []):
		var text := fill(str(line), t)
		if text != "": out.facts.append(text)
	out.buttons = _buttons(rule, f, t)
	for b in out.buttons: b.sends = sends(b, context)
	if rule.get("price", false): out.price = _price(view, item_id, opts)
	# STALL-NEW-2 (E-04): a buy row unlocked since the stall was last opened reads `◆ New for you` in newInk.
	if context == &"counter_buy" and _new_offer(item_id, opts) and out.facts.has(NEW_FOR_YOU): out.gate_tone = &"new"
	if rule.get("quota", false): out.quota = _quota(view, item_id, kind, opts)
	if rule.has("fact_note"): out.fact_note = fill(str(rule.fact_note), t)   # muted, under the fact beside the buttons
	if rule.has("card_note"): out.card_note = fill(str(rule.card_note), t)   # muted, its own line in a buy row's › card
	return out

## Fills {tokens}. Segments are " · "-separated: a segment whose token is empty drops out, and a line with no
## segment left drops out (so "{count} · {source}" reads "12" when the source is unknown).
static func fill(template: String, t: Dictionary) -> String:
	var kept: Array[String] = []
	for seg in template.split(SEP):
		var s := seg
		var empty := false
		var re := RegEx.create_from_string("\\{([a-z_]+)\\}")
		for m in re.search_all(seg):
			var v := str(t.get(m.get_string(1), ""))
			if v == "": empty = true
			s = s.replace(m.get_string(0), v)
		if not empty and s.strip_edges() != "": kept.append(s)
	return SEP.join(kept)

## Predicate over flags: names joined by &, each optionally negated with !. Empty = true.
static func holds(expr: String, f: Dictionary) -> bool:
	if expr.strip_edges() == "": return true
	for term in expr.split("&"):
		var name := term.strip_edges()
		var neg := name.begins_with("!")
		if neg: name = name.substr(1).strip_edges()
		assert(f.has(name), "P0ItemInfo: unknown flag %s" % name)
		if bool(f.get(name, false)) == neg: return false
	return true

## Buttons that only open or pick something on this device: they keep working offline (§10.7.1). A card's Gift opens
## the resident's gift drawer; only the gift drawer's own Gift sends the gift.
const LOCAL_BUTTONS: Array[StringName] = [&"pin", &"unpin", &"bag_room"]

## Whether button `b` (from `buttons`) sends a server command: greyed to `Offline` while offline, its press tracked.
static func sends(b: Dictionary, context: StringName) -> bool:
	var id := StringName(b.get("id", &""))
	# An unavailable one is grey already and keeps its reason (✓ Equipped, Locked, Need 2 more Radish).
	if StringName(b.get("kind", &"")) in [&"nav", &"unavailable"] or LOCAL_BUTTONS.has(id): return false
	return id != &"gift" or context == &"gift"

static func _buttons(rule: Dictionary, f: Dictionary, t: Dictionary) -> Array:
	var out := []
	var promote := str(rule.get("promote", ""))
	var promoted := false
	for b in rule.get("buttons", []):
		if not holds(str(b.get("when", "")), f): continue
		var kind := StringName(str(b.get("kind", "secondary")))
		var label := fill(str(b.get("label", "")), t)
		for u in b.get("unless", []):
			if holds(str(u.get("when", "")), f):
				kind = &"unavailable"
				label = fill(str(u.get("label", "")), t)
				break
		if str(b.id) == promote and kind != &"unavailable": promoted = true
		out.append({id = StringName(str(b.id)), label = label, kind = kind, payload = _ints(b.get("payload", {}))})
	if promoted:
		for b in out:
			if b.id == StringName(promote): b.kind = &"primary"
			elif b.kind == &"primary": b.kind = &"secondary"
	return out

## JSON numbers load as floats; a payload's whole numbers go to the server as ints ({qty: 10}, not 10.0).
static func _ints(payload: Dictionary) -> Dictionary:
	var out := {}
	for k in payload:
		var v = payload[k]
		out[k] = int(v) if v is float and v == floor(v) else v
	return out

# ---------------------------------------------------------------- facts from the view

static func _stack(view: Dictionary, item_id: String) -> Dictionary:
	for s in view.get("bag", {}).get("slots", []):
		if str(s.get("id", "")) == item_id: return s
	return {}

static func _counter(opts: Dictionary) -> String: return str(opts.get("counter", "homestead"))

## Recipe Cards (§9.11.1 / §9.11.2): `recipe_card_<page>`, bought once at the counter that shelves it, its page Tasted.
const CARD := "recipe_card_"
static func is_card(item_id: String) -> bool: return item_id.begins_with(CARD)
static func card_page(item_id: String) -> String: return item_id.trim_prefix(CARD)

static func _card_line(view: Dictionary, offer: Dictionary, opts: Dictionary) -> String:
	var rarity := int(offer.get("rarity", 0))
	var word := P0Logic.rarity_name(view, rarity) if rarity > 0 else ""
	if _counter(opts) != "market": return word
	return ("Regional · %s" % word) if word != "" else "Regional"
## The gift drawer's key: `Gift · +3` with the resident's points for this dish (Gift Clues, Fishing Lv7), `Gift · −2`
## for the Mystery Dish, `Gift` without them (q(167); RESIDENT-GIFT 1216:83527).
static func _gift_label(target: Dictionary) -> String:
	if not target.has("preview"): return "Gift"
	var n := int(target.preview)
	return "Gift · %s" % (("+%d" % n) if n >= 0 else ("−%d" % -n))

## The shop's offer row for a Buy list: view.shops[role].buy (SGODOT-228), else the older stall / tackle lists.
static func _offer(view: Dictionary, item_id: String, opts: Dictionary) -> Dictionary:
	var role := _counter(opts)
	var lists := []
	var shop: Dictionary = view.get("shops", {}).get(role, {})
	if shop.has("buy"): lists.append(shop.buy)
	if shop.has("cards"): lists.append(shop.cards)   # today's Recipe Cards on this counter: {id, page, name, rarity, price, need, owned}
	lists.append(view.get("tackle", {}).get("buy", []) if role == "tackle" else view.get("stall", {}).get("buy", []))
	for l in lists:
		for o in l:
			if str(o.get("id", "")) == item_id: return o
	return {}

## This counter's buy-back entry for the item's kind ({kind, rate, quota}), {} when it doesn't take the kind.
## view.shops[role].sell (SGODOT-228); without it the Homestead Stall takes crops and fish at full price.
## A regional entry (the Market Square, §9.13.1) takes only the ids it lists: this city's climate's regional items.
static func _buyback(view: Dictionary, item_id: String, opts: Dictionary) -> Dictionary:
	if not P0Logic.fast_crop(view, item_id).is_empty() and _counter(opts) != "homestead": return {}
	var kind := kind_of(view, item_id)
	var shop: Dictionary = view.get("shops", {}).get(_counter(opts), {})
	if shop.has("sell"):
		for e in shop.sell:
			if str(e.get("kind", "")) != kind: continue
			if bool(e.get("regional", false)) and not (e.get("items", []) as Array).has(item_id.split("@")[0]): return {}
			return e
		return {}
	return {kind = kind, rate = 1.0, quota = null} if _counter(opts) == "homestead" and kind in ["crop", "fish"] else {}

## What this counter pays for one (view.items[id].sell is the Homestead price; a rate below 1 rounds down), or -1.
static func _sell_here(view: Dictionary, item_id: String, opts: Dictionary) -> int:
	var base = P0Logic.item(view, item_id).get("sell", null)
	var e := _buyback(view, item_id, opts)
	if e.is_empty() or base == null: return -1
	# q(251) ②: at least 1, and the server's epsilon — 90 × 0.7 is 62.99999… in floats and must read 63
	return maxi(1, int(floor(float(base) * float(e.get("rate", 1.0)) + 1e-9)))

## The quota this counter counts the kind against (view.quotas[id]: {used, cap, resets_in, scope}), {} for none.
static func _quota_of(view: Dictionary, item_id: String, opts: Dictionary) -> Dictionary:
	var e := _buyback(view, item_id, opts)
	var id = e.get("quota", null)
	if id == null: return {}
	var q: Dictionary = view.get("quotas", {}).get(str(id), {})
	return q

static func _stored(view: Dictionary, item_id: String) -> int:
	for it in view.get("storage", {}).get("items", []):
		if str(it.get("id", "")) == item_id: return int(it.get("qty", 0))
	return 0

## "4h", "1h 30m", "45m" — crop growth hours as F-07 writes them (no trailing 0m).
static func hours(h: float) -> String:
	var m := int(round(h * 60.0))
	if m < 60: return "%dm" % m
	return ("%dh" % (m / 60)) if m % 60 == 0 else "%dh %dm" % [m / 60, m % 60]

static func flags(view: Dictionary, item_id: String, context: StringName, opts := {}) -> Dictionary:
	var kind := kind_of(view, item_id)
	var stack := _stack(view, item_id)
	var it := P0Logic.item(view, item_id)
	var offer := _offer(view, item_id, opts)
	var e: Dictionary = view.get("energy", {})
	var target: Dictionary = opts.get("target", {})
	var quota := _quota_of(view, item_id, opts)
	var qty := maxi(1, int(opts.get("qty", 1)))
	var rod := _rod(view, item_id)
	var gifted := bool(stack.get("gifted", false))
	var wallet := int(offer.get("need", int(offer.get("price", 0)) * qty))   # need includes the 40-coin floor (228)
	return {
		at_home = str(opts.get("place", "home")) == "home",
		pinned = bool(opts.get("pinned", false)),
		bar_full = bool(opts.get("bar_full", false)),   # five pinned on its bar and it isn't one (q(61))
		locked = bool(stack.get("locked", false)),
		gifted = gifted,
		mystery = item_id.split("@")[0] == _MYSTERY,
		never_sold = gifted or item_id.split("@")[0] in [_MYSTERY, "dish_travel_biscuits"],
		sold_here = _sell_here(view, item_id, opts) >= 0,
		# the server sells ⌊left / unit⌋ (0 = limit_reached), so the allowance must still fit one at this price
		quota_left = quota.is_empty() or int(quota.get("cap", 0)) - int(quota.get("used", 0)) >= maxi(1, _sell_here(view, item_id, opts)),
		energy_full = int(e.get("value", 0)) >= int(e.get("max", 200)),
		unlocked = bool(offer.get("unlocked", true)),
		homestead_ok = bool(offer.get("homestead_ok", true)),
		sold_out = offer.get("left", null) != null and int(offer.left) <= 0,
		can_afford = int(view.get("coins", 0)) >= (wallet if qty == 1 else wallet + int(offer.get("price", 0)) * (qty - 1)),
		take_some = _stored(view, item_id) > _TAKE_SOME,
		owned = bool(rod.get("owned", offer.get("owned", false))),
		craftable_weapon = kind == "weapon" and not P0Logic.GearLogic.weapon_recipe(item_id).is_empty(),
		materials_ok = (offer.get("materials", []) as Array).all(func(m): return int(m.get("have", 0)) >= int(m.get("need", 0))),
		equipped = bool(rod.get("equipped", false)),
		has_friends = int(view.get("social", {}).get("mutual", 0)) > 0,
		has_target = not target.is_empty() and target.has("kind"),
		player_target = str(target.get("kind", "")) == "player",
		resident_target = str(target.get("kind", "")) == "resident",
		gifted_today = bool(target.get("gifted_today", false)),
		# The bag card's Gift (SGODOT-225): opts.near = {id, name, gifted_today} for the resident within reach, else {}.
		resident_near = str(opts.get("near", {}).get("id", "")) != "",
		near_gifted_today = bool(opts.get("near", {}).get("gifted_today", false)),
		deliverable = _deliverable(view, item_id, target),
		recyclable = it.get("sell", null) != null,
		gate_item = bool(it.get("gate", false)),
		# What the server can do at all (SGODOT-228 PR-A adds them): until then no button and no grey text.
		can_store = view.has("storage"),
		can_lock = stack.has("locked"),
		can_gift = view.has("residents") or view.has("social"),
	}

static func tokens(view: Dictionary, item_id: String, context: StringName, opts := {}) -> Dictionary:
	var kind := kind_of(view, item_id)
	var it := P0Logic.item(view, item_id)
	var stack := _stack(view, item_id)
	var count := P0Logic.bag_count(view, item_id)
	var crop := P0Logic.crop_for_seed(view, item_id) if kind == "seed" else {}
	var offer := _offer(view, item_id, opts)
	var here := _sell_here(view, item_id, opts)
	var quota := _quota_of(view, item_id, opts)
	var sellable := count
	# the allowance is in coins: Sell All takes as many as the rest of it pays for (server: ⌊left / unit⌋)
	if not quota.is_empty(): sellable = mini(count, maxi(0, int(quota.get("cap", 0)) - int(quota.get("used", 0))) / maxi(1, here))
	var rod := _rod(view, item_id)
	var t := {
		count = str(count) if count > 0 else "",
		source = {"crop": "Harvested at home"}.get(kind, str(stack.get("source", ""))),
		sell = str(int(it.sell)) if it.get("sell", null) != null else "",
		count_source = "",
		sell_here = str(here) if here >= 0 else "",
		sell_at_home = ("Sells for %d at home" % int(it.sell)) if it.get("sell", null) != null else "",
		# q(252) ③: an away counter's sell card says the home price under its own (`6 each` over `8 at home`)
		home_note = ("%d at home" % int(it.sell)) if here >= 0 and it.get("sell", null) != null and away(view, _counter(opts)) else "",
		energy = str(int(crop.energy)) if crop.has("energy") else "",
		grow = grow_time(crop),
		stored = str(_stored(view, item_id)) if _stored(view, item_id) > 0 else "",
		take_some = "Take %d" % _TAKE_SOME,
		homestead_gate = ("Homestead Lv%d needed" % int(offer.homestead)) if offer.get("homestead", null) != null else "",
		xp_hint = "",
		fert_use = fert_use(item_id) if kind == "fert" else "",   # the bag card's line 1 (NPC-2)
		# A buy row's line 2 (FARM-6 482:46): what the item does, in a few words.
		use = {"seed": _seed_use(crop), "bait": "Bites come faster",
			"fert": fert_use(item_id)}.get(kind, _offer_use(view, offer)),
		region_line = "",
		pin_verb = "Unpin" if opts.get("pinned", false) else "Pin",
		dex = _dex(view),
		meal = str(int(it.get("meal", 0))) if kind == "dish" else "",
		eat_label = str(P0Logic.eat_button(view, item_id).get("text", "")) if kind == "dish" else "",
		gifted_line = "Gifted · can't be sold · can eat · can gift to a Resident" if stack.get("gifted", false) else "",
		expires_line = ("Expires in " + P0Logic.span(float(stack.expires_in))) if stack.has("expires_in") else "",
		affinity_line = "",
		gift_label = _gift_label(opts.get("target", {})),
		gift_near_label = ("Gift to %s" % str(opts.near.name)) if str(opts.get("near", {}).get("name", "")) != "" else "",
		sell_all_label = _sell_all_label(count, sellable, here),
		quota_resets_in = P0Logic.span(float(quota.get("resets_in", 0))) if quota.has("resets_in") else "",
		stock_line = NEW_FOR_YOU if _new_offer(item_id, opts) else _stock_line(offer, count),
		gate_text = ("%s Lv%d needed" % [str(offer.get("skill", "")).capitalize(), int(offer.get("gate", 0))]) if offer.has("gate") else "",
		# Daily stock comes back at the day's rollover, the same moment as Rest (view.rest.resets_in).
		restock_in = P0Logic.span(float(view.get("rest", {}).get("resets_in", 0))) if view.get("rest", {}).has("resets_in") else "",
		coins_short = _P0Travel.grouped(maxi(0, int(offer.get("need", int(offer.get("price", 0)))) + int(offer.get("price", 0)) * (maxi(1, int(opts.get("qty", 1))) - 1) - int(view.get("coins", 0)))),
		rod_effect = _rod_effect(view, rod),
		# A buy row has room for the reach only (NPC-2-2 `Lands up to Rare fish`); the card says the bite window too.
		rod_reach = ("Lands up to %s fish" % P0Logic.rarity_name(view, int(rod.reach))) if rod.has("reach") else "",
		# q(278): `Legendary needs Fishing Lv7–9`, its own muted line under the effect — in Gear for a rod the player has
		# (不知火舞 386 1c3d0416: not under a greyed gate row); on the shelf and its › card once the rod can be bought (the
		# Buy key says `Fishing Lv6 needed` till then) and while it is not in Gear (`In Gear` takes the row's line)
		rod_tier = rod_tier(view, rod) if rod.get("owned", false) else "",
		rod_tier_shelf = rod_tier(view, rod) if bool(offer.get("unlocked", true)) and not rod.get("owned", false) else "",
		rod_gate = "" if rod.get("owned", false) or rod.is_empty() else "Fishing Lv%d · Tackle Shop" % int(rod.get("level", 1)),
		owned_line = "In Gear" if rod.get("owned", false) else "",
		# Row Hoe (market, LOCK-15 / 李白 q(46)): what it does, from view.gear.hoes.
		tool_effect = ("Sows %d plots at once" % int(rod.sow)) if rod.has("sow") else "",
		# A buy row's line 3 for goods made from materials (Bag Upgrade I): the first one still short and how many more are
		# (`Hardwood 0/4 · +2 more`), `Materials ready` once all are in, else the stock (_materials_line).
		need_line = _materials_line(offer) if not (offer.get("materials", []) as Array).is_empty() \
			else (("Stock %d/1" % (0 if offer.get("owned", false) else 1)) if offer.get("once", false) else _stock_line(offer, count)),   # MARKET-SPECIALTY `Stock 1/1`
		materials_short = _materials_short(offer),
		# LOCK-29: "1 Stone per rock"; where a pickaxe comes from while it isn't owned (Copper Pickaxe: Workbench).
		pick_effect = ("%d Stone per rock" % int(rod.stone)) if rod.has("stone") else "",
		pick_source = str({"start": "Starter", "workbench": "Workbench"}.get(str(rod.get("source", "")), "")) if not rod.get("owned", false) else "",
		# A workbench item (SGODOT-231 B2-06): its effect line, then In Gear for an owned pickaxe.
		craft_effect = str(P0MaterialLogic.EFFECTS.get(item_id, "")),
		craft_note = _craft_note(view, item_id),
		weapon_effect = P0Logic.GearLogic.weapon_effect(item_id),
		weapon_tier = "T%d" % int(rod.tier) if rod.has("tier") else "",
		weapon_source = P0Logic.GearLogic.weapon_source(view, item_id) if kind == "weapon" else "",
		weapon_gate = P0Logic.GearLogic.weapon_gate(view, item_id) if kind == "weapon" else "",
		potion_effect = P0Logic.GearLogic.potion_effect(item_id),
		# Decorate (SGODOT-284, q(111) / q(113)): a piece's footprint, its row line (`1×1 · Classic lamp` /
		# `5 pieces`) and the row's third line — the levels still to go while it is locked, else `In storage ×2`.
		footprint = P0Decor.footprint(item_id) if kind == "decor" else "",
		decor_line = P0Decor.line(item_id) if kind == "decor" else "",
		decor_third = _decor_third(view, item_id, offer) if kind == "decor" else "",
		# Recipe Cards (§9.11.1 / §9.11.2): the rarity alone — `Fine` at the stall, `Regional · Legendary` for the
		# Market's regional cards — beside a grey `Need 240 more coins` the row stays one line each (不知火舞 on 282).
		card_line = _card_line(view, offer, opts) if kind == "card" else "",
	}
	if kind == "potion": t.use = t.potion_effect
	if kind == "weapon": t.craft_effect = t.weapon_effect
	var src := str(t.source)
	t.count_source = ("%s · %s" % [t.count, src]) if src != "" and t.count != "" else ""
	return t

## A Decor row's third line (FARM-6-DECOR): `1 level to go` / `3 levels to go` while the stall holds it back, else
## `In storage ×2` with some in Farm Storage, else nothing.
static func _decor_third(view: Dictionary, item_id: String, offer: Dictionary) -> String:
	if not bool(offer.get("homestead_ok", true)) and offer.get("homestead", null) != null:
		var n := maxi(1, int(offer.homestead) - int(view.get("homestead", {}).get("level", 1)))
		return "%d level%s to go" % [n, "" if n == 1 else "s"]
	var n := P0Decor.stored(view, item_id)
	return "In storage ×%d" % n if n > 0 else ""

## The workbench card's second line: an owned pickaxe is In Gear, the Gather Gloves work without a slot (GLOVES-DONE copy).
static func _craft_note(view: Dictionary, item_id: String) -> String:
	for r in view.get("workbench", {}).get("recipes", []):
		if str(r.get("item", "")) != item_id or not r.get("owned", false): continue
		if str(r.get("to", "")) == "gear": return "In Gear"   # the Gather Gloves' passive note left with 丁11
	return ""

static func _deliverable(view: Dictionary, item_id: String, target: Dictionary) -> bool:
	if not target.has("request"): return false
	for r in view.get("stall", {}).get("board", {}).get("requests", []):
		if str(r.get("id", "")) == str(target.request) and str(r.get("item", "")) == item_id:
			return str(r.get("status", "")) == "accepted"
	return false

static func _dex(view: Dictionary) -> String:
	var dex: Array = view.get("fishing", {}).get("dex", [])
	if dex.is_empty(): return ""
	return "%d/%d" % [dex.filter(func(d): return int(d.get("caught", 0)) > 0).size(), dex.size()]

## A tool's Gear row: view.gear.rods / picks / hoes ({id, name, owned, equipped, ...}).
static func _rod(view: Dictionary, item_id: String) -> Dictionary:
	if item_id.begins_with("weapon_"):
		for r in P0Logic.GearLogic.weapon_rows(view):
			if str(r.id) == item_id: return r
		return P0Logic.GearLogic.weapon(item_id)
	for list in ["rods", "picks", "hoes"]:
		for r in view.get("gear", {}).get(list, []):
			if str(r.get("id", "")) == item_id: return r
	return {}

## "Lands up to Fine fish · Bite window 2.2 s": the window is absolute, the content's hook window plus the rod's bonus
## (安其拉 225 walkthrough 76834e35), so the Starter Rod has a line too. One sentence a translation reads whole (#649
## 第二批 ⑥, zh-11): built of parts, the place line's `%s to %s · %s` took it (「距 上品鱼 Lands up · 咬钩窗口 2.2 秒」).
static func _rod_effect(view: Dictionary, rod: Dictionary) -> String:
	if rod.is_empty() or not rod.has("reach"): return ""
	var reach := P0Logic.rarity_name(view, int(rod.get("reach", 1)))
	var window := int(P0Logic.content().get("fishing", {}).get("hook_window_ms", 0))
	if window <= 0: return "Lands up to %s fish" % reach
	return "Lands up to %s fish · Bite window %.1f s" % [reach, float(window + int(rod.get("hook_bonus_ms", 0))) / 1000.0]

## q(278) (SGODOT-386; 不知火舞's spec, 李白's words): the top tier a rod lands and the Fishing levels its fish need, from
## the content's fish, lowest to highest (`LvX` when one) — Carbon Rod `Legendary needs Fishing Lv7–9`, Reed Rod `Rare
## needs Fishing Lv4–6`, Starter Rod `Fine needs Fishing Lv2–3` — while some are above the rod's own level (it lands
## the tier, its fish still break free below theirs) and the player is short of the highest; "" otherwise.
static func rod_tier(view: Dictionary, rod: Dictionary) -> String:
	if not rod.has("reach"): return ""
	var reach := int(rod.reach)
	var levels: Array = []
	for f in P0Logic.content().get("fish", []):
		if int(f.get("rarity", 0)) == reach: levels.append(int(f.get("level", 1)))
	if levels.is_empty(): return ""
	var lo: int = levels.min()
	var hi: int = levels.max()
	if hi <= int(rod.get("level", 1)) or int(view.get("skills", {}).get("fishing", {}).get("level", 1)) >= hi: return ""
	return "%s needs Fishing %s" % [P0Logic.rarity_name(view, reach), ("Lv%d" % lo) if lo == hi else ("Lv%d–%d" % [lo, hi])]

## Line 2 of a buy row for goods that aren't seeds / bait / fertilizer: where they go (view.shops[role].buy `to`).
static func _offer_use(view: Dictionary, offer: Dictionary) -> String:
	match str(offer.get("to", "")):
		"storage": return "Goes to your Farm Storage"
		"bag_cap":
			# the tier's own slots (+5), not its capacity less the bag's now: Upgrade II, bought only after I, said `+10`
			# to a bag still at 25 (不知火舞 on 283, q(194))
			var more := P0Logic.bag_tier_slots(str(offer.get("id", "")))
			return ("+%d bag slots" % more) if more > 0 else ""
	return ""

## A buy row's materials line (不知火舞 on 284, q(174)): the full list ran past the row beside a grey key (`Hardwood 0/4 ·
## Clay 0/6 · C…`), so the first material still short and how many others are short too (`Hardwood 0/4 · +2 more`, the
## game's `+N more`), `Hardwood 0/4` alone, or `Materials ready` once every one is in.
static func _materials_line(offer: Dictionary) -> String:
	var short: Array = (offer.get("materials", []) as Array).filter(func(m): return int(m.get("have", 0)) < int(m.get("need", 0)))
	if short.is_empty(): return "Materials ready"
	var first: Dictionary = short[0]
	var line := "%s %d/%d" % [str(first.get("name", "")), int(first.get("have", 0)), int(first.get("need", 0))]
	return line + ((SEP + "+%d more" % (short.size() - 1)) if short.size() > 1 else "")

## "10 Reeds" — the first material still short for a buy row, "" when all are in.
static func _materials_short(offer: Dictionary) -> String:
	for m in offer.get("materials", []):
		var short := int(m.get("need", 0)) - int(m.get("have", 0))
		if short > 0: return "%d %s" % [short, str(m.get("name", ""))]
	return ""

static func _sell_all_label(count: int, sellable: int, each: int) -> String:
	if each < 0 or sellable <= 0: return ""
	if sellable < count: return "Sell %d%s%d coins" % [sellable, SEP, sellable * each]   # quota can't take the whole stack
	return "Sell All%s%d coins" % [SEP, count * each]

## STALL-NEW-2 (E-04, 1378:93021): the gate line of a seed unlocked since the stall was last opened, until the next visit.
const NEW_FOR_YOU := "◆ New for you"

## opts.new_ids: the offers new to this visit (P0Ui.stall_new_ids, through the counter drawer's opts).
static func _new_offer(item_id: String, opts: Dictionary) -> bool:
	return (opts.get("new_ids", []) as Array).has(item_id)

## A seed row's line 2: how long it takes on this farm. A regional crop away from its climate zone ripens ×1.5 there
## (the view's grow_h is already that time) and says so (§5.2.3, glossary off_zone_penalty `not native`).
## What a fertiliser does, the words of Figma NPC-2 (不知火舞): Compost `Crops ready 20% sooner` (q(46)), Orchard Feed
## `Next regrow time −50%` — no hours: trees regrow at their own pace and the card does not know which one it feeds.
static func fert_use(item_id: String) -> String:
	var g: Dictionary = P0Logic.content().get("goods", {}).get(item_id, {})
	if g.has("regrow_mult"): return "Next regrow time −%d%%" % roundi((1.0 - float(g.regrow_mult)) * 100.0)
	if g.has("grow_mult"): return "Crops ready %d%% sooner" % roundi((1.0 - float(g.grow_mult)) * 100.0)
	return "Grows faster"

## q(247): a seed's static duration is seconds below one minute, then the usual minute/hour format, never m:ss.
static func grow_time(crop: Dictionary) -> String:
	if not crop.has("grow_s") and not crop.has("grow_h"): return ""
	var seconds := float(crop.grow_s) if crop.has("grow_s") else float(crop.grow_h) * 3600.0
	return "%ds" % ceili(seconds) if seconds < 60.0 else hours(seconds / 3600.0)

static func _seed_use(crop: Dictionary) -> String:
	if grow_time(crop) == "": return ""
	var line := "Ready in " + grow_time(crop)
	return line + (SEP + "not native" if crop.has("native") and not bool(crop.native) else "")

static func _stock_line(offer: Dictionary, count: int) -> String:
	var bag := "Bag ×%d" % count
	if not bool(offer.get("unlocked", true)) and offer.has("xp_to_go"): return "%d XP to go" % int(offer.xp_to_go)
	if offer.get("left", null) != null and offer.has("daily"): return "Stock %d/%d%s%s" % [int(offer.left), int(offer.daily), SEP, bag]
	return bag

static func _price(view: Dictionary, item_id: String, opts: Dictionary) -> Dictionary:
	var offer := _offer(view, item_id, opts)
	if offer.is_empty(): return {}
	var each := int(offer.get("price", 0))
	var qty := maxi(1, int(opts.get("qty", 1)))
	return {each = each, total = each * qty, text = "%s coins" % _P0Travel.grouped(each * qty),
		line = ("%d × %s coins" % [qty, _P0Travel.grouped(each)]) if qty > 1 else ""}

static func _quota(view: Dictionary, item_id: String, kind: String, opts: Dictionary) -> Dictionary:
	return _quota_line(_quota_of(view, item_id, opts), "" if _regional(view, item_id, opts) else kind, _counter(opts), view)

## Whether this counter buys the item back as one of the city's regional goods (the Market Square).
static func _regional(view: Dictionary, item_id: String, opts: Dictionary) -> bool:
	return bool(_buyback(view, item_id, opts).get("regional", false))

## The counter's own line with nothing selected (the counter drawer's scope row): the first kind it counts against a
## quota (an older server's Tackle Shop and Market, q(9)), else its price line (q(252) ①).
static func counter_quota(view: Dictionary, role: String) -> Dictionary:
	if role != "homestead":
		for e in view.get("shops", {}).get(role, {}).get("sell", []):
			if e.get("quota", null) != null:   # the market (NPC-3 482:120): "Buy-back today 30/60" over "all San Francisco markets · resets in 9h 12m"
				return _quota_line(view.get("quotas", {}).get(str(e.quota), {}), "" if e.get("regional", false) else str(e.get("kind", "")), role, view)
	return _quota_line({}, "", role, view)

## How far this counter's city is from home (q(251) ②, view.shops[role].distance: {home, factor, km, trip, band});
## {} from an older server, which still counts the Tackle Shop's and Market's quotas.
static func distance(view: Dictionary, role: String) -> Dictionary:
	var d = view.get("shops", {}).get(role, {}).get("distance", null)
	return d if d is Dictionary else {}

## A counter away from home pays less than home (q(251) ②).
static func away(view: Dictionary, role: String) -> bool:
	var d := distance(view, role)
	return not d.is_empty() and not bool(d.get("home", true))

## The price line where no quota counts (q(252) ①): `Home price` at home, else `80% of home price` over the city row's
## `1,093 km · Trip 4 · Long Haul`; {} from an older server at a counter with no quota (it said nothing there).
static func price_line(view: Dictionary, role: String) -> Dictionary:
	var d := distance(view, role)
	if d.is_empty():
		return {text = "Crops & fish · no daily limit", note = "", have = 0, total = 0} if role == "homestead" else {}
	if bool(d.get("home", true)): return {text = "Home price", note = "", have = 0, total = 0}
	return {text = "%d%% of home price" % roundi(float(d.get("factor", 1.0)) * 100.0), have = 0, total = 0,
		note = "%s km · Trip %d · %s" % [_P0Travel.grouped(int(d.get("km", 0))), int(d.get("trip", 0)), str(d.get("band", ""))]}

static func _quota_line(quota: Dictionary, kind: String, role: String, view := {}) -> Dictionary:
	var q := quota
	if not q.is_empty() and not q.has("label"): q = q.merged({label = kind.capitalize()})   # "Fish buy-back today 30/80"
	if q.is_empty(): return price_line(view, role)
	# "Buy-back today 30/60" at a market, "Fish buy-back today 30/80" at the tackle shop (F-07): label = category.
	var text := ("%s buy-back today %d/%d" % [str(q.get("label", "")), int(q.get("used", 0)), int(q.get("cap", 0))]).strip_edges()
	text = text.left(1).to_upper() + text.substr(1)
	var note := str(q.get("scope", ""))
	if q.has("resets_in"): note = SEP.join(PackedStringArray([note, "resets in " + P0Logic.span(float(q.resets_in))])).trim_prefix(SEP)
	return {text = text, note = note, have = int(q.get("used", 0)), total = int(q.get("cap", 0))}
