extends RefCounted
## C-193: does a parcel's yard, cleared, hold a building shape? Shared by building_fit_stats.gd (the statistic over
## whole parcel sets) and tests/dynamic_farm/test_building_fit.gd (the guard on the narrowest r8 parcels).
## The yard is taken as a player leaves it after clearing every core obstacle (no buildings, tilled cells or crops),
## exactly as test_coop.gd's `_keep_clear_parcel` judges it: Building.reason with nothing taken, the protected path,
## and the walk cells reserved by the scenery plan. Each shape is tried at every cell in all four turns until one spot
## passes; three levels say why a parcel fails:
##   core  — footprint and kept cells all in the core (the yard has room of that shape at all),
##   path  — and the footprint off the protected entry→spawn path,
##   full  — and every walk cell still reaches spawn (the real rule).
## Nothing here changes the game's placement rule; it only calls it.
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")

const NONE := 0
const PATH := 1
const REACH := 2
const OK := 3
const VERDICT := ["none", "path", "reach", "ok"]

## A plain W×D shape with one walkable cell outside its front middle (the sheep pen's size is not set yet).
static func plain(base: Vector2i) -> Dictionary:
	return {"base": base, "type": "", "keep": [{"cell": Vector2i(base.x / 2, base.y), "walk": true}], "cutouts": []}

## The coop with its real art (7×5 and its kept cells, from the art file).
static func coop() -> Dictionary:
	return {"base": Building.base_of(ParcelFarm.rules().buildings.coop), "type": "coop", "keep": [], "cutouts": []}

## The barn with its real art (C-202, SEN-C-179's final yard: 11×6 less the rear-left 2×2, the two cells outside its
## gate, from the rules and the art file).
static func barn() -> Dictionary:
	var rule: Dictionary = ParcelFarm.rules().buildings.barn
	return {"base": Building.base_of(rule), "type": "barn", "keep": [], "cutouts": Building.cutouts_of(rule)}

## C-192's draft barn: 8×6, the cell outside its entry (f000a009), for comparison with earlier statistics.
static func draft_barn() -> Dictionary:
	return {"base": Vector2i(8, 6), "type": "", "keep": [{"cell": Vector2i(3, 6), "walk": true}], "cutouts": []}

## The cottage, 3×3, keeping nothing past its footprint.
static func cottage() -> Dictionary:
	return {"base": Building.base_of(ParcelFarm.rules().buildings.cottage), "type": "", "keep": [], "cutouts": []}

## The statistic's shapes: name → {base, keep: [{cell, walk}] in the unturned frame (cells outside the footprint),
## type: real art type or "", cutouts: the footprint's rects that are not its own (C-202)}.
static func shapes() -> Dictionary:
	var out := {"coop": coop(), "barn": barn(), "barn_8x6": draft_barn()}
	for s: Vector2i in [Vector2i(5, 3), Vector2i(6, 4), Vector2i(7, 5), Vector2i(8, 6), Vector2i(9, 7), Vector2i(10, 8)]:
		out["plain_%dx%d" % [s.x, s.y]] = plain(s)
	return out

## The cleared yard of a parcel payload: {ok, data, walk, path, bounds, core}; ok=false when it does not decode.
static func yard(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {"ok": false}
	var data := Data.decode(raw)
	if not data.ok: return {"ok": false}
	var walk := Walk.new(data)
	var planned := Scenery.plan(data, walk)
	Shade.enforce_budget(planned, data, walk)
	var core := 0
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for cell: Dictionary in data.cells:
		if cell.zone != "core": continue
		core += 1
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	return {"ok": true, "data": data, "walk": walk, "path": Space.protected_path(data), "core": core,
		"bounds": Rect2i(lo, hi - lo + Vector2i.ONE)}

## The shape's kept cells at `at` turned `rotation`: {walk, art}; the real art's for a typed shape, else turned
## exactly as Building.apron turns them.
static func kept(s: Dictionary, at: Vector2i, rotation: int) -> Dictionary:
	if s.type != "": return Building.apron(s.type, at, s.base, rotation)
	var out := {"walk": [] as Array[Vector2i], "art": [] as Array[Vector2i]}
	for k: Dictionary in s.keep:
		out["walk" if k.walk else "art"].append(at + ParcelFarm.own_to_grid(k.cell, s.base, rotation))
	return out

## The shape's kept cells in the unturned frame, for reports.
static func kept_view(s: Dictionary) -> Array:
	if s.type != "": return Building.apron_cells(s.type, Vector2i.ZERO, s.base, 0)
	return s.keep.map(func(k): return k.cell)

## NONE core fails, PATH core ok but on the path, REACH path ok but cuts a walk cell off spawn, OK the spot passes.
static func level(data: Dictionary, s: Dictionary, at: Vector2i, rotation: int, taken: Dictionary, path: Dictionary, walk_blocked: Dictionary) -> int:
	var footprint := Building.cells(at, s.base, rotation, s.get("cutouts", []))
	var k := kept(s, at, rotation)
	var all_kept: Array[Vector2i] = []
	all_kept.append_array(k.walk)
	all_kept.append_array(k.art)
	for cell in footprint + all_kept:
		if not data.by_cell.has(cell) or data.by_cell[cell].zone != "core": return NONE
	for cell in footprint:
		if taken.has(cell): return NONE
	for cell in all_kept:
		if walk_blocked.has(cell): return NONE
	for cell in footprint:
		if path.has(cell): return PATH
	if not Building.keeps_open(data, footprint, walk_blocked): return REACH
	if s.type != "":
		# Same verdict as the game's own check (a typed shape only).
		assert(Building.reason(data, at, s.base, rotation, taken, path, walk_blocked, s.type) == "")
	return OK

## The best level any spot in the yard reaches, with the first passing spot (or null) and its turn.
static func best(y: Dictionary, s: Dictionary, taken := {}, walk_blocked: Variant = null) -> Dictionary:
	var data: Dictionary = y.data
	var bounds: Rect2i = y.bounds
	var blocked: Dictionary = y.walk.reserved if walk_blocked == null else walk_blocked
	var top := NONE
	for rotation in 4:
		var size := Building.size(s.base, rotation)
		for cy in range(bounds.position.y - 1, bounds.end.y - size.y + 2):
			for cx in range(bounds.position.x - 1, bounds.end.x - size.x + 2):
				var l := level(data, s, Vector2i(cx, cy), rotation, taken, y.path, blocked)
				if l == OK: return {"level": OK, "at": Vector2i(cx, cy), "rotation": rotation}
				top = maxi(top, l)
	return {"level": top, "at": null, "rotation": -1}

## In order, each shape at its first passing spot; nothing may then cover it or its kept cells. How many went down
## (a greedy lower bound on all of them fitting together).
static func together(y: Dictionary, order: Array) -> int:
	var taken := {}
	var walk_blocked: Dictionary = y.walk.reserved.duplicate()
	var placed := 0
	for s: Dictionary in order:
		var b := best(y, s, taken, walk_blocked)
		if b.level != OK: break
		placed += 1
		var k := kept(s, b.at, b.rotation)
		for cell in Building.cells(b.at, s.base, b.rotation, s.get("cutouts", [])):
			taken[cell] = true
			walk_blocked[cell] = true
		for cell in k.walk + k.art: taken[cell] = true
	return placed
