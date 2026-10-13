extends GdUnitTestSuite
## The farmhouse interior moves with the Homestead (§8.3.1, q(14); 282 c62a6ed9 ②): Lv1–4 the Basic Room, Lv5–9 the
## Standard Room, Lv10 the Deluxe Room (content homestead.rooms). Each room's kitchen corner keeps the P0 names, so the
## stoves, the Spice Rack and the Warming Cabinet are found, reached and tapped the same way in all three.

const FARMHOUSE := preload("res://scenes/p0/rooms/p0_farmhouse.gd")
const KITCHEN := ["use_stove_1", "drop_pot_1", "badge_stove_1", "cam_stove", "use_stove_2", "drop_pot_2", "badge_stove_2",
	"cam_stove_2", "use_stove_3", "drop_pot_3", "badge_stove_3", "cam_stove_3", "stand_stove", "use_spice_rack",
	"stand_spice_rack", "use_warming_cabinet", "badge_warming_cabinet", "stand_warming_cabinet", "spawn", "exit"]

func _farmhouse(level: int, phone := false) -> P0Room:
	var r: P0Room = FARMHOUSE.new()
	r.use_runtime = false
	r.level = level
	var host: Node = self
	if phone:   # a 360 × 800 portrait screen whatever the runner's window is
		var vp := SubViewport.new()
		vp.size = Vector2i(360, 800)
		add_child(auto_free(vp))
		host = vp
	host.add_child(r)
	auto_free(r)
	return r

func test_the_room_follows_the_homestead_level() -> void:
	var by_level := {}
	for lv in [1, 4, 5, 7, 9, 10]: by_level[lv] = FARMHOUSE.room_for(lv)
	assert_dict(by_level).is_equal({1: "basic", 4: "basic", 5: "standard", 7: "standard", 9: "standard", 10: "deluxe"})
	for lv in [4, 5, 10]:
		var r := _farmhouse(lv)
		var kit := {4: "basic_room", 5: "standard_room_5", 10: "deluxe_room_10"}[lv] as String
		assert_str(r.art.scene_file_path).override_failure_message("Lv%d" % lv).is_equal("res://scenes/%s/%s_art.tscn" % [kit, kit])
		assert_str(r.layout_path).is_equal("res://assets/rooms/%s/layout.json" % kit)

## Every kitchen anchor is there; the stands are reached from the door; the art that takes each tap exists.
func test_each_rooms_kitchen_corner_is_complete_and_reachable() -> void:
	for lv in [1, 5, 10]:
		var r := _farmhouse(lv if lv > 1 else 3)   # Lv3: the Basic Room's rack and cabinet are out
		var label := "Lv%d %s" % [lv, r.get("room_kind")]
		for n in KITCHEN: assert_object(r.anchor(n)).override_failure_message("%s %s" % [label, n]).is_not_null()
		for n in ["stand_stove", "stand_spice_rack", "stand_warming_cabinet", "exit"]:
			assert_array(r.grid.point_path(r.actor.position, r.anchor(n).global_position)).override_failure_message("%s to %s" % [label, n]).is_not_empty()
		for a in r.hit_nodes: assert_bool(r.art.has_node(NodePath(str(r.hit_nodes[a])))).override_failure_message("%s %s" % [label, a]).is_true()
		assert_array(Array(r._tappable())).override_failure_message(label).contains(["use_stove_1", "use_spice_rack", "use_warming_cabinet", "exit"])

## The stoves sit on the cooker's hob (Standard / Deluxe range_cooker.glb), each pot mouth above its own burner.
func test_the_stoves_are_on_the_range_cookers_hob() -> void:
	for lv in [5, 10]:
		var r := _farmhouse(lv)
		var hob := _aabb(r.art.get_node("range_cooker"))
		for i in [1, 2, 3]:
			var p := r.anchor("use_stove_%d" % i).global_position
			var label := "Lv%d stove %d at %s, hob %s" % [lv, i, p, hob]
			assert_bool(p.x > hob.position.x and p.x < hob.end.x and p.z > hob.position.z and p.z < hob.end.z).override_failure_message(label).is_true()
			assert_float(p.y).override_failure_message(label).is_equal_approx(hob.end.y, 0.02)
			assert_float(r.anchor("drop_pot_%d" % i).global_position.y).is_greater(p.y)
		# three distinct burners
		var spots := [1, 2, 3].map(func(i): return Vector2(r.anchor("use_stove_%d" % i).global_position.x, r.anchor("use_stove_%d" % i).global_position.z))
		for a in 3:
			for b in range(a + 1, 3): assert_float((spots[a] as Vector2).distance_to(spots[b])).is_greater(0.25)

## The Warming Cabinet's glow stands in front of its door wherever the room puts the cabinet; the Deluxe Room has none of
## its own (its fittings), and only the Basic Room's hearth burns brighter while a pot cooks.
func test_the_cabinet_glow_and_the_cooking_fire_follow_the_room() -> void:
	var basic := _farmhouse(3)
	assert_vector(basic.art.get_node("warming_cabinet_glow").position).is_equal_approx(Vector3(-2.13, 0.75, -1.69), Vector3.ONE * 0.002)
	assert_object(basic.call("stove_fire")).is_not_null()
	var standard := _farmhouse(5)
	var cab := standard.art.get_node("warming_cabinet") as Node3D
	var glow := standard.art.get_node("warming_cabinet_glow") as Node3D
	assert_float(cab.position.x - glow.position.x).is_equal_approx(0.477, 0.002)   # it faces −X, into the room
	assert_float(glow.position.z).is_equal_approx(cab.position.z, 0.002)
	assert_object(standard.call("stove_fire")).is_null()
	var deluxe := _farmhouse(10)
	assert_bool(deluxe.art.has_node("warming_cabinet_glow")).is_false()
	assert_object(deluxe.call("stove_fire")).is_null()

## Opening the rack's or the cabinet's sheet frames that one: the Standard Room's stand apart.
func test_each_corner_sheet_has_its_own_shot_in_the_bigger_rooms() -> void:
	for lv in [5, 10]:
		var r := _farmhouse(lv)
		for n in ["cam_spice_rack", "cam_warming_cabinet"]: assert_object(r.anchor(n)).override_failure_message("Lv%d %s" % [lv, n]).is_not_null()
	assert_object(_farmhouse(3).anchor("cam_spice_rack")).is_null()   # the Basic Room keeps its one corner shot

## The Deluxe Room opens at its door, its cooker across the room off screen: the stoves' buttons stay with their stoves,
## not pulled onto the screen's edge by the row that keeps crowded stove buttons on screen.
func test_stoves_off_screen_keep_their_buttons_off_screen() -> void:
	var r := _farmhouse(10, true)
	var screen := r.get_viewport().get_visible_rect()
	var spots := {}
	for n in ["use_stove_1", "use_stove_2", "use_stove_3"]:
		spots[n] = r.cam.unproject_position(r.anchor("badge_" + n.trim_prefix("use_")).global_position)
		assert_bool(screen.has_point(spots[n])).override_failure_message("%s on screen at the door: %s" % [n, spots[n]]).is_false()
	assert_dict(r._marker_spots(spots)).is_equal(spots)

static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var box := (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out
