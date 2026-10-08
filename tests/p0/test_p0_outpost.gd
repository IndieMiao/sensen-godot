extends GdUnitTestSuite
## Outpost rooms (SGODOT-227) on the Basic Room placeholder: each of the four outposts opens from the shared
## outpost table with its anchors, keeper and residents; counters and residents are tappable, decor is not;
## seats walk to the nearest free one, sit, skip seats other players hold, and the joystick stands up.

const OutpostScript := preload("res://scenes/p0/p0_outpost.gd")

class Sample extends "res://scenes/p0/p0_outpost.gd":
	var used: Array = []
	func setup(a: Dictionary) -> void:
		super.setup(a)
		use_runtime = false
	func _on_facility(n: String) -> void:
		used.append(n)
		super._on_facility(n)

func _room(id: String) -> Sample:
	var r := Sample.new()
	r.setup({"outpost_id": id})
	add_child(r)
	auto_free(r)
	return r

func _walk_until_idle(r: P0Room, seconds := 6.0) -> void:
	var t := 0.0
	while t < seconds and not r.p0_until("idle"):
		r.p0_frame({}, 1.0 / 30.0)
		t += 1.0 / 30.0
	r.p0_frame({}, 1.0 / 30.0)

func _tap(r: P0Room, n: String) -> void:
	var lift := Vector3(0, 1.0, 0) if n.begins_with("npc_") else Vector3.ZERO
	r.p0_tap(r.cam.unproject_position(r.anchor(n).global_position + lift))

func test_the_outpost_table_and_anchor_files_agree() -> void:
	assert_int(P0Outposts.all().size()).is_equal(4)
	for o in P0Outposts.all():
		var anchors: Array = P0RoomAnchors.read_json(str(o.anchors)).get("anchors", [])
		var names := anchors.map(func(a): return str(a.name))
		assert_array(names).override_failure_message(str(o.id) + " spawn / exit").contains(["spawn", "exit"])
		assert_array(names.filter(func(n): return n.begins_with("seat_"))).override_failure_message(str(o.id) + " seats").is_equal(o.seats)
		assert_int(int(o.capacity)).is_equal(30 if str(o.role) == "market" else 12)
		# The keeper's finger card has its own badge_ point, clear above the door's card (安其拉's review of #14).
		var at := {}
		for a in anchors: at[str(a.name)] = Vector3(a.position[0], a.position[1], a.position[2])
		assert_bool(at.has("badge_keeper")).override_failure_message(str(o.id) + " badge_keeper").is_true()
		assert_float(at.badge_keeper.y - (at.exit.y + 1.1)).override_failure_message(str(o.id) + " cards apart").is_greater(0.9)
	assert_str(str(P0Outposts.by_role("tea").name)).is_equal("Lotus Tea House")

func test_each_outpost_opens_with_its_keeper_and_residents() -> void:
	var expected := {"sh_tackle_1": ["npc_keeper", "npc_kai"], "sh_tea_1": ["npc_keeper"], "sh_post_1": ["npc_keeper", "npc_pip"], "sh_market_1": ["npc_keeper"]}
	for id in expected:
		var r := _room(id)
		assert_str(r.place_name).is_equal(str(P0Outposts.find(id).name))
		assert_array(r.npcs.keys()).override_failure_message(id).contains_exactly_in_any_order(expected[id])
		assert_float(P0Room._flat_distance(r.actor.position, r.anchor("spawn").global_position)).is_less(0.2)
		assert_str(r.exit_text).is_equal("Exit · Back to map" if id == "sh_market_1" else "Door · Back to map")
	assert_str(str(_room("sh_tackle_1").npcs.npc_keeper.name)).is_equal("Finn")

func test_decor_is_not_tappable_and_counters_are() -> void:
	var post := _room("sh_post_1")
	var taps := post._tappable()
	for n in ["use_stamp_desk", "use_fee_board", "use_coffee_pot"]: assert_bool(taps.has(n)).override_failure_message(n).is_false()
	for n in ["use_counter", "npc_keeper", "npc_pip", "exit"]: assert_bool(taps.has(n)).override_failure_message(n).is_true()
	assert_bool(_room("sh_tackle_1")._tappable().has("use_fish_board")).is_false()

func test_tapping_the_counter_walks_there_and_reaches_the_keeper_entry() -> void:
	var r := _room("sh_tackle_1")
	_tap(r, "use_counter")
	_walk_until_idle(r)
	assert_array(r.used).is_equal(["use_counter"])
	assert_float(P0Room._flat_distance(r.actor.position, r.anchor("stand_counter").global_position)).is_less(P0Room.REACH_M)

func test_tapping_the_keeper_stops_in_front_of_them_not_inside() -> void:
	for id in ["sh_tackle_1", "sh_tea_1", "sh_post_1", "sh_market_1"]:
		var r := _room(id)
		_tap(r, "npc_keeper")
		_walk_until_idle(r)
		assert_array(r.used).override_failure_message(id).is_equal(["npc_keeper"])
		assert_float(P0Room._flat_distance(r.actor.position, r.anchor("npc_keeper").global_position)).override_failure_message(id).is_greater(0.5)

func test_tapping_the_tea_table_sits_on_the_nearest_free_seat_and_the_joystick_stands_up() -> void:
	var r := _room("sh_tea_1")
	assert_dict(r._marker("use_tea_table_1", {})).is_equal({text = "Sit"})
	_tap(r, "use_tea_table_1")
	_walk_until_idle(r)
	assert_str(r.seat).is_equal("seat_table1_1")   # the chair on the door side is nearer
	assert_str(r.actor.state).is_equal("locked")
	assert_dict(r._marker("use_tea_table_1", {})).is_empty()   # no Sit card while seated
	for i in 12: r.p0_frame({}, 1.0 / 30.0)   # the root glides onto the seat within 0.3 s
	assert_float(P0Room._flat_distance(r.actor.position, r.anchor("seat_table1_1").global_position)).is_less(0.02)
	assert_float(r.actor.position.y).is_equal_approx(r.anchor("seat_table1_1").global_position.y - OutpostScript.SIT_ROOT_BELOW_SEAT, 0.02)
	var ap := r.actor.rig.get_node("AnimationPlayer") as AnimationPlayer
	assert_str(ap.current_animation).is_equal("sit_down")
	assert_array(ap.get_queue()).contains(["sit_idle"])
	r.p0_joystick(Vector2(0, 1))
	assert_str(r.seat).is_equal("")
	assert_str(ap.current_animation).is_equal("sit_up")
	assert_str(r.actor.state).override_failure_message("held while sit_up plays").is_equal("locked")
	var steps: Array[float] = []
	var last := r.actor.position
	for i in 30:
		var standing := r.actor.state == "locked"
		r.p0_frame({}, 1.0 / 30.0)
		if standing: steps.append(r.actor.position.distance_to(last))   # the joystick walks on after release
		last = r.actor.position
	assert_str(r.actor.state).is_not_equal("locked")
	assert_float(r.actor.position.y).is_equal_approx(r.floor_y, 0.02)
	assert_float(steps.max()).override_failure_message("no jump while standing up: %s" % [steps]).is_less(0.12)

func test_other_players_on_seats_are_lifted_onto_them() -> void:
	var r := _room("sh_tea_1")
	var online := P0Online.new()
	online.transport = func(_m): pass
	r.attach_online(online)
	online._message(JSON.stringify({"t": "joined", "room": 1, "self": 1, "epoch": 2}))
	online._message(JSON.stringify({"t": "roster", "members": [{"id": 1, "player": "me-0000001", "seat": ""}, {"id": 2, "player": "them-000002", "seat": "seat_bench_1"}, {"id": 3, "player": "walker-0003", "seat": ""}]}))
	var bench_y: float = r.seat_root_y("seat_bench_1") - r.room.position.y
	assert_float(r._crowd_height(2)).is_equal_approx(bench_y, 0.001)
	assert_float(r._crowd_height(3)).is_equal_approx(r.floor_y - r.room.position.y, 0.001)

func test_seats_other_players_hold_are_skipped() -> void:
	var r := _room("sh_tea_1")
	var online := P0Online.new()
	var sent: Array = []
	online.transport = func(m): sent.append(m)
	r.attach_online(online)
	online._message(JSON.stringify({"t": "joined", "room": 1, "self": 1, "epoch": 2}))
	online._message(JSON.stringify({"t": "roster", "members": [{"id": 1, "player": "me-0000001", "seat": ""}, {"id": 2, "player": "them-000002", "seat": "seat_table1_1"}]}))
	assert_array(r._free_seats("seat_table1_").map(func(m): return str(m.name))).is_equal(["seat_table1_2"])
	_tap(r, "use_tea_table_1")
	_walk_until_idle(r)
	assert_str(r.seat).is_equal("")   # waiting for the server …
	var claim: Dictionary = sent.filter(func(m): return m.t == "act")[-1]
	assert_str(claim.node).is_equal("seat_table1_2")
	assert_int((claim.at as Array).size()).is_equal(2)
	online._message(JSON.stringify({"t": "result", "seq": claim.seq, "ok": true, "code": ""}))
	assert_str(r.seat).is_equal("seat_table1_2")   # … seated once it agrees

func test_back_while_seated_stands_up_and_walks_out() -> void:
	var r := _room("sh_tea_1")
	var left := [0]
	r.left.connect(func(): left[0] += 1)
	_tap(r, "use_tea_table_1")
	_walk_until_idle(r)
	assert_str(r.seat).is_not_empty()
	assert_bool(r.is_back_navigation_locked()).override_failure_message("Back is handled by the room").is_true()
	assert_str(r.seat).is_equal("")
	assert_bool(r.is_back_navigation_locked()).override_failure_message("a second Back while standing up is absorbed").is_true()
	assert_int(left[0]).override_failure_message("stands, then walks to the door, not out at once").is_equal(0)
	for i in 30: r.p0_frame({}, 1.0 / 30.0)   # sit_up
	_walk_until_idle(r, 8.0)
	assert_int(left[0]).is_equal(1)

func test_the_keeper_greeting_gets_names_and_places_from_the_outpost_data() -> void:
	assert_dict(_room("sh_market_1").keeper_ctx()).is_equal({"keeper": "Mei", "place": "Xuhui Market Square"})
	assert_dict(_room("sh_tackle_1").keeper_ctx()).is_equal({"keeper": "Finn", "place": "Xuhui Tackle Shop",
		"nearest": {"name": "Reed Pond", "site": "pond"}})
