extends GdUnitTestSuite
## Alcatraz's dock (SGODOT-474, 上官婉儿's ruling d7980cff): the player lands at (−22, 1, 17), in the walkway's middle, not
## in the crates; the crates, the two bollards, the welcome sign, the two planters and the shelter's posts and bench are
## out of the navigation (the stick and a tap walk only on it), kept clear of by the island's clearance (0.25 m); the
## shelter's posts and bench only, not its roof (they take all but its edges, so the walk ends at the roof's edge). Read from layout.json, what the scene builds them from.

const ALCATRAZ := "res://scenes/landmark/alcatraz_island.tscn"
const P0LandmarkVisit := preload("res://modules/p0/p0_landmark_visit.gd")
const SPAWN := Vector3(-22, 1, 17)
const PROPS := ["alc_dock_crates_000", "alc_dock_bollard_000", "alc_dock_bollard_001", "alc_dock_welcome_000",
	"alc_dock_planter_000", "alc_dock_planter_001"]
## The shelter's posts and bench (alc_dock_shelter.glb's parts, its local x along the long side): world x −23.41 … −22.59,
## z 13.78 … 16.92 at (−23, 15.35) turned 90°.
const SHELTER_SOLID := Rect2(-23.41, 13.78, 0.82, 3.14)
## q(311)'s places on the dock for the 2nd to the 4th player in (安其拉 on 474, 13150e3e): on the navigation.
const Q311 := [Vector2(-21.27, 16.81), Vector2(-21.80, 16.28), Vector2(-21.60, 15.55)]

func after() -> void:
	P0Runtime.free_instance_for_tests()

static func _v(a) -> Vector3: return Vector3(float(a[0]), float(a[1]), float(a[2]))

static func _on_nav(scene: Node3D, x: float, z: float) -> bool:
	var at := Vector3(x, 1, z)
	var p := NavigationServer3D.map_get_closest_point(scene._nav_map, at)
	return Vector2(p.x - x, p.z - z).length() < 0.01 and absf(p.y - 1.0) < 0.2

## A placement's footprint on the ground (its mesh's box, turned with it).
static func _footprint(scene: Node3D, name: String) -> Rect2:
	for p in scene.layout.placements:
		if str(p.name) != name: continue
		var box: AABB = scene._transform_of(p) * scene._mesh(str(p.asset)).get_aabb()
		return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
	return Rect2()

func test_the_player_lands_in_the_walkway() -> void:
	var scene := await _alcatraz()
	assert_vector(_v(scene.layout.spawn)).is_equal(SPAWN)
	var anchor: Array = scene.layout.anchors.filter(func(a): return str(a.name) == "spawn")
	assert_vector(_v(anchor[0].position)).is_equal(SPAWN)
	assert_bool(_on_nav(scene, SPAWN.x, SPAWN.z)).is_true()
	# far enough from the way out that the visit does not step them off it (2.6 m, P0LandmarkVisit.START_FROM_EXIT_M 2.2)
	var exit := _v(scene.layout.exit)
	assert_float(Vector2(SPAWN.x - exit.x, SPAWN.z - exit.z).length()).is_greater(P0LandmarkVisit.START_FROM_EXIT_M)
	assert_bool(_footprint(scene, "alc_dock_crates_000").has_point(Vector2(SPAWN.x, SPAWN.z))).is_false()

## No point of the navigation in a prop or within 0.2 m of it (the clearance is 0.25, its cells' edges on a 0.25 grid).
func test_the_dock_props_are_walked_round() -> void:
	var scene := await _alcatraz()
	var solids: Array = PROPS.map(func(n): return _footprint(scene, n))
	solids.append(SHELTER_SOLID)
	for i in solids.size():
		var r: Rect2 = (solids[i] as Rect2).grow(0.2)
		var inside: Array = []
		var x := r.position.x
		while x <= r.end.x:
			var z := r.position.y
			while z <= r.end.y:
				if _on_nav(scene, x, z): inside.append(Vector2(x, z))
				z += 0.05
			x += 0.05
		assert_array(inside).override_failure_message("%s: walkable at %s" % [(PROPS + ["shelter"])[i], inside.slice(0, 3)]).is_empty()
	# the walkway beside the shelter stays: up to the roof's east edge (x −22.5; the bench's front at −22.69 and the
	# clearance on the 0.25 grid end the navigation at −22.25)
	assert_bool(_on_nav(scene, -22.2, 15.35)).is_true()

## The way out, the dock's land end between the planters and the museum are all still reached from where the player lands.
func test_the_dock_still_leads_everywhere() -> void:
	var scene := await _alcatraz()
	for goal in [_v(scene.layout.exit), Vector3(-22.4, 1, 12.1), _v(scene.layout.walk_goals[-1])]:
		var p: PackedVector3Array = scene.find_path(SPAWN, goal)
		assert_bool(not p.is_empty() and p[-1].distance_to(goal) < 0.6).override_failure_message("to %s" % goal).is_true()
	for at in Q311:
		assert_bool(_on_nav(scene, at.x, at.y)).override_failure_message("q(311) place %s" % at).is_true()

## The stick pushed at the crates, then at the bollard and the shelter from the walkway: the player stops short of each.
func test_the_stick_stops_at_the_props() -> void:
	var scene := await _alcatraz()
	var cam: Camera3D = scene._camera
	var right := Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()
	var ahead := Vector3(-cam.global_basis.z.x, 0, -cam.global_basis.z.z).normalized()
	var crates := _footprint(scene, "alc_dock_crates_000")
	var bollard := _footprint(scene, "alc_dock_bollard_001")
	for leg in [[SPAWN, crates], [Vector3(-21.9, 1, 15.65), bollard], [Vector3(-22.0, 1, 15.35), SHELTER_SOLID]]:
		var from: Vector3 = leg[0]
		var solid: Rect2 = leg[1]
		scene._player.position = NavigationServer3D.map_get_closest_point(scene._nav_map, from)
		var way := Vector3(solid.get_center().x - from.x, 0, solid.get_center().y - from.z).normalized()
		var stick := Vector2(way.dot(right), -way.dot(ahead))
		for frame in 90: scene.step_stick(stick, 1.0 / 30.0)
		var at: Vector3 = scene.player_position()
		assert_bool(solid.grow(0.2).has_point(Vector2(at.x, at.z))).override_failure_message("into %s at %s" % [solid, at]).is_false()
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
