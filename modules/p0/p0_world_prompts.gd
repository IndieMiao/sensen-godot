class_name P0WorldPrompts
extends RefCounted
## The farm's world prompts (SGODOT-250; LOCK-07 v2 / LOCK-11 / LOCK-17 v2; copy 李白 q(62); WORLD-HINT-1…5, row 51):
## what each facility's icon button and name strip say. No "Tap to …" anywhere: the strip is icon + name + at most
## one fact; a state (LOCK-11) takes the icon's place on both. The farm decides which facility is open (the nearest
## in reach, P0Garden.pick_card) and which show their button (within RANGE, or any distance with a state).
##
## A prompt is {icon: Texture2D, text, fact, status (UiStatusBadge.State or -1), dimmed, button (false: no icon
## button, only the strip when open — the Upgrade Plaque), count (the button's small tag, "" for none: the Mailbox's
## `Parcel`)}.

## Metres: facilities this close show their icon button (spec 370794d2, engineering default).
const RANGE := 8.0

enum Show { NONE, ICON, BAR }

## The open facility shows its strip; the others their button within RANGE, or from any distance while they carry a
## state or a tag (LOCK-11 marks are unchanged: a stall request or a ready gathering spot shows from across the farm;
## the Mailbox's `Parcel` as far, 不知火舞 on 234).
static func show(id: String, open: String, metres: float, prompt: Dictionary) -> Show:
	if id == open: return Show.BAR
	if not bool(prompt.get("button", true)): return Show.NONE
	if int(prompt.get("status", -1)) >= 0 or str(prompt.get("count", "")) != "" or metres <= RANGE: return Show.ICON
	return Show.NONE

static func _p(icon: String, text: String, fact := "", status := -1, dimmed := false, button := true, count := "") -> Dictionary:
	return {icon = P0Logic.icon(icon), text = text, fact = fact, status = status, dimmed = dimmed, button = button, count = count}

## Homestead Stall: ✓ when a Stall Board request can be handed in, ! when one is open (P0Guide.stall_badge, q(44 / 48)),
## else New while goods unlocked since the last visit wait (STALL-NEW, E-04; `fresh` = P0Ui.stall_has_new()). While the
## new-player guide is on, no state at all, only the plain button (q(215) ⑥: marks are the current step's targets).
static func stall(view: Dictionary, fresh := false) -> Dictionary:
	var board := P0Guide.stall_badge(view)
	var status := -1
	if board == "deliver": status = UiStatusBadge.State.DELIVERABLE
	elif board != "": status = UiStatusBadge.State.REQUEST
	elif fresh and not P0Guide.guide_on(view): status = UiStatusBadge.State.NEW
	return _p("homestead_stall", "Homestead Stall", "", status)

## Farmhouse: the guide's ! while a cookable fish waits for the stove (A-03, P0Guide.door_badge; 不知火舞 on 232).
static func farmhouse(view: Dictionary) -> Dictionary:
	return _p("home", "Farmhouse", "", UiStatusBadge.State.REQUEST if P0Guide.door_badge(view) else -1)

## Homestead sign (WORLD-HINT-5, 228 64c75e54): its own mark i-level-up (a house with an up arrow, 1705:102404 —
## the farmhouse keeps i-home, 不知火舞 on #59), Ready once the Needs are met; open: `Homestead LvN`.
static func sign(view: Dictionary) -> Dictionary:
	var h: Dictionary = view.get("homestead", {})
	var nxt = h.get("next", null)
	var lit: bool = nxt is Dictionary and bool(nxt.get("can_upgrade", false)) and not P0Guide.guide_on(view)
	return _p("level_up", "Homestead Lv%d" % int(h.get("level", 1)), "", UiStatusBadge.State.READY if lit else -1)

## Upgrade Plaque: no mark; only the strip when it is the nearest (PLAQUE-READ).
static func plaque(_view: Dictionary) -> Dictionary:
	return _p("board", "Upgrade Plaque", "", -1, false, false)

## The Chef's Sign (Homestead Lv10; 不知火舞 on 282): its name strip `Chef's Sign`, no fact.
static func chef_sign(_view: Dictionary) -> Dictionary:
	return _p("kitchen", "Chef's Sign", "", -1, false, false)

## The Notice Board (Homestead Lv5, q(164) ①): its name strip `Notice Board`, no fact; a tap opens the board.
static func notice_board(_view: Dictionary) -> Dictionary:
	return _p("board", "Notice Board", "", -1, false, false)

## Rest bench (FARM-7, q(62)): what resting gives now — `+60 Energy`, or less near full (REST-NEARFULL `+25 Energy`).
## Only when it can be used is it the normal strip; otherwise Dimmed with the reason as its one fact (不知火舞 on #59):
## used today `Rested today`; Energy full `Energy full`. No 2 h away countdown since q(269) (SGODOT-377).
static func bench(view: Dictionary) -> Dictionary:
	var st := P0Logic.rest_state(view)
	var amount := int(view.get("rest", {}).get("amount", 60))
	var e: Dictionary = view.get("energy", {})
	var gain := mini(amount, maxi(0, int(e.get("max", 200)) - int(e.get("value", 0))))
	var text := "+%d Energy" % (gain if gain > 0 else amount)
	match str(st.state):
		"used": return _p("rest", "Rested today", "", UiStatusBadge.State.USED_TODAY, true)
		"full": return _p("rest", text, str(st.reason), -1, true)
	return _p("rest", text)

## The farmhouse Mailbox (§12.5.2; SGODOT-234 C, 不知火舞 on 234): the strip says `Mailbox` only; while parcels are in
## the list — the bell's rule: a full bag still counts, the queued ones never (q(79)) — its button wears the small
## `Parcel` tag (the Show count tag, like the Warming Cabinet's 4/6), no new LOCK-11 state. Icon i-mailbox 1822:104445;
## WORLD-HINT-6a 1822:123663 (far, the tag) / 6b 1822:123873 (near, the strip).
static func mailbox(view: Dictionary) -> Dictionary:
	return _p("mailbox", "Mailbox", "", -1, false, true, "" if P0Inbox.parcels(view).is_empty() else "Parcel")

## Workbench (231): name only.
static func workbench() -> Dictionary:
	return _p("workbench", "Workbench")

## The mine mouth (231, 不知火舞 on 235; MINE-P0-1 / P0-5 copy): the plain pickaxe button within RANGE, open:
## `The mine` · `Runs today 0/2` (`1/2` with a run, `2/2` once used up) — with or without an unfinished run (SGODOT-266,
## 不知火舞 on #190: no Run 1/2 badge). Its EntryCard takes the strip's place once tapped and walked up to.
static func mine(view: Dictionary) -> Dictionary:
	var runs: Dictionary = view.get("mine", {}).get("runs", {})
	return _p("pickaxe", "The mine", "Runs today %d/%d" % [int(runs.get("used", 0)), int(runs.get("limit", 2))])

## The mine's facilities (SGODOT-266, copy 李白 q(102) / 不知火舞): tapped like the farm's, so they carry the same icon
## button and strip, labels only — the fee is confirmed on the card at the ladder, never by the tap. A ladder up names
## where it goes, as a door does: floor 1's way out `Farm` (i-door), the ladder below it `Floor 1` (i-ladder). The ladder
## down `Floor 2 · 2 Energy`, only `Floor 2` once paid this run, `Floor 2 · Clear Floor 1 first` while this floor is not
## cleared; the elevator `Elevator`. kind: P0MaterialLogic.mine_facility's ("exit", "up", "stairs", "elevator").
static func mine_facility(view: Dictionary, n: int, kind: String) -> Dictionary:
	match kind:
		"exit": return _p("door", "Farm")
		"up": return _p("ladder", "Floor %d" % (n - 1))
		"elevator": return _p("elevator", "Elevator")
		"stairs":
			var mine: Dictionary = view.get("mine", {})
			var floors: Array = (mine.get("run", {}) if mine.get("run", null) is Dictionary else {}).get("floors", [])
			var here := {}
			var next := {}
			for f in floors:
				if int(f.get("floor", 0)) == n: here = f
				if int(f.get("floor", 0)) == n + 1: next = f
			var name := "Floor %d" % (n + 1)
			if next.get("paid", false): return _p("ladder", name)
			if not here.get("cleared", false): return _p("ladder", name, "Clear Floor %d first" % n)
			return _p("ladder", name, "%d Energy" % int(mine.get("floor_energy", 2)))
	return {}

## A gathering spot from P0MaterialLogic.gather_marks: its first yield's icon; Ready from anywhere; locked (Clay Bank
## before Homestead Lv2) with the level as its fact; cooling down: the time left.
static func spot(view: Dictionary, mark: Dictionary) -> Dictionary:
	var def: Dictionary = P0Logic.content().get("gather", {}).get("spots", {}).get(str(mark.id), {})
	var first: Array = def.get("yield", [[""]])[0] if not def.get("yield", []).is_empty() else [""]
	var icon := str(first[0]) if str(first[0]) != "" else "field"
	match str(mark.badge):
		"ready": return _p(icon, str(mark.name), "", UiStatusBadge.State.READY)
		"locked": return _p(icon, str(mark.name), str(mark.caption).trim_prefix(str(mark.name) + " · "), UiStatusBadge.State.LOCKED)
	return _p(icon, str(mark.name), str(mark.caption).trim_prefix(str(mark.name) + " · "))
