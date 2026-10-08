extends GdUnitTestSuite
## Outpost rooms (SGODOT-227) on their room kits (Farm Tools Store, Coffee Shop, Post Office, Fruit Shop; placeholders
## until SGODOT-218): each of the four outposts opens from the shared outpost table with its anchors, keeper and residents; counters and residents are tappable, decor is not;
## seats walk to the nearest free one, sit, skip seats other players hold, and the joystick stands up.

const OutpostScript := preload("res://scenes/p0/p0_outpost.gd")

class Sample extends "res://scenes/p0/p0_outpost.gd":
	var used: Array = []
	var arrived := {}   # facility → where the player stood when it fired
	func setup(a: Dictionary) -> void:
		super.setup(a)
		use_runtime = false
	func _on_facility(n: String) -> void:
		used.append(n)
		arrived[n] = actor.position
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

## The bag's dish card asks for the resident within a finger card's reach (SGODOT-225 Gift to <Name>): Old Kai at
## the tackle shop once the player stands by him; never the keeper, and nobody from across the room.
func test_near_resident_is_a_resident_within_card_reach_never_the_keeper() -> void:
	var r := _room("sh_tackle_1")
	r.actor.position = r.anchor("npc_keeper").global_position
	assert_str(r.p0_near_resident()).is_not_equal(str(r.npcs.npc_keeper.id))   # Finn keeps the shop: never a gift target (Kai may be in reach)
	r.actor.position = r.anchor("npc_keeper").global_position + Vector3(1.5, 0, 0)   # only Finn within a card's reach
	assert_float(P0Room._flat_distance(r.actor.position, r.anchor("npc_kai").global_position)).is_greater(P0Room.CARD_NEAR_M)
	assert_str(r.p0_near_resident()).is_equal("")
	var kai := r.anchor("npc_kai").global_position
	r.actor.position = kai + Vector3(1.0, 0, 0)
	assert_str(r.p0_near_resident()).is_equal(str(r.npcs.npc_kai.id))
	r.actor.position = kai + Vector3(P0Room.CARD_NEAR_M + 0.5, 0, 0)
	assert_str(r.p0_near_resident()).is_equal("")
	assert_str(_room("sh_tea_1").p0_near_resident()).is_equal("")   # no resident at the tea house

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
	assert_str(str(r._marker("use_tea_table_1", {}).get("kind", ""))).is_equal("seat")   # the seat icon (LOCK-30 v2)
	_tap(r, "use_tea_table_1")
	_walk_until_idle(r)
	assert_str(r.seat).is_equal("seat_table1_1")   # the chair on the door side is nearer
	assert_str(r.actor.state).is_equal("locked")
	assert_dict(r._marker("use_tea_table_1", {})).is_empty()   # no seat icon while seated
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
	online._message(JSON.stringify({"t": "roster", "members": [{"id": 1, "player": "me-0000001", "seat": ""}, {"id": 2, "player": "them-000002", "seat": "seat_table2_1"}, {"id": 3, "player": "walker-0003", "seat": ""}]}))
	var chair_y: float = r.seat_root_y("seat_table2_1") - r.room.position.y
	assert_float(chair_y).is_greater(r.floor_y - r.room.position.y + 0.2)   # a real seat, not the floor fallback
	assert_float(r._crowd_height(2)).is_equal_approx(chair_y, 0.001)
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
## card until another is clearly nearer. On the Coffee Shop the door is at the front, so three prompts meet between
## the two tea tables and the door rather than at the counter.
func test_only_the_nearest_card_shows_in_a_room() -> void:
	var r := _room("sh_tea_1")
	var marks := {}
	for n in r._tappable():
		var m: Dictionary = r._marker(n, {})
		if not m.is_empty(): marks[n] = m
	var flat := func(n: String) -> float: return P0Room._flat_distance(r.actor.position, r.anchor(n).global_position)
	var spot := (r.anchor("use_tea_table_1").global_position + r.anchor("use_tea_table_2").global_position + r.anchor("exit").global_position) / 3.0
	r.actor.position = Vector3(spot.x, r.actor.position.y, spot.z)
	var in_reach := marks.keys().filter(func(n): return flat.call(n) < P0Room.CARD_NEAR_M)
	assert_int(in_reach.size()).override_failure_message(str(in_reach)).is_greater_equal(3)   # the 246 / 07 situation
	in_reach.sort_custom(func(a, b): return flat.call(a) < flat.call(b))
	assert_str(r.card_pick(marks)).is_equal(str(in_reach[0]))
	var keeper := r.anchor("npc_keeper").global_position
	r.actor.position = Vector3(keeper.x + 0.3, r.actor.position.y, keeper.z + 0.6)   # by Ama
	assert_str(r.card_pick(marks)).is_equal("npc_keeper")
	# Ama's card stays while the nearest other prompt is only a little nearer …
	var others := marks.keys().filter(func(n): return n != "npc_keeper")
	others.sort_custom(func(a, b): return P0Room._flat_distance(keeper, r.anchor(a).global_position) < P0Room._flat_distance(keeper, r.anchor(b).global_position))
	var other := str(others[0])
	var there := r.anchor(other).global_position
	var mid := (keeper + there) * 0.5
	var along := (there - keeper).normalized()
	r.actor.position = Vector3(mid.x, r.actor.position.y, mid.z) + Vector3(along.x, 0, along.z) * 0.05
	assert_str(r.card_pick(marks)).is_equal("npc_keeper")
	# … and goes to it once it is clearly nearer.
	r.actor.position = Vector3(there.x, r.actor.position.y, there.z) - Vector3(along.x, 0, along.z) * 0.3
	assert_str(r.card_pick(marks)).is_equal(other)
	# Out of every reach: no card.
	r.actor.position = Vector3(20, r.actor.position.y, 20)
	assert_str(r.card_pick(marks)).is_equal("")

## SGODOT-250 (LOCK-07 / 16 / 30 v2, q(62)): no "Tap to …" anywhere in a room. NPCs carry their name only (as the UI's
## NpcNameTag, no Label3D left on the rig), seats an i-seat icon, the door i-door + Map, the market counters their names
## with the board's request mark riding in its button.
func test_room_prompts_are_names_and_icons_only() -> void:
	var tea := _room("sh_tea_1")
	var ama: Dictionary = tea._marker("npc_keeper", {})
	assert_str(str(ama.get("kind", ""))).is_equal("npc")
	assert_str(str(ama.get("name", ""))).is_equal("Ama")
	assert_bool(ama.has("text")).is_false()
	assert_float((ama.head as Vector3).y).is_greater(tea.anchor("npc_keeper").global_position.y + 1.5)   # over the head
	assert_array(tea.npcs.npc_keeper.root.find_children("*", "Label3D", true, false)).is_empty()
	for table in ["use_tea_table_1", "use_tea_table_2"]:
		assert_dict(tea._marker(table, {})).override_failure_message(table).contains_keys(["icon"])
		assert_str(str(tea._marker(table, {}).get("kind", ""))).override_failure_message(table).is_equal("seat")
	assert_bool(tea._tappable().has("use_bench")).is_false()   # the Coffee Shop has no bench (不知火舞 on 227)
	var door: Dictionary = tea._marker("exit", {})
	assert_str(str(door.get("kind", ""))).is_equal("facility")
	assert_str(str(door.get("name", ""))).is_equal("Map")
	var market := _room("sh_market_1")
	var board: Dictionary = market._marker("use_market_board", {"keepers": {"market": {"board_open": 2}}})
	assert_str(str(board.name)).is_equal("Market Board")
	assert_str(str(board.badge)).is_equal("request")
	assert_str(str(market._marker("use_market_board", {"keepers": {"market": {"board_open": 0}}}).badge)).is_equal("")
	assert_str(str(market._marker("use_specialty_shelf", {}).name)).is_equal("City Specialty")
	for r in [tea, market, _room("sh_tackle_1"), _room("sh_post_1")]:
		for n in r._tappable():
			var m: Dictionary = r._marker(n, {})
			assert_str(str(m.get("text", ""))).override_failure_message("%s %s" % [str(r.outpost.get("id", "")), n]).not_contains("Tap to")
			assert_str(str(m.get("name", ""))).override_failure_message("%s %s" % [str(r.outpost.get("id", "")), n]).not_contains("Tap to")

## 不知火舞 on #57: the NPC whose greeting card or dialogue bar this room opened is "talking" while that modal is up,
## so its name stays lit there; no other NPC, and nobody once the modal closes. Through the real runtime and UI.
func test_the_npc_the_room_opened_a_talk_for_is_talking_until_it_closes() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.transport = func(_method: int, _path: String, _body: Dictionary, _cmd: Dictionary): pass   # nothing goes out
	var r := _room("sh_tackle_1")
	r.rt = rt
	r._on_facility("npc_keeper")   # Finn greets first (the tackle shop's greeting card)
	assert_bool(rt.ui.has_modal()).is_true()
	assert_bool(bool(r._marker("npc_keeper", {}).talking)).is_true()
	assert_bool(bool(r._marker("npc_kai", {}).talking)).is_false()
	rt.ui.close_modal()
	r._room_frame({}, 1.0 / 30.0)
	assert_bool(bool(r._marker("npc_keeper", {}).talking)).is_false()

## Scene integration (SGODOT-227, 不知火舞's walkthrough on 227): the tea house opens on the Coffee Shop kit with the
## background of its signed render and every anchor of its file, and the opening view holds the whole art, centred, with at least
## 16 px clear on both sides (the kit's own camera left about 14 px on the right).
func test_the_tea_house_opens_on_the_coffee_shop_kit() -> void:
	var r := _room("sh_tea_1")
	assert_str(r.layout_path).is_equal("res://assets/rooms/coffee_shop/layout.json")
	assert_str((r.art.get_script() as Script).resource_path).is_equal("res://scenes/coffee_shop/coffee_shop_art.gd")
	var clear := r.environment.background_color.srgb_to_linear()   # the plate's top colour, as it shows on screen
	assert_str(P0Room.aces_screen(Vector3(clear.r, clear.g, clear.b)).to_html(false)).is_equal("e6f5f1")
	for a in P0RoomAnchors.read_json(str(P0Outposts.find("sh_tea_1").anchors)).anchors:
		assert_object(r.anchor(str(a.name))).override_failure_message(str(a.name)).is_not_null()
	assert_bool(r._fits).override_failure_message("the opening view holds still").is_true()
	var right := (-r._cam_dir).cross(Vector3.UP).normalized()
	var span := r.art_span(right)
	var centre := r.cam.global_position.dot(right)   # the view axis is square to `right`
	var px := r._view().x / r.cam.size
	var left_px := (span.x - (centre - r.cam.size * 0.5)) * px
	var right_px := (centre + r.cam.size * 0.5 - span.y) * px
	assert_float(left_px).override_failure_message("left %.1f px" % left_px).is_greater_equal(16.0)
	assert_float(right_px).override_failure_message("right %.1f px" % right_px).is_greater_equal(16.0)
	assert_float(absf(left_px - right_px)).override_failure_message("%.1f / %.1f px" % [left_px, right_px]).is_less(2.0)

## Every chair of both tea tables can be walked to from the door: the player arrives on the floor beside it (not
## sat there by a failed path) and sits on it.
func test_every_tea_seat_is_walked_to_from_the_door() -> void:
	for s in ["seat_table1_1", "seat_table1_2", "seat_table2_1", "seat_table2_2"]:
		var r := _room("sh_tea_1")
		var beside := P0RoomNav.nearest_walkable(r.bp, r.anchor(s).global_position)
		r.walk_to(s)
		_walk_until_idle(r, 10.0)
		assert_str(r.seat).override_failure_message(s).is_equal(s)
		assert_float(P0Room._flat_distance(r.arrived[s], beside)).override_failure_message(s + " walked there").is_less(P0Room.REACH_M + 0.05)

func test_the_second_tea_table_seats_on_its_door_side_chair() -> void:
	var r := _room("sh_tea_1")
	assert_str(str(r._marker("use_tea_table_2", {}).get("kind", ""))).is_equal("seat")
	_tap(r, "use_tea_table_2")
	_walk_until_idle(r, 10.0)
	assert_str(r.seat).is_equal("seat_table2_1")

## The tea house door is at the front steps: walking out there from inside leaves for the map.
func test_the_tea_house_door_is_at_the_front_and_leaves() -> void:
	var r := _room("sh_tea_1")
	var left := [0]
	r.left.connect(func(): left[0] += 1)
	assert_float(r.anchor("exit").position.z).is_greater(r.anchor("use_tea_table_2").position.z)   # in front of the tables
	r.actor.teleport(r.anchor("stand_counter").global_position)
	r.p0_frame({}, 0.1)
	r.walk_to("exit")
	_walk_until_idle(r, 10.0)
	assert_int(left[0]).is_equal(1)

## A front door's prompt (badge_exit) sits on the steps, below the player who comes in, and is picked there: 1.1 m
## over the threshold it covered the player at the Coffee Shop's spawn (sample shots on 227). Tapping the player is
## not tapping the door.
func test_the_front_door_prompt_sits_on_the_steps_clear_of_the_player() -> void:
	var r := _room("sh_tea_1")
	var feet := r.cam.unproject_position(r.actor.position)
	var head := r.cam.unproject_position(r.actor.position + Vector3(0, 1.75, 0))
	var prompt := r.cam.unproject_position(r.pick_point("exit"))
	assert_float(prompt.y - feet.y).override_failure_message("prompt %s, feet %s" % [prompt, feet]).is_greater(10.0)
	assert_str(r.pick(prompt)).is_equal("exit")
	assert_str(r.pick((feet + head) * 0.5)).is_not_equal("exit")
	assert_object(r.anchor("badge_exit")).is_not_null()
	if r.anchor("badge_exit"): assert_vector(r.pick_point("exit")).is_equal(r.anchor("badge_exit").global_position)

## A tapped world prompt goes to its own anchor by id, as in every other room (PR #21's rule): the door's prompt on
## the steps leads out even where the tap point is nearer another facility.
func test_a_tapped_prompt_goes_to_its_own_anchor() -> void:
	var rt: P0Runtime = auto_free(P0Runtime.new())
	add_child(rt)
	await get_tree().process_frame
	rt.session.transport = func(_method: int, _path: String, _body: Dictionary, _cmd: Dictionary): pass   # nothing goes out
	var r := _room("sh_tea_1")
	r.rt = rt
	var table := r.cam.unproject_position(r.anchor("use_tea_table_2").global_position)
	assert_str(r.pick(table)).is_equal("use_tea_table_2")
	rt.ui.tapped_card = "room:exit"
	assert_str(r.tap_target(table)).is_equal("exit")
	r.p0_tap(table)
	assert_str(str(r._walk.get("name", ""))).is_equal("exit")
	rt.ui.tapped_card = ""
	assert_str(r.tap_target(table)).is_equal("use_tea_table_2")

## The tea house lights as the Coffee Shop was signed off (SGODOT-227 美术决定 2b53b84d): review ambient, sun and its
## three lamps in scene metres, the kit's angular distance, and the screen-calibrated two-colour backdrop.
func test_the_tea_house_lights_as_the_coffee_shop_was_signed() -> void:
	var r := _room("sh_tea_1")
	var review: Dictionary = r.layout.review_lighting
	assert_str(r.environment.ambient_light_color.to_html(false)).is_equal(str(review.ambient_color).to_lower())
	assert_float(r.environment.ambient_light_energy).is_equal_approx(float(review.ambient), 0.001)
	var sun := r.room.get_node("RoomSun") as DirectionalLight3D
	assert_str(sun.light_color.to_html(false)).is_equal(str(review.sun_color).to_lower())
	assert_float(sun.light_energy).is_equal_approx(float(review.sun), 0.001)
	assert_float(sun.light_angular_distance).is_equal_approx(4.5, 0.001)
	var lamps := r.room.find_children("ReviewLamp*", "OmniLight3D", false, false)
	assert_int(lamps.size()).is_equal((review.points as Array).size())
	for i in lamps.size():
		var p: Array = review.points[i].position
		assert_vector((lamps[i] as OmniLight3D).global_position).is_equal_approx(r.room.position + Vector3(p[0], p[1], p[2]), Vector3.ONE * 0.001)
	assert_array(r.room.find_children("HearthGlow", "OmniLight3D", false, false)).is_empty()   # no hearth here
	var mat := (r.cam.get_node("Backdrop") as MeshInstance3D).material_override as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_str(P0Room.aces_screen(mat.get_shader_parameter("top_input")).to_html(false)).is_equal("e6f5f1")
	assert_str(P0Room.aces_screen(mat.get_shader_parameter("bottom_input")).to_html(false)).is_equal("fffbee")
	assert_vector(mat.get_shader_parameter("blend")).is_equal(Vector2(0.5, 0.85))

## Scene integration (SGODOT-227): every outpost opens on its own kit with every anchor of its file, the background
## sampled from its signed render, and an opening view that holds the whole art, centred, with at least 16 px clear on
## both sides; the door's prompt is clear of the player who comes in.
func test_every_outpost_opens_on_its_kit() -> void:
	var kits := {"sh_tackle_1": "farm_tools_store", "sh_tea_1": "coffee_shop", "sh_post_1": "post_office", "sh_market_1": "fruit_shop"}
	for id in kits:
		var o := P0Outposts.find(id)
		var r := _room(id)
		assert_str(str(o.art)).is_equal(kits[id])
		assert_str(r.layout_path).override_failure_message(id).is_equal("res://assets/rooms/%s/layout.json" % kits[id])
		for a in P0RoomAnchors.read_json(str(o.anchors)).anchors:
			assert_object(r.anchor(str(a.name))).override_failure_message("%s %s" % [id, a.name]).is_not_null()
		var clear := r.environment.background_color.srgb_to_linear()
		assert_str(P0Room.aces_screen(Vector3(clear.r, clear.g, clear.b)).to_html(false)).override_failure_message(id).is_equal(str(o.backdrop.top).to_lower())
		assert_bool(r._fits).override_failure_message(id + " holds still").is_true()
		var right := (-r._cam_dir).cross(Vector3.UP).normalized()
		var span := r.art_span(right)
		var centre := r.cam.global_position.dot(right)
		var px := r._view().x / r.cam.size
		var left_px := (span.x - (centre - r.cam.size * 0.5)) * px
		var right_px := (centre + r.cam.size * 0.5 - span.y) * px
		assert_float(minf(left_px, right_px)).override_failure_message("%s %.1f / %.1f px" % [id, left_px, right_px]).is_greater_equal(16.0)
		assert_float(absf(left_px - right_px)).override_failure_message("%s %.1f / %.1f px" % [id, left_px, right_px]).is_less(2.0)
		# The door's prompt keeps off the player at spawn: below the feet at a front door, above the head at a back one.
		var feet := r.cam.unproject_position(r.actor.position)
		var head := r.cam.unproject_position(r.actor.position + Vector3(0, 1.75, 0))
		var prompt := r.cam.unproject_position(r.pick_point("exit"))
		var on_body := absf(prompt.x - feet.x) < 25.0 and prompt.y > head.y - 12.0 and prompt.y < feet.y + 10.0
		assert_bool(on_body).override_failure_message("%s prompt %s, head %s, feet %s" % [id, prompt, head, feet]).is_false()

## The residents and the market's facilities stand where the player can walk up to them, and every door leads out.
func test_residents_facilities_and_doors_are_walked_to() -> void:
	for job in [["sh_tackle_1", "npc_kai"], ["sh_post_1", "npc_pip"], ["sh_market_1", "use_market_board"], ["sh_market_1", "use_specialty_shelf"]]:
		var r := _room(str(job[0]))
		_tap(r, str(job[1]))
		_walk_until_idle(r, 10.0)
		assert_array(r.used).override_failure_message(str(job)).is_equal([job[1]])
		var stand := P0RoomAnchors.stand_for(str(job[1]), r._anchors.keys())
		assert_float(P0Room._flat_distance(r.arrived[job[1]], r.anchor(stand).global_position)).override_failure_message(str(job)).is_less(P0Room.REACH_M + 0.05)
	for id in ["sh_tackle_1", "sh_tea_1", "sh_post_1", "sh_market_1"]:
		var r := _room(id)
		var left := [0]
		r.left.connect(func(): left[0] += 1)
		r.actor.teleport(r.anchor("stand_keeper").global_position)
		r.p0_frame({}, 0.1)
		r.walk_to("exit")
		_walk_until_idle(r, 10.0)
		assert_int(left[0]).override_failure_message(id).is_equal(1)
