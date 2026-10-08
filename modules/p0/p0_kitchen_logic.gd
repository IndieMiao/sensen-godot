class_name P0KitchenLogic
extends RefCounted
## What the cooking drawer and the stove stage show, from the P0 server view (SGODOT-226, LOCK-20 v5; plan
## §7.2.3 / §7.2.7; Figma COOK-2a / COOK-2b). Pure functions, unit-tested; the drawer and stage only draw them.
## P0 has one stove (Stove 1/1). Pot contents are item ids, one entry per unit (the same id may fill two slots).

const FAMILY_OF_CHIP := {"Fish": "W", "Produce": "F", "Fruit": "O", "Seasoning": "S"}
const COOKBOOK_CHIPS := ["All", "Can cook", "Common", "Fine", "Rare", "Legendary"]
const EXPERIMENT_CHIPS := ["All", "Fish", "Produce", "Fruit", "Seasoning"]
const LOCKED_SLOT_LEVEL := 4   # the 3rd slot opens at Cooking Lv4 (§7.2.3)

static func cooking(view: Dictionary) -> Dictionary: return view.get("cooking", {})

## The P0 stove's pot, or null when empty. Reads cooking.stoves[0] when the server sends the stove list
## (SGODOT-232, Queue ×2), else cooking.stove.
static func stove(view: Dictionary):
	var list = cooking(view).get("stoves", null)
	if list is Array:
		if list.is_empty() or not (list[0] is Dictionary): return null
		return list[0] if list[0].get("ms", list[0].get("ready_in", null)) != null else null
	return cooking(view).get("stove", null)
static func slots(view: Dictionary) -> int: return int(cooking(view).get("slots", 2))
static func level(view: Dictionary) -> int: return int(view.get("skills", {}).get("cooking", {}).get("level", 1))

# ---------------------------------------------------------------- drawer header (q(31): stove · level · state)
static func header(view: Dictionary) -> Dictionary:
	return {stove = "Stove 1/1", level = "Cooking Lv%d" % level(view), state = stove_state(view)}

static func stove_state(view: Dictionary) -> String:
	var st = stove(view)
	if st == null: return "Empty"
	var left := float(st.get("ready_in", 0))
	var queued := " · Queued 1" if cooking(view).get("queued", null) is Dictionary else ""   # S5 Queue ×2 (Lv5)
	return ("Ready" if left <= 0.0 else "Cooking " + P0Logic.duration(left)) + queued

## "Lv4 · 60 XP to go" for the locked 3rd slot (SGODOT-203: the 90 px label holds the short form); "Lv4" when
## the cooking thresholds are unknown.
static func locked_slot_label(view: Dictionary) -> String:
	var third = cooking(view).get("third_slot", null)   # S5: {level, xp_to_go} from the server
	if third is Dictionary: return "Lv%d · %d XP to go" % [int(third.get("level", LOCKED_SLOT_LEVEL)), int(third.get("xp_to_go", 0))]
	var thresholds: Array = P0Logic.content().get("skills", {}).get("cooking", [])
	var xp := int(view.get("skills", {}).get("cooking", {}).get("xp", 0))
	if thresholds.size() < LOCKED_SLOT_LEVEL: return "Lv%d" % LOCKED_SLOT_LEVEL
	return "Lv%d · %d XP to go" % [LOCKED_SLOT_LEVEL, maxi(0, int(thresholds[LOCKED_SLOT_LEVEL - 1]) - xp)]

# ---------------------------------------------------------------- Cookbook
static func pages(view: Dictionary) -> Array: return cooking(view).get("cookbook", [])

static func cookbook_count(view: Dictionary) -> String:
	if cooking(view).has("pages_total"): return "%d/%d" % [int(cooking(view).get("discovered", 0)), int(cooking(view).pages_total)]   # S5
	var all := pages(view)
	return "%d/%d" % [all.filter(func(p): return p.get("known", false)).size(), all.size()]

## Pages in the grid order of §7.2.7: can cook (rarity high → low) → discovered but short → Tasted → clued → unknown.
static func cookbook_order(view: Dictionary, chip := "All") -> Array:
	var out := pages(view).filter(func(p): return _chip_keeps(view, p, chip))
	out.sort_custom(func(a, b):
		var ra := _rank(a)
		var rb := _rank(b)
		if ra != rb: return ra < rb
		if int(a.rarity) != int(b.rarity): return int(a.rarity) > int(b.rarity) if ra == 0 else int(a.rarity) < int(b.rarity)
		return str(a.id) < str(b.id))
	return out

static func _rank(p: Dictionary) -> int:
	if p.get("can_cook", false): return 0
	match str(p.get("state", "")):   # S5 page states; without them, known / unknown
		"discovered", "mastered": return 1
		"tasted": return 2
		"clued": return 3
		"hidden": return 4
	return 1 if p.get("known", false) else 4

static func _chip_keeps(view: Dictionary, p: Dictionary, chip: String) -> bool:
	match chip:
		"All": return true
		"Can cook": return bool(p.get("can_cook", false))
	var rarity := COOKBOOK_CHIPS.find(chip) - 1   # Common = 1 …
	return int(p.get("rarity", 0)) == rarity

## One Cookbook page as a kitchen cell (Compact/Kitchen/Cell states).
static func page_cell(view: Dictionary, p: Dictionary) -> Dictionary:
	var K := UiItemCell.KitchenState
	var cell := {id = str(p.id), rarity = int(p.get("rarity", 1)), kitchen_state = K.DEFAULT, marked = false, status = ""}
	if p.has("state"): return _page_cell_s5(view, p, cell)
	if not p.get("known", false):
		cell.kitchen_state = K.LOCKED if int(p.get("slots", 1)) > slots(view) else K.HIDDEN
		if cell.kitchen_state == K.LOCKED: cell.status = "Lv%d" % LOCKED_SLOT_LEVEL
		return cell
	cell.icon = P0Logic.icon(str(p.id))
	if not p.get("cooked", false): cell.kitchen_state = K.TASTED
	cell.marked = bool(p.get("can_cook", false))
	return cell

## S5 pages carry their state (hidden / clued / tasted / discovered / mastered) and the 3rd-slot lock.
static func _page_cell_s5(_view: Dictionary, p: Dictionary, cell: Dictionary) -> Dictionary:
	var K := UiItemCell.KitchenState
	var lock = p.get("lock", null)
	match str(p.state):
		"hidden", "clued":
			cell.kitchen_state = K.CLUED if str(p.state) == "clued" else K.HIDDEN
			if lock is Dictionary:
				cell.kitchen_state = K.LOCKED
				cell.status = "Lv%d" % int(lock.get("level", LOCKED_SLOT_LEVEL))
			return cell
		"tasted": cell.kitchen_state = K.TASTED
		"mastered": cell.kitchen_state = K.MASTERED
	cell.icon = P0Logic.icon(str(p.id))
	cell.marked = bool(p.get("can_cook", false))
	return cell

## The detail card and its button (Compact/Kitchen/Recipe): {title, state, effect, icon, button, reason, nav}.
## button "Cook" when it can cook; otherwise `reason` says the first gap (LOCK-10: the gap on the button);
## unknown pages only guide to Experiment (`nav`, never puts anything in the pot).
static func page_card(view: Dictionary, p: Dictionary) -> Dictionary:
	var rarity := int(p.get("rarity", 1))
	var tier: Dictionary = cooking(view).get("tiers", {}).get(str(rarity), {})
	var card := {icon = null, effect = "+%d Energy" % int(tier.get("energy", 0)), button = "", reason = "", nav = ""}
	var locked: bool = p.get("lock", null) is Dictionary or (not p.has("state") and int(p.get("slots", 1)) > slots(view))
	if not p.get("known", false):
		card.title = "Unknown dish"
		var n := int(p.get("slots", 1))
		card.state = "%s · %d %s" % [P0Logic.rarity_name(view, rarity), n, "ingredient" if n == 1 else "ingredients"]
		if locked: card.reason = "Cooking Lv%d · 3rd slot" % LOCKED_SLOT_LEVEL
		else: card.nav = "Try in Experiment"
		return card
	card.title = str(p.get("name", ""))
	card.icon = P0Logic.icon(str(p.id))
	var made := int(p.get("cooked_total", 0))
	card.state = "%s · %s" % [P0Logic.rarity_name(view, rarity), ("Cooked ×%d" % made if made > 1 else "Cooked") if p.get("cooked", false) else ("Tasted" if str(p.get("state", "")) == "tasted" else "Discovered")]
	if p.get("can_cook", false): card.button = "Cook"
	elif locked: card.reason = "Cooking Lv%d · 3rd slot" % LOCKED_SLOT_LEVEL
	else: card.reason = missing_reason(view, p)
	return card

## "Need Wild Herb ×1": the first ingredient the bag is short of (§7.2.7 button four states).
static func missing_reason(view: Dictionary, p: Dictionary) -> String:
	var used := {}
	for token in p.get("in", []):
		var t := str(token)
		var found := ""
		for s in view.get("bag", {}).get("slots", []):
			var id := str(s.get("id", ""))
			if int(s.get("qty", 0)) - int(used.get(id, 0)) > 0 and P0Logic._token_matches(view, t, id):
				found = id
				break
		if found == "": return "Need %s ×1" % P0Logic.ingredient_label(view, t)
		used[found] = int(used.get(found, 0)) + 1
	return "Missing ingredients"

## Ghosts and slot bar for a selected page: [{id, name, icon}] per ingredient (family tokens show their label).
static func page_ingredients(view: Dictionary, p: Dictionary) -> Array:
	var out: Array = []
	for token in p.get("in", []):
		var t := str(token)
		var specific := t.length() > 2 and t != "?"
		out.append({id = t, name = P0Logic.ingredient_label(view, t) if t != "?" else "?",
			icon = P0Logic.icon(t) if specific else P0Logic.icon("question")})
	return out

# ---------------------------------------------------------------- Experiment
## Bag items for the Experiment grid: everything that can go in a pot, plus ornamental fish greyed
## (`Not for cooking`, F-07); `pot` units are taken off the count and their cells read `In pot`.
static func experiment_items(view: Dictionary, pot: Array, chip := "All") -> Array:
	var K := UiItemCell.KitchenState
	var out: Array = []
	var totals := {}   # one cell per ingredient, however many stacks it fills
	var order: Array = []
	for s in view.get("bag", {}).get("slots", []):
		var sid := str(s.get("id", ""))
		if not totals.has(sid): order.append(sid)
		totals[sid] = int(totals.get(sid, 0)) + int(s.get("qty", 0))
	for raw in order:
		var id := str(raw)
		var info := P0Logic.item(view, id)
		var cookable := bool(info.get("cook", false))
		var ornamental := not cookable and id.begins_with("fish_")
		if not cookable and not ornamental: continue
		var family := str(info.get("family", "W" if id.begins_with("fish_") else ""))
		if chip != "All" and family != str(FAMILY_OF_CHIP.get(chip, "")): continue
		var in_pot := pot.count(id)
		out.append({id = id, icon = P0Logic.icon(id), qty = int(totals[id]) - in_pot, rarity = int(info.get("rarity", 1)),
			kitchen_state = K.NOT_FOR_COOKING if ornamental else (K.IN_POT if in_pot > 0 else K.DEFAULT),
			marked = in_pot > 0, cookable = cookable})
	return out

## Whether one more `id` can go in the pot: a free slot and one left in the bag.
static func can_add(view: Dictionary, pot: Array, id: String) -> bool:
	if pot.size() >= slots(view) or not P0Logic.item(view, id).get("cook", false): return false
	return P0Logic.bag_count(view, id) - pot.count(id) > 0

static func slots_used_line(view: Dictionary, pot: Array) -> String:
	return "%d / %d slots used" % [pot.size(), slots(view)]

## Preview capsule facts (Compact/Kitchen/Preview: title · rarity · time; §7.2.7 facts only).
static func preview(view: Dictionary, pot: Array) -> Dictionary:
	if pot.is_empty(): return {title = "Add up to %d ingredients" % slots(view), state = "", time = ""}
	var fams := {}
	var top := 1
	var mains := 0
	for id in pot:
		var info := P0Logic.item(view, str(id))
		fams[str(info.get("family", "W"))] = true
		top = maxi(top, int(info.get("rarity", 1)))
		if str(info.get("family", "")) != "S": mains += 1
	if mains == 0: return {title = "Needs a main ingredient", state = "", time = ""}
	var known := P0Logic.match_known(view, pot)
	var rarity: int
	if not known.is_empty(): rarity = int(known.rarity)
	else:
		var derive: Array = cooking(view).get("derive", [[1, 2, 3], [2, 3, 3], [3, 3, 4], [4, 4, 4]])
		rarity = int(derive[clampi(top - 1, 0, derive.size() - 1)][clampi(fams.size(), 1, 3) - 1])
	var t: Dictionary = cooking(view).get("tiers", {}).get(str(rarity), {})
	return {title = str(known.name) if not known.is_empty() else "Unknown dish", state = P0Logic.rarity_name(view, rarity),
		time = "%d s" % (int(t.get("ms", 5000)) / 1000)}

## Experiment's cook row (COOK-P0-2 / 2b): "+20 Energy" when the pot is a known page, "" for an unknown mix.
static func pot_energy(view: Dictionary, pot: Array) -> String:
	if pot.is_empty(): return ""
	var known := P0Logic.match_known(view, pot)
	if known.is_empty(): return ""
	var t: Dictionary = cooking(view).get("tiers", {}).get(str(int(known.rarity)), {})
	return "+%d Energy" % int(t.get("energy", 0))

## Preview for a Cookbook page: COOK-2a writes `Ready to cook` when the page can cook now.
static func page_preview(view: Dictionary, p: Dictionary) -> Dictionary:
	var rarity := int(p.get("rarity", 1))
	var t: Dictionary = cooking(view).get("tiers", {}).get(str(rarity), {})
	var title := "Unknown dish"
	if p.get("known", false): title = "Ready to cook" if p.get("can_cook", false) else str(p.get("name", ""))
	return {title = title, state = P0Logic.rarity_name(view, rarity), time = "%d s" % (int(t.get("ms", 5000)) / 1000)}

## Experiment's Cook button: the gap when it cannot cook (LOCK-10), else "Cook" (never "Free", §7.2.7).
static func experiment_reason(view: Dictionary, pot: Array) -> String:
	if pot.is_empty(): return "Add an ingredient"
	if preview(view, pot).title == "Needs a main ingredient": return "Needs a main ingredient"
	if stove(view) != null: return "Stove busy"
	return ""

# ---------------------------------------------------------------- the dish comes out (COOK-4 / 6 / P0-9, COOK-7-2)
## Portions waiting on the stove after a collect with no room (§7.2.6, PR #20): [] when none.
static func stove_left(view: Dictionary) -> Array:
	var st = stove(view)
	if not (st is Dictionary) or st.get("left", null) == null: return []
	return st.left

## What one portion restores today (§7.17.1): the server's number when the dish sits in the bag or the Warming
## Cabinet; for a portion still on the stove the page's tier and quality, halved for a 2nd serving, 0 after.
static func meal_value(view: Dictionary, id: String) -> int:
	var info := P0Logic.item(view, id)
	if info.has("meal"): return int(info.meal)
	var cab = cooking(view).get("cabinet", null)
	if cab is Dictionary:
		for row in cab.get("items", []):
			if str(row.id) == id: return int(row.get("energy", 0))
	var base := id.get_slice("@", 0)
	var page := _page(view, base)
	if page.is_empty(): return int(P0Logic.content().get("cooking", {}).get("mystery", {}).get("energy", 5))
	var tier: Dictionary = cooking(view).get("tiers", {}).get(str(int(page.get("rarity", 1))), {})
	var quality := ["plain", "good", "perfect"].find(id.get_slice("@", 1)) if id.contains("@") else 0
	var full := int(tier.get("energy", 20)) + int((tier.get("bonus", [0, 0, 0]) as Array)[maxi(quality, 0)])
	var eaten := int(view.get("meals", {}).get("eaten", {}).get(base, 0))
	return full if eaten == 0 else (ceili(full / 2.0) if eaten == 1 else 0)

static func _page(view: Dictionary, id: String) -> Dictionary:
	for p in pages(view):
		if str(p.id) == id: return p
	return {}

## COOK-7-2 eating states, first match wins: {text, reason}. `reason` makes Eat unavailable (LOCK-10, Energy
## full, Bonus counts as full). The button says what the player really gets, the smaller of the energy room and
## the food-limit room, in one tap (q(10); no "Eat anyway?" question, An Qi La's review b7b0c99c).
static func eat_state(view: Dictionary, id: String) -> Dictionary:
	var e: Dictionary = view.get("energy", {})
	var have := int(e.get("value", 0))
	var mx := int(e.get("max", 200))
	if have >= mx: return {text = "Energy full", reason = "Energy full"}
	var value := meal_value(view, id)
	var m: Dictionary = view.get("meals", {})
	var left := maxi(0, int(m.get("cap", 200)) - int(m.get("used", 0)))
	if left <= 0 or value <= 0: return {text = "Eat · no Energy today", reason = ""}
	return {text = "Eat · +%d Energy" % mini(mini(value, left), mx - have), reason = ""}

## Where each portion of a collect went, from its events: id → "cabinet" / "bag" / "stove" (PR #20 events).
static func routes(events: Array) -> Dictionary:
	var out := {}
	for ev in events:
		match str(ev.get("kind", "")):
			"cabinet":
				if int(ev.delta) > 0: out[str(ev.id)] = "cabinet"
				elif int(ev.get("to_bag", 0)) > 0: out[str(ev.id)] = "bag"
			"item":
				if str(ev.id).begins_with("dish_") and int(ev.delta) > 0 and not out.has(str(ev.id)): out[str(ev.id)] = "bag"
			"plate":
				for id in ev.get("ids", []): out[str(id)] = "stove"
	return out

## The eat command for a portion that went `where` (cabinet / bag / stove), §7.2.6.
static func eat_command(id: String, where: String) -> Dictionary:
	match where:
		"cabinet": return {"type": "eat", "item": id, "from": "cabinet"}
		"stove": return {"type": "collect", "eat": true}
	return {"type": "eat", "item": id}

## KEEP-STATES (§7.2.6, appendix B.7): the toast once the player keeps the dish (Keep, or tapping outside).
## {text, tone}: tone "info" for a normal keep, "warn" when it went to the bag instead, "error" when it stayed.
static func keep_line(view: Dictionary, id: String, where: String) -> Dictionary:
	var name := str(P0Logic.item(view, id).get("name", P0Logic.item_name(view, id.get_slice("@", 0))))
	var cab = cooking(view).get("cabinet", null)
	match where:
		"cabinet": return {text = "Kept · Warming Cabinet %d/%d" % [int(cab.get("have", 0)), int(cab.get("cap", 6))] if cab is Dictionary else "Kept", tone = "info"}
		"stove": return {text = ("Cabinet and bag full · dish left on the stove" if cab is Dictionary else "Bag full · dish left on the stove"), tone = "error"}
	if cab is Dictionary: return {text = "Cabinet full · %s sent to bag" % name, tone = "warn"}
	return {text = "%s · saved to your bag" % name, tone = "info"}

## RewardMoment fields for a collected pot (COOK-4 New recipe! / COOK-6 Mystery Dish / COOK-P0-9 Dish ready).
## ev = the `dish` event; first_xp = the first-cook XP of the same reply (0 when not first); from_stove = the
## player came back to a Ready stove instead of watching the pot.
static func dish_card(view: Dictionary, ev: Dictionary, first_xp: int, from_stove: bool) -> Dictionary:
	var base := str(ev.get("dish", ""))
	var quality := int(ev.get("quality", 0))
	var id := base if quality == 0 else "%s@%s" % [base, ["plain", "good", "perfect"][quality]]
	# Newcomer Blessing: a failed pot gives its ingredients back and no dish (q(48) A; S5 none: true).
	if bool(ev.get("none", false)):
		return {tone = UiRewardMoment.Tone.NEUTRAL, event = "No dish this time", icon = P0Logic.icon("dish_mystery"),
			item_name = "Ingredients back (%d left today)" % int(ev.get("trial_left", 0)), rarity = 0, rarity_word = "", quality = 0,
			strip = "", note = "", none = true, dish_id = ""}
	if bool(ev.get("mystery", false)):
		return {tone = UiRewardMoment.Tone.NEUTRAL, event = "Mystery Dish", icon = P0Logic.icon("dish_mystery"),
			item_name = "Hmm… not a dish", rarity = 0, rarity_word = "", quality = 0,
			strip = "A clue was added to your Cookbook" if ev.get("clue", null) != null else "", strip_icon = P0Logic.icon("cookbook"),
			note = "Can't be sold or delivered", dish_id = id}
	var page := _page(view, base)
	var rarity := int(page.get("rarity", 1))
	var strip := ""
	if bool(ev.get("first", false)): strip = "First cooked · +%d Cooking XP · Cookbook %s" % [first_xp, cookbook_count(view)]
	elif from_stove: strip = "Collected from Stove 1"
	return {tone = UiRewardMoment.Tone.REWARD, event = "New recipe!" if bool(ev.get("first", false)) else "Dish ready",
		icon = P0Logic.icon(base), item_name = str(page.get("name", P0Logic.item_name(view, base))) if page.get("name", null) != null else P0Logic.item_name(view, base),
		rarity = rarity, rarity_word = P0Logic.rarity_name(view, rarity), quality = quality,
		strip = strip, strip_icon = P0Logic.icon("cookbook"), note = "Gift later from your bag", dish_id = id}

## Whether a kept portion of `id` would find a place now: a free cabinet portion, a dish stack with room, or a
## free bag slot (the server decides; this only spares a retry that would be refused, §7.2.6).
static func keep_room(view: Dictionary, id: String) -> bool:
	var cab = cooking(view).get("cabinet", null)
	if cab is Dictionary and int(cab.get("have", 0)) < int(cab.get("cap", 0)): return true
	var bag: Dictionary = view.get("bag", {})
	if int(bag.get("free", 0)) > 0: return true
	var limit := int(P0Logic.content().get("bag", {}).get("stack", {}).get("dish", 5))
	return bag.get("slots", []).any(func(b): return str(b.id) == id and not b.get("gifted", false) and int(b.qty) < limit)

# ---------------------------------------------------------------- Spice Rack / Warming Cabinet (COOK-P0-5 / P0-6)
## Spice Rack rows: the stored seasonings the stove reaches, with their real count (q(46): no cap).
static func rack_rows(view: Dictionary) -> Array:
	var rack = cooking(view).get("rack", null)
	if not (rack is Dictionary): return []
	return rack.get("items", []).map(func(i): return {id = str(i.id), title = str(i.get("name", P0Logic.item_name(view, str(i.id)))), quantity = str(int(i.qty)), unit = "items"})

## Warming Cabinet: the card title and one row per stack (★ quality, what a portion restores today, ×qty); rows
## is empty for "No dishes yet". null cabinet (before Lv3) = {}.
static func cabinet_sheet(view: Dictionary) -> Dictionary:
	var cab = cooking(view).get("cabinet", null)
	if not (cab is Dictionary): return {}
	var rows: Array = []
	for i in cab.get("items", []):
		var id := str(i.id)
		var q := ["plain", "good", "perfect"].find(id.get_slice("@", 1)) if id.contains("@") else 0
		rows.append({id = id, title = str(i.get("name", P0Logic.item_name(view, id.get_slice("@", 0)))),
			state = UiQualityBadge.LABELS[maxi(q, 0)], effect = "+%d Energy" % int(i.get("energy", 0)), quantity = "×%d" % int(i.qty)})
	return {title = "Warming Cabinet %d/%d" % [int(cab.get("have", 0)), int(cab.get("cap", 6))], rows = rows,
		empty = "No dishes yet"}

## The world badge on the cabinet (appendix B.7): "4/6", or "Full".
static func cabinet_badge(view: Dictionary) -> String:
	var cab = cooking(view).get("cabinet", null)
	if not (cab is Dictionary): return ""
	return "Full" if int(cab.get("have", 0)) >= int(cab.get("cap", 6)) else "%d/%d" % [int(cab.get("have", 0)), int(cab.get("cap", 6))]

## The selected cabinet row's buttons: Eat (COOK-7-2 states) and Take one (unavailable "Bag full", LOCK-10).
static func cabinet_actions(view: Dictionary, id: String) -> Dictionary:
	var bag: Dictionary = view.get("bag", {})
	var limit := int(P0Logic.content().get("bag", {}).get("stack", {}).get("dish", 5))
	var room: bool = int(bag.get("free", 0)) > 0 or bag.get("slots", []).any(func(b): return str(b.id) == id and not b.get("gifted", false) and int(b.qty) < limit)
	return {eat = eat_state(view, id), take = "Take one", take_reason = "" if room else "Bag full"}
