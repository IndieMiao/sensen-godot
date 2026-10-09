class_name P0Guide
extends RefCounted
## The first-session guide layer as pure rules over the server view (plan §14.2–14.5, §3.7.4, q(44), q(46), q(49);
## SGODOT-232 U6). The world and the panels only draw what these return: which TipCard to show and when, the rows
## that lead Today, the farmhouse door "!", the stall badge, Free to do now and the quick-bar flash. Every stage comes
## from the server's state, so a reinstall picks the guide up where the save is; only "tips already shown" is local.

const TUTORIAL := "req_pond_catch"
const BEGINNER_POND := "pond_shanghai_05"   # Reed Pond (q(32))

## The TipCards of P0 (q(44), TUT-2): one sentence, no button, each shown once. TUT-2's eighth sentence, "Levels unlock
## gear, fish and seeds…", is the Tip line of the account's first level-up banner (P0Logic.LEVEL_TIP), never a card
## (q(86); TUT-2 frame note A-03 / TUT-3-10, 不知火舞 on 235-B2).
const TIPS := {
	"sow": "Pick a seed, walk up to a plot and press Sow. Hold to keep sowing.",
	"cast": "Casting uses 5 Energy",
	"creel": "Your creel is your bag: 10 fish per free slot.",
	"cook": "Tap Cook to grill your first fish",
	"heat": "Tap when the needle hits gold!",
	"meal": "Energy comes back over time. A meal brings it back now.",
	"map": "Browse the map for free. Travel costs Energy and coins.",
}
## Doing what a tip teaches closes it (q(26)); the other tips wait out their time or a tap.
const TAUGHT_BY := {"sow": "sow", "cast": "cast", "cook": "cook", "heat": "heat"}

## Toast timing (q(26)): 2 s plus 0.5 s per 20 characters, at most 5 s.
static func tip_seconds(text: String) -> float:
	return minf(5.0, 2.0 + 0.5 * floorf(text.length() / 20.0))

## The tip a moment calls for (TUT-2 sources), or "": the first time the player is on the farm / at a pond / on the
## map / at the stove; and from server events, the first cast, the account's first fire, the first meal or the first
## time Energy runs out (the first level-up teaches in its banner instead).
static func tip_for_surface(surface: String) -> String:
	return {"farm": "sow", "pond": "creel", "map": "map", "stove": "cook"}.get(surface, "")

## before / after: the views either side of the response carrying ev ("the account's first fire" is the pot started
## while before.cooking.first_fire was still true).
static func tip_for_event(ev: Dictionary, before: Dictionary, after: Dictionary) -> String:
	match str(ev.get("kind", "")):
		"cast": return "cast"
		"pot": return "heat" if before.get("cooking", {}).get("first_fire", false) else ""
		"meal": return "meal" if int(ev.get("gain", 0)) > 0 else ""
		"energy": return "meal" if int(ev.get("delta", 0)) < 0 and int(after.get("energy", {}).get("value", 1)) <= 0 else ""
	return ""

## One TipCard at a time, in order, each key once. While a RewardMoment / MomentBanner is up a new tip waits, and the
## one already on screen stays (q(49)): the first catch shows `Caught!` first, then "Your creel is your bag…".
class TipQueue:
	extends RefCounted
	var seen := {}          # key -> true: shown before (the caller persists it)
	var showing := ""       # the tip on screen
	var waiting: Array = []
	var moments := 0        # RewardMoment / MomentBanner open now

	func _init(already_seen: Dictionary = {}) -> void:
		seen = already_seen.duplicate()

	## Ask for a tip; false when it was shown before, is on screen or already waits.
	func request(key: String) -> bool:
		if key == "" or not P0Guide.TIPS.has(key) or seen.has(key) or showing == key or waiting.has(key): return false
		waiting.append(key)
		return true

	func moment_opened() -> void: moments += 1
	func moment_closed() -> void: moments = maxi(0, moments - 1)

	## The next tip to put on screen, or "" (one is up, a Moment is up, or none waits). Marks it seen.
	func next() -> String:
		if showing != "" or moments > 0 or waiting.is_empty(): return ""
		showing = str(waiting.pop_front())
		seen[showing] = true
		return showing

	## The player did something: a tip that teaches it closes. Returns true when it closed one.
	func did(action: String) -> bool:
		if showing != "" and str(P0Guide.TAUGHT_BY.get(showing, "")) == action:
			showing = ""
			return true
		return false

	## Timed out or tapped.
	func close() -> void: showing = ""

# ---------------------------------------------------------------- first session state

## The Stall Board's tutorial request, or {} once it is handed in (the first session's one goal, §14.2).
static func tutorial(view: Dictionary) -> Dictionary:
	for r in view.get("stall", {}).get("board", {}).get("requests", []):
		if str(r.get("id", "")) == TUTORIAL: return r
	return {}

static func first_session(view: Dictionary) -> bool: return not tutorial(view).is_empty()

## The first session in the guide's sense: until Pond Catch is handed in and the first dish is cooked (q(58)).
static func first_phase(view: Dictionary) -> bool:
	if first_session(view): return true
	return (view.get("req_done", []) as Array).has(TUTORIAL) and not page(view, "dish_grilled_crucian").get("cooked", false) \
		and not page(view, "dish_grilled_crucian").is_empty()

static func page(view: Dictionary, id: String) -> Dictionary:
	for p in view.get("cooking", {}).get("cookbook", []):
		if str(p.get("id", "")) == id: return p
	return {}

# ---------------------------------------------------------------- Today rows

## Rows that lead Today (§14.2, §14.3, q(46)); P0Logic.today_rows puts them first and fills up to 3 from its own.
## A row is {line, icon, go, state, tail, focus} like P0Logic._row; go "pond:<id>" (and "outpost:<role>", "map") is a
## place on the map: Show on map there (the map's targets, SGODOT-225 #37).
static func lead_rows(view: Dictionary) -> Array:
	var rows: Array = []
	var t := tutorial(view)
	var grill := page(view, "dish_grilled_crucian")
	var first := first_phase(view)   # the first session lasts to the first dish
	# Row 1 follows the request's state, never events (q(58)): Catch while short (eaten fish send it back), Deliver
	# once the creel holds them (not ticked), ticked only when handed in. Show: Catch → Reed Pond's pin; Deliver → the
	# stall in the farm, the home pin elsewhere (go "stall").
	if not t.is_empty():
		var qty := int(t.get("qty", 2))
		var fish := P0Logic.item_name(view, str(t.item))   # fish names take no plural s
		if int(t.get("have", 0)) >= qty: rows.append(_row("Deliver %d %s · Stall" % [qty, fish], str(t.item), "stall"))
		else: rows.append(_row("Catch %d %s · %s" % [qty, fish, _place_name(view, BEGINNER_POND)], str(t.item),
			"pond:" + BEGINNER_POND))   # the pond is elsewhere: Show on map (q(31)); the stall's "!" asks to take it
	elif first:
		var done := _row("Deliver 2 %s · Stall" % P0Logic.item_name(view, "fish_crucian"), "fish_crucian", "stall")
		done.state = "done"
		rows.append(done)
	# Cook it: Grilled Crucian — through the first session (ticked once cooked), and after it until the first dish is made
	if not grill.is_empty() and (first or not grill.get("cooked", false)):
		var cook := _row("Cook it: %s" % str(grill.get("name", "Grilled Crucian")), "dish_grilled_crucian", "stove")
		if grill.get("cooked", false): cook.state = "done"
		rows.append(cook)
	if first: return focus_first(rows)   # the third row is the radishes' timer (P0Logic), not another goal
	var third := third_slot_row(view)
	if not third.is_empty(): rows.append(third)
	var fresh := new_recipe_row(view)
	if not fresh.is_empty(): rows.append(fresh)
	var sow := sow_row(view)
	if not sow.is_empty(): rows.append(sow)
	return focus_first(rows)

## Today highlights only the first row still to do (q(58)): "focus" true on it, false on the rest. Call it again on
## the full list once P0Logic has filled Today up to 3.
static func focus_first(rows: Array) -> Array:
	var found := false
	for r in rows:
		r.focus = not found and str(r.get("state", "")) != "done"
		if r.focus: found = true
	return rows

## `Cook: Herb Grilled Fish · new recipe` (§14.2 minute 22): a known page never cooked that the stove can make now.
static func new_recipe_row(view: Dictionary) -> Dictionary:
	for p in view.get("cooking", {}).get("cookbook", []):
		if p.get("known", false) and not p.get("cooked", false) and p.get("can_cook", false) and str(p.id) != "dish_grilled_crucian":
			return _row("Cook: %s · new recipe" % str(p.get("name", "")), str(p.id), "stove")
	return {}

## `3rd slot open · try Fine fish + Potato + Rock Salt` (q(46)): from Cooking Lv4 until the first 3-slot dish.
static func third_slot_row(view: Dictionary) -> Dictionary:
	if int(view.get("cooking", {}).get("slots", 2)) < 3: return {}
	for p in view.get("cooking", {}).get("cookbook", []):
		if int(p.get("slots", 0)) >= 3 and p.get("cooked", false): return {}
	return _row("3rd slot open · try Fine fish + Potato + Rock Salt", "pot", "stove")

## `Sow 10 Lettuce · 20 Energy` (§14.2 minute 16): seeds in the bag and free beds (wild ones till for free). Short of
## Energy the row stays, with `needs 20 Energy · +8 in 21m` (§14.5). Before the first sow P0Logic has its own row.
static func sow_row(view: Dictionary) -> Dictionary:
	var plots: Array = view.get("plots", [])
	if not plots.any(func(p): return str(p.get("state", "")) in ["sown", "growing", "ready"]) \
			and not (view.get("firsts", []) as Array).any(func(f): return str(f).begins_with("harvest:")):
		return {}
	var free := plots.filter(func(p): return str(p.get("state", "")) in ["tilled", "wild"]).size()
	if free == 0: return {}
	for s in view.get("bag", {}).get("slots", []):
		var seed := str(s.get("id", ""))
		if not seed.begins_with("seed_"): continue
		var crop := P0Logic.crop_for_seed(view, seed)
		if crop.is_empty(): continue
		var n := mini(int(s.get("qty", 0)), free)
		if n <= 0: continue
		var cost := n * int(crop.get("energy", 2))
		var r := _row("Sow %d %s · %d Energy" % [n, crop_count_name(view, str(crop.id), n), cost], seed, "plots")
		var e: Dictionary = view.get("energy", {})
		var gap := cost - int(e.get("value", 0))
		if gap > 0:
			r.state = "short"
			r.tail = "needs %d Energy" % cost + _gain_in(e, gap)
		return r
	return {}

## Crop plurals for counts (q(58)): Lettuce, Chamomile and Corn stay as they are; Chili → Chilies; the rest by
## P0Logic.plural (Radishes, Herbs, Carrots, Potatoes, Tomatoes, Cabbages, Cucumbers). Fish names never take an s.
static func crop_count_name(view: Dictionary, crop_id: String, n: int) -> String:
	var name := P0Logic.item_name(view, crop_id)
	return name if n == 1 else P0Logic.plural(name)   # q(58)'s exceptions live in P0Logic.PLURALS (q(98))

## ` · +8 in 21m`: the Energy still missing and when natural recovery brings it.
static func _gain_in(e: Dictionary, gap: int) -> String:
	if e.get("next_in", null) == null: return ""
	var ms := float(e.next_in) + float(gap - 1) * float(e.get("regen_ms", 240000))
	return " · +%d in %s" % [gap, _short(ms)]

## `21m`, `1h 05m`: Today's tail is one short line.
static func _short(ms: float) -> String:
	var minutes := maxi(1, ceili(ms / 60000.0))
	return "%dm" % minutes if minutes < 60 else "%dh %02dm" % [minutes / 60, minutes % 60]

## ` · Farming Lv 2 at first harvest` (§14.2 end): what the growing beds' locked XP and first-harvest bonuses reach.
static func harvest_level_tail(view: Dictionary) -> String:
	var h := harvest_level(view)
	return " · Farming Lv%d at first harvest" % int(h.level) if not h.is_empty() else ""

## Whether harvesting reaches the next Farming level (q(69), RETURN-SESSION): {level, now: true} when the plots ready
## now are enough (`Farming Lv 2 with this harvest`); {level, now: false} when it takes the growing ones too and no crop
## was ever harvested (`Farming Lv 2 at your first harvest`); {} otherwise. First-harvest bonuses count once a crop.
static func harvest_level(view: Dictionary) -> Dictionary:
	var sk: Dictionary = view.get("skills", {}).get("farming", {})
	if sk.get("next", null) == null: return {}
	var base := int(sk.get("xp", 0))
	if base >= int(sk.next): return {}
	var crops := {}
	for c in P0Logic.content().get("crops", []): crops[str(c.id)] = c
	var firsts: Array = view.get("firsts", [])
	var counted := {}
	var ready_xp := 0
	var all_xp := 0
	for p in view.get("plots", []):
		var st := str(p.get("state", ""))
		if not st in ["growing", "ready"]: continue
		var c: Dictionary = crops.get(str(p.get("crop", "")), {})
		if c.is_empty(): continue
		var xp := floori(float(c.get("xp", 0)) * float(p.get("xp_pct", 100)) / 100.0)
		if not firsts.has("harvest:" + str(c.id)) and not counted.has(c.id):
			counted[c.id] = true
			xp += int(c.get("first_xp", 0))
		all_xp += xp
		if st == "ready": ready_xp += xp
	var lv := int(sk.get("level", 1)) + 1
	if base + ready_xp >= int(sk.next) and ready_xp > 0: return {level = lv, now = true}
	var harvested := firsts.any(func(f): return str(f).begins_with("harvest:"))
	if not harvested and base + all_xp >= int(sk.next): return {level = lv, now = false}
	return {}

# ---------------------------------------------------------------- world badges

## The farmhouse marker's REQUEST state, the guide's "!" (§14.3; #59, 250 v2: one mark per facility): a cookable
## fish in the bag while Today has a Cook row still to do.
static func door_badge(view: Dictionary) -> bool:
	var fish := false
	for s in view.get("bag", {}).get("slots", []):
		var id := str(s.get("id", ""))
		if id.begins_with("fish_") and P0Logic.item(view, id).get("cook", true): fish = true
	if not fish: return false
	for r in lead_rows(view):
		if str(r.get("go", "")) == "stove" and str(r.get("state", "")) != "done": return true
	return false

## The stall's badge (q(44)): "deliver" when a Stall Board request can be handed in now, "request" when one is open,
## else "". A badge from the board opens the drawer on the Stall Board page; the finger card still says Tap to shop.
static func stall_badge(view: Dictionary) -> String:
	var open := false
	for r in view.get("stall", {}).get("board", {}).get("requests", []):
		if int(r.get("have", 0)) >= int(r.get("qty", 1)): return "deliver"
		if str(r.get("status", "")) == "open": open = true
	return "request" if open else ""

# ---------------------------------------------------------------- Free to do now (§3.7.4)

## The rows after `Free to do now` closes the Energy card: what costs no Energy now, at most 3, in this order —
## crops to harvest, a dish the stove can make, 10+ of one thing to sell, a request to hand in, an unfinished mine
## run, then `Browse the map` (always possible). Only P0 features (no Plot Marks, social or decorating).
static func free_now(view: Dictionary) -> Array:
	var rows: Array = []
	var ready := (view.get("plots", []) as Array).filter(func(p): return str(p.get("state", "")) == "ready").size()
	if ready > 0: rows.append(_row("Harvest %d ready" % ready, "harvest", "plots"))
	var stove = view.get("cooking", {}).get("stove", null)
	if stove == null and (view.get("cooking", {}).get("cookbook", []) as Array).any(func(p): return p.get("can_cook", false)):
		var fish := 0
		for s in view.get("bag", {}).get("slots", []):
			if str(s.get("id", "")).begins_with("fish_") and P0Logic.item(view, str(s.id)).get("cook", true): fish += int(s.get("qty", 0))
		rows.append(_row("Cook · %d fish in creel" % fish if fish > 0 else "Cook · ingredients in bag", "pot", "stove"))
	var best := {}
	for s in view.get("bag", {}).get("slots", []):
		var info := P0Logic.item(view, str(s.get("id", "")))
		if info.get("sell", null) == null or s.get("locked", false) or s.get("gifted", false): continue
		if int(s.get("qty", 0)) >= 10 and int(s.get("qty", 0)) > int(best.get("qty", 0)): best = s
	if not best.is_empty(): rows.append(_row("Sell %d at Homestead Stall" % int(best.qty), str(best.id), "stall"))
	for r in view.get("stall", {}).get("board", {}).get("requests", []):
		if int(r.get("have", 0)) >= int(r.get("qty", 1)):
			rows.append(_row("Deliver %s" % str(r.get("title", "")), "board", "stall"))
			break
	if view.get("mine", {}).get("run", null) != null: rows.append(_row("Mine run · Continue · Free", "mine", ""))   # no camera target yet
	rows = rows.slice(0, 3)
	if rows.size() < 3: rows.append(_row("Browse the map", "map", "map"))   # the fallback, always possible
	return rows

# ---------------------------------------------------------------- quick bar

## Items new to the bag since the last view (a level gift, the first lettuce seeds): their quick-bar slot flashes once
## for UiTokens.MOTION_NEW_UNLOCK_FLASH_MS (§14.2 minutes 16 and 22).
static func new_items(before: Dictionary, after: Dictionary) -> Array:
	var had := {}
	for s in before.get("bag", {}).get("slots", []): had[str(s.get("id", ""))] = true
	var out: Array = []
	for s in after.get("bag", {}).get("slots", []):
		var id := str(s.get("id", ""))
		if not had.has(id) and not out.has(id): out.append(id)
	return out

# ---------------------------------------------------------------- helpers

static func _row(line: String, icon_id: String, go: String) -> Dictionary:
	return {"line": line, "icon": icon_id, "go": go, "state": "default", "tail": "", "focus": false}

static func _place_name(view: Dictionary, place: String) -> String:
	var p = view.get("fishing", {}).get("places", {}).get(place, null)
	if p is Dictionary and p.has("name"): return str(p.name)
	var c = P0Logic.content().get("fishing", {}).get("places", {}).get(place, {})
	return str(c.get("name", "Reed Pond")) if c is Dictionary else "Reed Pond"
