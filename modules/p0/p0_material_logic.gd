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

## A key's sub "Free" is not shown (q(122): a 0-Energy action shows its verb alone, P0Ui drops it); Free stays only where
## a paid choice sits beside it — the elevator rows and the ladders' strips (LOCK-21, E2 323:181572), not keys.
static func _key(icon: String, verb: String, sub: String, cmd := {}, enabled := true, amber := false, need := 0) -> Dictionary:
	return {"icon": icon, "verb": verb, "sub": sub, "enabled": enabled, "amber": amber, "cmd": cmd, "need": need}

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

## Where the player is in the mine (355 b1, contract-efg §7.1): view.mine.at — the mine, its name and type, the floor,
## HP, the day, the elevator's stops, this floor and the stairs up and down; {} outside a mine.
static func mine_at(view: Dictionary) -> Dictionary:
	var at = view.get("mine", {}).get("at", null)
	return at if at is Dictionary else {}

## Floor n as the view has it (at.floor_state), {} unless the player is on it.
static func _floor(view: Dictionary, n: int) -> Dictionary:
	var at := mine_at(view)
	if at.is_empty() or int(at.get("floor", 0)) != n: return {}
	var f = at.get("floor_state", null)
	return f if f is Dictionary else {}

## The stairs below (at.next) or above (at.prev) floor n: {floor, paid, fee, open?, locked?}, {} for none — the deepest
## floor of a quarry has no way down, Floor 1's way up is the Entrance.
static func _stairs(view: Dictionary, n: int, key: String) -> Dictionary:
	var at := mine_at(view)
	if at.is_empty() or int(at.get("floor", 0)) != n: return {}
	var s = at.get(key, null)
	return s if s is Dictionary else {}

## A monster kind's name (content.mine.monsters: `Iron Slime King`), the id itself if the content lacks it.
static func monster_name(kind: String) -> String:
	return str(P0Logic.content().get("mine", {}).get("monsters", {}).get(kind, {}).get("name", kind))

## The place chip in the mine (E2 323:181423): `Ironvale Vein · Floor 3`.
static func mine_place(view: Dictionary) -> String:
	var at := mine_at(view)
	if at.is_empty(): return ""
	return "%s · Floor %d" % [str(at.get("name", "")), int(at.get("floor", 1))]

# --- Inside the mine ---

## Main action key in the mine: Mining itself only (SGODOT-266, user on 263 ③). ctx: {floor: int, target: "rock" | "",
## rock: int, item: String} where item is the quick-bar selection ("torch" or ""). Rocks never respond to taps (LOCK-02);
## the ladders and the elevator are tapped like any facility (mine_facility), so the key never names them. Rocks are
## the player's choice (355 b1: the stairs open on the monsters, not the rocks); a full bag greys them alone,
## `Mine · Bag full` (v4q(5) ⑫, q(48)).
## A 0-Energy move shows its verb alone (`Light Torch`, q(122); was `Light Torch · Free`, q(46)).
static func mine_action(view: Dictionary, ctx: Dictionary) -> Dictionary:
	return _with_pick(view, _mine_action(view, ctx))

static func _mine_action(view: Dictionary, ctx: Dictionary) -> Dictionary:
	var mine: Dictionary = view.get("mine", {})
	var n := int(ctx.get("floor", 1))
	var floor := _floor(view, n)
	if floor.is_empty(): return _key("pickaxe", "Mine", "", {}, false)
	if int(floor.get("rocks", 0)) == 0: return _key("pickaxe", "Mine", "No rocks here", {}, false)   # a guard's floor
	if str(ctx.get("item", "")) == "torch":
		if floor.get("lit", false): return _key("torch", "Light Torch", "Lit", {}, false)
		return _key("torch", "Light Torch", "Free", {"type": "mine_torch", "floor": n})
	if int(floor.get("left", 0)) == 0: return _key("pickaxe", "Mine", "No rocks here", {}, false)   # q(62), 不知火舞 on 355
	if str(ctx.get("target", "")) == "rock":
		var rock := int(ctx.get("rock", -1))
		var broken: Array = floor.get("broken", [])
		var cost := int(mine.get("rock_energy", 2))
		if rock < 0 or rock >= broken.size() or bool(broken[rock]): return _key("pickaxe", "Mine", "Walk to a rock", {}, false)
		if not floor.get("bag_ok", true): return _unavailable("pickaxe", "Mine", "Bag full", BAG_FULL)
		if _energy(view) < cost: return _key("pickaxe", "Mine", "Need %d Energy" % cost, {"type": "energy_card"}, true, true, cost)
		return _key("pickaxe", "Mine", "%d Energy" % cost, {"type": "mine_rock", "floor": n, "rock": rock}, true, false, cost)
	return _key("pickaxe", "Mine", "Walk to a rock", {}, false)

## Combat's main action key (§13.3.8, COMBAT-1): `Attack`, 0 Energy and no sub-line, the sword's badge; a swing with
## nothing in reach still swings (the old mine's). ctx {floor}.
static func combat_action(view: Dictionary, ctx: Dictionary) -> Dictionary:
	var n := int(ctx.get("floor", 1))
	var k := _key("sword", "Attack", "", {"type": "mine_swing", "floor": n}, not _floor(view, n).is_empty())
	k["tool"] = "sword"
	return k

## The switch key's actions in the mine: Mining and Combat on every floor (355 b1: monsters from Floor 1 on; the radial
## E2 325:181641).
static func mine_actions() -> Array:
	return ["mine", "combat"]

## The main key's mode on landing on a floor (李元芳 R5 on 288): Combat while a monster of this floor is up, Mining
## otherwise. Only on arrival — the player's own pick on the radial stays until the next floor.
static func landing_mode(view: Dictionary, n: int) -> String:
	return "combat" if mobs_up(view, n) > 0 else "mine"

## Monsters of floor n still standing.
static func mobs_up(view: Dictionary, n: int) -> int:
	return (_floor(view, n).get("mobs", []) as Array).filter(func(m): return int(m.get("hp", 0)) > 0).size()

## The guard fighting on floor n for its HUD card (E5 329:182739, UiHpBar ELITE under the player's): {name, hp, max}
## once it has been hit — before that the status line names it (不知火舞 on 355) —, {} when there is none, it is down or
## still untouched. Elites have no card (contract-efg §7.4: the guard's only).
static func guard_card(view: Dictionary, n: int) -> Dictionary:
	for m in _floor(view, n).get("mobs", []):
		var hp := int(m.get("hp", 0))
		if bool(m.get("guard", false)) and hp > 0 and hp < int(m.get("max", hp)):
			return {"name": monster_name(str(m.get("kind", ""))), "hp": hp, "max": int(m.max)}
	return {}

## The status line under the HUD in the mine (MINE-1 / P0-2; 不知火舞 on 355): the rocks broken and the monsters still
## standing — `Rocks 2/6 · 3 monsters left` (`1 monster left`; elites count, every kind alike), `Rocks 2/6` once they are
## down, the monsters alone on a floor without rocks; a guard not yet hit by its name (`Iron Slime King`) — once hit,
## its card covers the line (P0Ui.set_hp). "" off the floor.
static func mine_status(view: Dictionary, n: int) -> String:
	var floor := _floor(view, n)
	if floor.is_empty(): return ""
	var parts: Array = []
	var rocks := int(floor.get("rocks", 0))
	if rocks > 0: parts.append("Rocks %d/%d" % [rocks - int(floor.get("left", rocks)), rocks])
	var up: Array = (floor.get("mobs", []) as Array).filter(func(m): return int(m.get("hp", 0)) > 0)
	var guard: Array = up.filter(func(m): return bool(m.get("guard", false)))
	if not guard.is_empty(): parts.append(monster_name(str(guard[0].get("kind", ""))))
	elif not up.is_empty(): parts.append("%d monster%s left" % [up.size(), "" if up.size() == 1 else "s"])
	return " · ".join(parts)

## The mine's facilities, tapped and walked to (SGODOT-266; 不知火舞's spec 2e580bed, LOCK-21): kind "exit" (Floor 1's
## way up, the Entrance), "up", "stairs" (down) and "elevator" (Floor 1 and the stops). What arriving does:
## {card: false, cmd} goes at once — leaving, a floor paid today, the elevator's panel; {card: true, label, enabled,
## amber, cmd, need, verb, toast} shows the EntryCard over the ladder with the fee button (`Floor 13 · 2 Energy`): amber
## `Need 2 Energy` opens the Energy card, grey says why (LOCK-10) — `Floor 13 · Clear Floor 12 first` while a monster
## stands (355 b1: the stairs open on the monsters), `Floor 41 · Not open yet` past the first batch's floors.
## Moves carry `to` and `via` (contract-efg §6); the scene adds the day.
static func mine_facility(view: Dictionary, n: int, kind: String) -> Dictionary:
	match kind:
		"elevator": return {"card": false, "cmd": {"type": "elevator"}}
		"exit": return {"card": false, "cmd": {"type": "mine_exit"}}
		"up", "stairs":
			var down := kind == "stairs"
			var s := _stairs(view, n, "next" if down else "prev")
			if s.is_empty():   # no way down (a quarry's last floor); a view without `prev` (contract-efg v0.7) goes up as a free move
				return {"card": false, "cmd": {} if down or n <= 1 or _floor(view, n).is_empty() else {"type": "mine_floor", "to": n - 1, "via": "ladder"}}
			var to := int(s.get("floor", n + 1 if down else n - 1))
			var verb := "Floor %d" % to
			var move := {"type": "mine_floor", "to": to, "via": "ladder"}
			if down and str(s.get("locked", "")) == "not_open": return _fee_card("%s · Not open yet" % verb)
			if down and not bool(s.get("open", false)): return _fee_card("%s · Clear Floor %d first" % [verb, n])
			if bool(s.get("paid", false)): return {"card": false, "cmd": move}
			var fee := int(s.get("fee", view.get("mine", {}).get("floor_energy", 2)))
			if _energy(view) < fee:
				return {"card": true, "label": "%s · Need %d Energy" % [verb, fee], "enabled": true, "amber": true,
					"cmd": {"type": "energy_card"}, "need": fee, "verb": verb}
			return {"card": true, "label": "%s · %d Energy" % [verb, fee], "enabled": true, "amber": false,
				"cmd": move, "need": fee, "verb": verb}
	return {"card": false, "cmd": {}}

## A grey fee button: its label is the reason, and a press toasts exactly that line (不知火舞 on 266, 5181bba0).
static func _fee_card(label: String) -> Dictionary:
	return {"card": true, "label": label, "enabled": false, "amber": false, "cmd": {}, "toast": label}

## Whether floor n has the elevator: Floor 1 and every stop (contract-efg §4 ⑤; F1 is no stop, the machine is there).
static func has_elevator(view: Dictionary, n: int) -> bool:
	return n == 1 or bool(_floor(view, n).get("station", false))

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

## The elevator panel's header (E3 326:181733, v4q(5) ⑪): `Elevator · Ironvale Vein`.
static func elevator_title(view: Dictionary) -> String:
	return "Elevator · %s" % str(mine_at(view).get("name", ""))

## Elevator rows (E3 326:181733, v4q(5) ⑪): the Entrance first (leaving: back to the map at this mine's mouth), then
## each stop of this mine — every 10th floor down to the deepest reached (contract-efg §4 ⑤, F1 is none). here: the
## floor the player is on. Each row {name, state, kind, label, enabled, amber, cmd}: the panel draws name left and state
## right (`Floor 20` · `2 Energy`); label is the joined line. kind is the ElevatorRow state (LOCK-21): "here", "free",
## "cost" (a stop not paid today), "short" (Need 2 Energy). cmd type "mine_leave", "mine_floor" {to, via} or
## "energy_card".
static func elevator_rows(view: Dictionary, here: int) -> Array:
	var rows: Array = []
	for r in _elevator_rows(view, here):
		var parts := str(r.label).split(" · ", true, 1)
		r["name"] = parts[0]
		r["state"] = parts[1] if parts.size() > 1 else ""
		if r.state == "Here": r["kind"] = "here"
		elif r.state == "Free": r["kind"] = "free"
		elif r.amber: r["kind"] = "short"
		elif r.enabled: r["kind"] = "cost"
		else: r["kind"] = "locked"
		rows.append(r)
	return rows

static func _elevator_rows(view: Dictionary, here: int) -> Array:
	var at := mine_at(view)
	var fee := int(view.get("mine", {}).get("floor_energy", 2))
	var rows: Array = [{"label": "Entrance · Free", "enabled": true, "amber": false, "cmd": {"type": "mine_leave"}}]
	for st in at.get("stations", []):
		var n := int(st.get("floor", 0))
		var move := {"type": "mine_floor", "to": n, "via": "elevator"}
		if n == here: rows.append({"label": "Floor %d · Here" % n, "enabled": false, "amber": false, "cmd": {}})
		elif bool(st.get("paid", false)): rows.append({"label": "Floor %d · Free" % n, "enabled": true, "amber": false, "cmd": move})
		elif _energy(view) < fee: rows.append({"label": "Floor %d · Need %d Energy" % [n, fee], "enabled": true, "amber": true,
			"cmd": {"type": "energy_card", "need": fee, "verb": "Floor %d" % n}})
		else: rows.append({"label": "Floor %d · %d Energy" % [n, fee], "enabled": true, "amber": false, "cmd": move})
	return rows

## What each rock of floor n shows: gone, or greyed by a full bag (the whole floor, `Mine · Bag full`). The torch lights
## the floor's deck, not each rock (v4q(5) ⑫: torch_toast), so no rock carries a preview any more.
static func rock_marks(view: Dictionary, n: int) -> Array:
	var floor := _floor(view, n)
	var out: Array = []
	for b in floor.get("broken", []): out.append({"broken": bool(b), "grey": not floor.get("bag_ok", true)})
	return out

## The torch's Info toast (v4q(5) ⑪ ⑫): what the floor's rocks still hold, in one line — `Floor 12 · Copper Ore ×2 ·
## Iron Ore ×1` (the scene breaks it after a ` · ` when long); `Floor 12 · Stone only` when no card holds more than
## Stone. "" before the torch is lit.
static func torch_toast(view: Dictionary, n: int) -> String:
	var deck = _floor(view, n).get("deck", null)
	if not (deck is Array): return ""
	var parts: Array = ["Floor %d" % n]
	for d in deck: parts.append("%s ×%d" % [P0Logic.item_name(view, str(d[0])), int(d[1])])
	if parts.size() == 1: parts.append("Stone only")
	return " · ".join(parts)

## A new day while inside (v4q(5) ⑥ ⑪): the floor is drawn again and the player stays — the Info toast.
static func new_day_toast(n: int) -> String:
	return "New day · Floor %d has changed" % n

## The first fall of a guard kind (E5 329:182895): `First kill · Iron Slime King`, a result float.
static func first_kill_float(kind: String) -> Dictionary:
	var text := "First kill · %s" % monster_name(kind)
	return {kind = "result", key = text, text = text, tone = UiFloatText.Tone.ITEM}

## A drop the bag had no room for lies on the floor (v4q(5) ⑫): `Bag full · Iron Ore left on the floor`.
static func ground_float(view: Dictionary, item: String) -> Dictionary:
	var text := "Bag full · %s left on the floor" % P0Logic.item_name(view, item)
	return {kind = "result", key = text, text = text, tone = UiFloatText.Tone.ITEM}

## The floor fee's float (q(46), the Energy line of the reply's three, q(49) ①): `Floor 12 · −2 Energy` from a reply's
## mine_floor event and its Energy spent for it (reason mine_floor); "" for a free move.
static func floor_fee_line(events: Array) -> String:
	var spent := 0
	var floor := 0
	for e in events:
		match str(e.get("kind", "")):
			"energy": if str(e.get("reason", "")) == "mine_floor": spent -= int(e.get("delta", 0))
			"mine_floor": floor = int(e.get("floor", 0))
	return "Floor %d · −%d Energy" % [floor, spent] if spent > 0 and floor > 0 else ""

## The knock-out card (E6 328:182082 / 328:182298, v4q(5) ⑪) over the mine's mouth card on the map: {title, lines,
## lost, best, button}. lost [[item, qty]…] from the mine_ko event: from Floor 11 on, half of what this floor gave;
## on Floors 1–10 nothing. best: this mine's deepest (records), which a fall never lowers.
static func ko_card(view: Dictionary, mine: String, floor: int, lost: Array) -> Dictionary:
	var best := int(view.get("mine", {}).get("records", {}).get(mine, {}).get("deepest", floor))
	var keep_from := int(P0Logic.content().get("mine", {}).get("combat", {}).get("ko_keep_from", 11))
	var dropped := floor >= keep_from and not lost.is_empty()
	return {"title": "Knocked out", "lines": ["You're back at the entrance.",
		"You dropped half of what you found on this floor:" if dropped else "You kept everything."],
		"lost": lost.map(func(l): return {"item": str(l[0]), "text": "%s ×%d" % [P0Logic.item_name(view, str(l[0])), int(l[1])]}) if dropped else [],
		"best": "Your best here is still Floor %d." % best, "button": "Close"}

## What a server refusal of a material command says (苏烈's #39 review). null: not ours, the runtime's own wording
## applies (need_energy opens the Energy card). "": quiet — a race the next frame shows anyway (a held repeat hitting
## the 0.9 s tempo, a rock another press already broke, a torch already lit, a swing racing a kill, an item on the floor
## someone already picked up) or a new day's state the reply already carries (new_day: the scene rebuilds the floor
## without an error, v4q(5) ⑥, contract-efg §5 ⑩). Else a toast.
static func refusal_text(code: String, detail: Dictionary, cmd: Dictionary) -> Variant:
	var type := str(cmd.get("type", ""))
	if not (type.begins_with("mine_") or type == "gather"): return null
	match code:
		"tempo", "rock_gone", "lit", "not_in_mine", "stale_state", "bad_spot", "mob_gone", "bad_target", "bad_rock", "new_day":
			return ""
		"bad_floor":   # past the first batch's floors (F41 of a vein); any other bad floor is a race the view settles
			return "Floor %d · Not open yet" % int(cmd.get("to", 0)) if bool(detail.get("not_open", false)) else ""
		"floor_locked":   # the stairs open once this floor's monsters are down (355 b1)
			return "Floor %d · Clear Floor %d first" % [int(cmd.get("to", 1)), int(cmd.get("to", 1)) - 1]
		"no_item":   # a torch gone meanwhile; a drop on the floor already picked up is a race
			return "No torches" if str(detail.get("item", "")) == "torch" else ""
		"no_rocks":
			return "No rocks here"
		"bag_full":   # what lies on the floor stays there (v4q(5) ⑫): its float said so when it fell
			if type == "mine_pick": return ""
			return BAG_FULL if type.begins_with("mine_") else "Bag full · free a slot first"
		"not_open":   # a mine's type not open yet, or a vein before its Homestead level (v4 2.7)
			return "Homestead Lv%d" % int(detail.homestead) if detail.has("homestead") else "Not open yet"
		"homestead_level":
			return "Homestead Lv%d" % int(detail.get("need", 2))
		"not_ready":
			return "Ready in %s" % P0Logic.span(float(detail.get("ready_in", 0)))
	return null

## The Energy card's verb for a refused material command ("Mine", "Enter mine", "Floor 13"); `fallback` for others.
static func energy_verb(cmd: Dictionary, fallback: String) -> String:
	match str(cmd.get("type", "")):
		"mine_rock": return "Mine"
		"mine_enter": return "Enter mine"
		"mine_floor": return "Floor %d" % int(cmd.get("to", 2))
	return fallback

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
			mark.caption = "%s · Ready in %s" % [name, P0Logic.span(float(sp.get("ready_in", 0)))]
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
	return "%s · Ready in %s" % [str(best.get("name", "")), P0Logic.span(float(best.get("ready_in", 0)))]

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
## yet comes last with its gate, `Clay · Quarry · or Clay Bank from Homestead Lv2`, and loses only the gate once
## open, `Clay · Quarry · or Clay Bank`. Order: spots open from the start, then the mine types that yield it (355 b1:
## a quarry's mains, a vein's; every rock gives Stone: `Stone · Rock Pile · or the mine`), then spots a Homestead level
## opens; still-locked ones last.
## `go` (Show, 不知火舞 on 228): the first open source ("spot_grove", "mine"); with none open, the first source (its
## name strip says the gate). {} for anything that is not a material (content.materials) or that nothing yields.
## Two lines at most (不知火舞 on 228): the label may break only before ` · or `, so every other space is a no-break
## space — `Clay · Quarry` / `· or Clay Bank from Homestead Lv2`.
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
	var mines := mine_types_yielding(id)
	if id == "stone": first.append({"name": "the mine", "go": "mine", "gate": 1, "open": true})   # every rock gives Stone (Li Bai on 228)
	else:
		for t in mines: first.append({"name": str(t.word), "go": "mine", "gate": 1, "open": true})
	var all: Array = first + gated
	if all.is_empty(): return {}
	var ordered: Array = all.filter(func(s): return s.open) + all.filter(func(s): return not s.open)
	var parts: Array = ordered.map(func(s): return s.name if s.open else "%s from Homestead Lv%d" % [s.name, s.gate])
	var text := _nowrap("%s · %s" % [P0Logic.item_name(view, id), parts[0]])
	for i in range(1, parts.size()): text += " " + _nowrap("· or %s" % parts[i])   # the only breakable space
	return {"text": text, "go": str(ordered[0].go)}

## The open mine types that yield a material as a main (355 b1): world_gen's wild.mines[type].mains, for the types the
## mine content opens (content.mine.types: quarry and vein in the first batch), in that order — [{type, word}], the
## word the map names them by (`Quarry`, `Vein`). Stone comes from every rock; callers say `the mine` for it.
static func mine_types_yielding(id: String) -> Array:
	var c := P0Logic.content()
	var wild: Dictionary = c.get("world", {}).get("wild", {})
	var out: Array = []
	for t in c.get("mine", {}).get("types", {}):
		if (wild.get("mines", {}).get(t, {}).get("mains", []) as Array).has(id):
			out.append({"type": str(t), "word": str(wild.get("type_words", {}).get(t, str(t).capitalize()))})
	return out

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
	"facility_sprinkler": "Waters 8 plots for you",   # P1 FARM-5 v5 (q(59) §5)
	"facility_greenhouse": "Any seed grows inside",     # FARM-5 (不知火舞 on 241 e3141c25; `16 plots · −25%` is the status card's)
	"facility_compost_bin": "5 crops → 5 Compost a day",   # q(118) ③ (不知火舞 on 241, FARM-5-FAC 2109:133018)
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
		# a facility paid in coins too (the greenhouse's 300): a Coins tile after the materials, the 40 floor in its
		# denominator so the tile and the button agree (q(10): `Coins 230/340`)
		elif r.get("coins_need", null) != null:
			card.cost.append({"id": "coin", "name": "Coins", "have": int(r.get("coins_have", 0)), "need": int(r.coins_need)})
		card.button = _craft_button(r)
		# a facility that can be built says how many stand of how many may, left of Build (FARM-5-FAC: `Sprinklers 2/6`;
		# 不知火舞 B7 286 6e15f758); at the cap its grey key says it instead (q(130) ①)
		if str(r.get("to", "")) == "field" and r.get("block", null) == null and r.has("cap"):
			card.have = "%ss %d/%d" % [str(r.get("name", "")), int(r.get("used", 0)), int(r.get("cap", 0))]
		# a facility says its level first, locked or not (FARM-5-FAC 2109:133018: `Farming Lv6 · Waters 8 plots for you`,
		# `Farming Lv7 · 5 crops → 5 Compost a day`; 不知火舞 on 241 ba9359df)
		var gate = r.get("gate", null)
		if str(r.get("to", "")) == "field" and gate is Dictionary:
			card.effect = "%s Lv%d · %s" % [str(gate.get("skill", "")).capitalize(), int(gate.get("level", 1)), card.effect]
		out.append(card)
	return out

static func _craft_button(r: Dictionary) -> Dictionary:
	if r.get("owned", false):
		if str(r.get("to", "")) == "gear":
			if r.get("equipped", false): return {"label": "Equipped", "kind": "done", "cmd": {}}
			return {"label": "Equip", "kind": "secondary", "cmd": {"type": "equip", "item": str(r.get("item", ""))}}
		return {"label": "Owned · always on", "kind": "done", "cmd": {}}   # Gather Gloves (B2-06 GLOVES-DONE)
	var block = r.get("block", null)
	# P1 Facilities (SGODOT-241): Build opens placement mode (place_start, handled by the world); the place command is
	# sent from there, with the plot.
	var field := str(r.get("to", "")) == "field"
	if block == null:
		if field: return {"label": "Build", "kind": "primary", "cmd": {"type": "place_start", "recipe": str(r.get("id", ""))}}
		return {"label": "Craft", "kind": "primary", "cmd": {"type": "craft", "recipe": str(r.get("id", ""))}}
	var d: Dictionary = block.get("detail", {})
	match str(block.get("code", "")):
		"locked":
			return {"label": "%s Lv%d" % [str(d.get("skill", "")).capitalize(), int(d.get("level", 1))], "kind": "unavailable", "cmd": {}}
		"skill_level_required":   # q(59) §5: `Farming Lv6 needed`
			return {"label": "%s Lv%d needed" % [str(d.get("skill", "")).capitalize(), int(d.get("level", 1))], "kind": "unavailable", "cmd": {}}
		"facility_cap":   # q(130) ①: the grey key only counts, `Sprinklers 6/6`; a tap's Info toast says what adds one,
			# `Sprinklers 6/6 · Homestead Lv4 adds 1` / `Greenhouses 1/1 · Farming Lv10 adds 1`; at the top both only count
			var label := "%ss %d/%d" % [str(r.get("name", "")), int(d.get("used", 0)), int(d.get("cap", 0))]
			var toast := label
			if d.get("homestead_next", null) != null: toast += " · Homestead Lv%d adds 1" % int(d.homestead_next)
			if d.get("farming_next", null) != null: toast += " · Farming Lv%d adds 1" % int(d.farming_next)
			return {"label": label, "kind": "unavailable", "cmd": {}, "toast": toast}
		"no_coins":   # LOCK-10 (the greenhouse's 300 coins with the 40 floor)
			return {"label": "Need %d more coins" % int(d.get("need", 0)), "kind": "unavailable", "cmd": {}}
		"need_material", "missing_materials":
			var short := int(d.get("need", 0)) - int(d.get("have", 0))
			var cost_name := str(d.get("item", ""))
			for c in r.get("cost", []):
				if str(c.id) == cost_name: cost_name = str(c.name)
			return {"label": "Need %d more %s" % [short, cost_name], "kind": "unavailable", "cmd": {}}
		"bag_full":
			return {"label": "No room · free a slot first", "kind": "unavailable", "cmd": {}}
	return {"label": "Build" if field else "Craft", "kind": "unavailable", "cmd": {}}
