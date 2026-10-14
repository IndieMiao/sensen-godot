class_name P0KitchenLogic
extends RefCounted
## What the cooking drawer and the stove stage show, from the P0 server view (SGODOT-226, LOCK-20 v5; plan
## §7.2.3 / §7.2.7; Figma COOK-2a / COOK-2b). Pure functions, unit-tested; the drawer and stage only draw them.
## Stoves: 1 at Homestead Lv1–3, 2 from Lv4, 3 from Lv8 (§7.7, SGODOT-282); every stove function takes the stove's
## 0-based index (default stove 1). Pot contents are item ids, one entry per unit (the same id may fill two slots).

const FAMILY_OF_CHIP := {"Fish": "W", "Produce": "F", "Fruit": "O", "Seasoning": "S"}
const COOKBOOK_CHIPS := ["All", "Can cook", "Common", "Fine", "Rare", "Legendary"]
const EXPERIMENT_CHIPS := ["All", "Fish", "Produce", "Fruit", "Seasoning"]
const LOCKED_SLOT_LEVEL := 4   # the 3rd slot opens at Cooking Lv4 (§7.2.3)

static func cooking(view: Dictionary) -> Dictionary: return view.get("cooking", {})

## Stove i's pot, or null when empty. Reads cooking.stoves[i] when the server sends the stove list (SGODOT-232,
## Queue ×2; one entry per stove, null when empty, SGODOT-282), else cooking.stove for stove 1.
static func stove(view: Dictionary, i := 0):
	var list = cooking(view).get("stoves", null)
	if list is Array:
		if i >= list.size() or not (list[i] is Dictionary): return null
		return list[i] if list[i].get("ms", list[i].get("ready_in", null)) != null else null
	return cooking(view).get("stove", null) if i == 0 else null

## How many stoves the kitchen has (the server's stove list, else 1).
static func stove_count(view: Dictionary) -> int:
	var list = cooking(view).get("stoves", null)
	return maxi(1, list.size()) if list is Array else 1

## `Stove 2/3`: the stove's number of the kitchen's stoves (q(31), §7.2.7).
static func stove_label(view: Dictionary, i := 0) -> String:
	return "Stove %d/%d" % [i + 1, stove_count(view)]

## The stove a cook from the Energy card / a Today row goes to: the first empty one, else the first that can queue,
## else stove 1 (§7.2.3: "the nearest free stove").
static func free_stove(view: Dictionary) -> int:
	for i in stove_count(view):
		if stove(view, i) == null: return i
	for i in stove_count(view):
		if can_queue(view, i): return i
	return 0

## An ingredient as a button's gap names it (q(112), 李白): a tag slot without its leading "Any" (`Need Legendary fish
## ×1`, `Need seasoning ×1`); the ingredient column keeps `Any Legendary fish`.
static func need_label(view: Dictionary, token: String) -> String:
	return P0Logic.ingredient_label(view, token).trim_prefix("Any ")

## Another stove's heat reminder (b84a5e01 ④): the index of the ring that comes up within `lead_ms` from now on this
## pot (its rings grow in RING_EARLY before their turn, so "comes up" is that moment), else -1.
static func ring_soon(st: Dictionary, lead_ms: float, early_ms := 1000.0) -> int:
	var e := float(st.get("elapsed", float(st.get("ms", 0)) - float(st.get("ready_in", 0))))
	var heats: Array = st.get("heats", [])
	for i in heats.size():
		var up := float(heats[i].get("at", 0)) - early_ms
		if up > e and up - e <= lead_ms: return i
	return -1

## Big Pot (Homestead Lv6): the drawer offers Double.
static func big_pot(view: Dictionary) -> bool: return bool(cooking(view).get("big_pot", false))

## The Double toggle (b84a5e01 ③) for the Cookbook's selected page (`page`) or Experiment's pot (`pot`):
## {shown, enabled, toast}. Hidden before Homestead Lv6 (no locked look); grey for a Legendary dish, a mix that makes
## no known page and seasonings alone, a tap on it saying why.
static func double_state(view: Dictionary, page := {}, pot := []) -> Dictionary:
	if not big_pot(view): return {shown = false, enabled = false, toast = ""}
	var rarity := 0
	var known := false
	if not page.is_empty():
		known = bool(page.get("known", false))
		rarity = int(page.get("rarity", 1))
	elif not pot.is_empty():
		if not has_main(view, pot): return {shown = true, enabled = false, toast = DOUBLE_KNOWN_ONLY}
		var pv := preview(view, pot)
		known = str(pv.get("title", "")) != "Unknown dish" and str(pv.get("title", "")) != ""
		rarity = int(pv.get("rarity", 1))
	if not known: return {shown = true, enabled = false, toast = DOUBLE_KNOWN_ONLY}
	if rarity >= 4: return {shown = true, enabled = false, toast = DOUBLE_NOT_LEGENDARY}
	return {shown = true, enabled = true, toast = ""}

const DOUBLE_NOT_LEGENDARY := "Double · not for Legendary dishes"
const DOUBLE_KNOWN_ONLY := "Double · known recipes only"

## Double's main key (b84a5e01 ③): `Cook ×2` / `Queue ×2`, or the first gap for two portions (LOCK-10, `Need 1 more
## Pond Crucian`); "" when the stock covers two. `tokens`: the page's ingredients or the pot's items.
static func double_gap(view_: Dictionary, tokens: Array) -> String:
	var view := with_rack(view_)
	var left := stock(view)
	for round in 2:
		for token in tokens:
			var t := str(token)
			var found := ""
			for id in left:
				if int(left[id]) > 0 and _matches(view, t, id):
					found = id
					break
			if found == "":
				var need := tokens.filter(func(x): return str(x) == t).size() * 2
				var have := 0
				for id in stock(view): if _matches(view, t, id): have += int(stock(view)[id])
				return "Need %d more %s" % [maxi(1, need - have), need_label(view, t)]
			left[found] = int(left[found]) - 1
	return ""

static func double_label(queue := false) -> String: return "Queue ×2" if queue else "Cook ×2"
static func slots(view: Dictionary) -> int: return int(cooking(view).get("slots", 2))
static func level(view: Dictionary) -> int: return int(view.get("skills", {}).get("cooking", {}).get("level", 1))

# ---------------------------------------------------------------- drawer header (q(31): stove · level · state)
## The drawer's heading leaves out `· Queued 1` (不知火舞 on #289: the stove's strip and sign say it; the heading never
## cuts its state short, and drops `Cooking LvN` before the state when the row is still too long).
static func header(view: Dictionary, i := 0) -> Dictionary:
	return {stove = stove_label(view, i), level = "Cooking Lv%d" % level(view), state = stove_state(view, i, false)}

static func stove_state(view: Dictionary, i := 0, with_queue := true) -> String:
	var st = stove(view, i)
	if st == null: return "Empty"
	var left := float(st.get("ready_in", 0))
	var queued := " · Queued 1" if with_queue and queued(view, i) != null else ""   # S5 Queue ×2 (Lv5)
	return ("Ready" if left <= 0.0 else "Cooking " + P0Logic.duration(left)) + queued

# ---------------------------------------------------------------- Queue ×2 (Cooking Lv5, q(71))
## The pot waiting behind the one on the stove ({id, dish, rarity, ms, starts_in}), or null.
static func queued(view: Dictionary, i := 0):
	var list = cooking(view).get("stoves", null)
	# The stove list carries each stove's queued pot; stove 1 also has the older top-level cooking.queued.
	var q = list[i].get("queued", null) if list is Array and i < list.size() and list[i] is Dictionary else null
	if q == null and i == 0: q = cooking(view).get("queued", null)
	return q if q is Dictionary else null

## Whether the watch sheet offers `Queue next ›`: Queue ×2 is open (Cooking Lv5), a pot is cooking and none waits.
## Lv1–4 and a full queue show nothing, not a grey button (q(71)).
static func can_queue(view: Dictionary, i := 0) -> bool:
	return cooking(view).get("conveniences", []).has("queue_two") and stove(view, i) != null and queued(view, i) == null

## The watch sheet's state line: `Cooking`, or `Cooking · Queued 1` with a pot waiting (q(71) supplement).
static func watch_state(view: Dictionary, i := 0) -> String:
	return "Cooking · Queued 1" if queued(view, i) != null else "Cooking"

## The toast when the stove turns over to the waiting pot while the player is in the kitchen (q(71)):
## "Grilled Crucian kept · Herb Grilled Fish cooking". dish_ev = the kept pot's `dish` event; next_dish = the pot now
## cooking (null when the server does not name it: an unknown mix).
static func rotation_line(view: Dictionary, dish_ev: Dictionary, next_dish) -> String:
	var kept := "Ingredients back" if bool(dish_ev.get("none", false)) else \
		"%s kept" % P0Logic.item_name(view, "dish_mystery" if bool(dish_ev.get("mystery", false)) else str(dish_ev.get("dish", "")))
	var next := P0Logic.item_name(view, str(next_dish)) if next_dish != null and str(next_dish) != "" else "Unknown dish"
	return "%s · %s cooking" % [kept, next]

## A first-time dish kept by a turn-over (q(85); 不知火舞 on 226: no COOK-4 over the next pot's rings, yet not silent): a
## Success toast `New recipe! Herb Grilled Fish kept`, without the next pot (that would wrap to three lines; the watch
## sheet already counts the next pot down). "" when the dish is not a new recipe.
static func new_recipe_line(view: Dictionary, dish_ev: Dictionary) -> String:
	if not bool(dish_ev.get("first", false)) or bool(dish_ev.get("mystery", false)) or bool(dish_ev.get("none", false)): return ""
	return "New recipe! %s kept" % P0Logic.item_name(view, str(dish_ev.get("dish", "")))

## The events of a reply that a pot Queue ×2 kept on its own brought (server settleStove: finishPot, then startQueued),
## each `dish` with `auto` and around it: the Keep way before it (dish into the bag, the Warming Cabinet, plates left on
## the stove); after it the ingredients a Mishap gives back and its `mishap`, the first-time Energy rewards, the
## first-cook bonus, the pot's Cooking XP, Cooking level-ups and the waiting pot firing. Away from the kitchen none of
## them floats or toasts (不知火舞 on 226); the XP still counts and a level-up still shows. A level-up's gifts that did
## not fit the bag are the level-up's, not the pot's (LOCK-14 `… sent to Inbox · 24h`, the bell +1), so they are left
## out.
static func auto_kept_events(events: Array) -> Array:
	var out: Array = []
	for d in events.size():
		var dish: Dictionary = events[d]
		if str(dish.get("kind", "")) != "dish" or not bool(dish.get("auto", false)): continue
		var i := d - 1
		while i >= 0 and _kept_way(events[i]): i -= 1
		var j := d + 1
		if bool(dish.get("mystery", false)):
			var m := j
			while m < events.size() and str(events[m].get("kind", "")) in ["item", "parcel"]: m += 1
			if m < events.size() and str(events[m].get("kind", "")) == "mishap": j = m + 1
		var gifts := false   # a level-up's gifts that did not fit the bag follow it as parcels
		while j < events.size():
			var e: Dictionary = events[j]
			var k := str(e.get("kind", ""))
			var ours := (k == "energy" and str(e.get("reason", "")) == "reward") \
				or (k == "reward" and (str(e.get("id", "")).begins_with("first_dish_") or str(e.get("id", "")).begins_with("cookbook_"))) \
				or (k == "first" and str(e.get("what", "")).begins_with("cook:")) \
				or (k in ["xp", "level"] and str(e.get("skill", "")) == "cooking") or (k == "parcel" and gifts)
			if not ours: break
			gifts = k == "level" or (k == "parcel" and gifts)
			j += 1
		if j < events.size() and str(events[j].get("kind", "")) == "queue": j += 1
		var level := false
		for e in events.slice(i + 1, j):
			var k := str(e.get("kind", ""))
			if not (k == "parcel" and level): out.append(e)
			level = k == "level" or (k == "parcel" and level)
	return out

## What the Keep way of a pot pushes before its dish: a dish into the bag, into the Warming Cabinet (or past a full one,
## to_bag), plates left. A dish taken out (eaten, sold) is the command's, not the pot's (后裔 on #108).
static func _kept_way(e: Dictionary) -> bool:
	match str(e.get("kind", "")):
		"plate": return true
		"cabinet": return int(e.get("delta", 0)) > 0 or (int(e.get("delta", 0)) == 0 and int(e.get("to_bag", 0)) > 0)
		"item": return str(e.get("id", "")).begins_with("dish_") and int(e.get("delta", 0)) > 0
	return false

## "Lv4 · 60 XP to go" for the locked 3rd slot; "Lv4" when the cooking thresholds are unknown. The slot itself shows
## only its lock: a tap on it says `Cooking Lv4 · 60 XP to go` in a toast (locked_slot_toast, SGODOT-256 ⑤ A').
static func locked_slot_label(view: Dictionary) -> String:
	var third = cooking(view).get("third_slot", null)   # S5: {level, xp_to_go} from the server
	if third is Dictionary: return "Lv%d · %d XP to go" % [int(third.get("level", LOCKED_SLOT_LEVEL)), int(third.get("xp_to_go", 0))]
	var thresholds: Array = P0Logic.content().get("skills", {}).get("cooking", [])
	var xp := int(view.get("skills", {}).get("cooking", {}).get("xp", 0))
	if thresholds.size() < LOCKED_SLOT_LEVEL: return "Lv%d" % LOCKED_SLOT_LEVEL
	return "Lv%d · %d XP to go" % [LOCKED_SLOT_LEVEL, maxi(0, int(thresholds[LOCKED_SLOT_LEVEL - 1]) - xp)]

static func locked_slot_toast(view: Dictionary) -> String: return "Cooking " + locked_slot_label(view)

# ---------------------------------------------------------------- Cookbook
static func pages(view: Dictionary) -> Array: return cooking(view).get("cookbook", [])

static func cookbook_count(view: Dictionary) -> String:
	var n := cookbook_progress(view)
	return "%d/%d" % [n.x, n.y]

## Discovered pages (cooked at least once) and the pages the Cookbook shows (48 in P0): the Cookbook tab's count and the
## profile's Pages tile read this one (李白 q(100): Pages counted known pages too, 4/48 against the tab's 1/48).
static func cookbook_progress(view: Dictionary) -> Vector2i:
	if cooking(view).has("pages_total"): return Vector2i(int(cooking(view).get("discovered", 0)), int(cooking(view).pages_total))   # S5
	var all := pages(view)
	return Vector2i(all.filter(func(p): return p.get("known", false)).size(), all.size())

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

## One Cookbook page as a kitchen cell (Compact/Kitchen/Cell states). No can-cook check (SGODOT-256 ⑨, q(92)): the
## Can cook chip, the order and the Cook / Need button say it; a known page not cooked yet is half colour with Try it.
static func page_cell(view: Dictionary, p: Dictionary) -> Dictionary:
	var K := UiItemCell.KitchenState
	var cell := {id = str(p.id), rarity = int(p.get("rarity", 1)), kitchen_state = K.DEFAULT, status = ""}
	if p.has("state"): return _page_cell_s5(view, p, cell)
	if not p.get("known", false):
		cell.kitchen_state = K.LOCKED if int(p.get("slots", 1)) > slots(view) else K.HIDDEN
		if cell.kitchen_state == K.LOCKED: cell.status = "Lv%d" % LOCKED_SLOT_LEVEL
		return cell
	cell.icon = P0Logic.icon(str(p.id))
	if not p.get("cooked", false): cell.kitchen_state = K.TASTED
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
			cell.families = p.get("families", [])
			cell.clues = page_clues(p)
			cell.might_have = bool(p.get("maybe", false))   # §7.5.1 "You might have what it takes" (int6 C41)
			return cell
		"tasted": cell.kitchen_state = K.TASTED
		"mastered": cell.kitchen_state = K.MASTERED
	cell.icon = P0Logic.icon(str(p.id))
	return cell

const MAYBE_LINE := "You might have what it takes"

## Per slot of an unknown page, the clue that lit it (int6 C29): a named ingredient shows its own icon, a family clue
## ("W1", Any Common fish) its family icon, an unlit slot ("?") null. A lit slot stays lit under the Lv4 lock.
static func page_clues(p: Dictionary) -> Array:
	var out: Array = []
	for token in p.get("in", []):
		var t := str(token)
		if t == "?": out.append(null)
		elif t.length() == 2 and t[1].is_valid_int(): out.append(UiItemCell.family_icon(t[0]))
		else: out.append(P0Logic.icon(t))
	return out

## How long a pot of `rarity` cooks, as the stove runs it: the tier's time, × Quick Fire from Cooking Lv6 (5 / 15 / 30 /
## 60 s, then 4 / 12 / 24 / 48 s). The pot card's result line, the detail card and Cook Again all say this one.
static func cook_time(view: Dictionary, rarity: int) -> String:
	var ms := int(cooking(view).get("tiers", {}).get(str(rarity), {}).get("ms", 5000))
	if cooking(view).get("conveniences", []).has("quick_fire"):
		ms = int(ms * float(P0Logic.content().get("cooking", {}).get("quick_fire", 0.8)))
	return "%d s" % (ms / 1000)

## The detail card and its button (Compact/Kitchen/Recipe): {title, state, effect, effect_parts, icon, button, reason,
## nav, maybe}. `effect_parts`: a known page's `+40 Energy`, `15 s`, `Soup` (256 follow-up, 不知火舞: the card drops the
## dish style first, then the time, when the line does not fit; the energy always stays); an unknown page's energy only.
## button "Cook" when it can cook; otherwise `reason` says the first gap (LOCK-10: the gap on the button);
## unknown pages only guide to Experiment (`nav`, never puts anything in the pot); `maybe` is their might-have line.
const BUFF_LATER := "Buff · coming later"

static func page_card(view: Dictionary, p: Dictionary) -> Dictionary:
	var rarity := int(p.get("rarity", 1))
	var tier: Dictionary = cooking(view).get("tiers", {}).get(str(rarity), {})
	var energy := "+%d Energy" % int(tier.get("energy", 0))
	# buff: a Legendary page's Buff slot, empty until P3 (§7.14.4: "Buff · coming later"); "" otherwise. Where the
	# line sits on the locked page card is 不知火舞's call (LOCK-20 v5), so the drawer does not draw it yet.
	var card := {icon = null, effect = energy, effect_parts = [energy], button = "", reason = "", nav = "", maybe = "",
		buff = BUFF_LATER if rarity == 4 else ""}
	var locked: bool = p.get("lock", null) is Dictionary or (not p.has("state") and int(p.get("slots", 1)) > slots(view))
	if not p.get("known", false):
		card.title = "Unknown dish"
		var n := int(p.get("slots", 1))
		card.state = "%s · %d %s" % [P0Logic.rarity_name(view, rarity), n, "ingredient" if n == 1 else "ingredients"]
		if locked: card.reason = "Cooking Lv%d · 3rd slot" % LOCKED_SLOT_LEVEL
		else: card.nav = "Try in Experiment"
		if bool(p.get("maybe", false)): card.maybe = MAYBE_LINE   # its own line under the facts (§7.5.1, int6 C41)
		return card
	card.title = str(p.get("name", ""))
	card.icon = P0Logic.icon(str(p.id))
	card.effect_parts = [energy, cook_time(view, rarity)]
	if str(p.get("style", "")) != "": card.effect_parts.append(str(p.style))
	card.effect = " · ".join(PackedStringArray(card.effect_parts))
	var made := int(p.get("cooked_total", 0))
	card.state = "%s · %s" % [P0Logic.rarity_name(view, rarity), ("Cooked ×%d" % made if made > 1 else "Cooked") if p.get("cooked", false) else first_cook_line(rarity)]
	if p.get("can_cook", false): card.button = "Cook"
	elif locked: card.reason = "Cooking Lv%d · 3rd slot" % LOCKED_SLOT_LEVEL
	else: card.reason = missing_reason(view, p)
	return card

## A known page not cooked yet (SGODOT-256 ⑨, q(92)): `First cook +20 XP` after its rarity, the one-off first-cook XP of
## its tier (10 / 20 / 40 / 80), as the pot's `First cooked · +20 Cooking XP` gives it. The word Tasted is not shown.
static func first_cook_line(rarity: int) -> String:
	var tier: Dictionary = P0Logic.content().get("cooking", {}).get("tiers", {}).get(str(rarity), {})
	return "First cook +%d XP" % int(tier.get("first_xp", 0))

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
		if found == "": return "Need %s ×1" % need_label(view, t)
		used[found] = int(used.get(found, 0)) + 1
	return "Missing ingredients"

## A known page short of one ingredient only, a crop still in the ground (plan §14.2 end, §14.5; 李白 A3 / q(95)):
## {page, name, crop, ms, fish} for the Today line `Fresh Fish Soup · when radishes are ready`, or {} when none. The bag
## and the Spice Rack cover the rest; the one short kind is a crop sown or growing on the plots (a family slot takes the
## soonest such crop) — two kinds short, no line. A ripe crop is a Harvest line instead, so the page drops out then.
## Of several, the one whose crop is ripe first. `fish` is how many of the bag's fish it keeps for itself (the stove-free
## line counts the rest).
static func waiting_on_crops(view_: Dictionary) -> Dictionary:
	var view := with_rack(view_)
	var pool := {}
	for s in view.get("bag", {}).get("slots", []): pool[str(s.get("id", ""))] = int(pool.get(str(s.get("id", "")), 0)) + int(s.get("qty", 0))
	for r in rack_rows(view_): pool[str(r.id)] = int(pool.get(str(r.id), 0)) + int(r.quantity)
	var growing: Array = []   # [ms, crop]; a sown plot not watered yet counts, last
	for p in view.get("plots", []):
		var st := str(p.get("state", ""))
		if st == "growing": growing.append([float(p.get("ready_in", 0)), str(p.crop)])
		elif st == "sown": growing.append([INF, str(p.crop)])
		elif st == "ready": pool[str(p.crop)] = int(pool.get(str(p.crop), 0)) + 1   # ripe: a Harvest away, not waited on
	if growing.is_empty(): return {}
	growing.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var best := {}
	for p in pages(view):
		var known := bool(p.get("known", false)) or str(p.get("state", "")) in ["tasted", "discovered", "mastered"]
		if not known or bool(p.get("can_cook", false)): continue
		var left := pool.duplicate()
		var short: Array = []   # the tokens the bag cannot cover
		var fish := 0
		for token in p.get("in", []):
			var t := str(token)
			var found := ""
			for id in left:
				if int(left[id]) > 0 and P0Logic._token_matches(view, t, str(id)):
					found = str(id)
					break
			if found == "":
				short.append(t)
				continue
			left[found] = int(left[found]) - 1
			if found.begins_with("fish_"): fish += 1
		if short.is_empty(): continue
		var crop := ""
		var ms := 0.0
		for t in short:   # one kind short: every uncovered slot is the same growing crop
			var grow: Array = []
			for g in growing:
				if P0Logic._token_matches(view, t, str(g[1])):
					grow = g
					break
			if grow.is_empty() or (crop != "" and str(grow[1]) != crop):
				crop = ""
				break
			crop = str(grow[1])
			ms = float(grow[0])
		if crop == "": continue
		if best.is_empty() or ms < float(best.ms):
			best = {page = str(p.id), name = str(p.get("name", P0Logic.item_name(view, str(p.id)))), crop = crop, ms = ms, fish = fish}
	return best

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
static func experiment_items(view_: Dictionary, pot: Array, chip := "All") -> Array:
	var view := with_rack(view_)
	var K := UiItemCell.KitchenState
	var out: Array = []
	var totals := {}   # one cell per ingredient, however many stacks it fills
	var order: Array = []
	for s in view.get("bag", {}).get("slots", []):
		var sid := str(s.get("id", ""))
		if not totals.has(sid): order.append(sid)
		totals[sid] = int(totals.get(sid, 0)) + int(s.get("qty", 0))
	# The Spice Rack's stored seasonings are on hand too (q(46): real count, a Rack tag; the stove takes them first).
	var racked := {}
	for r in rack_rows(view):
		if not totals.has(r.id): order.append(r.id)
		totals[r.id] = int(totals.get(r.id, 0)) + int(r.quantity)
		racked[r.id] = true
	for raw in order:
		var id := str(raw)
		var info := P0Logic.item(view, id)
		if racked.has(id) and info.is_empty(): info = {cook = true, family = "S", rarity = 1}   # stored only: a Common seasoning
		var cookable := bool(info.get("cook", false))
		var ornamental := not cookable and id.begins_with("fish_")
		if not cookable and not ornamental: continue
		var family := str(info.get("family", "W" if id.begins_with("fish_") else ""))
		if chip != "All" and family != str(FAMILY_OF_CHIP.get(chip, "")): continue
		var in_pot := pot.count(id)
		out.append({id = id, icon = P0Logic.icon(id), qty = int(totals[id]) - in_pot, rarity = int(info.get("rarity", 1)),
			kitchen_state = K.NOT_FOR_COOKING if ornamental else (K.IN_POT if in_pot > 0 else K.DEFAULT),
			cookable = cookable, rack = racked.has(id)})
	return out

## Whether one more `id` can go in the pot: a free slot and one left in the bag.
static func can_add(view_: Dictionary, pot: Array, id: String) -> bool:
	var view := with_rack(view_)
	if pot.size() >= slots(view): return false
	var on_rack := int(stock(view).get(id, 0)) - P0Logic.bag_count(view, id)
	if not P0Logic.item(view, id).get("cook", on_rack > 0): return false
	return int(stock(view).get(id, 0)) - pot.count(id) > 0

static func slots_used_line(view: Dictionary, pot: Array) -> String:
	return "%d / %d slots used" % [pot.size(), slots(view)]

## The pot card's result line (PotResultLine, SGODOT-256 ⑤ A'): {title, rarity, time}. An empty pot has none (title
## ""; the card shrinks to its slots); seasonings alone read `?` with no dot or time (the button says Needs a main
## ingredient); otherwise the dish, `Unknown dish` or `Tried before`, its rarity (a dot, no word) and the cooking time.
static func preview(view_: Dictionary, pot: Array) -> Dictionary:
	var view := with_rack(view_)
	if pot.is_empty(): return {title = "", rarity = 0, time = ""}
	if not has_main(view, pot): return {title = "?", rarity = 0, time = ""}
	var fams := {}
	var top := 1
	for id in pot:
		var info := P0Logic.item(view, str(id))
		fams[str(info.get("family", "W"))] = true
		top = maxi(top, int(info.get("rarity", 1)))
	var known := P0Logic.match_known(view, pot)
	var rarity: int
	if not known.is_empty(): rarity = int(known.rarity)
	else:
		var derive: Array = cooking(view).get("derive", [[1, 2, 3], [2, 3, 3], [3, 3, 4], [4, 4, 4]])
		rarity = int(derive[clampi(top - 1, 0, derive.size() - 1)][clampi(fams.size(), 1, 3) - 1])
	var title := str(known.name) if not known.is_empty() else ("Tried before" if tried(view, pot) else "Unknown dish")
	return {title = title, rarity = rarity, time = cook_time(view, rarity)}

## At least one main ingredient (field, orchard or water) besides the seasonings (§7.2.7).
static func has_main(view_: Dictionary, pot: Array) -> bool:
	var view := with_rack(view_)
	for id in pot:
		if str(P0Logic.item(view, str(id)).get("family", "")) != "S": return true
	return false

## This exact mix already failed (S5 Kitchen Mishaps, §7.2.7): the capsule's title reads Tried before and a line above
## the Cook row says "Tried before · not a recipe" (q(56): while the blessing still refunds, a failed pot gives no
## Mystery Dish, so the line never names the result; An Qi La, 226 e8e5617a); the pot may still cook it.
static func tried(view: Dictionary, pot: Array) -> bool:
	if pot.is_empty(): return false
	var mine := pot.map(func(i): return str(i))
	mine.sort()
	for m in cooking(view).get("mishaps", []):
		var theirs: Array = (m.get("items", []) as Array).map(func(i): return str(i))
		theirs.sort()
		if theirs == mine: return true
	return false

## Experiment's cook row (COOK-P0-2 / 2b): "+20 Energy" when the pot is a known page, "" for an unknown mix.
static func pot_energy(view_: Dictionary, pot: Array) -> String:
	var view := with_rack(view_)
	if pot.is_empty(): return ""
	var known := P0Logic.match_known(view, pot)
	if known.is_empty(): return ""
	var t: Dictionary = cooking(view).get("tiers", {}).get(str(int(known.rarity)), {})
	return "+%d Energy" % int(t.get("energy", 0))

## The result line for a Cookbook page: its name (`Unknown dish` before it is known), rarity and time. Whether it can
## cook is the Cook / Queue button's (`Ready to cook` / `Ready to queue` retired, SGODOT-256 ⑤ A', q(92)).
static func page_preview(view: Dictionary, p: Dictionary) -> Dictionary:
	var rarity := int(p.get("rarity", 1))
	var title := str(p.get("name", "")) if p.get("known", false) else "Unknown dish"
	return {title = title, rarity = rarity, time = cook_time(view, rarity)}

## Experiment's Cook button: the gap when it cannot cook (LOCK-10), else "Cook" (never "Free", §7.2.7). In the drawer
## opened from Queue next › the pot on the stove is the point: the button reads Queue, never Stove busy (q(71)).
static func experiment_reason(view: Dictionary, pot: Array, queue := false, i := 0) -> String:
	if pot.is_empty(): return "Add an ingredient"
	if not has_main(view, pot): return "Needs a main ingredient"
	if stove(view, i) != null and not queue: return "Stove busy"
	return ""

# ---------------------------------------------------------------- the dish comes out (COOK-4 / 6 / P0-9, COOK-7-2)
## Portions waiting on the stove after a collect with no room (§7.2.6, PR #20): [] when none.
static func stove_left(view: Dictionary, i := 0) -> Array:
	var st = stove(view, i)
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

## The Keep toast for a dish that gets no result card: a pot kept on its own (S5 Queue ×2), or a collect answered after
## the player left the farmhouse. Away from the stove nothing pops up (§7.2.7 step 7, q(46); 不知火舞 on 251): Today
## and the stove's sign say a dish is ready, this line says where a kept one went. {} for a pot that made no dish.
static func kept_line(view: Dictionary, ev: Dictionary, events: Array) -> Dictionary:
	if bool(ev.get("none", false)): return {}
	var base := str(ev.get("dish", ""))
	var q := int(ev.get("quality", 0))
	var id := base if q == 0 else "%s@%s" % [base, ["plain", "good", "perfect"][q]]
	return keep_line(view, id, str(routes(events).get(id, "bag")))

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
			# "Ingredients back" / "9 refunds left today" on two lines: the name line ellipsizes, and the count is the point
			# (int6 C14). The count names what it counts (Joey on 296: `8 left today` read as nothing, trying a new dish).
			item_name = "Ingredients back", rarity = 0, rarity_word = P0Logic.refunds_left(int(ev.get("trial_left", 0))), quality = 0,
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

## The view with the Spice Rack's stored seasonings in `items` (view.items lists bag ids only): Common, family S,
## cookable, so the Experiment grid, the pot preview and recipe matching see what the stove can reach (q(46)).
static func with_rack(view: Dictionary) -> Dictionary:
	var rows := rack_rows(view)
	if rows.is_empty(): return view
	var items: Dictionary = view.get("items", {}).duplicate()
	for r in rows:
		if not items.has(r.id): items[r.id] = {name = r.title, kind = "material", family = "S", rarity = 1, cook = true}
	var out := view.duplicate()
	out["items"] = items
	return out

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

## The cabinet's icon button count tag (C21, q(31)): 4/6 or Full, "" when it holds nothing (or there is no cabinet).
static func cabinet_count(view: Dictionary) -> String:
	var cab = cooking(view).get("cabinet", null)
	return cabinet_badge(view) if cab is Dictionary and int(cab.get("have", 0)) > 0 else ""

## The selected cabinet row's buttons: Eat (COOK-7-2 states) and Take one (unavailable "Bag full", LOCK-10).
static func cabinet_actions(view: Dictionary, id: String) -> Dictionary:
	var bag: Dictionary = view.get("bag", {})
	var limit := int(P0Logic.content().get("bag", {}).get("stack", {}).get("dish", 5))
	var room: bool = int(bag.get("free", 0)) > 0 or bag.get("slots", []).any(func(b): return str(b.id) == id and not b.get("gifted", false) and int(b.qty) < limit)
	return {eat = eat_state(view, id), take = "Take one", take_reason = "" if room else "Bag full"}

# ---------------------------------------------------------------- Cook Again (COOK-P0-7 / P0-8, Cooking Lv2)
const TAG_NAMES := {"W": "Fish", "F": "Vegetable", "O": "Fruit", "S": "Seasoning"}
const ORDINALS := ["1st", "2nd", "3rd"]

## 1st, 2nd, 3rd, 4th … (Cooks today, and the XP float's `· 2nd today` / `No XP · 3rd today`).
static func ordinal(n: int) -> String: return ORDINALS[n - 1] if n >= 1 and n <= 3 else "%dth" % n

## Cooking Lv2's Cook Again is unlocked (S5 conveniences).
static func cook_again_on(view: Dictionary) -> bool:
	return cooking(view).get("conveniences", []).has("cook_again")

## What the stove can draw from: plain bag stacks plus the Spice Rack's stored seasonings (q(46)).
static func stock(view: Dictionary) -> Dictionary:
	var out := {}
	for s in view.get("bag", {}).get("slots", []):
		if s.get("gifted", false): continue
		out[str(s.id)] = int(out.get(str(s.id), 0)) + int(s.qty)
	for r in rack_rows(view): out[r.id] = int(out.get(r.id, 0)) + int(r.quantity)
	return out

## A stocked item's name: the rack row's (stored seasonings are not in view.items) or the bag item's.
static func _stock_name(view: Dictionary, id: String) -> String:
	for r in rack_rows(view):
		if r.id == id: return str(r.title)
	return P0Logic.item_name(view, id)

static func _matches(view: Dictionary, token: String, id: String) -> bool:
	if token.length() == 2 and token[0] == "S" and rack_rows(view).any(func(r): return r.id == id): return true   # rack seasonings are Common
	return P0Logic._token_matches(view, token, id)

## COOK-P0-7 (can) / P0-8 (short) for one known page: header, facts, slots, NEED-TILEs and the button. A tag
## slot shows its one matching item when only one is in stock ("Wild Herb"), else the family ("Fish").
static func cook_again(view: Dictionary, page_id: String) -> Dictionary:
	var p := _page(view, page_id)
	if p.is_empty(): return {}
	var have := stock(view)
	var needs := {}   # key → {name, icon, have, need}
	var order: Array = []
	for token in p.get("in", []):
		var t := str(token)
		var key := t
		var name := P0Logic.item_name(view, t)
		var icon := P0Logic.icon(t)
		var count := int(have.get(t, 0))
		var gap := name   # the button names what the page asks for: a family for a tag, the item otherwise
		if t.length() == 2 and "WFOS".contains(t[0]) and t[1].is_valid_int():
			var ids := have.keys().filter(func(id): return int(have[id]) > 0 and _matches(view, t, str(id)))
			count = ids.reduce(func(n, id): return n + int(have[id]), 0)
			name = _stock_name(view, str(ids[0])) if ids.size() == 1 else str(TAG_NAMES[t[0]])
			gap = str(TAG_NAMES[t[0]])
			icon = P0Logic.icon(str(ids[0])) if ids.size() == 1 else P0Logic.icon("fish_crucian" if t[0] == "W" else ("rock_salt" if t[0] == "S" else "crop_radish"))
		if not needs.has(key):
			needs[key] = {name = name, gap = gap, icon = icon, have = count, need = 0}
			order.append(key)
		needs[key].need = int(needs[key].need) + 1
	var tiles: Array = order.map(func(k): return needs[k])
	var short: Array = tiles.filter(func(n): return int(n.have) < int(n.need))
	var met := 0
	for n in tiles: met += mini(int(n.have), int(n.need))
	var today := int(p.get("today", 0))
	var facts: Array = []
	var rarity := int(p.get("rarity", 1))
	if short.is_empty(): facts.append(["Cooking", cook_time(view, rarity)])
	facts.append(["Cooks today", ordinal(today + 1)])
	facts.append(["Cooking XP", "Full" if today == 0 else ("Half" if today == 1 else "None")])
	var first: Dictionary = short[0] if not short.is_empty() else {}
	return {title = str(p.get("name", "")), state = "Can cook again" if short.is_empty() else "Materials short",
		effect = "Repeat this recipe with the shown ingredients." if short.is_empty() else "Add %s to cook this recipe again." % str(first.get("name", "")).to_lower(),
		facts = facts, section = "Ingredients · %d/%d" % [met, p.get("in", []).size()],
		slots = p.get("in", []).size(), locked = slots(view) < 3, lock_note = locked_slot_toast(view),
		tiles = tiles, button = "Cook Again",
		reason = "" if short.is_empty() else "Need %d more %s" % [int(first.need) - int(first.have), str(first.gap)],
		command = {"type": "cook", "recipe": page_id}}

# ---------------------------------------------------------------- Cook All (Cooking Lv8, COOK-P1-4 / COOK-EMPTY)
const COOK_ALL_RULE := "Rare → Fine → Common · up to 2 of a dish · no Legendary"
const COOK_ALL_GAP := "Nothing to cook"

## Cook All as the Cookbook strip and its sheet read it, from the server's preview (view.cooking.cook_all: the pots
## cook_all would start, worked out by running it on a copy, so the sheet and the cook never disagree). {} before
## Cooking Lv8. button: "" when it can go, else the gap greyed on the strip (`Nothing to cook`, D-10 / LOCK-10: no
## empty sheet); empty: every stove and queue is taken (COOK-EMPTY: `No space`); rows: [{dish, icon, name, rarity,
## rarity_word, where}] in firing order (`Stove 1 · now` / `Stove 1 · next`); uses: [{token, name, icon, have, need}]
## (the planned pages' slots summed, a tag without its `Any`); body, label; stoves / facts for COOK-EMPTY.
static func cook_all(view: Dictionary) -> Dictionary:
	var plan = cooking(view).get("cook_all", null)
	if not plan is Dictionary: return {}
	var reason := str(plan.get("reason", "")) if plan.get("reason", null) != null else ""
	var out := {"button": COOK_ALL_GAP if reason == "nothing_to_cook" else "", "empty": reason == "no_space",
		"rows": [], "uses": [], "rule": COOK_ALL_RULE, "stoves": [], "facts": []}
	for p in plan.get("pots", []):
		var dish := str(p.get("dish", ""))
		var r := int(p.get("rarity", 1))
		out.rows.append({"dish": dish, "icon": P0Logic.icon(dish), "name": P0Logic.item_name(view, dish), "rarity": r,
			"rarity_word": P0Logic.rarity_name(view, r),
			"where": "Stove %d · %s" % [int(p.get("stove", 0)) + 1, "next" if str(p.get("when", "")) == "next" else "now"]})
	for u in plan.get("uses", []):
		var token := str(u.get("token", ""))
		var family = UiItemCell.family_icon(token.left(1)) if token.length() == 1 or (token.length() == 2 and token[1].is_valid_int()) else null
		var name := need_label(view, token)
		out.uses.append({"token": token, "name": name.left(1).to_upper() + name.substr(1),
			"icon": family if family != null else P0Logic.icon(token),
			"have": int(u.get("have", 0)), "need": int(u.get("need", 0))})
	var n: int = out.rows.size()
	var on := int(plan.get("stoves", 0))
	out.body = "%d pot%s on %d stove%s · ingredients come out of your Bag now" % [n, "" if n == 1 else "s", on, "" if on == 1 else "s"]
	out.label = "Cook All · %d pot%s" % [n, "" if n == 1 else "s"]
	# COOK-EMPTY: each stove Busy (Queue full when one waits behind it), Stoves n/n · Queues q/n
	var count := stove_count(view)
	var queues := 0
	for i in count:
		var q = queued(view, i) != null
		if q: queues += 1
		out.stoves.append({"title": "Stove %d" % (i + 1), "state": "Busy" if stove(view, i) != null else "Free",
			"detail": "Queue full" if q else ""})
	out.facts = [["Stoves", "%d/%d" % [count - out.stoves.filter(func(s): return s.state == "Free").size(), count]],
		["Queues", "%d/%d" % [queues, count]]]
	return out

# ---------------------------------------------------------------- Cookbook titles (§7.6.1; 不知火舞 on 282)
## Home Cook comes with the P0 reward `cookbook_8` (its +50 Energy); Line Cook 20 / Head Chef 36 / Master Chef 48 count
## Discovered pages and Muscle Memory counts Mastered ones (the server's `milestone` events, view.cooking.milestones).
const HOME_COOK := "Home Cook"
const NEW_TITLE := "New title"

## A title's card (RewardMoment Milestone, no buttons; after the dish card): the title, how far the Cookbook is, and
## `New title` with what came with it — `Cookbook 8/48` · `New title · +50 Energy`, `Cookbook 20/48` · `New title ·
## +100 coins · Recipe Stand`, `Cookbook 36/48` · `New title · Warming Cabinet +4`, `Cookbook 48/48` · `New title ·
## Gold frame`, `Mastered 10` · `New title`. No next tier here: the Cookbook's title strip says it. `ev` is the
## `reward` (id cookbook_N) or the `milestone` event; {} for anything else (a Fish-dex milestone).
static func title_card(view: Dictionary, ev: Dictionary) -> Dictionary:
	var id := str(ev.get("id", ""))
	var total := int(cooking(view).get("pages_total", 48))
	var gifts: Array = []
	if str(ev.get("kind", "")) == "reward":
		if not id.begins_with("cookbook_"): return {}
		if int(ev.get("energy", 0)) > 0: gifts.append("+%d Energy" % int(ev.energy))
		return {event = HOME_COOK, item_name = "Cookbook %d/%d" % [int(id.trim_prefix("cookbook_")), total], strip = _title_strip(gifts)}
	if str(ev.get("kind", "")) != "milestone" or id.begins_with("fishdex_"): return {}
	var m := _milestone(view, id)
	var mastered := str(m.get("counts", "")) == "mastered"
	if int(ev.get("coins", 0)) > 0: gifts.append("+%d coins" % int(ev.coins))
	if ev.get("decor", null) != null: gifts.append(P0Decor.name_of(str(ev.decor)))
	if int(ev.get("cabinet", 0)) > 0: gifts.append("Warming Cabinet +%d" % int(ev.cabinet))
	if id == "master_chef": gifts.append("Gold frame")
	var need := int(m.get("need", 0))
	return {event = str(ev.get("title", m.get("title", ""))),
		item_name = ("Mastered %d" % need) if mastered else "Cookbook %d/%d" % [need, total], strip = _title_strip(gifts)}

static func _title_strip(gifts: Array) -> String:
	return " · ".join(PackedStringArray([NEW_TITLE] + gifts))

static func _milestone(view: Dictionary, id: String) -> Dictionary:
	for m in cooking(view).get("milestones", []):
		if str(m.get("id", "")) == id: return m
	return {}

## The Cookbook's title strip (COOK-5: a line under the filter chips): Home Cook, then the Discovered milestones in
## order, each {title, state, have, need}: reached (ink), the next one with its count (`Line Cook 12/20`), the rest later
## (grey, the name only). Muscle Memory counts Mastered pages, its own axis: muscle_item.
static func title_strip(view: Dictionary) -> Array:
	var have := int(cooking(view).get("discovered", 0))
	var home := int((P0Logic.content().get("rewards", {}).get("cookbook", [[8, 50]]) as Array)[0][0])
	var out: Array = [{title = HOME_COOK, need = home, reached = have >= home}]
	for m in cooking(view).get("milestones", []):
		if str(m.get("counts", "")) == "discovered": out.append({title = str(m.title), need = int(m.need), reached = bool(m.reached)})
	var next_found := false
	for t in out:
		t.have = have
		if t.reached: t.state = "reached"
		elif not next_found:
			t.state = "next"
			next_found = true
		else: t.state = "later"
	return out

## The strip's last item, after its divider (COOK-TITLES 2575:133159): Muscle Memory and the Mastered pages toward it,
## {title, have, need, reached} — `Muscle Memory 6/10` grey until reached, then the name alone in ink; {} without it.
static func muscle_item(view: Dictionary) -> Dictionary:
	for m in cooking(view).get("milestones", []):
		if str(m.get("counts", "")) == "mastered":
			return {title = str(m.title), have = int(cooking(view).get("mastered_count", 0)), need = int(m.need), reached = bool(m.get("reached", false))}
	return {}
