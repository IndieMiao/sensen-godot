class_name P0Inbox
extends RefCounted
## The P0 Inbox's words and rows from the server view (§12.5.2, q(50) / q(79); LOCK-14; SGODOT-234). view.inbox:
## {limit, badge, waiting, claim_slots, parcels: [{key, id, qty, source, left, can_claim, gift?}], updates:
## [{key, id, qty, source, at, status (claimed | expired | returned), coins, read, gift?}]} — updates newest first.
## P0 has no To do (invites, helper asks and Close Friend checks are P2): its page is the empty state.

const TABS := ["todo", "parcels", "updates"]
const TAB_LABELS := ["To do", "Parcels", "Updates"]
## Updates shows only what happened while the player was away (q(79)): claims stay on the server for the double-claim
## check, and anything newer than this build is not drawn.
const SHOWN_UPDATES := ["expired", "returned"]

static func inbox(view: Dictionary) -> Dictionary: return view.get("inbox", {})

static func parcels(view: Dictionary) -> Array: return inbox(view).get("parcels", [])

static func todo_count(_view: Dictionary) -> int: return 0

static func updates(view: Dictionary) -> Array:
	return (inbox(view).get("updates", []) as Array).filter(func(u): return SHOWN_UPDATES.has(str(u.get("status", ""))))

static func unread_updates(view: Dictionary) -> Array:
	return updates(view).filter(func(u): return not bool(u.get("read", false)))

## The bell's number (q(79)): parcels in the list (even when the bag is full) and unread Updates; queued ones never.
static func badge(view: Dictionary) -> int:
	var i := inbox(view)
	return int(i.get("badge", parcels(view).size() + unread_updates(view).size()))

## Which page opens (q(22)): To do with anything to do, else Parcels with any parcel (queued ones too), else Updates.
static func default_tab(view: Dictionary) -> String:
	if todo_count(view) > 0: return "todo"
	if not parcels(view).is_empty() or int(inbox(view).get("waiting", 0)) > 0: return "parcels"
	return "updates"

## Under the title: `3 new · 2 to do`, `2 new`, `Nothing new`.
static func new_line(view: Dictionary) -> String:
	var fresh := parcels(view).size() + unread_updates(view).size()
	var todo := todo_count(view)
	var parts: Array = []
	if fresh > 0: parts.append("%d new" % fresh)
	if todo > 0: parts.append("%d to do" % todo)
	return " · ".join(parts) if not parts.is_empty() else "Nothing new"

static func _free(view: Dictionary) -> int:
	var bag: Dictionary = view.get("bag", {})
	return int(bag.get("free", int(bag.get("capacity", 25)) - (bag.get("slots", []) as Array).size()))

static func _used(view: Dictionary) -> int:
	var bag: Dictionary = view.get("bag", {})
	return int(bag.get("capacity", 25)) - _free(view)

## Parcels page head: `Bag 19/25 · 6 slots free` / `Bag 25/25 · Bag full`.
static func capacity_line(view: Dictionary) -> String:
	var cap := int(view.get("bag", {}).get("capacity", 25))
	var free := _free(view)
	if free <= 0: return "Bag %d/%d · Bag full" % [_used(view), cap]
	return "Bag %d/%d · %d slot%s free" % [_used(view), cap, free, "" if free == 1 else "s"]

## `Parcels 3/8 · Kept 24h · Claim needs a free slot`; with a queue `Parcels 8/8 · 2 more waiting · …` (q(45)).
static func rule_line(view: Dictionary) -> String:
	var i := inbox(view)
	var waiting := int(i.get("waiting", 0))
	var head := "Parcels %d/%d" % [parcels(view).size(), int(i.get("limit", 8))]
	if waiting > 0: head += " · %d more waiting" % waiting
	return head + " · Kept 24h · Claim needs a free slot"

## Under the rows (PARCEL-1 / -3, q(81)): what happens to what is left unclaimed — one fixed line whatever the list
## holds, with no `in 24h` (a resident's gift meal goes back at 4:00; each row says its own time).
const EXPIRY_NOTE := "If not claimed: sellable items turn into coins at 80% · gifts go back · the rest is lost"

static func expiry_note(_view: Dictionary) -> String: return EXPIRY_NOTE

## `42m left` under an hour, `23h 40m left` from one hour, `22h left` on the hour.
static func left_text(ms: float) -> String:
	var minutes := maxi(1, ceili(ms / 60000.0))
	if minutes < 60: return "%dm left" % minutes
	if minutes % 60 == 0: return "%dh left" % (minutes / 60)
	return "%dh %dm left" % [minutes / 60, minutes % 60]

## `Just now`, `12m ago`, `2h ago`, `1d ago`.
static func ago_text(at_ms: float, now_ms: float) -> String:
	var mins := int((now_ms - at_ms) / 60000.0)
	if mins < 1: return "Just now"
	if mins < 60: return "%dm ago" % mins
	if mins < 1440: return "%dh ago" % (mins / 60)
	return "%dd ago" % (mins / 1440)

## InboxRow Kind=Item specs, soonest to go first: {key, icon, title, sub, left, can_claim}.
static func parcel_rows(view: Dictionary) -> Array:
	var rows := parcels(view).duplicate()
	rows.sort_custom(func(a, b) -> bool: return float(a.get("left", 0)) < float(b.get("left", 0)))
	return rows.map(func(p) -> Dictionary:
		return {key = str(p.key), icon = P0Logic.icon(str(p.id)), title = "%s ×%d" % [P0Logic.item_name(view, str(p.id)), int(p.get("qty", 1))],
			sub = str(p.get("source", "")), left = left_text(float(p.get("left", 0))), can_claim = bool(p.get("can_claim", _free(view) > 0))})

## InboxRow Kind=System specs (q(79)), newest first: {key, icon, title, sub, time, unread}.
##   expired, coins > 0   `Parcel expired · +18 coins` / `Perch ×7 · turned into coins at 80%`
##   expired, no coins    `Parcel expired · Worm Bait ×3 lost` / its source
##   returned (a gift)    `Pip's gift meal went back · unclaimed` / the dish ×1
static func update_rows(view: Dictionary, now_ms: float) -> Array:
	return updates(view).map(func(u) -> Dictionary:
		var thing := "%s ×%d" % [P0Logic.item_name(view, str(u.id)), int(u.get("qty", 1))]
		var title := ""
		var sub := ""
		if str(u.status) == "returned":
			var from := str((u.get("gift", {}) if u.get("gift", null) is Dictionary else {}).get("from", "")).strip_edges()
			title = "%s gift meal went back · unclaimed" % (("%s's" % from) if from != "" else "A")
			sub = thing
		elif int(u.get("coins", 0)) > 0:
			title = "Parcel expired · +%d coins" % int(u.coins)
			sub = "%s · turned into coins at 80%%" % thing
		else:
			title = "Parcel expired · %s lost" % thing
			sub = str(u.get("source", ""))
		return {key = str(u.key), icon = P0Logic.icon("parcel"), title = title, sub = sub,
			time = ago_text(float(u.get("at", now_ms)), now_ms), unread = not bool(u.get("read", false))})

## The fixed command under Parcels (PARCEL-1 / -3): `Claim all · 2 slots`, or the grey `Make room · 2 slots` with the
## bag full; {} with nothing to claim. {label, reason, keys}.
static func claim_all(view: Dictionary) -> Dictionary:
	var rows := parcel_rows(view)
	if rows.is_empty(): return {}
	var free := _free(view)
	if free <= 0:
		var n := rows.size()
		return {label = "", reason = "Make room · %d slot%s" % [n, "" if n == 1 else "s"], keys = []}
	var slots := mini(free, rows.size())
	return {label = "Claim all · %d slot%s" % [slots, "" if slots == 1 else "s"], reason = "", keys = rows.map(func(r): return r.key)}
