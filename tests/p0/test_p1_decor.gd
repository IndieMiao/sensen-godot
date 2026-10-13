extends GdUnitTestSuite
const P0Farm := preload("res://scenes/p0/p0_farm.gd")
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
	assert_that(Rect2i(int(walk[0]), int(walk[1]), int(walk[2]), int(walk[3]))).is_equal(P0Garden.WALK_RECT)   # q(145)
	var bp := P0Garden.blueprint()   # the front fence, the sign, the plaque and the mailbox are objects too
	for p in P0Garden.fence_block_points(bp) + [P0Garden.sign_point(bp), P0Garden.plaque_point(bp), P0Garden.mailbox_point(bp),
			P0Garden.chef_sign_point(bp)]:
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
	assert_str(P0Decor.reason(v, "deco_bench", Vector2i(3, 14))).is_equal("Keep the path clear")   # (4, 14) would reach the Chef's Sign's cell
	v.decor.placed = [{"uid": 1, "id": "deco_bench", "x": 6, "y": 18, "rot": 0}]   # 2 × 1: cells 6–7, 18
	assert_str(P0Decor.reason(v, "deco_planter", Vector2i(7, 18))).is_equal("Space taken")
	assert_str(P0Decor.reason(v, "deco_bench", Vector2i(7, 18), 0, 1)).is_equal("")   # moving the bench itself
	assert_str(P0Decor.reason(v, "deco_pergola", Vector2i(1, 16), 1)).is_equal("")    # turned: 2 wide, 3 tall
	assert_str(P0Decor.reason(v, "deco_pergola", Vector2i(4, 17), 1)).is_equal("Outside your yard")   # its third row: behind the back fence
	assert_str(P0Decor.reason(v, "deco_pergola", Vector2i(4, 17), 0)).is_equal("Space taken")   # 3 × 2 reaches the tree at (6, 17)
	assert_that(P0Decor.piece_at(v, Vector2i(7, 18)).get("uid")).is_equal(1)
	assert_that(P0Decor.nearest_spot(v, "deco_planter", 0, Vector2i(9, 1))).is_not_equal(P0Decor.NONE)
	assert_str(P0Decor.reason(v, "deco_planter", P0Decor.nearest_spot(v, "deco_planter", 0, Vector2i(9, 1)))).is_equal("")

func test_rows_cards_and_lines_read_like_q111_and_q113() -> void:
	assert_str(P0Decor.line("deco_lantern")).is_equal("1×1 · Classic lamp")
	assert_str(P0Decor.line("deco_bench")).is_equal("2×1 · A sunny seat")
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
	assert_array(row.call("deco_scarecrow")).is_equal([["1×1 · Keeps watch"], ["secondary:Buy"]])
	assert_array(row.call("deco_fence")).is_equal([["6 pieces", "In storage ×6"], ["unavailable:Bought today · 9h 12m"]])
	assert_array(row.call("deco_birdbath")).is_equal([["1×1 · Bluebird perch"], ["unavailable:Need 40 more coins"]])
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

## SGODOT-290: every piece sold has 刘备's model (the Recipe Stand, a reward, keeps its shape). Each stands on its
## footprint's middle, feet on the ground, inside its cells (the kit's two exceptions: the Fence's half posts meet at
## the seam, the Scarecrow's hands reach 0.85), turned with rot, within the brief's triangle budget.
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

const BUDGET := {"deco_fence": 500, "deco_path": 500, "deco_fountain": 4000, "deco_windmill": 4000}   # else 2000

func test_every_piece_has_its_model_in_its_cells() -> void:
	var sold: Array = (P0Logic.content().get("decor", {}).get("items", {}) as Dictionary).keys().filter(func(id): return str(id).begins_with("deco_"))
	assert_int(sold.size()).is_equal(10)
	assert_bool(P0FarmDecor.has_model("recipe_stand")).is_false()
	for id in sold:
		assert_bool(P0FarmDecor.has_model(id)).override_failure_message(id).is_true()
		for rot in 2:
			var a: Node3D = auto_free(P0FarmDecor.art(id, rot, 0.65))
			var size := P0Decor.size_of(id, rot)
			var b := _bounds(a)
			var reach := 0.85 if id == "deco_scarecrow" else size.x * 0.65   # the hands' allowed reach (the kit's README)
			var deep := 0.85 if id == "deco_scarecrow" else size.y * 0.65
			assert_float(b.position.y).override_failure_message(id).is_between(-0.01, 0.01)       # feet on the ground
			assert_float(b.size.x).override_failure_message("%s %d" % [id, rot]).is_less_equal(reach + 0.001)
			assert_float(b.size.z).override_failure_message("%s %d" % [id, rot]).is_less_equal(deep + 0.001)
			assert_float(absf(b.get_center().x)).override_failure_message(id).is_less(0.08)
			assert_float(absf(b.get_center().z)).override_failure_message(id).is_less(0.08)
			assert_int(_tris(a)).override_failure_message(id).is_less_equal(int(BUDGET.get(id, 2000)))
	var bench: Node3D = auto_free(P0FarmDecor.art("deco_bench", 0))
	var turned: Node3D = auto_free(P0FarmDecor.art("deco_bench", 1))
	assert_float(_bounds(bench).size.x).is_greater(_bounds(bench).size.z)   # 2×1 runs along x …
	assert_float(_bounds(turned).size.z).is_greater(_bounds(turned).size.x)   # … and along z once turned
	var stand: Node3D = auto_free(P0FarmDecor.art("recipe_stand"))
	assert_bool(stand.find_children("*", "MeshInstance3D", true, false).all(func(m): return (m as MeshInstance3D).mesh is PrimitiveMesh)).is_true()
	# the sails sit on the body's rotor socket (manifest), the whole sweep inside the 2 × 2 cells
	assert_vector(P0FarmDecor.socket("deco_windmill", "rotor")).is_equal_approx(Vector3(0, 0.985, 0.273), Vector3.ONE * 0.001)
	var mill: Node3D = auto_free(P0FarmDecor.art("deco_windmill"))
	assert_vector((mill.find_child("Sails", true, false) as Node3D).position).is_equal_approx(Vector3(0, 0.985, 0.273), Vector3.ONE * 0.001)

func test_the_preview_ghosts_its_own_materials() -> void:
	var placed: Node3D = auto_free(P0FarmDecor.art("deco_fountain"))
	var preview: Node3D = auto_free(P0FarmDecor.art("deco_fountain"))
	P0FarmDecor.ghost(preview)
	for m in preview.find_children("*", "MeshInstance3D", true, false):
		var mat := (m as MeshInstance3D).material_override as StandardMaterial3D
		assert_object(mat).is_not_null()
		assert_float(mat.albedo_color.a).is_equal_approx(0.6, 0.001)
	var body: MeshInstance3D = placed.find_children("*", "MeshInstance3D", true, false)[0]
	assert_object(body.material_override).is_same(P0FarmDecor.FarmArt.material())   # the shared one untouched
	assert_float((body.material_override as StandardMaterial3D).albedo_color.a).is_equal(1.0)

## The windmill's sails turn once a SAIL_TURN_S, one tween however often the piece re-enters the tree (周瑜 on #276).
func test_the_sails_turn_with_one_tween() -> void:
	var running := func() -> int: return get_tree().get_processed_tweens().filter(func(tw: Tween): return tw.is_valid() and tw.is_running()).size()
	var before: int = running.call()   # other tweens in the scene don't count (周瑜 on #276)
	var mill: Node3D = P0FarmDecor.art("deco_windmill")
	add_child(mill)
	var sails := mill.find_child("Sails", true, false) as Node3D
	remove_child(mill)
	add_child(mill)
	assert_bool(sails.get_meta("turning", false)).is_true()
	assert_int(running.call() - before).is_equal(1)
	var was := sails.rotation.z
	await get_tree().create_timer(0.3).timeout
	assert_float(absf(sails.rotation.z - was)).is_greater(0.01)   # it turns
	mill.free()

## 上官婉儿 on #276: every placed piece of a kind is one draw — its instances at their footprints' middles, turned as
## art() turns them; the piece a Move lifted is left out; a piece without a model is not batched.
func test_placed_pieces_batch_by_kind() -> void:
	var list := [{"uid": 1, "id": "deco_fence", "x": 3, "y": 18, "rot": 0}, {"uid": 2, "id": "deco_fence", "x": 4, "y": 18, "rot": 1},
		{"uid": 3, "id": "deco_path", "x": 5, "y": 18, "rot": 0}, {"uid": 4, "id": "recipe_stand", "x": 6, "y": 18, "rot": 0},
		{"uid": 5, "id": "deco_path", "x": 7, "y": 18, "rot": 0}]
	var at := func(id: String, cell: Vector2i, _rot: int) -> Vector3: return Vector3(cell.x, 0, cell.y)
	var g := P0FarmDecor.batch_transforms(list, 5, 0.65, at)
	assert_array(g.keys()).contains_exactly_in_any_order(["deco_fence", "deco_path"])
	assert_int((g.deco_fence as Array).size()).is_equal(2)
	assert_int((g.deco_path as Array).size()).is_equal(1)   # uid 5 lifted
	var turned: Transform3D = g.deco_fence[1]
	assert_vector(turned.origin).is_equal(Vector3(4, 0, 18))
	assert_vector(turned.basis.x).is_equal_approx(Vector3(0, 0, 1), Vector3.ONE * 0.001)   # a quarter turn, as art()

## 不知火舞 on 290 (993a560e): the garden's own dressing stands on no cell a piece may take — the sign by the gate, the
## bushes, the stepping stones and the scattered rocks (solid) are the yard's objects too, or a piece would stand through
## them. Ground cover (grass, daisies, flowers) may go under a piece.
func test_the_garden_dressing_is_off_the_placeable_cells() -> void:
	var bp: FarmBlueprint = P0Garden.blueprint()
	var scenery: Node3D = auto_free(load("res://scenes/p0/p0_garden_scenery.gd").new())
	add_child(scenery)
	scenery.build(bp, "cottage")
	var walk: Array = _yard().walk
	var yard := Rect2i(int(walk[0]), int(walk[1]), int(walk[2]), int(walk[3]))
	var free := func(c: Vector2i) -> bool: return yard.has_point(c) and not _in("field", c) and not _in("objects", c) and not _in("paths", c)
	var points: Array = scenery.rock_points.duplicate()
	for n in scenery.find_children("*", "", true, false):
		if n is MultiMeshInstance3D and str(n.name) in ["Bush", "SteppingStone", "Tree0"]:
			var mm: MultiMesh = n.multimesh
			for i in mm.instance_count: points.append(mm.get_instance_transform(i).origin)
		elif n is MeshInstance3D and n.name == "Sign": points.append(n.position)
	assert_int(points.size()).is_greater(20)
	var on: Array = points.map(func(p): return bp.world_to_cell(p)).filter(free)
	assert_array(on).is_empty()

## q(131) ②: a Pergola's posts stand on its four corner cells and its middle line is open — the player walks under it,
## front to back (turned, side to side); placing still takes all six cells, so nothing stands under it.
func test_the_pergola_lets_one_walk_through_its_middle() -> void:
	var at := Vector2i(10, 4)
	assert_array(P0Decor.solid_cells("deco_pergola", at, 0)).contains_exactly_in_any_order(
		[Vector2i(10, 4), Vector2i(12, 4), Vector2i(10, 5), Vector2i(12, 5)])
	assert_array(P0Decor.solid_cells("deco_pergola", at, 1)).contains_exactly_in_any_order(
		[Vector2i(10, 4), Vector2i(11, 4), Vector2i(10, 6), Vector2i(11, 6)])
	assert_int(P0Decor.cells("deco_pergola", at, 0).size()).is_equal(6)   # all of it is the piece's for placing
	assert_array(P0Decor.solid_cells("deco_bench", at, 0)).is_equal(P0Decor.cells("deco_bench", at, 0))   # the rest stay solid
	var v := {"decor": {"placed": [{"uid": 1, "id": "deco_pergola", "x": at.x, "y": at.y, "rot": 0}]}}
	assert_bool(P0Decor.taken(v).has("11,4")).is_true()   # nothing goes under it
	# on the walk grid: the middle line is open and leads through
	var bp: FarmBlueprint = P0Garden.blueprint()
	var grid := BlueprintGrid.new(bp)
	for c in P0Decor.solid_cells("deco_pergola", at, 0): grid.set_solid(c, true)
	assert_bool(grid.astar.is_point_solid(Vector2i(11, 4))).is_false()
	assert_bool(grid.astar.is_point_solid(Vector2i(10, 4))).is_true()

## q(131): a placed Fountain bubbles — a ring quad on each basin's water, on its own beside its kind's batch, sharing its
## basin's material with every Fountain; the preview has none (ghost() makes its own materials).
func test_a_placed_fountain_ripples_on_both_basins() -> void:
	assert_bool(P0FarmDecor._has_extra("deco_fountain")).is_true()
	assert_bool(P0FarmDecor._has_extra("deco_bench")).is_false()
	var a := P0FarmDecor._ripples_on("deco_fountain", 0, 0.65)
	var b := P0FarmDecor._ripples_on("deco_fountain", 1, 0.65)
	var quads := a.find_children("Ripple*", "MeshInstance3D", true, false)
	assert_int(quads.size()).is_equal(2)
	assert_float((quads[0] as MeshInstance3D).position.y).is_equal_approx(0.729, 0.001)   # just over the upper water
	assert_float((quads[1] as MeshInstance3D).position.y).is_equal_approx(0.259, 0.001)
	assert_vector(((quads[1] as MeshInstance3D).mesh as PlaneMesh).size).is_equal_approx(Vector2(1.02, 1.02), Vector2.ONE * 0.001)
	var other := b.find_children("Ripple*", "MeshInstance3D", true, false)
	assert_object((other[0] as MeshInstance3D).material_override).is_same((quads[0] as MeshInstance3D).material_override)
	assert_int((quads[0] as MeshInstance3D).cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var preview := P0FarmDecor.art("deco_fountain")
	assert_array(preview.find_children("Ripple*", "MeshInstance3D", true, false)).is_empty()
	for n in [a, b, preview]: n.free()

## 李元芳's 0.2.1 smoke (d83191bb): a Fountain was offered — green — on the yard's back wall. The Homestead fence ring
## (Lv3, a Stone Wall with look b) runs between rows 18 and 19 and through column 19; every cell a piece may take lies
## inside it, so nothing stands on or behind the fence, whichever look.
func test_no_piece_stands_on_or_behind_the_fence_ring() -> void:
	var bp := P0Garden.blueprint()
	var r: Dictionary = P0Garden.FENCE_RING
	var walk: Array = _yard().get("walk", [])
	var yard := Rect2i(int(walk[0]), int(walk[1]), int(walk[2]), int(walk[3]))
	var half := bp.cell_m * 0.5
	for y in range(yard.position.y, yard.end.y):
		for x in range(yard.position.x, yard.end.x):
			var p := bp.cell_to_world(Vector2i(x, y))
			var inside := p.x - half >= float(r.west) - 0.001 and p.x + half <= float(r.east) + 0.001 \
				and p.z - half >= float(r.back) - 0.001 and p.z + half <= float(r.front) + 0.001
			assert_bool(inside).override_failure_message("cell %d,%d is on or past the fence" % [x, y]).is_true()
	var v := {"decor": {"placed": []}, "facilities": []}
	for x in range(1, 20): assert_str(P0Decor.reason(v, "deco_planter", Vector2i(x, 19))).is_equal(P0Decor.REASONS.decor_outside)
	for y in range(0, 20): assert_str(P0Decor.reason(v, "deco_planter", Vector2i(19, y))).is_equal(P0Decor.REASONS.decor_outside)
	assert_str(P0Decor.reason(v, "deco_fountain", Vector2i(5, 18))).is_equal(P0Decor.REASONS.decor_outside)   # the smoke's spot
	assert_str(P0Decor.reason(v, "deco_fountain", Vector2i(13, 17))).is_equal("")   # just inside the wall is fine

## q(145): the player walks inside the fence ring too, whatever the level — no walking through the back wall to row
## 19 or along the east one in column 19; the exit and the spawn stay open, and a player standing past the ring (row
## or column 19) comes back to the nearest walkable cell on entering the farm.
func test_the_player_walks_inside_the_fence_ring() -> void:
	var bp := P0Garden.blueprint()
	var r: Dictionary = P0Garden.FENCE_RING
	var half := bp.cell_m * 0.5
	for y in range(0, bp.grid.y):
		for x in range(0, bp.grid.x):
			var c := Vector2i(x, y)
			if not bp.is_walkable(c): continue
			var p := bp.cell_to_world(c)
			var inside := p.x - half >= float(r.west) - 0.001 and p.x + half <= float(r.east) + 0.001 \
				and p.z - half >= float(r.back) - 0.001 and p.z + half <= float(r.front) + 0.001
			assert_bool(inside).override_failure_message("walkable cell %d,%d is on or past the fence" % [x, y]).is_true()
	for k in [P0Garden.ANCHORS.spawn, P0Garden.ANCHORS.exit]: assert_bool(bp.is_walkable(k)).is_true()
	var grid := BlueprintGrid.new(bp)
	assert_array(grid.path(Vector2i(13, 17), Vector2i(13, 19))).is_empty()   # through the back wall
	assert_array(grid.path(Vector2i(17, 14), Vector2i(19, 14))).is_empty()   # onto the east wall
	assert_that(P0Farm.landing_cell(grid, Vector2i(13, 19))).is_equal(Vector2i(13, 18))
	assert_that(P0Farm.landing_cell(grid, Vector2i(19, 10))).is_equal(Vector2i(18, 10))
	var corner: Vector2i = P0Farm.landing_cell(grid, Vector2i(19, 19))
	assert_bool(bp.is_walkable(corner)).is_true()
	assert_int(maxi(19 - corner.x, 19 - corner.y)).is_less_equal(2)   # just inside the corner
	assert_that(P0Farm.landing_cell(grid, P0Garden.ANCHORS.spawn)).is_equal(P0Garden.ANCHORS.spawn)   # where one may stand: there
