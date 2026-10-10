class_name P0Board
extends RefCounted
const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
## The counter drawer's board page (SGODOT-224; BOARD-READY / SHORT / DONE 1498:96193 / 96574 / 96382, E-11; the
## Stall Board uses the same rows): server facts (view.boards[id].slots, view.quotas) as UiBoardCard data and the
## page's fact lines. A request's command follows the frames: ready to hand in → Deliver (taken or not, q(48)); open
## → Track (accept); tracked and short → the gap on the button (LOCK-10).


## The board a counter shows: the Homestead Stall's Stall Board, the market's Market Board.
static func board_id(role: String) -> String:
	return "stall" if role == "homestead" else "market"

## Page facts above the rows: `Requests today 4/6` (both boards share the daily count), `Next request 3h 58m`
## (the soonest empty slot), `Bonus today 20/100` once any bonus has been paid. Counts are x/y, the general rule
## (李白's copy audit 1009 A2). [[label, value], …]
static func facts(view: Dictionary, board: String) -> Array:
	var out: Array = []
	var q: Dictionary = view.get("quotas", {})
	var sys: Dictionary = q.get("sys_requests", {})
	if not sys.is_empty(): out.append(["Requests today", "%d/%d" % [int(sys.get("used", 0)), int(sys.get("cap", 0))]])
	var soonest := -1.0
	for sl in view.get("boards", {}).get(board, {}).get("slots", []):
		if sl.get("empty", false) and sl.has("refill_in"):
			var t := float(sl.refill_in)
			soonest = t if soonest < 0.0 else minf(soonest, t)
	if soonest >= 0.0: out.append(["Next request", P0Logic.span(soonest)])
	var bonus: Dictionary = q.get("request_bonus", {})
	if int(bonus.get("used", 0)) > 0: out.append(["Bonus today", "%d/%d" % [int(bonus.used), int(bonus.get("cap", 0))]])
	return out

## The board's rows in slot order: each request as UiBoardCard data; a slot whose request was delivered while the
## drawer is open shows that row Done (`done`: slot index → the row as it was, from the host).
static func cards(view: Dictionary, board: String, done := {}) -> Array:
	var out: Array = []
	var slots: Array = view.get("boards", {}).get(board, {}).get("slots", [])
	for i in slots.size():
		var sl: Dictionary = slots[i]
		if not sl.get("empty", false): out.append(card(view, sl, i))
		elif done.has(i): out.append((done[i] as Dictionary).merged({status = "Done", done = true, info = false}, true))   # gone: no sheet
	return out

## One request (view.boards[...].slots[i], server requestView) as UiBoardCard data, plus `slot` and `cmd`.
static func card(view: Dictionary, r: Dictionary, slot := 0) -> Dictionary:
	var qty := int(r.get("qty", 1))
	var ready := bool(r.get("ready", false))
	var tracked := str(r.get("status", "")) == "accepted"
	var needs := _needs(view, r)
	var d := {
		id = str(r.get("id", "")), slot = slot, title = str(r.get("title", "")), info = true,
		status = "Ready to deliver" if ready else ("Tracked" if tracked else "Open"),
		facts = [_what(view, r)], reward = reward_line(view, r), needs = needs,
		command = "", reason = "", cmd = {}, done = false,
	}
	if ready:
		d.command = "Deliver"
		d.cmd = {"type": "deliver", "request": d.id}
	elif tracked and _visit_place(r) != "":
		d.command = "Deliver"
		d.reason = "Visit %s first" % _visit_place(r)   # Stamp Run: the check-in is the gap (LOCK-10)
	elif tracked:
		d.command = "Deliver"
		for n in needs:
			if int(n.have) < int(n.need):
				d.reason = "Need %d more %s" % [int(n.need) - int(n.have), str(n.name)]
				break
	else:
		d.command = "Track"
		d.cmd = {"type": "accept", "request": d.id}
	if qty <= 0: d.command = ""
	return d

## The row's coins (李白 on #224): the full amount; once today's completion-bonus cap (§9.13 quota_request_bonus,
## 100) leaves less than the request's bonus, what delivering now actually pays and when the bonus is back —
## `20 coins · Bonus resets in 9h 12m`, `0 coins · …`. Every system request, not only Stamp Run; the button is unchanged.
static func reward_line(view: Dictionary, r: Dictionary) -> String:
	var coins := int(r.get("coins", 0))
	var bonus := int(r.get("bonus", 0))
	var q: Dictionary = view.get("quotas", {}).get("request_bonus", {})
	if q.is_empty() or bonus <= 0: return "%d coins" % coins
	var left := maxi(0, int(q.get("cap", 0)) - int(q.get("used", 0)))
	if left >= bonus: return "%d coins" % coins
	return "%d coins · Bonus resets in %s" % [coins - bonus + left, P0Logic.span(float(q.get("resets_in", 0)))]

## An explore request's outpost by name (Stamp Run, view `visit: {place, done}`); "" for any other request.
static func _visit_place(r: Dictionary) -> String:
	var v = r.get("visit", null)
	if not (v is Dictionary): return ""
	return str(P0Outposts.find(str(v.get("place", ""))).get("name", str(v.get("place", ""))))

## "2 Pond Crucian", "4 Fine fish · any kind", "3 crops · 6 each", "Visit Oak Tea House".
static func _what(view: Dictionary, r: Dictionary) -> String:
	if _visit_place(r) != "": return "Visit %s" % _visit_place(r)
	var items: Array = r.get("items", [])
	var qty := int(r.get("qty", 1))
	var kind := str(r.get("kind", ""))
	if items.size() > 1: return "%d %s · %d each" % [items.size(), _kinds(kind), qty]
	if items.size() == 1: return "%d %s" % [qty, _name(view, str(items[0]), qty)]
	return "%d %s · any kind" % [qty, _any(view, r)]

## One NeedTile per item a request takes (each item's own count in the bag), or one for "any Fine fish".
static func _needs(view: Dictionary, r: Dictionary) -> Array:
	if _visit_place(r) != "":   # a check-in, not items: one tile, done or not
		return [{id = "", name = _visit_place(r), have = 1 if bool(r.visit.get("done", false)) else 0, need = 1, icon = P0Logic.icon("pin")}]
	var items: Array = r.get("items", [])
	var qty := int(r.get("qty", 1))
	var out: Array = []
	if items.size() > 1:
		for id in items:
			out.append({id = str(id), name = P0Logic.item_name(view, str(id)), have = P0Logic.bag_count(view, str(id)), need = qty,
				icon = P0Logic.icon(str(id))})
	else:
		var id := str(items[0]) if items.size() == 1 else str(r.get("icon", ""))
		var any := _any(view, r)
		out.append({id = id, name = P0Logic.item_name(view, id) if items.size() == 1 else any.left(1).to_upper() + any.substr(1),
			have = int(r.get("have", 0)), need = qty, icon = P0Logic.icon(id) if id != "" else null})
	return out

## "Fine fish", "crops", "Common dishes", "Soup dishes", "Grilled or Dessert dishes", "Orchard crops" — what an
## any-of-a-kind request takes (P1 SGODOT-284: a style or a crop family narrows it).
const FAMILY_NAMES := {"W": "Water", "F": "Field", "O": "Orchard", "S": "Seasoning"}

static func _any(view: Dictionary, r: Dictionary) -> String:
	var kind := str(r.get("kind", ""))
	var rarity = r.get("rarity", null)
	var noun := "fish" if kind == "fish" else _kinds(kind)
	var styles: Array = r.get("style", []) if r.get("style", null) is Array else []
	if not styles.is_empty(): noun = "%s %s" % [" or ".join(styles), noun]
	elif r.get("family", null) != null: noun = "%s %s" % [str(FAMILY_NAMES.get(str(r.family), str(r.family))), noun]
	return ("%s %s" % [P0Logic.rarity_name(view, int(rarity)), noun]) if rarity != null and int(rarity) > 0 else noun

static func _kinds(kind: String) -> String:
	return {"fish": "fish", "crop": "crops", "dish": "dishes", "material": "materials"}.get(kind, kind + "s")

static func _name(view: Dictionary, id: String, qty: int) -> String:
	var n := P0Logic.item_name(view, id)
	return P0Logic.plural(n) if qty > 1 and not id.begins_with("fish_") else n

# ---------------------------------------------------------------- one request (BOARD-1 / BOARD-3 / BOARD-DROPPED)

## BOARD-1 482:284 for request `id` on `board`: {title, state, effect, needs, delivery, next ({} or {slot, within}),
## go (where its items come from, for Show / Show on map; "" for none), item (for Details; "" when there is no single
## item), tracked (only a tracked
## request can be dropped; an open one swaps itself after 72 h), noun ("fish", "crops" …)}; {} once it is gone.
static func detail(view: Dictionary, board: String, id: String) -> Dictionary:
	var slots: Array = view.get("boards", {}).get(board, {}).get("slots", [])
	for i in slots.size():
		var r: Dictionary = slots[i]
		if r.get("empty", false) or str(r.get("id", "")) != id: continue
		var c := card(view, r, i)
		var items: Array = r.get("items", [])
		# Details › only for a request of one item: "4 Fine fish · any kind" or a mixed basket has no single item.
		var item := str(items[0]) if items.size() == 1 else ""
		var noun := _noun(view, r)
		# 李白 q(68): the stall's own sentence from BOARD-1; the Market Board takes deliveries at any market of the home
		# city (§9.6.5).
		var where := "the Homestead Stall" if board == "stall" else "any %s market" % P0City.city_name()
		var d := {title = c.title, state = c.status, needs = c.needs, delivery = c.reward, next = {}, item = item,
			tracked = str(r.get("status", "")) == "accepted", noun = noun, go = _go(view, r, str(items[0]) if not items.is_empty() else ""),
			effect = "Bring the required %s to %s." % [noun, where]}
		if _visit_place(r) != "":   # Stamp Run: walk in once, then come back to this board
			d.effect = "Visit %s, then come back to %s." % [_visit_place(r), where]
		for j in slots.size():
			var other: Dictionary = slots[j]
			if j != i and other.get("empty", false) and other.has("refill_in"):
				d.next = {slot = "%s board slot" % ["First", "Second", "Third"][mini(j, 2)], within = P0Logic.span(float(other.refill_in))}
				break
		return d
	return {}

## Where the items of a request come from: the beginner pond for fish (Reed Pond, q(32)), the plots for crops, the
## stove for dishes, a material's own spot.
static func _go(view: Dictionary, r: Dictionary, item: String) -> String:
	if r.get("visit", null) is Dictionary:   # Stamp Run: the outpost's pin, by role as Today's deliver_go
		return "outpost:" + str(P0Outposts.find(str(r.visit.get("place", ""))).get("role", ""))
	match str(r.get("kind", "")):
		"fish": return "pond:" + P0Guide.BEGINNER_POND
		"crop": return "plots"
		"dish": return "stove"
	return str(P0Logic.need_source(view, item).get("go", "")) if item != "" else ""

## What the sentences call the request's items (李白 q(68)): fish / crops / dishes, a material by its own name
## ("timber" for Timber Run).
static func _noun(view: Dictionary, r: Dictionary) -> String:
	var kind := str(r.get("kind", ""))
	var items: Array = r.get("items", [])
	if kind == "material" and items.size() == 1: return P0Logic.item_name(view, str(items[0])).to_lower()
	return {"fish": "fish", "crop": "crops", "dish": "dishes", "material": "materials"}.get(kind, "items")

## The wait after dropping a request (content requests.drop_refill_h, BOARD-3 `Next request after drop 8h`).
static func drop_wait() -> String:
	return "%dh" % int(P0Logic.content().get("requests", {}).get("drop_refill_h", 8))
