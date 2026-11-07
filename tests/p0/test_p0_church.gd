extends GdUnitTestSuite
## Grace Cathedral (SGODOT-423; 亚瑟 / 后裔: role `church`, keeper {}, art `poi_church`, 黄忠's kit): its pin, its card
## and its room. And what made 0.3.0 safe without a forced update (亚瑟 on 423), kept for the next new kind of place: an
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
	assert_bool(r.npcs.is_empty()).is_true()   # no keeper, no residents, no sign
	assert_object(r.get_node_or_null("Room").find_child("SignText", true, false)).is_null()
	assert_float(P0Room._flat_distance(r.actor.position, r.anchor("spawn").global_position)).is_less(0.2)
	assert_str(r.exit_to).is_equal("Map")
	for n in P0Outposts.find(CHURCH_ID).seats: assert_object(r.anchor(str(n))).override_failure_message(str(n)).is_not_null()
	assert_array(r.opening_subjects()).is_equal([[r.anchor("cam_default").global_position]])   # nobody: the room's middle

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
	var seats: Array = P0Outposts.find(CHURCH_ID).seats
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
	for n in P0Outposts.find(CHURCH_ID).seats:
		r._sit_down(str(n))
		r._stand_up()
		for i in 30: r.p0_frame({}, 1.0 / 30.0)
		assert_str(r.seat).is_empty()
		assert_bool(on_door_floor.call(r.actor.position)).override_failure_message("%s up at %s" % [n, r.actor.position]).is_true()
		var at: Vector3 = r.anchor(str(n)).global_position
		assert_float(Vector2(r.actor.position.x - at.x, r.actor.position.z - at.z).length()).override_failure_message(str(n)).is_less(1.0)   # beside it
