extends GdUnitTestSuite

func _state() -> Dictionary:
	return {"clock": {"chapter_index": 0}, "wallet": 80, "inventory": {"produce": {}, "dishes": {}, "seeds": {}}, "nursery": {}, "cells": {},
		"engineering": {"reserved": {}}, "journey": {"version": 1, "facts": ["workbench", "planter_crafted", "side_path", "crafted_lantern", "shared_meal", "project_terrace_0", "project_terrace_1"],
			"unlocks": ["bistro", "crafting"], "wood": 0, "materials": {"stone": 1, "fiber": 2},
			"exploration": {"round": 2, "collected": [], "branching_places": ["nursery"]}, "opportunities": {},
			"workshop": {"sequence": 1, "stock": {}, "displays": {}, "planned": {"project": "terrace", "slot": 2, "item": "fountain"}}}}

func test_display_goal_follows_materials_workbench_and_original_slot() -> void:
	var st := _state()
	var original := st.duplicate(true)
	var goal := JourneyProgress.next_goal(st)
	assert_str(goal.target).is_equal("bundle:nursery_west")
	assert_str(goal.label).is_equal("Small garden fountain: Stone 1/4")
	assert_dict(st).is_equal(original)
	st.journey.materials.stone = 4
	assert_str(JourneyProgress.next_goal(st).target).is_equal("workbench")
	st.journey.workshop.stock.fountain = 1
	goal = JourneyProgress.next_goal(st)
	assert_str(goal.place).is_equal("bistro")
	assert_str(goal.target).is_equal("display:terrace:2")
	assert_str(JourneyWorkshop.preview_item(st, "terrace", 2)).is_equal("fountain")
	assert_str(JourneyWorkshop.preview_item(st, "terrace", 0)).is_empty()

func test_copper_crate_goal_returns_to_farm_mine_then_workbench() -> void:
	var state := _state()
	state.journey.workshop.planned.item = "crate"
	state.journey.wood = 2
	var original := state.duplicate(true)
	var goal := JourneyWorkshop.goal(state)
	assert_str(goal.place).is_equal("farm")
	assert_str(goal.target).is_equal("mine")
	assert_str(goal.hint).is_equal("Copper ore 0/3")
	assert_int(JourneyProgress.material(state, "rock_salt")).is_equal(0)
	assert_dict(state).is_equal(original)
	state.journey.materials.copper_ore = 3
	assert_str(JourneyWorkshop.goal(state).target).is_equal("workbench")
	state.journey.workshop.stock.crate = 1
	assert_str(JourneyWorkshop.goal(state).target).is_equal("display:terrace:2")

func test_copper_crate_is_offered_after_workbench_before_first_planter() -> void:
	var state := _state()
	state.journey.facts = ["workbench"]
	state.journey.wood = 2
	state.journey.materials.copper_ore = 3
	state.journey.workshop.erase("planned")
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", FakeTransport.new([]).callable()))
	session.state = state
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "nursery"
	panel.target = "workbench"
	panel.setup(session)
	add_child(panel)
	for frame in 3: await get_tree().process_frame
	var make := panel.find_child("Craft_crate", true, false) as Button
	assert_object(make).is_not_null()
	assert_bool(make.disabled).is_false()

func test_kitchen_counter_guides_missing_salt_to_the_farm_mine() -> void:
	var state := _state()
	state.journey.unlocks.append("kitchen")
	state.inventory.produce = {"R": 1, "L": 1}
	var transport := FakeTransport.new([])
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.state = state
	var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
	panel.place_id = "bistro"
	panel.target = "counter"
	panel.setup(session)
	var goals := []
	panel.goal_requested.connect(func(goal): goals.append(goal))
	add_child(panel)
	for frame in 3: await get_tree().process_frame
	var make := panel.find_child("Cook_vegetable_soup", true, false) as Button
	assert_object(make).is_not_null()
	assert_bool(make.disabled).is_true()
	var gather := panel.find_child("Gather_rock_salt", true, false) as Button
	assert_object(gather).is_not_null()
	gather.pressed.emit()
	assert_str(goals[0].place).is_equal("farm")
	assert_str(goals[0].target).is_equal("mine")
	session.state.journey.materials.rock_salt = 1
	session.state_changed.emit(session.state, 1)
	for frame in 3: await get_tree().process_frame
	assert_bool((panel.find_child("Cook_vegetable_soup", true, false) as Button).disabled).is_false()
	assert_object(panel.find_child("Gather_rock_salt", true, false)).is_null()
	assert_array(transport.requests).is_empty()

func test_already_displayed_piece_can_be_moved_without_crafting_another() -> void:
	var st := _state()
	st.journey.facts.append_array(["project_seedbeds_0", "project_seedbeds_1"])
	st.journey.workshop.displays.seedbeds = ["", "fountain", ""]
	assert_str(JourneyProgress.next_goal(st).target).is_equal("display:seedbeds:1")
	assert_str(JourneyProgress.next_goal(st).hint).is_equal("Collect your piece")
	st.journey.workshop.erase("planned")
	assert_dict(JourneyWorkshop.goal(st)).is_empty()

func test_unavailable_or_occupied_plan_is_ignored_without_mutating_the_save() -> void:
	for fields in [{"project": "missing"}, {"project": "waystation"}, {"item": "missing"}, {"slot": -1}, {"slot": 3}]:
		var st := _state()
		st.journey.workshop.planned.merge(fields, true)
		var before := st.duplicate(true)
		assert_dict(JourneyWorkshop.goal(st)).is_empty()
		assert_dict(st).is_equal(before)
	var occupied := _state()
	occupied.journey.workshop.displays.terrace = ["", "", "planter"]
	assert_dict(JourneyWorkshop.goal(occupied)).is_empty()

func test_empty_slot_offers_recipes_and_plans_only_after_server_acceptance() -> void:
	for accepted in [false, true]:
		var st := _state()
		st.journey.workshop.erase("planned")
		st.journey.workshop.sequence = 0
		var result := st.duplicate(true)
		result.journey.workshop.planned = {"item": "fountain", "project": "terrace", "slot": 2}
		result.journey.workshop.sequence = 1
		var reply := {"status": 200, "json": {"version": 2, "state": result}} if accepted else {"status": 422, "json": {"code": "NOT_AVAILABLE"}}
		var transport := FakeTransport.new([reply])
		var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
		session.state = st
		session.version = 1
		var panel := auto_free(JourneyActivityPanel.new()) as JourneyActivityPanel
		panel.place_id = "bistro"
		panel.target = "display:terrace:2"
		panel.setup(session)
		var completed := []
		var plan_changes := []
		panel.world_action_completed.connect(func(target): completed.append(target))
		panel.display_plan_changed.connect(func(): plan_changes.append(true))
		add_child(panel)
		for frame in 3: await get_tree().process_frame
		var buttons := panel.content.find_children("*", "Button", true, false)
		var choose: Button = buttons.filter(func(button): return button.text == "Plan Small garden fountain")[0]
		assert_bool(choose.disabled).is_false()
		choose.pressed.emit()
		for frame in 5: await get_tree().process_frame
		assert_str(transport.last_body().type).is_equal("plan_journey_display")
		assert_dict(transport.last_body().payload).is_equal({"project": "terrace", "slot": 2.0, "item": "fountain", "sequence": 0.0})
		assert_array(completed).is_equal(["display:terrace:2"] if accepted else [])
		assert_int(plan_changes.size()).is_equal(1 if accepted else 0)
		assert_dict(session.state).is_equal(result if accepted else st)

func test_planning_and_cancelling_restore_exploration_and_keep_world_feedback() -> void:
	for item in ["fountain", ""]:
		var st := _state()
		if not item.is_empty(): st.journey.workshop.erase("planned")
		var result := st.duplicate(true)
		if item.is_empty(): result.journey.workshop.erase("planned")
		else: result.journey.workshop.planned = {"project": "terrace", "slot": 2, "item": item}
		result.journey.workshop.sequence = 2
		var transport := FakeTransport.new([{"status": 200, "json": {"version": 2, "state": result}}])
		var scene := await _scene(st, "bistro", transport)
		scene._arrange_display("terrace")
		scene._show_panel("display:terrace:2")
		for frame in 3: await get_tree().process_frame
		var panel := scene.active_panel as JourneyActivityPanel
		var tooltip := "Cancel handmade plan" if item.is_empty() else "Plan Small garden fountain"
		var button: Button = panel.content.find_children("*", "Button", true, false).filter(func(b): return b.tooltip_text == tooltip)[0]
		button.pressed.emit()
		for frame in 5: await get_tree().process_frame
		assert_str(scene.display_project).is_empty()
		assert_bool(scene.display_done.visible).is_false()
		assert_bool(scene.panel.visible).is_false()
		assert_bool(scene.world_notice.visible).is_true()
		assert_str(scene.world_notice_label.text).is_equal("Handmade plan cancelled." if item.is_empty() else "Small garden fountain planned.")
		assert_dict(scene.session.state).is_equal(result)
		assert_bool(scene.targets.has("display:terrace:2")).is_equal(not item.is_empty())
		assert_int(transport.requests.size()).is_equal(1)
		scene.queue_free()
		await get_tree().process_frame

func test_planned_craft_returns_to_world_only_after_acceptance() -> void:
	for accepted in [false, true]:
		var st := _state()
		st.journey.materials.stone = 4
		var result := st.duplicate(true)
		result.journey.materials = {"stone": 0, "fiber": 0}
		result.journey.workshop.stock.fountain = 1
		result.journey.workshop.sequence = 2
		var reply := {"status": 200, "json": {"version": 2, "state": result}} if accepted else {"status": 422, "json": {"code": "INSUFFICIENT_ITEMS"}}
		var transport := FakeTransport.new([reply])
		var scene := await _scene(st, "nursery", transport)
		scene._show_panel("workbench")
		for frame in 3: await get_tree().process_frame
		var button := scene.active_panel.content.find_child("Craft_fountain", true, false) as Button
		assert_bool(button.disabled).is_false()
		button.pressed.emit()
		for frame in 5: await get_tree().process_frame
		assert_bool(scene.panel.visible).is_equal(not accepted)
		assert_str(transport.last_body().type).is_equal("craft_journey_item")
		assert_str(JourneyProgress.next_goal(scene.session.state).target).is_equal("display:terrace:2" if accepted else "workbench")
		assert_dict(scene.session.state).is_equal(result if accepted else st)
		assert_int(transport.requests.size()).is_equal(1)
		scene.queue_free()
		await get_tree().process_frame

func test_reconnected_plan_or_cancellation_releases_arrangement_mode() -> void:
	for item in ["fountain", ""]:
		var st := _state()
		if not item.is_empty(): st.journey.workshop.erase("planned")
		var result := st.duplicate(true)
		if item.is_empty(): result.journey.workshop.erase("planned")
		else: result.journey.workshop.planned = {"project": "terrace", "slot": 2, "item": item}
		result.journey.workshop.sequence = 2
		var transport := FakeTransport.new([
			{"error": "lost confirmation after commit"}, {"error": "lost confirmation after commit"},
			{"status": 200, "json": {"version": 2, "state": result}},
			{"status": 200, "json": {"version": 2, "state": result}},
		])
		var scene := await _scene(st, "bistro", transport)
		scene._arrange_display("terrace")
		scene._show_panel("display:terrace:2")
		for frame in 3: await get_tree().process_frame
		var panel := scene.active_panel as JourneyActivityPanel
		var tooltip := "Cancel handmade plan" if item.is_empty() else "Plan Small garden fountain"
		var button: Button = panel.content.find_children("*", "Button", true, false).filter(func(b): return b.tooltip_text == tooltip)[0]
		button.pressed.emit()
		for frame in 5: await get_tree().process_frame
		assert_bool(scene.session.has_unconfirmed_command()).is_true()
		assert_dict(scene.session.state).is_equal(st)
		assert_str(scene.display_project).is_equal("terrace")
		var reconnect := panel.content.find_child("ReconnectSession", true, false) as Button
		assert_bool(reconnect.disabled).is_false()
		reconnect.pressed.emit()
		for frame in 5: await get_tree().process_frame
		assert_bool(scene.session.has_unconfirmed_command()).is_false()
		assert_bool(scene.session.offline).is_false()
		assert_dict(scene.session.state).is_equal(result)
		assert_str(scene.display_project).is_empty()
		assert_bool(scene.display_done.visible).is_false()
		assert_int(transport.requests.size()).is_equal(4)
		for request in transport.requests.slice(0, 3):
			assert_str(request.method).is_equal("POST")
			assert_dict(request.body).is_equal(transport.requests[0].body)
		assert_str(transport.requests[3].method).is_equal("GET")
		scene._close_panel()
		assert_bool(scene.panel.visible).is_false()
		assert_bool(scene.targets.has("display:terrace:2")).is_equal(not item.is_empty())
		scene.queue_free()
		await get_tree().process_frame

func test_scene_rebuild_keeps_preview_at_its_slot_until_cancelled_or_placed() -> void:
	for spec in [["terrace", "fountain"], ["seedbeds", "planter"], ["waystation", "lantern"]]:
		var st := _state()
		var project := str(spec[0])
		var item := str(spec[1])
		for stage in 2:
			var fact := "project_%s_%d" % [project, stage]
			if not st.journey.facts.has(fact): st.journey.facts.append(fact)
		st.journey.workshop.planned = {"project": project, "slot": 2, "item": item}
		var before := st.duplicate(true)
		var scene := await _scene(st, str(JourneyProgress.data().projects[project].place), FakeTransport.new())
		var path := "Handmade_%s/Display_2_" % project
		var preview := scene.objects.get_node(path) as MeshInstance3D
		assert_str(preview.get_meta("planned_item")).is_equal(item)
		assert_that(preview.position).is_equal(JourneyProjects.display_position(project, 2))
		var material := preview.material_override as StandardMaterial3D
		assert_int(material.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
		assert_float(material.albedo_color.a).is_equal_approx(0.45, 0.001)
		assert_int(preview.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		var target := "display:%s:2" % project
		assert_bool(scene.mover.set_target_position(scene.targets[target].approach - JourneyPlace.NAV_ORIGIN)).is_true()
		assert_dict(st).is_equal(before)
		st.journey.workshop.erase("planned")
		scene._refresh()
		assert_bool(scene.objects.has_node(path)).is_false()
		st.journey.workshop.displays[project] = ["", "", item]
		scene._refresh()
		var placed := scene.objects.get_node(path + item) as MeshInstance3D
		assert_bool(placed.has_meta("planned_item")).is_false()
		assert_int((placed.material_override as StandardMaterial3D).transparency).is_equal(BaseMaterial3D.TRANSPARENCY_DISABLED)
		assert_bool(scene.mover.set_target_position(scene.targets[target].approach - JourneyPlace.NAV_ORIGIN)).is_true()
		scene.queue_free()
		await get_tree().process_frame

func _scene(st: Dictionary, place: String, transport: FakeTransport) -> JourneyPlace:
	var scene := auto_free(JourneyPlace.new()) as JourneyPlace
	scene.place_id = place
	scene.session = FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	scene.session.state = st
	scene.session.version = 1
	add_child(scene)
	scene.set_process(false)
	for frame in 3: await get_tree().process_frame
	return scene
