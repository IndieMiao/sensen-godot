extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"cells": {}, "clock": {"chapter_index": 0, "field_condition": "sunny"}, "wallet": 180, "engineering": {"reserved": {}},
		"nursery": {"stage": 0, "appearance": {}},
		"inventory": {"produce": {"R": 0, "L": 0, "C": 0, "H": 0}, "dishes": {"salad": 0, "tea": 0},
			"seeds": {"R": {"bound": 6}, "L": {"bound": 3}, "C": {"bound": 2}, "H": {"bound": 0}}},
		"xp": {"total": 0, "first_harvest_crops": []}, "chapters": [], "journey": {"version": 1, "facts": [], "unlocks": [],
			"wood": 0, "completed": [], "materials": {}, "exploration": {"round": 0, "collected": []}, "opportunities": {}}}

func _terrain() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_farm_terrain.json"))

func _session(generated := true) -> FarmSession:
	var session := FarmSession.new(ApiClient.new("https://private-farm.test/v1", FakeTransport.new([]).callable()))
	session.farm_id = "private-test"
	session.region_id = "shanghai"
	session.state = _state()
	session.layout_patch_id = "sh_a"
	session.blueprint_revision = 2
	if generated:
		session.farm_terrain = _terrain()
		session.layout_patch_id = str(session.farm_terrain.layout_id)
		session.blueprint_revision = 1
		session.location = session.farm_terrain.source.center
	return session

func _farm(generated := true) -> Node:
	var session := _session(generated)
	var scene := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	scene.setup({"session": session})
	add_child(auto_free(scene))
	await get_tree().process_frame
	return scene

func after_test() -> void:
	while AppRouter._navigation_pending: await get_tree().process_frame
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame
	FarmChoice.clear()
	for frame in 3: await get_tree().process_frame

func test_generated_farm_uses_persisted_plot_for_ground_navigation_and_mine() -> void:
	var farm := await _farm()
	assert_str(farm.bp.layout_patch_id).is_equal(str(_terrain().layout_id))
	assert_bool(FarmPlot.verify_checksum(farm.bp)).is_true()
	assert_object(farm.grid.bp).is_same(farm.bp)
	assert_float(farm.bp.play_area_m).is_equal(48.0)
	assert_vector(farm.mine_entrance.position).is_equal(farm.mine_position(farm.bp))
	assert_bool(farm.grid.point_path(farm.mover.position, farm.mine_approach(farm.bp)).is_empty()).is_false()
	assert_bool(FishingModel.plan("farm_pond", farm.mover.position, Vector3.INF, farm.grid).is_empty()).is_false()
	assert_str(farm.title.text).is_equal(L10n.text("My Farm"))

func test_old_farm_keeps_original_terrain_and_state() -> void:
	var farm := await _farm(false)
	assert_object(farm.bp).is_same(FarmPlot.blueprint_for())
	assert_str(farm.geo_blueprint.layout_patch_id).is_equal("sh_a")
	assert_that(farm.session.state).is_equal(_state())
	assert_bool(farm.session.farm_terrain.is_empty()).is_true()

func test_resources_and_residents_are_reachable_without_entering_a_street() -> void:
	var farm := await _farm()
	var activities: FarmActivities = farm.farm_activities
	assert_bool(activities.targets.has("nursery")).is_true()
	assert_bool(activities.targets.has("resident:nursery")).is_true()
	for node in JourneyProgress.remaining_nodes(farm.session.state):
		for bundle in JourneyProgress.node_bundles(farm.session.state, node):
			assert_bool(activities.targets.has(bundle.id)).is_true()
	for target in activities.targets.values():
		assert_bool(farm.grid.point_path(farm.mover.position, target.approach).is_empty()).is_false()
	var resource: Dictionary = JourneyProgress.remaining_nodes(farm.session.state)[0]
	farm.focus_destination({"surface": "street", "target": resource.id})
	assert_str(farm._activity_pending).is_equal(str(resource.id))
	assert_int(AppRouter.instance_depth()).is_equal(0)
	assert_that(farm.session.state).is_equal(_state())

func test_activity_placement_does_not_cover_planted_cells_and_claimed_resources_disappear() -> void:
	var farm := await _farm()
	var activities: FarmActivities = farm.farm_activities
	var node: Dictionary = JourneyProgress.remaining_nodes(farm.session.state)[0]
	var cell: Vector2i = farm.bp.world_to_cell(activities.targets[node.id].position)
	var key := "%d,%d" % [cell.x, cell.y]
	farm.session.state.cells[key] = {"state": "growing", "crop": "R", "ready_at": 9999999999999}
	var before: Dictionary = farm.session.state.duplicate(true)
	activities.sync(farm.session.state)
	for target in activities.targets.values():
		assert_vector(farm.bp.world_to_cell(target.position)).is_not_equal(cell)
	assert_that(farm.session.state).is_equal(before)
	farm.session.state.journey.exploration.collected.append(node.id)
	activities.sync(farm.session.state)
	assert_bool(activities.targets.has(node.id)).is_false()
	assert_bool(activities.targets.has("bundle:" + str(node.id))).is_false()

func test_visitor_can_render_same_generated_plot_without_private_activities() -> void:
	var terrain := _terrain()
	terrain.erase("source")
	terrain.farm_style = "east_asian"
	var snapshot := {"farm_id": "other-farm", "layout_patch_id": terrain.layout_id, "blueprint_revision": 1,
		"farm_terrain": terrain, "avatar_ref": "seed:other", "cells": [], "props": []}
	var scene := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	scene.setup({"visitor": true, "snapshot": snapshot})
	add_child(auto_free(scene))
	await get_tree().process_frame
	assert_str(scene.bp.checksum).is_equal(str(terrain.plot.checksum))
	assert_object(scene.farm_activities).is_null()
	assert_bool(scene.work_mode).is_false()
	assert_str(scene.farm_style).is_equal("east_asian")

func _routed_farm() -> Node:
	var farm := AppRouter.push_instance(AppRouter.FARM, {"session": _session()})
	await get_tree().process_frame
	return farm

func test_old_street_routes_reuse_the_same_farm_and_ground_taps_cancel_resource_travel() -> void:
	var farm := await _routed_farm()
	var resource: Dictionary = JourneyProgress.remaining_nodes(farm.session.state)[0]
	AppRouter.open_instance(AppRouter.STREET, {"session": farm.session, "target": resource.id})
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_object(AppRouter.top_instance()).is_same(farm)
	assert_str(farm._activity_pending).is_equal(str(resource.id))
	farm._on_ground_tapped(farm.bp.cell_to_world(farm.bp.anchor("spawn")))
	assert_str(farm._activity_pending).is_empty()
	assert_bool(farm._activity_busy).is_false()

func test_reused_farm_handles_stall_seed_crop_and_mine_targets() -> void:
	var farm := await _routed_farm()
	AppRouter.open_instance(AppRouter.FARM, {"session": farm.session, "target": "stall", "seed_crop": "L"})
	assert_bool(farm.stall.visible).is_true()
	assert_int(AppRouter.instance_depth()).is_equal(1)
	farm.hud.close_modal()
	AppRouter.open_instance(AppRouter.FARM, {"session": farm.session, "plant_crop": "L"})
	assert_str(farm.hud.selected_crop).is_equal("L")
	assert_str(farm._explicit_crop).is_equal("L")
	assert_bool(farm.work_mode).is_false()
	AppRouter.open_instance(AppRouter.FARM, {"session": farm.session, "target": "mine"})
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_bool(farm._mine_pending).is_true()
	assert_bool(farm.mover.is_moving()).is_true()
	farm._on_ground_tapped(farm.mover.position)
	farm._activity_goal({"place": "farm", "target": "mine"})
	assert_bool(farm._mine_pending).is_true()

func test_resident_goal_without_target_walks_to_the_resident_and_modal_blocks_busy_departure() -> void:
	var farm := await _routed_farm()
	var transport := FakeTransport.new([{"status": 200, "json": {"version": 1, "state": farm.session.state}}])
	farm.session.client.transport = transport.callable()
	AppRouter.open_instance(AppRouter.STREET, {"session": farm.session, "resident": "nursery_keeper"})
	assert_str(farm._activity_pending).is_equal("resident:nursery")
	for step in 200:
		if not farm.mover.is_moving(): break
		farm._process(0.1)
	assert_bool(farm.activity_sheet.visible).is_true()
	assert_str(transport.last_body().type).is_equal("talk_to_resident")
	assert_str(transport.last_body().payload.resident_id).is_equal("nursery_keeper")
	farm.activity_sheet.active.busy = true
	farm.hud.close_modal()
	AppRouter.handle_back()
	farm.focus_destination({"target": "mine"})
	assert_bool(farm.activity_sheet.visible).is_true()
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_bool(farm._mine_pending).is_false()
	farm.activity_sheet.active.busy = false
	AppRouter.handle_back()
	assert_bool(farm.hud.modal_open()).is_false()
	assert_int(AppRouter.instance_depth()).is_equal(1)

func test_reaching_resource_uses_original_command_and_only_confirmed_state_removes_it() -> void:
	var farm := await _routed_farm()
	var node: Dictionary = JourneyProgress.remaining_nodes(farm.session.state)[0]
	var confirmed: Dictionary = farm.session.state.duplicate(true)
	confirmed.journey.exploration.collected.append(node.id)
	confirmed.journey.wood = 3
	var transport := FakeTransport.new([{"status": 200, "json": {"outcome": "applied", "version": 1, "state": confirmed}}])
	farm.session.client.transport = transport.callable()
	farm.focus_destination({"target": node.id})
	assert_int(transport.requests.size()).is_zero()
	for step in 200:
		if farm._activity_busy: break
		farm._process(0.1)
	assert_bool(farm._activity_busy).is_true()
	assert_bool(farm.farm_activities.targets.has(node.id)).is_true()
	for tick in 30:
		if not farm._activity_busy: break
		await get_tree().create_timer(0.1).timeout
	assert_bool(farm._activity_busy).is_false()
	assert_int(transport.requests.size()).is_equal(1)
	assert_str(transport.last_body().type).is_equal("collect_resource")
	assert_str(transport.last_body().payload.node_id).is_equal(str(node.id))
	assert_int(int(transport.last_body().payload.round)).is_zero()
	assert_str(transport.last_body().payload.choice).is_equal("primary")
	assert_bool(farm.farm_activities.targets.has(node.id)).is_false()
	assert_int(farm.session.state.journey.wood).is_equal(3)
	assert_int(AppRouter.instance_depth()).is_equal(1)

func test_claiming_one_resource_does_not_move_other_residents_or_resources() -> void:
	var farm := await _farm()
	var before: Dictionary = farm.farm_activities.targets.duplicate(true)
	var node: Dictionary = JourneyProgress.remaining_nodes(farm.session.state)[0]
	farm.session.state.journey.exploration.collected.append(node.id)
	farm.farm_activities.sync(farm.session.state)
	for id in farm.farm_activities.targets:
		assert_vector(farm.farm_activities.targets[id].position).is_equal(before[id].position)

func test_place_exit_resumes_the_original_farm_and_camera_without_a_second_surface() -> void:
	var farm := await _routed_farm()
	var position: Vector3 = farm.player.position
	var camera: Vector3 = farm._camera_center
	var place := AppRouter.push_instance(AppRouter.PLACE, {"session": farm.session, "place_id": "nursery"})
	await get_tree().process_frame
	assert_int(AppRouter.instance_depth()).is_equal(2)
	place.journey_scene._go_street()
	assert_int(AppRouter.instance_depth()).is_equal(1)
	assert_object(AppRouter.top_instance()).is_same(farm)
	assert_vector(farm.player.position).is_equal(position)
	assert_vector(farm._camera_center).is_equal(camera)
	assert_bool(farm.visible).is_true()

func test_woody_blocked_paths_are_used_when_relocating_activity_targets() -> void:
	var farm := await _farm(false)
	var nodes: Array = JourneyProgress.remaining_nodes(farm.session.state)
	var target_id := str(nodes[0].id)
	var cell: Vector2i = farm.bp.world_to_cell(farm.farm_activities.targets[target_id].position)
	var woody := ""
	for crop in CropInfo.ORDER:
		if CropInfo.is_woody(crop):
			woody = crop
			break
	assert_str(woody).is_not_empty()
	# The four planted neighbours enclose this target on otherwise passable ground.
	for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var blocked: Vector2i = cell + delta
		farm.session.state.cells["%d,%d" % [blocked.x, blocked.y]] = {"state": "growing", "crop": woody, "ready_at": 9999999999999}
	farm._sync_woody_blocking(farm.session.state.cells)
	assert_bool(farm.grid.point_path(farm.mover.position, farm.bp.cell_to_world(cell)).is_empty()).is_true()
	farm.farm_activities.sync(farm.session.state)
	assert_bool(farm.farm_activities.targets.has(target_id)).is_true()
	var next: Vector3 = farm.farm_activities.targets[target_id].position
	assert_vector(farm.bp.world_to_cell(next)).is_not_equal(cell)
	assert_bool(farm.grid.point_path(farm.mover.position, next).is_empty()).is_false()

func test_compact_owner_scene_uses_32_meter_plot_with_reachable_facilities_and_residents() -> void:
	var session := _session()
	session.farm_terrain = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/retired_compact_farm_terrain.json"))
	session.layout_patch_id = session.farm_terrain.layout_id
	session.location = session.farm_terrain.source.center
	var scene := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	scene.setup({"session": session})
	add_child(auto_free(scene))
	await get_tree().process_frame
	assert_vector(scene.bp.grid).is_equal(Vector2i(40, 40))
	assert_float(scene.bp.play_area_m).is_equal(32.0)
	assert_object(scene.get_node_or_null("farm_pond")).is_null()
	assert_bool(scene.bp.is_walkable(Vector2i(8,33))).is_true()
	assert_bool(FarmPlot.verify_checksum(scene.bp)).is_true()
	assert_object(scene.grid.bp).is_same(scene.bp)
	assert_bool(scene.grid.point_path(scene.mover.position, scene.mine_approach(scene.bp)).is_empty()).is_false()
	assert_bool(FishingModel.plan("farm_pond", scene.mover.position, Vector3.INF, scene.grid).is_empty()).is_false()
	assert_bool(scene.farm_activities.targets.has("resident:nursery")).is_true()
	for target in scene.farm_activities.targets.values():
		assert_bool(scene.bp.in_bounds(scene.bp.world_to_cell(target.approach))).is_true()
		assert_bool(scene.grid.point_path(scene.mover.position, target.approach).is_empty()).is_false()
	assert_that(session.state).is_equal(_state())

func test_compact_visitor_scene_keeps_own_saved_farm_and_uses_host_dimensions() -> void:
	FarmChoice.save("sh_b", 2)
	var own := FarmChoice.load()
	var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/retired_compact_farm_terrain.json"))
	terrain.erase("source")
	var snapshot := {"farm_id": "compact-host", "layout_patch_id": terrain.layout_id, "blueprint_revision": 1,
		"farm_terrain": terrain, "avatar_ref": "seed:other", "cells": [], "props": []}
	var scene := (load("res://scenes/farm/farm.tscn") as PackedScene).instantiate()
	scene.setup({"visitor": true, "snapshot": snapshot})
	add_child(auto_free(scene))
	await get_tree().process_frame
	assert_float(scene.bp.play_area_m).is_equal(32.0)
	assert_object(scene.get_node_or_null("farm_pond")).is_null()
	assert_bool(scene.bp.is_walkable(Vector2i(8,33))).is_true()
	assert_str(scene.bp.checksum).is_equal(str(terrain.plot.checksum))
	assert_object(scene.farm_activities).is_null()
	assert_bool(scene.work_mode).is_false()
	assert_that(FarmChoice.load()).is_equal(own)
