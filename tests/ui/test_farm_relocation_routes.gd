extends GdUnitTestSuite

const RouterScript := preload("res://modules/ui/app_router.gd")

class ControlledRouter extends RouterScript:
	var fail_farm_load := false
	func _load_with_feedback(path: String) -> PackedScene:
		return null if fail_farm_load and path == FARM else load(path) as PackedScene
	func _end_transition() -> void:
		await get_tree().process_frame

var router: ControlledRouter
var _locale := ""

func before_test() -> void:
	_locale = TranslationServer.get_locale()
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	FarmChoice.save("sh_b", 2)
	FarmRegions.save_choice("tokyo")
	router = ControlledRouter.new()
	add_child(router)

func after_test() -> void:
	while router.instance_depth() > 0:
		router._discard_top()
		await get_tree().process_frame
	router._clear_relocation()
	router.queue_free()
	await get_tree().process_frame
	FarmChoice.clear()
	FarmRegions.clear_choice()
	UiState.clear()
	TranslationServer.set_locale(_locale)

func _session() -> FarmSession:
	var session := FarmSession.new(ApiClient.new("https://route-test.invalid/v1", FakeTransport.new([]).callable()))
	session._adopt({"farm_id": "retained-farm", "region_id": "shanghai", "layout_patch_id": "sh_b", "blueprint_revision": 2,
		"version": 8, "state": {"wallet": 187, "cells": {}}, "relocation": {"available": true, "used": false}})
	return session

func _committed(session: FarmSession) -> Dictionary:
	var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_farm_terrain.json"))
	return {"farm_id": session.farm_id, "region_id": "shanghai", "layout_patch_id": terrain.layout_id, "blueprint_revision": 1,
		"version": 9, "state": session.state.duplicate(true), "farm_terrain": terrain, "location": terrain.source.center,
		"relocation": {"available": false, "used": true}}

func test_cancel_restores_same_farm_camera_ownership_and_preserves_quota_and_browsing_city() -> void:
	var session := _session()
	var source := router.push_instance(router.FARM, {"session": session})
	await get_tree().process_frame
	var old_choice := FarmChoice.load()
	var pose: Transform3D = source.cam.transform
	var environment: Environment = source.get_node("WorldEnvironment").environment
	await router.begin_farm_relocation(session, source)
	assert_int(router.instance_depth()).is_equal(2)
	assert_that(router.top_instance().region.id).is_equal("shanghai")
	assert_that(router.top_instance()._relocation_session).is_equal(session)
	assert_bool(source.visible).is_false()
	assert_bool(source.cam.current).is_false()
	assert_object(source.get_node("WorldEnvironment").environment).is_null()
	router.cancel_farm_relocation()
	await get_tree().process_frame
	assert_int(router.instance_depth()).is_equal(1)
	assert_object(router.top_instance()).is_equal(source)
	assert_bool(source.visible).is_true()
	assert_bool(source.cam.current).is_true()
	assert_that(source.cam.transform).is_equal(pose)
	assert_object(source.get_node("WorldEnvironment").environment).is_equal(environment)
	assert_that(FarmChoice.load()).is_equal(old_choice)
	assert_str(FarmRegions.load_choice()).is_equal("tokyo")
	assert_bool(session.relocation_available()).is_true()
	assert_int(session.state.wallet).is_equal(187)

func test_confirmed_server_geometry_replaces_scene_but_preserves_identity_and_assets() -> void:
	var session := _session()
	var source := router.push_instance(router.FARM, {"session": session})
	await get_tree().process_frame
	await router.begin_farm_relocation(session, source)
	var chooser := router.top_instance()
	assert_bool(session._adopt(_committed(session))).is_true()
	chooser._relocation_committed = true
	assert_bool(source._terrain_stale).is_true()
	await router.complete_farm_relocation(session.farm_choice())
	await get_tree().process_frame
	var destination := router.top_instance()
	assert_int(router.instance_depth()).is_equal(1)
	assert_bool(is_instance_valid(source)).is_false()
	assert_bool(is_instance_valid(chooser)).is_false()
	assert_object(destination.session).is_equal(session)
	assert_str(destination.geo_blueprint.layout_patch_id).is_equal(session.layout_patch_id)
	assert_str(session.farm_id).is_equal("retained-farm")
	assert_int(session.state.wallet).is_equal(187)
	assert_bool(destination.cam.current).is_true()
	assert_bool(destination._relocate_button.visible).is_false()
	assert_str(FarmRegions.load_choice()).is_equal("shanghai")
	assert_that(FarmChoice.load()).is_equal(session.farm_choice())

func test_failed_load_after_commit_cannot_cancel_into_stale_farm_and_can_retry() -> void:
	var session := _session()
	var source := router.push_instance(router.FARM, {"session": session})
	await get_tree().process_frame
	await router.begin_farm_relocation(session, source)
	var chooser := router.top_instance()
	session._adopt(_committed(session))
	chooser._relocation_committed = true
	router.fail_farm_load = true
	await router.complete_farm_relocation(session.farm_choice())
	router.cancel_farm_relocation()
	assert_object(router.top_instance()).is_equal(chooser)
	assert_bool(source.visible).is_false()
	assert_bool(source.cam.current).is_false()
	router.fail_farm_load = false
	await router.complete_farm_relocation(session.farm_choice())
	await get_tree().process_frame
	assert_int(router.instance_depth()).is_equal(1)
	assert_str(router.top_instance().geo_blueprint.layout_patch_id).is_equal(session.layout_patch_id)

func test_unconfirmed_state_and_visitor_source_cannot_replace_owner_farm() -> void:
	var session := _session()
	var source := router.push_instance(router.FARM, {"session": session})
	await get_tree().process_frame
	await router.begin_farm_relocation(session, source)
	var chooser := router.top_instance()
	await router.complete_farm_relocation(session.farm_choice())
	assert_object(router.top_instance()).is_equal(chooser)
	router.cancel_farm_relocation()
	await get_tree().process_frame
	source.visitor = true
	await router.begin_farm_relocation(session, source)
	assert_int(router.instance_depth()).is_equal(1)
	assert_object(router._relocation_map).is_null()

func test_chinese_relocation_entry_fits_phone_header_and_is_hidden_for_visitors() -> void:
	TranslationServer.set_locale("zh_CN")
	var session := _session()
	var farm := router.push_instance(router.FARM, {"session": session})
	await get_tree().process_frame
	var bar: HBoxContainer = farm.get_node("HUD/SafeArea/Root/TopBar")
	assert_bool(farm._relocate_button.visible).is_true()
	assert_float(bar.get_combined_minimum_size().x).is_less_equal(328.0)
	assert_str(farm._relocate_button.text).is_equal("重新选址")
	farm.visitor = true
	farm._refresh_hud()
	assert_bool(farm._relocate_button.visible).is_false()

func test_nested_relocation_uses_its_own_camera_and_outline_stays_at_selection_center() -> void:
	var root_map := router.push_instance(router.MAP)
	await get_tree().process_frame
	var session := _session()
	var source := router.push_instance(router.FARM, {"session": session})
	await get_tree().process_frame
	await router.begin_farm_relocation(session, source)
	var chooser := router.top_instance()
	assert_object(get_viewport().get_camera_3d()).override_failure_message("The relocation outline must render through the moving picker camera, not the suspended root map camera").is_equal(chooser.cam)
	assert_bool(root_map.cam.current).is_false()
	assert_bool(source.cam.current).is_false()
	for delta in [Vector3.ZERO, Vector3(100, 0, -70), Vector3(-240, 0, 160), Vector3(3100, 0, 0)]:
		chooser._apply_world_delta(delta)
		chooser._update_cameras()
		var outline: Node3D = chooser.candidate_overlay.get_child(0)
		var rendered_center := get_viewport().get_camera_3d().unproject_position(outline.global_position)
		var selected_center: Vector2 = chooser.cam.unproject_position(chooser.center_world)
		assert_float(rendered_center.distance_to(selected_center)).is_less(1.5)
	router.cancel_farm_relocation()
	await get_tree().process_frame
	assert_object(get_viewport().get_camera_3d()).is_equal(source.cam)
	assert_bool(session.relocation_available()).is_true()
