extends GdUnitTestSuite
## Gathering at a pond (SGODOT-410; 后裔's 409 interface, 不知火舞's words on 410): the main key at a point's stand — `Gather ·
## 3 Energy`, grey `Ready in …`, amber `Need 3 Energy`, grey `Bag full` with its toast; the nearest point's name bar; the
## cooldown counted down with the view; the bank's trees and bushes kept off the points.

const PondGather := preload("res://scenes/p0/p0_pond_gather.gd")
const Art = preload("res://modules/farm/farm_art.gd")
const POND := "gn-1850147~pond0"

func _point(kind := "wood", ready := 0.0, x := 3.1, z := -0.4) -> Dictionary:
	return {"id": POND + "#L2", "slot": "L2", "kind": kind, "name": "Grove", "yield": [["wood", 4]], "energy": 3,
		"x": x, "z": z, "stand": [x - 0.1, z - 0.8], "ready_in": ready}

func _view(energy := 50, free := 5) -> Dictionary:
	return {"energy": {"value": energy, "max": 200}, "bag": {"free": free, "slots": []},
		"gather": {"pond": {"pond": POND, "shape": "crescent", "points": [_point()]}}}

func test_the_key_at_a_point() -> void:
	var a := PondGather.key(_view(), _point(), POND)
	assert_str(str(a.verb)).is_equal("Gather")
	assert_str(str(a.sub)).is_equal("3 Energy")
	assert_bool(a.enabled).is_true()
	assert_dict(a.cmd).is_equal({"type": "gather", "spot": POND + "#L2", "space": "pond", "place": POND})
	var cooling := PondGather.key(_view(), _point("wood", 3.0 * 3600000.0 + 12 * 60000.0), POND)
	assert_str(str(cooling.sub)).is_equal("Ready in 3h 12m")
	assert_bool(cooling.enabled).is_false()
	var tired := PondGather.key(_view(2), _point(), POND)
	assert_str(str(tired.sub)).is_equal("Need 3 Energy")
	assert_bool(tired.amber).is_true()
	assert_dict(tired.cmd).is_equal({"type": "energy_card"})
	var full := PondGather.key(_view(50, 0), _point(), POND)
	assert_str(str(full.sub)).is_equal("Bag full")
	assert_bool(full.enabled).is_false()
	assert_str(str(full.toast)).is_equal("No room · free a slot first")

func test_the_name_bar_is_the_items_name_dimmed_while_cooling() -> void:
	var v := _view()
	assert_dict(PondGather.tag(v, _point())).is_equal({"icon": "wood", "text": P0Logic.item_name(v, "wood"), "fact": "", "dimmed": false})
	var t := PondGather.tag(v, _point("wood", 4.0 * 3600000.0))
	assert_str(str(t.fact)).is_equal("Ready in 4h")
	assert_bool(t.dimmed).is_true()

func test_the_nearest_point_by_its_stand() -> void:
	var a := _point("wood", 0.0, 3.0, -1.0)
	var b := _point("stone", 0.0, 9.0, -1.0)
	b.id = POND + "#R1"
	assert_str(str(PondGather.nearest([a, b], Vector3(8.5, 0, -2)).id)).is_equal(POND + "#R1")
	assert_dict(PondGather.nearest([], Vector3.ZERO)).is_empty()

func test_the_cooldown_counts_down_with_the_view() -> void:
	var v := _view()
	v.gather.pond.points = [_point("wood", 10000.0)]
	var later := P0Logic.project(v, 4000.0)
	assert_float(float(later.gather.pond.points[0].ready_in)).is_equal(6000.0)
	assert_float(float(v.gather.pond.points[0].ready_in)).is_equal(10000.0)   # the view itself untouched

func test_pieces_built_by_kind_and_the_bank_kept_off() -> void:
	var g: Node3D = auto_free(PondGather.new())
	add_child(g)
	var v := _view()
	var stone := _point("stone", 0.0, 9.0, -1.0)
	stone.id = POND + "#R1"
	v.gather.pond.points = [_point(), stone]
	g.sync(v)
	assert_int(g.nodes.size()).is_equal(2)
	assert_int((g.nodes[POND + "#L2"] as Node3D).get_child_count()).is_equal(3)   # the grove's three trees
	assert_vector((g.nodes[POND + "#R1"] as Node3D).position).is_equal(Vector3(9.0, 0, -1.0))
	assert_array(PondGather.clear_points(v)).is_equal([Vector3(3.1, 0, -0.4), Vector3(9.0, 0, -1.0)])
	assert_bool(PondScenery._near(Vector3(3.5, 0, 0.3), PondGather.clear_points(v))).is_true()
	assert_bool(PondScenery._near(Vector3(0.1, 0, -4), PondGather.clear_points(v))).is_false()
	# Fern Pond's clay (12, -7.6): the tree 2.1 m in front of it (12.1, -5.5) goes, the one behind (12.2, -12) stays
	assert_bool(PondScenery._in_front(Vector3(12.1, 0, -5.5), [Vector3(12, 0, -7.6)])).is_true()
	assert_bool(PondScenery._in_front(Vector3(12.2, 0, -12), [Vector3(12, 0, -7.6)])).is_false()
	assert_bool(PondScenery._in_front(Vector3(9.5, 0, -5.5), [Vector3(12, 0, -7.6)])).is_false()

## Reeds, Clay, Hardwood and Flax are #782's pieces, one glb each (no stand-in).
func test_the_new_kinds_are_782s_pieces() -> void:
	var g: Node3D = auto_free(PondGather.new())
	add_child(g)
	var v := _view()
	var list: Array = []
	for k in ["reed", "clay", "hardwood", "flax"]:
		var p := _point(k, 0.0, list.size() * 3.0, -2.0)
		p.id = POND + "#" + k
		list.append(p)
	v.gather.pond.points = list
	g.sync(v)
	for k in ["reed", "clay", "hardwood", "flax"]:
		var piece := g.nodes[POND + "#" + k] as Node3D
		assert_int(piece.get_child_count()).is_equal(1)
		assert_object((piece.get_child(0) as MeshInstance3D).mesh).is_same(Art.mesh_for(str(PondGather.PIECES[k])))
		assert_object(Art.mesh_for(str(PondGather.PIECES[k]))).is_not_null()
