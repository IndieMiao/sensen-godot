extends GdUnitTestSuite
## Indoor P0 spaces (SGODOT-226): anchors (WP7-B F-03 ③), the walkable grid from the art's colliders, and the
## room shell's tap → walk to the stand point → facility callback, run on the accepted Basic Room.

const ROOM_ANCHORS := {"anchors": [
	{"name": "use_stove_1", "position": [-2.05, 1.40, -2.36], "module": "hearth"},
	{"name": "stand_stove", "position": [-2.05, 0.085, -1.55], "yaw_degrees": 0},
	{"name": "cam_stove", "position": [-1.9, 1.3, -2.2]},
	{"name": "use_stove_2", "position": [-0.9, 1.25, -2.6], "module": "stove_2"},
	{"name": "spawn", "position": [2.03, 0.085, -1.9], "yaw_degrees": 180},
	{"name": "exit", "position": [2.03, 0.085, -2.55]},
]}

class Sample extends P0Room:
	var used: Array = []
	func setup(_a: Dictionary) -> void:
		use_runtime = false
		place_name = "Farmhouse"
	func _on_facility(n: String) -> void: used.append(n)

func _room(external := ROOM_ANCHORS) -> Sample:
	var path := "user://test_room.anchors.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(external))
	f.close()
	var r := Sample.new()
	r.setup({})
	r.anchors_path = path
	add_child(r)
	auto_free(r)
	return r

func _walk_until_idle(r: P0Room, seconds := 6.0) -> void:
	var t := 0.0
	while t < seconds and not r.p0_until("idle"):
		r.p0_frame({}, 1.0 / 30.0)
		t += 1.0 / 30.0
	r.p0_frame({}, 1.0 / 30.0)

# ---------------------------------------------------------------- anchors
func test_external_anchors_override_layout_by_name_and_spawn_falls_back() -> void:
	var layout := {"spawn": [1.4, 0.085, 1.65], "anchors": [{"name": "use_counter", "position": [0, 1, 0]}]}
	var merged := P0RoomAnchors.merge(layout, {"anchors": [{"name": "use_counter", "position": [1, 1, 1]}]})
	assert_int(merged.size()).is_equal(2)
	assert_that(merged[0].position).is_equal([1, 1, 1])
	assert_str(merged[1].name).is_equal("spawn")
	assert_that(merged[1].position).is_equal([1.4, 0.085, 1.65])
	# An authored spawn wins over the legacy point.
	var own := P0RoomAnchors.merge(layout, {"anchors": [{"name": "spawn", "position": [0, 0, 0], "yaw_degrees": 90}]})
	assert_that(own.filter(func(a): return a.name == "spawn")[0].position).is_equal([0, 0, 0])

func test_stand_point_lookup_follows_the_naming_table() -> void:
	var names := ["use_stove_1", "stand_stove", "use_counter", "stand_counter", "use_stall_2", "stand_stall_2"]
	assert_str(P0RoomAnchors.stand_for("use_stove_1", names)).is_equal("stand_stove")
	assert_str(P0RoomAnchors.stand_for("use_counter", names)).is_equal("stand_counter")
	assert_str(P0RoomAnchors.stand_for("use_stall_2", names)).is_equal("stand_stall_2")
	assert_str(P0RoomAnchors.stand_for("npc_keeper", names)).is_equal("")
	assert_str(P0RoomAnchors.object_of("seat_table1_2")).is_equal("table1_2")
	assert_str(P0RoomAnchors.prefix_of("exit")).is_equal("exit")

func test_validation_reports_each_naming_rule() -> void:
	var errors := P0RoomAnchors.validate([
		{"name": "use_stove_1", "position": [0, 0, 0], "module": "hearth"},
		{"name": "use_stove_1", "position": [0, 0, 0]},
		{"name": "anchor_pot_1", "position": [0, 0, 0]},
		{"name": "npc_keeper", "position": [0, 0, 0]},
		{"name": "sign_name", "position": [0, 0, 0], "yaw_degrees": 180},
		{"name": "use_fish_loop", "position": [0, 0, 0]},
		{"name": "use_Counter", "position": [0, 0, 0]},
		{"name": "use_rack", "position": [0, 0, 0], "module": "no_such_module"},
	], ["hearth"])
	var text := "\n".join(errors)
	for expect in ["use_stove_1: duplicate", "anchor_pot_1: unknown prefix", "npc_keeper: needs yaw_degrees",
			"sign_name: needs size", "use_fish_loop: ends in the Godot import hint", "use_Counter: use lower-case",
			"use_rack: unknown module"]:
		assert_str(text).contains(expect)
	assert_int(errors.size()).is_equal(7)

func test_the_placeholder_anchor_files_pass_validation() -> void:
	var layout := P0RoomAnchors.read_json(P0Room.BASIC_ROOM_LAYOUT)
	var modules: Array = layout.assets.map(func(a): return str(a.name)) + layout.instances.map(func(a): return str(a.name))
	for path in _anchor_files("res://assets/p0"):
		var errors := P0RoomAnchors.validate(P0RoomAnchors.merge(layout, P0RoomAnchors.read_json(path)), modules)
		assert_array(errors).override_failure_message(path + "\n" + "\n".join(errors)).is_empty()

func _anchor_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null: return out
	for sub in d.get_directories(): out.append_array(_anchor_files(dir + "/" + sub))
	for file in d.get_files():
		if file.ends_with(".anchors.json"): out.append(dir + "/" + file)
	return out

# ---------------------------------------------------------------- walkable grid
func test_rotated_boxes_and_cylinders_block_with_the_player_radius() -> void:
	var floor_box := {kind = "box", xform = Transform3D(Basis.IDENTITY, Vector3(0, -0.1, 0)), size = Vector3(4, 0.2, 4)}
	var table := {kind = "box", xform = Transform3D(Basis(Vector3.UP, deg_to_rad(45)), Vector3(0, 0.5, 0)), size = Vector3(1, 1, 1)}
	var plant := {kind = "cylinder", xform = Transform3D(Basis.IDENTITY, Vector3(1.5, 0.2, 1.5)), radius = 0.2, height = 0.4}
	var nav := P0RoomNav.build([floor_box, table, plant], 0.1, 0.2)
	var bp: FarmBlueprint = nav.bp
	var off: Vector3 = nav.offset
	assert_float(nav.floor_y).is_equal_approx(0.0, 0.001)
	assert_that(bp.grid).is_equal(Vector2i(40, 40))
	var walkable := func(x: float, z: float) -> bool: return bp.is_walkable(bp.world_to_cell(Vector3(x, 0, z) + off))
	assert_bool(walkable.call(0.0, 0.0)).is_false()          # under the table
	assert_bool(walkable.call(0.85, 0.0)).is_false()         # inside the rotated corner (0.707) + radius
	assert_bool(walkable.call(0.75, 0.75)).is_true()         # a 45° box leaves its old square corner free
	assert_bool(walkable.call(1.5, 1.5)).is_false()          # the plant
	assert_bool(walkable.call(-1.5, -1.5)).is_true()

func test_basic_room_grid_keeps_furniture_solid_and_connects_door_and_stove() -> void:
	var r := _room()
	var bp := r.bp
	var at := func(x: float, z: float) -> Vector3: return Vector3(x, 0, z) + r.room.position
	assert_bool(bp.is_walkable(bp.world_to_cell(at.call(-0.12, 0.62)))).override_failure_message("dining table").is_false()
	assert_bool(bp.is_walkable(bp.world_to_cell(at.call(-2.05, -2.57)))).override_failure_message("hearth").is_false()
	assert_bool(bp.is_walkable(bp.world_to_cell(at.call(-3.1, 0.0)))).override_failure_message("window wall").is_false()
	assert_bool(bp.is_walkable(bp.world_to_cell(at.call(2.68, -2.07)))).override_failure_message("floor plant").is_false()
	var path := r.grid.point_path(r.anchor("spawn").global_position, r.anchor("stand_stove").global_position)
	assert_array(path).override_failure_message("no path from the door to the stove").is_not_empty()
	assert_float(r.floor_y).is_equal_approx(0.08, 0.01)

# ---------------------------------------------------------------- room shell
func test_hidden_modules_hide_their_anchors() -> void:
	var r := _room()
	assert_object(r.anchor("use_stove_1")).is_not_null()
	assert_object(r.anchor("use_stove_2")).override_failure_message("stove_2 is not in the Basic Room").is_null()
	assert_int(r.anchors("use_").size()).is_equal(1)
	r.module_levels = {"hearth": 2}
	r.refresh_modules()
	assert_object(r.anchor("use_stove_1")).is_null()
	assert_bool(r.p0_surface() == "room").is_true()

func test_spawn_faces_into_the_room() -> void:
	var r := _room()
	var spawn := r.anchor("spawn").global_position
	assert_float(P0Room._flat_distance(r.actor.position, spawn)).is_less(0.2)
	assert_float(r.actor.facing().z).is_greater(0.9)   # yaw 180 = towards the camera side (+Z)
	assert_vector(P0Room.yaw_dir(90)).is_equal_approx(Vector3(-1, 0, 0), Vector3.ONE * 0.001)

func test_tapping_a_facility_walks_to_its_stand_point_then_calls_back() -> void:
	var r := _room()
	var seen: Array = []
	r.facility_tapped.connect(func(n): seen.append(n))
	var screen := r.cam.unproject_position(r.anchor("use_stove_1").global_position)
	assert_str(r.pick(screen)).is_equal("use_stove_1")
	assert_str(r.pick(screen + Vector2(200, 200))).is_equal("")
	r.p0_tap(screen)
	_walk_until_idle(r)
	assert_array(r.used).is_equal(["use_stove_1"])
	assert_array(seen).is_equal(["use_stove_1"])
	assert_float(P0Room._flat_distance(r.actor.position, r.anchor("stand_stove").global_position)).is_less(P0Room.REACH_M)

func test_joystick_cancels_a_walk_and_the_door_only_leaves_after_stepping_away() -> void:
	var r := _room()
	var left := [0]
	r.left.connect(func(): left[0] += 1)
	r.walk_to("use_stove_1")
	r.p0_joystick(Vector2(0.5, 0))
	r.p0_frame({}, 0.1)
	r.p0_joystick(Vector2.ZERO)
	_walk_until_idle(r, 1.0)
	assert_array(r.used).is_empty()
	# Spawn sits next to the door: standing there does not leave …
	var door := r.anchor("exit").global_position
	r.actor.teleport(r.anchor("spawn").global_position)
	r.p0_frame({}, 0.1)
	assert_int(left[0]).is_equal(0)
	# … stepping away and back onto the door does, once.
	r.actor.teleport(Vector3(door.x - 1.6, r.floor_y, door.z + 1.2))
	r.p0_frame({}, 0.1)
	r.actor.teleport(Vector3(door.x, r.floor_y, door.z))
	r.p0_frame({}, 0.1)
	r.p0_frame({}, 0.1)
	assert_int(left[0]).is_equal(1)

func test_push_in_puts_the_stove_in_the_band_above_the_drawer() -> void:
	var r := _room()
	r.focus("cam_stove")
	r._shot_k = 1.0
	r._update_camera()
	var view := r.get_viewport().get_visible_rect().size
	var band := r.band_below_hud(0.40)
	var y := r.cam.unproject_position(r.anchor("cam_stove").global_position).y / view.y
	assert_float(y).is_equal_approx(band.get_center().y, 0.01)
	r.release_focus()
	r._shot_k = 0.0
	r._shot = {}
	r._update_camera()
	assert_bool(r.is_focused()).is_false()

# ---------------------------------------------------------------- farmhouse (placeholder Basic Room)
const FARMHOUSE := preload("res://scenes/p0/rooms/p0_farmhouse.gd")

func _farmhouse() -> P0Room:
	var r: P0Room = FARMHOUSE.new()
	r.use_runtime = false
	add_child(r)
	auto_free(r)
	return r

func test_farmhouse_opens_on_the_stove_corner_with_a_door_back_to_the_farm() -> void:
	var r := _farmhouse()
	for n in ["use_stove_1", "drop_pot_1", "badge_stove_1", "stand_stove", "cam_stove", "spawn", "exit"]:
		assert_object(r.anchor(n)).override_failure_message(n).is_not_null()
	assert_str(r.place_name).is_equal("Farmhouse")
	assert_dict(r._marker("exit", {})).is_equal({text = "Door · Back to farm"})
	assert_array(Array(r._tappable())).contains_exactly_in_any_order(["use_stove_1", "exit"])
	assert_array(r.grid.point_path(r.actor.position, r.anchor("stand_stove").global_position)).is_not_empty()
	# The opening shot keeps the stove and the door on screen.
	var view := r.get_viewport().get_visible_rect()
	for n in ["use_stove_1", "exit"]:
		assert_bool(view.has_point(r.cam.unproject_position(r.anchor(n).global_position))).override_failure_message(n).is_true()

func test_farmhouse_stove_card_and_badge_follow_the_server_stove() -> void:
	var r := _farmhouse()
	var empty := r._marker("use_stove_1", {"cooking": {"stove": null}})
	assert_str(empty.text).is_equal("Stove 1/1 · Empty · Tap to cook")
	assert_str(empty.badge).is_equal("available")
	var cooking := r._marker("use_stove_1", {"cooking": {"stove": {"ready_in": 22000, "dish": "dish_grilled_crucian"}}})
	assert_str(cooking.text).is_equal("Stove 1/1 · Cooking 0:22")
	assert_str(cooking.badge).is_equal("countdown")
	assert_str(cooking.caption).is_equal("0:22")
	var ready := r._marker("use_stove_1", {"cooking": {"stove": {"ready_in": 0, "dish": null}}})
	assert_str(ready.text).is_equal("Stove · Ready · Unknown dish")
	assert_str(ready.badge).is_equal("ready")

func test_a_room_that_fits_the_screen_holds_its_framing_while_walking() -> void:
	var r := _farmhouse()
	assert_bool(r._fits).override_failure_message("the Basic Room fits a portrait screen").is_true()
	var before := r.cam.global_position
	r.p0_joystick(Vector2(1, 0))
	for i in 20: r.p0_frame({}, 1.0 / 30.0)
	r.p0_joystick(Vector2.ZERO)
	for i in 40: r.p0_frame({}, 1.0 / 30.0)
	assert_float(P0Room._flat_distance(r.actor.position, r.anchor("spawn").global_position)).is_greater(0.3)
	assert_vector(r.cam.global_position).is_equal_approx(before, Vector3.ONE * 0.001)
	# Zoomed in, the safe box follows the player again.
	r.p0_zoom(1.0 / 1.4)
	r.p0_joystick(Vector2(-1, 0))
	for i in 30: r.p0_frame({}, 1.0 / 30.0)
	assert_bool(r.cam.global_position.is_equal_approx(before)).is_false()
