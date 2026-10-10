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

## The stall's ten pieces have their own icons (安其拉, 284 2ab958d8), not the sprout stand-in.
func test_every_sold_piece_has_its_icon() -> void:
	for id in P0Decor.items():
		if not bool(P0Decor.item(str(id)).get("buy", false)): continue
		var tex := P0Logic.icon(str(id))
		assert_object(tex).override_failure_message(str(id)).is_not_null()
		assert_str(tex.resource_path).override_failure_message(str(id)).is_equal("res://assets/p0/icons/%s.svg" % id)

## A multi-piece one sent piece by piece (周瑜 on #265): a sent piece stays pending until the view places it, so the next
## spot avoids it; one refused, failed or older than PENDING_MS goes.
func test_a_sent_piece_stays_pending_until_the_view_places_it() -> void:
	var a := {"uid": -1, "id": "deco_path", "x": 12, "y": 0, "rot": 0, "sent": 1000}
	var b := {"uid": -2, "id": "deco_path", "x": 13, "y": 0, "rot": 0, "sent": 1200}
	var placed := [{"uid": 7, "id": "deco_path", "x": 12, "y": 0, "rot": 0}]   # A came back, B not yet
	assert_array(P0FarmDecor.settle_pending([a, b], placed, 1500)).is_equal([b])
	assert_array(P0FarmDecor.settle_pending([a, b], [], 1500)).is_equal([a, b])
	assert_array(P0FarmDecor.settle_pending([a, b], [], 1200 + P0FarmDecor.PENDING_MS + 1)).is_empty()   # stale: gone
	var moved := [{"uid": 7, "id": "deco_path", "x": 12, "y": 0, "rot": 1}]   # same cell, another turn: not this one
	assert_array(P0FarmDecor.settle_pending([a], moved, 1500)).is_equal([a])

## A pending piece is negative and "ignore no piece" is 0 (#265): the first piece sent of a multi-piece one counts as taken
## for the next spot and the preview, it is never mistaken for the piece being moved.
func test_the_first_pending_piece_is_taken_for_the_next_spot() -> void:
	var v := {"decor": {"placed": [{"uid": -1, "id": "deco_path", "x": 8, "y": 1, "rot": 0}], "cap": 20, "stored": {}}}
	assert_str(P0Decor.reason(v, "deco_path", Vector2i(8, 1))).is_equal("Space taken")
	assert_that(P0Decor.nearest_spot(v, "deco_path", 0, Vector2i(9, 1))).is_not_equal(Vector2i(8, 1))
	assert_str(P0Decor.reason(v, "deco_path", Vector2i(8, 1), 0, -1)).is_equal("")   # moving that very piece

## SGODOT-290 stand-ins (上官婉儿's list): eight pieces borrow an existing model, the Scarecrow / Pergola / Recipe Stand
## keep their shapes. Each stands on its footprint's middle, feet on the ground, inside its cells, turned with rot.
func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = m
		while n != root:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		var b: AABB = xf * (m as MeshInstance3D).mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out

func _tris(root: Node3D) -> int:
	var n := 0
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var a := mesh.surface_get_arrays(s)
			n += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n

func test_stand_in_models_stand_in_their_cells() -> void:
	assert_array(P0FarmDecor.MODELS.keys()).contains_exactly_in_any_order(["deco_planter", "deco_lantern", "deco_path",
		"deco_bench", "deco_fence", "deco_birdbath", "deco_fountain", "deco_windmill"])
	for id in P0FarmDecor.MODELS:
		for rot in 2:
			var a: Node3D = auto_free(P0FarmDecor.art(id, rot, 0.65))
			var size := P0Decor.size_of(id, rot)
			var b := _bounds(a)
			assert_float(b.position.y).is_between(-0.02, 0.02)                                   # feet on the ground
			assert_float(b.size.x).is_less_equal(size.x * 0.65 + 0.01)                             # inside its cells …
			assert_float(b.size.z).is_less_equal(size.y * 0.65 + 0.01)
			assert_float(absf(b.get_center().x)).is_less(0.08)                                    # … round their middle
			assert_float(absf(b.get_center().z)).is_less(0.08)
			assert_int(_tris(a)).is_less_equal(4000 if id in ["deco_fountain", "deco_windmill"] else 2000)   # 290's budget
	var bench: Node3D = auto_free(P0FarmDecor.art("deco_bench", 0))
	var turned: Node3D = auto_free(P0FarmDecor.art("deco_bench", 1))
	assert_float(_bounds(bench).size.x).is_greater(_bounds(bench).size.z)   # 2×1 runs along x …
	assert_float(_bounds(turned).size.z).is_greater(_bounds(turned).size.x)   # … and along z once turned
	var crow: Node3D = auto_free(P0FarmDecor.art("deco_scarecrow"))
	assert_bool(crow.find_children("*", "MeshInstance3D", true, false).all(func(m): return (m as MeshInstance3D).mesh is PrimitiveMesh)).is_true()

func test_the_preview_ghosts_its_own_materials() -> void:
	var placed: Node3D = auto_free(P0FarmDecor.art("deco_fountain"))
	var preview: Node3D = auto_free(P0FarmDecor.art("deco_fountain"))
	P0FarmDecor.ghost(preview)
	for m in preview.find_children("*", "MeshInstance3D", true, false):
		var mat := (m as MeshInstance3D).material_override as StandardMaterial3D
		assert_object(mat).is_not_null()
		assert_float(mat.albedo_color.a).is_equal_approx(0.6, 0.001)
	var body := placed.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.name != "Water")
	assert_float(((body[0] as MeshInstance3D).material_override as StandardMaterial3D).albedo_color.a).is_equal(1.0)   # the shared one untouched
	assert_object((body[0] as MeshInstance3D).material_override).is_same(P0FarmDecor.FarmArt.material())
