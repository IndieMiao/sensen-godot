extends GdUnitTestSuite
## Decorate (SGODOT-284): the server judges a spot with content decor.yard; it must agree with the garden the client
## draws (P0Garden), so a piece never stands on a bed, in the house or on a facility the player can see, and the client
## (P0Decor) judges a spot as the server does. Pieces are solid: a yard filled with them still lets the player walk to
## the exit, the door, the stall, the mine mouth, the gathering spots and the workbench (q(120), 不知火舞 49b11f91).

func _yard() -> Dictionary:
	return P0Logic.content().get("decor", {}).get("yard", {})

func _in(list: String, cell: Vector2i) -> bool:
	for r in _yard().get(list, []):
		if Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).has_point(cell): return true
	return false

func test_every_footprint_and_plot_of_the_garden_is_off_the_yard() -> void:
	assert_bool(_yard().is_empty()).is_false()
	for key in P0Garden.FOOTPRINTS:
		var f: Rect2i = P0Garden.FOOTPRINTS[key]
		for y in range(f.position.y, f.end.y):
			for x in range(f.position.x, f.end.x):
				assert_bool(_in("objects", Vector2i(x, y))).override_failure_message("%s at %d,%d" % [key, x, y]).is_true()
	for id in 40:   # P0's 30 and the two P1 columns (q(59)): the field and its walkways
		var grid := Vector2i(id % 6, id / 6) if id < 30 else Vector2i(6 + (id - 30) % 2, (id - 30) / 2)   # #215's grid_of
		var c := P0Garden.PLOT_ORIGIN + grid * 2
		assert_bool(_in("field", c)).override_failure_message("plot %d at %s" % [id, str(c)]).is_true()
	var walk: Array = _yard().get("walk", [])
	assert_that(Rect2i(int(walk[0]), int(walk[1]), int(walk[2]), int(walk[3]))).is_equal(P0Garden.WALK_RECT)
	var bp := P0Garden.blueprint()   # the front fence, the sign, the plaque and the mailbox are objects too
	for p in P0Garden.fence_block_points(bp) + [P0Garden.sign_point(bp), P0Garden.plaque_point(bp), P0Garden.mailbox_point(bp)]:
		var c := bp.world_to_cell(p)
		assert_bool(_in("objects", c) or _in("field", c)).override_failure_message("object at %s" % str(c)).is_true()
	for k in [P0Garden.ANCHORS.spawn, P0Garden.ANCHORS.exit]: assert_bool(_in("paths", k)).is_true()

func test_the_catalog_and_the_stall_shelf_keeps_decor_off_until_its_page() -> void:
	var items: Dictionary = P0Logic.content().get("decor", {}).get("items", {})
	assert_int(items.size()).is_equal(11)
	assert_str(str(items.deco_bench.name)).is_equal("Wooden Bench")
	var v := {"shops": {"homestead": {"buy": [{"id": "seed_radish"}, {"id": "deco_planter"}]}}}
	var d := P0CounterDrawer.new(v, "homestead")
	assert_array(d.offers().map(func(o): return str(o.id))).is_equal(["seed_radish"])
	d.free()

## The same spots as server/test/p0/p1_decor.test.ts, in the bar's words.
func test_a_spot_is_judged_as_the_server_does() -> void:
	var v := {"decor": {"placed": [], "cap": 20, "used": 0, "stored": {}}}
	assert_str(P0Decor.reason(v, "deco_planter", Vector2i(6, 5))).is_equal("Outside your yard")    # the field
	assert_str(P0Decor.reason(v, "deco_planter", Vector2i(0, 18))).is_equal("Outside your yard")   # off the yard
	for at in [Vector2i(9, 16), Vector2i(12, 16), Vector2i(6, 13)]:   # the house, the mailbox, the front fence
		assert_str(P0Decor.reason(v, "deco_planter", at)).override_failure_message(str(at)).is_equal("Space taken")
	for at in [Vector2i(9, 1), Vector2i(10, 0), Vector2i(8, 14), Vector2i(10, 13), Vector2i(13, 14), Vector2i(4, 13), Vector2i(17, 15)]:
		assert_str(P0Decor.reason(v, "deco_planter", at)).override_failure_message(str(at)).is_equal("Keep the path clear")
	assert_str(P0Decor.reason(v, "deco_bench", Vector2i(4, 15))).is_equal("")
	assert_str(P0Decor.reason(v, "deco_bench", Vector2i(4, 14))).is_equal("Keep the path clear")
	v.decor.placed = [{"uid": 1, "id": "deco_bench", "x": 6, "y": 18, "rot": 0}]   # 2 × 1: cells 6–7, 18
	assert_str(P0Decor.reason(v, "deco_planter", Vector2i(7, 18))).is_equal("Space taken")
	assert_str(P0Decor.reason(v, "deco_bench", Vector2i(7, 18), 0, 1)).is_equal("")   # moving the bench itself
	assert_str(P0Decor.reason(v, "deco_pergola", Vector2i(1, 17), 1)).is_equal("")    # turned: 2 wide, 3 tall
	assert_str(P0Decor.reason(v, "deco_pergola", Vector2i(1, 17), 0)).is_equal("Space taken")   # 3 × 2 reaches the herb patch
	assert_that(P0Decor.piece_at(v, Vector2i(7, 18)).get("uid")).is_equal(1)
	assert_that(P0Decor.nearest_spot(v, "deco_planter", 0, Vector2i(9, 1))).is_not_equal(P0Decor.NONE)
	assert_str(P0Decor.reason(v, "deco_planter", P0Decor.nearest_spot(v, "deco_planter", 0, Vector2i(9, 1)))).is_equal("")

func test_rows_cards_and_lines_read_like_q111_and_q113() -> void:
	assert_str(P0Decor.line("deco_lantern")).is_equal("1×1 · Glows at night")
	assert_str(P0Decor.line("deco_bench")).is_equal("2×1 · Visitors can sit")
	assert_str(P0Decor.line("deco_path")).is_equal("5 pieces")
	assert_bool(P0Decor.turns("deco_bench")).is_true()
	assert_bool(P0Decor.turns("deco_windmill")).is_false()
	var v := {"homestead": {"level": 2}, "decor": {"placed": [], "cap": 24, "stored": {}}}
	for i in 12: v.decor.placed.append({"uid": i + 1, "id": "deco_planter", "x": 99, "y": i, "rot": 0})
	assert_str(P0Decor.header_line(v)).is_equal("Decor 12/24 · Goes to Farm Storage")
	for i in 12: v.decor.placed.append({"uid": i + 13, "id": "deco_planter", "x": 98, "y": i, "rot": 0})
	assert_str(P0Decor.cap_line(v)).is_equal("Decor 24/24 · Homestead Lv3 adds 4")
	v.homestead.level = 10
	v.decor.cap = 24
	assert_str(P0Decor.cap_line(v)).is_equal("Decor 24/24 · Store one to place this")

func test_today_offers_a_free_row_while_decor_waits_in_storage() -> void:
	var v := {"decor": {"placed": [], "cap": 20, "stored": {}}}
	assert_dict(P0Decor.today_row(v)).is_empty()
	v.decor.stored = {"deco_planter": 1}
	assert_str(str(P0Decor.today_row(v).line)).is_equal("Place Flower Planter · in storage")
	v.decor.stored = {"deco_planter": 1, "deco_path": 5}
	assert_str(str(P0Decor.today_row(v).line)).is_equal("Place 2 decor · in storage")
	v.decor.cap = 0   # the yard is full: nothing to place
	assert_dict(P0Decor.today_row(v)).is_empty()

## A yard filled with 1 × 1 pieces wherever one may stand: every place the player walks to is still reachable.
func test_a_yard_full_of_decor_walls_nothing_off() -> void:
	var bp := P0Garden.blueprint()
	P0Garden.block_points(bp, P0Garden.fence_block_points(bp))
	P0Garden.block_points(bp, [P0Garden.sign_point(bp), P0Garden.mailbox_point(bp)])
	var grid := BlueprintGrid.new(bp)
	var v := {"decor": {"placed": [], "cap": 999, "stored": {}}}
	var n := 0
	for y in bp.grid.y:
		for x in bp.grid.x:
			if P0Decor.reason(v, "deco_planter", Vector2i(x, y)) != "": continue
			n += 1
			v.decor.placed.append({"uid": n, "id": "deco_planter", "x": x, "y": y, "rot": 0})
			grid.set_solid(Vector2i(x, y), true)
	assert_int(n).is_greater(60)   # plenty of yard is left to decorate
	var from: Vector2i = P0Garden.ANCHORS.spawn
	var reach := func(target: Vector3, within: float) -> bool:
		for y in bp.grid.y:
			for x in bp.grid.x:
				var c := Vector2i(x, y)
				if bp.cell_to_world(c).distance_to(target) > within or grid.astar.is_point_solid(c): continue
				if c == from or not grid.path(from, c).is_empty(): return true
		return false
	var cell := func(c: Vector2i) -> Vector3: return bp.cell_to_world(c)
	assert_bool(reach.call(cell.call(P0Garden.ANCHORS.exit), 0.1)).override_failure_message("the map exit").is_true()
	assert_bool(reach.call(cell.call(Vector2i(9, 14)), 0.1)).override_failure_message("the farmhouse door").is_true()
	assert_bool(reach.call(cell.call(Vector2i(14, 14)), 0.1)).override_failure_message("the stall").is_true()
	assert_bool(reach.call(cell.call(P0Garden.ANCHORS.mine) + Vector3(-0.3, 0, 0.3), P0FarmMaterials.MOUTH_REACH)).override_failure_message("the mine mouth").is_true()
	for id in ["spot_grove", "spot_rock_pile", "spot_reed_bank", "spot_clay_bank", "spot_herb_patch", "workbench"]:
		assert_bool(reach.call(cell.call(P0Garden.ANCHORS[id]), P0FarmMaterials.SPOT_REACH - 0.3)).override_failure_message(id).is_true()

## FARM-6-DECOR (Figma 2187:33369): the stall's Decor page — its tab, its fact line, the rows' four states.
func test_the_stall_decor_page_lists_the_pieces_in_their_states() -> void:
	var v := {"coins": 80, "homestead": {"level": 2}, "rest": {"resets_in": 33120000},
		"decor": {"placed": [], "cap": 24, "used": 0, "stored": {"deco_fence": 6}},
		"shops": {"homestead": {"buy": [
			{"id": "seed_radish", "price": 4},
			{"id": "deco_scarecrow", "price": 80, "need": 80, "homestead": 1, "homestead_ok": true, "left": 1, "daily": 1},
			{"id": "deco_fence", "price": 90, "need": 90, "homestead": 1, "homestead_ok": true, "left": 0, "daily": 1},
			{"id": "deco_birdbath", "price": 120, "need": 120, "homestead": 1, "homestead_ok": true, "left": 1, "daily": 1},
			{"id": "deco_windmill", "price": 250, "need": 250, "homestead": 3, "homestead_ok": false, "left": 1, "daily": 1}]}}}
	for i in 12: v.decor.placed.append({"uid": i + 1, "id": "deco_planter", "x": 99, "y": i, "rot": 0})
	var d := P0CounterDrawer.new(v, "homestead", {}, "decor")
	assert_array(d.offers().map(func(o): return str(o.id))).is_equal(["deco_scarecrow", "deco_fence", "deco_birdbath", "deco_windmill"])
	assert_str(d._decor_line.text).is_equal("Decor 12/24 · Goes to Farm Storage")
	assert_bool(d._decor_line.visible).is_true()
	assert_bool(d._scope.visible).is_false()   # nothing is sold on this page
	d.set_section("buy")
	assert_array(d.offers().map(func(o): return str(o.id))).is_equal(["seed_radish"])
	assert_bool(d._decor_line.visible).is_false()
	d.free()
	var row := func(id: String) -> Array:
		var s := P0ItemInfo.spec(v, id, &"counter_buy", {counter = "homestead"})
		return [s.facts, (s.buttons as Array).map(func(b): return "%s:%s" % [b.kind, b.label])]
	assert_array(row.call("deco_scarecrow")).is_equal([["1×1 · Shoos crows"], ["secondary:Buy"]])
	assert_array(row.call("deco_fence")).is_equal([["6 pieces", "In storage ×6"], ["unavailable:Bought today · 9h 12m"]])
	assert_array(row.call("deco_birdbath")).is_equal([["1×1 · Birds drop by"], ["unavailable:Need 40 more coins"]])
	assert_array(row.call("deco_windmill")).is_equal([["2×2 · Spins in wind", "1 level to go"], ["unavailable:Homestead Lv3 needed"]])

## Spec v2 (284 6a751a9a): a piece taps as at least 44 × 44 at any zoom (the whole yard is about 17 px a cell); the nearest
## centre wins where two grown boxes overlap.
func test_a_small_piece_taps_as_44_px() -> void:
	var boxes := [Rect2(100, 100, 17, 17), Rect2(125, 100, 34, 17)]   # two pieces side by side at the whole-yard zoom
	assert_int(P0FarmDecor.pick_near(boxes, Vector2(108, 108))).is_equal(0)
	assert_int(P0FarmDecor.pick_near(boxes, Vector2(90, 100))).is_equal(0)    # 10 px off a 17 px piece: inside 44
	assert_int(P0FarmDecor.pick_near(boxes, Vector2(80, 100))).is_equal(-1)   # 20 px off: outside
	assert_int(P0FarmDecor.pick_near(boxes, Vector2(122, 108))).is_equal(0)   # in both grown boxes: the nearer centre
	assert_int(P0FarmDecor.pick_near(boxes, Vector2(128, 108))).is_equal(1)
	assert_int(P0FarmDecor.pick_near([Rect2(0, 0, 80, 80)], Vector2(85, 40))).is_equal(-1)   # a big piece is not grown

## The yard's dashed edge goes round the walk rect's outer cell edges, dashes no longer than DASH_M.
func test_the_yard_edge_is_dashed_round_the_walk_rect() -> void:
	var bp := P0Garden.blueprint()
	var dashes := P0FarmDecor.yard_dashes(bp, [1, 0, 19, 20])
	assert_int(dashes.size()).is_greater(40)
	var xs := dashes.map(func(d): return (d[0] as Vector3).x)
	assert_float(xs.min()).is_equal_approx(bp.cell_to_world(Vector2i(1, 0)).x - bp.cell_m * 0.5, 0.001)
	assert_float(xs.max()).is_equal_approx(bp.cell_to_world(Vector2i(19, 0)).x + bp.cell_m * 0.5, 0.001)
	for d in dashes: assert_float(maxf((d[1] as Vector2).x, (d[1] as Vector2).y)).is_less_equal(P0FarmDecor.DASH_M + 0.001)

## The grid round a picked piece is the yard's (不知火舞 on 284): where a piece could stand and the paths, never the field.
func test_the_grid_round_a_piece_is_the_yard_only() -> void:
	var v := {"decor": {"placed": [], "cap": 20, "stored": {}}}
	var halo := P0FarmDecor.halo_cells(v, [Vector2i(12, 1), Vector2i(13, 1)])
	assert_int(halo.size()).is_greater(10)
	for h in halo:
		var c: Vector2i = h[0]
		assert_str(P0Decor.reason(v, "deco_planter", c)).override_failure_message(str(c)).is_not_equal("Outside your yard")
		assert_str(P0Decor.reason(v, "deco_planter", c)).override_failure_message(str(c)).is_not_equal("Space taken")
		assert_int(maxi(absi(c.x - 12), absi(c.y - 1))).is_less_equal(4)
	assert_bool(halo.any(func(h): return (h[0] as Vector2i).y >= 2)).is_false()   # rows 2+ are the field there
	assert_bool(halo.any(func(h): return bool(h[2]))).is_true()                   # the exit path at x 9–10 is in reach
