extends GdUnitTestSuite

const FarmCamera = preload("res://modules/farm/farm_camera.gd")
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
	# Each file against its own room kit: an outpost's art (p0_outposts.json), else the Basic Room (SGODOT-227).
	var kit_of := {}
	for o in P0Outposts.all(): kit_of[str(o.anchors)] = str(o.get("art", "basic_room"))
	for path in _anchor_files("res://assets/p0"):
		var layout := P0RoomAnchors.read_json("res://assets/rooms/%s/layout.json" % kit_of.get(path, "basic_room"))
		var modules: Array = layout.get("assets", []).map(func(a): return str(a.name)) + layout.get("instances", []).map(func(a): return str(a.name))
		var external := P0RoomAnchors.read_json(path)
		var known: Array = modules + P0RoomAnchors.props(external).map(func(p): return str(p.name))
		var errors := P0RoomAnchors.validate(P0RoomAnchors.merge(layout, external), known)
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

func _farmhouse(level := 1) -> P0Room:
	var r: P0Room = FARMHOUSE.new()
	r.use_runtime = false
	r.level = level
	add_child(r)
	auto_free(r)
	return r

## SGODOT-235 (LOCK-07 v1 retired with UiTapCard): every marker the farmhouse and a plain room hang has a kind; the
## door is i-door + Farm (a plain room's: Map).
func test_every_room_marker_is_a_world_prompt() -> void:
	for r in [_farmhouse(), _room()]:
		for n in r._tappable():
			var m: Dictionary = r._marker(n, {})
			if m.is_empty(): continue
			assert_str(str(m.get("kind", ""))).override_failure_message(n).is_not_empty()
			assert_bool(m.has("text")).override_failure_message(n).is_false()
	assert_str(str(_farmhouse()._marker("exit", {}).get("name", ""))).is_equal("Farm")
	assert_str(str(_room()._marker("exit", {}).get("name", ""))).is_equal("Map")

## Show from inside the farmhouse (亚瑟 on #37): the stove is the room's own spot; farm targets are not, so the
## runtime steps out to the farm and shows them there.
func test_farmhouse_has_the_stove_spot_but_not_the_farms() -> void:
	var r := _farmhouse()
	assert_bool(r.p0_has_spot("stove")).is_true()
	for where in ["plots", "stall", "bench", "home"]: assert_bool(r.p0_has_spot(where)).override_failure_message(where).is_false()

func test_farmhouse_opens_on_the_stove_corner_with_a_door_back_to_the_farm() -> void:
	var r := _farmhouse()
	for n in ["use_stove_1", "drop_pot_1", "badge_stove_1", "stand_stove", "cam_stove", "spawn", "exit"]:
		assert_object(r.anchor(n)).override_failure_message(n).is_not_null()
	assert_str(r.place_name).is_equal("Farmhouse")
	assert_dict(r._marker("exit", {})).is_equal({kind = "facility", icon = P0Logic.icon("door"), name = "Farm"})   # 250: i-door + Farm
	assert_array(Array(r._tappable())).contains_exactly_in_any_order(["use_stove_1", "exit"])
	assert_array(r.grid.point_path(r.actor.position, r.anchor("stand_stove").global_position)).is_not_empty()
	# The opening shot keeps the stove and the door on screen.
	var view := r.get_viewport().get_visible_rect()
	for n in ["use_stove_1", "exit"]:
		assert_bool(view.has_point(r.cam.unproject_position(r.anchor(n).global_position))).override_failure_message(n).is_true()

func test_the_room_has_one_hearth_lamp_ahead_of_the_art() -> void:
	# The Basic Room's particle fire (PR #29) looks for ../HearthGlow when the art enters the tree; it must find
	# the room's lamp rather than add a second one.
	var r := _farmhouse()
	var lamps := r.room.find_children("HearthGlow", "OmniLight3D", true, false)
	assert_int(lamps.size()).is_equal(1)
	assert_int(lamps[0].get_index()).is_less(r.art.get_index())
	assert_object(r.room.get_node_or_null("HearthGlow")).is_not_null()
	# …and the fire drives that very lamp (its light_path is relative to the fire node, Hou Yi's review on #32).
	var fire: Node = r.art.get("fire")
	assert_object(fire.get_node_or_null(fire.get("light_path"))).is_same(r.room.get_node("HearthGlow"))

func test_the_kitchen_corner_grows_with_the_homestead() -> void:
	# Lv1: no Spice Rack, no Warming Cabinet (props hidden, their anchors absent, nothing to tap).
	var lv1 := _farmhouse(1)
	assert_bool(lv1.art.get_node("spice_rack").visible).is_false()
	assert_bool(lv1.art.get_node("warming_cabinet").visible).is_false()
	assert_object(lv1.anchor("use_warming_cabinet")).is_null()
	assert_array(Array(lv1._tappable())).not_contains(["use_spice_rack", "use_warming_cabinet"])
	# Lv2: the rack; Lv3: the cabinet too, with its glow, a collider in the walkable grid and a reachable stand.
	var lv2 := _farmhouse(2)
	assert_bool(lv2.art.get_node("spice_rack").visible).is_true()
	assert_bool(lv2.art.get_node("warming_cabinet").visible).is_false()
	var lv3 := _farmhouse(3)
	assert_array(Array(lv3._tappable())).contains(["use_spice_rack", "use_warming_cabinet"])
	assert_bool(lv3.art.get_node("warming_cabinet_glow").visible).is_true()
	var cab := lv3.anchor("use_warming_cabinet").global_position
	assert_bool(lv3.bp.is_walkable(lv3.bp.world_to_cell(Vector3(cab.x, 0, cab.z)))).override_failure_message("the cabinet blocks the floor").is_false()
	assert_array(lv3.grid.point_path(lv3.actor.position, lv3.anchor("stand_warming_cabinet").global_position)).is_not_empty()
	assert_str(str(lv3._marker("use_spice_rack", {}).name)).is_equal("Spice Rack")
	assert_str((lv3._marker("use_spice_rack", {}).icon as Texture2D).resource_path).is_equal("res://assets/p0/icons/spice_rack.svg")   # i-spice-rack
	var cab_mark := lv3._marker("use_warming_cabinet", {"cooking": {"cabinet": {"cap": 6, "have": 6, "items": []}}})
	assert_str(str(cab_mark.name)).is_equal("Warming Cabinet")
	assert_str(str(cab_mark.fact)).is_equal("Full")
	assert_str(str(cab_mark.count)).is_equal("Full")   # C21: its button hangs the count from afar
	assert_str(str(lv3._marker("use_warming_cabinet", {"cooking": {"cabinet": {"cap": 6, "have": 4, "items": []}}}).count)).is_equal("4/6")
	assert_str(str(lv3._marker("use_warming_cabinet", {"cooking": {"cabinet": {"cap": 6, "have": 0, "items": []}}}).count)).is_equal("")
	assert_str((cab_mark.icon as Texture2D).resource_path).is_equal("res://assets/p0/icons/cabinet.svg")   # i-cabinet

func test_farmhouse_stove_card_and_badge_follow_the_server_stove() -> void:
	var r := _farmhouse()
	# SGODOT-250 (q(62) "Stove 1/1 · Empty"): i-pot + name + one fact; the stove's state rides as its status mark.
	var empty := r._marker("use_stove_1", {"cooking": {"stove": null}})
	assert_str(str(empty.kind)).is_equal("facility")
	assert_str(str(empty.name)).is_equal("Stove 1/1")
	assert_str(str(empty.fact)).is_equal("Empty")
	assert_bool(empty.has("badge")).is_false()   # an empty stove shows the pot, no status
	var cooking := r._marker("use_stove_1", {"cooking": {"stove": {"ready_in": 22000, "dish": "dish_grilled_crucian"}}})
	assert_str(str(cooking.fact)).is_equal("Cooking 0:22")
	assert_str(str(cooking.badge)).is_equal("countdown")
	var ready := r._marker("use_stove_1", {"cooking": {"stove": {"ready_in": 0, "dish": null}}})
	assert_str(str(ready.fact)).is_equal("Unknown dish")
	assert_str(str(ready.badge)).is_equal("ready")
	for n in r._tappable():   # no Tap to anywhere in the farmhouse
		assert_bool(r._marker(n, {}).has("text")).override_failure_message(n).is_false()

## One player scale (用户 2026-10-09): the farm's own camera at 43° gives the P0 farm's 6.72 m on 360 × 800, and a
## flatter camera needs a wider view by cos(pitch) / cos(43°) for the player to stand as tall.
func test_the_player_scale_size_is_the_farms_view_at_its_pitch() -> void:
	var view := Vector2(360, 800)
	assert_float(FarmCamera.player_scale_size(view, FarmCamera.PITCH_DEG)).is_equal_approx(6.72, 0.0001)
	assert_float(FarmCamera.player_scale_size(view, 24.8)).is_equal_approx(6.72 * cos(deg_to_rad(24.8)) / cos(deg_to_rad(43.0)), 0.0001)
	assert_float(FarmCamera.player_scale_size(view, 24.8)).is_greater(FarmCamera.player_scale_size(view, 37.0))

## Camera unification (用户 2026-10-09; 不知火舞 on 226): the farmhouse shows the player at the farm's scale, which
## supersedes the whole-room diorama opening; it pans across inside its art, follows the player as they walk, and its
## push-ins keep framing from the whole room's width.
func test_the_room_shows_the_player_at_the_farms_scale_and_pans_inside_its_art() -> void:
	var r := _farmhouse()
	_assert_player_scale_framing(r, "farmhouse")
	assert_float(r.view_size()).is_greater(r.cam.size)   # push-ins still frame from the whole room
	r.frame_all()   # straight onto the player at the door, the view stopped at the art's edge
	assert_bool(r._fits).override_failure_message("wider than the band at the player's scale").is_false()
	var before := r.cam.global_position
	r.p0_joystick(Vector2(-1, 0))   # into the room, away from that edge
	for i in 60: r.p0_frame({}, 1.0 / 30.0)
	r.p0_joystick(Vector2.ZERO)
	for i in 40: r.p0_frame({}, 1.0 / 30.0)
	assert_float(P0Room._flat_distance(r.actor.position, r.anchor("spawn").global_position)).is_greater(0.3)
	assert_bool(r.cam.global_position.is_equal_approx(before)).override_failure_message("follows across").is_false()
	var e := _art_edges_px(r)   # never more than SIDE_MARGIN of backdrop beside the art
	assert_float(maxf(float(e.left), float(e.right))).override_failure_message(str(e)).is_less_equal(P0Room.SIDE_MARGIN + 0.5)

## 不知火舞 on #127: with Bag alone at the bottom (a room) the room centres down to the safe bottom's 24 px — lower than
## the quick bar's top — but its lowest point keeps 8 px above Bag's top.
func test_with_bag_alone_the_room_frames_lower_and_clears_bag() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.ui.set_surface("room")
	await get_tree().process_frame
	assert_bool(rt.ui.bag_only()).is_true()
	var r := _farmhouse()
	r.rt = rt
	var e_full := _art_edges_px(r)   # framed before the room knew its UI: the quick bar's band
	r.frame_all()
	var e := _art_edges_px(r)
	var view := r._view()
	var bag_top := view.y - (UiTokens.SIZE_QUICK_BAR_BOTTOM + UiTokens.SIZE_QUICK_BAR_H)
	var art_bottom := view.y - (UiTokens.SIZE_QUICK_BAR_BOTTOM + UiTokens.SIZE_QUICK_BAR_H) - float(e.bottom)   # px from the top
	assert_float(art_bottom).override_failure_message(str(e)).is_less_equal(bag_top - P0Room.BAG_CLEAR + 0.5)
	var art_top := float(P0Room.HUD_BOTTOM) + float(e.top)
	var centred := absf((art_top - P0Room.HUD_BOTTOM) - (view.y - UiTokens.SIZE_QUICK_BAR_BOTTOM - art_bottom)) < 1.0
	var on_guard := absf(art_bottom - (bag_top - P0Room.BAG_CLEAR)) < 0.5
	assert_bool(centred or on_guard).override_failure_message("top %.1f bottom %.1f" % [art_top, art_bottom]).is_true()
	assert_float(float(e.top)).override_failure_message("lower than with the quick bar").is_greater(float(e_full.top))

## Camera unification (用户 2026-10-09): where the room's art edges sit on screen, in px — across from the screen's left
## and right edges, down from the HUD's bottom and to the quick bar's top (the free band P0Room keeps the art in).
func _art_edges_px(r: P0Room) -> Dictionary:
	var forward := -r._cam_dir
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	var view := r._view()
	var px := view.x / r.cam.size
	var cx := r.cam.global_position.dot(right)
	var cy := r.cam.global_position.dot(up)
	var half_h := r.cam.size * 0.5 * view.y / view.x
	var top_band := float(P0Room.HUD_BOTTOM)
	var bottom_band := view.y - (UiTokens.SIZE_QUICK_BAR_BOTTOM + UiTokens.SIZE_QUICK_BAR_H)
	return {left = (r._bounds_lo.x - (cx - r.cam.size * 0.5)) * px, right = (cx + r.cam.size * 0.5 - r._bounds_hi.x) * px,
		top = (cy + half_h - r._bounds_hi.y) * px - top_band, bottom = bottom_band - (cy + half_h - r._bounds_lo.y) * px}

## Pushes the camera's centre `by` along the screen axes (metres) and lets the room keep it inside its art.
func _push_view(r: P0Room, by: Vector2) -> void:
	var forward := -r._cam_dir
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward).normalized()
	r._focus += right * by.x + up * by.y
	r._update_camera()

## The player stands as tall as on the farm; across, a room wider than the free band pans and stops with its art's
## edge SIDE_MARGIN from the screen's; down, a room that fits the band holds centred in it (不知火舞 on 226).
func _assert_player_scale_framing(r: P0Room, label: String) -> void:
	var pitch := rad_to_deg(asin(r._cam_dir.y))
	assert_float(r.cam.size).override_failure_message(label + " size").is_equal_approx(FarmCamera.player_scale_size(r._view(), pitch), 0.001)
	for side in [-1.0, 1.0]:
		_push_view(r, Vector2(side * 100.0, 0.0))
		var e := _art_edges_px(r)
		var edge: float = e.left if side < 0.0 else e.right
		if edge > P0Room.SIDE_MARGIN + 0.5:   # narrower than the band: centred instead
			assert_float(absf(float(e.left) - float(e.right))).override_failure_message("%s centred across %s" % [label, e]).is_less(1.0)
		else:
			assert_float(edge).override_failure_message("%s edge %s" % [label, e]).is_equal_approx(P0Room.SIDE_MARGIN, 0.5)
	for side in [-1.0, 1.0]:
		_push_view(r, Vector2(0.0, side * 100.0))
		var e := _art_edges_px(r)
		if float(e.top) >= -0.5 and float(e.bottom) >= -0.5:   # fits down: centred in the band, whichever way it was pushed
			assert_float(absf(float(e.top) - float(e.bottom))).override_failure_message("%s centred down %s" % [label, e]).is_less(1.0)
		else:   # taller than the band: the art's edge on the band's
			assert_float(minf(absf(float(e.top)), absf(float(e.bottom)))).override_failure_message("%s down %s" % [label, e]).is_less(0.5)

func test_back_is_always_handled_by_the_room_so_the_router_never_pops_twice() -> void:
	var r := _room()
	var left := [0]
	r.left.connect(func(): left[0] += 1)
	# Far from the door: Back starts the walk out and is handled.
	assert_bool(r.is_back_navigation_locked()).is_true()
	assert_int(left[0]).is_equal(0)
	# Back again while walking out leaves at once, still handled.
	assert_bool(r.is_back_navigation_locked()).is_true()
	assert_int(left[0]).is_equal(1)
	assert_bool(r.is_back_navigation_locked()).is_true()
	assert_int(left[0]).is_equal(1)

func test_back_at_the_door_leaves_at_once_and_is_still_handled() -> void:
	var r := _room()
	var left := [0]
	r.left.connect(func(): left[0] += 1)
	var door := r.anchor("exit").global_position
	r.actor.teleport(Vector3(door.x, r.floor_y, door.z))
	assert_bool(r.is_back_navigation_locked()).is_true()
	assert_int(left[0]).is_equal(1)
	r.p0_frame({}, 0.1)   # a frame after leaving does nothing

## Hard constraint (Arthur, SGODOT-226): with the cooking drawer up (480 of 800 at 360 wide), the whole stove stays
## above the drawer's top edge, and the pot sits between the HUD and the slot bar.
func test_pushed_in_stove_clears_the_cooking_drawer_on_a_360_by_800_screen() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(360, 800)
	sv.own_world_3d = true
	add_child(auto_free(sv))
	var r: P0Room = FARMHOUSE.new()
	r.use_runtime = false
	sv.add_child(r)
	r.focus("cam_stove", {band = r.band_below_hud(P0Kitchen.BAND_TOP_DRAWER), size = r.view_size() * P0Kitchen.FOCUS_SIZE})
	r._shot_k = 1.0
	r._update_camera()
	var drawer_top := 800.0 - P0KitchenDrawer.HEIGHT
	var lowest := -INF
	var hearth: Node3D = r.art.get_node("hearth")
	for mi in hearth.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		for i in 8: lowest = maxf(lowest, r.cam.unproject_position(box.get_endpoint(i)).y)
	assert_float(lowest).override_failure_message("stove bottom %.0f vs drawer top %.0f" % [lowest, drawer_top]).is_less(drawer_top)
	var pot := r.cam.unproject_position(r.anchor("drop_pot_1").global_position).y
	assert_float(pot).is_greater(P0Room.HUD_BOTTOM)
	assert_float(pot).is_less(drawer_top - 80.0)   # slot bar (50) and preview (26) sit above the drawer

# ---------------------------------------------------------------- environment and backdrop (SGODOT-248 / 249)
## The real farm scene and its suspend() / resume(), without the farm's _ready (runtime, session, world build).
func _farm_under() -> Node3D:
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_farm.gd\"\nfunc _ready() -> void: pass\nfunc _exit_tree() -> void: pass\n"
	stub.reload()
	var farm: Node3D = load("res://scenes/p0/p0_farm.tscn").instantiate()
	farm.set_script(stub)
	add_child(farm)
	auto_free(farm)
	return farm

func test_the_farm_hands_its_environment_to_the_farmhouse_above_it() -> void:
	# The viewport lights with the first WorldEnvironment in the tree: unless the farm lets go of its own, the
	# farmhouse shows the farm's cool ambient and green backdrop (hand test 249).
	var farm := _farm_under()
	var farm_env: Environment = farm.world_env.environment
	assert_object(farm_env).is_not_null()
	farm.suspend()
	assert_object(farm.world_env.environment).is_null()
	# Its canvas backdrop (layer −1, BG_CANVAS only) would otherwise cover the room's colour background: it leaves the
	# tree while the farm is suspended (hidden was not enough under a BG_CANVAS scene, SGODOT-256 ⑥).
	assert_object(farm.get_node_or_null("FarmBackground")).is_null()
	var r := _farmhouse()
	await get_tree().process_frame
	assert_object(r.get_viewport().find_world_3d().environment).is_same(r.environment)
	r.suspend()
	farm.resume()
	await get_tree().process_frame
	assert_object(farm.world_env.environment).is_same(farm_env)
	assert_object(farm.get_viewport().find_world_3d().environment).is_same(farm_env)
	assert_bool(farm.get_node("FarmBackground").visible).is_true()
	farm.suspend()
	farm.suspend()   # twice in a row still keeps the farm's own
	farm.resume()
	assert_object(farm.world_env.environment).is_same(farm_env)

func test_a_room_is_opaque_over_the_map() -> void:
	# The map's root is transparent so its tiles show; a room pushed above it must not let them through (248).
	var was := get_viewport().transparent_bg
	get_viewport().transparent_bg = true
	var r := _farmhouse()
	assert_bool(r.get_viewport().transparent_bg).is_false()
	r.suspend()
	get_viewport().transparent_bg = true   # the map underneath on its own resume
	r.resume()
	assert_bool(r.get_viewport().transparent_bg).is_false()
	get_viewport().transparent_bg = was

func test_the_spice_rack_takes_taps_beside_it_and_the_stove_keeps_to_its_body() -> void:
	# int6 C8: the rack is a small shelf on the wall beside the stove; picking by the nearest anchor gave taps just
	# beside the shelf to the stove. Now each of the three is tapped by its art: the rack's box is at least 44 × 44,
	# overlaps go to the smaller (small things first), and the stove never reaches past its body and pot.
	for lv in [2, 3]:
		var r := _farmhouse(lv)
		await get_tree().process_frame
		var rack := r.hit_rect("use_spice_rack")
		var stove := r.hit_rect("use_stove_1")
		assert_bool(rack.size.x >= P0Room.MIN_HIT and rack.size.y >= P0Room.MIN_HIT).override_failure_message(str(rack)).is_true()
		assert_str(r.pick(rack.get_center())).is_equal("use_spice_rack")
		# Every corner of the rack's box (including the edge towards the stove) opens the rack.
		for corner in [rack.position, rack.end - Vector2.ONE, Vector2(rack.end.x - 1, rack.position.y), Vector2(rack.position.x, rack.end.y - 1)]:
			assert_str(r.pick(corner)).override_failure_message("Lv%d %s" % [lv, corner]).is_equal("use_spice_rack")
		# The stove's body still opens the stove; a point on the wall left of its box is no longer the stove's.
		var pot := r.cam.unproject_position(r.anchor("use_stove_1").global_position)
		assert_bool(stove.has_point(pot)).is_true()
		assert_str(r.pick(pot)).is_equal("use_stove_1")
		assert_str(r.pick(Vector2(stove.position.x - 4, pot.y))).is_not_equal("use_stove_1")
	var lv3 := _farmhouse(3)
	await get_tree().process_frame
	var cab := lv3.hit_rect("use_warming_cabinet")
	var rack3 := lv3.hit_rect("use_spice_rack")
	var below := Vector2(cab.get_center().x, maxf(cab.get_center().y, rack3.end.y + 4))
	assert_bool(cab.has_point(below)).override_failure_message("%s not in the cabinet's box %s" % [below, cab]).is_true()
	assert_str(lv3.pick(below)).is_equal("use_warming_cabinet")   # under the shelf, the cabinet's own

## Godot's ACES as P0Room models it gives exactly the screen colours 248 and 227 measured, and reverses the art
## director's backdrop colours (SGODOT-227 美术决定 2b53b84d) to inputs that show them.
func test_the_aces_model_matches_the_measured_screen_colours_and_reverses() -> void:
	var lin := func(hex: String) -> Vector3:
		var c := Color(hex).srgb_to_linear()
		return Vector3(c.r, c.g, c.b)
	assert_str(P0Room.aces_screen(lin.call("e8e4c8")).to_html(false)).is_equal("f7f6ea")   # 248, Metal and Vulkan
	assert_str(P0Room.aces_screen(lin.call("d3e7d8")).to_html(false)).is_equal("eff7f1")   # 227, the tea house
	for hex in ["e6f5f1", "fffbee", "eff7f4", "fdfcf4", "d5eff3", "f7f6ea"]:
		assert_str(P0Room.aces_screen(P0Room.aces_input(Color(hex))).to_html(false)).override_failure_message(hex).is_equal(hex)

## The Basic Room has no review_lighting: the farmhouse keeps the P0Room benchmark light (249) and the plain plate.
func test_the_basic_room_keeps_the_benchmark_light() -> void:
	var r := _room()
	assert_str(r.environment.ambient_light_color.to_html(false)).is_equal("fff0dc")
	assert_float(r.environment.ambient_light_energy).is_equal_approx(0.70, 0.001)
	var sun := r.room.get_node("RoomSun") as DirectionalLight3D
	assert_str(sun.light_color.to_html(false)).is_equal("ffe6c2")
	assert_float(sun.light_energy).is_equal_approx(1.05, 0.001)
	assert_float(sun.shadow_bias).is_equal_approx(0.045, 0.001)
	assert_float(sun.shadow_normal_bias).is_equal_approx(0.4, 0.001)
	assert_float(sun.directional_shadow_max_distance).is_equal_approx(30.0, 0.001)
	assert_int(sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_float(sun.light_angular_distance).is_equal_approx(1.4, 0.001)
	assert_array(r.room.find_children("ReviewLamp*", "OmniLight3D", false, false)).is_empty()
	var plate := r.cam.get_node("Backdrop") as MeshInstance3D
	assert_str((plate.material_override as StandardMaterial3D).albedo_color.to_html(false)).is_equal("e8e4c8")
	assert_float(r.cam.near).is_equal_approx(0.1, 0.0001)
	assert_float(r.cam.far).is_equal_approx(70.0, 0.0001)
	assert_vector(r.sun_direction()).is_equal(Vector3(-6, 7, 1.5))   # layout.sun_direction

## A kit whose review lamp sits on the hearth keeps one hearth lamp: HearthGlow, the one the fire brightens (#29 / #32).
func test_a_review_lamp_on_the_hearth_is_not_added_twice() -> void:
	var layout := P0RoomAnchors.read_json(P0Room.BASIC_ROOM_LAYOUT)
	var fire: Array = layout.fire_position
	layout["review_lighting"] = {"ambient_color": "c0ada9", "ambient": 0.67, "sun_color": "ffe0ae", "sun": 1.55,
		"sun_position": [6, 9, -4], "sun_target": [0, 0, 0.8],
		"points": [{"position": fire, "color": "ffb85e", "energy": 1.0}, {"position": [1.0, 2.2, 0.5], "color": "ffe0a3", "energy": 1.2, "range": 1.45}]}
	layout["lighting"] = {"angular_distance": 4.5}
	var path := "user://test_review_room.layout.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(layout))
	f.close()
	var r := Sample.new()
	r.setup({})
	r.layout_path = path
	add_child(r)
	auto_free(r)
	assert_int(r.room.find_children("HearthGlow", "OmniLight3D", false, false).size()).is_equal(1)
	var lamps := r.room.find_children("ReviewLamp*", "OmniLight3D", false, false)
	assert_int(lamps.size()).is_equal(1)
	assert_vector((lamps[0] as OmniLight3D).position).is_equal(Vector3(1.0, 2.2, 0.5))
	assert_float((lamps[0] as OmniLight3D).omni_range).is_equal_approx(1.45, 0.001)
	var sun := r.room.get_node("RoomSun") as DirectionalLight3D
	assert_float(sun.light_angular_distance).is_equal_approx(4.5, 0.001)
	# No shadow values in the review: Godot's own shadow, as render_r1 signed the Coffee Shop and Fruit Shop.
	assert_int(sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_float(sun.directional_shadow_max_distance).is_equal_approx(40.0, 0.001)
	assert_float(sun.shadow_bias).is_equal_approx(0.1, 0.001)
	assert_float(sun.shadow_normal_bias).is_equal_approx(2.0, 0.001)
	# The signed sun wins over the Basic Room's layout.sun_direction, and the camera clips as render_r1's did.
	assert_vector(r.sun_direction()).is_equal(Vector3(6, 9, -4.8))
	assert_float(r.cam.near).is_equal_approx(0.05, 0.0001)
	assert_float(r.cam.far).is_equal_approx(150.0, 0.0001)

## A review with shadow values was signed through review_room.gd: one orthogonal map with those values (Farm Tools
## Store, Post Office); the ones it leaves out take that tool's defaults.
func test_review_shadow_values_cast_the_review_tools_shadow() -> void:
	var sun := DirectionalLight3D.new()
	P0Room._set_sun_shadow(sun, {"sun": 1.2, "shadow_bias": 0.03})
	assert_int(sun.directional_shadow_mode).is_equal(DirectionalLight3D.SHADOW_ORTHOGONAL)
	assert_float(sun.shadow_bias).is_equal_approx(0.03, 0.001)
	assert_float(sun.shadow_normal_bias).is_equal_approx(0.18, 0.001)
	assert_float(sun.directional_shadow_max_distance).is_equal_approx(35.0, 0.001)
	sun.free()
	# … and its camera clipped at Godot's defaults: at the old 70 m the Post Office's west wall shaded the floor by
	# the door, which the signed render does not show.
	assert_vector(P0Room.review_clip({"shadow_bias": 0.065})).is_equal(Vector2(0.05, 4000.0))
	assert_vector(P0Room.review_clip({"sun": 1.55})).is_equal(Vector2(0.05, 150.0))
	assert_vector(P0Room.review_clip({})).is_equal(Vector2(0.1, 70.0))

## A door without its own badge_exit point keeps its prompt and pick point over the threshold (the Basic Room's door).
func test_a_door_without_a_badge_point_is_picked_over_the_threshold() -> void:
	var r := _room()
	assert_object(r.anchor("badge_exit")).is_null()
	assert_vector(r.pick_point("exit")).is_equal(r.anchor("exit").global_position + Vector3(0, 1.0, 0))
