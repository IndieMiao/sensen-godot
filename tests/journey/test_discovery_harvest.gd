extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0}, "wallet": 50, "engineering": {"reserved": {}}, "cells": {}, "nursery": {},
		"inventory": {"produce": {"C": 0, "L": 0, "H": 0}, "dishes": {}, "seeds": {"L": {"bound": 0, "bought": 0}}},
		"journey": {"version": 1, "completed": [], "opportunities": {},
			"facts": ["workbench", "planter_crafted", "planter_placed", "met_bistro", "shared_meal", "side_path", "crafted_lantern",
				"discovery_stone_hollow", "discovery_reed_garden", "discovery_kitchen_garden"],
			"unlocks": ["bistro", "crop_H"], "wood": 0, "materials": {"stone": 0, "fiber": 0},
			"exploration": {"round": 3, "collected": []}, "workshop": {"sequence": 0, "stock": {}, "displays": {}}}}

func _scene(st: Dictionary, id: String, transport: FakeTransport, size := Vector2i(390, 844)) -> JourneyPlace:
	var viewport := auto_free(SubViewport.new()) as SubViewport
	viewport.size = size
	viewport.own_world_3d = true
	add_child(viewport)
	var scene := JourneyPlace.new()
	scene.place_id = str(JourneyProgress.data().discoveries[id].place)
	scene.session = FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	scene.session.state = st
	scene.session.version = 1
	viewport.add_child(scene)
	scene.set_process(false)
	for frame in 3: await get_tree().process_frame
	return scene

func test_two_world_choices_are_separate_pickable_and_reachable_on_each_screen() -> void:
	for size in [Vector2i(360, 640), Vector2i(390, 844), Vector2i(960, 720)]:
		for id in JourneyProgress.data().discoveries:
			var st := _state()
			var original := st.duplicate(true)
			var scene := await _scene(st, str(id), FakeTransport.new(), size)
			var choices := JourneyProjects.discovery_choices(str(id), st)
			assert_int(choices.size()).is_equal(2)
			var captions: Array[Rect2] = []
			for choice in choices:
				var target: Dictionary = scene.targets[choice.id]
				var point := scene.cam.unproject_position(target.body)
				assert_str(scene._pick_target(point)).is_equal(choice.id)
				for offset in [Vector2(-10, 0), Vector2(10, 0), Vector2(0, -8), Vector2(0, 8)]:
					assert_str(scene._pick_target(point + offset)).is_equal(choice.id)
				assert_bool(Rect2(Vector2.ZERO, Vector2(size)).has_point(point)).is_true()
				assert_bool((target.caption as Label).visible).is_true()
				captions.append(target.caption.get_global_rect())
				assert_bool(scene.mover.set_target_position(target.approach - JourneyPlace.NAV_ORIGIN)).is_true()
				var tray := scene.objects.get_node("Discovery_%s/Harvest_%s" % [id, choice.choice]) as MeshInstance3D
				assert_bool(tray.get_meta("harvest_ready")).is_true()
				assert_int(tray.mesh.get_surface_count()).is_greater(0)
			assert_bool(captions[0].intersects(captions[1])).is_false()
			assert_dict(st).is_equal(original)
			await _dispose(scene)

func test_unrestored_locked_and_collected_rewards_do_not_expose_harvest_targets() -> void:
	var st := _state()
	st.journey.facts.erase("discovery_kitchen_garden")
	var scene := await _scene(st, "kitchen_garden", FakeTransport.new())
	assert_array(scene.targets.keys().filter(func(id): return str(id).begins_with("harvest:"))).is_empty()
	st.journey.facts.append("discovery_kitchen_garden")
	st.journey.unlocks.erase("crop_H")
	scene._refresh()
	assert_bool(scene.targets.has("harvest:kitchen_garden:salad")).is_true()
	for frame in 3: await get_tree().process_frame
	assert_bool(scene.targets.has("harvest:kitchen_garden:flowers")).is_false()
	st.journey.exploration.collected.append("discovery_kitchen_garden")
	scene._refresh()
	assert_array(scene.targets.keys().filter(func(id): return str(id).begins_with("harvest:"))).is_empty()
	assert_bool(scene.objects.get_node("Discovery_kitchen_garden/Harvest_salad").get_meta("harvest_ready")).is_false()
	st.journey.exploration.round += 1
	st.journey.exploration.collected.clear()
	scene._refresh()
	assert_bool(scene.targets.has("harvest:kitchen_garden:salad")).is_true()
	await _dispose(scene)

func test_tapping_a_harvest_walks_before_sending_and_removes_both_choices_after_acceptance() -> void:
	for id in JourneyProgress.data().discoveries:
		for choice_id in JourneyProgress.data().discoveries[id].choices:
			var st := _state()
			var result := st.duplicate(true)
			result.journey.exploration.collected.append("discovery_" + str(id))
			result.journey.discovery_choices = {id: choice_id}
			var reward: Dictionary = JourneyProgress.data().discoveries[id].choices[choice_id]
			for material in reward.materials:
				if material == "wood": result.journey.wood += int(reward.materials[material])
				else: result.journey.materials[material] += int(reward.materials[material])
			for crop in reward.produce: result.inventory.produce[crop] += int(reward.produce[crop])
			for crop in reward.seeds: result.inventory.seeds[crop].bound += int(reward.seeds[crop])
			var transport := FakeTransport.new([{ "status": 200, "json": {"version": 2, "state": result}}])
			var scene := await _scene(st, str(id), transport)
			var target_id := "harvest:%s:%s" % [id, choice_id]
			scene._ground_tap(scene.cam.unproject_position(scene.targets[target_id].body))
			assert_str(scene.pending_target).is_equal(target_id)
			assert_array(transport.requests).is_empty()
			assert_bool(scene.panel.visible).is_false()
			for step in 250:
				if scene.busy: break
				scene._process(0.05)
			assert_bool(scene.busy).is_true()
			assert_bool(scene.select_target(target_id)).is_false()
			var work_seconds := CharacterModel.gather_seconds(st, CharacterModel.resource_kind(reward.materials))
			var deadline := Time.get_ticks_msec() + ceili(work_seconds * 1000) + 1500
			while scene.busy and Time.get_ticks_msec() < deadline: await get_tree().process_frame
			for frame in 3: await get_tree().process_frame
			assert_bool(scene.busy).is_false()
			assert_int(transport.requests.size()).is_equal(1)
			assert_str(transport.last_body().type).is_equal("harvest_journey_discovery")
			assert_dict(transport.last_body().payload).is_equal({"discovery": id, "choice": choice_id, "round": 3.0})
			assert_dict(scene.session.state).is_equal(result)
			assert_bool(scene.panel.visible).is_false()
			assert_bool(scene.world_notice.visible).is_true()
			assert_str(scene.world_notice_label.text).is_equal("+" + JourneyProgress.discovery_reward_label(reward))
			assert_array(scene.targets.keys().filter(func(target): return str(target).begins_with("harvest:"))).is_empty()
			assert_bool(scene.select_target(target_id)).is_false()
			await _dispose(scene)

func test_rejected_harvest_keeps_the_offers_and_does_not_show_success() -> void:
	var st := _state()
	var transport := FakeTransport.new([{ "status": 422, "json": {"code": "NOT_AVAILABLE"}}])
	var scene := await _scene(st, "kitchen_garden", transport)
	await scene._arrived("harvest:kitchen_garden:flowers")
	assert_dict(scene.session.state).is_equal(st)
	assert_bool(scene.targets.has("harvest:kitchen_garden:flowers")).is_true()
	assert_bool(scene.world_notice.visible).is_false()
	assert_bool(scene.panel.visible).is_true()
	assert_str(scene.selected_target).is_equal("discovery_kitchen_garden")
	assert_str(scene.feedback.text).is_not_empty()
	assert_int(transport.requests.size()).is_equal(1)
	await _dispose(scene)

func test_following_a_request_runs_to_its_harvest_and_continues_to_delivery() -> void:
	var st := _state()
	st.inventory.produce.L = 1
	st.journey.tracked_opportunity = {"slot": "nursery", "sequence": 2}
	st.journey.opportunities.nursery = {"sequence": 2, "variant": 0}
	var result := st.duplicate(true)
	result.inventory.produce.L = 2
	result.inventory.produce.C = 1
	result.journey.exploration.collected.append("discovery_kitchen_garden")
	var transport := FakeTransport.new([{ "status": 200, "json": {"version": 2, "state": result}}])
	var scene := await _scene(st, "kitchen_garden", transport)
	scene.follow_goal.pressed.emit()
	assert_str(scene.pending_target).is_equal("harvest:kitchen_garden:salad")
	assert_bool(scene.panel.visible).is_false()
	assert_array(transport.requests).is_empty()
	for step in 250:
		if scene.busy: break
		scene._process(0.05)
	assert_bool(scene.busy).is_true()
	var deadline := Time.get_ticks_msec() + 2000
	while scene.busy and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	for frame in 3: await get_tree().process_frame
	assert_int(transport.requests.size()).is_equal(1)
	assert_str(transport.last_body().payload.choice).is_equal("salad")
	assert_bool(scene.panel.visible).is_false()
	assert_bool(scene.world_notice.visible).is_true()
	assert_str(JourneyProgress.tracked_goal(scene.session.state).resident).is_equal("nursery_keeper")
	assert_dict(scene.session.state.journey.tracked_opportunity).is_equal(st.journey.tracked_opportunity)
	await _dispose(scene)

func test_dragging_over_a_harvest_does_not_select_or_collect_it() -> void:
	var transport := FakeTransport.new()
	var scene := await _scene(_state(), "kitchen_garden", transport)
	var target_id := "harvest:kitchen_garden:salad"
	var point := scene.cam.unproject_position(scene.targets[target_id].body)
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = point
	press.pressed = true
	scene._unhandled_input(press)
	assert_str(scene._pressed_target).is_equal(target_id)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = point + Vector2(70, 0)
	drag.relative = Vector2(70, 0)
	scene._input(drag)
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = drag.position
	scene._input(release)
	assert_str(scene.pending_target).is_empty()
	assert_array(transport.requests).is_empty()
	assert_bool(scene.camera_pan.offset.length() > 0).is_true()
	var center := Vector2(scene.get_viewport().size) * 0.5
	scene.camera_pan.magnify(scene.cam, center, 1.2)
	scene._update_camera()
	scene._sync_markers()
	point = scene.cam.unproject_position(scene.targets[target_id].body)
	assert_str(scene._pick_target(point)).is_equal(target_id)
	assert_array(transport.requests).is_empty()
	await _dispose(scene)

func test_lost_harvest_confirmation_recovers_without_a_second_choice() -> void:
	var st := _state()
	var result := st.duplicate(true)
	result.journey.exploration.collected.append("discovery_kitchen_garden")
	result.journey.discovery_choices = {"kitchen_garden": "flowers"}
	result.inventory.produce.H = 1
	var transport := FakeTransport.new([
		{"error": "lost confirmation after commit"}, {"error": "lost confirmation after commit"},
		{"status": 200, "json": {"version": 2, "state": result}},
		{"status": 200, "json": {"version": 2, "state": result}},
	])
	var scene := await _scene(st, "kitchen_garden", transport)
	await scene._arrived("harvest:kitchen_garden:flowers")
	for frame in 3: await get_tree().process_frame
	assert_bool(scene.session.has_unconfirmed_command()).is_true()
	assert_dict(scene.session.state).is_equal(st)
	assert_bool(scene.select_target("harvest:kitchen_garden:salad")).is_false()
	assert_bool(scene.world_notice.visible).is_false()
	var reconnect := scene.active_panel.content.find_child("ReconnectSession", true, false) as Button
	assert_bool(reconnect.disabled).is_false()
	reconnect.pressed.emit()
	for frame in 5: await get_tree().process_frame
	assert_bool(scene.session.has_unconfirmed_command()).is_false()
	assert_bool(scene.session.offline).is_false()
	assert_dict(scene.session.state).is_equal(result)
	assert_array(scene.targets.keys().filter(func(target): return str(target).begins_with("harvest:"))).is_empty()
	assert_int(transport.requests.size()).is_equal(4)
	for request in transport.requests.slice(0, 3):
		assert_str(request.method).is_equal("POST")
		assert_dict(request.body).is_equal(transport.requests[0].body)
	assert_str(transport.requests[3].method).is_equal("GET")
	scene._close_panel()
	assert_bool(scene.world_notice.visible).is_false()
	assert_bool(scene.panel.visible).is_false()
	await _dispose(scene)

func _dispose(scene: JourneyPlace) -> void:
	scene.get_parent().queue_free()
	for frame in 3: await get_tree().process_frame
