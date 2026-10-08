class_name P0MaterialLogic
extends RefCounted
## SGODOT-231 client rules for the material chain, read only from the server view: the mine mouth, the mine floors
## and elevator (plan §13.3, LOCK-21, q(44)), gathering spots (§13.2) and the workbench (§13.4, B2-06). Farm Storage
## rows in the bag drawer follow P0ItemInfo.kind_of (225), not this file. Every user-visible string is written here, so
## scenes only render. Pure and static: tested headless.
## Key dicts have the P0Logic.main_action shape {icon, verb, sub, enabled, amber, cmd, need}; line 2 (sub) stays
## within ~16 characters (q(44)). An unavailable key is grey (enabled false) and may carry `toast`, the long reason a
## press shows (LOCK-10: unavailable stays tappable and says why).

const ENTRANCE := 0

static func _energy(view: Dictionary) -> int:
	return int(view.get("energy", {}).get("value", 0))

## Mining's free moves keep "Free" on the key: LOCK-21 and its 10-08 LOCK-02 clarification write `Elevator · Free`,
## q(46) `Exit mine · Free` / `Floor 1 · Free`, §13.3.8 `Light Torch · Free` (P0Ui drops "Free" elsewhere).
static func _key(icon: String, verb: String, sub: String, cmd := {}, enabled := true, amber := false, need := 0) -> Dictionary:
	var k := {"icon": icon, "verb": verb, "sub": sub, "enabled": enabled, "amber": amber, "cmd": cmd, "need": need}
	if sub == "Free": k["show_free"] = true
	return k

## A grey key whose press toasts `reason`.
static func _unavailable(icon: String, verb: String, sub: String, reason: String) -> Dictionary:
	var k := _key(icon, verb, sub, {}, false)
	k["toast"] = reason
	return k

const BAG_FULL := "Bag full · free a slot to mine"

## The key's tool badge in the mine and at its mouth (LOCK-02, LOCK-29): the equipped pickaxe (P0Ui.set_action `tool`).
static func _with_pick(view: Dictionary, key: Dictionary) -> Dictionary:
	key["tool"] = str(view.get("gear", {}).get("slots", {}).get("mining", "pickaxe"))
	return key

static func _runs_line(mine: Dictionary) -> String:
	var runs: Dictionary = mine.get("runs", {})
	return "Mine runs today %d/%d · Resets in %s" % [int(runs.get("used", 0)), int(runs.get("limit", 2)), P0Logic.duration(float(runs.get("resets_in", 0)))]

static func _floor(view: Dictionary, n: int) -> Dictionary:
	var run = view.get("mine", {}).get("run", null)
	if run == null: return {}
	for f in run.get("floors", []):
		if int(f.get("floor", 0)) == n: return f
	return {}

# --- Mine mouth (farm side) ---

## Main action key at the farm's mine mouth (LOCK-21): Continue run · Free with an unfinished run, else Enter mine.
static func mine_entry_action(view: Dictionary) -> Dictionary:
	return _with_pick(view, _mine_entry_action(view))

static func _mine_entry_action(view: Dictionary) -> Dictionary:
	var mine: Dictionary = view.get("mine", {})
	var fee := int(mine.get("floor_energy", 2))
	if mine.get("run", null) != null:
		return _key("pickaxe", "Continue run", "Free", {"type": "mine_enter"})
	var runs: Dictionary = mine.get("runs", {})
	if int(runs.get("used", 0)) >= int(runs.get("limit", 2)):
		return _unavailable("pickaxe", "Enter mine", "No runs left", _runs_line(mine))
	if not mine.get("entry_bag_ok", true): return _unavailable("pickaxe", "Enter mine", "Bag full", BAG_FULL)   # q(48)
	if _energy(view) < fee:
		return _key("pickaxe", "Enter mine", "Need %d Energy" % fee, {"type": "energy_card"}, true, true, fee)
	return _key("pickaxe", "Enter mine", "%d Energy" % fee, {"type": "mine_enter"}, true, false, fee)

## The EntryCard over the mine mouth (MINE-P0-5): only with an unfinished run; a secondary text button to start over.
## {show, label, line2, enabled, amber, cmd}; line2 is empty when unavailable (the reason is the label).
static func mine_entry_card(view: Dictionary) -> Dictionary:
	var mine: Dictionary = view.get("mine", {})
	var run = mine.get("run", null)
	if run == null: return {"show": false}
	var fee := int(mine.get("floor_energy", 2))
	var runs: Dictionary = mine.get("runs", {})
	match str(run.get("new_run_block", "")):
		"clear_floor_2":
			return {"show": true, "label": "New run · Clear Floor 2 first", "line2": "", "enabled": false, "amber": false, "cmd": {},
				"toast": "New run · Clear Floor 2 first"}
		"no_runs":
			return {"show": true, "label": _runs_line(mine), "line2": "", "enabled": false, "amber": false, "cmd": {}, "toast": _runs_line(mine)}
	if not mine.get("entry_bag_ok", true):   # q(48): no fee into a floor whose first rock wouldn't fit
		return {"show": true, "label": "New run · Bag full", "line2": "", "enabled": false, "amber": false, "cmd": {}, "toast": BAG_FULL}
	var consequence := "Current run will end · Runs today %d/%d" % [int(runs.get("used", 0)), int(runs.get("limit", 2))]
	if _energy(view) < fee:   # warning action line, the consequence kept, the tap opens the Energy card (不知火舞 on #45)
		return {"show": true, "label": "New run · Need %d Energy" % fee, "line2": consequence, "enabled": true, "amber": true, "cmd": {"type": "energy_card"}}
	return {"show": true, "label": "New run · %d Energy" % fee, "line2": consequence, "enabled": true, "amber": false, "cmd": {"type": "mine_new_run"}}

## What a server refusal of a material command says (苏烈's #39 review). null: not ours, the runtime's own wording
## applies (need_energy opens the Energy card). "": quiet — a race the next frame shows anyway (a held repeat hitting
## the 0.9 s tempo, a rock another press already broke, a torch already lit, a run that just ended). Else a toast.
static func refusal_text(code: String, detail: Dictionary, cmd: Dictionary) -> Variant:
	var type := str(cmd.get("type", ""))
	if not (type.begins_with("mine_") or type == "gather"): return null
	match code:
		"tempo", "rock_gone", "lit", "no_run", "floor_not_paid", "bad_floor", "not_in_mine", "stale_state", "bad_spot":
			return ""
		"bag_full":
			return BAG_FULL if type.begins_with("mine_") else "Bag full · free a slot first"
		"no_runs":
			return "Enter mine · No runs left"
		"clear_floor_first":   # detail.floor is the floor to clear (going to Floor 2 → 1; a new run → restart_floor 2)
			return "Clear Floor %d first" % int(detail.get("floor", 1))
		"homestead_level":
			return "Homestead Lv%d" % int(detail.get("need", 2))
		"not_ready":
			return "Ready in %s" % P0Logic.duration(float(detail.get("ready_in", 0)))
	return null

## The Energy card's verb for a refused material command ("Mine", "Enter mine", "Floor 2"); `fallback` for others.
static func energy_verb(cmd: Dictionary, fallback: String) -> String:
	match str(cmd.get("type", "")):
		"mine_rock": return "Mine"
		"mine_enter", "mine_new_run": return "Enter mine"
		"mine_floor": return "Floor %d" % int(cmd.get("floor", 2))
	return fallback

## "Run ended at daily reset" once per ended run (q(44)): the text when the view's `ended.at` is newer than the last shown.
static func reset_notice(view: Dictionary, shown_at: float) -> String:
	var ended = view.get("mine", {}).get("ended", null)
	if ended == null or float(ended.get("at", 0)) <= shown_at: return ""
	return "Run ended at daily reset"

## The mine mouth's world badge (MAT-1 / MINE-P0-5): "Explore" with no run, "Run 1/2" with one.
static func mine_badge(view: Dictionary) -> String:
	var mine: Dictionary = view.get("mine", {})
	if mine.get("run", null) == null: return "Explore"
	var runs: Dictionary = mine.get("runs", {})
	return "Run %d/%d" % [int(runs.get("used", 0)), int(runs.get("limit", 2))]

## "The mine" sheet from tapping the mouth (MINE-P0-1 / P0-8): {title, subtitle, line, facts: [[k, v]], button}.
## button {label, enabled}: only when no run is possible today (Mine runs today 2/2 · Resets in 9h 12m, grey).
static func mine_sheet(view: Dictionary) -> Dictionary:
	var mine: Dictionary = view.get("mine", {})
	var runs: Dictionary = mine.get("runs", {})
	var used := int(runs.get("used", 0))
	var limit := int(runs.get("limit", 2))
	var sheet := {"title": "The mine", "subtitle": "Entrance", "line": "Explore two floors and gather materials.",
		"facts": [["Runs today", "%d/%d" % [used, limit]]], "button": {}}
	if mine.get("run", null) == null and used >= limit:
		sheet.subtitle = "No run · Runs today %d/%d" % [used, limit]
		sheet.line = ""
		sheet.facts = []
		sheet.button = {"label": _runs_line(mine), "enabled": false}
	return sheet

## New run confirmation (MINE-P0-7), opened from the EntryCard: {title, subtitle, facts, cost, note, confirm, keep}.
## No "Unmined rocks…" line: a new run needs floor 2 cleared, so nothing is left to lose (Li Bai, 231 3f6b8fb5).
static func new_run_sheet(view: Dictionary) -> Dictionary:
	var mine: Dictionary = view.get("mine", {})
	var runs: Dictionary = mine.get("runs", {})
	var used := int(runs.get("used", 0))
	var limit := int(runs.get("limit", 2))
	return {"title": "The mine", "subtitle": "New run", "facts": [["Runs today", "%d/%d → %d/%d" % [used, limit, mini(used + 1, limit), limit]]],
		"cost": ["New run", "%d Energy" % int(mine.get("floor_energy", 2))], "note": "Your stored materials stay yours.",
		"confirm": {"label": "Start new run", "cmd": {"type": "mine_new_run"}}, "keep": "Keep current run"}

## Status line under the HUD in the mine (MINE-1 / P0-2): "Rocks 2/6" for the floor; "Run 1/2 today" just after entering.
static func mine_status(view: Dictionary, n: int, just_entered := false) -> String:
	var mine: Dictionary = view.get("mine", {})
	if just_entered:
		var runs: Dictionary = mine.get("runs", {})
		return "Run %d/%d today" % [int(runs.get("used", 0)), int(runs.get("limit", 2))]
	var floor := _floor(view, n)
	if floor.is_empty(): return ""
	var rocks := int(mine.get("rocks", 6))
	return "Rocks %d/%d" % [rocks - int(floor.get("left", rocks)), rocks]

# --- Inside the mine ---

## Main action key in the mine. ctx: {floor: int, target: "rock" | "stairs" | "up" | "exit" | "elevator" | "", rock: int,
## item: String} where item is the quick-bar selection ("torch" or ""). Rocks and stairs never respond to taps (LOCK-02).
## Every 0-Energy move reads "· Free" (Exit mine · Free, Floor 1 · Free; Li Bai q(46)).
static func mine_action(view: Dictionary, ctx: Dictionary) -> Dictionary:
	return _with_pick(view, _mine_action(view, ctx))

static func _mine_action(view: Dictionary, ctx: Dictionary) -> Dictionary:
	var mine: Dictionary = view.get("mine", {})
	var n := int(ctx.get("floor", 1))
	var floor := _floor(view, n)
	if floor.is_empty(): return _key("pickaxe", "Mine", "Run ended", {}, false)
	if str(ctx.get("item", "")) == "torch":
		if floor.get("lit", false): return _key("torch", "Light Torch", "Lit", {}, false)
		return _key("torch", "Light Torch", "Free", {"type": "mine_torch", "floor": n})
	var fee := int(mine.get("floor_energy", 2))
	match str(ctx.get("target", "")):
		"elevator":
			return _key("elevator", "Elevator", "Free", {"type": "elevator"})
		"exit":
			return _key("stairs", "Exit mine", "Free", {"type": "mine_exit"})
		"up":
			return _key("stairs", "Floor %d" % (n - 1), "Free", {"type": "mine_floor", "floor": n - 1})
		"stairs":
			var next := _floor(view, n + 1)
			if next.is_empty(): return _key("stairs", "Stairs", "Deepest floor", {}, false)
			var verb := "Floor %d" % (n + 1)
			if next.get("paid", false): return _key("stairs", verb, "Free", {"type": "mine_floor", "floor": n + 1})
			if not floor.get("cleared", false): return _unavailable("stairs", verb, "Clear Floor %d" % n, "%s · Clear this floor first" % verb)
			if not next.get("bag_ok", true): return _unavailable("stairs", verb, "Bag full", BAG_FULL)   # q(48)
			if _energy(view) < fee: return _key("stairs", verb, "Need %d Energy" % fee, {"type": "energy_card"}, true, true, fee)
			return _key("stairs", verb, "%d Energy" % fee, {"type": "mine_floor", "floor": n + 1}, true, false, fee)
		"rock":
			var rock := int(ctx.get("rock", -1))
			var broken: Array = floor.get("broken", [])
			var cost := int(mine.get("rock_energy", 2))
			if rock < 0 or rock >= broken.size() or bool(broken[rock]): return _key("pickaxe", "Mine", "Walk to a rock", {}, false)
			if not floor.get("bag_ok", true): return _unavailable("pickaxe", "Mine", "Bag full", BAG_FULL)
			if _energy(view) < cost: return _key("pickaxe", "Mine", "Need %d Energy" % cost, {"type": "energy_card"}, true, true, cost)
			return _key("pickaxe", "Mine", "%d Energy" % cost, {"type": "mine_rock", "floor": n, "rock": rock}, true, false, cost)
	if int(floor.get("left", 0)) == 0: return _key("pickaxe", "Mine", "Floor cleared", {}, false)
	return _key("pickaxe", "Mine", "Walk to a rock", {}, false)

## Mining quick bar: torches only (§13.3.8; P0 has no dynamite). Ghost word when empty: "Torch" (q(44)).
const MINE_FAMILY := ["torch"]

static func mine_candidates(view: Dictionary) -> Array:
	return MINE_FAMILY.filter(func(id): return P0Logic.bag_count(view, str(id)) > 0)

## The Mining bar with LOCK-05 pins like Farming / Fishing: kept order first, pinned stay at 0, flung-off ones
## stay off until pinned again.
static func mine_bar(view: Dictionary, previous: Array, pinned: Array = [], removed: Array = []) -> Array:
	var have := mine_candidates(view)
	var bar: Array = []
	for id in previous:
		if MINE_FAMILY.has(id) and not bar.has(id) and (pinned.has(id) or (have.has(id) and not removed.has(id))): bar.append(id)
	for id in pinned:
		if MINE_FAMILY.has(id) and not bar.has(id): bar.append(id)
	for id in have:
		if not bar.has(id) and not removed.has(id): bar.append(id)
	return bar

const ELEVATOR_TITLE := "Elevator · stops this run"   # MINE-P0-6 panel header

## Elevator card rows (§13.3.9, q(44); P0: Entrance, Floor 1, Floor 2, no Express). here: 0 = entrance, else a floor.
## Each row {name, state, label, enabled, amber, cmd}: MINE-P0-6 draws name left and state right ("Floor 1" · "Free");
## label is the joined line (≤ 26 characters). cmd type "mine_leave" (back to the farm) or "mine_floor" {floor}.
static func elevator_rows(view: Dictionary, here: int) -> Array:
	var rows: Array = []
	for r in _elevator_rows(view, here):
		var parts := str(r.label).split(" · ", true, 1)
		r["name"] = parts[0]
		r["state"] = parts[1] if parts.size() > 1 else ""
		rows.append(r)
	return rows

static func _elevator_rows(view: Dictionary, here: int) -> Array:
	var mine: Dictionary = view.get("mine", {})
	var fee := int(mine.get("floor_energy", 2))
	var rows: Array = []
	rows.append({"label": "Entrance · Here" if here == ENTRANCE else "Entrance · Free", "enabled": here != ENTRANCE, "amber": false,
		"cmd": {} if here == ENTRANCE else {"type": "mine_leave"}})
	var run = mine.get("run", null)
	if run == null: return rows
	var floors: Array = run.get("floors", [])
	for i in floors.size():
		var f: Dictionary = floors[i]
		var n := int(f.get("floor", i + 1))
		var row := {"label": "", "enabled": false, "amber": false, "cmd": {}}
		if n == here: row.label = "Floor %d · Here" % n
		elif f.get("paid", false): row = {"label": "Floor %d · Free" % n, "enabled": true, "amber": false, "cmd": {"type": "mine_floor", "floor": n}}
		elif i > 0 and not floors[i - 1].get("cleared", false): row.label = "Floor %d · Clear Floor %d first" % [n, n - 1]
		elif not f.get("bag_ok", true): row.label = "Floor %d · Bag full" % n   # q(48)
		elif _energy(view) < fee: row = {"label": "Floor %d · Need %d Energy" % [n, fee], "enabled": true, "amber": true, "cmd": {"type": "energy_card"}}
		else: row = {"label": "Floor %d · %d Energy" % [n, fee], "enabled": true, "amber": false, "cmd": {"type": "mine_floor", "floor": n}}
		rows.append(row)
	return rows

## What each rock of a floor shows: gone, greyed by a full bag (whole floor, q(44)), and the torch preview icon id
## ("" = Stone only, null = not lit).
static func rock_marks(view: Dictionary, n: int) -> Array:
	var floor := _floor(view, n)
	var out: Array = []
	if floor.is_empty(): return out
	var broken: Array = floor.get("broken", [])
	var preview = floor.get("preview", null)
	for i in broken.size():
		var drop = null
		if preview is Array and i < preview.size(): drop = "" if preview[i] == null else str(preview[i])
		out.append({"broken": bool(broken[i]), "grey": not floor.get("bag_ok", true), "preview": drop})
	return out

## Floats for mine events: floor fees, a cleared floor (Floor 1 cleared · Elevator stop). Drops float as items (runtime).
static func mine_event_text(e: Dictionary) -> String:
	if str(e.get("kind", "")) != "mine": return ""
	match str(e.get("action", "")):
		"enter", "floor":
			return "Floor %d · −%d Energy" % [int(e.get("floor", 1)), int(e.get("cost", 0))] if int(e.get("cost", 0)) > 0 else ""
		"cleared":
			return "Floor %d cleared · Elevator stop" % int(e.get("floor", 1))
	return ""

# --- Gathering spots (farm) ---

## Finger card and badge per spot (§13.2.2, STATE-ICONS): READY with "Tap to gather", a countdown, or the Homestead gate.
static func gather_marks(view: Dictionary) -> Array:
	var out: Array = []
	for sp in view.get("gather", {}).get("spots", []):
		var name := str(sp.get("name", ""))
		var mark := {"id": str(sp.get("id", "")), "name": name, "ready": bool(sp.get("ready", false)), "badge": "", "caption": ""}
		if not sp.get("open", false):
			mark.badge = "locked"
			mark.caption = "%s · Homestead Lv%d" % [name, int(sp.get("homestead", 2))]
		elif sp.get("ready", false):
			mark.badge = "ready"
			mark.caption = "%s · Tap to gather" % name
		else:
			mark.badge = "countdown"
			mark.caption = "%s · Ready in %s" % [name, P0Logic.duration(float(sp.get("ready_in", 0)))]
		out.append(mark)
	return out

## Today line 2 (§13.2.2, q(46) wording): "Timber Grove · Ready in 2h 10m" for the soonest open spot that is not ready; "" if one is ready.
static func today_gather_line(view: Dictionary) -> String:
	var best := {}
	for sp in view.get("gather", {}).get("spots", []):
		if not sp.get("open", false): continue
		if sp.get("ready", false): return ""
		if best.is_empty() or float(sp.get("ready_in", 0)) < float(best.get("ready_in", 0)): best = sp
	if best.is_empty(): return ""
	return "%s · Ready in %s" % [str(best.get("name", "")), P0Logic.duration(float(best.get("ready_in", 0)))]

## Floats for one gather event (MAT-2): "+6 Timber · Stored" for what went to Farm Storage. What went to the bag
## ("+2 Worm Bait") is an item event the runtime floats already, so the Reed Bank still shows two lines (Li Bai 3f6b8fb5).
static func gather_floats(view: Dictionary, e: Dictionary) -> Array:
	var out: Array = []
	for it in e.get("items", []):
		if str(it[2]) == "storage": out.append("+%d %s · Stored" % [int(it[1]), P0Logic.item_name(view, str(it[0]))])
	return out

## Coming home (q(40)): "Stored · 12 Stone · 3 Copper Ore" once per new storage.auto.at (number first, appendix B).
static func stored_notice(view: Dictionary, shown_at: float) -> String:
	var auto = view.get("storage", {}).get("auto", null)
	if auto == null or float(auto.get("at", 0)) <= shown_at: return ""
	var parts: Array = []
	for it in auto.get("items", []): parts.append("%d %s" % [int(it[1]), P0Logic.item_name(view, str(it[0]))])
	return "Stored · " + " · ".join(parts)

## Locked spot sheet (MAT-3): tapping the Clay Bank before Homestead Lv2.
static func locked_spot_sheet(view: Dictionary, spot_id: String) -> Dictionary:
	for sp in view.get("gather", {}).get("spots", []):
		if str(sp.get("id", "")) != spot_id: continue
		var item := str((sp.get("yield", [[""]]) as Array)[0][0])
		return {"title": str(sp.get("name", "")), "subtitle": "Locked",
			"line": "Gather %s from this spot once unlocked." % P0Logic.item_name(view, item),
			"facts": [["Unlock", "Homestead Lv%d" % int(sp.get("homestead", 2))]]}
	return {}

## Gather Gloves moment (MAT-GLOVES-RESULT): MomentBanner lines after crafting them.
static func gloves_moment(view: Dictionary) -> Dictionary:
	var next := 0
	for sp in view.get("gather", {}).get("spots", []):
		if str(sp.get("id", "")) == "spot_grove": next = int((sp.get("yield", [["", 0]]) as Array)[0][1])
	return {"title": "Gather Gloves", "line": "+1 at every gathering spot",
		"fact": "Next Timber harvest: %d" % next, "note": "Passive · no gear slot needed"}

# --- Material sources (NeedSource) ---

## Where a material comes from, for a tapped NEED-TILE (LOCK-10, one line; Show only moves the camera, LOCK-08), shared
## by HOME-1 and the workbench. Li Bai q(65), plan §8.6.1 / §8.6.2: sources joined by ` · or `; a spot that is not open
## yet comes last with its gate, `Clay · Mine floor 1 · or Clay Bank from Homestead Lv2`, and loses only the gate once
## open, `Clay · Mine floor 1 · or Clay Bank`. Order: spots open from the start, then the mine floors that yield it
## (every rock gives Stone: `Stone · Rock Pile · or the mine`), then spots a Homestead level opens; still-locked ones last.
## `go` (Show, 不知火舞 on 228): the first open source ("spot_grove", "mine"); with none open, the first source (its
## name strip says the gate). {} for anything that is not a material (content.materials) or that nothing yields.
## Two lines at most (不知火舞 on 228): the label may break only before ` · or `, so every other space is a no-break
## space and the floor range's en dash is followed by U+2060 — `Clay · Mine floor 1` / `· or Clay Bank from Homestead Lv2`.
static func material_source(view: Dictionary, id: String) -> Dictionary:
	var c := P0Logic.content()
	if not c.get("materials", {}).has(id): return {}   # bait also comes from the tackle shop: only materials here
	var live := {}   # the view's spot states (open / homestead) by id
	for sp in view.get("gather", {}).get("spots", []): live[str(sp.get("id", ""))] = sp
	var level := int(view.get("homestead", {}).get("level", 1))
	var first: Array = []
	var gated: Array = []
	var gather: Dictionary = c.get("gather", {}).get("spots", {})
	for sid in gather:
		var y: Array = gather[sid].get("yield", [])
		if y.is_empty() or str(y[0][0]) != id: continue   # a side yield (Worm Bait at the Reed Bank) is not the spot's material
		var sp: Dictionary = live.get(str(sid), {})
		var gate := int(sp.get("homestead", gather[sid].get("homestead", 1)))
		var src := {"name": str(sp.get("name", gather[sid].get("name", ""))), "go": str(sid), "gate": gate,
			"open": bool(sp.get("open", gate <= level))}
		(first if gate <= 1 else gated).append(src)
	var floors: Array = []
	for f in c.get("mine", {}).get("floors", []):
		var yields := id == "stone"
		for d in f.get("drops", []):
			if d[0] != null and str(d[0]) == id: yields = true
		if yields: floors.append(int(f.get("floor", 0)))
	if not floors.is_empty():
		var where := "Mine floor %d" % floors[0] if floors.size() == 1 else "Mine floors %d–\u2060%d" % [floors.min(), floors.max()]
		if id == "stone": where = "the mine"   # every rock gives Stone: no floors to name (Li Bai on 228)
		first.append({"name": where, "go": "mine", "gate": 1, "open": true})
	var all: Array = first + gated
	if all.is_empty(): return {}
	var ordered: Array = all.filter(func(s): return s.open) + all.filter(func(s): return not s.open)
	var parts: Array = ordered.map(func(s): return s.name if s.open else "%s from Homestead Lv%d" % [s.name, s.gate])
	var text := _nowrap("%s · %s" % [P0Logic.item_name(view, id), parts[0]])
	for i in range(1, parts.size()): text += " " + _nowrap("· or %s" % parts[i])   # the only breakable space
	return {"text": text, "go": str(ordered[0].go)}

const _NBSP := "\u00a0"

static func _nowrap(s: String) -> String:
	return s.replace(" ", _NBSP)

# --- Workbench (B2-06) ---

## Effect line under each recipe name (LOCK-29; q(45) gloves sentence; Compost per Li Bai / Anqila, B2-06).
const EFFECTS := {
	"pick_copper": "2 Stone per rock",
	"gather_gloves": "+1 at every gathering spot",
	"torch": "See what rocks hold",
	"fert_compost": "Crops ready 20% sooner",
}

## Cards for one tab ("tools" | "supplies"): icon, name, effect, NEED-TILE costs, Supplies yield/have, one button.
## button {label, kind: "primary" | "secondary" | "unavailable" | "done", cmd}; unavailable reasons sit on the button (LOCK-10).
static func workbench_model(view: Dictionary, tab: String) -> Array:
	var out: Array = []
	for r in view.get("workbench", {}).get("recipes", []):
		if str(r.get("tab", "")) != tab: continue
		var item := str(r.get("item", ""))
		var card := {
			"id": str(r.get("id", "")), "item": item, "name": str(r.get("name", "")), "effect": str(EFFECTS.get(item, "")),
			"cost": r.get("cost", []).map(func(c): return {"id": str(c.id), "name": str(c.name), "have": int(c.have), "need": int(c.need)}),
			"yield": "", "have": "", "button": {},
		}
		if str(r.get("to", "")) == "bag":
			card.yield = "You get %d" % int(r.get("qty", 1))
			card.have = "You have %d" % int(r.get("have", 0))   # bag + Farm Storage (server, B2-06)
		if r.get("owned", false): card.cost = []   # an owned tool turns its materials row off (BlueprintCard main)
		card.button = _craft_button(r)
		out.append(card)
	return out

static func _craft_button(r: Dictionary) -> Dictionary:
	if r.get("owned", false):
		if str(r.get("to", "")) == "gear":
			if r.get("equipped", false): return {"label": "Equipped", "kind": "done", "cmd": {}}
			return {"label": "Equip", "kind": "secondary", "cmd": {"type": "equip", "item": str(r.get("item", ""))}}
		return {"label": "Owned · always on", "kind": "done", "cmd": {}}   # Gather Gloves (B2-06 GLOVES-DONE)
	var block = r.get("block", null)
	if block == null: return {"label": "Craft", "kind": "primary", "cmd": {"type": "craft", "recipe": str(r.get("id", ""))}}
	var d: Dictionary = block.get("detail", {})
	match str(block.get("code", "")):
		"locked":
			return {"label": "%s Lv%d" % [str(d.get("skill", "")).capitalize(), int(d.get("level", 1))], "kind": "unavailable", "cmd": {}}
		"need_material":
			var short := int(d.get("need", 0)) - int(d.get("have", 0))
			var cost_name := str(d.get("item", ""))
			for c in r.get("cost", []):
				if str(c.id) == cost_name: cost_name = str(c.name)
			return {"label": "Need %d more %s" % [short, cost_name], "kind": "unavailable", "cmd": {}}
		"bag_full":
			return {"label": "No room · free a slot first", "kind": "unavailable", "cmd": {}}
	return {"label": "Craft", "kind": "unavailable", "cmd": {}}
