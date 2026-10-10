class_name P0Decor
extends RefCounted
## Decorate on the client (P1, SGODOT-284; plan §9.11.6, q(111) / q(113) / q(120); 不知火舞 on 284 ee15926a, 29e28d3f,
## 49b11f91; Figma row 62 2187:33367). The catalog and the yard come from the content (content/shops_decor.json), the
## pieces from view.decor (server decor.ts decorView: placed [{uid, id, x, y, rot}], cap, used, stored {id: n}).
## A spot is judged with the server's rules (decor.ts spotBlock), so the bar never offers a Place the server refuses.
## Pure and static: tested headless.

## The bar's words for a spot the server would refuse (decor.ts codes).
const REASONS := {"decor_outside": "Outside your yard", "decor_overlap": "Space taken", "decor_path": "Keep the path clear"}
const NONE := Vector2i(-1, -1)
const MAX_LEVEL := 10

static func items() -> Dictionary: return P0Logic.content().get("decor", {}).get("items", {})
static func yard() -> Dictionary: return P0Logic.content().get("decor", {}).get("yard", {})
static func is_decor(id: String) -> bool: return items().has(id)
static func item(id: String) -> Dictionary: return items().get(id, {})
static func name_of(id: String) -> String: return str(item(id).get("name", id))

## Cells a piece takes: [w, h], turned (rot 1) h × w.
static func size_of(id: String, rot := 0) -> Vector2i:
	var s: Array = item(id).get("size", [1, 1])
	return Vector2i(int(s[1]), int(s[0])) if rot else Vector2i(int(s[0]), int(s[1]))

## Only a piece that isn't square turns (the bar's Rotate, ee15926a ③).
static func turns(id: String) -> bool:
	var s := size_of(id)
	return s.x != s.y

static func cells(id: String, at: Vector2i, rot := 0) -> Array:
	var s := size_of(id, rot)
	var out: Array = []
	for dy in s.y:
		for dx in s.x: out.append(at + Vector2i(dx, dy))
	return out

static func _rect(r) -> Rect2i: return Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))

static func _in_any(cell: Vector2i, rects: Array) -> bool:
	for r in rects:
		if _rect(r).has_point(cell): return true
	return false

static func placed(view: Dictionary) -> Array: return view.get("decor", {}).get("placed", []) if view.get("decor", null) is Dictionary else []

## Cells the yard's pieces take ("x,y" → uid), but the one being moved.
static func taken(view: Dictionary, ignore := -1) -> Dictionary:
	var out := {}
	for p in placed(view):
		if int(p.get("uid", 0)) == ignore: continue
		for c in cells(str(p.id), Vector2i(int(p.x), int(p.y)), int(p.get("rot", 0))): out["%d,%d" % [c.x, c.y]] = int(p.uid)
	return out

## "" when the piece may stand with its top-left cell at `at`, else the bar's reason (decor.ts spotBlock, same order).
static func reason(view: Dictionary, id: String, at: Vector2i, rot := 0, ignore := -1) -> String:
	var y := yard()
	var cs := cells(id, at, rot)
	for c in cs:
		if not _rect(y.get("walk", [0, 0, 0, 0])).has_point(c) or _in_any(c, y.get("field", [])): return REASONS.decor_outside
	var t := taken(view, ignore)
	for c in cs:
		if _in_any(c, y.get("objects", [])) or t.has("%d,%d" % [c.x, c.y]): return REASONS.decor_overlap
	for c in cs:
		if _in_any(c, y.get("paths", [])): return REASONS.decor_path
	return ""

## The legal top-left cell nearest `from` (the preview starts there, q(59) §4 as the sprinkler), NONE when none is.
static func nearest_spot(view: Dictionary, id: String, rot: int, from: Vector2i, ignore := -1) -> Vector2i:
	var walk := _rect(yard().get("walk", [0, 0, 0, 0]))
	var best := NONE
	var best_d := INF
	for y in range(walk.position.y, walk.end.y):
		for x in range(walk.position.x, walk.end.x):
			var at := Vector2i(x, y)
			var d := Vector2(at - from).length_squared()
			if d >= best_d or reason(view, id, at, rot, ignore) != "": continue
			best_d = d
			best = at
	return best

## The piece covering a cell, {} when none.
static func piece_at(view: Dictionary, cell: Vector2i) -> Dictionary:
	for p in placed(view):
		if cells(str(p.id), Vector2i(int(p.x), int(p.y)), int(p.get("rot", 0))).has(cell): return p
	return {}

static func stored(view: Dictionary, id: String) -> int:
	return int(view.get("decor", {}).get("stored", {}).get(id, 0)) if view.get("decor", null) is Dictionary else 0

static func cap(view: Dictionary) -> int: return int(view.get("decor", {}).get("cap", 20)) if view.get("decor", null) is Dictionary else 20
static func used(view: Dictionary) -> int: return placed(view).size()
static func full(view: Dictionary) -> bool: return used(view) >= cap(view)

## `1×1` · the footprint as the row and the card write it.
static func footprint(id: String) -> String:
	var s := size_of(id)
	return "%d×%d" % [s.x, s.y]

## The row's and the card's second line (q(111) / q(113)): `1×1 · Glows at night`; a multi-piece one `5 pieces`.
static func line(id: String) -> String:
	var it := item(id)
	if int(it.get("pieces", 1)) > 1: return "%d pieces" % int(it.pieces)
	var blurb := str(it.get("blurb", ""))
	return footprint(id) + (" · " + blurb if blurb != "" else "")

## The Decor page's fact line (q(111)): `Decor 12/24 · Goes to Farm Storage`.
static func header_line(view: Dictionary) -> String:
	return "Decor %d/%d · Goes to Farm Storage" % [used(view), cap(view)]

## The cap reached, said where Decorate is entered (q(113) ①): `Decor 24/24 · Homestead Lv3 adds 4`, at Lv10
## `Decor 56/56 · Store one to place this`.
static func cap_line(view: Dictionary) -> String:
	var level := int(view.get("homestead", {}).get("level", 1))
	var head := "Decor %d/%d" % [used(view), cap(view)]
	if level >= MAX_LEVEL: return head + " · Store one to place this"
	var per := int(P0Logic.content().get("homestead", {}).get("decor_max", {}).get("per_level", 4))
	return head + " · Homestead Lv%d adds %d" % [level + 1, per]

## Today's free row while pieces wait in Farm Storage (q(111), 29e28d3f): `Place Flower Planter · in storage`, several
## kinds `Place 2 decor · in storage`; no red dot (q(107)). {} when nothing waits or the yard is full.
static func today_row(view: Dictionary) -> Dictionary:
	if full(view) or not view.get("decor", null) is Dictionary: return {}
	var kinds: Array = (view.decor.get("stored", {}) as Dictionary).keys().filter(func(id): return is_decor(str(id)) and stored(view, str(id)) > 0)
	if kinds.is_empty(): return {}
	kinds.sort()
	var what := name_of(str(kinds[0])) if kinds.size() == 1 else "%d decor" % kinds.size()
	return {"line": "Place %s · in storage" % what, "icon": "storage", "id": str(kinds[0]) if kinds.size() == 1 else ""}
