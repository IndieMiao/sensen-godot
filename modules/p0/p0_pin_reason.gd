extends RefCounted
## Why a map pin wears its mark (q(103), SGODOT-268; style 不知火舞 on 268): the marks the map draws, and the one-line
## reason its card shows under the subtitle — `Pond Catch · Pond Crucian 0/2` (a taken fish request still short),
## `Market Board · 2 requests`, `Pip · New request`, `Pond Catch · Ready to deliver`, `New for you · Reed Rod`,
## `Pip · New chat` (李白 on 268), the strongest one with ` · +N more`. Entering a pond with ! toasts the same line
## (周瑜, P0Pond), so both read it here. Preloaded, no class_name (a new global class needs an editor import).
##
## The marks are the server's view.map_markers (q(48): {place, kind: deliver|request|new, why: {request?, resident?,
## item?, guide?, tracked?}, more?}, one per place, strongest first) whenever it sends them. Without them the client
## knows only the first session's (q(103) ④, the server's rule): while Pond Catch is on the Stall Board and taken, Reed Pond wears
## the ! until the bag holds the fish, then the homestead the ✓; untaken it hangs nowhere (its ! is the stall's own).

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const HOME := "home"
static var REED_POND := P0City.beginner_pond()   # the beginner pond, where the server points Pond Catch too (SGODOT-270)
const STATES := {"deliver": "deliverable", "request": "request", "new": "new"}
const NOUNS := {"fish": "fish", "crop": "crops", "dish": "dishes", "material": "materials", "sow": "plots"}

## The marks the map draws: [{place, kind, why, more?}], strongest first.
static func markers(view: Dictionary) -> Array:
	if not view.has("map_markers"): return fallback(view)
	return (view.get("map_markers", []) as Array).filter(func(m): return m is Dictionary and str(m.get("place", "")) != "")

## The first session's marks without the server's list (q(103) ④): only a taken Pond Catch is marked, and its pond only
## while its fish can be landed at the player's Fishing level (q(104); Pond Crucian is Lv1, so always).
static func fallback(view: Dictionary) -> Array:
	var t := P0Guide.tutorial(view)
	if t.is_empty() or str(t.get("status", "")) != "accepted": return []
	var why := {"request": str(t.get("id", "")), "tracked": true}
	if int(t.get("have", 0)) >= int(t.get("qty", 1)): return [{"place": HOME, "kind": "deliver", "why": why}]
	if P0Logic.fish_level_short(view, [str(t.get("item", ""))], null) > 0: return []
	return [{"place": REED_POND, "kind": "request", "why": why}]

## The reason line for a pin: {state (UiStatusBadge key), text (with ` · +N more`), request, resident, more}; {} when
## the pin wears no mark.
static func reason(view: Dictionary, place: String) -> Dictionary:
	var mine: Array = markers(view).filter(func(m): return str(m.get("place", "")) == place)
	if mine.is_empty(): return {}
	var m: Dictionary = mine[0]
	var state := str(STATES.get(str(m.get("kind", "")), ""))
	if state == "": return {}
	var why: Dictionary = m.get("why", {}) if m.get("why", {}) is Dictionary else {}
	var more := int(m.get("more", 0)) + mine.size() - 1
	var text := line(view, m)
	if more > 0: text += " · +%d more" % more
	return {"state": state, "text": text, "request": str(why.get("request", "")), "resident": str(why.get("resident", "")),
		"more": more}

## One mark's reason, without the ` · +N more`.
static func line(view: Dictionary, m: Dictionary) -> String:
	var why: Dictionary = m.get("why", {}) if m.get("why", {}) is Dictionary else {}
	var r := request_of(view, str(why.get("request", "")))
	var resident := str(why.get("resident", ""))
	if str(why.get("guide", "")) != "": return guide_line(view, str(m.get("place", "")))
	match str(m.get("kind", "")):
		"deliver":
			return "%s · Ready to deliver" % str(r.title) if not r.is_empty() else "Ready to deliver"
		"request":
			if bool(why.get("tracked", false)) and not r.is_empty(): return progress_text(r)
			if resident != "": return "%s · New request" % resident_name(resident)
			var open := market_open(view)
			return "Market Board · %d %s" % [open, "request" if open == 1 else "requests"]
		"new":
			if str(why.get("item", "")) != "": return "New for you · %s" % P0Logic.item_name(view, str(why.item))
			if resident != "": return "%s · New chat" % resident_name(resident)
			return "New for you"
	return ""

## A guide pin's reason (SGODOT-341, 不知火舞 694e8da8): the server's own line for the mark at that place in
## view.guide.marks (`Catch 2 fish · 0/2`, `Nadia · A Fresh Radish`), else the step's Today row (the Homestead's
## `Cook it: Grilled Crucian`, with its count); "" when the guide shows neither, never the Market Board's count.
static func guide_line(view: Dictionary, place: String) -> String:
	for mark in P0Guide.guide_marks(view):
		if mark is Dictionary and str(mark.get("place", "")) == place and str(mark.get("why", "")) != "": return str(mark.why)
	var rows := P0Guide.guide_rows(view)
	if rows.is_empty(): return ""
	var tail := str(rows[0].get("tail", ""))
	return str(rows[0].line) + (" · " + tail if tail != "" else "")

## `Pond Catch · Pond Crucian 0/2`: the request, what it takes and how many the bag holds (the Today row's wording).
static func progress_text(r: Dictionary) -> String:
	return "%s · %s %d/%d" % [str(r.get("title", "")), str(r.get("need_name", "")), int(r.get("have", 0)), int(r.get("qty", 1))]

## A request by id from the Stall Board, a Market Board (the one shown, or another city's tracked one, q(270)) or a
## resident: {id, title, item, need_name, have, qty, ready, tracked, city, deliver (`Deliver at the Stall` / `Deliver at
## Mission Market Square` / `Deliver at Shibuya Market Square · Tokyo` / `Deliver to Pip`)}; {} when gone.
static func request_of(view: Dictionary, id: String) -> Dictionary:
	if id == "": return {}
	for e in board_requests(view):
		var r: Dictionary = e.r
		if str(r.get("id", "")) != id: continue
		var items: Array = r.get("items", [])
		var styles: Array = r.get("style", []) if r.get("style", null) is Array else []
		var at := market_at(view, e.board, e.from)
		return {"id": id, "title": str(r.get("title", "")), "item": str(items[0]) if items.size() == 1 else "",
			"need_name": ("%s dishes" % " or ".join(styles)) if not styles.is_empty() and items.is_empty()
				else _need_name(view, str(r.get("kind", "")), items, r.get("rarity", null)),
			"have": int(r.get("have", 0)), "qty": int(r.get("qty", 1)), "ready": bool(r.get("ready", false)),
			"tracked": str(r.get("status", "")) == "accepted", "city": at.city, "away": at.away, "deliver": at.deliver}
	# The Stall Board as the older view has it (stall.board.requests), for a server without view.boards.
	for r in view.get("stall", {}).get("board", {}).get("requests", []):
		if not (r is Dictionary) or str(r.get("id", "")) != id: continue
		return {"id": id, "title": str(r.get("title", "")), "item": str(r.get("item", "")),
			"need_name": P0Logic.item_name(view, str(r.get("item", ""))), "have": int(r.get("have", 0)),
			"qty": int(r.get("qty", 1)), "ready": int(r.get("have", 0)) >= int(r.get("qty", 1)),
			"tracked": str(r.get("status", "")) == "accepted", "deliver": "Deliver at the Stall"}
	for rid in view.get("residents", {}):
		var rv: Dictionary = view.residents[rid] if view.residents[rid] is Dictionary else {}
		var q = rv.get("request", null)
		if not (q is Dictionary) or str(q.get("id", "")) != id: continue
		var def := P0Logic.resident_request(str(rid), id)
		var need: Dictionary = def.get("need", {})
		var item := str(need.get("id", ""))
		var style := str(need.get("style", ""))
		return {"id": id, "title": str(def.get("title", id)), "item": item,
			"need_name": ("%s dishes" % style) if style != "" and item == ""
				else _need_name(view, str(q.get("kind", need.get("kind", ""))), [item] if item != "" else [], q.get("rarity", null)),
			"have": int(q.get("have", 0)), "qty": int(q.get("qty", 1)), "ready": bool(q.get("ready", false)),
			"tracked": str(rv.get("request_state", "")) == "accepted", "deliver": "Deliver to %s" % resident_name(str(rid))}
	return {}

## Every board request the view holds, with the board it hangs on: [{board: "stall" | "market", from: that board's view
## (another city's tracked request: its own entry, q(270)), r}] — the Stall Board's, the Market Board shown, then the
## requests tracked on other cities' Market Boards (view.boards.elsewhere).
static func board_requests(view: Dictionary) -> Array:
	var out: Array = []
	var boards: Dictionary = view.get("boards", {})
	for board in ["stall", "market"]:
		var b = boards.get(board, {})
		for r in (b.get("slots", []) if b is Dictionary else []):
			if r is Dictionary and not r.get("empty", false): out.append({"board": board, "from": b, "r": r})
	for r in (boards.get("elsewhere", []) if boards.get("elsewhere", null) is Array else []):
		if r is Dictionary: out.append({"board": "market", "from": r, "r": r})
	return out

## Where a board request is handed in (q(270) ⑥): {deliver, go, city ("" at home), away (not the city the player is
## in)} — the Stall, the home set's market square, or another city's Market Square 1 with ` · <City>` (q(128)'s form).
static func market_at(view: Dictionary, board: String, from: Dictionary) -> Dictionary:
	if board == "stall": return {"deliver": "Deliver at the Stall", "go": "stall", "city": "", "away": false}
	if from.is_empty() or bool(from.get("home", true)):
		return {"deliver": "Deliver at %s" % _outpost_name(view, "market"), "go": "outpost:" + P0Outposts.home_id(view, "market"),
			"city": "", "away": from.has("deliver_place") and not is_same(from, view.get("boards", {}).get("market", {}))}
	var city := str(from.get("city", ""))
	var name := str(from.get("deliver_name", ""))
	return {"deliver": "Deliver at %s · %s" % [name if name != "" else "the market", city] if city != "" else "Deliver at %s" % name,
		"go": "outpost:" + str(from.get("deliver_place", "")), "city": city,
		"away": not is_same(from, view.get("boards", {}).get("market", {}))}

## The requests the player has taken (q(104), 李白 4ac4a4e7: they all go to Today): the Stall Board's, the Market
## Board's and the residents', in that order; the first session's Pond Catch is the guide's own row and is left out. Each
## {id, title, kind, items, rarity, need_name, have, qty, ready, deliver, deliver_go} — `deliver` as request_of writes
## it, `deliver_go` the pin it is handed in at (the stall, the market square, the resident's outpost).
static func taken(view: Dictionary) -> Array:
	var out: Array = []
	var boards: Dictionary = view.get("boards", {})
	var stall: Array = []
	if boards.has("stall"): stall = boards.stall.get("slots", [])
	else:   # an older view: stall.board.requests, one item each
		for r in view.get("stall", {}).get("board", {}).get("requests", []):
			if r is Dictionary: stall.append((r as Dictionary).merged({"items": [str(r.get("item", ""))] if str(r.get("item", "")) != "" else []}))
	var rows: Array = stall.map(func(r): return {"board": "stall", "from": {}, "r": r})
	for e in board_requests(view):
		if str(e.board) == "market": rows.append(e)
	for e in rows:
		var r = e.r
		var board := str(e.board)
		if not (r is Dictionary) or r.get("empty", false) or str(r.get("status", "")) != "accepted": continue
		if str(r.get("id", "")) == P0Guide.TUTORIAL: continue
		var at := market_at(view, board, e.from)
		var items: Array = r.get("items", [])
		out.append({"id": str(r.get("id", "")), "title": str(r.get("title", "")), "kind": str(r.get("kind", "fish" if items.any(func(i): return str(i).begins_with("fish_")) else "")),
			"items": items, "rarity": r.get("rarity", null),
			"visit": r.get("visit", null), "where": r.get("where", null),   # cross-city (q(128)): the Today row says where
			"need_name": _need_name(view, str(r.get("kind", "")), items, r.get("rarity", null)),
			"have": int(r.get("have", 0)), "qty": int(r.get("qty", 1)),
			"ready": bool(r.get("ready", int(r.get("have", 0)) >= int(r.get("qty", 1)))),
			"accepted_at": accepted_at(r),   # q(143): when it was tracked (0 on an older server or save)
			"city": at.city, "away": at.away,   # q(270): another city's request names its city; away = not where the player is
			"deliver": at.deliver, "deliver_go": at.go})
	for rid in view.get("residents", {}):
		var rv: Dictionary = view.residents[rid] if view.residents[rid] is Dictionary else {}
		var q = rv.get("request", null)
		if not (q is Dictionary) or str(rv.get("request_state", "")) != "accepted": continue
		var r := request_of(view, str(q.get("id", "")))
		if r.is_empty(): continue
		var def := P0Logic.resident_request(str(rid), str(r.id))
		var need: Dictionary = def.get("need", {})
		out.append(r.merged({"kind": str(q.get("kind", need.get("kind", ""))), "items": [str(r.item)] if str(r.item) != "" else [],
			"rarity": q.get("rarity", need.get("rarity", null)), "deliver_go": "outpost:" + resident_place(rv, str(rid)),
			"accepted_at": accepted_at(q)}))
	return out

## When a taken request was tracked (q(143), the view's `accepted_at`, ms); 0 when the server or the save has none, as
## the earliest.
static func accepted_at(r: Dictionary) -> float:
	var at = r.get("accepted_at", null)
	return float(at) if at != null else 0.0

## Where a resident's request is handed in, for Show on map: the place id the server gives as the resident's `place`
## (q(204), 后裔: home's outpost they live at, Pip's travel post, Ivo's Mine Hut in his own city — `gn-5419384~hut0`);
## an older server without it, or none found, the role of the home set's outpost they live at, as before.
static func resident_place(rv: Dictionary, rid: String) -> String:
	var place = rv.get("place", null)
	if place is String and place != "": return place
	return _resident_role(rid)

## The role of the outpost a resident lives at (p0_outposts.json residents): Old Kai at the Tackle Shop, Pip at the post.
static func _resident_role(rid: String) -> String:
	for o in P0Outposts.all():
		if (o.get("residents", []) as Array).has(rid): return str(o.get("role", ""))
	return ""

## The Market Board's requests nobody has taken yet.
static func market_open(view: Dictionary) -> int:
	var n := 0
	for r in view.get("boards", {}).get("market", {}).get("slots", []):
		if r is Dictionary and not r.get("empty", false) and str(r.get("status", "")) == "open": n += 1
	return n

static func resident_name(id: String) -> String:
	return str(P0Logic.content().get("residents", {}).get(id, {}).get("name", id))

## "Pond Crucian" for a named item, "Common fish" for any fish of a rarity, else the kind's noun.
static func _need_name(view: Dictionary, kind: String, items: Array, rarity) -> String:
	if items.size() == 1: return P0Logic.item_name(view, str(items[0]))
	var noun := str(NOUNS.get(kind, kind))
	if rarity != null and int(rarity) > 0: return "%s %s" % [P0Logic.rarity_name(view, int(rarity)), noun]
	return noun.left(1).to_upper() + noun.substr(1)

## The home set's outpost of a role by name (SGODOT-311: the player's, not the written city's).
static func _outpost_name(view: Dictionary, role: String) -> String:
	return str(P0Outposts.home(view, role).get("name", "the market"))
