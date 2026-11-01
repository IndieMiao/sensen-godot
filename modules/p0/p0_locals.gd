extends RefCounted
## q(272) (SGODOT-378, cross-city plan H step 2): the keepers' local requests away from home, as view.locals gives them
## — today's in the city the player is in and the tracked ones elsewhere, each a board request with its keeper (place,
## giver, giver_role), cluster, city and `here`. The greeting card's one key (不知火舞 378 091a3ae9: Deliver > Request >
## the gap), the card's copy (who, the keeper's line, Deliver to), the name tag's mark and the order a keeper's
## requests page through (77524b0e). Preloaded, no class_name (a new global class needs an editor import).

## The server's content fragment (requests_local.json): the lines a keeper says by role.
static func _lines() -> Dictionary:
	return P0Logic.content().get("requests", {}).get("local", {}).get("lines", {})

## Every local request the view holds.
static func all(view: Dictionary) -> Array:
	var out: Array = []
	for r in (view.get("locals", []) if view.get("locals", null) is Array else []):
		if r is Dictionary: out.append(r)
	return out

## One by id; {} when gone.
static func find(view: Dictionary, id: String) -> Dictionary:
	for r in all(view):
		if str(r.get("id", "")) == id: return r
	return {}

static func is_local(id: String) -> bool:
	return id.begins_with("req_loc_")

## What a request stands at for its keeper's key and the card's order: 0 ready to hand in, 1 not taken yet, 2 taken and
## still short (the gap).
static func stage(r: Dictionary) -> int:
	if str(r.get("status", "")) == "accepted": return 0 if bool(r.get("ready", false)) else 2
	return 1

## The keeper's requests in the city the player is in, in the key's order (Deliver > Request > the gap); the cards page
## through them in this order.
static func of_keeper(view: Dictionary, place: String) -> Array:
	var mine: Array = all(view).filter(func(r): return bool(r.get("here", false)) and str(r.get("place", "")) == place)
	mine.sort_custom(func(a, b): return stage(a) < stage(b))
	return mine

## The greeting card's key under Trade (091a3ae9 ①): {} when this keeper has none for the player (home, all handed in or
## dropped) — no key, no placeholder; else {id, text, reason, kind: "deliver" | "request" | "gap"}: `Deliver` hands in at
## once, `Request` opens the card, the gap opens it too — a grey Deliver whose reason the button shows, as a resident's
## (`Need 2 more Pond Crucian`, LOCK-10; `Need 12 more` where that does not fit).
const KEY_CHARS := 28
static func key(view: Dictionary, place: String) -> Dictionary:
	var mine := of_keeper(view, place)
	if mine.is_empty(): return {}
	var r: Dictionary = mine[0]
	match stage(r):
		0: return {"id": str(r.id), "text": "Deliver", "reason": "", "kind": "deliver"}
		1: return {"id": str(r.id), "text": "Request", "reason": "", "kind": "request"}
	var gap := gap_text(view, r)
	if gap.length() > KEY_CHARS: gap = "Need %d more" % maxi(0, int(r.get("qty", 0)) - int(r.get("have", 0)))
	return {"id": str(r.id), "text": "Deliver", "reason": gap, "kind": "gap"}

## What a tracked one still needs, as a resident's button says it (P0Logic._request_gap).
static func gap_text(view: Dictionary, r: Dictionary) -> String:
	var items: Array = r.get("items", [])
	var styles: Array = r.get("style", []) if r.get("style", null) is Array else []
	return P0Logic._request_gap(view, {"qty": r.get("qty", 0), "have": r.get("have", 0), "kind": r.get("kind", ""),
		"item": str(items[0]) if items.size() == 1 else null, "style": str(styles[0]) if styles.size() == 1 else null,
		"rarity": r.get("rarity", null)})

## The keeper's name tag mark in the outpost (091a3ae9 ①): "deliverable" for one ready, else "request" for one not taken
## yet, else "" — ✓ first.
static func badge(view: Dictionary, place: String) -> String:
	var mine := of_keeper(view, place)
	if mine.is_empty(): return ""
	match stage(mine[0]):
		0: return "deliverable"
		1: return "request"
	return ""

## The card's requester line (091a3ae9 ②): `Wen · Tackle Keeper · local request`, as a resident's `… · personal request`.
static func who(r: Dictionary) -> String:
	var role := str(r.get("giver_role", ""))
	return "%s · %s · local request" % [str(r.get("giver", "")), role] if role != "" else "%s · local request" % str(r.get("giver", ""))

## The keeper's line on the card (q(272) ⑨): one of their role's, fixed by the request's id; an S-tier cabin keeper
## speaks for the kind asked (fish → the tackle shop's). {city} and {outpost} filled in.
const KIND_ROLE := {"fish": "tackle", "dish": "tea", "crop": "market", "material": "post"}
static func line(r: Dictionary) -> String:
	var role := str(KIND_ROLE.get(str(r.get("kind", "")), "post"))
	var lines: Array = _lines().get(role, [])
	if lines.is_empty(): return ""
	var text := str(lines[absi(str(r.get("id", "")).hash()) % lines.size()])
	return text.replace("{city}", str(r.get("city", ""))).replace("{outpost}", outpost_name(r))

static func outpost_name(r: Dictionary) -> String:
	return str(P0Outposts.find(str(r.get("place", ""))).get("name", ""))

## Deliver to (091a3ae9 ②): `Wen · Xuhui Tackle Shop` in that city; away (opened from Today) ` · Shanghai` after it.
static func deliver_to(r: Dictionary) -> String:
	var where := outpost_name(r)
	var out := "%s · %s" % [str(r.get("giver", "")), where] if where != "" else str(r.get("giver", ""))
	return out if bool(r.get("here", false)) else "%s · %s" % [out, str(r.get("city", ""))]
