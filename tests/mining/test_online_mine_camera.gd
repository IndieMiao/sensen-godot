extends GdUnitTestSuite

const OnlineMine = preload("res://scenes/mine/online_mine.gd")
const Layout = preload("res://modules/mining/mine_layout.gd")

func test_online_arrival_frames_server_spawn_and_same_floor_updates_keep_pan() -> void:
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = Vector2i(390, 844)
	viewport.own_world_3d = true
	add_child(viewport)
	var session := FarmSession.new(ApiClient.new("https://mine-camera.invalid", FakeTransport.new([]).callable()))
	session.farm_id = "online-mine-camera-review"
	session.state = {"inventory": {"produce": {}, "dishes": {}}, "journey": {"materials": {}},
		"mine": {"floor": 0, "run": 0, "deepest_floor": 1, "broken": {}, "cleared_floors": [], "elevator_unlocked": false}}
	var mine := OnlineMine.new()
	mine.setup({"session": session})
	viewport.add_child(mine)
	for frame in 4: await get_tree().process_frame
	var spawn := Vector3(6.75, 0, -0.75)
	var bp := Layout.navigation(1, [])
	assert_bool(bp.is_walkable(bp.world_to_cell(spawn))).is_true()
	mine.online._message({"t": "joined", "self": 1, "room": "mine:camera-review", "epoch": 1, "floor": 1, "spawn": [spawn.x, spawn.z]})
	var world := {"t": "world", "epoch": 1, "instance": "camera-review", "run": 0, "floor": 1,
		"navigation": {"cell": bp.cell_m, "rows": bp.masks.walkable, "spawn": [4.75, -0.75]},
		"cleared": [], "elevator": false, "floors": {"1": {"broken": [], "hp": []}}, "rocks": []}
	mine.online._message(world)
	for frame in 3: await get_tree().process_frame
	assert_vector(mine.player.position).is_equal_approx(spawn, Vector3.ONE * 0.001)
	assert_vector(mine._camera_center).is_equal_approx(spawn + Vector3.UP * 0.7, Vector3.ONE * 0.001)
	mine._camera_center += Vector3(3, 0, 2)
	mine._update_camera()
	var panned: Vector3 = mine._camera_center
	mine.online._message(world.duplicate(true))
	for frame in 3: await get_tree().process_frame
	assert_vector(mine._camera_center).is_equal_approx(panned, Vector3.ONE * 0.001)
	# A reconnect temporarily clears world while joined/world arrive separately.
	# Retain the same room/floor view even if its newly admitted seat is elsewhere.
	spawn = Vector3(4.25, 0, -1.25)
	mine.online._message({"t": "joined", "self": 2, "room": "mine:camera-review", "epoch": 2, "floor": 1, "spawn": [spawn.x, spawn.z]})
	world.epoch = 2
	mine.online._message(world.duplicate(true))
	for frame in 3: await get_tree().process_frame
	assert_vector(mine._camera_center).is_equal_approx(panned, Vector3.ONE * 0.001)
	assert_vector(mine.player.position).is_equal_approx(spawn, Vector3.ONE * 0.001)
	# Stairs should frame the actual arrival, then a different mine instance on
	# the same floor/run must take ownership of its new arrival view as well.
	spawn = Vector3(3.75, 0, -1.25)
	mine.online._message({"t": "floor", "epoch": 3, "floor": 2, "spawn": [spawn.x, spawn.z]})
	world.epoch = 3
	world.floor = 2
	world.floors["2"] = {"broken": [], "hp": []}
	mine.online._message(world.duplicate(true))
	for frame in 3: await get_tree().process_frame
	assert_vector(mine._camera_center).is_equal_approx(spawn + Vector3.UP * 0.7, Vector3.ONE * 0.001)
	mine._camera_center += Vector3(3, 0, 2)
	mine._update_camera()
	spawn = Vector3(5.25, 0, -1.25)
	mine.online._message({"t": "joined", "self": 3, "room": "mine:another-instance", "epoch": 4, "floor": 2, "spawn": [spawn.x, spawn.z]})
	world.epoch = 4
	world.instance = "another-instance"
	mine.online._message(world.duplicate(true))
	for frame in 3: await get_tree().process_frame
	assert_vector(mine._camera_center).is_equal_approx(spawn + Vector3.UP * 0.7, Vector3.ONE * 0.001)
