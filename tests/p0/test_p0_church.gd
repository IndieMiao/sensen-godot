extends GdUnitTestSuite
## Grace Cathedral (SGODOT-423; 亚瑟 / 后裔: role `church`, art `poi_church`, 黄忠's kit): its pin, its card and its
## room, and Gabriel the priest, its keeper who only talks (q(299)). And what made 0.3.0 safe without a forced update (亚瑟 on 423), kept for the next new kind of place: an
## outpost of a role and art this build does not know falls back — the travel icon at the post's rank, a card with no
## keeper row, the Basic Room — and nothing errors.

const P0_MAP := "res://scenes/p0/p0_map.tscn"
const P0Map := preload("res://scenes/p0/p0_map.gd")
const CHURCH_ID := "sf_church_1"
const UNKNOWN := {"id": "sf_unknown_1", "role": "chapel", "name": "Test Chapel",
	"category": "Chapel · Quiet", "lat": 37.7919, "lng": -122.4130, "capacity": 12, "seats": [],
	"art": "poi_chapel", "anchors": "res://assets/p0/outposts/chapel.anchors.json", "keeper": {}, "residents": []}

class Room extends "res://scenes/p0/p0_outpost.gd":
	func setup(a: Dictionary) -> void:
		super.setup(a)
		use_runtime = false

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	P0Runtime.ensure().here = {"space": "home", "place": ""}
	P0Outposts.all().append(UNKNOWN.duplicate(true))

func after_test() -> void:
	P0Outposts._list = P0Outposts._list.filter(func(o): return str(o.id) != str(UNKNOWN.id))

func _map() -> Node:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	add_child(auto_free(viewport))
	var m: Node = (load(P0_MAP) as PackedScene).instantiate()
	viewport.add_child(m)
	return m

func _room(id: String, phone := false) -> Room:
	var r := Room.new()
	r.setup({"outpost_id": id})
	if phone:   # a 360 × 800 screen, as the phone's
		var vp := SubViewport.new()
		vp.size = Vector2i(360, 800)
		add_child(auto_free(vp))
		vp.add_child(r)
	else:
		add_child(r)
	auto_free(r)
	return r

func test_the_cathedral_pin_and_card() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var entry := P0Outposts.place_entry(P0Outposts.find(CHURCH_ID))
	assert_str(str(entry.art_path)).is_equal(str(P0Outposts.PIN_ART.church))   # the stained glass without its cross
	var style: Dictionary = m._destination_style_of(entry)
	assert_object(style.icon).is_equal(P0Logic.icon(str(P0Map.PIN_ICONS.church)))
	assert_int(int(style.rank)).is_equal(int(P0Map.PIN_RANK.tea))
	assert_str(str(style.label)).is_equal(P0Map.short_name("Grace Cathedral"))
	var card: Dictionary = m.place_card(entry)
	assert_str(str(card.title)).is_equal("Grace Cathedral")
	assert_str(str(card.subtitle)).is_equal("Church · Stained glass")

func test_the_cathedral_room_on_its_kit() -> void:
	var r := _room(CHURCH_ID)
	await get_tree().process_frame
	r.p0_frame({}, 1.0 / 30.0)
	assert_str(r.place_name).is_equal("Grace Cathedral")
	assert_str(r.art.scene_file_path).is_equal("res://scenes/poi_church/poi_church_art.tscn")
	assert_array(r.npcs.keys()).is_equal(["npc_keeper"])   # Gabriel (q(299)); no residents, no sign
	assert_str(str(r.npcs.npc_keeper.name)).is_equal("Gabriel")
	assert_object(r.get_node_or_null("Room").find_child("SignText", true, false)).is_null()
	assert_float(P0Room._flat_distance(r.actor.position, r.anchor("spawn").global_position)).is_less(0.2)
	assert_str(r.exit_to).is_equal("Map")
	# q(304): six pews, one seat each; the table keeps the two second seats for older clients, which have no anchor here
	assert_int(P0Outposts.find(CHURCH_ID).seats.size()).is_equal(8)
	assert_array(Array(r._lone_seats())).is_equal(["seat_left_1", "seat_left_2", "seat_left_3", "seat_right_1", "seat_right_2", "seat_right_3"])
	for n in r.LEGACY_SEATS: assert_object(r.anchor(str(n))).override_failure_message(str(n)).is_null()
	assert_vector(r.opening_subjects()[0][0]).is_equal(r.npcs.npc_keeper.root.global_position)   # the opening frames him

func test_an_unknown_place_falls_back() -> void:
	var m := _map()
	for i in 3: await get_tree().process_frame
	m.set_process(false)
	var entry := P0Outposts.place_entry(P0Outposts.find(str(UNKNOWN.id)))
	var style: Dictionary = m._destination_style_of(entry)
	assert_object(style.icon).is_equal(P0Logic.icon("travel"))
	assert_int(int(style.rank)).is_equal(int(P0Map.PIN_RANK.post))
	assert_str(str(m.place_card(entry).title)).is_equal("Test Chapel")
	m._set_outpost_places()
	var r := _room(str(UNKNOWN.id))
	await get_tree().process_frame
	assert_str(r.art.scene_file_path).is_equal(r.BASIC_ROOM_ART)
	assert_object(r.anchor("spawn")).is_not_null()
	r.p0_frame({}, 1.0 / 30.0)

## The pews (黄忠's README: an i-seat over each of the eight seats, no seat names): each seat its own prompt — there is
## no table or bench anchor to stand for them as at the tea house — and a tap walks there and sits. The card room's bar
## stools (the tavern kit's seat_ points, its seats []) stay scenery.
func test_each_pew_seat_is_its_own_prompt() -> void:
	var r := _room(CHURCH_ID)
	await get_tree().process_frame
	var seats: Array = Array(r._lone_seats())
	assert_int(seats.size()).is_equal(6)
	for n in seats:
		assert_array(Array(r._tappable())).override_failure_message(str(n)).contains([n])
		assert_str(str(r._marker(str(n), {}).get("kind", ""))).override_failure_message(str(n)).is_equal("seat")
	r.p0_tap(r.cam.unproject_position(r.anchor("seat_right_2").global_position))
	var t := 0.0
	while t < 8.0 and r.seat == "":
		r.p0_frame({}, 1.0 / 30.0)
		t += 1.0 / 30.0
	assert_str(r.seat).is_equal("seat_right_2")
	assert_dict(r._marker("seat_left_1", {})).is_empty()   # seated: no seat prompts until the player stands
	var cards := _room("sf_card_room_1")
	await get_tree().process_frame
	assert_bool(Array(cards._tappable()).any(func(n): return str(n).begins_with("seat_"))).is_false()

## The cathedral's camera follows the player (上官婉儿 / 不知火舞 on 423, 李元芳's recording: by the organ the player
## went out of sight) but never past REACH_INSET_M from its footprint's edges — its art's box on the 45° screen is a
## diamond with empty corners; the opening is as before. A room without a camera_contract (the tea house) is not held.
func test_the_cathedral_camera_keeps_to_its_reach() -> void:
	var r := _room(CHURCH_ID)
	await get_tree().process_frame
	r.p0_frame({}, 1.0 / 30.0)
	var opening: Vector3 = r._focus
	var half := 10.5 * 0.5 - P0Room.REACH_INSET_M
	for corner in [Vector3(-5, 0, -5), Vector3(5, 0, -5), Vector3(-5, 0, 5), Vector3(5, 0, 5)]:
		var f: Vector3 = r._clamp_to_reach(r.room.position + corner) - r.room.position
		assert_float(absf(f.x)).is_less_equal(half + 0.001)
		assert_float(absf(f.z)).is_less_equal(half + 0.001)
	assert_vector(r._clamp_to_reach(opening)).is_equal_approx(opening, Vector3.ONE * 0.001)   # the opening: not moved
	var tea := _room("sh_tea_1")
	await get_tree().process_frame
	var far := tea.room.position + Vector3(9, 0, 9)
	assert_vector(tea._clamp_to_reach(far)).is_equal(far)

## 周瑜 on #846: in every corner of the room's bounds the player is still on the screen, a margin in (the reach gives
## way for them).
func test_the_player_stays_on_screen_in_every_corner() -> void:
	var r := _room(CHURCH_ID, true)
	await get_tree().process_frame
	var b: Array = P0Outposts.find(CHURCH_ID).bounds
	for c in [Vector2(b[1], b[2]), Vector2(b[0], b[3]), Vector2(b[0], b[2]), Vector2(b[1], b[3])]:
		r.actor.teleport(r.room.position + Vector3(c.x, r.floor_y, c.y))
		r._focus = r.actor.position
		for i in 90: r.p0_frame({}, 1.0 / 30.0)
		var view := r._view()
		for p in [r.actor.position, r.actor.position + Vector3(0, 1.75, 0)]:
			var at := r.cam.unproject_position(p)
			assert_bool(Rect2(Vector2(12, 0), view - Vector2(24, 0)).has_point(at)).override_failure_message("%s at %s, %s" % [c, at, view]).is_true()

## 李元芳 on 0.3.1: up from a pew the player stood in the gap between the left rows and could not walk out. Up from
## every seat they stand beside it on floor the door reaches, and the spawn is on that floor too.
func test_up_from_every_pew_onto_the_floor_the_door_reaches() -> void:
	var r := _room(CHURCH_ID)
	await get_tree().process_frame
	var door: Vector3 = r.anchor("exit").global_position
	var on_door_floor := func(p: Vector3) -> bool:
		var c := P0RoomNav.nearest_reachable(r.bp, p, door)
		return r.bp.world_to_cell(c) == r.bp.world_to_cell(p)
	assert_bool(on_door_floor.call(r.actor.position)).override_failure_message("spawn %s" % r.actor.position).is_true()
	for n in r._lone_seats():
		r._sit_down(str(n))
		r._stand_up()
		for i in 30: r.p0_frame({}, 1.0 / 30.0)
		assert_str(r.seat).is_empty()
		assert_bool(on_door_floor.call(r.actor.position)).override_failure_message("%s up at %s" % [n, r.actor.position]).is_true()
		var at: Vector3 = r._walk_point(str(n), r.anchor(str(n)))   # q(304): up at its pew's aisle end, where it was slid in from
		assert_float(Vector2(r.actor.position.x - at.x, r.actor.position.z - at.z).length()).override_failure_message(str(n)).is_less(0.6)
		assert_bool(P0RoomNav._open(r.bp, r.bp.world_to_cell(r.actor.position), 2)).override_failure_message("%s in the open" % n).is_true()   # not at a pew's end between rows

## 不知火舞 on #850: the tea house's stools stand up beside them on the door's floor (no open-ground rule there, the
## cathedral's is its kit's), and never hidden behind someone — up from the third table's they were, behind Hana.
func test_tea_stools_stand_up_beside_them_in_sight() -> void:
	for n in ["seat_table2_2", "seat_table3_1", "seat_table1_1"]:
		var r := _room("sh_tea_1")
		await get_tree().process_frame
		r._sit_down(n)
		r._stand_up()
		for i in 30: r.p0_frame({}, 1.0 / 30.0)
		var at: Vector3 = r.anchor(n).global_position
		assert_float(Vector2(r.actor.position.x - at.x, r.actor.position.z - at.z).length()).override_failure_message(n).is_less(1.0)
		var people: Array = r.npcs.values().map(func(x): return (x.root as Node3D).global_position)
		assert_bool(P0RoomNav.hidden(r.actor.position, people, r._cam_dir)).override_failure_message("%s behind someone" % n).is_false()

## q(299): Gabriel greets with no Trade — only his question, which tells his stories in turn, one a tap, round again
## after the fifth — and he gives no requests (church is not in requests.local.roles; the card shows none).
func test_gabriel_only_talks() -> void:
	var lines := P0Logic.keeper_lines({}, "church")
	assert_bool(bool(lines.talk_only)).is_true()
	assert_array(lines.answers).is_equal(P0Logic.CHURCH_STORIES)
	assert_bool(bool(P0Logic.keeper_lines({}, "tea").get("talk_only", false))).is_false()
	var ui := P0Ui.new()
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.open_keeper_greeting("church", {"outpost": CHURCH_ID})
	assert_str(ui.modal_kind).is_equal("greeting")
	var card: UiDialogueCard = ui._modal.find_children("*", "UiDialogueCard", true, false)[0]
	assert_str(card.title).is_equal("Priest · Gabriel")
	assert_array(card.content.get_children().map(func(b): return (b as Button).text)).is_equal(["Any stories?"])
	assert_str(card.line).is_equal("Welcome to Grace. Sit as long as you like.")
	var told := []
	for i in 6:
		(card.content.get_child(0) as UiCommandButton).activated.emit()
		told.append(card.line)
	assert_array(told).is_equal(P0Logic.CHURCH_STORIES + [P0Logic.CHURCH_STORIES[0]])

## 不知火舞 / 上官婉儿 on q(299): Gabriel stands up on the sanctuary, so by his own spot every floor point is nearer the
## first pews' seats; at the spot the player talks to him from it is his name that opens, and beside a pew its seat.
func test_gabriel_opens_at_his_talking_spot() -> void:
	var r := _room(CHURCH_ID)
	await get_tree().process_frame
	var marks := {}
	for n in r._tappable():
		var m: Dictionary = r._marker(n, {})
		if not m.is_empty(): marks[n] = m
	r.actor.teleport(r.anchor("stand_keeper").global_position)
	assert_str(r.card_pick(marks)).is_equal("npc_keeper")
	r._card = ""
	r.actor.teleport(r.room.position + Vector3(-0.375, r.floor_y, 1.03))   # the aisle beside the second left pew
	assert_str(r.card_pick(marks)).is_equal("seat_left_2")

## q(300) v1.2, SGODOT-445 (the user 11-08; 不知火舞 priest-buff ui-spec v1.2 §2): one full-width `Pray` over
## `Any stories?`; each tap draws Twin Catch or Swift Growth half and half and sends the buff command, the card stays up.
## No time on the card. In the demo (no limit) no count line; from 11-15 `2 left today`, then a grey Pray with
## `Limit reached · resets in …`. A server without buffs (no view.buff_takes) shows no Pray.
func test_gabriel_prays() -> void:
	assert_str(P0Logic.pray_draw(0.0)).is_equal("fish")
	assert_str(P0Logic.pray_draw(0.4999)).is_equal("fish")
	assert_str(P0Logic.pray_draw(0.5)).is_equal("farm")
	assert_str(P0Logic.pray_draw(0.9999)).is_equal("farm")
	assert_dict(P0Logic.priest_pray({})).is_empty()
	var demo := {"buffs": [{"id": "fish", "left": 761000.0}], "buff_takes": {"used": 7, "limit": null, "resets_in": 3600000.0}}
	assert_dict(P0Logic.priest_pray(demo)).is_equal({"reason": "", "line": ""})
	# the view ages the buffs: past the end one is gone from the array (亚瑟's `… has worn off`)
	assert_float(float(P0Logic.project(demo, 41000.0).buffs[0].left)).is_equal(720000.0)
	assert_array(P0Logic.project(demo, 761000.0).buffs).is_empty()
	assert_array(demo.buffs).has_size(1)   # the server's view left as it was
	var ui := P0Ui.new()
	add_child(auto_free(ui))
	await await_idle_frame()
	ui.view = demo
	ui.open_keeper_greeting("church", {"outpost": CHURCH_ID})
	var card: UiDialogueCard = ui._modal.find_children("*", "UiDialogueCard", true, false)[0]
	var keys := card.content.get_children().filter(func(n): return n is UiCommandButton)
	assert_array(keys.map(func(b): return (b as UiCommandButton).label)).is_equal(["Pray", "Any stories?"])
	var pray := keys[0] as UiCommandButton
	var count := card.content.get_node("PrayCount") as Label
	assert_int(pray.kind).is_equal(UiCommandButton.Kind.PRIMARY)
	assert_str(pray.reason).is_empty()
	assert_bool(count.visible).is_false()
	var sent := []
	ui.command.connect(func(c): sent.append(c))
	var rolls := [0.2, 0.7, 0.3]
	ui.pray_roll = func() -> float: return rolls.pop_front()
	for i in 3: pray.activated.emit()
	assert_array(sent.map(func(c): return c.buff)).is_equal(["fish", "farm", "fish"])
	assert_bool(sent.all(func(c): return c.type == "buff")).is_true()
	assert_str(ui.modal_kind).is_equal("greeting")
	# from 11-15: the count line, then the grey key with the limit beside it
	ui.set_view({"buffs": [], "buff_takes": {"used": 1, "limit": 2, "resets_in": 3600000.0}})
	assert_bool(count.visible).is_true()
	assert_str(count.text).is_equal("1 left today")
	assert_str(pray.reason).is_empty()
	ui.set_view({"buffs": [], "buff_takes": {"used": 2, "limit": 2, "resets_in": 18720000.0}})
	assert_str(count.text).is_equal("Limit reached · resets in 5h 12m")
	assert_str(pray.reason).is_equal("Limit reached · resets in 5h 12m")
	assert_str(pray.label).is_equal("Pray")

# ---------------------------------------------------------------- q(304): one seat in each pew's middle
## The user on 0.3.5 (q(304), 李白 / 不知火舞): each pew seats one, its icon in the pew's middle; the icons are not pushed
## apart from each other (overlapping is fine), still off the door and the open name strip. One walks to the pew's aisle
## end and slides along it to the middle, as long as the slide takes.
func test_one_seat_in_each_pews_middle() -> void:
	var r := _room(CHURCH_ID)
	await get_tree().process_frame
	var pews := {}
	for a in r.layout.get("instances", []): if str(a.name).begins_with("pew_"): pews[str(a.name)] = a
	assert_int(pews.size()).is_equal(6)
	for n in r._lone_seats():
		var pew: Dictionary = pews[str(r.anchor_data(n).module)]
		var at: Vector3 = r.anchor(n).position
		assert_float(at.x).override_failure_message(n).is_equal_approx(float(pew.position[0]), 0.001)   # its middle
		assert_float(at.z).override_failure_message(n).is_equal_approx(float(pew.position[2]), 0.03)
		# walked to from the aisle end of its pew (the layout's approach), not the floor nearest the middle
		var appr: Array = r.anchor_data(n).approach
		var want: Vector3 = (r.anchor(n).get_parent() as Node3D).to_global(Vector3(float(appr[0]), float(appr[1]), float(appr[2])))
		assert_float(P0Room._flat_distance(r._walk_point(n, r.anchor(n)), want)).override_failure_message(n).is_less(0.2)   # on the floor by it
		assert_bool(r._may_overlap(n)).is_true()
	# from the aisle the slide to the middle takes longer than the 0.3 s onto a stool
	r.actor.teleport(r._walk_point("seat_left_2", r.anchor("seat_left_2")))
	r._sit_down("seat_left_2")
	assert_float(float(r._glide.dur)).is_greater(r.SIT_GLIDE_S)
	assert_float(float(r._glide.dur)).is_equal_approx(P0Room._flat_distance(r._glide.from, r._glide.to) / r.SIT_SLIDE_MPS, 0.01)
	r._glide = {}
	r._stand_up()   # getting up: no seat prompts while sliding out, back once on the aisle (不知火舞 on #925)
	assert_dict(r._marker("seat_left_1", {})).is_empty()
	for i in 60: r.p0_frame({}, 1.0 / 30.0)
	assert_str(str(r._marker("seat_left_1", {}).get("kind", ""))).is_equal("seat")
	var tea := _room("sh_tea_1")   # elsewhere seats are walked to, slid onto and spread as before
	await get_tree().process_frame
	assert_bool(tea._may_overlap("seat_table1_1")).is_false()
	tea.actor.teleport(tea.anchor("seat_table1_1").global_position + Vector3(2, 0, 0))
	tea._sit_down("seat_table1_1")
	assert_float(float(tea._glide.dur)).is_equal(tea.SIT_GLIDE_S)

## spread's ①: buttons that may overlap stay on each other; the door and any other button still push them off.
func test_pew_icons_overlap_but_keep_off_the_door() -> void:
	var screen := Rect2(0, 0, 360, 800)
	var spots := {"seat_left_1": Vector2(100, 400), "seat_left_2": Vector2(110, 410), "exit": Vector2(200, 600), "seat_right_1": Vector2(205, 605)}
	var pews := {"seat_left_1": true, "seat_left_2": true, "seat_right_1": true}
	var out: Dictionary = P0Room.spread(spots, spots.keys(), Rect2(), screen, 60.0, {}, {}, pews).spots
	assert_vector(out.seat_left_1).is_equal(spots.seat_left_1)   # the two seats stay where they are, on each other
	assert_vector(out.seat_left_2).is_equal(spots.seat_left_2)
	assert_float((out.seat_right_1 as Vector2).distance_to(out.exit)).is_greater_equal(P0Room.SPREAD_GAP - 0.01)   # off the door
	var apart: Dictionary = P0Room.spread(spots, spots.keys(), Rect2(), screen, 60.0).spots   # without: as before
	assert_float((apart.seat_left_2 as Vector2).distance_to(apart.seat_left_1)).is_greater_equal(P0Room.SPREAD_GAP - 0.01)
	spots["use_x"] = Vector2(130, 400)   # another button among them: kept off both seats
	out = P0Room.spread(spots, spots.keys(), Rect2(), screen, 60.0, {}, {}, pews).spots
	for n in ["seat_left_1", "seat_left_2"]:
		assert_float((out.use_x as Vector2).distance_to(out[n])).override_failure_message(n).is_greater_equal(P0Room.SPREAD_GAP - 0.01)

## While older clients are about (q(304), 不知火舞): one sitting on a second seat taken off its pew makes that pew taken —
## no icon, no seat for us — and is drawn at that pew's seat height where it sat.
func test_an_older_clients_second_seat_takes_its_pew() -> void:
	var r := _room(CHURCH_ID)
	await get_tree().process_frame
	assert_bool(r._free_seats("seat_left_2").is_empty()).is_false()
	r.online = P0Online.new()
	add_child(auto_free(r.online))
	r.online.self_id = 1
	r.online.members = {1: {"seat": ""}, 7: {"seat": "seat_left_4"}}
	assert_bool(r._free_seats("seat_left_2").is_empty()).is_true()
	assert_dict(r._marker("seat_left_2", {})).is_empty()
	assert_bool(r._free_seats("seat_left_1").is_empty()).is_false()   # the other pews as they were
	assert_float(r.seat_root_y("seat_left_4")).is_equal_approx(r.seat_root_y("seat_left_2"), 0.001)
	assert_float(r._crowd_height(7)).is_equal_approx(r.seat_root_y("seat_left_2") - r.room.position.y, 0.001)

