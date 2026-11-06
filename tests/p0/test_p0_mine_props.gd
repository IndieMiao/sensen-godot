extends GdUnitTestSuite
## 355 b1 mine kit (contract-efg §10.1; 黄忠's v1, 不知火舞 11-03 on the rocks): the elevator station with its floor plate
## and lamp, a guard floor's arena, every rock of a mine its main ore's block, turned and sized by its index and the
## floor's seed. Where a glb was never imported (a machine with no --import) the code art stands in; the tests pass
## either way, and check the imported piece where it is there.

const Art := preload("res://modules/mining/mine_art.gd")
const Layout := preload("res://modules/mining/mine_layout.gd")
const Fx := preload("res://tests/p0/fixtures/mine_b1_view.gd")
const STORE := "user://test_p0_mine_props.json"
const P0_MINE := "res://scenes/p0/p0_mine.tscn"
const FAKE := "user://test_p0_mine_props_never_imported.glb"

var rt: P0Runtime
var mine: Node3D

func after_test() -> void:
	if is_instance_valid(mine): mine.queue_free()
	if rt != null: P0Runtime.free_instance_for_tests()
	rt = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FAKE + ".import"))
	await get_tree().process_frame

func test_a_piece_never_imported_is_null_without_a_load() -> void:
	# its .import names a file this machine never made: ResourceLoader.exists would say yes, load() would fail loudly
	var f := FileAccess.open(FAKE + ".import", FileAccess.WRITE)
	f.store_string('[remap]\n\nimporter="scene"\ntype="PackedScene"\npath="res://.godot/imported/never-made.scn"\n')
	f.close()
	assert_object(Art.kit(FAKE)).is_null()
	assert_object(Art.kit("res://assets/mine/props/not_a_piece.glb")).is_null()
	var backdrop: Node3D = Art.kit("res://assets/mine/backdrop/mine_backdrop.glb")   # in every build since SGODOT-257
	assert_object(backdrop).is_not_null()
	backdrop.free()

## A station-shaped node: its two anchors where the glb has them (assets/mine/props/manifest.json).
func _station() -> Node3D:
	var root := Node3D.new()
	var plate := Node3D.new()
	plate.name = "PlateAnchor"
	plate.position = Vector3(0, 0.99, 0.515)
	root.add_child(plate)
	var lamp := Node3D.new()
	lamp.name = "LampAnchor"
	lamp.position = Vector3(0.8, 0.73, 0.47)
	root.add_child(lamp)
	return auto_free(root)

func _glyphs(label: Label3D) -> Vector2:
	var width := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	return Vector2(width, label.font.get_ascent(label.font_size) * 0.7) * label.pixel_size

func test_the_plate_says_the_floor_short_dark_and_bold_within_the_plate() -> void:
	for n in [1, 10, 40]:
		var root := _station()
		Art.dress_station(root, n, true)
		var label := root.find_child("FloorPlate", true, false) as Label3D
		assert_object(label).is_not_null()
		assert_str(label.text).is_equal("F%d" % n)
		assert_object(label.get_parent()).is_same(root.find_child("PlateAnchor", true, false))
		assert_object(label.font).is_same(UiKit.font(&"bold"))
		assert_float(label.modulate.get_luminance()).is_less(0.25)
		var g := _glyphs(label)
		assert_float(g.y).is_less_equal(Art.PLATE.y * 0.7 + 0.001)   # about seven tenths of the plate's height …
		assert_float(g.x).is_less_equal(Art.PLATE.x * 0.86 + 0.001)   # … unless that would run past its sides
		if n == 1: assert_float(g.y).is_equal_approx(Art.PLATE.y * 0.7, 0.002)

func test_the_lamp_is_green_unlocked_and_amber_locked() -> void:
	for unlocked in [true, false]:
		var root := _station()
		Art.dress_station(root, 10, unlocked)
		var lamp := root.find_child("ElevatorLamp", true, false) as MeshInstance3D
		assert_object(lamp.get_parent()).is_same(root.find_child("LampAnchor", true, false))
		var colour: Color = (lamp.material_override as StandardMaterial3D).albedo_color
		assert_str(colour.to_html(false)).is_equal((Art.LAMP_UNLOCKED if unlocked else Art.LAMP_LOCKED).to_html(false))

func test_the_elevator_is_mine_elevator_either_way() -> void:
	var lift: Node3D = auto_free(Art.elevator(true, 20))
	assert_str(str(lift.name)).is_equal("MineElevator")
	var station: Node3D = Art.kit(Art.STATION)
	if station == null:   # not imported here: the code-built elevator, as before
		assert_bool(lift is MeshInstance3D).is_true()
		return
	station.free()
	assert_vector(lift.position).is_equal(Layout.ELEVATOR)
	assert_str((lift.find_child("FloorPlate", true, false) as Label3D).text).is_equal("F20")
	assert_object(lift.find_child("ElevatorLamp", true, false)).is_not_null()

func test_a_rock_turns_and_sizes_by_its_index_and_the_floor_the_same_each_time() -> void:
	var seed_a := "%s:%d:%s" % [Fx.MINE, 3, "2026-11-02"]
	var yaws: Array = []
	for i in 12:
		var a: Node3D = auto_free(Art.rock(Vector3.ZERO, i, 1, "", seed_a))
		var b: Node3D = auto_free(Art.rock(Vector3.ZERO, i, 1, "", seed_a))
		var pose := a.get_node("Rock") as Node3D
		assert_float(pose.rotation.y).is_equal((b.get_node("Rock") as Node3D).rotation.y)
		assert_float(pose.scale.x).is_between(0.9, 1.1)
		assert_vector(pose.scale).is_equal(Vector3.ONE * pose.scale.x)
		assert_vector(a.scale).is_equal(Vector3.ONE)   # the root is the break's (shake, shrink)
		assert_vector(a.rotation).is_equal(Vector3.ZERO)
		yaws.append(snappedf(pose.rotation.y, 0.01))
	assert_int(yaws.filter(func(y): return y == yaws[0]).size()).is_less(3)   # turned apart, not one way
	var other: Node3D = auto_free(Art.rock(Vector3.ZERO, 0, 1, "", "%s:%d:%s" % [Fx.MINE, 4, "2026-11-02"]))
	var first: Node3D = auto_free(Art.rock(Vector3.ZERO, 0, 1, "", seed_a))
	assert_bool(is_equal_approx((other.get_node("Rock") as Node3D).rotation.y, (first.get_node("Rock") as Node3D).rotation.y)).is_false()
	var plain: Node3D = auto_free(Art.rock(Vector3.ZERO, 5, 1))   # the old mine's call: no seed, no pose
	assert_vector((plain.get_node("Rock") as Node3D).scale).is_equal(Vector3.ONE)
	assert_float((plain.get_node("Rock") as Node3D).rotation.y).is_equal(0.0)

func test_a_rock_is_its_mines_ore_block_where_imported() -> void:
	for ore in ["iron_ore", "quartz", "copper_ore"]:
		var rock: Node3D = auto_free(Art.rock(Vector3.ZERO, 1, 1, ore, "s"))
		var block: Node3D = Art.kit(Art.ROCK_KIT % ore)
		if block == null:
			assert_bool(rock.get_node("Rock") is MeshInstance3D).is_true()   # the code-built ore stands in
			continue
		block.free()
		assert_bool(rock.get_node("Rock") is MeshInstance3D).is_false()   # the glb's own root

func test_the_rocks_ore_comes_from_the_mine() -> void:
	assert_str(P0MaterialLogic.rock_ore(Fx.view(3, {"type": "quarry", "records": {Fx.MINE: {"deepest": 3, "guards": [], "type": "quarry", "main": null}}}))).is_equal("copper_ore")
	assert_str(P0MaterialLogic.rock_ore(Fx.view(3, {"records": {Fx.MINE: {"deepest": 3, "guards": [], "type": "vein", "main": "iron_ore"}}}))).is_equal("iron_ore")
	assert_str(P0MaterialLogic.rock_ore(Fx.view(3, {"records": {Fx.MINE: {"deepest": 3, "guards": [], "type": "vein", "main": "quartz"}}}))).is_equal("quartz")
	assert_str(P0MaterialLogic.rock_ore(Fx.view(3))).is_equal("")   # an older view, no main: the code rock
	assert_str(P0MaterialLogic.rock_ore({})).is_equal("")

func test_a_guard_floor_is_the_contents_beaten_or_not() -> void:
	assert_bool(P0MaterialLogic.guard_floor(Fx.view(20, {"guard": "boss_slime_king_iron"}), 20)).is_true()
	assert_bool(P0MaterialLogic.guard_floor(Fx.view(20, {"mobs": []}), 20)).is_true()   # beaten an earlier day: guard null
	assert_bool(P0MaterialLogic.guard_floor(Fx.view(10, {"type": "quarry", "mobs": []}), 10)).is_true()
	assert_bool(P0MaterialLogic.guard_floor(Fx.view(10), 10)).is_false()   # a vein's F10 is a station, not a guard's
	assert_bool(P0MaterialLogic.guard_floor(Fx.view(5), 5)).is_false()

func test_the_arena_stands_on_rock_bounds_middle_with_two_torch_lights() -> void:
	var arena: Node3D = Art.guard_arena()
	var model: Node3D = Art.kit(Art.ARENA)
	if model == null:
		assert_object(arena).is_null()
		return
	model.free()
	auto_free(arena)
	assert_str(str(arena.name)).is_equal("GuardArena")
	assert_vector(arena.position).is_equal(Vector3(4.9, 0, -3.8))
	assert_int(arena.find_children("*", "OmniLight3D", true, false).size()).is_equal(2)
	assert_int(arena.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)

func _open(v: Dictionary, n: int) -> void:
	P0Runtime.free_instance_for_tests()
	rt = P0Runtime.ensure()
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	await get_tree().process_frame
	rt.session.view = v
	mine = load(P0_MINE).instantiate()
	mine.setup({"mine": Fx.MINE, "floor": n})
	add_child(mine)
	await get_tree().process_frame
	await get_tree().process_frame

func test_the_mine_scene_lays_the_kit_out() -> void:
	# a vein's F20: the iron King's floor and a stop, beaten an earlier day (no guard in the view)
	await _open(Fx.view(20, {"mobs": [], "rocks": 0, "station": true,
		"records": {Fx.MINE: {"deepest": 20, "guards": [20], "type": "vein", "main": "iron_ore"}}}), 20)
	var lift := mine.objects.find_child("MineElevator", false, false) as Node3D
	assert_object(lift).is_not_null()
	assert_object(mine._facilities.get("mine_elevator", {}).get("node", null)).is_same(lift)
	var arena = mine.objects.find_child("GuardArena", false, false)
	var model: Node3D = Art.kit(Art.ARENA)
	assert_bool(arena != null).is_equal(model != null)
	if model: model.free()
	# a vein's F3: its rocks posed by the floor's seed, its iron block where imported
	await _open(Fx.view(3, {"records": {Fx.MINE: {"deepest": 3, "guards": [], "type": "vein", "main": "iron_ore"}}}), 3)
	assert_object(mine.objects.find_child("GuardArena", false, false)).is_null()
	assert_int(mine._rocks.size()).is_equal(5)
	for i in mine._rocks:
		var want: Node3D = auto_free(Art.rock(Vector3.ZERO, i, 1, "iron_ore", "%s:%d:%s" % [Fx.MINE, 3, "2026-11-02"]))
		var pose := (mine._rocks[i] as Node3D).get_node("Rock") as Node3D
		assert_float(pose.rotation.y).is_equal_approx((want.get_node("Rock") as Node3D).rotation.y, 0.0001)
		assert_float(pose.scale.x).is_equal_approx((want.get_node("Rock") as Node3D).scale.x, 0.0001)


func test_q292_scene_enlarges_three_rocks_and_blocks_their_outer_navigation_ring() -> void:
	await _open(Fx.view(3, {"rocks": 3, "mobs": []}), 3)
	assert_int(mine._rocks.size()).is_equal(3)
	var ring_cells := 0
	for rock in mine._rocks.values():
		assert_float((rock.get_node("Rock") as Node3D).scale.x).is_between(1.1699, 1.4301)
		assert_vector(rock.scale).is_equal(Vector3.ONE)
		for y in Layout.SIZE.y:
			for x in Layout.SIZE.x:
				var cell := Vector2i(x, y)
				var d: float = mine.bp.cell_to_world(cell).distance_to(rock.position)
				if d > 0.65 and d < 0.85:
					ring_cells += 1
					assert_bool(mine.bp.is_walkable(cell)).is_false()
	assert_int(ring_cells).is_greater(0)
