extends GdUnitTestSuite
## Yard v2 (v4q(12) ③ ④; the user 11-10 bot 655): the yard grows with the Home level — Lv13 row 19 (the back fence to
## z −13.0), Lv14 columns 19–20 (the east fence to x 13.65) — from content decor.yard.grow, the server's own (#954):
## where decor may stand, the walk grid opened as the level comes, the fence ring, the ground and the scatter's strips.

const STORE := "user://test_p1_yard_grow.json"
const P0Farm := preload("res://scenes/p0/p0_farm.gd")
const Fence := preload("res://scenes/p0/p0_fence.gd")
const GardenScenery := preload("res://scenes/p0/p0_garden_scenery.gd")

var rt: P0Runtime

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

static func _v(level: int, decor := {}) -> Dictionary:
	return {"homestead": {"level": level}, "decor": decor if not decor.is_empty() else {"placed": [], "cap": 99, "stored": {}}}

func test_the_yard_at_each_level() -> void:
	for lv in [1, 12]:
		assert_that(P0Garden.yard_at(lv).walk).is_equal(P0Garden.WALK_RECT)
		assert_dict(P0Garden.yard_at(lv).ring).is_equal(P0Garden.FENCE_RING)
	assert_that(P0Garden.yard_at(13).walk).is_equal(Rect2i(1, -2, 18, 22))
	assert_float(float(P0Garden.yard_at(13).ring.back)).is_equal(-13.0)
	assert_float(float(P0Garden.yard_at(13).ring.east)).is_equal(12.95)
	assert_that(P0Garden.yard_at(14).walk).is_equal(Rect2i(1, -2, 20, 22))
	assert_float(float(P0Garden.yard_at(14).ring.back)).is_equal(-13.0)
	assert_float(float(P0Garden.yard_at(14).ring.east)).is_equal(13.65)
	assert_that(P0Garden.yard_at(17).walk).is_equal(Rect2i(1, -2, 20, 22))

## q(145) ①: the walk ends inside the fence ring at every level — each walk cell inside the ring the level stands.
func test_the_walk_stays_inside_the_ring_at_every_level() -> void:
	var bp := P0Garden.blueprint()
	var half := bp.cell_m * 0.5
	for lv in [1, 13, 14]:
		var y := P0Garden.yard_at(lv)
		var r: Dictionary = y.ring
		var walk: Rect2i = y.walk
		for yy in range(walk.position.y, walk.end.y):
			for x in range(walk.position.x, walk.end.x):
				var p := bp.cell_to_world(Vector2i(x, yy))
				var inside := p.x - half >= float(r.west) - 0.001 and p.x + half <= float(r.east) + 0.001 \
					and p.z - half >= float(r.back) - 0.001 and p.z + half <= float(r.front) + 0.001
				assert_bool(inside).override_failure_message("Lv%d cell %d,%d past the fence" % [lv, x, yy]).is_true()
		# and the ring is no more than a cell past it: the yard's edge is the fence's
		assert_float(float(r.east) - (bp.cell_to_world(Vector2i(walk.end.x - 1, 0)).x + half)).is_less(bp.cell_m)
		assert_float((bp.cell_to_world(Vector2i(0, walk.end.y - 1)).z - half) - float(r.back)).is_less(bp.cell_m)

func test_decor_may_stand_where_the_level_s_yard_reaches() -> void:
	var outside: String = P0Decor.REASONS.decor_outside
	assert_str(P0Decor.reason(_v(12), "deco_planter", Vector2i(2, 19))).is_equal(outside)
	assert_str(P0Decor.reason(_v(13), "deco_planter", Vector2i(2, 19))).is_equal("")
	assert_str(P0Decor.reason(_v(13), "deco_planter", Vector2i(3, 19))).is_equal(P0Decor.REASONS.decor_overlap)   # a rock
	assert_str(P0Decor.reason(_v(13), "deco_planter", Vector2i(19, 14))).is_equal(outside)
	for c in [Vector2i(19, 14), Vector2i(20, 19), Vector2i(19, -2), Vector2i(20, 12)]:
		assert_str(P0Decor.reason(_v(14), "deco_planter", c)).override_failure_message(str(c)).is_equal("")
	assert_str(P0Decor.reason(_v(14), "deco_planter", Vector2i(20, 4))).is_equal(P0Decor.REASONS.decor_overlap)   # a rock
	assert_str(P0Decor.reason(_v(14), "deco_planter", Vector2i(18, 11))).is_equal(outside)   # the field ends at x 18
	assert_that(P0Decor.nearest_spot(_v(14), "deco_planter", 0, Vector2i(21, 16))).is_equal(Vector2i(20, 16))

## 不知火舞's spec v1 三: `Home LvN adds N` points at the first level that adds (view.decor.grows, the server's, the yard's
## cells counted) — Lv8–12 all at Lv13; none above, `Store one to place this`; the next level's formula without it.
func test_the_cap_line_points_at_the_first_level_that_adds() -> void:
	var at := func(lv: int, cap: int, grows) -> Dictionary:
		var d := {"placed": [], "cap": cap, "stored": {}, "grows": grows}
		for i in cap: (d.placed as Array).append({"uid": i + 1, "id": "deco_planter", "x": 0, "y": 0})
		return _v(lv, d)
	assert_str(P0Decor.cap_line(at.call(9, 48, {"level": 13, "adds": 13}))).is_equal("Decor 48/48 · Home Lv13 adds 13")
	assert_str(P0Decor.cap_line(at.call(13, 61, {"level": 14, "adds": 11}))).is_equal("Decor 61/61 · Home Lv14 adds 11")
	assert_str(P0Decor.cap_line(at.call(17, 84, null))).is_equal("Decor 84/84 · Store one to place this")
	var older := _v(3, {"placed": [], "cap": 28, "stored": {}})   # no grows: the next level's formula
	for i in 28: (older.decor.placed as Array).append({"uid": i + 1, "id": "deco_planter", "x": 0, "y": 0})
	assert_str(P0Decor.cap_line(older)).is_equal("Decor 28/28 · Home Lv4 adds 4")

## 不知火舞's spec v1 一 / 二: the What changes row and the HOME-2 line of the level that grows the yard, the server's numbers.
func test_the_level_that_grows_the_yard_says_so() -> void:
	var v := _v(12, {"placed": [], "cap": 48, "stored": {}, "next_cap": 61, "room": 48, "next_room": 61})
	assert_dict(P0Logic.yard_change(v)).is_equal({"icon": "wood", "text": "Decor 61 · Yard +13 spaces", "note": "now 48"})
	v.decor = {"placed": [], "cap": 61, "stored": {}, "next_cap": 72, "room": 61, "next_room": 102}
	assert_str(str(P0Logic.yard_change(v).text)).is_equal("Decor 72 · Yard +41 spaces")
	v.decor = {"placed": [], "cap": 48, "stored": {}, "next_cap": 48, "room": 48, "next_room": 48}
	assert_dict(P0Logic.yard_change(v)).is_empty()                      # Lv9–11: the yard stays
	assert_dict(P0Logic.yard_change(_v(12))).is_empty()                 # an older server's view
	var m := P0Logic.home_moment(_v(14), {"level": 14, "energy": 0, "unlocks": ["fruit_trees"], "yard": {"cap": 72, "spaces": 41}})
	assert_str(str(m.detail).split("\n")[0]).is_equal("Decor 72 · Yard +41 spaces")   # first, before the level's other lines
	assert_bool(str(P0Logic.home_moment(_v(12), {"level": 12, "energy": 0, "unlocks": []}).detail).contains("Yard")).is_false()

func test_the_cells_between_two_walks() -> void:
	var lv13 := P0Farm.yard_cells_between(P0Garden.WALK_RECT, P0Garden.yard_at(13).walk)
	assert_int(lv13.size()).is_equal(18)
	assert_bool(lv13.all(func(c): return c.y == 19)).is_true()
	assert_int(P0Farm.yard_cells_between(P0Garden.yard_at(13).walk, P0Garden.yard_at(14).walk).size()).is_equal(44)
	assert_array(P0Farm.yard_cells_between(P0Garden.WALK_RECT, P0Garden.WALK_RECT)).is_empty()

func _farm() -> Node3D:
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	add_child(rt)
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_farm.gd\"\nfunc _ready() -> void: pass\nfunc _exit_tree() -> void: pass\nfunc _process(_d) -> void: pass\n"
	stub.reload()
	var farm: Node3D = load("res://scenes/p0/p0_farm.tscn").instantiate()
	farm.set_script(stub)
	add_child(farm)
	auto_free(farm)
	farm.rt = rt
	farm.bp = P0Garden.blueprint()
	farm._scenery = GardenScenery.new()
	farm.add_child(farm._scenery)
	farm._scenery.build(farm.bp, "cottage")
	farm._block(farm._scenery.rock_points)
	farm._fence = Fence.new()
	farm.add_child(farm._fence)
	farm._fence.build(farm.bp)
	farm.grid = BlueprintGrid.new(farm.bp)
	return farm

## The level's yard opened as it comes: row 19 walked at Lv13 but for its rocks, the fence ring round it, the strips shown;
## yard_grown says so — not animated for the level the farm opened at, animated for one reached here.
func test_the_farm_opens_the_grown_yard_as_the_level_comes() -> void:
	var farm := _farm()
	var said: Array = []
	farm.yard_grown.connect(func(lv, animate): said.append([lv, animate]))
	farm._sync_yard(_v(12))
	assert_array(said).is_empty()
	assert_bool(farm.bp.is_walkable(Vector2i(2, 19))).is_false()
	farm._sync_yard(_v(13))
	assert_array(said).is_equal([[13, true]])
	assert_bool(farm.bp.is_walkable(Vector2i(2, 19))).is_true()
	assert_bool(farm.grid.astar.is_point_solid(Vector2i(2, 19))).is_false()
	assert_bool(farm.grid.astar.is_point_solid(Vector2i(3, 19))).is_true()    # its rock stays
	assert_bool(farm.grid.astar.is_point_solid(Vector2i(19, 14))).is_true()   # Lv14's
	assert_array(farm.grid.path(Vector2i(13, 17), Vector2i(13, 19))).is_not_empty()   # the old back wall's line walked through
	assert_int(farm._fence.level).is_equal(13)
	assert_bool(farm._scenery._strips[13].visible).is_true()
	assert_bool(farm._scenery._strips[14].visible).is_false()
	assert_bool(farm._scenery._gives_way[14].visible).is_true()   # the shrub on Lv14's field edge, still there
	farm._sync_yard(_v(13))
	assert_int(said.size()).is_equal(1)   # once a level
	farm._sync_yard(_v(14))
	assert_array(said[1]).is_equal([14, true])
	assert_bool(farm.grid.astar.is_point_solid(Vector2i(19, 14))).is_false()
	assert_bool(farm._scenery._gives_way[14].visible).is_false()   # gone: no hedge on the new grass (v4q(12) ④)
	assert_bool(farm.grid.astar.is_point_solid(Vector2i(20, 4))).is_true()   # the field edge's rock
	assert_array(farm.grid.path(P0Garden.ANCHORS.spawn, Vector2i(20, 0))).is_not_empty()
	var fresh := _farm()
	var first: Array = []
	fresh.yard_grown.connect(func(lv, animate): first.append([lv, animate]))
	fresh._sync_yard(_v(14))
	assert_array(first).is_equal([[14, false]])   # a farm opened at Lv14: there at once
	assert_bool(fresh.bp.is_walkable(Vector2i(2, 19))).is_true()
