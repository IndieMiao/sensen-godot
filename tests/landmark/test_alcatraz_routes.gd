extends GdUnitTestSuite
## Alcatraz's ways up, on the runtime's navigation (424 方案 A, the user 11-08: a 15-step flight in the middle of each
## terrace, switching back, the dock to the museum about 57 m instead of 125). Read from layout.json: what the scene
## builds its navigation from, the route and walk goals the art's review walks.

const ALCATRAZ := "res://scenes/landmark/alcatraz_island.tscn"
const P0LandmarkVisit := preload("res://modules/p0/p0_landmark_visit.gd")
## The flights at the two ends (x −22 and x 8), kept beside the new ones: each one's foot and head on its terrace.
const END_FLIGHTS := [[Vector3(-22, 1, 12), Vector3(-22, 3.25, 7.5)], [Vector3(8, 3.25, 7.5), Vector3(8, 5.5, 3)],
	[Vector3(-22, 5.5, 3), Vector3(-22, 7.75, -1.5)], [Vector3(8, 7.75, -1.5), Vector3(8, 10, -6)]]
## The three middle flights' strip (terrace 1 to the summit) with their landings (上官婉儿 on 27417c0a: treads x
## −3.5 … 1, landings −4.75 … 2.25).
const MID_X := Vector2(-5.0, 2.5)

static func _v(a) -> Vector3: return Vector3(float(a[0]), float(a[1]), float(a[2]))

## The way the scene walks a tap (find_path: every polygon of the island searched, not Godot's default 4096).
func _path(scene: Node3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	return scene.find_path(from, to)

static func _length(p: PackedVector3Array) -> float:
	var out := 0.0
	for i in range(1, p.size()): out += p[i].distance_to(p[i - 1])
	return out

## Where the path ends: on the goal (a path that stops short has met a wall on the way).
static func _reaches(p: PackedVector3Array, goal: Vector3) -> bool:
	return not p.is_empty() and p[-1].distance_to(goal) < 0.6

## The dock to the museum's door: up the middle flights, about 57 m on the layout's centre line, about 62 m walked;
## the way it climbs is the middle strip, not the two ends.
func test_the_dock_to_the_museum_goes_up_the_middle() -> void:
	var scene := await _alcatraz()
	var goals: Array = scene.layout.walk_goals
	var door := _v(goals[-1])
	var p := _path(scene, _v(scene.layout.spawn), door)
	print("ALC route_centerline_m ", scene.layout.route_centerline_m, " walked ", _length(p))
	assert_bool(_reaches(p, door)).is_true()
	# the centre line (the flights as straight slopes, 马可波罗's 57.02 m) under 60; the path walked step by step (62.13 m)
	# under 70 — the ends' way was 118 m, so 70 still tells the middle from the ends
	assert_float(float(scene.layout.route_centerline_m)).is_less(60.0)
	assert_float(_length(p)).is_less(70.0)
	# every point the path climbs at above the first terrace (off the levels) is in the middle strip; the dock's
	# own flight up to the first terrace is the west one, as it was (27417c0a: three middle flights, terrace 1 up)
	var off: Array = []
	for pt in p:
		var on_level := [3.25, 5.5, 7.75, 10.0].any(func(y): return absf(pt.y - y) < 0.05)
		if pt.y > 3.3 and not on_level and (pt.x < MID_X.x or pt.x > MID_X.y): off.append(pt)
	assert_array(off).override_failure_message("climbs outside the middle strip at %s" % [off.slice(0, 3)]).is_empty()
	# and each walk goal leads to the next
	for i in range(1, goals.size()):
		assert_bool(_reaches(_path(scene, _v(goals[i - 1]), _v(goals[i])), _v(goals[i]))) \
			.override_failure_message("walk goal %d" % i).is_true()

## The flights at the two ends still go: from each one's foot its head is reached by about the flight itself.
func test_the_end_flights_still_go() -> void:
	var scene := await _alcatraz()
	for f in END_FLIGHTS:
		var p := _path(scene, f[0], f[1])
		print("ALC end flight ", f, " ", _length(p))
		assert_bool(_reaches(p, f[1])).override_failure_message("flight %s" % [f]).is_true()
		assert_float(_length(p)).override_failure_message("flight %s" % [f]).is_less(f[0].distance_to(f[1]) * 1.5 + 1.0)

## The summit has no invisible wall (#886): along the front of the museum, end to end and from the door to both ends,
## the path is about as long as the straight line.
func test_the_summit_walk_is_open() -> void:
	var scene := await _alcatraz()
	var door := _v(scene.layout.walk_goals[-1])
	var west := Vector3(-20, 10, door.z)
	var east := Vector3(20, 10, door.z)
	for pair in [[west, east], [door, west], [door, east]]:
		var p := _path(scene, pair[0], pair[1])
		print("ALC summit ", pair, " ", _length(p))
		assert_bool(_reaches(p, pair[1])).override_failure_message("summit %s" % [pair]).is_true()
		assert_float(_length(p)).override_failure_message("summit %s" % [pair]) \
			.is_less(pair[0].distance_to(pair[1]) * 1.2 + 1.0)

## A tap on each middle flight lands on it (上官婉儿 / 周瑜: the flights are geometry with trimesh collision — the tap is a
## ray on what is drawn, the walk is the navigation; the two have to agree): its middle step, on the way the dock's path
## climbs, walked to by a tap, ends on that step.
func test_a_tap_on_each_middle_flight_lands_on_it() -> void:
	var scene := await _alcatraz()
	var p := _path(scene, _v(scene.layout.spawn), _v(scene.layout.walk_goals[-1]))
	var levels := [1.0, 3.25, 5.5, 7.75, 10.0]
	for i in range(1, levels.size()):
		var on: Array = Array(p).filter(func(pt): return pt.y > levels[i - 1] + 0.3 and pt.y < levels[i] - 0.3)
		assert_array(on).override_failure_message("no climb from %s to %s" % [levels[i - 1], levels[i]]).is_not_empty()
		if on.is_empty(): continue
		var step: Vector3 = on[on.size() / 2]
		scene.walk_to_screen(scene._camera.unproject_position(step))
		assert_bool(scene._path.is_empty()).override_failure_message("tap on %s found no way" % step).is_false()
		if scene._path.is_empty(): continue
		var end: Vector3 = scene._path[-1]
		print("ALC tap ", step, " -> ", end)
		var off := Vector2(end.x - step.x, end.z - step.z).length()
		assert_float(off).override_failure_message("tap on %s ends %s" % [step, end]).is_less(1.0)
		assert_float(absf(end.y - step.y)).override_failure_message("tap on %s ends %s" % [step, end]).is_less(0.5)

## 用户 0.3.3: the stick did not take the player up the middle flights (their navigation was flat treads joined by
## upright links: a push found the nearest point on the tread it stood on). Each middle flight (layout.stairs with an
## ascent), from its lower landing's middle, the stick held the way it climbs: the player is up on its upper landing;
## held the other way, back down on the lower one.
func test_the_stick_climbs_each_middle_flight() -> void:
	var scene := await _alcatraz()
	var cam: Camera3D = scene._camera
	var right := Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()
	var ahead := Vector3(-cam.global_basis.z.x, 0, -cam.global_basis.z.z).normalized()
	var flights: Array = scene.layout.stairs.filter(func(f): return f.has("ascent"))
	assert_int(flights.size()).is_equal(3)
	for f in flights:
		var low: Array = f.lower_platform
		var mid := Vector2((float(low[0]) + float(low[1])) * 0.5, (float(low[2]) + float(low[3])) * 0.5)
		var start := Vector3(mid.x, float(f.lower), mid.y)
		scene._player.position = NavigationServer3D.map_get_closest_point(scene._nav_map, start)
		var way := Vector3(1 if str(f.ascent) == "east" else -1, 0, 0)
		var stick := Vector2(way.dot(right), -way.dot(ahead))   # P0LandmarkVisit.stick_step's own sum, solved
		for frame in 240:   # 8 s at 30 fps: the 4.5 m run and a landing at the walk's speed, with room
			scene.step_stick(stick, 1.0 / 30.0)
			if scene.player_position().y >= float(f.upper) - 0.05: break
		var at: Vector3 = scene.player_position()
		print("ALC stick flight ", f.flight, " from ", start, " to ", at)
		assert_float(at.y).override_failure_message("flight %d stopped at %s" % [f.flight, at]) \
			.is_greater(float(f.upper) - 0.1)
		for frame in 240:   # and back down the way it came
			scene.step_stick(-stick, 1.0 / 30.0)
			if scene.player_position().y <= float(f.lower) + 0.05: break
		at = scene.player_position()
		assert_float(at.y).override_failure_message("flight %d stopped going down at %s" % [f.flight, at]) \
			.is_less(float(f.lower) + 0.1)
		scene.step_stick(Vector2.ZERO, 1.0 / 30.0)

func _alcatraz() -> Node3D:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 800)
	viewport.own_world_3d = true
	add_child(auto_free(viewport))
	var scene := (load(ALCATRAZ) as PackedScene).instantiate() as Node3D
	scene.call("setup", P0LandmarkVisit.args_for({"id": "alcatraz_island", "name": "Alcatraz Island"}, "San Francisco"))
	viewport.add_child(scene)
	for frame in 120:
		await get_tree().physics_frame
		if scene.navigation_ready(): break
	for frame in 10: await get_tree().physics_frame   # the zones' navigation meshes join a sync or two after the first
	scene.set_process(false)
	return scene
