class_name P0WorldPrompts
extends RefCounted
## The farm's world prompts (SGODOT-250; LOCK-07 v2 / LOCK-11 / LOCK-17 v2; copy 李白 q(62); WORLD-HINT-1…5, row 51):
## what each facility's icon button and name strip say. No "Tap to …" anywhere: the strip is icon + name + at most
## one fact; a state (LOCK-11) takes the icon's place on both. The farm decides which facility is open (the nearest
## in reach, P0Garden.pick_card) and which show their button (within RANGE, or any distance with a state).
##
## A prompt is {icon: Texture2D, text, fact, status (UiStatusBadge.State or -1), dimmed, button (false: no icon
## button, only the strip when open — the Upgrade Plaque)}.

## Metres: facilities this close show their icon button (spec 370794d2, engineering default).
const RANGE := 8.0

enum Show { NONE, ICON, BAR }

## The open facility shows its strip; the others their button within RANGE, or from any distance while they carry a
## state (LOCK-11 marks are unchanged: a stall request or a ready gathering spot shows from across the farm).
static func show(id: String, open: String, metres: float, prompt: Dictionary) -> Show:
	if id == open: return Show.BAR
	if not bool(prompt.get("button", true)): return Show.NONE
	if int(prompt.get("status", -1)) >= 0 or metres <= RANGE: return Show.ICON
	return Show.NONE

static func _p(icon: String, text: String, fact := "", status := -1, dimmed := false, button := true) -> Dictionary:
	return {icon = P0Logic.icon(icon), text = text, fact = fact, status = status, dimmed = dimmed, button = button}

## Homestead Stall: ✓ when a Stall Board request can be handed in, ! when one is open (P0Guide.stall_badge, q(44 / 48)),
## else New while goods unlocked since the last visit wait (STALL-NEW, E-04; `fresh` = P0Ui.stall_has_new()).
static func stall(view: Dictionary, fresh := false) -> Dictionary:
	var board := P0Guide.stall_badge(view)
	var status := -1
	if board == "deliver": status = UiStatusBadge.State.DELIVERABLE
	elif board != "": status = UiStatusBadge.State.REQUEST
	elif fresh: status = UiStatusBadge.State.NEW
	return _p("homestead_stall", "Homestead Stall", "", status)

## Farmhouse: the guide's ! while a cookable fish waits for the stove (A-03, P0Guide.door_badge; 不知火舞 on 232).
static func farmhouse(view: Dictionary) -> Dictionary:
	return _p("home", "Farmhouse", "", UiStatusBadge.State.REQUEST if P0Guide.door_badge(view) else -1)

## Homestead sign (WORLD-HINT-5, 228 64c75e54): its own mark i-level-up (a house with an up arrow, 1705:102404 —
## the farmhouse keeps i-home, 不知火舞 on #59), Ready once the Needs are met; open: `Homestead LvN`.
static func sign(view: Dictionary) -> Dictionary:
	var h: Dictionary = view.get("homestead", {})
	var nxt = h.get("next", null)
	var lit: bool = nxt is Dictionary and bool(nxt.get("can_upgrade", false))
	return _p("level_up", "Homestead Lv%d" % int(h.get("level", 1)), "", UiStatusBadge.State.READY if lit else -1)

## Upgrade Plaque: no mark; only the strip when it is the nearest (PLAQUE-READ).
static func plaque(_view: Dictionary) -> Dictionary:
	return _p("board", "Upgrade Plaque", "", -1, false, false)

## Rest bench (FARM-7, q(62)): what resting gives now — `+60 Energy`, or less near full (REST-NEARFULL `+25 Energy`).
## Only when it can be used is it the normal strip; otherwise Dimmed with the reason as its one fact (不知火舞 on #59):
## used today `Rested today`; not yet (q(41): 2 h away from home first) the Countdown state with `Ready in 1h 12m` /
## `After 2h away`; Energy full `Energy full`.
static func bench(view: Dictionary) -> Dictionary:
	var st := P0Logic.rest_state(view)
	var amount := int(view.get("rest", {}).get("amount", 60))
	var e: Dictionary = view.get("energy", {})
	var gain := mini(amount, maxi(0, int(e.get("max", 200)) - int(e.get("value", 0))))
	var text := "+%d Energy" % (gain if gain > 0 else amount)
	match str(st.state):
		"used": return _p("rest", "Rested today", "", UiStatusBadge.State.USED_TODAY, true)
		"away": return _p("rest", text, str(st.reason), UiStatusBadge.State.COUNTDOWN, true)
		"full": return _p("rest", text, str(st.reason), -1, true)
	return _p("rest", text)

## Workbench (231): name only.
static func workbench() -> Dictionary:
	return _p("workbench", "Workbench")

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
