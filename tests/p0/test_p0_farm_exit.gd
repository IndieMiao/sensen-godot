extends GdUnitTestSuite
## The farm's way out to the map (SGODOT-443, the user 11-07; q(298); 不知火舞's spec v1.2): its map-pin `Map` prompt
## shows from any distance; a tap on it walks there and the arrival goes to the map; the joystick or a tap elsewhere
## stops the walk; walked into the ring with the joystick it goes only once armed — never armed on coming into the farm,
## only after having been EXIT_ARM_M away (不知火舞 443 603fe5ea).

const STORE := "user://test_p0_farm_exit.json"
const P0Farm := preload("res://scenes/p0/p0_farm.gd")

var rt: P0Runtime

func _farm() -> Node3D:
	rt = auto_free(P0Runtime.new())
	rt.ui.quick_store = STORE
	rt.session.transport = func(_m, _p, _b, _c): pass
	add_child(rt)
	var stub := GDScript.new()
	stub.source_code = "extends \"res://scenes/p0/p0_farm.gd\"\nvar left := 0\nfunc _ready() -> void: pass\nfunc _exit_tree() -> void: pass\nfunc _process(_d) -> void: pass\nfunc leave_by_exit() -> void: left += 1\n"
	stub.reload()
	var farm: Node3D = load("res://scenes/p0/p0_farm.tscn").instantiate()
	farm.set_script(stub)
	add_child(farm)
	auto_free(farm)
	farm.rt = rt
	farm.bp = P0Garden.blueprint()
	farm.grid = BlueprintGrid.new(farm.bp)
	farm.cam = Camera3D.new()
	farm.add_child(farm.cam)
	farm.actor = P0Actor.new()
	farm.add_child(farm.actor)
	farm.actor.setup(farm.bp, farm.grid, farm.cam)
	farm._exit = P0Farm.EXIT_AT
	return farm

func _run(farm: Node3D, seconds: float) -> void:
	var t := 0.0
	while t < seconds and farm.left == 0:
		farm.actor.step(1.0 / 30.0)
		farm._exit_check()
		t += 1.0 / 30.0

func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORE))

func test_its_prompt_is_the_ringed_pin_and_map_and_shows_from_anywhere() -> void:
	var p := P0WorldPrompts.farm_exit(P0Farm.EXIT_ICON)
	assert_str(p.text).is_equal("Map")
	assert_str((p.icon as Texture2D).resource_path).is_equal("res://assets/p0/icons/exit_pin.svg")   # the pin in its ring (q(298))
	assert_int(P0WorldPrompts.show("exit", "", 40.0, p)).is_equal(P0WorldPrompts.Show.ICON)   # past RANGE, still there
	assert_int(P0WorldPrompts.show("exit", "exit", 1.0, p)).is_equal(P0WorldPrompts.Show.BAR)
	assert_int(P0WorldPrompts.show("workbench", "", 40.0, P0WorldPrompts.workbench())).is_equal(P0WorldPrompts.Show.NONE)   # others as before

func test_a_tap_walks_there_and_the_arrival_goes_to_the_map() -> void:
	var farm := _farm()
	farm.actor.teleport(farm._exit + Vector3(0, 0, -4))   # into the farm, 4 m off
	farm.walk_to_exit()
	assert_bool(farm._exit_walk).is_true()
	_run(farm, 6.0)
	assert_int(farm.left).is_equal(1)

func test_the_joystick_or_a_panel_stops_the_walk_where_it_is() -> void:
	var farm := _farm()
	farm.actor.teleport(farm._exit + Vector3(0, 0, -4))
	farm.walk_to_exit()
	for i in 10: farm.actor.step(1.0 / 30.0)
	farm.p0_joystick(Vector2(1, 0))
	assert_bool(farm._exit_walk).is_false()
	farm.p0_joystick(Vector2.ZERO)
	var at: Vector3 = farm.actor.position
	_run(farm, 2.0)
	assert_int(farm.left).is_equal(0)
	assert_float(farm.actor.position.distance_to(at)).is_less(0.3)   # stopped there, not still walking out

func test_landing_and_standing_still_never_leaves() -> void:
	var farm := _farm()
	var spawn: Vector3 = farm.bp.cell_to_world(farm.bp.anchor("spawn"))
	assert_float(P0FarmMaterials.flat(spawn, farm._exit)).is_greater(P0Farm.EXIT_ARM_M)   # 4.6 m: no two steps out (bot 389)
	farm.actor.teleport(spawn)   # back from the map
	_run(farm, 1.0)
	assert_int(farm.left).is_equal(0)

func test_from_the_landing_walking_into_the_ring_leaves_once() -> void:
	var farm := _farm()
	farm.actor.teleport(farm.bp.cell_to_world(farm.bp.anchor("spawn")))
	farm.actor.mover.set_target_position(farm._exit + Vector3(0.1, 0, 0))   # the walk there is the player's own
	_run(farm, 6.0)
	assert_int(farm.left).is_equal(1)
	for v in [Vector2(-1, 0), Vector2(0, 1), Vector2(1, 0)]:   # turning round in the ring: not again
		farm.actor.face(farm.actor.position + Vector3(v.x, 0, v.y))
		farm.actor.mover.set_target_position(farm.actor.position + Vector3(v.x, 0, v.y) * 0.2)
		for i in 6:
			farm.actor.step(1.0 / 30.0)
			farm._exit_check()
	assert_int(farm.left).is_equal(1)

func test_away_past_the_arming_distance_and_back_into_the_ring_leaves() -> void:
	var farm := _farm()
	farm.actor.teleport(farm._exit + Vector3(0, 0, -(P0Farm.EXIT_ARM_M + 0.3)))
	farm._exit_check()
	assert_bool(farm._exit_armed).is_true()
	farm.actor.mover.set_target_position(farm._exit + Vector3(0.1, 0, 0))
	_run(farm, 5.0)
	assert_int(farm.left).is_equal(1)
	var back := _farm()   # out of the farmhouse: not armed however it was
	back._exit_armed = true
	back.resume()
	assert_bool(back._exit_armed).is_false()

func test_the_exit_stands_on_the_farms_walk() -> void:
	var bp := P0Garden.blueprint()
	P0Garden.block_points(bp, P0Garden.fence_block_points(bp))   # the yard fence, as the farm blocks it
	var exit := P0Farm.EXIT_AT
	assert_bool(bp.is_walkable(bp.world_to_cell(exit))).is_true()
	for d in [Vector3(-0.6, 0, 0), Vector3(0.6, 0, 0), Vector3(0, 0, -0.6), Vector3(0, 0, 0.6)]:   # the whole ring on the walk
		assert_bool(bp.is_walkable(bp.world_to_cell(exit + d))).override_failure_message(str(d)).is_true()
	var grid := BlueprintGrid.new(bp)
	assert_bool(grid.path(bp.anchor("spawn"), bp.world_to_cell(exit)).is_empty()).is_false()

## 周瑜 on #860: the exit is one of the facilities whose strip opens nearest (its `Map` strip, spec v1.2 §3).
func test_beside_it_its_map_strip_opens() -> void:
	var farm := _farm()
	assert_str(FileAccess.get_file_as_string("res://scenes/p0/p0_farm.gd")).contains("exit_card()]")   # in _card_candidates
	var far := ["mailbox", farm._exit + Vector3(6, 0, -6), P0Farm.SIGN_NEAR]
	assert_str(P0Garden.pick_card([far, farm.exit_card()], farm._exit + Vector3(0.8, 0, 0), "")).is_equal("exit")
	assert_str(P0Garden.pick_card([far, farm.exit_card()], farm._exit + Vector3(4, 0, 0), "")).is_equal("")   # past its reach
