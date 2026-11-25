extends SceneTree
## First house (Q-40, C-33): placement rules, the model-fitted wall profile and place_house on C-34's local save.
## C-150: through the per-type building rules (FarmBuilding, the cottage's entry), every footprint check in all four
## turns, and place_building on the local save.
##   godot --headless --path "$QA" --script res://tests/dynamic_farm/test_house.gd -- <farm1.json> <farm2.json> …
## Without payloads it runs the synthetic fixtures only.
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
## The cottage through the building rules (C-150): its art entry and its 3×3 footprint.
const COTTAGE := "cottage"
const BLUEPRINT := "blueprint_cottage"
const SIZE := Vector2i(3, 3)
var KIND: Dictionary = Building.kind(COTTAGE)
const LocalStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
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
	var faces := Art.mesh_for(KIND.asset).get_faces()
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
	var aabb := Art.mesh_for(KIND.asset).get_aabb()
	var half := SIZE.x * 0.8 * 0.5
	_check(absf(aabb.position.x) <= half and aabb.end.x <= half and absf(aabb.position.z) <= half and aabb.end.z <= half,
		"model inside its 3×3 footprint")

func _proxy_at(model: Transform3D) -> RefCounted:
	return Building.Proxy.new(KIND.profile, model, 1.0)

func _footprint() -> void:
	var cells := Building.cells(Vector2i(5, 7), SIZE)
	_check(cells.size() == 9 and cells[0] == Vector2i(5, 7) and cells[-1] == Vector2i(7, 9), "3×3 from its lowest cell")
	var walk := Walk.new(Data.decode(Fixture.farm("p-A")))
	_check(Building.center(walk, Vector2i(5, 7), SIZE).is_equal_approx(walk.point(Vector2i(6, 8))), "model on the middle cell")
	# C-114: the build's dust at the footprint's corners and edge middles (1.2 m out at 0.8 m cells), on the ground.
	var middle := Building.center(walk, Vector2i(5, 7), SIZE)
	var rim := Building.rim(walk, Vector2i(5, 7), SIZE)
	var half := 1.5 * walk.cell_m
	var wanted: Array[Vector3] = []
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx != 0 or dz != 0: wanted.append(middle + Vector3(dx, 0, dz) * half)
	_check(rim.size() == 8 and range(8).all(func(i): return rim[i].is_equal_approx(wanted[i])),
		"dust round the footprint's rim")
	# C-150: a 4×2 footprint (a test size, not a building) turned a quarter or three quarters is 2×4; a turn keeps its
	# middle cell; the model turns a quarter per step about the footprint's middle.
	var wide := Vector2i(4, 2)
	for turns in 4:
		var s := Building.size(wide, turns)
		var at := Building.turned_at(Vector2i(10, 10), wide, 0, turns)
		_check(s == (Vector2i(2, 4) if turns % 2 else wide) and Building.cells(at, wide, turns).size() == 8, "4×2 turned %d: %s" % [turns, s])
		_check(at + Building.middle(wide, turns) == Vector2i(10, 10) + Building.middle(wide, 0), "a turn keeps the middle cell (%d)" % turns)
		var pose := Building.transform(walk, at, wide, turns)
		_check(pose.origin.is_equal_approx(Building.center(walk, at, wide, turns))
			and pose.basis.z.is_equal_approx(Vector3.BACK.rotated(Vector3.UP, turns * PI * 0.5)), "the model turns %d quarter(s)" % turns)
		# The turned cells are exactly the cells under the turned model's 4×2 m-per-cell outline.
		var under := {}
		for x in range(-15, 16):
			for z in range(-15, 16):
				var local := Vector3((x + 0.5) * 0.1 * walk.cell_m, 0, (z + 0.5) * 0.1 * walk.cell_m)
				if absf(local.x) < wide.x * walk.cell_m * 0.5 and absf(local.z) < wide.y * walk.cell_m * 0.5:
					under[walk.cell_at(pose * local)] = true
		_check(under.keys().all(func(c): return Building.cells(at, wide, turns).has(c)) and under.size() == 8,
			"turned %d: the model covers its turned footprint" % turns)

## The house through C-34's save (Q-44), same answers as the server (C-31): the gift once, one house, a blueprint
## spent, the house back after reopening; the house's size and model as the shared rules file says.
func _local_save() -> void:
	var rules := ParcelFarm.rules()
	var cottage: Dictionary = rules.buildings[COTTAGE]
	_check(cottage.model == "cottage" and cottage.blueprint == BLUEPRINT and Building.base_of(cottage) == SIZE and cottage.max == 1,
		"the cottage matches dynamic_farm.json")
	_check(Building.KINDS.keys().all(func(t): return rules.buildings.has(t)) and rules.buildings.keys().all(func(t): return not Building.kind(t).is_empty()),
		"every building type has art and every art entry a rule")
	_check(int(rules.welcome_gift.get(BLUEPRINT, 0)) == 1, "the welcome gift holds one blueprint")
	var dir := "user://test_house_%d" % Time.get_ticks_usec()
	var save := LocalStore.new("p-A", dir)
	var first: Dictionary = save.enter()
	_check(first.granted and int(first.farm.bag.get(BLUEPRINT, 0)) == 1, "first entry gives the blueprint")
	var second: Dictionary = save.enter()
	_check(not second.granted and int(second.farm.bag.get(BLUEPRINT, 0)) == 1, "a second entry gives nothing")
	var placed: Dictionary = save.send(second.farm_version, [{"type":"place_house", "x":4, "y":4, "rotation":0}])
	_check(placed.ok and placed.farm.house.x == 4 and placed.farm.house.y == 4 and not placed.farm.bag.has(BLUEPRINT),
		"placing spends the blueprint and builds at once")
	_check(placed.farm.house.model == "cottage" and placed.farm.house.width == 3 and placed.farm.house.built_at > 0, "cottage 3×3 built now")
	_check(ParcelFarm.building_cells(placed.farm).keys().all(func(c): return Building.cells(Vector2i(4, 4), SIZE).has(c)), "one footprint for save and scene")
	var again: Dictionary = save.send(placed.farm_version, [{"type":"place_house", "x":10, "y":4, "rotation":0}])
	_check(not again.ok and again.code == "HOUSE_PLACED", "only one house")
	var reopened: Dictionary = LocalStore.new("p-A", dir).enter()
	_check(not reopened.granted and int(reopened.farm.house.x) == 4 and int(reopened.farm.house.y) == 4, "reopened: the house in place, no new gift")
	_check(int(reopened.farm.bag.get(BLUEPRINT, 0)) == 0, "reopened: no second blueprint")
	var other := LocalStore.new("p-B", dir)
	var entered: Dictionary = other.enter()
	var tilled: Dictionary = other.send(entered.farm_version, [{"type":"till", "cell":"2,2"}])
	var over: Dictionary = other.send(tilled.farm_version, [{"type":"place_house", "x":1, "y":1, "rotation":0}])
	_check(over.code == "CELL_OCCUPIED", "not over a tilled cell")
	var built: Dictionary = other.send(tilled.farm_version, [{"type":"place_house", "x":5, "y":5, "rotation":0}])
	var none: Dictionary = other.send(built.farm_version, [{"type":"place_house", "x":10, "y":10, "rotation":0}])
	_check(built.ok and none.code == "HOUSE_PLACED", "the blueprint builds once")
	# C-150: the scene's place_building, turned, on a third save; reopened it stands as it was turned.
	var third := LocalStore.new("p-C", dir)
	var opened: Dictionary = third.enter()
	var turned: Dictionary = third.send(opened.farm_version, [{"type":"place_building", "building":COTTAGE, "x":6, "y":3, "rotation":3}])
	var back: Dictionary = LocalStore.new("p-C", dir).enter()
	_check(turned.ok and back.farm.buildings.size() == 1 and back.farm.buildings[0].type == COTTAGE and int(back.farm.buildings[0].rotation) == 3
		and Building.at_of(back.farm.buildings[0]) == Vector2i(6, 3) and back.farm.house.rotation == 3, "a turned cottage reopens turned")
	_check(third.send(turned.farm_version, [{"type":"place_building", "building":COTTAGE, "x":20, "y":3, "rotation":0}]).code == "BUILDING_LIMIT",
		"still one cottage")
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
	# Connection alone (no protected path given).
	_check(Building.reason(data, Vector2i(13,4), SIZE, 0, {}, {}, {}) == Building.PATH, "a house cannot seal the neck")
	_check(Building.reason(data, Vector2i(20,4), SIZE, 0, {}, {}, {}) == "", "the open side takes it")
	# The protected path tilling keeps clear (C-34): the entry–spawn route ±1 cell and the ring round spawn.
	var path := Space.protected_path(data)
	_check(Building.reason(data, Vector2i(20,4), SIZE, 0, {}, path, {}) == Building.PATH, "not on the protected path")
	_check(Building.reason(data, Vector2i(20,0), SIZE, 0, {}, path, {}) == "", "beside the path is fine")
	_check(Building.reason(data, Vector2i(0,1), SIZE, 0, {}, path, {}) == "" and Building.reason(data, Vector2i(1,2), SIZE, 0, {}, path, {}) == Building.PATH,
		"the spawn's ring is kept")

func _parcel(raw: Dictionary) -> void:
	var data := Data.decode(raw)
	_check(data.ok, "valid parcel")
	if not data.ok: return
	var walk := Walk.new(data)
	var planned := Scenery.plan(data, walk)
	Shade.enforce_budget(planned, data, walk)
	var layout: Array = planned.core_obstacles.layout
	var obstacles := {}
	for item: Dictionary in layout: obstacles[item.cell] = true
	var taken := Building.blocked(obstacles, {})
	var walk_blocked: Dictionary = Building.solid(layout, obstacles).merged(walk.reserved)
	var path := Space.protected_path(data)
	_check(not path.is_empty(), "%s: a protected path" % data.block_id)
	# Every footprint position over the grid: outside, obstacle, protected path and sealing are each refused.
	var judged := _judge(data, SIZE, 0, taken, path, walk_blocked, 1)
	var accepted: Array[Vector2i] = judged.accepted
	_check(judged.exact, "%s: every spot judged by core, obstacles, protected path and connection" % data.block_id)
	# C-150: the same rules for a 4×2 footprint (a test size) in each of the four turns, every third spot.
	for turns in 4:
		var wide := _judge(data, Vector2i(4, 2), turns, taken, path, walk_blocked, 3)
		_check(wide.exact, "%s: 4×2 turned %d judged the same way (%d sampled spots valid)" % [data.block_id, turns, wide.accepted.size()])
	_check(accepted.size() >= 3, "%s: room for the house (%d spots)" % [data.block_id, accepted.size()])
	# Every obstacle refuses a house over it; once cleared (gone from obstacle_cells()) it frees its cell and its
	# walk block. Tilled cells and crops take cells.
	var held := 0
	var eligible := 0
	var freed := true
	for item: Dictionary in layout:
		var spot: Vector2i = item.cell - Vector2i.ONE
		if Building.cells(spot, SIZE).all(func(c): return data.by_cell.get(c, {}).get("zone") == "core" and not path.has(c)):
			eligible += 1
			held += 1 if Building.reason(data, spot, SIZE, 0, taken, path, walk_blocked) == Building.TAKEN else 0
		var left := obstacles.duplicate()
		left.erase(item.cell)
		freed = freed and not Building.blocked(left, {}).has(item.cell) and not Building.solid(layout, left).has(item.cell)
	_check(held > 0 and held == eligible, "%s: every obstacle (weeds too) refuses a house over it (%d)" % [data.block_id, held])
	_check(freed, "%s: a cleared obstacle frees its cell" % data.block_id)
	var first: Vector2i = accepted[0]
	var tilled := Building.blocked(obstacles, {"tilled":["%d,%d" % [first.x + 1, first.y + 2]]})
	var crops := Building.blocked(obstacles, {"crops":{"%d,%d" % [first.x, first.y]: {}}})
	_check(Building.reason(data, first, SIZE, 0, tilled, path, walk_blocked) == Building.TAKEN and Building.reason(data, first, SIZE, 0, crops, path, walk_blocked) == Building.TAKEN,
		"%s: tilled cells and crops refuse the house" % data.block_id)
	# C-150: a standing building takes its cells and its walking from the next one.
	var standing := {"buildings": [{"id": 1, "type": COTTAGE, "x": first.x, "y": first.y, "width": 3, "depth": 3, "rotation": 0}]}
	var with_one := Building.blocked(obstacles, standing)
	_check(Building.reason(data, first, SIZE, 0, with_one, path, walk_blocked) == Building.TAKEN
		and Building.cells(first, SIZE).all(func(c): return with_one.has(c)),
		"%s: not on a standing building" % data.block_id)
	var around := walk_blocked.merged(ParcelFarm.building_cells(standing))
	var second := _judge(data, SIZE, 0, with_one, path, around, 1)
	_check(second.exact and second.accepted.all(func(at): return Building.cells(at, SIZE).all(func(c): return not with_one.has(c))),
		"%s: a second building judged with the first standing (%d spots)" % [data.block_id, second.accepted.size()])
	var near = Building.nearest(data, data.spawn, SIZE, taken, path, walk_blocked)
	_check(near != null and Building.reason(data, near, SIZE, 0, taken, path, walk_blocked) == "", "%s: a valid starting spot near spawn" % data.block_id)
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
		var proxy: RefCounted = Building.proxy(trial, COTTAGE, at, SIZE)
		trial.add_prop(proxy)
		var after := _reachable(trial, data)
		var footprint := Building.cells(at, SIZE)
		for cell: Vector2i in before:
			if not after.has(cell) and not footprint.has(cell): sealed += 1
		# Walls alone (no scenery), so only the house can stop the player.
		var bare := Walk.new(data)
		bare.add_prop(Building.proxy(bare, COTTAGE, at, SIZE))
		var c := Building.center(bare, at, SIZE)
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

## Every footprint position over the grid (every `stride`th along x and y): {exact, accepted}. `exact` when each
## spot's reason is the first of outside the core, taken, on the protected path, or sealing a walk cell off.
func _judge(data: Dictionary, base: Vector2i, turns: int, taken: Dictionary, path: Dictionary, walk_blocked: Dictionary,
		stride: int) -> Dictionary:
	var accepted: Array[Vector2i] = []
	var exact := true
	for y in range(-2, data.grid_size.y, stride):
		for x in range(-2, data.grid_size.x, stride):
			var at := Vector2i(x, y)
			var why := Building.reason(data, at, base, turns, taken, path, walk_blocked)
			var footprint := Building.cells(at, base, turns)
			var outside := footprint.any(func(c): return not data.by_cell.has(c) or data.by_cell[c].zone != "core")
			var covered := footprint.any(func(c): return taken.has(c))
			var on_path := footprint.any(func(c): return path.has(c))
			if outside: exact = exact and why == Building.OUTSIDE
			elif covered: exact = exact and why == Building.TAKEN
			elif on_path: exact = exact and why == Building.PATH
			else:
				exact = exact and (why == "") == Building.keeps_open(data, footprint, walk_blocked)
				if why == "": accepted.append(at)
	return {"exact": exact, "accepted": accepted}

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
		var blocked_by_house := Building.Proxy.new(KIND.profile, Transform3D(Basis(), c), 1.0).gap(p) < Walk.BODY_RADIUS + 0.01
		if blocked_by_house and (gap < -0.005 or gap > 0.04):
			print("GAP k=", k, " local=", local, " gap=", gap)
			return false
	return true

## Pushed 6° into a wall face, the player keeps moving along it.
func _slides(walk: RefCounted, c: Vector3) -> bool:
	for side in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var along: Vector3 = side.rotated(Vector3.UP, -PI * 0.5)
		var proxy := Building.Proxy.new(KIND.profile, Transform3D(Basis(), c), 1.0)
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
