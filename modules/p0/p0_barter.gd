class_name P0Barter
extends RefCounted
## Specialty barter at a Market Square keeper (plan §8.4.5, SGODOT-284; 不知火舞's spec on 284): a group of rows at the
## end of the counter's Buy page, from the server's view.shops.market.barter ({give, daily, left, resets_in, items:
## [{id, name, have}], minerals: [{id, name, room, share}]}). What goes is this city's climate's regional crops and fish
## (the server lists them; a Gifted stack is not counted). Pure and static: the counter drawer draws the rows.

const MAX_LEFT_REASON := "Limit reached · %s"   # q(121): the day's six are used, and when they come back

static func block(view: Dictionary) -> Dictionary:
	var b = view.get("shops", {}).get("market", {}).get("barter", null)
	return b if b is Dictionary else {}

## The group's heading: `Barter · 2 for 1 · 4/6 today` (barters done today of the day's six, as the buy-back line's
## `Buy-back today 30/60`); "" without a barter block (an older server, or not the market).
static func header(view: Dictionary) -> String:
	var b := block(view)
	if b.is_empty(): return ""
	var daily := int(b.get("daily", 6))
	return "Barter · %d for 1 · %d/%d today" % [int(b.get("give", 2)), daily - int(b.get("left", daily)), daily]

## The regional item a barter takes now: the one the bag holds most of, if it holds enough (ties: the list's order);
## {} when none has `give`.
static func pick(view: Dictionary) -> Dictionary:
	var b := block(view)
	var give := int(b.get("give", 2))
	var best := {}
	for it in b.get("items", []):
		if int(it.get("have", 0)) >= give and (best.is_empty() or int(it.have) > int(best.have)): best = it
	return best

## One row per mineral: {id, title, effect (`For 2 Sweet Potato` / `For 2 regional crops or fish`), gate
## (`3 of 6 left this level`), price (`2 items`), button (`Barter`), reason ("" when it can go; else the grey key's
## words), cmd ({} when it cannot)}.
static func rows(view: Dictionary) -> Array:
	var b := block(view)
	if b.is_empty(): return []
	var give := int(b.get("give", 2))
	var item := pick(view)
	var out: Array = []
	for m in b.get("minerals", []):
		var room := int(m.get("room", 0))
		var row := {id = str(m.get("id", "")), title = str(m.get("name", "")),
			effect = ("For %d %s" % [give, str(item.name)]) if not item.is_empty() else ("For %d regional crops or fish" % give),
			gate = "%d of %d left this level" % [room, int(m.get("share", room))],
			price = "%d items" % give, button = "Barter", reason = "", cmd = {}}
		if int(b.get("left", 0)) <= 0: row.reason = MAX_LEFT_REASON % P0Logic.span(float(b.get("resets_in", 0)))
		elif room <= 0: row.reason = "Level quota used"
		elif item.is_empty(): row.reason = "Need %d regional items" % give
		else: row.cmd = {"type": "barter", "item": str(item.id), "mineral": row.id, "shop": "market"}
		out.append(row)
	return out

## The Success toast after a barter's reply (its item events): `+1 Stone · −2 Sweet Potato`; "" when the events are
## not a barter's.
static func toast(view: Dictionary, events: Array) -> String:
	var b := block(view)
	var minerals: Array = b.get("minerals", []).map(func(m): return str(m.get("id", "")))
	var got := ""
	var gave := ""
	for e in events:
		if str(e.get("kind", "")) != "item": continue
		var id := str(e.get("id", ""))
		var d := int(e.get("delta", 0))
		if d > 0 and minerals.has(id): got = "+%d %s" % [d, P0Logic.item_name(view, id)]
		elif d < 0: gave = "−%d %s" % [-d, P0Logic.item_name(view, id)]
	return "%s · %s" % [got, gave] if got != "" and gave != "" else ""
