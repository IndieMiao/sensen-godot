extends GdUnitTestSuite
## SGODOT-411 (the user, 11-04; 不知火舞's spec 2026-11-04): while the guide has Pip on the farm he wanders by the starting
## beds — walkable cells in no one's way within TETHER of STAND (TETHER_BANG with his `!`), never on a bed — at about
## WALK_SPEED (his walk clip's own ground speed), stopping a while at each; the player near, a talk or a panel: he stands and turns to the player, and walks on
## (RESUME_S after a talk or a panel) once that is over. On the real farm's blueprint; the farm host is a stand-in.

const FarmGuide := preload("res://scenes/p0/p0_farm_guide.gd")
const DT := 1.0 / 30.0

func _host() -> Node3D:
	var src := GDScript.new()
	src.source_code = """extends Node3D
class Ui extends RefCounted:
	var talking := ""
	var modal := false
	func speaker() -> String: return talking
	func has_modal() -> bool: return modal
class Rt extends RefCounted:
	var ui := Ui.new()
var bp: FarmBlueprint
var grid: BlueprintGrid
var actor := Node3D.new()
var rt := Rt.new()
"""
	src.reload()
	var host: Node3D = src.new()
	host.bp = P0Garden.blueprint()
	host.grid = BlueprintGrid.new(host.bp)
	host.add_child(host.actor)
	add_child(auto_free(host))
	return host

func _pip(host: Node3D, seed := 7) -> Node3D:
	var g = FarmGuide.new()
	g.setup(host)
	host.add_child(g)
	g.rng.seed = seed
	g.pip_root = Node3D.new()
	g.pip_root.position = host.bp.cell_to_world(FarmGuide.STAND)
	g.add_child(g.pip_root)
	g._stop_left = 0.5
	g._last_stop = FarmGuide.STAND
	return g

func _run(g, seconds: float, info := {}) -> void:
	for i in int(seconds / DT): g._wander(info, DT)

func _far(host: Node3D) -> void:
	host.actor.position = host.bp.cell_to_world(host.bp.anchor("house"))   # the farmhouse: well away from the beds

func test_his_stops_are_off_the_beds_the_kept_paths_and_within_his_tether() -> void:
	var host := _host()
	var g = _pip(host)
	var cells: Array = g.stops(FarmGuide.TETHER)
	assert_int(cells.size()).is_greater(8)
	var beds := {}
	for id in P0Garden.max_plots(): beds[P0Garden.cell_of(id)] = true
	for c in cells:
		assert_bool(beds.has(c)).override_failure_message("%s is a bed" % c).is_false()
		assert_bool(host.grid.astar.is_point_solid(c)).is_false()
		assert_float(Vector2(c - FarmGuide.STAND).length()).is_less_equal(FarmGuide.TETHER)
		for r in P0Decor.yard().get("paths", []): assert_bool(P0Decor._rect(r).has_point(c)).is_false()
	var near: Array = g.stops(FarmGuide.TETHER_BANG)
	assert_int(near.size()).is_greater(0)
	for c in near:
		assert_bool(cells.has(c)).is_true()
		assert_float(Vector2(c - FarmGuide.STAND).length()).is_less_equal(FarmGuide.TETHER_BANG)

func test_he_strolls_from_stop_to_stop_never_onto_a_bed_at_a_walk() -> void:
	var host := _host()
	_far(host)
	var g = _pip(host)
	var allowed := {FarmGuide.STAND: true}
	for c in g.stops(FarmGuide.TETHER): allowed[c] = true
	var visited := {}
	var was: Vector3 = g.pip_root.position
	var fastest := 0.0
	for i in int(60.0 / DT):
		g._wander({}, DT)
		var at: Vector3 = g.pip_root.position
		fastest = maxf(fastest, P0FarmMaterials.flat(at, was) / DT)
		was = at
		var cell: Vector2i = host.bp.world_to_cell(at)
		assert_bool(allowed.has(cell)).override_failure_message("on %s" % cell).is_true()
		if g._route.is_empty(): visited[cell] = true
	assert_int(visited.size()).is_greater_equal(4)   # 60 s: stops of 3–6 s and the walks between
	assert_float(fastest).is_less_equal(FarmGuide.WALK_SPEED * 1.01)

## With his `!` he keeps within two cells — and still strolls: the shortest hop is the tether then (the spec's 1.5 m is
## over a 2-cell tether's 1.3 m; a first cut stood him at STAND for good).
func test_with_his_bang_he_keeps_within_two_cells_and_still_strolls() -> void:
	var host := _host()
	_far(host)
	var g = _pip(host)
	var visited := {}
	for i in int(40.0 / DT):
		g._wander({bang = true}, DT)
		var cell: Vector2i = host.bp.world_to_cell(g.pip_root.position)
		assert_float(Vector2(cell - FarmGuide.STAND).length()).is_less_equal(FarmGuide.TETHER_BANG)
		if g._route.is_empty(): visited[cell] = true
	assert_int(visited.size()).is_greater_equal(3)

## A talk stops him where he is — mid-walk too — turned to the player; RESUME_S after it closes he walks on.
func test_a_talk_stops_him_turned_to_the_player_and_he_walks_on_after_it() -> void:
	var host := _host()
	_far(host)
	var g = _pip(host)
	while g._route.is_empty(): g._wander({}, DT)   # off on a walk
	g._wander({}, DT)
	host.rt.ui.talking = FarmGuide.PIP
	g._wander({}, DT)
	var stood: Vector3 = g.pip_root.position
	_run(g, 1.0)
	assert_vector(g.pip_root.position).is_equal(stood)
	assert_bool(g._route.is_empty()).is_true()
	var off: Vector3 = host.actor.position - g.pip_root.position
	assert_float(absf(angle_difference(g.pip_root.rotation.y, atan2(-off.x, -off.z)))).is_less(0.05)   # facing the player
	host.rt.ui.talking = ""
	_run(g, FarmGuide.RESUME_S - 0.2)
	assert_vector(g.pip_root.position).is_equal(stood)   # still standing a moment
	_run(g, 8.0)
	assert_bool(g.pip_root.position.is_equal_approx(stood)).is_false()   # and on his way again

func test_a_panel_stops_him_too() -> void:
	var host := _host()
	_far(host)
	var g = _pip(host)
	while g._route.is_empty(): g._wander({}, DT)
	host.rt.ui.modal = true
	g._wander({}, DT)
	var stood: Vector3 = g.pip_root.position
	_run(g, 2.0)
	assert_vector(g.pip_root.position).is_equal(stood)

## The player within NEAR_M: he stands and turns to them; he walks on only past AWAY_M (no to and fro at the edge).
func test_the_player_near_stops_him_until_past_the_hysteresis() -> void:
	var host := _host()
	_far(host)
	var g = _pip(host)
	while g._route.is_empty(): g._wander({}, DT)
	host.actor.position = g.pip_root.position + Vector3(2.0, 0, 0)
	g._wander({}, DT)
	var stood: Vector3 = g.pip_root.position
	_run(g, 0.4)
	assert_vector(g.pip_root.position).is_equal(stood)
	var off: Vector3 = host.actor.position - g.pip_root.position
	assert_float(absf(angle_difference(g.pip_root.rotation.y, atan2(-off.x, -off.z)))).is_less(0.05)   # within 0.25 s
	host.actor.position = stood + Vector3(3.0, 0, 0)   # out of NEAR_M, not past AWAY_M
	_run(g, 6.0)
	assert_vector(g.pip_root.position).is_equal(stood)
	_far(host)
	_run(g, 8.0)
	assert_bool(g.pip_root.position.is_equal_approx(stood)).is_false()

## Only while the guide has him here (the user's A): the guide over with the player still on the farm (the model kept
## till leave()), he stops mid-walk where he is and stands, the player well away (亚瑟 on #739).
func test_the_guide_over_he_stops_where_he_is() -> void:
	var host := _host()
	_far(host)
	var g = _pip(host)
	while g._route.is_empty(): g._stroll({"here": true}, DT)
	g._stroll({"here": true}, DT)
	var walked_from: Vector3 = g.pip_root.position
	g._stroll({"here": true}, DT)
	assert_bool(g.pip_root.position.is_equal_approx(walked_from)).is_false()   # walking while the guide has him
	var stood: Vector3 = g.pip_root.position
	for i in int(20.0 / DT): g._stroll({}, DT)   # P0Guide.pip: here false once the guide ends
	assert_vector(g.pip_root.position).is_equal(stood)
	assert_bool(g._route.is_empty()).is_true()

## He turns smoothly: a half turn takes TURN_S, never a snap.
func test_he_turns_at_most_a_half_turn_per_quarter_second() -> void:
	var host := _host()
	var g = _pip(host)
	g.pip_root.rotation.y = 0.0
	host.actor.position = g.pip_root.position + Vector3(0, 0, 2.0)   # straight behind him
	g._wander({}, DT)
	assert_float(absf(g.pip_root.rotation.y)).is_less_equal(PI / FarmGuide.TURN_S * DT + 0.0001)
