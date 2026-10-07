extends GdUnitTestSuite
## Outpost rooms (SGODOT-227) on the Basic Room placeholder: each of the four outposts opens from the shared
## outpost table with its anchors, keeper and residents; counters and residents are tappable, decor is not;
## seats walk to the nearest free one, sit, skip seats other players hold, and the joystick stands up.

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

func test_tapping_the_tea_table_sits_on_the_nearest_free_seat_and_the_joystick_stands_up() -> void:
	var r := _room("sh_tea_1")
	assert_dict(r._marker("use_tea_table_1", {})).is_equal({text = "Sit"})
	_tap(r, "use_tea_table_1")
	_walk_until_idle(r)
	assert_str(r.seat).is_equal("seat_table1_1")   # the chair on the door side is nearer
	assert_str(r.actor.state).is_equal("locked")
	assert_float(P0Room._flat_distance(r.actor.position, r.anchor("seat_table1_1").global_position)).is_less(0.05)
	assert_dict(r._marker("use_tea_table_1", {})).is_empty()   # no Sit card while seated
	r.p0_joystick(Vector2(0, 1))
	assert_str(r.seat).is_equal("")
	assert_str(r.actor.state).is_not_equal("locked")

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
	assert_int(left[0]).override_failure_message("walks to the door first, not out at once").is_equal(0)
	_walk_until_idle(r, 8.0)
	assert_int(left[0]).is_equal(1)
