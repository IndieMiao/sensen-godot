extends GdUnitTestSuite
## q(311) (SGODOT-470) in the outposts' rooms: the places a newcomer sends (room metres) — the spawn anchor first, then
## the rings' places that are reachable on the floor, out of the door's reach, off the seats, not behind a keeper, seen
## past the furniture and 8 px from the keys on the opening's screen — the same each time; and the visit's first `joined`
## stands the player on the room's pick (room metres to the scene's), before their first input.

class Sample extends "res://scenes/p0/p0_outpost.gd":
	func setup(a: Dictionary) -> void:
		super.setup(a)
		use_runtime = false

func _room(id: String) -> Sample:
	var vp := SubViewport.new()
	vp.size = Vector2i(360, 800)
	vp.own_world_3d = true
	add_child(auto_free(vp))
	var r := Sample.new()
	r.setup({"outpost_id": id})
	vp.add_child(r)
	auto_free(r)
	return r

func _places(id: String) -> Array:
	var r := _room(id)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var at := P0RoomAnchors.vec(r.anchor_data("spawn").get("position", [0, 0, 0]))
	var why := {}
	var places: Array = r.places(at, why)
	print("Q311 %s places %s left out %s" % [id, places, why])
	assert_vector(places[0]).is_equal(Vector2(at.x, at.z))
	assert_int(places.size()).is_less_equal(P0SpawnRing.MAX)
	var exit := r.anchor("exit")
	for p in places.slice(1):
		var w := r.room.position + Vector3(p.x, 0, p.y)
		w.y = r.floor_y
		assert_bool(r.bp.is_walkable(r.bp.world_to_cell(w))).override_failure_message("%s %s" % [id, p]).is_true()
		if exit: assert_float(Sample._flat(w, exit.global_position)).is_greater(Sample.EXIT_RADIUS_M)
		for n in r._anchors.keys():
			if str(n).begins_with("seat_"): assert_float(Sample._flat(w, r.anchor(n).global_position)).is_greater_equal(Sample.SEAT_CLEAR_M)
	assert_array(r.places(at)).is_equal(places)
	return places

func test_the_tea_house() -> void: await _places("sh_tea_1")
func test_the_post() -> void: await _places("sh_post_1")
func test_the_tackle_shop() -> void: await _places("sh_tackle_1")
func test_the_cathedral() -> void: await _places("sf_church_1")
func test_the_card_room() -> void: await _places("sf_card_room_1")
func test_the_market_square() -> void: await _places("sh_market_1")

func test_the_first_joined_lands_the_player_in_room_metres() -> void:
	var r := _room("sh_market_1")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var at := P0RoomAnchors.vec(r.anchor_data("spawn").get("position", [0, 0, 0]))
	var places: Array = r.places(at)
	assert_int(places.size()).is_greater(1)
	var o := P0Online.new()
	o.transport = func(_m: Dictionary): pass
	r.attach_online(o)
	r.landing.begin(o, places, r.to_room(r.actor.position))
	assert_bool(r.p0_landing_pending()).is_true()
	var pick: Vector2 = places[1]
	o._message(JSON.stringify({"t": "joined", "outpost": "sh_market_1", "room": 1, "capacity": 30, "rejoined": false,
		"self": 2, "epoch": 4, "spawn": [pick.x, pick.y]}))
	var now := r.to_room(r.actor.position)
	assert_float(Vector2(now.x - pick.x, now.z - pick.y).length()).is_less(0.01)
	assert_bool(r.p0_landing_pending()).is_false()
	assert_float(r.actor.position.y).is_equal_approx(r.floor_y, 0.001)
