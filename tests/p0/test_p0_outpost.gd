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
	# The board and the shelf open the counter without the greeting: they carry the keeper ctx themselves.
	assert_dict(_room("sh_market_1").counter_opts("board")).is_equal({"section": "board",
		"ctx": {"keeper": "Mei", "place": "Xuhui Market Square"}})
	for o in P0Outposts.all():   # nearest.site keys view.keepers.tackle.next_fish (fishing.sites)
		if o.has("nearest"): assert_array(["pond", "river"]).contains([str(o.nearest.site)])

## SGODOT-229: the NPC-only parts reach the NPCs. OnlineAppearance.config drops them unless asked (they are kept out of
## player outfits and the online appearances), so the spawn has to pass allow_npc.
func test_npcs_wear_their_npc_only_parts() -> void:
	var kai: Node = _room("sh_tackle_1").npcs.npc_kai.root
	var rig: AvatarRig = kai.find_children("*", "AvatarRig", true, false)[0]
	var worn: Dictionary = rig.get("_desired")
	assert_str(str(worn.get(&"hairHat", ""))).is_equal("hairhat71_npc_kai")
	assert_str(str(worn.get(&"mask", ""))).is_equal("mask16_npc_kai")
	assert_str(str(worn.get(&"cloth", ""))).is_equal("cloth11_npc_mei")
	assert_bool(Avatar.catalog.is_npc_only("hairhat71_npc_kai")).is_true()

## Every outfit part exists in its slot; no two NPCs share both hairHat and cloth (the outfit rules in the file's note).
func test_npc_outfits_name_real_parts_and_stay_distinct() -> void:
	var npcs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/outpost_npcs.json")).npcs
	var pairs := {}
	for id in npcs:
		var slots: Dictionary = npcs[id].slots
		for slot in slots:
			var part = Avatar.catalog.part(str(slots[slot]))
			assert_object(part).override_failure_message("%s: %s" % [id, slots[slot]]).is_not_null()
			if part: assert_str(String(part.slot)).override_failure_message("%s: %s" % [id, slots[slot]]).is_equal(str(slot))
		var pair := "%s|%s" % [slots.get("hairHat", ""), slots.get("cloth", "")]
		assert_bool(pairs.has(pair)).override_failure_message("%s shares %s with %s" % [id, pair, pairs.get(pair, "")]).is_false()
		pairs[pair] = id

## SGODOT-250 (spec 370794d2 item 5): one finger card at a time in a room. Hand test 246 pictures 06 / 07 showed the
## keeper's, the seat's and the door's cards together; now only the nearest within reach shows, and it keeps the
## card until another is clearly nearer.
func test_only_the_nearest_card_shows_in_a_room() -> void:
	var r := _room("sh_tea_1")
	var marks := {}
	for n in r._tappable():
		var m: Dictionary = r._marker(n, {})
		if not m.is_empty(): marks[n] = m
	var keeper := r.anchor("npc_keeper").global_position
	var door := r.anchor("exit").global_position
	r.actor.position = Vector3(keeper.x + 0.3, r.actor.position.y, keeper.z + 0.6)   # by Ama, the tea table and the door in reach
	var in_reach := marks.keys().filter(func(n): return Vector2(r.actor.position.x - r.anchor(n).global_position.x,
		r.actor.position.z - r.anchor(n).global_position.z).length() < P0Room.CARD_NEAR_M)
	assert_int(in_reach.size()).override_failure_message(str(in_reach)).is_greater_equal(3)   # the 246 / 07 situation
	assert_str(r.card_pick(marks)).is_equal("npc_keeper")
	# Ama's card stays while the door is only a little nearer …
	var mid := (keeper + door) * 0.5
	var along := (door - keeper).normalized()
	r.actor.position = Vector3(mid.x, r.actor.position.y, mid.z) + Vector3(along.x, 0, along.z) * 0.05
	assert_str(r.card_pick(marks)).is_equal("npc_keeper")
	# … and goes to the door once it is clearly nearer.
	r.actor.position = Vector3(door.x, r.actor.position.y, door.z) - Vector3(along.x, 0, along.z) * 0.3
	assert_str(r.card_pick(marks)).is_equal("exit")
	# Out of every reach: no card.
	r.actor.position = Vector3(20, r.actor.position.y, 20)
	assert_str(r.card_pick(marks)).is_equal("")
