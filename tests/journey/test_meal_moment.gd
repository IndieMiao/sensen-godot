extends GdUnitTestSuite

func after_test() -> void:
	# Panel rebuilds free the previous controls at the end of the frame.
	for frame in 3: await get_tree().process_frame

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0}, "wallet": 40, "inventory": {"produce": {"R": 2, "L": 2, "C": 2, "H": 2}, "dishes": {"tea": 1, "salad": 1}},
		"engineering": {"reserved": {}}, "journey": {"version": 1, "facts": ["met_bistro", "shared_meal"],
		"unlocks": ["bistro", "kitchen", "tea"], "completed": [], "wood": 0, "materials": {},
		"exploration": {"round": 0, "collected": []}, "opportunities": {"bistro": {"sequence": 4, "variant": 1}}}}

func test_failed_meal_does_not_present_success_or_change_food() -> void:
	var initial := _state()
	var transport := FakeTransport.new([{"status": 422, "json": {"code": "INSUFFICIENT_ITEMS"}}])
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = initial
	session.version = 1
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "bistro"
	panel.target = "table"
	panel.setup(session)
	add_child(panel)
	await get_tree().process_frame
	var results := []
	panel.world_action_completed.connect(func(id): results.append(id))
	panel.meal_served.connect(func(id): results.append(id))
	await panel._deliver_offer("bistro", JourneyProgress.offer(initial, "bistro"))
	assert_array(results).is_empty()
	assert_that(session.state).is_equal(initial)
	assert_str(transport.last_body().type).is_equal("fulfill_opportunity")

func test_accepted_tea_uses_delivered_recipe_even_after_request_rotates() -> void:
	var initial := _state()
	var served := initial.duplicate(true)
	served.inventory.dishes.tea = 0
	served.wallet += 22
	served.journey.opportunities.bistro = {"sequence": 5, "variant": 0}
	var transport := FakeTransport.new([{"status": 200, "json": {"version": 2, "state": served}}])
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = initial
	session.version = 1
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "bistro"
	panel.target = "table"
	panel.setup(session)
	add_child(panel)
	await get_tree().process_frame
	var results := []
	panel.world_action_completed.connect(func(id): results.append(id))
	panel.meal_served.connect(func(id): results.append(id))
	await panel._deliver_offer("bistro", JourneyProgress.offer(initial, "bistro"))
	assert_array(results).is_equal(["table", "tea"])
	assert_str(panel.message.text).is_equal("Tea served. +22 coins")
	assert_int(session.state.inventory.dishes.tea).is_equal(0)

func test_resident_route_pauses_and_replans_after_player_input_without_teleporting() -> void:
	var actor := auto_free(Node3D.new()) as Node3D
	actor.position = Vector3(0, 0.04, 0)
	var moment := ResidentMoment.new(actor, Vector3.ZERO)
	var blueprint := FarmBlueprint.new()
	blueprint.grid = Vector2i(10, 10)
	blueprint.cell_m = 1.0
	blueprint.masks = {"walkable": []}
	for i in 10: blueprint.masks.walkable.append("1111111111")
	blueprint.anchors = {"spawn": Vector2i.ZERO}
	var routes := []
	var route := func(destination: Vector3):
		var movement := PlayerMover.new(blueprint, BlueprintGrid.new(blueprint))
		movement.position = Vector3(actor.position.x, 0, actor.position.z)
		routes.append(movement.position)
		return movement if movement.set_target_position(destination) else null
	moment.start(Vector3(2, 0, -2), Vector3(3, 0, -2))
	moment.step(0.1, false, route)
	var interrupted := actor.position
	assert_float(interrupted.distance_to(moment.home)).is_less_equal(0.3751)
	moment.step(1.0, true, route)
	assert_that(actor.position).is_equal(interrupted)
	moment.step(0.1, false, route)
	assert_int(routes.size()).is_equal(2)
	assert_float(actor.position.distance_to(interrupted)).is_less_equal(0.3751)
	for i in 100: moment.step(0.1, false, route)
	assert_str(moment.phase).is_equal("idle")
	assert_that(actor.position).is_equal(moment.home)

func test_expired_interrupted_response_returns_instead_of_replaying_the_celebration() -> void:
	var actor := auto_free(Node3D.new()) as Node3D
	var moment := ResidentMoment.new(actor, Vector3.ZERO)
	moment.start(Vector3(2, 0, -2), Vector3.ZERO)
	moment.phase = "reacting"
	moment.step(1.0, true, func(_point): return null)
	moment.finish()
	assert_str(moment.phase).is_equal("returning")
	moment.step(1.0, true, func(_point): return null)
	assert_str(moment.phase).is_equal("returning")
	assert_that(actor.position).is_equal(moment.home)

func test_terrace_meal_signals_only_after_accepted_facility_command() -> void:
	for accepted in [false, true]:
		var initial := _state()
		initial.journey.facts.append_array(["project_terrace_0", "project_terrace_1"])
		initial.journey.facility_uses = {"terrace": 3}
		var served := initial.duplicate(true)
		served.inventory.dishes.tea = 0
		served.wallet += 24
		served.journey.facility_uses.terrace = 4
		var response := {"status": 200, "json": {"version": 2, "state": served}} if accepted else {"status": 422, "json": {"code": "INSUFFICIENT_ITEMS"}}
		var transport := FakeTransport.new([response])
		var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
		session.state = initial
		session.version = 1
		var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
		panel.place_id = "bistro"
		panel.target = "project_terrace"
		panel.setup(session)
		add_child(panel)
		await get_tree().process_frame
		var results := []
		panel.world_action_completed.connect(func(id): results.append(id))
		panel.terrace_served.connect(func(dish): results.append(dish))
		await panel._use_facility("terrace", "tea")
		assert_array(results).is_equal(["project_terrace", "tea"] if accepted else [])
		assert_that(session.state).is_equal(served if accepted else initial)
		assert_str(transport.last_body().type).is_equal("use_journey_facility")
		assert_float(transport.last_body().payload.sequence).is_equal(3.0)
		await get_tree().process_frame

func test_activity_refuses_a_new_blocker_and_replans_from_actual_position() -> void:
	var actor := auto_free(Node3D.new()) as Node3D
	actor.position = Vector3(0, 0.04, 0)
	var moment := ResidentMoment.new(actor, Vector3.ZERO)
	var blueprint := FarmBlueprint.new()
	blueprint.grid = Vector2i(10, 10)
	blueprint.cell_m = 1.0
	blueprint.masks = {"walkable": []}
	for i in 10: blueprint.masks.walkable.append("1111111111")
	blueprint.anchors = {"spawn": Vector2i.ZERO}
	var starts := []
	var route := func(destination: Vector3):
		var movement := PlayerMover.new(blueprint, BlueprintGrid.new(blueprint))
		movement.position = Vector3(actor.position.x, 0, actor.position.z)
		starts.append(movement.position)
		return movement if movement.set_target_position(destination) else null
	moment.start(Vector3(2, 0, -2), Vector3.ZERO, "labour_water", 4.0)
	moment.step(0.1, false, route, func(_from, _to): return false)
	assert_that(actor.position).is_equal(moment.home)
	assert_that(moment.movement).is_null()
	for i in 7: moment.step(0.1, false, route, func(_from, _to): return true)
	assert_that(starts[0]).is_equal(starts[1])
	for i in 100: moment.step(0.1, false, route)
	assert_str(moment.phase).is_equal("idle")
	assert_that(actor.position).is_equal(moment.home)

func test_finished_terrace_opens_table_access_while_chairs_remain_solid() -> void:
	var scene := auto_free(JourneyPlace.new()) as JourneyPlace
	scene.place_id = "bistro"
	scene.session = FarmSession.new(ApiClient.new())
	scene.session.state = _state()
	scene._build_navigation()
	var terrace_side := Vector3(3.55, 0, -0.65) - JourneyPlace.NAV_ORIGIN
	assert_bool(scene.mover.set_target_position(terrace_side)).is_false()
	scene.session.state.journey.facts.append_array(["project_terrace_0", "project_terrace_1"])
	scene._build_navigation()
	assert_bool(scene.mover.set_target_position(terrace_side)).is_true()
	var start := scene.mover.position
	for point in scene.mover.remaining_path():
		assert_bool(scene.mover.grid.segment_walkable(start, point)).is_true()
		start = point
	for z in [0.3, -1.65]:
		for x in [1.19, 2.0, 2.81]:
			var furniture := Vector3(x, 0, z) - JourneyPlace.NAV_ORIGIN
			assert_bool(scene.nav.is_walkable(scene.nav.world_to_cell(furniture))).is_false()
