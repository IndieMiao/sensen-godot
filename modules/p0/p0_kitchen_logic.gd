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
	return "Ready" if left <= 0.0 else "Cooking " + P0Logic.duration(left)

## "Lv4 · 60 XP to go" for the locked 3rd slot (SGODOT-203: the 90 px label holds the short form); "Lv4" when
## the cooking thresholds are unknown.
static func locked_slot_label(view: Dictionary) -> String:
	var thresholds: Array = P0Logic.content().get("skills", {}).get("cooking", [])
	var xp := int(view.get("skills", {}).get("cooking", {}).get("xp", 0))
	if thresholds.size() < LOCKED_SLOT_LEVEL: return "Lv%d" % LOCKED_SLOT_LEVEL
	return "Lv%d · %d XP to go" % [LOCKED_SLOT_LEVEL, maxi(0, int(thresholds[LOCKED_SLOT_LEVEL - 1]) - xp)]

# ---------------------------------------------------------------- Cookbook
static func pages(view: Dictionary) -> Array: return cooking(view).get("cookbook", [])

static func cookbook_count(view: Dictionary) -> String:
	var all := pages(view)
	return "%d/%d" % [all.filter(func(p): return p.get("known", false)).size(), all.size()]

## Pages in the grid order of §7.2.7: can cook (rarity high → low) → known but short → unknown.
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
	if p.get("known", false): return 1
	return 2

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
	if not p.get("known", false):
		cell.kitchen_state = K.LOCKED if int(p.get("slots", 1)) > slots(view) else K.HIDDEN
		if cell.kitchen_state == K.LOCKED: cell.status = "Lv%d" % LOCKED_SLOT_LEVEL
		return cell
	cell.icon = P0Logic.icon(str(p.id))
	if not p.get("cooked", false): cell.kitchen_state = K.TASTED
	cell.marked = bool(p.get("can_cook", false))
	return cell

## The detail card and its button (Compact/Kitchen/Recipe): {title, state, effect, icon, button, reason, nav}.
## button "Cook" when it can cook; otherwise `reason` says the first gap (LOCK-10: the gap on the button);
## unknown pages only guide to Experiment (`nav`, never puts anything in the pot).
static func page_card(view: Dictionary, p: Dictionary) -> Dictionary:
	var rarity := int(p.get("rarity", 1))
	var tier: Dictionary = cooking(view).get("tiers", {}).get(str(rarity), {})
	var card := {icon = null, effect = "+%d Energy" % int(tier.get("energy", 0)), button = "", reason = "", nav = ""}
	if not p.get("known", false):
		card.title = "Unknown dish"
		var n := int(p.get("slots", 1))
		card.state = "%s · %d %s" % [P0Logic.rarity_name(view, rarity), n, "ingredient" if n == 1 else "ingredients"]
		if n > slots(view): card.reason = "Cooking Lv%d · 3rd slot" % LOCKED_SLOT_LEVEL
		else: card.nav = "Try in Experiment"
		return card
	card.title = str(p.get("name", ""))
	card.icon = P0Logic.icon(str(p.id))
	card.state = "%s · %s" % [P0Logic.rarity_name(view, rarity), "Cooked" if p.get("cooked", false) else "Discovered"]
	if p.get("can_cook", false): card.button = "Cook"
	elif int(p.get("slots", 1)) > slots(view): card.reason = "Cooking Lv%d · 3rd slot" % LOCKED_SLOT_LEVEL
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
