extends GdUnitTestSuite

func _wait_navigation() -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while AppRouter._navigation_pending and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.01).timeout

func after_test() -> void:
	await _wait_navigation()
	assert_bool(AppRouter._navigation_pending).is_false()
	while AppRouter.instance_depth() > 0:
		AppRouter.pop_instance()
		await get_tree().process_frame
	var current := get_tree().current_scene
	if current != null and current.scene_file_path == AppRouter.MAP:
		get_tree().current_scene = null
		current.queue_free()
	for frame in 3: await get_tree().process_frame

func _session(chapter: int) -> FarmSession:
	var s := FarmSession.new(ApiClient.new("http://test", FakeTransport.new([]).callable()))
	s.farm_id = "place-entry-test"
	s.layout_patch_id = "sh_a"
	s.blueprint_revision = 2
	s.region_id = "shanghai"
	s.state = {"clock": {"chapter_index": chapter}, "nursery": {"stage": "derelict", "appearance": null}, "cells": {}, "xp": {"total": 0, "first_harvest_crops": []}, "engineering": {"reserved": {}}}
	return s

func test_place_access_uses_authoritative_chapter() -> void:
	assert_bool(PlaceCatalog.available("nursery", _session(0).state)).is_true()
	assert_bool(PlaceCatalog.available("courtyard", _session(0).state)).is_true()
	assert_bool(PlaceCatalog.available("bistro", _session(0).state)).is_false()
	assert_bool(PlaceCatalog.available("bistro", _session(1).state)).is_true()
	assert_bool(PlaceCatalog.available("unknown", _session(6).state)).is_false()
	assert_bool(PlaceCatalog.available("nursery", {})).is_false()

func test_enter_and_return_restore_previous_scene_and_camera() -> void:
	var previous := AppRouter.push_instance("res://tests/fixtures/scenes/stack_probe.tscn")
	var place := AppRouter.push_instance(AppRouter.PLACE, {"place_id": "bistro", "session": _session(1)})
	await get_tree().process_frame
	assert_bool(get_viewport().get_camera_3d() == place.cam).is_true()
	assert_int(previous.suspended).is_equal(1)
	assert_bool(get_viewport().transparent_bg).is_false()
	place._exit.pressed.emit()
	await get_tree().process_frame
	assert_bool(is_instance_valid(place)).is_false()
	assert_bool(AppRouter.top_instance() == previous).is_true()
	assert_bool(get_viewport().get_camera_3d() == previous.cam).is_true()
	assert_int(previous.resumed).is_equal(1)

func test_locked_scene_cannot_be_opened_by_direct_routing() -> void:
	var previous := AppRouter.push_instance("res://tests/fixtures/scenes/stack_probe.tscn")
	AppRouter.push_instance(AppRouter.PLACE, {"place_id": "bistro", "session": _session(0)})
	await get_tree().process_frame
	assert_bool(AppRouter.top_instance() == previous).is_true()

func test_journey_exit_arrival_stops_updates_after_removing_the_scene() -> void:
	var session := _session(0)
	session.state.wallet = 0
	session.state.inventory = {"produce": {}, "dishes": {}, "seeds": {}}
	session.state.journey = {"version": 1, "facts": [], "unlocks": [], "completed": [],
		"wood": 0, "exploration": {"round": 0, "collected": []}, "opportunities": {}}
	var place := AppRouter.push_instance(AppRouter.PLACE, {"place_id": "nursery", "session": session})
	await get_tree().process_frame
	var journey: JourneyPlace = place.journey_scene
	journey.ui.size = Vector2(390, 844)
	journey.header.size.y = 100
	assert_bool(journey.select_target("exit")).is_true()
	journey._process(10.0)
	assert_bool(journey.is_inside_tree()).is_false()
	# The legacy place exit now returns to the unified private farm asynchronously.
	await _wait_navigation()
	assert_bool(AppRouter._navigation_pending).is_false()
	assert_int(AppRouter.instance_depth()).is_equal(1)
	var farm := AppRouter.top_instance()
	assert_object(farm).is_not_null()
	if farm == null: return
	assert_str(farm.scene_file_path).is_equal(AppRouter.FARM)
	assert_object(farm.session).is_same(session)
	await get_tree().process_frame
	assert_bool(is_instance_valid(place)).is_false()

func test_physical_place_exits_resume_the_same_private_farm_camera_and_session() -> void:
	var session := _session(1)
	session.state.wallet = 0
	session.state.inventory = {"produce": {}, "dishes": {}, "seeds": {}}
	session.state.journey = {"version": 1, "facts": [], "unlocks": ["bistro"], "completed": [],
		"wood": 0, "exploration": {"round": 0, "collected": []}, "opportunities": {}}
	var original := session.state.duplicate(true)
	var farm := AppRouter.push_instance(AppRouter.STREET, {"session": session})
	for frame in 3: await get_tree().process_frame
	for id in ["nursery", "bistro", "courtyard"]:
		farm.camera_pan.offset = Vector3(0.6, 0, -0.4)
		farm.camera_pan._log_zoom = log(1.2)
		farm._update_camera()
		var camera: Transform3D = farm.cam.transform
		var size: float = farm.cam.size
		var avatar_id: int = farm.player.get_instance_id()
		var position: Vector3 = farm.player.position
		var place := AppRouter.push_instance(AppRouter.PLACE, {"place_id": id, "session": session})
		await get_tree().process_frame
		place.journey_scene._arrived("exit")
		await get_tree().process_frame
		assert_int(AppRouter.instance_depth()).is_equal(1)
		assert_object(AppRouter.top_instance()).is_same(farm)
		assert_bool(is_instance_valid(place)).is_false()
		assert_that(farm.player.position).is_equal(position)
		assert_that(farm.cam.transform).is_equal(camera)
		assert_float(farm.cam.size).is_equal(size)
		assert_bool(farm.cam.current).is_true()
		assert_bool(farm.hud.visible).is_true()
		assert_int(farm.player.get_instance_id()).is_equal(avatar_id)
		assert_that(session.state).is_equal(original)
	var place := AppRouter.push_instance(AppRouter.PLACE, {"place_id": "nursery", "session": session})
	await get_tree().process_frame
	place.journey_scene.busy = true
	place.journey_scene._go_street()
	assert_object(AppRouter.top_instance()).is_same(place)
	place.journey_scene.busy = false
	place.journey_scene._go_map()
	assert_int(AppRouter.instance_depth()).is_equal(0)
	await get_tree().process_frame
	assert_bool(is_instance_valid(farm)).is_false()

func test_places_tab_preserves_farm_selection_and_scroll() -> void:
	var panel := NearbyPanel.new()
	add_child(auto_free(panel))
	panel.set_entries([{"farm_id": "f1", "avatar_ref": "preset_a", "nursery_stage": "derelict"}], 1)
	panel.focus("f1")
	panel.set_place_state(_session(0).state)
	panel.show_places(true)
	assert_str(panel.focused_id).is_equal("f1")
	assert_bool(panel._farm_content.visible).is_false()
	assert_bool(panel._place_buttons.bistro.disabled).is_true()
	panel.set_place_state(_session(1).state)
	assert_bool(panel._place_buttons.bistro.disabled).is_false()
	panel.show_places(false)
	assert_str(panel.focused_id).is_equal("f1")
	assert_bool(panel._preview.visible).is_true()

func test_changing_place_tabs_starts_at_the_new_panels_top() -> void:
	var place := AppRouter.push_instance(AppRouter.PLACE, {"place_id": "nursery", "session": _session(5)})
	place.select_tab("project")
	for index in 5: await get_tree().process_frame
	var scroll := place.content.get_parent() as ScrollContainer
	scroll.scroll_vertical = 120
	assert_int(scroll.scroll_vertical).is_greater(0)
	place.select_tab("people")
	for index in 5: await get_tree().process_frame
	assert_int(scroll.scroll_vertical).is_equal(0)

func test_place_action_feedback_remains_visible_while_content_scrolls() -> void:
	var session := _session(5)
	var saved := session.state.duplicate(true)
	saved.engineering = {"reserved": {"C": 1}}
	var transport := FakeTransport.new([{"status": 200, "json": {"version": 2, "state": saved}}])
	session.client = ApiClient.new("https://example.test/v1", transport.callable())
	var place := AppRouter.push_instance(AppRouter.PLACE, {"place_id": "nursery", "session": session})
	place.select_tab("project")
	for index in 5: await get_tree().process_frame
	assert_bool(await place.active_panel.command("reserve_engineering", {"items": {"C": 1}}, "Material reserved")).is_true()
	for index in 5: await get_tree().process_frame
	var message: Label = place.active_panel.message
	var bounds := message.get_global_rect()
	assert_str(message.text).is_equal("Material reserved")
	assert_bool(place.body.get_global_rect().encloses(bounds)).is_true()
	var scroll := place.content.get_parent() as ScrollContainer
	scroll.scroll_vertical = 120
	for index in 5: await get_tree().process_frame
	assert_that(message.get_global_rect()).is_equal(bounds)
	place.select_tab("people")
	for index in 5: await get_tree().process_frame
	assert_str(place.active_panel.message.text).is_empty()
