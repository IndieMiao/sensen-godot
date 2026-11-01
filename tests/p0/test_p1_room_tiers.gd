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
	for lv in [1, 4, 5, 7, 10, 11, 12, 17]: by_level[lv] = FARMHOUSE.room_for(lv)
	assert_dict(by_level).is_equal({1: "basic", 4: "basic", 5: "standard", 7: "standard", 10: "standard", 11: "standard",
		12: "deluxe", 17: "deluxe"})   # the Deluxe Room at Lv12 since v4q(1) ⑧ (q(14)'s Lv10)
	for lv in [4, 5, 12]:
		var r := _farmhouse(lv)
		var kit := {4: "basic_room", 5: "standard_room_5", 12: "deluxe_room_10"}[lv] as String
		assert_str(r.art.scene_file_path).override_failure_message("Lv%d" % lv).is_equal("res://scenes/%s/%s_art.tscn" % [kit, kit])
		assert_str(r.layout_path).is_equal("res://assets/rooms/%s/layout.json" % kit)

## Every kitchen anchor is there; the stands are reached from the door; the art that takes each tap exists.
func test_each_rooms_kitchen_corner_is_complete_and_reachable() -> void:
	for lv in [1, 5, 12]:   # the three rooms (Deluxe at Lv12, v4q(1))
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

## The Warming Cabinet's glow sits at the model's glow socket, inside it, wherever the room puts the cabinet; the Deluxe Room has none of
## its own (its fittings), and only the Basic Room's hearth burns brighter while a pot cooks.
func test_the_cabinet_glow_and_the_cooking_fire_follow_the_room() -> void:
	var basic := _farmhouse(3)
	# the model's glow socket (0, 0.795, 0.25), its back at x −2.850 facing +X (SGODOT-282 warming_cabinet.glb)
	assert_vector(basic.art.get_node("warming_cabinet_glow").position).is_equal_approx(Vector3(-2.6, 0.877, -1.69), Vector3.ONE * 0.002)
	assert_object(basic.call("stove_fire")).is_not_null()
	var standard := _farmhouse(5)
	var cab := standard.art.get_node("warming_cabinet") as Node3D
	var glow := standard.art.get_node("warming_cabinet_glow") as Node3D
	assert_float(glow.position.x - cab.position.x).is_equal_approx(0.25, 0.002)   # it faces +X, as in the Basic Room
	assert_float(glow.position.z).is_equal_approx(cab.position.z, 0.002)
	assert_object(standard.call("stove_fire")).is_null()
	var deluxe := _farmhouse(12)
	assert_bool(deluxe.art.has_node("warming_cabinet_glow")).is_false()
	assert_object(deluxe.call("stove_fire")).is_null()

## The Warming Cabinet model (SGODOT-282, glass option B; 上官婉儿's notes): its own materials — no atlas override, which
## would cover the dishes — with the room's specular 0.28; all six dishes; scale 1 and its 0.56 × 1.32 × 0.50 collider;
## use_warming_cabinet on its top_center.
func test_the_warming_cabinet_is_the_model_with_its_own_materials() -> void:
	for lv in [3, 5]:
		var r := _farmhouse(lv)
		var cab := r.art.get_node("warming_cabinet") as Node3D
		assert_vector(cab.scale).is_equal(Vector3.ONE)
		var meshes := cab.find_children("*", "MeshInstance3D", true, false)
		assert_int(meshes.size()).is_equal(8)   # the cabinet, dish_1 … dish_6 and the door's two highlights
		for m in meshes:
			var mi := m as MeshInstance3D
			assert_object(mi.material_override).is_null()
			for i in mi.mesh.get_surface_count():
				assert_float((mi.get_surface_override_material(i) as BaseMaterial3D).metallic_specular).is_equal_approx(0.28, 0.001)
		r.call("show_cabinet_plates", 6)
		for i in range(1, 7): assert_bool((cab.find_child("dish_%d" % i, true, false) as Node3D).visible).is_true()
		var box := (cab.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D).shape as BoxShape3D
		assert_vector(box.size).is_equal_approx(Vector3(0.56, 1.32, 0.5), Vector3.ONE * 0.001)
		var top := (cab.find_child("top_center", true, false) as Node3D).global_position
		assert_vector(r.anchor("use_warming_cabinet").global_position).is_equal_approx(top, Vector3.ONE * 0.002)

## q(202): the cabinet shows a plate a dish it holds — dish_1 … dish_N — none when empty, six from six up; the warm
## light stays on either way.
func test_the_cabinet_shows_a_plate_a_dish() -> void:
	var cab := {"have": 0, "cap": 12}
	var plates := func(have: int) -> int:
		cab.have = have
		return P0KitchenLogic.cabinet_plates({"cooking": {"cabinet": cab}})
	assert_array([0, 1, 4, 6, 9, 12].map(func(n): return plates.call(n))).is_equal([0, 1, 4, 6, 6, 6])
	assert_int(P0KitchenLogic.cabinet_plates({"cooking": {}})).is_equal(0)
	for lv in [3, 5]:
		var r := _farmhouse(lv)
		var cabinet := r.art.get_node("warming_cabinet")
		for n in [0, 3, 6]:
			r.call("show_cabinet_plates", n)
			var shown := range(1, 7).filter(func(i): return (cabinet.find_child("dish_%d" % i, true, false) as Node3D).visible)
			assert_array(shown).is_equal(range(1, n + 1))
		assert_bool((r.art.get_node("warming_cabinet_glow") as Node3D).visible).is_true()

## The cabinet shows its door, not its back (不知火舞 on 282: by the Standard Room's east wall it faced away from the camera).
func test_the_warming_cabinet_faces_the_camera() -> void:
	for lv in [3, 5]:
		var r := _farmhouse(lv)
		var cab := r.art.get_node("warming_cabinet") as Node3D
		var front := cab.global_transform.basis.z.normalized()
		var to_cam := Vector3(r._cam_dir.x, 0.0, r._cam_dir.z).normalized()
		assert_float(front.dot(to_cam)).override_failure_message("Lv%d: the cabinet's back to the camera" % lv).is_greater(0.3)
		assert_array(r.grid.point_path(r.actor.position, r.anchor("stand_warming_cabinet").global_position)).is_not_empty()

## Opening the rack's or the cabinet's sheet frames that one: the Standard Room's stand apart.
func test_each_corner_sheet_has_its_own_shot_in_the_bigger_rooms() -> void:
	for lv in [5, 12]:
		var r := _farmhouse(lv)
		for n in ["cam_spice_rack", "cam_warming_cabinet"]: assert_object(r.anchor(n)).override_failure_message("Lv%d %s" % [lv, n]).is_not_null()
	assert_object(_farmhouse(3).anchor("cam_spice_rack")).is_null()   # the Basic Room keeps its one corner shot

## The Deluxe Room opens at its door, its cooker across the room off screen: the stoves' buttons stay with their stoves,
## not pulled onto the screen's edge by the row that keeps crowded stove buttons on screen.
func test_stoves_off_screen_keep_their_buttons_off_screen() -> void:
	var r := _farmhouse(12, true)
	var screen := r.get_viewport().get_visible_rect()
	var spots := {}
	for n in ["use_stove_1", "use_stove_2", "use_stove_3"]:
		spots[n] = r.cam.unproject_position(r.anchor("badge_" + n.trim_prefix("use_")).global_position)
		assert_bool(screen.has_point(spots[n])).override_failure_message("%s on screen at the door: %s" % [n, spots[n]]).is_false()
	assert_dict(r._marker_spots(spots)).is_equal(spots)

## Upgraded inside (HOME-1 from Profile is at home here too): the farmhouse reopens in its next room once — after the
## level-up's banner and look cards and anything queued behind them, the stove idle — and not for a level in the same room.
func test_an_upgrade_inside_reopens_the_farmhouse_in_its_next_room() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	var r := _farmhouse(4)
	r.rt = rt
	var calls := [0]
	var router_busy := [true]
	r.set("reopen", func() -> bool:
		calls[0] += 1
		return not router_busy[0])
	r.call("check_room", {"homestead": {"level": 4}})
	assert_int(calls[0]).is_equal(0)   # the same room
	var banner := Control.new()
	rt.ui._open_modal(banner, 0.0)   # the level-up's banner is up
	rt.ui.queue_card(func(): pass)    # and a look card waits behind it
	r.call("check_room", {"homestead": {"level": 5}})
	assert_int(calls[0]).is_equal(0)
	rt.ui.close_modal()
	rt.ui._card_queue.clear()
	await get_tree().process_frame
	r.call("check_room", {"homestead": {"level": 5}})
	assert_int(calls[0]).is_equal(1)   # the router busy (another way in or out under way): not taken …
	router_busy[0] = false
	r.call("check_room", {"homestead": {"level": 5}})
	assert_int(calls[0]).is_equal(2)   # … so the next frame tries again, and it is taken
	r.call("check_room", {"homestead": {"level": 5}})
	assert_int(calls[0]).is_equal(2)   # once taken, never again
	var std := _farmhouse(6)
	std.rt = rt
	std.set("reopen", func() -> bool:
		calls[0] += 10
		return true)
	std.call("check_room", {"homestead": {"level": 9}})
	assert_int(calls[0]).is_equal(2)   # Lv6 → Lv9: still the Standard Room

static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var box := (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out
