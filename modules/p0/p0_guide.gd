class_name P0Guide
extends RefCounted
## The first-session guide layer as pure rules over the server view (plan §14.2–14.5, §3.7.4, q(44), q(46), q(49);
## SGODOT-232 U6). The world and the panels only draw what these return: which TipCard to show and when, the rows
## that lead Today, the farmhouse door "!", the stall badge, Free to do now and the quick-bar flash. Every stage comes
## from the server's state, so a reinstall picks the guide up where the save is; only "tips already shown" is local.

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const TUTORIAL := "req_pond_catch"
static var BEGINNER_POND := P0City.beginner_pond()   # q(32): the written city's beginner pond (SGODOT-270)

## The player's beginner pond (q(162): the home set's, frozen with the home, SGODOT-303); the written city's where the
## view has none.
static func home_pond(view: Dictionary) -> String:
	var id := P0Outposts.home_id(view, "pond")
	return id if id != "" else BEGINNER_POND

## The home's beginner pond by name (`Fern Pond`, a generated home's own): Nadia's soup line (q(218) ①).
static func home_pond_name(view: Dictionary) -> String:
	return _place_name(view, home_pond(view))

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

## The seven built-in TipCards (q(215) §14.3). NPC dialogue never becomes a TipCard.
static func tip_text(key: String) -> String:
	return str(TIPS.get(key, ""))
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
		if key == "" or P0Guide.tip_text(key) == "" or seen.has(key) or showing == key or waiting.has(key): return false
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

# ---------------------------------------------------------------- new-player guide (SGODOT-341)
# The v3 server resolves the current step/recover into view.guide.row / marks / progress / pip (341 c6f3189a).
# Never read the bundled step table: its ids, places and copy can differ from the server's current content.
# Old servers and legacy saves have no active step; their existing first-session presentation stays intact.

static func guide_on(view: Dictionary) -> bool:
	var g = view.get("guide", null)
	return g is Dictionary and g.get("step", null) != null and str(g.step) != ""

static func guide_shown_id(view: Dictionary) -> String:
	if not guide_on(view): return ""
	var rec = view.guide.get("recover", null)
	return str(rec) if rec != null and str(rec) != "" else str(view.guide.step)

## Resolved presentation, including a recover row when needed. Never change the server's step or counters.
static func guide_shown(view: Dictionary) -> Dictionary:
	return view.guide if guide_on(view) else {}

## Adapt an actual place id to the existing camera-only Show route. Names always come from the server row.
static func guide_go(view: Dictionary, go: String) -> String:
	if go == "" or go in ["home", "plots", "stove", "stall", "bench", "board", "inbox"] or go.contains(":"): return go
	var home = view.get("home", {}).get("set", {})
	if go == str(home.get("pond", "")) or go == home_pond(view): return "pond:" + go
	for role in ["market", "tea", "tackle", "post"]:
		if go == str(home.get(role, "")): return "outpost:" + go
	if not P0Outposts.find(go).is_empty(): return "outpost:" + go
	if not SystemPonds.location(go).is_empty(): return "pond:" + go
	return go

## Today uses the server's already-resolved line and progress, including recover progress. Red-dot identity stays
## stable as a counter changes; a different step/recover is a new goal. The server row is never mutated.
static func guide_rows(view: Dictionary) -> Array:
	var g := guide_shown(view)
	var row = g.get("row", null)
	if not row is Dictionary or str(row.get("line", "")) == "": return []
	var r := _row(str(row.line), str(row.get("icon", "")), guide_go(view, str(row.go) if row.get("go") != null else ""), "guide:" + guide_shown_id(view))
	# s2 d17b83a4: page is resolved on a cook mark; home is its map destination, stove is its local Show target.
	var marks = g.get("marks", [])
	if marks is Array:
		for mark in marks:
			if mark is Dictionary and mark.get("page") is String and str(mark.page) != "":
				r.page = str(mark.page)
				if r.go == "home": r.go = "stove"
	var countdown := str(row.get("countdown", ""))
	if r.go == "home" and (countdown != "" or str(r.icon).begins_with("seed_") or str(r.icon).begins_with("crop_")):
		r.go = "plots"
	if countdown != "":
		# The countdown's typed crop/count/time fields choose the copy; no parsing/replacing words in row.line.
		if row.get("ready_in") != null:
			var name := P0Logic.item_name(view, countdown)
			if int(row.get("count", 0)) != 1: name = P0Logic.plural(name)
			var ms := maxf(0.0, float(row.ready_in))
			var time := P0Logic.duration(ms) if str(row.get("format", "")) == "mss" else P0Logic.span(ms)
			r.line = "%s ready in %s" % [name, time]
	else:
		var p = g.get("progress", null)
		var recover_fish := g.get("recover") != null and str(r.go).begins_with("pond:")
		if p is Dictionary and (int(p.get("need", 0)) > 1 or recover_fish and int(p.get("need", 0)) > 0):
			r.tail = "%d/%d" % [int(p.get("have", 0)), int(p.need)]
	return [r]

## Keep all seven original scene/event triggers (q(215) ⑤). A step never introduces an eighth card or starts one
## early. TipQueue still handles seen state, the action closing a card, and RewardMoment ordering.
static func tip_allowed(_view: Dictionary, key: String) -> bool:
	return TIPS.has(key)

## The server's actual targets (plot numbers, place ids, resident ids and button keys), never bundled aliases.
static func guide_marks(view: Dictionary) -> Array:
	var marks = guide_shown(view).get("marks", [])
	return marks if marks is Array else []

static func button_marks(view: Dictionary) -> Array:
	return guide_marks(view).filter(func(m): return m is Dictionary and m.get("button") is String and bool(m.get("pulse", false)))

static func marked_resident(view: Dictionary) -> String:
	for mark in guide_marks(view):
		if mark is Dictionary and mark.get("resident") is String: return str(mark.resident)
	return ""

static func target_place(view: Dictionary, place: String) -> bool:
	if not guide_on(view): return true
	if place == "": return false
	return guide_marks(view).any(func(m): return m is Dictionary and str(m.get("place", "")) == place)

## A semantic entry point: only its current target's state survives during the guide. The callers deliberately
## exclude ordinary crop/resource facts, HUD dots and the Mailbox's Parcel count (341 ec56d336).
static func target_badge(view: Dictionary, field: String, id: String, ordinary := "") -> String:
	if not guide_on(view): return ordinary
	for mark in guide_marks(view):
		if mark is Dictionary and str(mark.get(field, "")) == id: return str(mark.get("kind", ""))
	return ""

static func resident_badge(view: Dictionary, id: String, place := "") -> String:
	if place != "" and not target_place(view, place): return ""
	var r: Dictionary = view.get("residents", {}).get(id, {})
	var req = r.get("request", null)
	var ordinary := "request" if str(r.get("request_state", "")) == "open" else ""
	if str(r.get("request_state", "")) == "accepted" and req is Dictionary and bool(req.get("ready", false)): ordinary = "deliverable"
	var kind := target_badge(view, "resident", id, ordinary)
	# S6's one target progresses from a new request to a real hand-in; S10's gift heart is never replaced by a tick.
	if kind == "request" and ordinary == "deliverable": return ordinary
	return "deliverable" if kind == "deliver" else kind

static func teaching_plots(view: Dictionary) -> Array:
	var ids := []
	for mark in guide_marks(view):
		if not mark is Dictionary or not mark.get("plot") is float and not mark.get("plot") is int: continue
		var id := int(mark.plot)
		if id >= 0 and id < P0Garden.plot_count(view) and not ids.has(id): ids.append(id)
	return ids

static func pip(view: Dictionary) -> Dictionary:
	var data = guide_shown(view).get("pip", {})
	return data if data is Dictionary else {}

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
static func lead_rows(view: Dictionary, leave: Variant = null) -> Array:
	if guide_on(view): return focus_first(guide_rows(view))   # the new-player guide leads instead (SGODOT-341)
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
		if int(t.get("have", 0)) >= qty: rows.append(_row("Deliver %d %s · Stall" % [qty, fish], str(t.item), "stall", "deliver:" + TUTORIAL))
		else: rows.append(_row("Catch %d %s · %s" % [qty, fish, _place_name(view, home_pond(view))], str(t.item),
			"pond:" + home_pond(view), "catch:" + TUTORIAL))   # the pond is elsewhere: Show on map (q(31)); the stall's "!" asks to take it
	elif first:
		var done := _row("Deliver 2 %s · Stall" % P0Logic.item_name(view, "fish_crucian"), "fish_crucian", "stall")
		done.state = "done"
		rows.append(done)
	# Cook it: Grilled Crucian — through the first session (ticked once cooked), and after it until the first dish is made
	if not grill.is_empty() and (first or not grill.get("cooked", false)):
		# It lights the red dot once the stove can make it (the Pond Catch handed in, fish in the bag), like a new recipe.
		var cook := _row("Cook it: %s" % str(grill.get("name", "Grilled Crucian")), "dish_grilled_crucian", "stove",
			"cook:dish_grilled_crucian" if grill.get("can_cook", false) else "")
		cook.page = "dish_grilled_crucian"   # Show opens the stove drawer on it (q(99))
		if grill.get("cooked", false): cook.state = "done"
		rows.append(cook)
	if first: return focus_first(rows)   # the third row is the radishes' timer (P0Logic), not another goal
	var third := third_slot_row(view)
	if not third.is_empty(): rows.append(third)
	var fresh := new_recipe_row(view)
	if not fresh.is_empty(): rows.append(fresh)
	var sow := sow_row(view, leave)
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
			var fresh := _row("Cook: %s · new recipe" % str(p.get("name", "")), str(p.id), "stove", "recipe:" + str(p.id))
			fresh.page = str(p.id)   # Show opens the stove drawer on it (q(99))
			return fresh
	return {}

## `3rd slot open · try Fine fish + Potato + Rock Salt` (q(46)): from Cooking Lv4 until the first 3-slot dish.
static func third_slot_row(view: Dictionary) -> Dictionary:
	if int(view.get("cooking", {}).get("slots", 2)) < 3: return {}
	for p in view.get("cooking", {}).get("cookbook", []):
		if int(p.get("slots", 0)) >= 3 and p.get("cooked", false): return {}
	return _row("3rd slot open · try Fine fish + Potato + Rock Salt", "pot", "stove", "slot3")

## `Sow 10 Lettuce · 20 Energy` (§14.2 minute 16): seeds in the bag and free beds (wild ones till for free). Short of
## Energy the row stays, with `needs 20 Energy · +8 in 21m` (§14.5). Before the first sow P0Logic has its own row.
## A crop a taken request's row already says to sow (`Six Radishes · Sow 6 Radishes`) is left to that row: the next
## seed in the bag gets this one (q(258) ①). `leave`: those crops (null: every one a request says to sow; Today passes
## only the ones its three rows show, P0Logic.today_rows).
static func sow_row(view: Dictionary, leave: Variant = null) -> Dictionary:
	var plots: Array = view.get("plots", [])
	if not plots.any(func(p): return str(p.get("state", "")) in ["sown", "growing", "ready"]) \
			and not (view.get("firsts", []) as Array).any(func(f): return str(f).begins_with("harvest:")):
		return {}
	var free := plots.filter(func(p): return str(p.get("state", "")) in ["tilled", "wild"]).size()
	if free == 0: return {}
	var asked: Array = leave if leave is Array else P0Logic.request_sow_crops(view)
	for s in view.get("bag", {}).get("slots", []):
		var seed := str(s.get("id", ""))
		if not seed.begins_with("seed_"): continue
		var crop := P0Logic.crop_for_seed(view, seed)
		if crop.is_empty() or asked.has(P0Logic.harvest_of(view, str(crop.id))): continue
		var n := mini(int(s.get("qty", 0)), free)
		if n <= 0: continue
		var cost := n * int(crop.get("energy", 2))
		var r := _row("Sow %d %s · %d Energy" % [n, crop_count_name(view, str(crop.id), n), cost], seed, "plots", "sow:" + seed)
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

## ` · +8 in 20:41`: the Energy still missing and when natural recovery brings it.
static func _gain_in(e: Dictionary, gap: int) -> String:
	if e.get("next_in", null) == null: return ""
	var ms := float(e.next_in) + float(gap - 1) * float(e.get("regen_ms", 240000))
	return " · +%d in %s" % [gap, P0Logic.duration(ms)]   # Energy regen ticks each second: `+2 in 7:41` (q(97) ①)

## ` · Farming Lv2 at first harvest` (§14.2 end): what the growing beds' locked XP and first-harvest bonuses reach.
static func harvest_level_tail(view: Dictionary) -> String:
	var h := harvest_level(view)
	return " · Farming Lv%d at first harvest" % int(h.level) if not h.is_empty() else ""

## Whether harvesting reaches the next Farming level (q(69), RETURN-SESSION): {level, now: true} when the plots ready
## now are enough (`Farming Lv2 with this harvest`); {level, now: false} when it takes the growing ones too and no crop
## was ever harvested (`Farming Lv2 at your first harvest`); {} otherwise. First-harvest bonuses count once a crop.
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
		var c: Dictionary = crops.get(P0Logic.harvest_of(view, str(p.get("crop", ""))), {})   # a Quick Radish counts as a Radish (q(217))
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
	if guide_on(view): return target_badge(view, "place", "home") == "request"
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
## While the new-player guide is on, none: the guide marks only its current step's targets and the stall is never one
## (q(215) ④ ⑥, 不知火舞 on #496 — the first slot refilled before the guide ends waits for it, a ✓ too).
## `mark`: the stall's own mark in the world, which hangs no ✓ once today's 6 are done, as the map's pins (q(270));
## the drawer still opens on the board, where the hand-in reads Limit reached.
static func stall_badge(view: Dictionary, mark := false) -> String:
	if guide_on(view): return ""
	var full := mark and P0Logic.sys_requests_full(view)
	var open := false
	for r in view.get("stall", {}).get("board", {}).get("requests", []):
		if int(r.get("have", 0)) >= int(r.get("qty", 1)) and not full: return "deliver"
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
	if view.get("mine", {}).get("run", null) != null: rows.append(_row("Mine run · Continue", "mine", ""))   # no camera target yet
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

## `dot`: the row's key for the Today icon's red dot (P0Logic.today_dots, q(107)); "" lights nothing.
static func _row(line: String, icon_id: String, go: String, dot := "") -> Dictionary:
	return {"line": line, "icon": icon_id, "go": go, "state": "default", "tail": "", "focus": false, "dot": dot}

static func _place_name(view: Dictionary, place: String) -> String:
	var p = view.get("fishing", {}).get("places", {}).get(place, null)
	if p is Dictionary and p.has("name"): return str(p.name)
	var g: Dictionary = load("res://modules/p0/p0_city_places.gd").pond(place)   # a generated home's (SGODOT-303)
	if not g.is_empty(): return str(g.get("name", "Pond"))
	var c = P0Logic.content().get("fishing", {}).get("places", {}).get(place, {})
	return str(c.get("name", "Pond")) if c is Dictionary else "Pond"
