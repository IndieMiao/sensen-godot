extends GdUnitTestSuite

const Scene = preload("res://scenes/mine/mine.gd")
const Layout = preload("res://modules/mining/mine_layout.gd")
const Farm = preload("res://scenes/farm/farm.gd")

func after_test() -> void:
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame

func _state(number := 1) -> Dictionary:
	return {"inventory": {"produce": {}, "dishes": {}}, "journey": {"wood": 0, "materials": {"stone": 0, "copper_ore": 0, "rock_salt": 0}},
		"mine": {"version": 1, "run": 0, "floor": number, "deepest_floor": maxi(1, number), "cleared_floors": [], "broken": {}, "elevator_unlocked": false}}

func _completed_state(number := 0) -> Dictionary:
	var state := _state(number)
	state.mine.run = 2
	state.mine.deepest_floor = 5
	state.mine.cleared_floors = JSON.parse_string("[1,5,2,3,4]")
	state.mine.elevator_unlocked = true
	for floor_number in range(1, 6):
		state.mine.broken[str(floor_number)] = Layout.rocks(floor_number).map(func(rock): return rock.id)
	state.journey.materials = {"stone": 88, "copper_ore": 29, "rock_salt": 18}
	state.inventory = {"produce": {"R": 3}, "dishes": {"vegetable_soup": 2}}
	return state

func _restarted_state(state: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	next.mine = _state(0).mine
	next.mine.run = int(state.mine.run) + 1
	next.mine.elevator_unlocked = state.mine.elevator_unlocked
	return next

func _session(transport: FakeTransport, state: Dictionary) -> FarmSession:
	var result := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	result.client.token = "test"
	result.farm_id = "mine-test"
	result.version = 0
	result.state = state
	return result

func _scene(transport: FakeTransport, state: Dictionary) -> Node3D:
	return await _scene_with_session(_session(transport, state))

func _scene_with_session(session: FarmSession) -> Node3D:
	var scene := auto_free(Scene.new()) as Node3D
	scene.setup({"session": session})
	add_child(scene)
	for frame in 3: await get_tree().process_frame
	scene.set_process(false)
	return scene

func _pan_to(mine: Node3D, world: Vector3) -> void:
	# A close view intentionally cannot contain every target at once.
	mine.camera_pan.drag(mine.cam, mine.cam.unproject_position(world), mine.world_area().get_center())
	mine.camera_pan.velocity = Vector3.ZERO
	mine._update_camera()

func _pick_box(mine: Node3D, position: Vector3, size := Vector3.ONE) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	model.mesh = mesh
	mine.add_child(model)
	model.global_position = position
	return model

func test_all_floor_rocks_have_reachable_approaches_and_distinct_layouts() -> void:
	var previous: Array = []
	for number in range(1, 6):
		var nav := Layout.navigation(number, [])
		var mover := PlayerMover.new(nav, BlueprintGrid.new(nav))
		var nodes := Layout.rocks(number)
		assert_int(nodes.size()).is_equal(0 if number == 5 else 6)
		for rock in nodes:
			var approach := Layout.approach(mover, rock.position)
			assert_bool(mover.grid.point_path(mover.position, approach).is_empty()).is_false()
			assert_bool(approach.distance_to(rock.position) < 1.6).is_true()
			mover.position = approach
		if not previous.is_empty(): assert_that(nodes).is_not_equal(previous)
		previous = nodes

func test_shipped_farms_reach_the_exact_mine_approach_from_spawn() -> void:
	# 自由格子种田起，所有农场共用同一份地面布局，可达性只需验证一次。
	var nav: FarmBlueprint = FarmPlot.blueprint_for()
	var mover := PlayerMover.new(nav, BlueprintGrid.new(nav))
	assert_bool(nav.is_walkable(nav.world_to_cell(Farm.mine_approach()))).override_failure_message("mine approach is blocked").is_true()
	assert_bool(mover.set_target_position(Farm.mine_approach())).override_failure_message("mine path is unreachable").is_true()
	mover.step(100.0)
	assert_vector(mover.position).is_equal(Farm.mine_approach())
	assert_bool(mover.is_moving()).is_false()

func test_reentry_uses_saved_floor_and_broken_rocks_without_issuing_a_command() -> void:
	var transport := FakeTransport.new([])
	var state := _state(3)
	state.mine.broken = {"3": ["rock_1", "rock_4"]}
	var mine := await _scene(transport, state)
	assert_int(mine.current_floor()).is_equal(3)
	assert_bool(mine.targets.has("rock_1")).is_false()
	assert_bool(mine.targets.has("rock_2")).is_true()
	assert_bool(mine.targets.has("down")).is_false()
	assert_bool(mine.targets.has("elevator")).is_false()
	assert_int(transport.requests.size()).is_equal(0)

func test_locked_elevator_has_feedback_and_never_sends_a_command() -> void:
	var transport := FakeTransport.new([])
	var mine := await _scene(transport, _state())
	_pan_to(mine, Layout.ELEVATOR + Vector3(0.8, 0.68, 0.4))
	var point: Vector2 = mine.cam.unproject_position(Layout.ELEVATOR + Vector3(0.8, 0.68, 0.4))
	mine._tap_scene(point)
	assert_str(mine.feedback.text).is_equal(L10n.text("Clear floor 5 to unlock the elevator"))
	assert_str(mine.pending_target).is_empty()
	assert_int(transport.requests.size()).is_equal(0)
	assert_bool(mine.targets.has("down")).is_false()
	assert_object(mine.objects.get_node_or_null("DownLadder")).is_null()

func test_navigation_models_are_pickable_across_their_visible_bodies() -> void:
	var mine := await _scene(FakeTransport.new([]), _completed_state(1))
	var samples := {
		"up": [Layout.UP + Vector3(0, 0.07, 0.3), Layout.UP + Vector3(0, 0.9, -0.3)],
		"down": [Layout.DOWN + Vector3(0, 0.07, 0.3), Layout.DOWN + Vector3(0, 0.16, -0.3)],
		"elevator": [Layout.ELEVATOR + Vector3(0, 1.68, -0.45),
			Layout.ELEVATOR + Vector3(0.8, 0.68, 0.4), Layout.ELEVATOR + Vector3(0, 0.12, 0.6)]}
	for zoom in [0.9, 1.0]:
		mine.camera_pan._log_zoom = log(zoom)
		mine._update_camera()
		for id in samples:
			assert_bool(mine.targets[id].button.is_visible_in_tree()).is_false()
			for world in samples[id]:
				_pan_to(mine, world)
				var point: Vector2 = mine.cam.unproject_position(world)
				assert_bool(mine.world_area().has_point(point)).override_failure_message("Model sample outside play area: %s %s" % [id, world]).is_true()
				assert_str(mine._pick_target(point)).override_failure_message("Model sample is not selectable: %s %s" % [id, world]).is_equal(id)

func test_all_target_icons_stay_hidden_after_camera_and_activity_changes() -> void:
	var transport := FakeTransport.new([])
	var state := _state()
	state.mine.elevator_unlocked = true
	state.mine.broken = {"1": ["rock_1"]}
	var mine := await _scene(transport, state)
	assert_bool(mine.targets.has("rock_2")).is_true()
	for activity in ["idle", "busy", "digging", "idle"]:
		mine.busy = activity == "busy"
		mine._dig_target = "rock_2" if activity == "digging" else ""
		for zoom in [0.9, 1.45, 1.0]:
			mine.camera_pan._log_zoom = log(zoom)
			mine.camera_pan.offset = Vector3(0.15, 0, -0.1)
			mine._update_camera()
			mine._sync_markers()
			for id in mine.targets:
				var button: Button = mine.targets[id].button
				assert_bool(button.is_visible_in_tree()).is_false()
				assert_object(button.icon).is_null()
				assert_bool(mine.targets[id].marker_visible).is_false()
				if activity != "idle":
					var point: Vector2 = mine.cam.unproject_position(mine.targets[id].body)
					mine._tap_scene(point)
					assert_str(mine.pending_target).is_empty()
	assert_int(transport.requests.size()).is_equal(0)
	mine.session.state.mine.floor = 2
	mine.session.state.mine.cleared_floors = [2]
	mine.session.state.mine.broken["2"] = Layout.rocks(2).map(func(rock): return rock.id)
	mine.session.state_changed.emit(mine.session.state, 1)
	for frame in 3: await get_tree().process_frame
	for id in ["up", "down"]:
		assert_bool(mine.targets[id].button.is_visible_in_tree()).is_false()
		assert_object(mine.targets[id].button.icon).is_null()
	mine.session.state.mine.floor = 3
	mine.session.state_changed.emit(mine.session.state, 2)
	for frame in 3: await get_tree().process_frame
	assert_bool(mine.targets.has("rock_1")).is_true()
	for target in mine.targets.values():
		assert_bool(target.button.is_visible_in_tree()).is_false()
		assert_object(target.button.icon).is_null()
		assert_bool(target.marker_visible).is_false()

func test_rock_models_are_pickable_at_their_transformed_body_centers() -> void:
	var mine := await _scene(FakeTransport.new([]), _state())
	for zoom in [0.9, 1.0]:
		mine.camera_pan._log_zoom = log(zoom)
		mine._update_camera()
		for id in mine.targets:
			if not id.begins_with("rock_"): continue
			var model: MeshInstance3D = mine.targets[id].model
			assert_object(model).is_equal(mine.objects.get_node(id + "/Rock"))
			var world := model.global_transform * model.get_aabb().get_center()
			_pan_to(mine, world)
			var point: Vector2 = mine.cam.unproject_position(world)
			assert_bool(mine.world_area().has_point(point)).override_failure_message("Rock body outside play area: " + id).is_true()
			assert_str(mine._pick_target(point)).override_failure_message("Rock body is not selectable: " + id).is_equal(id)

func test_overlapping_models_pick_the_nearest_ray_hit_regardless_of_target_order() -> void:
	var mine := await _scene(FakeTransport.new([]), _state())
	var point: Vector2 = mine.world_area().get_center()
	for id in mine.targets:
		mine.targets[id].button.disabled = id not in ["rock_1", "rock_2"]
	var first := _pick_box(mine, mine.cam.project_position(point, 10.0), Vector3.ONE * 0.4)
	var second := _pick_box(mine, mine.cam.project_position(point, 8.0), Vector3.ONE * 0.4)
	second.rotation = Vector3(0.1, 0.5, -0.2)
	second.scale = Vector3(0.8, 1.2, 1.5)
	mine.targets.rock_1.model = first
	mine.targets.rock_2.model = second
	assert_bool(mine._model_pick_rect(first).has_point(point)).is_true()
	assert_bool(mine._model_pick_rect(second).has_point(point)).is_true()
	assert_str(mine._pick_target(point)).is_equal("rock_2")
	first.global_position = mine.cam.project_position(point, 6.0)
	assert_str(mine._pick_target(point)).is_equal("rock_1")

func test_actual_model_hit_takes_priority_over_another_models_touch_padding() -> void:
	var mine := await _scene(FakeTransport.new([]), _state())
	var point: Vector2 = mine.world_area().get_center()
	for id in mine.targets:
		mine.targets[id].button.disabled = id not in ["rock_1", "rock_2"]
	var padded := _pick_box(mine, mine.cam.project_position(point + Vector2(16, 0), 8.0), Vector3.ONE * 0.05)
	var hit := _pick_box(mine, mine.cam.project_position(point, 10.0), Vector3.ONE * 0.05)
	mine.targets.rock_1.model = padded
	mine.targets.rock_2.model = hit
	assert_bool(mine._model_pick_rect(padded).has_point(point)).is_true()
	assert_str(mine._pick_target(point)).is_equal("rock_2")
	mine.targets.rock_2.button.disabled = true
	assert_str(mine._pick_target(point)).is_equal("rock_1")

func test_confirmed_stairs_and_elevator_arrivals_clear_walking_feedback() -> void:
	for route in [
		{"from": 1, "to": 5, "target": "elevator", "command": "use_mine_elevator"},
		{"from": 5, "to": 1, "target": "elevator", "command": "use_mine_elevator"},
		{"from": 1, "to": 2, "target": "down", "command": "descend_mine"},
		{"from": 2, "to": 1, "target": "up", "command": "ascend_mine"}]:
		var state := _state(route.from)
		state.mine.cleared_floors = [1]
		state.mine.broken = {"1": Layout.rocks(1).map(func(rock): return rock.id)}
		state.mine.elevator_unlocked = true
		var next := state.duplicate(true)
		next.mine.floor = route.to
		next.mine.deepest_floor = 5
		var transport := FakeTransport.new([{"status": 200, "json": {"state": next, "version": 1}}])
		var mine := await _scene(transport, state)
		_pan_to(mine, mine.targets[route.target].body)
		var point: Vector2 = mine.cam.unproject_position(mine.targets[route.target].body)
		mine._tap_scene(point)
		assert_str(mine.pending_target).is_equal(route.target)
		assert_str(mine.feedback.text).is_equal(L10n.text("Walking..."))
		assert_int(transport.requests.size()).is_equal(0)
		mine._process(100.0)
		for frame in 3: await get_tree().process_frame
		assert_int(transport.requests.size()).is_equal(1)
		assert_str(transport.last_body().type).is_equal(route.command)
		assert_int(mine.current_floor()).is_equal(route.to)
		assert_bool(mine.mover.is_moving()).is_false()
		assert_bool(mine.busy).is_false()
		assert_str(mine.pending_target).is_empty()
		assert_str(mine.feedback.text).is_empty()

func test_rejected_floor_navigation_keeps_error_feedback() -> void:
	var transport := FakeTransport.new([{"status": 422, "json": {"code": "NOT_AVAILABLE"}}])
	var mine := await _scene(transport, _state(2))
	mine.select_target("up")
	assert_str(mine.feedback.text).is_equal(L10n.text("Walking..."))
	mine._process(100.0)
	for frame in 3: await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(1)
	assert_int(mine.current_floor()).is_equal(2)
	assert_bool(mine.mover.is_moving()).is_false()
	assert_bool(mine.busy).is_false()
	assert_str(mine.feedback.text).is_equal(Scene.error_text("NOT_AVAILABLE"))

func test_clicking_rock_walks_then_digs_and_adopts_server_drop_once() -> void:
	var state := _state()
	var next := state.duplicate(true)
	next.mine.broken = {"1": ["rock_1"]}
	next.mine.last_drop = {"floor": 1, "node_id": "rock_1", "materials": {"stone": 1, "copper_ore": 1}}
	next.journey.materials = {"stone": 1, "copper_ore": 1, "rock_salt": 0}
	var transport := FakeTransport.new([{"status": 200, "json": {"state": next, "version": 1}}])
	var mine := await _scene(transport, state)
	assert_bool(mine.targets.rock_1.button.is_visible_in_tree()).is_false()
	assert_object(mine.targets.rock_1.button.icon).is_null()
	var model: MeshInstance3D = mine.targets.rock_1.model
	assert_object(model).is_equal(mine.objects.get_node("rock_1/Rock"))
	_pan_to(mine, model.global_transform * model.get_aabb().get_center())
	var point: Vector2 = mine.cam.unproject_position(model.global_transform * model.get_aabb().get_center())
	assert_str(mine._pick_target(point)).is_equal("rock_1")
	mine._tap_scene(point)
	assert_str(mine.pending_target).is_equal("rock_1")
	assert_bool(mine.mover.is_moving()).is_true()
	assert_int(transport.requests.size()).is_equal(0)
	for frame in 220:
		mine._process(0.05)
		await get_tree().process_frame
		if transport.requests.size() > 0: break
	assert_int(transport.requests.size()).is_equal(1)
	assert_int(int(transport.requests[0].body.payload.run)).is_equal(0)
	assert_int(int(transport.requests[0].body.payload.floor)).is_equal(1)
	assert_str(transport.requests[0].body.payload.node_id).is_equal("rock_1")
	assert_str(transport.requests[0].body.type).is_equal("mine_rock")
	assert_bool(mine.targets.has("rock_1")).is_false()
	assert_int(mine.session.state.journey.materials.copper_ore).is_equal(1)
	assert_str(mine.feedback.text).contains(L10n.format_text("+%d %s", [1, L10n.item_name("stone")]))
	assert_str(mine.feedback.text).contains(L10n.format_text("+%d %s", [1, L10n.item_name("copper_ore")]))
	mine.select_target("rock_1")
	assert_int(transport.requests.size()).is_equal(1)

func test_unconfirmed_mining_reply_retains_rock_and_blocks_more_commands() -> void:
	var transport := FakeTransport.new([{"status": 504, "json": {}}])
	var mine := await _scene(transport, _state())
	await mine._mine_rock("rock_1")
	assert_bool(mine.session.has_unconfirmed_command()).is_true()
	assert_bool(mine.targets.has("rock_1")).is_true()
	assert_bool(mine.reconnect.visible).is_true()
	assert_bool(mine.primary.disabled).is_true()
	mine.select_target("rock_2")
	assert_str(mine.pending_target).is_empty()
	assert_int(transport.requests.size()).is_equal(1)

func test_fully_cleared_reentry_starts_one_new_expedition_and_preserves_inventory_and_elevator() -> void:
	var state := _completed_state()
	var restarted := _restarted_state(state)
	var entered := restarted.duplicate(true)
	entered.mine.floor = 1
	var transport := FakeTransport.new([
		{"status": 200, "json": {"state": restarted, "version": 1}},
		{"status": 200, "json": {"state": entered, "version": 2}}])
	var mine := await _scene(transport, state)
	assert_int(transport.requests.size()).is_equal(2)
	assert_int(int(transport.requests[0].body.payload.run)).is_equal(2)
	assert_int(transport.requests[0].body.payload.size()).is_equal(1)
	assert_str(transport.requests[0].body.type).is_equal("restart_mine")
	assert_int(int(transport.requests[1].body.payload.run)).is_equal(3)
	assert_int(transport.requests[1].body.payload.size()).is_equal(1)
	assert_str(transport.requests[1].body.type).is_equal("enter_mine")
	assert_int(mine.current_floor()).is_equal(1)
	assert_int(int(mine.session.state.mine.run)).is_equal(3)
	assert_bool(mine.session.state.mine.elevator_unlocked).is_true()
	assert_that(mine.session.state.journey.materials).is_equal(state.journey.materials)
	assert_that(mine.session.state.inventory).is_equal(state.inventory)
	for rock in Layout.rocks(1): assert_bool(mine.targets.has(rock.id)).is_true()
	assert_bool(mine.targets.has("up")).is_true()
	assert_bool(mine.targets.has("elevator")).is_true()
	assert_bool(mine._can_act()).is_true()
	assert_bool(mine.restart.visible).is_false()
	await mine._enter()
	assert_int(transport.requests.size()).is_equal(2)

func test_partial_outside_expeditions_resume_without_discarding_unmined_rocks() -> void:
	for cleared_floors in [[], [1], [5], [1, 5]]:
		var state := _state(0)
		state.mine.run = 2
		state.mine.elevator_unlocked = true
		state.mine.cleared_floors = cleared_floors
		state.mine.broken = {"1": ["rock_1", "rock_4"]}
		for floor_number in cleared_floors:
			state.mine.broken[str(floor_number)] = Layout.rocks(floor_number).map(func(rock): return rock.id)
		var entered := state.duplicate(true)
		entered.mine.floor = 1
		var transport := FakeTransport.new([{"status": 200, "json": {"state": entered, "version": 1}}])
		var mine := await _scene(transport, state)
		assert_int(transport.requests.size()).is_equal(1)
		assert_str(transport.last_body().type).is_equal("enter_mine")
		assert_int(int(transport.last_body().payload.run)).is_equal(2)
		assert_int(mine.current_floor()).is_equal(1)
		assert_int(int(mine.session.state.mine.run)).is_equal(2)
		assert_that(mine.session.state.mine.broken).is_equal(state.mine.broken)
		assert_that(mine.session.state.mine.cleared_floors).is_equal(cleared_floors)
		assert_bool(mine.targets.has("rock_1")).is_false()
		assert_bool(mine.targets.has("rock_2")).is_equal(not cleared_floors.has(1))
		assert_bool(mine.targets.has("down")).is_equal(cleared_floors.has(1))
		assert_bool(mine._can_act()).is_true()
		assert_bool(mine.fully_cleared()).is_false()
		assert_bool(mine.restart.visible).is_equal(cleared_floors.has(5))

func test_explicit_restart_from_first_floor_leaves_then_restarts_and_enters() -> void:
	var state := _completed_state(1)
	state.mine.cleared_floors = [5]
	state.mine.broken = {"1": ["rock_1"], "5": Layout.rocks(5).map(func(rock): return rock.id)}
	var outside := state.duplicate(true)
	outside.mine.floor = 0
	var restarted := _restarted_state(state)
	var entered := restarted.duplicate(true)
	entered.mine.floor = 1
	var transport := FakeTransport.new([
		{"status": 200, "json": {"state": outside, "version": 1}},
		{"status": 200, "json": {"state": restarted, "version": 2}},
		{"status": 200, "json": {"state": entered, "version": 3}}])
	var mine := await _scene(transport, state)
	assert_int(transport.requests.size()).is_equal(0)
	assert_bool(mine.restart.visible).is_true()
	assert_str(mine.restart.text).is_equal(L10n.text("Start new expedition"))
	assert_bool(mine.restart.get_global_rect().position.y >= mine.primary.get_global_rect().end.y).is_true()
	await mine._restart()
	for frame in 3: await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(3)
	assert_str(transport.requests[0].body.type).is_equal("leave_mine")
	assert_int(transport.requests[0].body.payload.size()).is_equal(2)
	assert_int(int(transport.requests[0].body.payload.run)).is_equal(2)
	assert_int(int(transport.requests[0].body.payload.floor)).is_equal(1)
	assert_str(transport.requests[1].body.type).is_equal("restart_mine")
	assert_int(transport.requests[1].body.payload.size()).is_equal(1)
	assert_int(int(transport.requests[1].body.payload.run)).is_equal(2)
	assert_str(transport.requests[2].body.type).is_equal("enter_mine")
	assert_int(transport.requests[2].body.payload.size()).is_equal(1)
	assert_int(int(transport.requests[2].body.payload.run)).is_equal(3)
	assert_int(mine.current_floor()).is_equal(1)
	assert_bool(mine.targets.has("rock_1")).is_true()
	assert_bool(mine.session.state.mine.elevator_unlocked).is_true()
	assert_that(mine.session.state.journey.materials).is_equal(state.journey.materials)
	assert_that(mine.session.state.inventory).is_equal(state.inventory)

func test_rejected_automatic_restart_keeps_the_run_and_does_not_enter() -> void:
	var state := _completed_state()
	var transport := FakeTransport.new([{"status": 422, "json": {"code": "NOT_AVAILABLE"}}])
	var mine := await _scene(transport, state)
	assert_int(transport.requests.size()).is_equal(1)
	assert_str(transport.last_body().type).is_equal("restart_mine")
	assert_that(mine.session.state).is_equal(state)
	assert_int(mine.current_floor()).is_equal(0)
	assert_bool(mine.busy).is_false()
	assert_bool(mine.primary.disabled).is_false()
	assert_str(mine.feedback.text).is_equal(Scene.error_text("NOT_AVAILABLE"))

func test_lost_restart_reply_replays_the_same_command_before_entering_the_new_run() -> void:
	var state := _completed_state()
	var restarted := _restarted_state(state)
	var entered := restarted.duplicate(true)
	entered.mine.floor = 1
	var transport := FakeTransport.new([
		{"status": 504, "json": {}},
		{"status": 200, "json": {"state": restarted, "version": 1}},
		{"status": 200, "json": {"state": restarted, "version": 1}},
		{"status": 200, "json": {"state": entered, "version": 2}}])
	var mine := await _scene(transport, state)
	assert_int(transport.requests.size()).is_equal(1)
	assert_bool(mine.session.has_unconfirmed_command()).is_true()
	assert_bool(mine.primary.disabled).is_true()
	assert_that(mine.session.state).is_equal(state)
	await mine._recover()
	for frame in 3: await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(4)
	assert_str(transport.requests[0].body.type).is_equal("restart_mine")
	assert_that(transport.requests[1].body).is_equal(transport.requests[0].body)
	assert_str(transport.requests[2].method).is_equal("GET")
	assert_str(transport.requests[3].body.type).is_equal("enter_mine")
	assert_int(int(transport.requests[3].body.payload.run)).is_equal(3)
	assert_str(transport.requests[3].body.idempotency_key).is_not_equal(transport.requests[0].body.idempotency_key)
	assert_int(mine.current_floor()).is_equal(1)
	assert_bool(mine.session.has_unconfirmed_command()).is_false()
	assert_bool(mine._can_act()).is_true()
	assert_that(mine.session.state.journey.materials).is_equal(state.journey.materials)

func test_lost_entry_reply_replays_the_same_command_without_restarting_again() -> void:
	var state := _completed_state()
	var restarted := _restarted_state(state)
	var entered := restarted.duplicate(true)
	entered.mine.floor = 1
	var transport := FakeTransport.new([
		{"status": 200, "json": {"state": restarted, "version": 1}},
		{"status": 504, "json": {}},
		{"status": 200, "json": {"state": entered, "version": 2}},
		{"status": 200, "json": {"state": entered, "version": 2}}])
	var mine := await _scene(transport, state)
	assert_int(transport.requests.size()).is_equal(2)
	assert_bool(mine.session.has_unconfirmed_command()).is_true()
	assert_int(mine.current_floor()).is_equal(0)
	assert_int(int(mine.session.state.mine.run)).is_equal(3)
	await mine._recover()
	for frame in 3: await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(4)
	assert_str(transport.requests[0].body.type).is_equal("restart_mine")
	assert_str(transport.requests[1].body.type).is_equal("enter_mine")
	assert_that(transport.requests[2].body).is_equal(transport.requests[1].body)
	assert_str(transport.requests[3].method).is_equal("GET")
	assert_int(mine.current_floor()).is_equal(1)
	assert_int(int(mine.session.state.mine.run)).is_equal(3)
	assert_bool(mine.session.has_unconfirmed_command()).is_false()
	assert_bool(mine._can_act()).is_true()
	assert_that(mine.session.state.journey.materials).is_equal(state.journey.materials)

func test_offline_or_unconfirmed_outside_entry_does_not_issue_commands() -> void:
	for mode in ["offline", "unconfirmed"]:
		for state in [_state(0), _completed_state()]:
			var transport := FakeTransport.new([])
			var session := _session(transport, state)
			session.offline = mode == "offline"
			if mode == "unconfirmed": session._unconfirmed_command = {"type": "restart_mine"}
			var mine := await _scene_with_session(session)
			assert_int(transport.requests.size()).is_equal(0)
			assert_that(session.state).is_equal(state)
			assert_int(mine.current_floor()).is_equal(0)
			assert_bool(mine.primary.disabled).is_true()
			assert_bool(mine.reconnect.visible).is_true()

func test_normal_exit_from_cleared_mine_does_not_automatically_reenter() -> void:
	var state := _completed_state(5)
	var outside := state.duplicate(true)
	outside.mine.floor = 0
	var transport := FakeTransport.new([{"status": 200, "json": {"state": outside, "version": 1}}])
	var session := _session(transport, state)
	var underlying := AppRouter.push_instance("res://tests/fixtures/scenes/stack_probe.tscn")
	var mine := AppRouter.push_instance(AppRouter.MINE, {"session": session})
	for frame in 3: await get_tree().process_frame
	await mine._leave()
	for frame in 3: await get_tree().process_frame
	assert_that(AppRouter.top_instance()).is_equal(underlying)
	assert_int(transport.requests.size()).is_equal(1)
	assert_str(transport.last_body().type).is_equal("leave_mine")
	assert_that(session.state).is_equal(outside)

func test_lifecycle_releases_and_restores_camera_environment_and_hud() -> void:
	var mine := await _scene(FakeTransport.new([]), _state())
	mine.suspend()
	assert_bool(mine.visible).is_false()
	assert_bool(mine.canvas.visible).is_false()
	assert_that(mine.world_env.environment).is_null()
	assert_int(mine.process_mode).is_equal(Node.PROCESS_MODE_DISABLED)
	mine.resume()
	assert_bool(mine.canvas.visible).is_true()
	assert_bool(mine.cam.current).is_true()
	assert_that(mine.world_env.environment).is_equal(mine.environment)
	assert_int(mine.process_mode).is_equal(Node.PROCESS_MODE_INHERIT)

func test_deferred_layout_after_detaching_does_not_access_the_camera() -> void:
	var mine := await _scene(FakeTransport.new([]), _state())
	var before: Transform3D = mine.cam.transform
	mine._layout.call_deferred()
	remove_child(mine)
	mine._update_camera.call_deferred()
	mine._sync_markers.call_deferred()
	for frame in 3: await get_tree().process_frame
	assert_bool(mine.cam.is_inside_tree()).is_false()
	assert_bool(mine.cam.transform.is_equal_approx(before)).is_true()
	assert_that(mine.world_area()).is_equal(Rect2())
	add_child(mine)
	for frame in 3: await get_tree().process_frame
	assert_bool(mine.cam.is_inside_tree()).is_true()

func test_offline_and_unconfirmed_exits_preserve_progress_and_resume_on_reentry() -> void:
	for mode in ["offline", "unconfirmed"]:
		for system_back in [false, true]:
			var state := _state(3)
			state.mine.broken = {"3": ["rock_1", "rock_2"]}
			var transport := FakeTransport.new([])
			var ss := _session(transport, state)
			ss.offline = mode == "offline"
			if mode == "unconfirmed": ss._unconfirmed_command = {"type": "mine_rock"}
			var saved := ss.state.duplicate(true)
			var underlying := AppRouter.push_instance("res://tests/fixtures/scenes/stack_probe.tscn")
			var mine := AppRouter.push_instance(AppRouter.MINE, {"session": ss})
			for frame in 3: await get_tree().process_frame
			if system_back: AppRouter.handle_back()
			else: await mine._leave()
			for frame in 3: await get_tree().process_frame
			assert_that(AppRouter.top_instance()).is_equal(underlying)
			assert_that(ss.state).is_equal(saved)
			assert_int(transport.requests.size()).is_equal(0)
			mine = AppRouter.push_instance(AppRouter.MINE, {"session": ss})
			for frame in 3: await get_tree().process_frame
			assert_int(mine.current_floor()).is_equal(3)
			assert_bool(mine.targets.has("rock_1")).is_false()
			assert_bool(mine.targets.has("rock_3")).is_true()
			AppRouter.pop_instance()
			AppRouter.pop_instance()
			await get_tree().process_frame

func test_authoritative_floor_change_cancels_unfinished_local_dig() -> void:
	var mine := await _scene(FakeTransport.new([]), _state())
	mine._arrived("rock_1")
	assert_str(mine._dig_target).is_equal("rock_1")
	mine.session.state.mine.floor = 2
	mine.session.state_changed.emit(mine.session.state, 1)
	for frame in 3: await get_tree().process_frame
	assert_str(mine._dig_target).is_empty()
	assert_str(mine.pending_target).is_empty()
	assert_float(mine.progress.value).is_equal(0.0)
	assert_bool(mine.primary.disabled).is_false()

func test_json_number_arrays_unlock_ladders_and_completed_entry() -> void:
	var state: Dictionary = JSON.parse_string(JSON.stringify(_state(4)))
	state.mine.cleared_floors = JSON.parse_string("[1,2,3,4]")
	var transport := FakeTransport.new([])
	var mine := await _scene(transport, state)
	assert_bool(mine.cleared()).is_true()
	assert_bool(mine.targets.has("down")).is_true()
	assert_bool(mine.completed()).is_false()
	assert_bool(mine.fully_cleared()).is_false()
	mine.session.state.mine.cleared_floors = JSON.parse_string("[1,2,3,4,5]")
	for number in range(1, 6):
		mine.session.state.mine.broken[str(number)] = Layout.rocks(number).map(func(rock): return rock.id)
	mine.session.state.mine.floor = 0.0
	mine.session.state_changed.emit(mine.session.state, 1)
	for frame in 3: await get_tree().process_frame
	assert_bool(mine.completed()).is_true()
	assert_bool(mine.fully_cleared()).is_true()
	assert_bool(mine.restart.visible).is_true()
	assert_int(transport.requests.size()).is_equal(0)
	mine.session.state.mine.cleared_floors = JSON.parse_string("[1,1,2,3,5]")
	assert_bool(mine.fully_cleared()).is_false()

func test_mine_has_router_and_qa_entry() -> void:
	assert_str(AppRouter.qa_scene_path(PackedStringArray(["--qa-scene=mine"]))).is_equal(AppRouter.MINE)
	assert_int(AppRouter.back_action_for_scene(AppRouter.MINE)).is_equal(AppRouter.BACK_TO_MAP)

func test_diagonal_mine_camera_matches_farm_and_controls_follow_the_screen() -> void:
	var mine := await _scene(FakeTransport.new([]), _state())
	var expected := auto_free(Camera3D.new()) as Camera3D
	add_child(expected)
	Farm.FarmCamera.place(expected, Vector3.ZERO)
	assert_int(mine.cam.projection).is_equal(Camera3D.PROJECTION_ORTHOGONAL)
	assert_bool(mine.cam.global_basis.is_equal_approx(expected.global_basis)).is_true()
	for input in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		var direction: Vector2 = mine._camera_direction(input)
		assert_float(direction.length()).is_equal_approx(1.0,0.001)
		var origin := Vector3(4.75,0,-3.8)
		var projected: Vector2 = mine.cam.unproject_position(origin+Vector3(direction.x,0,direction.y)) - mine.cam.unproject_position(origin)
		assert_float(projected.normalized().dot(input)).is_greater(0.999)

func test_floor_rebuild_keeps_art_independent_and_all_saved_targets_pickable_after_panning() -> void:
	var mine := await _scene(FakeTransport.new([]), _state())
	for floor_number in range(1,6):
		mine.session.state.mine.floor = floor_number
		mine.session.state.mine.cleared_floors = [floor_number]
		mine._refresh()
		await get_tree().process_frame
		for id in mine.targets:
			var model: Node3D = mine.targets[id].model   # the elevator station is a shell of meshes (SGODOT-459)
			var center: Vector3 = model.global_transform * mine._model_box(model).get_center()
			_pan_to(mine, center)
			var point: Vector2 = mine.cam.unproject_position(center)
			assert_bool(mine.world_area().has_point(point)).override_failure_message("Target clipped: %d / %s" % [floor_number,id]).is_true()
			assert_str(mine._pick_target(point)).override_failure_message("Target obstructed: %d / %s" % [floor_number,id]).is_equal(id)
	var next := await _scene(FakeTransport.new([]), _state(5))
	assert_bool(mine.scenery != next.scenery).is_true()
	assert_bool(mine.scenery.get_node("MineElevator") != next.scenery.get_node("MineElevator")).is_true()

func test_passable_floors_with_unmined_rocks_are_not_automatically_restarted() -> void:
	var state := _state(0)
	state.mine.cleared_floors = [1, 2, 3, 4, 5]
	state.mine.elevator_unlocked = true
	for number in [1, 2]: state.mine.broken[str(number)] = Layout.rocks(number).map(func(rock): return rock.id)
	var mine := await _scene(FakeTransport.new([]), state)
	assert_bool(mine.completed()).is_true()
	assert_bool(mine.fully_cleared()).is_false()

func test_elite_floor_only_has_combat_and_exit_targets() -> void:
	var mine := await _scene(FakeTransport.new([]), _state(5))
	assert_bool(mine.targets.keys().any(func(id): return str(id).begins_with("rock_"))).is_false()
	assert_int(mine.combat.enemies.size()).is_equal(1)
	assert_str(mine.status.text).contains(L10n.text("Elite challenge"))
	assert_str(mine.primary.text).is_equal(L10n.text("Clear monsters"))
	assert_bool(mine.primary.disabled).is_true()

func test_floor_transition_rebinds_monster_picking_to_the_new_actor() -> void:
	var mine := await _scene(FakeTransport.new([]), _state(4))
	var old_id: int = mine.targets.slime_1.model.get_instance_id()
	mine.session.state.mine.floor = 5
	mine.session.state_changed.emit(mine.session.state, 1)
	for frame in 3: await get_tree().process_frame
	var model: MeshInstance3D = mine.targets.slime_1.model
	assert_bool(is_instance_valid(model)).is_true()
	assert_int(model.get_instance_id()).is_not_equal(old_id)
	assert_object(model).is_equal(mine.combat.enemies.slime_1.node.get_node("Body"))
	_pan_to(mine, model.global_position)
	assert_str(mine._pick_target(mine.cam.unproject_position(model.global_position))).is_equal("slime_1")
