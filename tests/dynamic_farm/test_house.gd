extends SceneTree
## First house (Q-40, C-33): placement rules, the model-fitted wall profile and the local save stand-in.
##   godot --headless --path "$QA" --script res://tests/dynamic_farm/test_house.gd -- <farm1.json> <farm2.json> …
## Without payloads it runs the synthetic fixtures only.
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const House = preload("res://modules/dynamic_farm/farm_house.gd")
const Local = preload("res://modules/dynamic_farm/parcel_farm_local.gd")
const Fixture = preload("res://tests/dynamic_farm/selection_fixtures.gd")
const Outline = preload("res://tests/dynamic_farm/prop_outline.gd")
const Art = preload("res://modules/farm/farm_art.gd")
const LATTICE_SAMPLES := 12  # accepted spots per parcel re-checked against the real walker
var checks := 0
var failures := 0
var walls := PackedVector2Array()  # the cottage's wall/plinth outline at 0.2 m (convex)

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL " + label)

func _run() -> void:
	var faces := Art.mesh_for(House.ASSET).get_faces()
	walls = Geometry2D.convex_hull(Outline.slice(faces, 0.2))
	_profile(faces)
	_footprint()
	_local_save()
	_pinch()
	_parcel(Fixture.farm("p-A"))
	for path in OS.get_cmdline_user_args():
		_parcel(JSON.parse_string(FileAccess.get_file_as_string(path)))
	print("DYNAMIC_HOUSE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

## The box sits on the walls and plinth: every wall point between 0.15 and 1.1 m lies within 3 cm of it, and the
## whole model stays inside the 3×3 footprint.
func _profile(faces: PackedVector3Array) -> void:
	var proxy := _proxy_at(Transform3D.IDENTITY)
	var worst := 0.0
	for h in [0.15, 0.2, 0.3, 0.4, 0.6, 0.8, 1.0, 1.1]:
		for p in Geometry2D.convex_hull(Outline.slice(faces, h)):
			# Bench, woodpile and window boxes reach past the walls; only the wall/plinth hull is compared.
			if absf(p.x) > 0.89 or p.y > 0.89 or p.y < -0.86: continue
			worst = maxf(worst, proxy.gap(Vector3(p.x, 0, p.y)))
	_check(worst <= 0.03, "wall points within 3 cm of the profile (%.3f)" % worst)
	var aabb := Art.mesh_for(House.ASSET).get_aabb()
	var half := House.SIZE.x * 0.8 * 0.5
	_check(absf(aabb.position.x) <= half and aabb.end.x <= half and absf(aabb.position.z) <= half and aabb.end.z <= half,
		"model inside its 3×3 footprint")

func _proxy_at(model: Transform3D) -> RefCounted:
	return House.Proxy.new(House.PROFILE, model, 1.0)

func _footprint() -> void:
	var cells := House.cells(Vector2i(5, 7))
	_check(cells.size() == 9 and cells[0] == Vector2i(5, 7) and cells[-1] == Vector2i(7, 9), "3×3 from its lowest cell")
	var walk := Walk.new(Data.decode(Fixture.farm("p-A")))
	_check(House.center(walk, Vector2i(5, 7)).is_equal_approx(walk.point(Vector2i(6, 8))), "model on the middle cell")

## Same answers as the server (C-31): the gift once, one house, a blueprint spent, the house back after reopening.
func _local_save() -> void:
	var dir := "user://test_house_%d" % Time.get_ticks_usec()
	var save := Local.new("p-A", dir)
	var replies: Array = []
	save.enter(func(r): replies.append(r))
	_check(replies[0].granted and replies[0].farm.bag == {"hoe_starter":1, "seed_carrot":3, "blueprint_cottage":1}, "first entry gives the gift")
	save.enter(func(r): replies.append(r))
	_check(not replies[1].granted and replies[1].farm.bag.blueprint_cottage == 1, "a second entry gives nothing")
	save.place_house(4, 4, 0, func(r): replies.append(r))
	_check(replies[2].ok and replies[2].farm.house.x == 4 and replies[2].farm.house.y == 4 and not replies[2].farm.bag.has("blueprint_cottage"),
		"placing spends the blueprint and builds at once")
	_check(replies[2].farm.house.model == "cottage" and replies[2].farm.house.width == 3 and replies[2].farm.house.built_at > 0, "cottage 3×3 built now")
	save.place_house(10, 4, 0, func(r): replies.append(r))
	_check(not replies[3].ok and replies[3].code == "HOUSE_PLACED", "only one house")
	var reopened := Local.new("p-A", dir)
	reopened.enter(func(r): replies.append(r))
	_check(not replies[4].granted and int(replies[4].farm.house.x) == 4 and int(replies[4].farm.house.y) == 4, "reopened: the house in place, no new gift")
	_check(int(replies[4].farm.bag.get("blueprint_cottage", 0)) == 0, "reopened: no second blueprint")
	var other := Local.new("p-B", dir)
	other.farm.welcomed_at = 1
	other.place_house(1, 1, 0, func(r): replies.append(r))
	_check(replies[5].code == "NO_BLUEPRINT", "no blueprint, no house")
	other.farm.bag = {"blueprint_cottage":1}
	other.farm.tilled = ["2,2"]
	other.place_house(1, 1, 0, func(r): replies.append(r))
	_check(replies[6].code == "CELL_OCCUPIED", "not over a tilled cell")
	for name in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)

## Two core blocks joined by a three-cell-wide neck, void on both sides: a house filling the neck would seal one
## side off.
func _pinch() -> void:
	var data := {"cell_m":0.8, "grid_size":Vector2i(30,11), "spawn":Vector2i(3,5), "entry":Vector2i(26,5),
		"cells":[], "by_cell":{}}
	for y in 11:
		for x in 30:
			if x >= 12 and x < 18 and (y < 4 or y > 6): continue
			var cell := {"x":x, "y":y, "zone":"core"}
			data.cells.append(cell)
			data.by_cell[Vector2i(x,y)] = cell
	_check(House.reason(data, Vector2i(13,4), 0, {}, {}) == House.PATH, "a house cannot seal the neck")
	_check(House.reason(data, Vector2i(20,4), 0, {}, {}) == "", "the open side takes it")
	_check(House.reason(data, Vector2i(2,4), 0, {}, {}) == House.PATH, "not on the arrival cells")

func _parcel(raw: Dictionary) -> void:
	var data := Data.decode(raw)
	_check(data.ok, "valid parcel")
	if not data.ok: return
	var walk := Walk.new(data)
	var planned := Scenery.plan(data, walk)
	Shade.enforce_budget(planned, data, walk)
	var obstacles: Array = planned.core_obstacles.layout
	var solid := {}
	var taken := House.blocked(obstacles, {}, solid)
	var walk_blocked: Dictionary = solid.merged(walk.reserved)
	# Every footprint position over the grid: outside, obstacle, arrival and sealing are each refused.
	var accepted: Array[Vector2i] = []
	var exact := true
	for y in range(-2, data.grid_size.y):
		for x in range(-2, data.grid_size.x):
			var at := Vector2i(x, y)
			var why := House.reason(data, at, 0, taken, walk_blocked)
			var footprint := House.cells(at)
			var outside := footprint.any(func(c): return not data.by_cell.has(c) or data.by_cell[c].zone != "core")
			var covered := footprint.any(func(c): return taken.has(c))
			var arrival := footprint.any(func(c): return (c - data.spawn).length_squared() <= House.ARRIVAL_R2)
			if outside: exact = exact and why == House.OUTSIDE
			elif covered: exact = exact and why == House.TAKEN
			elif arrival: exact = exact and why == House.PATH
			else:
				exact = exact and (why == "") == House.keeps_open(data, footprint, walk_blocked)
				if why == "": accepted.append(at)
	_check(exact, "%s: every spot judged by core, obstacles, arrival and connection" % data.block_id)
	_check(accepted.size() >= 3, "%s: room for the house (%d spots)" % [data.block_id, accepted.size()])
	# Clearing an obstacle (C-34) frees its cells; tilled cells and crops take them.
	var held := 0
	var freed := true
	for item: Dictionary in obstacles:
		var spot: Vector2i = item.cell - Vector2i.ONE
		var footprint := House.cells(spot)
		if footprint.any(func(c): return data.by_cell.get(c, {}).get("zone") != "core" or (c - data.spawn).length_squared() <= House.ARRIVAL_R2):
			continue
		held += 1 if House.reason(data, spot, 0, taken, walk_blocked) == House.TAKEN else 0
		var cleared := House.blocked(obstacles, {"cleared":["%d,%d" % [item.cell.x, item.cell.y]]})
		freed = freed and not cleared.has(item.cell) and cleared.size() == taken.size() - 1
	_check(held > 0 and held == obstacles.filter(func(o): return House.cells(o.cell - Vector2i.ONE).all(
		func(c): return data.by_cell.get(c, {}).get("zone") == "core" and (c - data.spawn).length_squared() > House.ARRIVAL_R2)).size(),
		"%s: every obstacle (weeds too) refuses a house over it (%d)" % [data.block_id, held])
	_check(freed, "%s: a cleared obstacle frees its cell" % data.block_id)
	var first: Vector2i = accepted[0]
	var tilled := House.blocked(obstacles, {"tilled":["%d,%d" % [first.x + 1, first.y + 2]]})
	var crops := House.blocked(obstacles, {"crops":{"%d,%d" % [first.x, first.y]: {}}})
	_check(House.reason(data, first, 0, tilled, walk_blocked) == House.TAKEN and House.reason(data, first, 0, crops, walk_blocked) == House.TAKEN,
		"%s: tilled cells and crops refuse the house" % data.block_id)
	var near = House.nearest(data, data.spawn, taken, walk_blocked)
	_check(near != null and House.reason(data, near, 0, taken, walk_blocked) == "", "%s: a valid starting spot near spawn" % data.block_id)
	# Against the real walker: an accepted house cuts no reachable walk point off; the player walks along its walls
	# and stops at them.
	var art := Scenery.build(planned, walk)
	var core_art := Scenery.build(planned.core_obstacles, walk)
	var before := _reachable(walk, data)
	var step := maxi(1, accepted.size() / LATTICE_SAMPLES)
	var sealed := 0
	var contact_ok := true
	var slide_ok := true
	var samples := 0
	for i in range(0, accepted.size(), step):
		var at: Vector2i = accepted[i]
		var trial := Walk.new(data)
		trial.reserved = walk.reserved
		trial._proxies_by_cell = walk._proxies_by_cell.duplicate(true)
		var proxy: RefCounted = House.proxy(trial, at)
		trial.add_prop(proxy)
		var after := _reachable(trial, data)
		var footprint := House.cells(at)
		for cell: Vector2i in before:
			if not after.has(cell) and not footprint.has(cell): sealed += 1
		# Walls alone (no scenery), so only the house can stop the player.
		var bare := Walk.new(data)
		bare.add_prop(House.proxy(bare, at))
		var c := House.center(bare, at)
		contact_ok = contact_ok and _contacts(bare, c)
		slide_ok = slide_ok and _slides(bare, c)
		samples += 1
	_check(sealed == 0, "%s: %d sampled houses cut %d walk cells off" % [data.block_id, samples, sealed])
	_check(contact_ok, "%s: approaches stop at the walls, never inside" % data.block_id)
	_check(slide_ok, "%s: walking into a wall at a slant slides along it" % data.block_id)
	art.root.free()
	core_art.root.free()
	print("HOUSE parcel=%s core=%d obstacles=%d spots=%d sampled=%d near=%s" % [data.block_id, data.counts.core,
		obstacles.size(), accepted.size(), samples, near])

## From 16 directions 3 m out, walk straight at the middle: where nothing else stops the player first, it stops
## with its body touching the walls (gap to the wall outline 0–4 cm; the plinth's chamfered corners leave the most),
## never inside them.
func _contacts(walk: RefCounted, c: Vector3) -> bool:
	for k in 16:
		var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 16.0)
		var start := c - d * 2.4
		if not walk.clear_position(start): continue
		walk.position = start
		for i in 60: walk.move(d * 0.06)
		var p: Vector3 = walk.position
		var local := Vector2(p.x - c.x, p.z - c.z)
		if Geometry2D.is_point_in_polygon(local, walls):
			print("INSIDE k=", k, " local=", local)
			return false
		var gap := _distance_to(walls, local) - Walk.BODY_RADIUS
		var blocked_by_house := House.Proxy.new(House.PROFILE, Transform3D(Basis(), c), 1.0).gap(p) < Walk.BODY_RADIUS + 0.01
		if blocked_by_house and (gap < -0.005 or gap > 0.04):
			print("GAP k=", k, " local=", local, " gap=", gap)
			return false
	return true

## Pushed 6° into a wall face, the player keeps moving along it.
func _slides(walk: RefCounted, c: Vector3) -> bool:
	for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var along: Vector3 = side.rotated(Vector3.UP, -PI * 0.5)
		var proxy := House.Proxy.new(House.PROFILE, Transform3D(Basis(), c), 1.0)
		var start: Vector3 = proxy.pose.origin + side * (proxy.reach(side) + Walk.BODY_RADIUS + 0.01) - along * 0.9
		if not walk.clear_position(start): continue
		walk.position = start
		var heading: Vector3 = (along * cos(deg_to_rad(6.0)) - side * sin(deg_to_rad(6.0))).normalized()
		var moved := 0.0
		for i in 10:
			var was: Vector3 = walk.position
			walk.move(heading * 0.05)
			moved += (walk.position - was).dot(along)
		var touched := proxy.gap(walk.position) < Walk.BODY_RADIUS + 0.01
		if not touched or moved < 0.45:
			print("SLIDE side=", side, " moved=", moved, " at=", walk.position - c)
			return false
	return true

static func _distance_to(polygon: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best

## Cells holding a walker-reachable point of a 0.2 m lattice, flooded from spawn (as test_core_obstacles.gd).
func _reachable(walk: RefCounted, data: Dictionary) -> Dictionary:
	var clear := {}
	for cell: Vector2i in data.by_cell:
		for sy in 4:
			for sx in 4:
				if walk.clear_position(walk.point(cell) + Vector3((sx-1.5)*0.2,0,-(sy-1.5)*0.2)):
					clear[cell*4+Vector2i(sx,sy)] = true
	var queue: Array[Vector2i] = []
	for sy in 4:
		for sx in 4:
			if clear.has(data.spawn*4+Vector2i(sx,sy)): queue.append(data.spawn*4+Vector2i(sx,sy))
	var seen := {}
	for key in queue: seen[key] = true
	var index := 0
	while index < queue.size():
		var key := queue[index]
		index += 1
		for offset: Vector2i in Walk.NEIGHBORS:
			if clear.has(key+offset) and not seen.has(key+offset):
				seen[key+offset] = true
				queue.append(key+offset)
	var cells := {}
	for key: Vector2i in seen: cells[Vector2i(key.x/4,key.y/4)] = true
	return cells
