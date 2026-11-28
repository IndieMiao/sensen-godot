extends RefCounted
## Buildings on the owner's parcel (C-150; the first house Q-40, C-33#14). A type's footprint, blueprint and limit
## are the rules' `buildings` (assets/farm/data/dynamic_farm.json, shared with the server); its model and wall
## profile are KINDS below. A building stands the moment it is placed. Every footprint cell must be core, clear of
## the parcel's uncleared obstacles, other buildings, tilled cells and crops, and off the protected path that tilling
## also keeps clear (ParcelFarming.protected_path(), C-34, one rule for both per Q-44); and no remaining walk cell
## may lose its way to spawn. Outside the core (the ring round it and the entry path) nothing can be placed.
## C-154: a type's art may keep cells outside its footprint clear (`apron`: the coop's entry, so the player walks in,
## and its rear hedge row); they too lie in the core, and no later building covers them. The server stores and
## checks the footprint only. C-202: a type's `cutouts` (the barn's rear-left 2×2) are not its footprint; anything
## may stand there.
## `at` is the footprint's lowest-x, lowest-y cell, as the save stores it; `base` the footprint unturned (width along
## x, depth along y); `rotation` quarter turns 0–3 (所有者 SEN-C-134#22 第 3 题: 0, 90, 180, 270°), a quarter or
## three-quarter turn swapping width and depth. The server checks only buildings, tilled cells and crops (C-31).
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Kit = preload("res://modules/dynamic_farm/parcel_fieldkit.gd")
const Art = preload("res://modules/farm/farm_art.gd")
## C-154: a type the art file (`assets/farm/data/dynamic_farm_art.json`) describes, such as the coop, takes its name,
## model, fence and parts from there (FarmLivestock) instead of KINDS.
const Livestock = preload("res://modules/dynamic_farm/farm_livestock.gd")
## Per type: `asset` (FarmArt model, its pivot on the footprint's middle, +Z the front), `name` (the Build key says
## "Build <name>") and `profile` (the walls the player stops at, a FarmPropProxy profile in the model's frame).
## The cottage (house_cottage.glb, 3×3): walls and plinth below the eaves, measured from its cross-sections at
## 0.15–1.1 m (x ±0.875, z −0.84…0.885; the low step, the side woodpile and the bench stay walkable, under the body
## only). The eaves are overhead; the whole model stays within the 3×3 footprint (2.4 m).
## The well (C-151, well.glb, 1×1 as P0's well): its bounds are x −0.41…0.48, z ±0.345, 0.98 m high; the stone ring
## stops the player, a hair inside them. The winch's ends reach 4 cm past the 0.8 m cell on each side, overhead only.
const KINDS := {
	"cottage": {"asset": "house_cottage", "name": "Cottage",
		"profile": {"solid": true, "shape": "box", "center_xz_m": [0.0, 0.0225], "size_xz_m": [1.75, 1.725], "height_m": 1.1}},
	"well": {"asset": "well", "name": "Well",
		"profile": {"solid": true, "shape": "box", "center_xz_m": [0.035, 0.0], "size_xz_m": [0.8, 0.66], "height_m": 0.9}},
}
const HOME := ParcelFarm.HOME_BUILDING
const OUTSIDE := "Outside your yard"
const TAKEN := "Space taken"
const PATH := "Keep the path clear"
## C-175: the spot is refused only for the core obstacles standing on it; it is valid once they are cleared.
const CLEAR := "Clear the plants and rocks here first"
const AROUND := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
## C-253: a placement preview starts within this many metres of the player (footprint middle to the player's cell)
## when the yard has any spot there, ready or once cleared, so it opens by home in view instead of across the yard.
const START_REACH_M := 8.0

## The client art of a type: {asset, name, profile} (KINDS), {name, livestock: true} for a type the art file
## describes (C-154), or {} for a type this client has no art for.
static func kind(type: String) -> Dictionary:
	if KINDS.has(type): return KINDS[type]
	var art := Livestock.building_art(type)
	return {"name": str(art.get("name", type.capitalize())), "livestock": true} if not art.is_empty() else {}

## The type's model in its own frame (pivot on the footprint's middle, +Z the front), or null without art here.
static func model(type: String, base: Vector2i, cell_m: float) -> Node3D:
	var k := kind(type)
	if k.get("asset") is String:
		var standing := Art.instance(k.asset)
		# Keep the exact authored doors, shutters, winch and stone courses. Only
		# the loose dressing is joined into a single additional opaque surface.
		if type in ["well", "cottage"]:
			var dressing := MeshInstance3D.new()
			dressing.name = "FootprintProps"
			dressing.mesh = Kit.mesh("WellPails" if type == "well" else "CottageSill")
			dressing.material_override = Art.material()
			dressing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			standing.add_child(dressing)
		return standing
	if k.get("livestock", false): return Livestock.model(type, base, cell_m)
	return null

## The unturned footprint of a rules entry or a saved building (width × depth).
static func base_of(entry: Dictionary) -> Vector2i:
	return Vector2i(int(entry.width), int(entry.depth))

static func size(base: Vector2i, rotation := 0) -> Vector2i:
	return ParcelFarm.turned(base, rotation)

## The footprint's cells; `cutouts` (C-202, the rules' rects in the unturned frame) are not its own.
static func cells(at: Vector2i, base: Vector2i, rotation := 0, cutouts := []) -> Array[Vector2i]:
	return ParcelFarm.footprint(at, base, rotation, cutouts)

## C-202 the cutouts of a rules entry or a saved building (the barn's rear-left 2×2), [] without.
static func cutouts_of(entry: Dictionary) -> Array:
	return ParcelFarm.cutouts_of(entry)

## The cutouts a new building of `type` is placed with (the rules'), [] for an unknown type or "".
static func type_cutouts(type: String) -> Array:
	var rule = ParcelFarm.rules().get("buildings", {}).get(type)
	return cutouts_of(rule) if rule is Dictionary else []

## Cells nothing may cover: uncleared core obstacles (ParcelFarming.obstacle_cells(), every role, weeds too),
## the save's buildings and the cells they keep clear (C-154 `apron`), tilled cells and crops.
static func blocked(obstacles: Dictionary, farm: Dictionary) -> Dictionary:
	var out := obstacles.duplicate()
	out.merge(ParcelFarm.building_cells(farm))
	for b: Dictionary in ParcelFarm.buildings_of(farm):
		for cell in apron_cells(str(b.get("type", "")), at_of(b), base_of(b), int(b.get("rotation", 0))): out[cell] = true
	for key in farm.get("tilled", []): out[_cell(str(key))] = true
	for key in (farm.get("crops", {}) as Dictionary): out[_cell(str(key))] = true
	return out

## The cells of `layout` (core obstacle plan) still standing in `obstacles` that also block walking (stones,
## bushes, saplings).
static func solid(layout: Array, obstacles: Dictionary) -> Dictionary:
	var out := {}
	for item: Dictionary in layout:
		if bool(item.solid) and obstacles.has(item.cell): out[item.cell] = true
	return out

## "" when the building may stand at `at`, else the reason shown on the main key.
## `path`: the protected path; `walk_blocked`: cells walking cannot use besides the footprint (solid obstacles,
## other buildings, reserved extension cells). `type` adds the cells the type keeps clear (C-154 `apron`: the coop's
## entry and rear hedge row): each in the core and off other buildings and solid obstacles; walkable, the entry is
## then held to reaching spawn like every other walk cell. Tilled cells and crops may lie there (they stay walkable).
## `type` also leaves its cutouts (C-202) out of the footprint: they are judged as any cell outside it.
static func reason(data: Dictionary, at: Vector2i, base: Vector2i, rotation: int, taken: Dictionary, path: Dictionary,
		walk_blocked: Dictionary, type := "") -> String:
	var footprint := cells(at, base, rotation, type_cutouts(type))
	var kept := apron_cells(type, at, base, rotation)
	for cell in footprint + kept:
		if not data.by_cell.has(cell) or data.by_cell[cell].zone != "core": return OUTSIDE
	for cell in footprint:
		if taken.has(cell): return TAKEN
	for cell in kept:
		if walk_blocked.has(cell): return TAKEN
	for cell in footprint:
		if path.has(cell): return PATH
	return "" if keeps_open(data, footprint, walk_blocked) else PATH

## Every walk cell outside the footprint and `walk_blocked` still reaches spawn.
static func keeps_open(data: Dictionary, footprint: Array[Vector2i], walk_blocked: Dictionary) -> bool:
	var closed := walk_blocked.duplicate()
	for cell in footprint: closed[cell] = true
	if closed.has(data.spawn): return false
	var open := 0
	for cell: Vector2i in data.by_cell:
		if not closed.has(cell): open += 1
	var queue: Array[Vector2i] = [data.spawn]
	var seen := {data.spawn: true}
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		for offset: Vector2i in AROUND:
			var next: Vector2i = cell + offset
			if data.by_cell.has(next) and not closed.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == open

## The valid spot whose footprint centre is nearest `near` (a cell), or null.
static func nearest(data: Dictionary, near: Vector2i, base: Vector2i, taken: Dictionary, path: Dictionary,
		walk_blocked: Dictionary, rotation := 0, type := "") -> Variant:
	var offset := middle(base, rotation)
	var candidates: Array[Vector2i] = []
	for cell: Dictionary in data.cells:
		if cell.zone == "core": candidates.append(Vector2i(cell.x, cell.y) - offset)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i):
		var da := (a - near + offset).length_squared()
		var db := (b - near + offset).length_squared()
		return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	for at in candidates:
		if reason(data, at, base, rotation, taken, path, walk_blocked, type) == "": return at
	return null

## Where a placement preview starts (C-175) as {at, rotation}: the valid spot nearest `near`, unturned first, then in
## the other turns. A fresh yard often has no room for the coop until some of its trees, bushes, rocks and weeds are
## cleared, so with no valid spot it starts on the one that needs the fewest of them (`obstacles`) cleared, nearest
## first, judged with them gone (`clear_taken` / `clear_walk_blocked`); null when even a cleared yard has none.
## C-253: both are first sought within `reach_m` metres of `near` (the preview's camera frames the spot, so a far one
## leaves home out of view: 711 Pacific Ave's yard had its only ready coop spot 60 cells off), a ready spot there
## before one to clear there; only with neither in reach does it take the nearest ready spot, then one to clear, anywhere.
static func start_spot(data: Dictionary, near: Vector2i, base: Vector2i, taken: Dictionary, path: Dictionary,
		walk_blocked: Dictionary, type: String, obstacles: Dictionary, clear_taken: Dictionary,
		clear_walk_blocked: Dictionary, reach_m := START_REACH_M) -> Variant:
	var reach := reach_m / float(data.get("cell_m", 1.0))
	var ready: Array = []
	for rotation in 4:
		var found = nearest(data, near, base, taken, path, walk_blocked, rotation, type)
		if found == null: continue
		var spot := {"at": found, "rotation": rotation}
		if (Vector2(found as Vector2i + middle(base, rotation) - near)).length() <= reach: return spot
		ready.append(spot)
	var options := _clear_options(data, near, base, walk_blocked, type, obstacles)
	for o: Array in options:
		if o[1] > reach * reach: continue
		if reason(data, o[3], base, o[2], clear_taken, path, clear_walk_blocked, type) == "": return {"at": o[3], "rotation": o[2]}
	if not ready.is_empty(): return ready[0]
	for o: Array in options:
		if reason(data, o[3], base, o[2], clear_taken, path, clear_walk_blocked, type) == "": return {"at": o[3], "rotation": o[2]}
	return null

## Every core spot in all four turns as [obstacles to clear, squared distance of its middle from `near`, rotation, at],
## fewest to clear first, then nearest, then the lower turn (C-175).
static func _clear_options(data: Dictionary, near: Vector2i, base: Vector2i, walk_blocked: Dictionary, type: String,
		obstacles: Dictionary) -> Array:
	var options: Array = []
	for rotation in 4:
		var offset := middle(base, rotation)
		for cell: Dictionary in data.cells:
			if cell.zone != "core": continue
			var at := Vector2i(cell.x, cell.y) - offset
			var count := 0
			for c in cells(at, base, rotation, type_cutouts(type)):
				if obstacles.has(c): count += 1
			for c in apron_cells(type, at, base, rotation):
				if walk_blocked.has(c): count += 1 # only solid ones (and buildings) refuse the kept-clear cells
			options.append([count, (at - near + offset).length_squared(), rotation, at])
	options.sort_custom(func(a: Array, b: Array):
		return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	return options

## C-154 the cells outside the footprint a type keeps clear (FarmLivestock.keep_clear), turned with the building:
## {walk: [Vector2i], art: [Vector2i]}, both empty for a type without them. A cell of the unturned frame turns about
## the footprint's middle exactly as `transform` turns the model (grid y runs against the scene's +Z, the front;
## ParcelFarm.own_to_grid, as the footprint's own cells turn).
static func apron(type: String, at: Vector2i, base: Vector2i, rotation := 0) -> Dictionary:
	var out := {"walk": [] as Array[Vector2i], "art": [] as Array[Vector2i]}
	if type == "" or not kind(type).get("livestock", false): return out
	for k: Dictionary in Livestock.keep_clear(type, base):
		out["walk" if k.walk else "art"].append(at + ParcelFarm.own_to_grid(k.cell, base, rotation))
	return out

static func apron_cells(type: String, at: Vector2i, base: Vector2i, rotation := 0) -> Array[Vector2i]:
	var a := apron(type, at, base, rotation)
	var out: Array[Vector2i] = []
	out.append_array(a.walk)
	out.append_array(a.art)
	return out

## The footprint's middle cell, from its lowest cell (the finger holds a building there).
static func middle(base: Vector2i, rotation := 0) -> Vector2i:
	var s := size(base, rotation)
	return Vector2i(s.x / 2, s.y / 2)

## Where a footprint turned to `rotation` starts so that it keeps the middle of the one at `at` turned `was`: a turn
## spins a building in place (an odd-sized one exactly; an even side keeps within half a cell).
static func turned_at(at: Vector2i, base: Vector2i, was: int, rotation: int) -> Vector2i:
	return at + middle(base, was) - middle(base, rotation)

## The footprint's middle on the ground, in scene space.
static func center(walk: RefCounted, at: Vector2i, base: Vector2i, rotation := 0) -> Vector3:
	var s := size(base, rotation)
	return (walk.point(at) + walk.point(at + s - Vector2i.ONE)) * 0.5

## Where the build's dust puffs (C-114): the footprint's four corners and four edge middles, on the ground.
static func rim(walk: RefCounted, at: Vector2i, base: Vector2i, rotation := 0) -> Array[Vector3]:
	var half := Vector2(size(base, rotation)) * float(walk.cell_m) * 0.5
	var mid := center(walk, at, base, rotation)
	var out: Array[Vector3] = []
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx != 0 or dz != 0: out.append(mid + Vector3(dx * half.x, 0, dz * half.y))
	return out

## The model's transform: its own pivot on the footprint's middle, +Z (the front) toward the camera, a quarter turn
## per rotation step.
static func transform(walk: RefCounted, at: Vector2i, base: Vector2i, rotation := 0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rotation * PI * 0.5), center(walk, at, base, rotation))

## The type's walls at that spot, or null for a type without a profile here.
static func proxy(walk: RefCounted, type: String, at: Vector2i, base: Vector2i, rotation := 0) -> Proxy:
	var profile = kind(type).get("profile")
	return Proxy.new(profile, transform(walk, at, base, rotation), 1.0) if profile is Dictionary else null

## Every wall of the type at that spot: the KINDS profile, or a livestock building's fence runs and parts (C-154; its
## entry stays open, so the player walks in; C-202: its fence round its `cutouts`).
static func proxies(walk: RefCounted, type: String, at: Vector2i, base: Vector2i, rotation := 0, cutouts := []) -> Array:
	if kind(type).get("livestock", false):
		return Livestock.proxies(type, base, float(walk.cell_m), transform(walk, at, base, rotation), cutouts)
	var one := proxy(walk, type, at, base, rotation)
	return [one] if one != null else []

static func at_of(building: Dictionary) -> Vector2i:
	return Vector2i(int(building.get("x", 0)), int(building.get("y", 0)))

static func _cell(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-1, -1)
