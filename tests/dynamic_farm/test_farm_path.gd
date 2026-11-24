extends SceneTree
## C-73 routes on the dynamic farm walker: around a wall through its gap, never through a gap
## the body does not fit, none to a cut-off island; stand cells prefer sides. On each r4 parcel
## passed after `--` (with all scenery bound), routes from the arrival to core cells keep the
## body clear along every leg and the walker really follows them to the goal.
const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const FarmPath = preload("res://modules/dynamic_farm/farm_path.gd")
const Proxy = preload("res://modules/dynamic_farm/farm_prop_proxy.gd")
const SPEED := 3.75
var checks := 0
var failures := 0
var parcels := 0
var routes := 0
var slowest_ms := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, name: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + name)

func _run() -> void:
	_synthetic()
	for path in OS.get_cmdline_user_args():
		if path.ends_with(".json"): _parcel(path)
	print("DYNAMIC_PATH_TESTS parcels=%d routes=%d slowest_ms=%d checks=%d failures=%d" % [parcels, routes, slowest_ms, checks, failures])
	quit(1 if failures else 0)

## 14×8 cells plus a 2×2 island two cells off; a post wall across x=6 with one gap.
func _grid(gap_y: int, post_radius: float) -> RefCounted:
	var by_cell := {}
	for y in 8:
		for x in 14: by_cell[Vector2i(x, y)] = {"zone": "core"}
	for y in [3, 4]:
		for x in [16, 17]: by_cell[Vector2i(x, y)] = {"zone": "core"}
	var walk := Walk.new({"cell_m": 0.8, "grid_size": Vector2i(18, 8), "spawn": Vector2i(2, 2), "by_cell": by_cell})
	for y in 8:
		if y == gap_y: continue
		walk.add_prop(Proxy.new({"shape": "cylinder", "radius_m": post_radius, "height_m": 1.0, "center_xz_m": [0, 0], "solid": true},
			Transform3D(Basis(), walk.point(Vector2i(6, y))), 1.0))
	return walk

func _synthetic() -> void:
	var walk := _grid(7, 0.4)
	var paths := FarmPath.new(walk)
	var stands := paths.stand_cells([Vector2i(10, 2)])
	_check(stands.size() == 8 and not stands.has(Vector2i(10, 2)), "stand cells: the eight neighbours, not the target")
	_check(stands[Vector2i(9, 2)] == 0.0 and stands[Vector2i(9, 1)] > 0.0, "sides cost less than corners")
	var post_stands := paths.stand_cells([Vector2i(7, 3)])
	_check(not post_stands.has(Vector2i(6, 3)) and not post_stands.has(Vector2i(6, 2)), "a post's cell is no place to stand")
	var block := paths.stand_cells([Vector2i(10, 4), Vector2i(11, 4), Vector2i(10, 5), Vector2i(11, 5)])
	_check(block.size() == 12 and not block.has(Vector2i(11, 5)), "a 2×2 block: the twelve cells around it")
	var from: Vector3 = walk.point(Vector2i(2, 2))
	var route := paths.route(from, stands)
	_check(not route.is_empty(), "a route around the wall")
	_check(stands.has(walk.cell_at(route.back())) and route.back() == walk.point(walk.cell_at(route.back())), "it ends on a stand cell's centre")
	var through_gap := false
	for p in route: through_gap = through_gap or walk.cell_at(p).y == 7
	_check(through_gap, "it goes through the gap")
	_check(_legs_clear(paths, from, route), "the body fits along every leg")
	_check(_follow(walk, route), "the walker follows it to the end")
	# Too narrow for the body: posts of 0.55 m leave the gap cell's centre blocked too.
	var narrow := _grid(7, 0.55)
	_check(FarmPath.new(narrow).route(narrow.point(Vector2i(2, 2)), FarmPath.new(narrow).stand_cells([Vector2i(10, 2)])).is_empty(),
		"no route through a gap the body does not fit")
	var island := FarmPath.new(walk)
	_check(island.route(from, island.stand_cells([Vector2i(16, 3)])).is_empty(), "no route to a cut-off island")
	_check(paths.route(from, {}).is_empty(), "no goals, no route")
	# Off-centre start right against a post.
	var tight: Vector3 = walk.point(Vector2i(5, 3)) + Vector3(0.05, 0, 0.1)
	_check(walk.clear_position(tight), "fixture: a tight but clear start")
	var from_tight := paths.route(tight, stands)
	_check(not from_tight.is_empty() and _legs_clear(paths, tight, from_tight), "routes start from off-centre positions")

func _parcel(path: String) -> void:
	var data = Data.decode(JSON.parse_string(FileAccess.get_file_as_string(path)))
	_check(data.ok, "decode " + path.get_file())
	if not data.ok: return
	var walk := Walk.new(data)
	var plan := Scenery.plan(data, walk)
	_check(plan.ok, "scenery plan " + path.get_file())
	if not plan.ok: return
	Shade.enforce_budget(plan, data, walk)
	var art := Scenery.build(plan, walk, plan.recipe)
	var core := Scenery.build(plan.core_obstacles, walk, plan.recipe)
	_check(art.ok and core.ok, "scenery bound " + path.get_file())
	if not art.ok or not core.ok: return
	parcels += 1
	var paths := FarmPath.new(walk)
	var from: Vector3 = walk.point(data.spawn)
	var cores: Array[Vector2i] = []
	for cell: Dictionary in data.cells:
		if cell.zone == "core": cores.append(Vector2i(cell.x, cell.y))
	# Every obstacle, then an even spread of plain core cells.
	var targets: Array = []
	for item: Dictionary in plan.core_obstacles.layout: targets.append(item.get("cells", [item.cell]))
	for i in range(0, cores.size(), maxi(1, cores.size() / 24)): targets.append([cores[i]])
	var reached := 0
	var tried := 0
	var clear := true
	var followed := true
	var ends_on_stand := true
	for cells: Array in targets:
		var stands := paths.stand_cells(cells)
		if stands.is_empty(): continue
		var started := Time.get_ticks_msec()
		var route := paths.route(from, stands)
		slowest_ms = maxi(slowest_ms, Time.get_ticks_msec() - started)
		routes += 1
		tried += 1
		if route.is_empty():
			print("unreached ", path.get_file(), " ", cells, " stands=", stands.keys())
			continue
		reached += 1
		ends_on_stand = ends_on_stand and stands.has(walk.cell_at(route.back()))
		clear = clear and _legs_clear(paths, from, route)
		followed = followed and _follow(walk, route)
		walk.position = from
	_check(reached > 0 and reached == tried, "every core target with a stand cell is reachable on " + path.get_file())
	_check(ends_on_stand, "routes end on a stand cell on " + path.get_file())
	_check(clear, "the body fits along every leg on " + path.get_file())
	_check(followed, "the walker follows every route on " + path.get_file())
	_check(slowest_ms < 2000, "routes are quick to find")
	art.root.free()
	core.root.free()

func _legs_clear(paths: RefCounted, from: Vector3, route: Array[Vector3]) -> bool:
	var at := from
	for p in route:
		if not paths.segment_clear(at, p): return false
		at = p
	return true

## Walks the route the way the scene does (fixed 60 Hz steps at walking speed).
func _follow(walk: RefCounted, route: Array[Vector3]) -> bool:
	for p in route:
		var guard := 0
		while walk.position.distance_to(p) > 0.02 and guard < 2000:
			var to: Vector3 = p - walk.position
			walk.move(to.limit_length(SPEED / 60.0))
			guard += 1
		if walk.position.distance_to(p) > 0.02: return false
	return true
