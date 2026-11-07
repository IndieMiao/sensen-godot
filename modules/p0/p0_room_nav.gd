class_name P0RoomNav
extends RefCounted
## Walkable grid for an indoor P0 space (SGODOT-226): the art's collision shapes (layout colliders and any
## shapes its script adds) are rasterised into a FarmBlueprint walkable mask, inflated by the player radius,
## so the shared P0Actor / PlayerMover walk rooms exactly as they walk the farm and the ponds.
## Blueprint space has x in [0, w] and z in [-h, 0]; `offset` moves the room's own origin into it.

const CELL_M := 0.15        # 0.7 m aisles (SGODOT-218) stay at least 4 cells wide
const RADIUS_M := 0.21      # Basic Room player capsule radius
const FLOOR_MAX_TOP := 0.2  # a shape whose top is this low is floor, not an obstacle
const HEAD_M := 1.8         # shapes entirely above head height do not block

## Footprints of every BoxShape3D / CylinderShape3D under `root` that is not hidden (modules a Homestead level
## hides do not block), in the root's space.
## Each entry: {kind: "box" | "cylinder", xform: Transform3D, size: Vector3, radius: float, height: float}.
static func shapes_from(root: Node3D) -> Array:
	var out: Array = []
	for n in root.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs.disabled or cs.shape == null or not _shown(cs, root): continue
		var xform := _relative(cs, root)
		if cs.shape is BoxShape3D:
			out.append({kind = "box", xform = xform, size = (cs.shape as BoxShape3D).size})
		elif cs.shape is CylinderShape3D:
			var cyl := cs.shape as CylinderShape3D
			out.append({kind = "cylinder", xform = xform, radius = cyl.radius, height = cyl.height})
	return out

static func _shown(n: Node, root: Node) -> bool:
	while n != null and n != root:
		if n is Node3D and not (n as Node3D).visible: return false
		n = n.get_parent()
	return true

## Transform of `n` in `root`'s space, without needing the tree (shapes are read right after instancing).
static func _relative(n: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D: xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

static func _vertical(s: Dictionary) -> Vector2:
	var half := float(s.size.y) * 0.5 if s.kind == "box" else float(s.height) * 0.5
	var y: float = (s.xform as Transform3D).origin.y
	return Vector2(y - half, y + half)

## Builds {bp: FarmBlueprint, offset: Vector3, floor_y: float, bounds: Rect2} from shape footprints.
## The floor is the largest shape whose top is at most FLOOR_MAX_TOP; it also bounds the grid.
static func build(shapes: Array, cell_m := CELL_M, radius := RADIUS_M) -> Dictionary:
	var floor_y := 0.0
	var floor_area := -1.0
	var bounds := Rect2()
	var obstacles: Array = []
	for s in shapes:
		var v := _vertical(s)
		var rect := _footprint(s)
		if v.y <= FLOOR_MAX_TOP:
			if rect.get_area() > floor_area:
				floor_area = rect.get_area()
				floor_y = v.y
				bounds = rect
		else:
			obstacles.append(s)
	obstacles = obstacles.filter(func(s): return _vertical(s).x < floor_y + HEAD_M)
	if floor_area <= 0.0:
		for s in obstacles: bounds = _footprint(s) if bounds.get_area() == 0.0 else bounds.merge(_footprint(s))
	var grid := Vector2i(maxi(1, ceili(bounds.size.x / cell_m)), maxi(1, ceili(bounds.size.y / cell_m)))
	var rows := PackedStringArray()
	for j in grid.y:
		var row := ""
		for i in grid.x:
			# Cell (i, j) centre in room space: blueprint z = -(j + 0.5) * cell counts back from the room's max z.
			var p := Vector2(bounds.position.x + (i + 0.5) * cell_m, bounds.end.y - (j + 0.5) * cell_m)
			row += "0" if _blocked(p, obstacles, radius) else "1"
		rows.append(row)
	var bp := FarmBlueprint.new()
	bp.layout_patch_id = "room"
	bp.cell_m = cell_m
	bp.cell_mm = roundi(cell_m * 1000)
	bp.play_area_m = maxf(bounds.size.x, bounds.size.y)
	bp.play_area_mm = roundi(bp.play_area_m * 1000)
	bp.grid = grid
	bp.masks = {"walkable": rows}
	# Blueprint world x = room x - bounds.x; blueprint world z = room z - bounds.end.y.
	var offset := Vector3(-bounds.position.x, 0.0, -bounds.end.y)
	return {bp = bp, offset = offset, floor_y = floor_y, bounds = bounds}

## Axis-aligned XZ rect around a shape (x, z) for bounds and floor detection.
static func _footprint(s: Dictionary) -> Rect2:
	var xf: Transform3D = s.xform
	if s.kind == "cylinder":
		var r := float(s.radius)
		return Rect2(Vector2(xf.origin.x - r, xf.origin.z - r), Vector2(r * 2.0, r * 2.0))
	var half: Vector3 = s.size * 0.5
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := xf * Vector3(half.x * sx, 0.0, half.z * sz)
			lo = lo.min(Vector2(c.x, c.z))
			hi = hi.max(Vector2(c.x, c.z))
	return Rect2(lo, hi - lo)

## True when the XZ point `p` is within `radius` of any obstacle footprint (boxes may be rotated about Y).
static func _blocked(p: Vector2, obstacles: Array, radius: float) -> bool:
	for s in obstacles:
		var xf: Transform3D = s.xform
		if s.kind == "cylinder":
			if p.distance_to(Vector2(xf.origin.x, xf.origin.z)) < float(s.radius) + radius: return true
			continue
		var local := xf.affine_inverse() * Vector3(p.x, xf.origin.y, p.y)
		var half: Vector3 = s.size * 0.5
		var d := Vector2(maxf(absf(local.x) - half.x, 0.0), maxf(absf(local.z) - half.z, 0.0))
		if d.length() < radius: return true
	return false

## Nearest walkable cell centre (blueprint space) to a blueprint-space point, or Vector3.INF.
## The walkable cell nearest `at` among those a walk from `from` (the room's door) reaches — never a pocket between two
## pews or behind a table that only looks close (Grace Cathedral: up from a pew the player was put in the 0.4 m gap
## between rows and stuck, 李元芳 on 0.3.1). Without a walkable cell near `from`, nearest_walkable.
## `clear`: the cell must have this many walkable cells on every side too (up from a seat: in the open, not wedged in the
## gap between two pews where the front one hides the player — 不知火舞 on #850); none such reached, any reached cell.
## `avoid`: floor points (NPCs) the cell is not hidden behind — within AVOID_M of one, or up to HIDE_DEPTH_M behind one
## along `toward` (the camera's direction over the floor) and HIDE_SIDE_M either side of it: up behind Hana at the tea
## house's third table the player was hidden (不知火舞 on #850).
const AVOID_M := 0.6
const HIDE_DEPTH_M := 2.0
const HIDE_SIDE_M := 0.45
static func nearest_reachable(bp: FarmBlueprint, at: Vector3, from: Vector3, clear := 0, avoid: Array = [],
		toward := Vector3.ZERO) -> Vector3:
	if clear > 0 or not avoid.is_empty():
		var open := _nearest_reached(bp, at, from, clear, avoid, toward)
		if open != Vector3.INF: return open
	return _nearest_reached(bp, at, from, 0, [], toward)

static func hidden(w: Vector3, avoid: Array, toward: Vector3) -> bool:
	var dir := Vector2(toward.x, toward.z).normalized()
	for a in avoid:
		var v := Vector2((a as Vector3).x - w.x, (a as Vector3).z - w.z)
		if v.length() < AVOID_M: return true
		var depth := v.dot(dir)
		if dir != Vector2.ZERO and depth > 0.0 and depth < HIDE_DEPTH_M and absf(v.cross(dir)) < HIDE_SIDE_M: return true
	return false

static func _open(bp: FarmBlueprint, c: Vector2i, clear: int) -> bool:
	for j in range(-clear, clear + 1):
		for i in range(-clear, clear + 1):
			if not bp.is_walkable(c + Vector2i(i, j)): return false
	return true

static func _nearest_reached(bp: FarmBlueprint, at: Vector3, from: Vector3, clear: int, avoid: Array, toward: Vector3) -> Vector3:
	var origin := nearest_walkable(bp, from)
	if origin == Vector3.INF: return nearest_walkable(bp, at) if clear == 0 and avoid.is_empty() else Vector3.INF
	var start := bp.world_to_cell(origin)
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var best := Vector3.INF
	var best_d := INF
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		var w := bp.cell_to_world(c)
		var d := Vector2(w.x - at.x, w.z - at.z).length()
		if d < best_d and (clear == 0 or _open(bp, c, clear)) and not hidden(w, avoid, toward):
			best_d = d
			best = w
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + step
			if seen.has(n) or not bp.is_walkable(n): continue
			seen[n] = true
			queue.append(n)
	return best

static func nearest_walkable(bp: FarmBlueprint, at: Vector3) -> Vector3:
	var start := bp.world_to_cell(at)
	var best := Vector3.INF
	var best_d := INF
	for r in maxi(bp.grid.x, bp.grid.y):
		for j in range(start.y - r, start.y + r + 1):
			for i in range(start.x - r, start.x + r + 1):
				if maxi(absi(i - start.x), absi(j - start.y)) != r: continue
				var c := Vector2i(i, j)
				if not bp.is_walkable(c): continue
				var w := bp.cell_to_world(c)
				var d := Vector2(w.x - at.x, w.z - at.z).length()
				if d < best_d:
					best_d = d
					best = w
		if best != Vector3.INF: return best
	return best
