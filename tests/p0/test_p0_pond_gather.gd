extends GdUnitTestSuite
## Gathering at a pond (SGODOT-410; 后裔's 409 interface, 不知火舞's words on 410): the main key at a point's stand — `Gather ·
## 3 Energy`, grey `Ready in …`, amber `Need 3 Energy`, grey `Bag full` with its toast; the nearest point's mark (475); the
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
	assert_str(str(cooling.sub)).is_equal("3h 12m")   # the key's line: `Ready in 3h 12m` ran past 80 px (q(44); 奕星 11-10)
	assert_bool(cooling.enabled).is_false()
	assert_str(str(PondGather.key(_view(), _point("wood", 4.0 * 3600000.0), POND).sub)).is_equal("Ready in 4h")   # one unit
	assert_str(str(PondGather.key(_view(), _point("wood", 125000.0), POND).sub)).is_equal("Ready in 2:05")   # the last five minutes tick
	var tired := PondGather.key(_view(2), _point(), POND)
	assert_str(str(tired.sub)).is_equal("Need 3 Energy")
	assert_bool(tired.amber).is_true()
	assert_dict(tired.cmd).is_equal({"type": "energy_card"})
	var full := PondGather.key(_view(50, 0), _point(), POND)
	assert_str(str(full.sub)).is_equal("Bag full")
	assert_bool(full.enabled).is_false()
	assert_str(str(full.toast)).is_equal("No room · free a slot first")

## SGODOT-475 (不知火舞's gather-compact spec ①): the nearest point's mark is its item's icon button; at its stand and ready
## it opens to the item's name alone; cooling it stays a button with the part grown back (of cooldown_h, 4 h without it).
func test_the_mark_is_a_button_opening_to_the_name_only_at_the_point_and_ready() -> void:
	var v := _view()
	var p := _point()
	var away := PondGather.mark(v, p, Vector3(10, 0, 10))
	assert_dict(away).is_equal({"icon": "wood", "text": P0Logic.item_name(v, "wood"), "progress": -1.0, "open": false})
	assert_bool(bool(PondGather.mark(v, p, PondGather.stand_of(p)).open)).is_true()   # at its stand: the name strip
	var cooling := _point("wood", 3.0 * 3600000.0)   # 1 h of 4 grown back
	var at := PondGather.mark(v, cooling, PondGather.stand_of(cooling))
	assert_bool(bool(at.open)).is_false()   # cooling: never opens, the key says how long
	assert_float(float(at.progress)).is_equal_approx(0.25, 0.0001)
	cooling["cooldown_h"] = 6.0
	assert_float(PondGather.progress(cooling)).is_equal_approx(0.5, 0.0001)   # the server's cooldown_h when it sends one
	assert_float(PondGather.progress(_point("wood", 99.0 * 3600000.0))).is_equal(0.0)   # never below 0

## 李元芳 on 422: Pebble Pond's reeds (C1 (4, -2.4), its stand (3.88, -3.12) on the water's side) gather from the front too.
func test_a_point_is_reached_at_its_stand_or_its_piece() -> void:
	var reeds := {"id": "pond_san_francisco_04#C1", "kind": "reed", "x": 4.0, "z": -2.4, "stand": [3.88, -3.12]}
	assert_bool(PondGather.in_reach(reeds, Vector3(3.88, 0, -3.12))).is_true()   # at the stand
	assert_bool(PondGather.in_reach(reeds, Vector3(4.0, 0, -1.2))).is_true()     # in front of the reeds, 1.2 m off
	assert_bool(PondGather.in_reach(reeds, Vector3(4.0, 0, -0.5))).is_false()    # further back: Cast
	assert_bool(PondGather.in_reach({}, Vector3.ZERO)).is_false()

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
	var grove := g.nodes[POND + "#L2"] as Node3D
	assert_int(grove.get_child_count()).is_equal(4)   # the grove's three trees and their feet's blades (SGODOT-422 v7)
	assert_bool(grove.get_child(3) is MultiMeshInstance3D).is_true()
	assert_vector((g.nodes[POND + "#R1"] as Node3D).position).is_equal(Vector3(9.0, 0, -1.0))
	assert_array(PondGather.clear_points(v)).is_equal([Vector3(3.1, 0, -0.4), Vector3(9.0, 0, -1.0)])
	assert_bool(PondScenery._near(Vector3(3.5, 0, 0.3), PondGather.clear_points(v))).is_true()
	assert_bool(PondScenery._near(Vector3(0.1, 0, -4), PondGather.clear_points(v))).is_false()
	# Fern Pond's clay (12, -7.6): the tree 2.1 m in front of it (12.1, -5.5) goes, the one behind (12.2, -12) stays
	assert_bool(PondScenery._in_front(Vector3(12.1, 0, -5.5), [Vector3(12, 0, -7.6)])).is_true()
	assert_bool(PondScenery._in_front(Vector3(12.2, 0, -12), [Vector3(12, 0, -7.6)])).is_false()
	assert_bool(PondScenery._in_front(Vector3(9.5, 0, -5.5), [Vector3(12, 0, -7.6)])).is_false()

## Reeds, Clay and Flax are #782's pieces, one glb each (no stand-in); Hardwood in the wild is the pack's (SGODOT-422 v7).
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
	for k in ["reed", "clay", "flax"]:
		var piece := g.nodes[POND + "#" + k] as Node3D
		assert_int(piece.get_child_count()).is_equal(1)
		assert_object((piece.get_child(0) as MeshInstance3D).mesh).is_same(Art.mesh_for(str(PondGather.PIECES[k])))
		assert_object(Art.mesh_for(str(PondGather.PIECES[k]))).is_not_null()
	# Hardwood in the wild (SGODOT-422 v7): the pack's Tree_20, a stump, two logs and their feet's blades
	var hardwood := g.nodes[POND + "#hardwood"] as Node3D
	assert_int(hardwood.get_child_count()).is_equal(5)
	assert_object((hardwood.get_child(0) as MeshInstance3D).mesh).is_same(Art.mesh_for("wild_pz_tree_20_g"))
	assert_object(Art.mesh_for("wild_pz_tree_20_g")).is_not_null()

## The Energy card the amber key opens says what was pressed — `Gather needs 3 Energy` at a point, `Cast` elsewhere
## (周瑜 on #788: the pond's p0_energy_verb said Cast always).
func test_the_energy_card_says_gather_at_a_point() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	rt.ui.quick_store = "user://test_p0_pond_gather.json"
	rt.session.transport = func(_m, _p, _b, _c): pass   # no server
	add_child(rt)
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_pond.gd\"\nfunc _ready() -> void: pass\n"
	stub.reload()
	var pond: Node3D = auto_free(Node3D.new())
	pond.set_script(stub)
	pond.rt = rt
	rt.ui.set_action(PondGather.key(_view(2), _point(), POND))
	assert_str(pond.p0_energy_verb()).is_equal("Gather")
	rt.ui.set_action({"icon": "", "verb": "Cast", "sub": "5 Energy", "enabled": true, "amber": false})
	assert_str(pond.p0_energy_verb()).is_equal("Cast")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_p0_pond_gather.json"))
