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
	if bool(prompt.get("always", false)) or int(prompt.get("status", -1)) >= 0 or str(prompt.get("count", "")) != "" or metres <= RANGE: return Show.ICON
	return Show.NONE

static func _p(icon: String, text: String, fact := "", status := -1, dimmed := false, button := true, count := "") -> Dictionary:
	return {icon = P0Logic.icon(icon), text = text, fact = fact, status = status, dimmed = dimmed, button = button, count = count}

## Homestead Stall: ✓ when a Stall Board request can be handed in, ! when one is open (P0Guide.stall_badge, q(44 / 48)),
## else New while goods unlocked since the last visit wait (STALL-NEW, E-04; `fresh` = P0Ui.stall_has_new()). While the
## new-player guide is on, no state at all, only the plain button (q(215) ⑥: marks are the current step's targets).
static func stall(view: Dictionary, fresh := false) -> Dictionary:
	var board := P0Guide.stall_badge(view, true)
	var status := -1
	if board == "deliver": status = UiStatusBadge.State.DELIVERABLE
	elif board != "": status = UiStatusBadge.State.REQUEST
	elif fresh and not P0Guide.guide_on(view): status = UiStatusBadge.State.NEW
	return _p("homestead_stall", "Home Stall", "", status)

## Farmhouse: the guide's ! while a cookable fish waits for the stove (A-03, P0Guide.door_badge; 不知火舞 on 232).
static func farmhouse(view: Dictionary) -> Dictionary:
	return _p("home", "Farmhouse", "", UiStatusBadge.State.REQUEST if P0Guide.door_badge(view) else -1)

## Homestead sign (WORLD-HINT-5, 228 64c75e54): its own mark i-level-up (a house with an up arrow, 1705:102404 —
## the farmhouse keeps i-home, 不知火舞 on #59), Ready once the Needs are met; open: `Homestead LvN`.
static func sign(view: Dictionary) -> Dictionary:
	var h: Dictionary = view.get("homestead", {})
	var nxt = h.get("next", null)
	# While the guide is on the sign is lit only by S7a's mark (v4q(4) ⑥ t_upgrade: `Tap the Homestead sign by the door.`)
	var marked := P0Guide.guide_marks(view).any(func(m): return m is Dictionary and str(m.get("object", "")) == "sign")
	var lit: bool = nxt is Dictionary and bool(nxt.get("can_upgrade", false)) and (not P0Guide.guide_on(view) or marked)
	return _p("level_up", "Home Lv%d" % int(h.get("level", 1)), "", UiStatusBadge.State.READY if lit else -1)

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

## The farm's way out to the map (SGODOT-443, the user 11-07): the rooms' door — i-door, `Map` (SGODOT-250). Its icon
## shows from any distance while on screen (不知火舞's spec v1.1 §3, with q(298): from the spawn it is mostly past RANGE,
## and the sign the user asked for would not be there); its strip opens as any facility's, the nearest.
## `icon`: the farm's exit icon (P0Farm.EXIT_ICON; q(298) the user 11-07: a map pin with a glow ring, 安其拉 drawing it).
static func farm_exit(icon := "door") -> Dictionary:
	var p := _p(icon, "Map")
	p["always"] = true
	return p

## Workbench (231): name only.
static func workbench() -> Dictionary:
	return _p("workbench", "Workbench")

## The mine's facilities (SGODOT-266, copy 李白 q(102) / v4q(5) ⑪, the strips E2 323:181572): tapped like the farm's,
## so they carry the same icon button and strip, labels only — a fee is confirmed on the card at the ladder, never by
## the tap. A ladder names where it goes: Floor 1's way up `Entrance` (out to the map), the others `Floor 12` with
## their fee — `Floor 13 · 2 Energy`, `Floor 13 · Free` once entered today, `Floor 13 · Clear Floor 12 first` while a
## monster stands, `Floor 41 · Not open yet` past the first batch's floors; the elevator `Elevator`.
## kind: P0MaterialLogic.mine_facility's ("exit", "up", "stairs", "elevator").
static func mine_facility(view: Dictionary, n: int, kind: String) -> Dictionary:
	match kind:
		"exit": return _p("ladder", "Entrance")
		"elevator": return _p("elevator", "Elevator")
		"up", "stairs":
			var at := P0MaterialLogic.mine_at(view)
			var s = at.get("next" if kind == "stairs" else "prev", null) if int(at.get("floor", 0)) == n else null
			var to := n + 1 if kind == "stairs" else n - 1
			if s is Dictionary: to = int(s.get("floor", to))
			var name := "Floor %d" % to
			if not (s is Dictionary): return _p("ladder", name)
			if kind == "stairs" and str(s.get("locked", "")) == "not_open": return _p("ladder", name, "Not open yet")
			if kind == "stairs" and not bool(s.get("open", false)): return _p("ladder", name, "Clear Floor %d first" % n)
			if bool(s.get("paid", false)): return _p("ladder", name, "Free")
			return _p("ladder", name, "%d Energy" % int(s.get("fee", view.get("mine", {}).get("floor_energy", 2))))
	return {}
