extends GdUnitTestSuite

func after_test() -> void:
	for frame in 3: await get_tree().process_frame

func _street() -> JourneyStreet:
	var session := FarmSession.new(ApiClient.new())
	session.layout_patch_id = "sh_a"
	session.blueprint_revision = 2
	session.state = {"clock": {"chapter_index": 0}, "wallet": 200, "cells": {}, "residents": {},
		"inventory": {"produce": {}, "dishes": {}, "seeds": {}}, "engineering": {"reserved": {}},
		"journey": {"version": 1, "facts": JourneyProgress.data().gatherings.requires + ["met_nursery", "met_bistro", "workbench", "side_path", "shared_meal"],
			"unlocks": ["bistro", "crafting", "gifts", "kitchen"], "completed": [], "wood": 0, "materials": {},
			"exploration": {"round": 3, "collected": []}, "opportunities": {}, "workshop": {"stock": {}, "displays": {}}}}
	var street := auto_free(JourneyStreet.new()) as JourneyStreet
	street.session = session
	add_child(street)
	for frame in 5: await get_tree().process_frame
	street.set_process(false)
	street._focus_view(street.residents.moments.nursery.actor.position, 30)
	street.camera_pan.offset = Vector3(1, 0, -1)
	street.camera_pan._log_zoom = log(1.2)
	street._update_camera()
	street._sync_markers()
	return street

func _view(street: JourneyStreet) -> Dictionary:
	return {"position": street.cam.position, "size": street.cam.size, "v_offset": street.cam.v_offset,
		"center": street._camera_center, "base": street._base_size, "pan": street.camera_pan.offset, "zoom": street.camera_pan.zoom}

func test_closing_dialogue_restores_the_exploration_view_immediately() -> void:
	var street := await _street()
	var expected := _view(street)
	street._show_dialogue("nursery")
	street._update_camera()
	assert_float(street.cam.size).is_not_equal(expected.size)
	street._close_dialogue()
	assert_dict(_view(street)).is_equal(expected)
	assert_bool(street.dialogue.visible).is_false()

func test_resident_success_keeps_pan_zoom_and_exploration_framing() -> void:
	var street := await _street()
	var expected := _view(street)
	for slot in ["nursery", "bistro", "restorer"]:
		street._show_dialogue(slot)
		street._update_camera()
		street.active_panel.message.text = "A shared moment"
		street._resident_interaction_completed(StreetCommons.RESIDENTS[slot])
		assert_bool(street.dialogue.visible).is_false()
		assert_str(street.notice.text).is_equal("A shared moment")
		assert_dict(_view(street)).is_equal(expected)

func test_construction_success_keeps_the_players_camera_choice() -> void:
	var street := await _street()
	var expected := _view(street)
	street._show_dialogue("restorer")
	street._update_camera()
	street.active_panel.message.text = "Timber delivered"
	street._contribution_completed("restorer", "bench")
	assert_bool(street.dialogue.visible).is_false()
	assert_str(street.notice.text).contains("Timber delivered")
	assert_dict(_view(street)).is_equal(expected)

func test_gathering_feedback_and_scene_return_preserve_the_view() -> void:
	var street := await _street()
	var expected := _view(street)
	street._show_gathering("garden")
	street._update_camera()
	var panel := street.active_panel as JourneyGatheringPanel
	panel.message.text = "Tea is ready"
	panel.hosted.emit("garden")
	assert_dict(_view(street)).is_equal(expected)
	assert_str(street.notice.text).is_equal("Tea is ready")
	street.suspend()
	street.resume()
	street._update_camera()
	assert_dict(_view(street)).is_equal(expected)
