extends GdUnitTestSuite
## q(311) (SGODOT-470) at a pond: the places a newcomer sends — the spawn, then the rings' places on the walk (not in the
## water, not on a trunk, not behind a tree), out of every gathering point's reach (or the key would be Gather, v4.1 4.1.3)
## and whole on screen — the same each time; the visit's first `joined` stands the player on the room's pick.

const P0Pond := preload("res://scenes/p0/p0_pond.gd")
const PondGather := preload("res://scenes/p0/p0_pond_gather.gd")
const PondWalk := preload("res://modules/ponds/pond_walk.gd")
const PHONE := Vector2(360, 800)

func _pond(points: Array = []) -> Node3D:
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_pond.gd\"\nfunc _ready() -> void: pass\n"
	stub.reload()
	var vp := SubViewport.new()
	vp.size = Vector2i(PHONE)
	vp.own_world_3d = true
	add_child(auto_free(vp))
	var pond: Node3D = Node3D.new()
	pond.set_script(stub)
	vp.add_child(pond)
	pond.entry = preload("res://modules/p0/p0_ponds.gd").location("pond_san_francisco_03")   # Fern Pond
	pond.bp = PondWalk.blueprint(pond.entry)
	pond.grid = BlueprintGrid.new(pond.bp)
	pond.cam = Camera3D.new()
	pond.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	pond.cam.keep_aspect = Camera3D.KEEP_WIDTH
	pond.add_child(pond.cam)
	pond.cam.make_current()
	pond.actor = P0Actor.new()
	pond.add_child(pond.actor)
	pond.actor.setup(pond.bp, pond.grid, pond.cam)
	pond.gather = PondGather.new()
	pond.add_child(pond.gather)
	pond.gather.sync({"gather": {"pond": {"pond": "pond_san_francisco_03", "points": points}}})
	pond._focus = pond.actor.position
	return pond

func test_fern_ponds_places_are_on_the_walk_and_the_same_each_time() -> void:
	var pond := _pond()
	var at: Vector3 = pond.actor.position
	var places: Array = pond.places(at)
	print("Q311 fern places ", places)
	assert_vector(places[0]).is_equal(Vector2(at.x, at.z))
	assert_int(places.size()).is_greater(1)
	for p in places:
		assert_bool(pond.bp.is_walkable(pond.bp.world_to_cell(Vector3(p.x, 0, p.y)))).override_failure_message("%s" % p).is_true()
	assert_array(pond.places(at)).is_equal(places)

## A gathering point 1.2 m to the screen's right of the spawn: the right places within its reach are left out.
func test_a_place_in_a_gathering_points_reach_is_left_out() -> void:
	var pond := _pond()
	var at: Vector3 = pond.actor.position
	var free: Array = pond.places(at)
	var near := at + P0Pond.right_axis() * 1.2
	var point := {"id": "g1", "kind": "reed", "x": near.x, "z": near.z}
	pond = _pond([point])
	var places: Array = pond.places(at)
	print("Q311 fern places by a point ", places)
	for p in places.slice(1):
		assert_bool(PondGather.in_reach(point, Vector3(p.x, 0, p.y))).override_failure_message("%s" % p).is_false()
	assert_int(places.size()).is_less(free.size())

func test_the_first_joined_lands_the_player() -> void:
	var pond := _pond()
	var at: Vector3 = pond.actor.position
	var places: Array = pond.places(at)
	var o := P0Online.new()
	var sent := []
	o.transport = func(m: Dictionary): sent.append(m)
	pond.crowd = auto_free(Node3D.new())
	pond.crowd.set_script(load("res://modules/net/online_crowd.gd"))
	pond.attach_online(o)
	o.spawns.assign(places)
	pond.landing.begin(o, places, at)
	assert_bool(pond.p0_landing_pending()).is_true()
	var pick: Vector2 = places[1]
	o._message(JSON.stringify({"t": "joined", "outpost": "pond:pond_san_francisco_03", "room": 1, "capacity": 8,
		"rejoined": false, "self": 2, "epoch": 4, "spawn": [pick.x, pick.y]}))
	assert_float(Vector2(pond.actor.position.x - pick.x, pond.actor.position.z - pick.y).length()).is_less(0.01)
	assert_bool(pond.p0_landing_pending()).is_false()
	assert_bool(o.spawns.is_empty()).is_true()
