extends SceneTree
## C-193: which claimable parcels can hold the coop, the barn and the sheep pen with the yard cleared.
## For every parcel file given, the yard is taken as a player leaves it after clearing every core obstacle (no
## buildings, tilled cells or crops), exactly as test_coop.gd's `_keep_clear_parcel` judges it: Building.reason with
## nothing taken, the protected path, and the walk cells reserved by the scenery plan. Each shape is tried at every
## cell in all four turns until one spot passes; three levels say why a parcel fails:
##   core  — footprint and kept cells all in the core (the yard has room of that shape at all),
##   path  — and the footprint off the protected entry→spawn path,
##   full  — and every walk cell still reaches spawn (the real rule).
## Shapes: the coop with its real art (7×5 and its kept cells); the barn as C-192's draft art (8×6, the cell outside
## its entry, f000a009); plain W×D sizes with one walkable cell outside the front middle (the sheep pen's size is not
## set yet); and, in order, cottage → coop → barn → pen 8×6 each at the first passing spot (a greedy lower bound on
## all fitting together).
##   godot --headless --path "$QA" --script res://tools/dev/dynamic_farm/building_fit_stats.gd -- <out.json> <list.txt>
## <list.txt>: one parcel JSON path per line.
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")

## name → {base, keep: [{cell, walk}] in the unturned frame (cells outside the footprint), type: real art type or ""}.
var shapes := {}

func _initialize() -> void:
	_run.call_deferred()

func _front(base: Vector2i) -> Array:
	return [{"cell": Vector2i(base.x / 2, base.y), "walk": true}]

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var rules := ParcelFarm.rules()
	shapes["coop"] = {"base": Building.base_of(rules.buildings.coop), "type": "coop", "keep": []}
	shapes["barn_8x6"] = {"base": Vector2i(8, 6), "type": "", "keep": [{"cell": Vector2i(3, 6), "walk": true}]}
	for s: Vector2i in [Vector2i(5, 3), Vector2i(6, 4), Vector2i(7, 5), Vector2i(8, 6), Vector2i(9, 7), Vector2i(10, 8)]:
		shapes["plain_%dx%d" % [s.x, s.y]] = {"base": s, "type": "", "keep": _front(s)}
	var rows := []
	var started := Time.get_ticks_msec()
	for line in FileAccess.get_file_as_string(args[1]).split("\n", false):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(line.strip_edges()))
		if not raw is Dictionary:
			rows.append({"file": line, "error": "unreadable"})
			continue
		rows.append(_parcel(raw))
	var out := FileAccess.open(args[0], FileAccess.WRITE)
	out.store_string(JSON.stringify({"shapes": _shape_view(), "parcels": rows}))
	out.close()
	print("BUILDING_FIT parcels=%d ms=%d" % [rows.size(), Time.get_ticks_msec() - started])
	quit(0)

func _shape_view() -> Dictionary:
	var view := {}
	for name: String in shapes:
		var s: Dictionary = shapes[name]
		var keep: Array = Building.apron_cells(s.type, Vector2i.ZERO, s.base, 0) if s.type != "" else s.keep.map(func(k): return k.cell)
		view[name] = {"base": [s.base.x, s.base.y], "keep": keep.map(func(c): return [c.x, c.y])}
	return view

## The shape's kept cells at `at` turned `rotation`: {walk, art}; the real art's for a typed shape, else turned
## exactly as Building.apron turns them.
func _kept(s: Dictionary, at: Vector2i, rotation: int) -> Dictionary:
	if s.type != "": return Building.apron(s.type, at, s.base, rotation)
	var out := {"walk": [] as Array[Vector2i], "art": [] as Array[Vector2i]}
	var base: Vector2i = s.base
	var size := Building.size(base, rotation)
	for k: Dictionary in s.keep:
		var x: int = 2 * k.cell.x + 1 - base.x
		var z: int = 2 * k.cell.y + 1 - base.y
		var grid: Vector2i = [Vector2i(x, -z), Vector2i(z, x), Vector2i(-x, z), Vector2i(-z, -x)][posmod(rotation, 4)]
		out["walk" if k.walk else "art"].append(Vector2i(floori((2 * at.x + size.x + grid.x) / 2.0), floori((2 * at.y + size.y + grid.y) / 2.0)))
	return out

## 0 core fails, 1 core ok but on the path, 2 path ok but cuts a walk cell off spawn, 3 the spot passes.
func _level(data: Dictionary, s: Dictionary, at: Vector2i, rotation: int, taken: Dictionary, path: Dictionary, walk_blocked: Dictionary) -> int:
	var footprint := Building.cells(at, s.base, rotation)
	var k := _kept(s, at, rotation)
	var kept: Array[Vector2i] = []
	kept.append_array(k.walk)
	kept.append_array(k.art)
	for cell in footprint + kept:
		if not data.by_cell.has(cell) or data.by_cell[cell].zone != "core": return 0
	for cell in footprint:
		if taken.has(cell): return 0
	for cell in kept:
		if walk_blocked.has(cell): return 0
	for cell in footprint:
		if path.has(cell): return 1
	if not Building.keeps_open(data, footprint, walk_blocked): return 2
	if s.type != "":
		# Same verdict as the game's own check (a typed shape only).
		assert(Building.reason(data, at, s.base, rotation, taken, path, walk_blocked, s.type) == "")
	return 3

## The best level any spot reaches, with the first passing spot (or null).
func _best(data: Dictionary, s: Dictionary, bounds: Rect2i, taken: Dictionary, path: Dictionary, walk_blocked: Dictionary) -> Dictionary:
	var best := 0
	for rotation in 4:
		var size := Building.size(s.base, rotation)
		for y in range(bounds.position.y - 1, bounds.end.y - size.y + 2):
			for x in range(bounds.position.x - 1, bounds.end.x - size.x + 2):
				var level := _level(data, s, Vector2i(x, y), rotation, taken, path, walk_blocked)
				if level == 3: return {"level": 3, "at": Vector2i(x, y), "rotation": rotation}
				best = maxi(best, level)
	return {"level": best, "at": null, "rotation": -1}

func _parcel(raw: Dictionary) -> Dictionary:
	var data := Data.decode(raw)
	if not data.ok: return {"block_id": str(raw.get("block_id", "")), "error": "decode"}
	var walk := Walk.new(data)
	var planned := Scenery.plan(data, walk)
	Shade.enforce_budget(planned, data, walk)
	var path := Space.protected_path(data)
	var core := 0
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for cell: Dictionary in data.cells:
		if cell.zone != "core": continue
		core += 1
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	var bounds := Rect2i(lo, hi - lo + Vector2i.ONE)
	var row := {"block_id": data.block_id, "core": core, "path": path.size(), "bounds": [bounds.size.x, bounds.size.y], "fit": {}}
	for name: String in shapes:
		var b := _best(data, shapes[name], bounds, {}, path, walk.reserved)
		row.fit[name] = "ok" if b.level == 3 else ["none", "path", "reach"][b.level]
	# Greedy, in order: each building at the first passing spot, then nothing may cover it or its kept cells.
	var taken := {}
	var walk_blocked: Dictionary = walk.reserved.duplicate()
	var placed := 0
	var cottage := {"base": Building.base_of(ParcelFarm.rules().buildings.cottage), "type": "", "keep": []}
	for s: Dictionary in [cottage, shapes.coop, shapes.barn_8x6, shapes.plain_8x6]:
		var b := _best(data, s, bounds, taken, path, walk_blocked)
		if b.level != 3: break
		placed += 1
		var k := _kept(s, b.at, b.rotation)
		for cell in Building.cells(b.at, s.base, b.rotation):
			taken[cell] = true
			walk_blocked[cell] = true
		for cell in k.walk + k.art: taken[cell] = true
	row["together"] = placed
	return row
