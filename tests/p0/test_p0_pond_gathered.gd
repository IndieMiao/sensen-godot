extends GdUnitTestSuite
## C67 (SGODOT-417; the user 11-10 bot 682): a pond point cooling shows its gathered look (410 924d6611) — the piece
## hidden, its gathered one shown, back when it is ready; every kind has one; none wider than its piece (the bank keeps
## 1.5 m off the piece, not off something wider); the feet's blades under both. The dev switch is the editor's only.

const PondGather := preload("res://scenes/p0/p0_pond_gather.gd")
const POND := "gn-1850147~pond0"
const KINDS := ["wood", "stone", "herb", "reed", "clay", "hardwood", "flax"]

func _point(kind: String, ready := 0.0) -> Dictionary:
	return {"id": POND + "#" + kind, "slot": "L2", "kind": kind, "name": kind, "yield": [[kind, 2]], "energy": 3,
		"x": 0.0, "z": 0.0, "stand": [-0.1, -0.8], "ready_in": ready}

func _view(points: Array) -> Dictionary:
	return {"energy": {"value": 50, "max": 200}, "bag": {"free": 5, "slots": []},
		"gather": {"pond": {"pond": POND, "shape": "crescent", "points": points}}}

func _gather(points: Array) -> Node3D:
	var g: Node3D = auto_free(PondGather.new())
	add_child(g)
	g.sync(_view(points))
	return g

## The farthest any part of a layer reaches from the point, across the ground (x–z), metres.
static func _reach(layer: Node3D) -> float:
	var r := 0.0
	for m: GeometryInstance3D in layer.find_children("*", "GeometryInstance3D", true, false):
		var to_layer := layer.global_transform.affine_inverse() * m.global_transform
		var boxes: Array[AABB] = []
		if m is MultiMeshInstance3D:   # its placements as recorded: a MultiMesh's own box is empty headless
			var mesh_box := (m as MultiMeshInstance3D).multimesh.mesh.get_aabb()
			for t: Transform3D in m.get_meta("placed", []): boxes.append((to_layer * t) * mesh_box)
		else: boxes.append(to_layer * m.get_aabb())
		for box in boxes:
			for i in 8:
				var e := box.get_endpoint(i)
				r = maxf(r, Vector2(e.x, e.z).length())
	return r

func test_every_kind_has_a_gathered_look_shown_while_cooling() -> void:
	var points: Array = KINDS.map(func(k): return _point(k))
	var g := _gather(points)
	for k in KINDS:
		var root: Node3D = g.nodes[POND + "#" + k]
		var live := root.get_node("Live") as Node3D
		var done := root.get_node("Gathered") as Node3D
		assert_int(done.get_child_count()).override_failure_message(k).is_greater(0)
		assert_bool(live.visible and not done.visible).override_failure_message(k).is_true()
	g.sync(_view(KINDS.map(func(k): return _point(k, 3600000.0))))   # gathered: cooling an hour
	for k in KINDS:
		var root: Node3D = g.nodes[POND + "#" + k]
		assert_bool((root.get_node("Gathered") as Node3D).visible and not (root.get_node("Live") as Node3D).visible).override_failure_message(k).is_true()
	g.sync(_view(points))   # ready again
	for k in KINDS:
		var root: Node3D = g.nodes[POND + "#" + k]
		assert_bool((root.get_node("Live") as Node3D).visible and not (root.get_node("Gathered") as Node3D).visible).override_failure_message(k).is_true()

func test_no_gathered_look_is_wider_than_its_piece() -> void:
	var g := _gather(KINDS.map(func(k): return _point(k)))
	for k in KINDS:
		var root: Node3D = g.nodes[POND + "#" + k]
		var live := _reach(root.get_node("Live") as Node3D)
		var done := _reach(root.get_node("Gathered") as Node3D)
		assert_float(done).override_failure_message("%s: gathered %.3f m, piece %.3f m" % [k, done, live]).is_less_equal(live + 0.001)

func test_the_feet_stay_under_both() -> void:
	var g := _gather([_point("stone"), _point("wood"), _point("hardwood")])
	for k in ["stone", "wood", "hardwood"]:
		var root: Node3D = g.nodes[POND + "#" + k]
		var outside := root.get_children().filter(func(n): return n.name != "Live" and n.name != "Gathered")
		assert_bool(outside.any(func(n): return n is MultiMeshInstance3D)).override_failure_message(k).is_true()

## Timber's stand-side pines are stumps, the farthest a small pine — well under a pine that can be gathered.
func test_timber_leaves_one_small_pine() -> void:
	var g := _gather([_point("wood", 3600000.0)])
	var done := (g.nodes[POND + "#wood"] as Node3D).get_node("Gathered") as Node3D
	var Art = preload("res://modules/farm/farm_art.gd")
	var pines := done.get_children().filter(func(n): return n is MeshInstance3D and n.mesh == Art.mesh_for("wild_pz_pine_01_g"))
	var stumps := done.get_children().filter(func(n): return n is MeshInstance3D and n.mesh == Art.mesh_for("wild_pz_log_05"))
	assert_int(pines.size()).is_equal(1)
	assert_int(stumps.size()).is_equal(2)
	var live := (g.nodes[POND + "#wood"] as Node3D).get_node("Live") as Node3D
	var tallest := 0.0
	for m: MeshInstance3D in live.get_children(): tallest = maxf(tallest, m.scale.y)
	assert_float((pines[0] as MeshInstance3D).scale.y).is_less_equal(tallest * 0.45)

func test_the_dev_switch_is_the_editors_only() -> void:
	var editor := func(f): return f == "editor"
	var exported := func(_f): return false
	assert_array(Array(PondGather.cool_switch(editor, "all"))).is_equal(["all"])
	assert_array(Array(PondGather.cool_switch(editor, "wood,C1"))).is_equal(["wood", "C1"])
	assert_array(Array(PondGather.cool_switch(exported, "all"))).is_empty()   # an exported build, debug or release
	assert_array(Array(PondGather.cool_switch(editor, ""))).is_empty()
	var p := _point("clay")
	assert_float(float(PondGather.cooled(p, PackedStringArray(["clay"])).ready_in)).is_equal(PondGather.COOL_MS)
	assert_float(float(PondGather.cooled(p, PackedStringArray(["wood"])).ready_in)).is_equal(0.0)
	assert_float(float(PondGather.cooled(_point("clay", 60000.0), PackedStringArray(["all"])).ready_in)).is_equal(60000.0)
	assert_float(float(p.ready_in)).is_equal(0.0)   # the view's own point untouched

## Draws a gathered look costs (上官婉儿 on #969: a pond all cooling adds no more than a few tens on GLES): a mesh's
## surfaces, a batch's once; Wild Herb at most 6 — its cut herbs one mesh, its foot's blades one batch, a sprout one.
static func _draws(layer: Node3D) -> int:
	var n := 0
	for g in layer.find_children("*", "GeometryInstance3D", true, false):
		if g is MeshInstance3D and (g as MeshInstance3D).mesh: n += (g as MeshInstance3D).mesh.get_surface_count()
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh.mesh: n += (g as MultiMeshInstance3D).multimesh.mesh.get_surface_count()
	return n

func test_a_gathered_look_is_a_few_draws() -> void:
	var g := _gather(KINDS.map(func(k): return _point(k)))
	for k in KINDS:
		var done := (g.nodes[POND + "#" + k] as Node3D).get_node("Gathered") as Node3D
		assert_int(_draws(done)).override_failure_message("%s: %d draws" % [k, _draws(done)]).is_less_equal(6)
	var herb := (g.nodes[POND + "#herb"] as Node3D).get_node("Gathered") as Node3D
	assert_int(_draws(herb)).is_equal(4)   # cut herbs, the foot's batch, two sprouts

## A batch in a gathered look says where its instances stand (the width above reads them, not the MultiMesh's box).
func test_wild_herb_gathered_keeps_inside_its_piece() -> void:
	var g := _gather([_point("herb")])
	var root := g.nodes[POND + "#herb"] as Node3D
	assert_float(_reach(root.get_node("Gathered") as Node3D)).is_less_equal(0.74)   # 上官婉儿 on #969: the piece reaches 0.75

func test_a_gathered_batch_records_its_placements() -> void:
	var g := _gather(KINDS.map(func(k): return _point(k)))
	for k in KINDS:
		var done := (g.nodes[POND + "#" + k] as Node3D).get_node("Gathered") as Node3D
		for m in done.find_children("*", "MultiMeshInstance3D", true, false):
			assert_int((m.get_meta("placed", []) as Array).size()).override_failure_message(k).is_equal((m as MultiMeshInstance3D).multimesh.instance_count)

## Turning a look (gathered, or grown back) says so once a sync, however many turned; none turned, nothing said
## (GroundShade.watch reads the pieces again: the shade follows, 周瑜 on #969).
func test_turning_looks_says_so_once_a_sync() -> void:
	var g := _gather(KINDS.map(func(k): return _point(k)))
	var said := [0]
	g.looks_changed.connect(func(): said[0] += 1)
	g.sync(_view(KINDS.map(func(k): return _point(k))))
	assert_int(said[0]).is_equal(0)
	g.sync(_view(KINDS.map(func(k): return _point(k, 3600000.0))))
	assert_int(said[0]).is_equal(1)
	g.sync(_view(KINDS.map(func(k): return _point(k, 3500000.0))))   # still cooling
	assert_int(said[0]).is_equal(1)
	g.sync(_view(KINDS.map(func(k): return _point(k))))   # grown back
	assert_int(said[0]).is_equal(2)

func test_the_dev_cooling_counts_down() -> void:
	var p := _point("wood")
	assert_float(float(PondGather.cooled(p, PackedStringArray(["wood"]), 5000.0).ready_in)).is_equal(5000.0)
	assert_float(float(PondGather.cooled(p, PackedStringArray(["wood"]), 0.0).ready_in)).is_equal(0.0)   # grown back
