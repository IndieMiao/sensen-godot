extends GdUnitTestSuite
## q(311) (SGODOT-470) on a landmark: the places a newcomer sends on its first join (the spawn, then the rings' places on
## the ground, out of the way out's reach, 8 px from the Map key on the opening's screen), the same every time; the visit's
## first `joined` stands the player on the room's pick before their first position goes out, the arrival cover waiting
## meanwhile; a later one, or one after they walked, moves nobody.

const P0LandmarkVisit := preload("res://modules/p0/p0_landmark_visit.gd")
const ALCATRAZ := "res://scenes/landmark/alcatraz_island.tscn"
const GRIFFITH := "res://scenes/landmark/griffith_observatory.tscn"

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())

func after() -> void:
	P0Runtime.free_instance_for_tests()

func test_alcatraz_places_are_on_the_ground_and_off_the_door() -> void:
	var scene := await _scene(ALCATRAZ, "alcatraz_island", "Alcatraz Island")
	var visit: P0LandmarkVisit = scene.p0_visit
	var places := visit.online.spawns.duplicate()
	print("Q311 alcatraz places ", places)
	_check(scene, visit, places)
	assert_bool(visit.landing_pending()).is_equal(places.size() > 1)
	assert_bool(scene.p0_landing_pending()).is_equal(places.size() > 1)
	assert_array(visit.places(scene.player_position())).is_equal(places)   # the same again

func test_griffith_places_are_on_the_ground() -> void:
	var scene := await _scene(GRIFFITH, "griffith_observatory", "Griffith Observatory")
	var visit: P0LandmarkVisit = scene.p0_visit
	var places := visit.online.spawns.duplicate()
	print("Q311 griffith places ", places)
	_check(scene, visit, places)
	assert_int(places.size()).is_greater(4)   # an open lawn: most of the first ring

## The first `joined` with another place: the player stands there (on the ground), the wait is over, and the first input
## carries it; a reconnect's `joined` later moves nobody.
func test_the_first_joined_lands_the_player_and_a_later_one_does_not() -> void:
	var scene := await _scene(GRIFFITH, "griffith_observatory", "Griffith Observatory")
	var visit: P0LandmarkVisit = scene.p0_visit
	var places: Array = visit.online.spawns.duplicate()
	assert_int(places.size()).is_greater(1)
	var sent := []
	visit.online.transport = func(m: Dictionary): sent.append(m)
	var pick: Vector2 = places[1]
	visit.online._message(JSON.stringify({"t": "joined", "outpost": visit.room_id(), "room": 1, "capacity": 8,
		"rejoined": false, "self": 2, "epoch": 1, "spawn": [pick.x, pick.y]}))
	var at: Vector3 = scene.player_position()
	assert_float(Vector2(at.x - pick.x, at.z - pick.y).length()).is_less(0.01)
	assert_bool(visit.landing_pending()).is_false()
	visit.online._tick(1.0)
	var input: Array = sent.filter(func(m): return m.t == "input")
	assert_float(float(input[0].x)).is_equal_approx(pick.x, 0.01)
	var back: Vector2 = places[0]
	visit.online._message(JSON.stringify({"t": "joined", "outpost": visit.room_id(), "room": 1, "capacity": 8,
		"rejoined": true, "self": 2, "epoch": 2, "spawn": [back.x, back.y]}))
	assert_vector(scene.player_position()).is_equal(at)
	visit.clear()

## Walked before the room answered: left where they are.
func test_a_player_who_walked_is_not_landed() -> void:
	var scene := await _scene(GRIFFITH, "griffith_observatory", "Griffith Observatory")
	var visit: P0LandmarkVisit = scene.p0_visit
	var places: Array = visit.online.spawns.duplicate()
	var start: Vector3 = scene.player_position()
	scene.dev_stand(start + Vector3(0.4, 0, 0.4))
	var walked: Vector3 = scene.player_position()
	var pick: Vector2 = places[1]
	visit.online._message(JSON.stringify({"t": "joined", "outpost": visit.room_id(), "room": 1, "capacity": 8,
		"rejoined": false, "self": 2, "epoch": 1, "spawn": [pick.x, pick.y]}))
	assert_vector(scene.player_position()).is_equal(walked)
	visit.clear()

func _check(scene: Node3D, visit: P0LandmarkVisit, places: Array) -> void:
	var at: Vector3 = scene.player_position()
	assert_vector(places[0]).is_equal(Vector2(at.x, at.z))
	assert_int(places.size()).is_less_equal(P0SpawnRing.MAX)
	var exit: Vector3 = scene.exit_position()
	for i in places.size():
		var p: Vector2 = places[i]
		var g := P0LandmarkVisit._on_nav(scene.nav_map(), Vector3(p.x, at.y, p.y))
		assert_bool(g != Vector3.INF).override_failure_message("place %d %s off the ground" % [i, p]).is_true()
		if exit != Vector3.INF:
			assert_float(Vector2(p.x - exit.x, p.y - exit.z).length()).is_greater(P0LandmarkVisit.EXIT_RADIUS_M)

func _scene(path: String, id: String, name: String) -> Node3D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	viewport.own_world_3d = true
	add_child(auto_free(viewport))
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	scene.call("setup", P0LandmarkVisit.args_for({"id": id, "name": name}, "San Francisco"))
	viewport.add_child(scene)
	for frame in 120:
		await get_tree().physics_frame
		if scene.navigation_ready(): break
	var visit: P0LandmarkVisit = scene.p0_visit
	for frame in 60:
		if visit.online != null: break
		await get_tree().process_frame
	scene.set_process(false)
	return scene
