extends RefCounted
## A bounded L8 painter, not navigation data. Uses decoded cell centres; no save writes.
const Farm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const SIDE := 256
const DIRS := [Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN,
	Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]
var _base: Image
var texture: ImageTexture
var _scale: Vector2
var _parents := {}
var _last_targets: Array
var _grid: Dictionary
var _spawn: Vector2i
var _entry: Vector2i

func _init(data: Dictionary) -> void:
	_grid = data.by_cell
	_spawn = data.spawn
	_entry = data.entry
	var grid_size: Vector2i = data.grid_size
	var size := (grid_size * 2).min(Vector2i(SIDE, SIDE))
	_scale = Vector2(size) / Vector2(grid_size)
	_base = Image.create_empty(size.x, size.y, false, Image.FORMAT_L8)
	for y in size.y:
		for x in size.x:
			var point := Vector2i((Vector2(x + 0.5, y + 0.5) / _scale).floor())
			var cell: Dictionary = _grid.get(point, {})
			if cell.get("surface_id", 1) == 2: _base.set_pixel(x, y, Color.WHITE)
			elif cell.get("zone") == "core": _base.set_pixel(x, y, Color(0.54, 0.54, 0.54))
	texture = ImageTexture.create_from_image(_base)
	update({})

func update(farm: Dictionary) -> void:
	var targets: Array[Vector2i] = [_entry]
	for b: Dictionary in Farm.buildings_of(farm):
		var at := Building.at_of(b)
		var base := Building.base_of(b)
		var turns := int(b.rotation)
		# Positive local Z faces decreasing grid Y at turn zero.
		var front: Vector2i = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][posmod(turns, 4)]
		var door := at + Building.middle(base, turns) + front * (base.y / 2 + 1)
		var apron: Array = Building.apron(str(b.type), at, base, turns).walk
		targets.append(apron[0] if not apron.is_empty() else (door if _grid.has(door) else at))
	# Lead to the nearest bed, not through every furrow on a large established farm.
	var closest := _spawn
	var best := INF
	for key: String in farm.get("tilled", []):
		var cell = Farm.parse_key(key)
		if cell == null: continue
		var d: float = cell.distance_squared_to(_spawn)
		if d < best:
			best = d
			closest = cell
	if best != INF: targets.append(closest)
	if targets == _last_targets: return
	_last_targets.assign(targets)
	var paint := _base.duplicate() as Image
	# A single flood gives all paths; never draws a straight shortcut across a hole.
	if _parents.is_empty():
		_parents[_spawn] = _spawn
		var queue: Array[Vector2i] = [_spawn]
		var i := 0
		while i < queue.size():
			var at := queue[i]
			i += 1
			for dir: Vector2i in DIRS:
				var next := at + dir
				if dir.x != 0 and dir.y != 0 and (not _grid.has(at + Vector2i(dir.x,0)) or not _grid.has(at + Vector2i(0,dir.y))): continue
				if _grid.has(next) and not _parents.has(next):
					_parents[next] = at
					queue.append(next)
	for goal: Vector2i in targets:
		if not _parents.has(goal): continue
		var at := goal
		while at != _spawn:
			var p := (Vector2(at) + Vector2(0.5, 0.5)) * _scale
			var q := (Vector2(_parents[at]) + Vector2(0.5, 0.5)) * _scale
			for step in 4:
				var mid := p.lerp(q, step / 4.0)
				var box := Rect2i(Vector2i(mid - _scale), Vector2i((_scale * 2).ceil()) + Vector2i(2,2)).intersection(Rect2i(Vector2i.ZERO, paint.get_size()))
				for y in range(box.position.y, box.end.y):
					for x in range(box.position.x, box.end.x):
						var dist := ((Vector2(x + 0.5, y + 0.5) - mid) / _scale).length()
						var value := maxf(paint.get_pixel(x,y).r, 1.0 - smoothstep(0.3, 1.1, dist))
						paint.set_pixel(x,y,Color(value,value,value))
			at = _parents[at]
	texture.update(paint)
