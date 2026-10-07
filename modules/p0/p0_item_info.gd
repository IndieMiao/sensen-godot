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

const CONTEXTS: Array[StringName] = [&"bag", &"gear", &"counter_buy", &"counter_sell", &"gift", &"storage"]
const RULES_PATH := "res://modules/p0/item_info_rules.json"
const KINDS := ["seed", "crop", "fish", "dish", "bait", "rod", "pick"]
const SEP := " · "
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
	var k := str(P0Logic.item(view, item_id).get("kind", ""))
	if k == "":
		var head := item_id.split("_")[0]
		k = head if head in KINDS + ["fert"] else "material"
	return str(_KIND_ALIAS.get(k, k))

## The bag drawer Tab an item sits on (§10.4.2): seeds and fertilizer on Seeds, crops on Produce, bait and rods on
## Tackle, torches and the rest on Materials (周瑜 / 刘邦).
## Kinds the plan doesn't put on a Tab (postcards, décor; §10.4.8 keepsakes go to storage) get &"": All only (刘邦).
static func tab_of(view: Dictionary, item_id: String) -> StringName:
	var k := str(P0Logic.item(view, item_id).get("kind", ""))
	if k == "": k = item_id.split("_")[0]
	var tab = {"seed": &"seeds", "fert": &"seeds", "fish": &"fish", "crop": &"produce", "dish": &"dishes", "bait": &"tackle",
		"rod": &"tackle", "pick": &"tackle", "material": &"materials", "torch": &"materials"}.get(k, null)
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
	var badge: StringName = &"locked" if f.locked else (&"pinned" if f.pinned else &"")
	var out := {
		card = not rule.is_empty(),
		id = item_id,
		kind = kind,
		icon = P0Logic.icon(item_id),
		title = P0Logic.item_name(view, item_id),
		quantity = P0Logic.bag_count(view, item_id),
		info = true,
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
	if rule.is_empty(): return out
	for line in rule.get("facts", []):
		var text := fill(str(line), t)
		if text != "": out.facts.append(text)
	out.buttons = _buttons(rule, f, t)
	if rule.get("price", false): out.price = _price(view, item_id, opts)
	if rule.get("quota", false): out.quota = _quota(view, item_id, kind, opts)
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

## The shop's offer row for a Buy list: view.shops[role].buy (SGODOT-228), else the older stall / tackle lists.
static func _offer(view: Dictionary, item_id: String, opts: Dictionary) -> Dictionary:
	var role := _counter(opts)
	var lists := []
	var shop: Dictionary = view.get("shops", {}).get(role, {})
	if shop.has("buy"): lists.append(shop.buy)
	lists.append(view.get("tackle", {}).get("buy", []) if role == "tackle" else view.get("stall", {}).get("buy", []))
	for l in lists:
		for o in l:
			if str(o.get("id", "")) == item_id: return o
	return {}

## This counter's buy-back entry for the item's kind ({kind, rate, quota}), {} when it doesn't take the kind.
## view.shops[role].sell (SGODOT-228); without it the Homestead Stall takes crops and fish at full price.
static func _buyback(view: Dictionary, item_id: String, opts: Dictionary) -> Dictionary:
	var kind := kind_of(view, item_id)
	var shop: Dictionary = view.get("shops", {}).get(_counter(opts), {})
	if shop.has("sell"):
		for e in shop.sell:
			if str(e.get("kind", "")) == kind: return e
		return {}
	return {kind = kind, rate = 1.0, quota = null} if _counter(opts) == "homestead" and kind in ["crop", "fish"] else {}

## What this counter pays for one (view.items[id].sell is the Homestead price; a rate below 1 rounds down), or -1.
static func _sell_here(view: Dictionary, item_id: String, opts: Dictionary) -> int:
	var base = P0Logic.item(view, item_id).get("sell", null)
	var e := _buyback(view, item_id, opts)
	if e.is_empty() or base == null: return -1
	return int(floor(float(base) * float(e.get("rate", 1.0))))

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
		locked = bool(stack.get("locked", false)),
		gifted = gifted,
		mystery = item_id.split("@")[0] == _MYSTERY,
		never_sold = gifted or item_id.split("@")[0] in [_MYSTERY, "dish_travel_biscuits"],
		sold_here = _sell_here(view, item_id, opts) >= 0,
		quota_left = quota.is_empty() or int(quota.get("used", 0)) < int(quota.get("cap", 0)),
		energy_full = int(e.get("value", 0)) >= int(e.get("max", 200)),
		unlocked = bool(offer.get("unlocked", true)),
		homestead_ok = bool(offer.get("homestead_ok", true)),
		sold_out = offer.get("left", null) != null and int(offer.left) <= 0,
		can_afford = int(view.get("coins", 0)) >= (wallet if qty == 1 else wallet + int(offer.get("price", 0)) * (qty - 1)),
		take_some = _stored(view, item_id) > _TAKE_SOME,
		owned = bool(rod.get("owned", offer.get("owned", false))),
		equipped = bool(rod.get("equipped", false)),
		has_friends = int(view.get("social", {}).get("mutual", 0)) > 0,
		has_target = not target.is_empty() and target.has("kind"),
		player_target = str(target.get("kind", "")) == "player",
		resident_target = str(target.get("kind", "")) == "resident",
		gifted_today = bool(target.get("gifted_today", false)),
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
	if not quota.is_empty(): sellable = mini(count, maxi(0, int(quota.get("cap", 0)) - int(quota.get("used", 0))))
	var rod := _rod(view, item_id)
	var t := {
		count = str(count) if count > 0 else "",
		source = {"crop": "Harvested at home"}.get(kind, str(stack.get("source", ""))),
		sell = str(int(it.sell)) if it.get("sell", null) != null else "",
		count_source = "",
		sell_here = str(here) if here >= 0 else "",
		sell_at_home = ("Sells for %d at home" % int(it.sell)) if it.get("sell", null) != null else "",
		energy = str(int(crop.energy)) if crop.has("energy") else "",
		grow = hours(float(crop.grow_h)) if crop.has("grow_h") else "",
		stored = str(_stored(view, item_id)) if _stored(view, item_id) > 0 else "",
		take_some = "Take %d" % _TAKE_SOME,
		homestead_gate = ("Homestead Lv%d needed" % int(offer.homestead)) if offer.get("homestead", null) != null else "",
		xp_hint = "",
		use = "",
		region_line = "",
		pin_verb = "Unpin" if opts.get("pinned", false) else "Pin",
		dex = _dex(view),
		meal = str(int(it.get("meal", 0))) if kind == "dish" else "",
		eat_label = str(P0Logic.eat_button(view, item_id).get("text", "")) if kind == "dish" else "",
		gifted_line = "Gifted · can't be sold · can eat · can gift to a Resident" if stack.get("gifted", false) else "",
		expires_line = ("Expires in " + P0Logic.duration(float(stack.expires_in))) if stack.has("expires_in") else "",
		affinity_line = "",
		gift_label = ("Gift · +%d" % int(opts.target.preview)) if opts.get("target", {}).has("preview") else "Gift",
		sell_all_label = _sell_all_label(count, sellable, here),
		quota_resets_in = P0Logic.duration(float(quota.get("resets_in", 0))) if quota.has("resets_in") else "",
		stock_line = _stock_line(offer, count),
		gate_text = ("%s Lv%d needed" % [str(offer.get("skill", "")).capitalize(), int(offer.get("gate", 0))]) if offer.has("gate") else "",
		# Daily stock comes back at the day's rollover, the same moment as Rest (view.rest.resets_in).
		restock_in = P0Logic.duration(float(view.get("rest", {}).get("resets_in", 0))) if view.get("rest", {}).has("resets_in") else "",
		coins_short = str(maxi(0, int(offer.get("need", int(offer.get("price", 0)))) + int(offer.get("price", 0)) * (maxi(1, int(opts.get("qty", 1))) - 1) - int(view.get("coins", 0)))),
		rod_effect = _rod_effect(view, rod),
		rod_gate = "" if rod.get("owned", false) or rod.is_empty() else "Fishing Lv%d · Tackle Shop" % int(rod.get("level", 1)),
		owned_line = "In Gear" if rod.get("owned", false) else "",
		# LOCK-29: "1 Stone per rock"; where a pickaxe comes from while it isn't owned (Copper Pickaxe: Workbench).
		pick_effect = ("%d Stone per rock" % int(rod.stone)) if rod.has("stone") else "",
		pick_source = str({"start": "Starter", "workbench": "Workbench"}.get(str(rod.get("source", "")), "")) if not rod.get("owned", false) else "",
	}
	var src := str(t.source)
	t.count_source = ("%s · %s" % [t.count, src]) if src != "" and t.count != "" else ""
	return t

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

## A tool's Gear row: view.gear.rods / view.gear.picks ({id, name, owned, equipped, ...}).
static func _rod(view: Dictionary, item_id: String) -> Dictionary:
	for list in ["rods", "picks"]:
		for r in view.get("gear", {}).get(list, []):
			if str(r.get("id", "")) == item_id: return r
	return {}

static func _rod_effect(view: Dictionary, rod: Dictionary) -> String:
	if rod.is_empty(): return ""
	var line := "Lands up to %s fish" % P0Logic.rarity_name(view, int(rod.get("reach", 1)))
	if int(rod.get("hook_bonus_ms", 0)) > 0: line += SEP + "Bite window +%.1f s" % (float(rod.hook_bonus_ms) / 1000.0)
	return line

static func _sell_all_label(count: int, sellable: int, each: int) -> String:
	if each < 0 or sellable <= 0: return ""
	if sellable < count: return "Sell %d%s%d coins" % [sellable, SEP, sellable * each]   # quota can't take the whole stack
	return "Sell All%s%d coins" % [SEP, count * each]

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
	return {each = each, total = each * qty, text = "%d coins" % (each * qty), line = ("%d × %d coins" % [qty, each]) if qty > 1 else ""}

static func _quota(view: Dictionary, item_id: String, kind: String, opts: Dictionary) -> Dictionary:
	var q := _quota_of(view, item_id, opts)
	if not q.is_empty() and not q.has("label"): q = q.merged({label = kind.capitalize()})   # "Fish buy-back today 30/80"
	if q.is_empty():
		return {text = "Crops & fish · no daily limit", note = "", have = 0, total = 0} if _counter(opts) == "homestead" else {}
	# "Buy-back today 30/60" at a market, "Fish buy-back today 30/80" at the tackle shop (F-07): label = category.
	var text := ("%s buy-back today %d/%d" % [str(q.get("label", "")), int(q.get("used", 0)), int(q.get("cap", 0))]).strip_edges()
	text = text.left(1).to_upper() + text.substr(1)
	var note := str(q.get("scope", ""))
	if q.has("resets_in"): note = SEP.join(PackedStringArray([note, "resets in " + P0Logic.duration(float(q.resets_in))])).trim_prefix(SEP)
	return {text = text, note = note, have = int(q.get("used", 0)), total = int(q.get("cap", 0))}
