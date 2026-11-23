extends RefCounted
## The first house (Q-40, C-33#14): the existing 3×3 cottage, built the moment it is placed. Every footprint cell
## must be core, clear of the parcel's obstacles (C-18, until cleared), tilled cells and crops, and of the protected
## ways: schema 4 marks the whole core as reserve, so on the core the protected ways are the spawn's arrival disc
## (the same dx²+dy² <= 4 the data contract keeps protected) and the walking connection itself — no remaining walk
## cell may lose its way to spawn. Outside the core (the ring round it and the entry path) nothing can be placed.
## `at` is the footprint's lowest-x, lowest-y cell, as the parcel save (C-31 farm_state.house) stores it.
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
const ASSET := "house_cottage"
const MODEL := "cottage"
const BLUEPRINT := "blueprint_cottage"
const SIZE := Vector2i(3, 3)
## Walls and plinth below the eaves, measured from house_cottage.glb's cross-sections at 0.15–1.1 m
## (x ±0.875, z −0.84…0.885; the low step, the side woodpile and the bench stay walkable, under the body only).
## The eaves are overhead; the whole model stays within the 3×3 footprint (2.4 m).
const PROFILE := {"solid":true, "shape":"box", "center_xz_m":[0.0, 0.0225], "size_xz_m":[1.75, 1.725], "height_m":1.1}
const ARRIVAL_R2 := 4
const OUTSIDE := "Outside your yard"
const TAKEN := "Space taken"
const PATH := "Keep the path clear"
const AROUND := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

static func size(rotation := 0) -> Vector2i:
	return Vector2i(SIZE.y, SIZE.x) if rotation % 2 else SIZE

static func cells(at: Vector2i, rotation := 0) -> Array[Vector2i]:
	var s := size(rotation)
	var out: Array[Vector2i] = []
	for dy in s.y:
		for dx in s.x: out.append(at + Vector2i(dx, dy))
	return out

## Cells nothing may cover: uncleared core obstacles (every role, weeds too), tilled cells and crops of the save.
## `solid` gets the obstacles that also block walking (stones, bushes, saplings).
static func blocked(obstacles: Array, farm: Dictionary, solid := {}) -> Dictionary:
	var cleared := {}
	for key in farm.get("cleared", []): cleared[_cell(str(key))] = true
	var out := {}
	for item: Dictionary in obstacles:
		var at: Vector2i = item.cell
		if cleared.has(at): continue
		out[at] = true
		if bool(item.solid): solid[at] = true
	for key in farm.get("tilled", []): out[_cell(str(key))] = true
	for key in (farm.get("crops", {}) as Dictionary): out[_cell(str(key))] = true
	return out

## "" when the house may stand at `at`, else the reason shown on the main key.
## `walk_blocked`: cells walking cannot use besides the footprint (solid obstacles, reserved extension cells).
static func reason(data: Dictionary, at: Vector2i, rotation: int, taken: Dictionary, walk_blocked: Dictionary) -> String:
	var footprint := cells(at, rotation)
	for cell in footprint:
		if not data.by_cell.has(cell) or data.by_cell[cell].zone != "core": return OUTSIDE
	for cell in footprint:
		if taken.has(cell): return TAKEN
	for cell in footprint:
		var d: Vector2i = cell - data.spawn
		if d.x * d.x + d.y * d.y <= ARRIVAL_R2: return PATH
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
static func nearest(data: Dictionary, near: Vector2i, taken: Dictionary, walk_blocked: Dictionary, rotation := 0) -> Variant:
	var s := size(rotation)
	var offset := Vector2i(s.x / 2, s.y / 2)
	var candidates: Array[Vector2i] = []
	for cell: Dictionary in data.cells:
		if cell.zone == "core": candidates.append(Vector2i(cell.x, cell.y) - offset)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i):
		var da := (a - near + offset).length_squared()
		var db := (b - near + offset).length_squared()
		return da < db or (da == db and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	for at in candidates:
		if reason(data, at, rotation, taken, walk_blocked) == "": return at
	return null

## The footprint's middle on the ground, in scene space.
static func center(walk: RefCounted, at: Vector2i, rotation := 0) -> Vector3:
	var s := size(rotation)
	return (walk.point(at) + walk.point(at + s - Vector2i.ONE)) * 0.5

## The model's transform: its own pivot on the footprint's middle, +Z (the door) toward the camera, a quarter turn
## per rotation step.
static func transform(walk: RefCounted, at: Vector2i, rotation := 0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, rotation * PI * 0.5), center(walk, at, rotation))

static func proxy(walk: RefCounted, at: Vector2i, rotation := 0) -> Proxy:
	return Proxy.new(PROFILE, transform(walk, at, rotation), 1.0)

static func at_of(house: Dictionary) -> Vector2i:
	return Vector2i(int(house.get("x", 0)), int(house.get("y", 0)))

static func _cell(key: String) -> Vector2i:
	var parts := key.split(",")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i(-1, -1)
