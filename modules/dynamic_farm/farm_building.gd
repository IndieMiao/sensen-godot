extends RefCounted
## Buildings on the owner's parcel (C-150; the first house Q-40, C-33#14). A type's footprint, blueprint and limit
## are the rules' `buildings` (assets/farm/data/dynamic_farm.json, shared with the server); its model and wall
## profile are KINDS below. A building stands the moment it is placed. Every footprint cell must be core, clear of
## the parcel's uncleared obstacles, other buildings, tilled cells and crops, and off the protected path that tilling
## also keeps clear (ParcelFarming.protected_path(), C-34, one rule for both per Q-44); and no remaining walk cell
## may lose its way to spawn. Outside the core (the ring round it and the entry path) nothing can be placed.
## C-154: a type's art may keep cells outside its footprint clear (`apron`: the coop's entry, so the player walks in,
## and its rear hedge row); they too lie in the core, and no later building covers them. The server stores and
## checks the footprint only.
## `at` is the footprint's lowest-x, lowest-y cell, as the save stores it; `base` the footprint unturned (width along
## x, depth along y); `rotation` quarter turns 0–3 (所有者 SEN-C-134#22 第 3 题: 0, 90, 180, 270°), a quarter or
## three-quarter turn swapping width and depth. The server checks only buildings, tilled cells and crops (C-31).
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Art = preload("res://modules/farm/farm_art.gd")
## C-154: a type the art file (`assets/farm/data/dynamic_farm_art.json`) describes, such as the coop, takes its name,
## model, fence and parts from there (FarmLivestock) instead of KINDS.
const Livestock = preload("res://modules/dynamic_farm/farm_livestock.gd")
## Per type: `asset` (FarmArt model, its pivot on the footprint's middle, +Z the front), `name` (the Build key says
## "Build <name>") and `profile` (the walls the player stops at, a FarmPropProxy profile in the model's frame).
## The cottage (house_cottage.glb, 3×3): walls and plinth below the eaves, measured from its cross-sections at
## 0.15–1.1 m (x ±0.875, z −0.84…0.885; the low step, the side woodpile and the bench stay walkable, under the body
## only). The eaves are overhead; the whole model stays within the 3×3 footprint (2.4 m).
const KINDS := {
	"cottage": {"asset": "house_cottage", "name": "Cottage",
		"profile": {"solid": true, "shape": "box", "center_xz_m": [0.0, 0.0225], "size_xz_m": [1.75, 1.725], "height_m": 1.1}},
}
const HOME := ParcelFarm.HOME_BUILDING
const OUTSIDE := "Outside your yard"
const TAKEN := "Space taken"
const PATH := "Keep the path clear"
const AROUND := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

## The client art of a type: {asset, name, profile} (KINDS), {name, livestock: true} for a type the art file
## describes (C-154), or {} for a type this client has no art for.
static func kind(type: String) -> Dictionary:
	if KINDS.has(type): return KINDS[type]
	var art := Livestock.building_art(type)
	return {"name": str(art.get("name", type.capitalize())), "livestock": true} if not art.is_empty() else {}

## The type's model in its own frame (pivot on the footprint's middle, +Z the front), or null without art here.
static func model(type: String, base: Vector2i, cell_m: float) -> Node3D:
	var k := kind(type)
	if k.get("asset") is String: return Art.instance(k.asset)
	if k.get("livestock", false): return Livestock.model(type, base, cell_m)
	return null

## The unturned footprint of a rules entry or a saved building (width × depth).
static func base_of(entry: Dictionary) -> Vector2i:
	return Vector2i(int(entry.width), int(entry.depth))

static func size(base: Vector2i, rotation := 0) -> Vector2i:
	return ParcelFarm.turned(base, rotation)

static func cells(at: Vector2i, base: Vector2i, rotation := 0) -> Array[Vector2i]:
	return ParcelFarm.footprint(at, base, rotation)

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
static func reason(data: Dictionary, at: Vector2i, base: Vector2i, rotation: int, taken: Dictionary, path: Dictionary,
		walk_blocked: Dictionary, type := "") -> String:
	var footprint := cells(at, base, rotation)
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

## C-154 the cells outside the footprint a type keeps clear (FarmLivestock.keep_clear), turned with the building:
## {walk: [Vector2i], art: [Vector2i]}, both empty for a type without them. A cell of the unturned frame turns about
## the footprint's middle exactly as `transform` turns the model (grid y runs against the scene's +Z, the front).
static func apron(type: String, at: Vector2i, base: Vector2i, rotation := 0) -> Dictionary:
	var out := {"walk": [] as Array[Vector2i], "art": [] as Array[Vector2i]}
	if type == "" or not kind(type).get("livestock", false): return out
	var s := size(base, rotation)
	for k: Dictionary in Livestock.keep_clear(type, base):
		# Doubled so every centre is a whole number: the cell's centre from the footprint's middle, model frame.
		var x: int = 2 * k.cell.x + 1 - base.x
		var z: int = 2 * k.cell.y + 1 - base.y
		var grid: Vector2i = [Vector2i(x, -z), Vector2i(z, x), Vector2i(-x, z), Vector2i(-z, -x)][posmod(rotation, 4)]
		var cell := Vector2i(floori((2 * at.x + s.x + grid.x) / 2.0), floori((2 * at.y + s.y + grid.y) / 2.0))
		out["walk" if k.walk else "art"].append(cell)
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
## entry stays open, so the player walks in).
static func proxies(walk: RefCounted, type: String, at: Vector2i, base: Vector2i, rotation := 0) -> Array:
	if kind(type).get("livestock", false):
		return Livestock.proxies(type, base, float(walk.cell_m), transform(walk, at, base, rotation))
	var one := proxy(walk, type, at, base, rotation)
	return [one] if one != null else []

static func at_of(building: Dictionary) -> Vector2i:
	return Vector2i(int(building.get("x", 0)), int(building.get("y", 0)))

static func _cell(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-1, -1)
