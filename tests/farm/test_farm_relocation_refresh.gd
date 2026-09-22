extends GdUnitTestSuite

func before_test() -> void:
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""
	FarmChoice.save("sh_b", 2)

func after_test() -> void:
	while AppRouter._navigation_pending: await get_tree().process_frame
	while AppRouter.instance_depth() > 0:
		AppRouter._discard_top()
		await get_tree().process_frame
	FarmChoice.clear()
	FarmRegions.clear_choice()
	Net.use_transport(FakeTransport.new([]).callable())

func _old(id := "owner-farm") -> Dictionary:
	return {"farm_id": id, "region_id": "shanghai", "layout_patch_id": "sh_b", "blueprint_revision": 2,
		"version": 8, "state": {"wallet": 187, "cells": {}}, "relocation": {"available": true, "used": false}}

func _moved(id := "owner-farm") -> Dictionary:
	var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_farm_terrain.json"))
	return _old(id).merged({"farm_terrain": terrain, "layout_patch_id": terrain.layout_id, "blueprint_revision": 1,
		"location": terrain.source.center, "version": 9, "relocation": {"available": false, "used": true}}, true)

func _owner(transport: FakeTransport) -> Node:
	var session := FarmSession.new(ApiClient.new("https://refresh-test.invalid/v1", transport.callable()))
	session._adopt(_old())
	var scene := AppRouter.push_instance(AppRouter.FARM, {"session": session})
	await get_tree().process_frame
	return scene

func test_owner_reload_replaces_old_ground_only_after_fresh_dto_without_duplicate_reads() -> void:
	var transport := FakeTransport.new([{"status": 200, "json": _moved()}])
	var source := await _owner(transport)
	var session: FarmSession = source.session
	source._on_farm_relocated()
	await get_tree().process_frame
	while AppRouter._navigation_pending: await get_tree().process_frame
	await get_tree().process_frame
	var next := AppRouter.top_instance()
	assert_bool(is_instance_valid(source)).is_false()
	assert_object(next.session).is_equal(session)
	assert_str(next.geo_blueprint.layout_patch_id).is_equal(str(_moved().layout_patch_id))
	assert_int(transport.requests.size()).is_equal(1)
	assert_str(transport.requests[0].method).is_equal("GET")
	assert_bool(next._terrain_stale).is_false()
	assert_that(FarmChoice.load()).is_equal(session.farm_choice())

func test_failed_owner_reload_keeps_ground_locked_and_can_recover() -> void:
	var transport := FakeTransport.new([{"error": "offline"}, {"status": 200, "json": _moved()}])
	var source := await _owner(transport)
	source._on_farm_relocated()
	await get_tree().process_frame
	assert_object(AppRouter.top_instance()).is_equal(source)
	assert_bool(source._terrain_stale).is_true()
	assert_bool(source.party_travel_ready()).is_false()
	assert_bool(source._terrain_loading.close_button.visible).is_true()
	source._reload_relocated_farm()
	await get_tree().process_frame
	while AppRouter._navigation_pending: await get_tree().process_frame
	await get_tree().process_frame
	assert_str(AppRouter.top_instance().geo_blueprint.layout_patch_id).is_equal(str(_moved().layout_patch_id))
	assert_int(transport.requests.size()).is_equal(2)

func test_visitor_reloads_hosts_snapshot_without_changing_own_choice_or_assets() -> void:
	var own := FarmChoice.load()
	var transport := FakeTransport.new([{"status": 200, "json": _moved("host-farm")}])
	Net.use_transport(transport.callable())
	var source := AppRouter.push_instance(AppRouter.FARM, {"visitor": true, "snapshot": _old("host-farm"),
		"blueprint": FarmBlueprint.load_choice(_old("host-farm"))})
	source.set_meta("party_travel", true)
	await get_tree().process_frame
	source._on_farm_relocated()
	await get_tree().process_frame
	while AppRouter._navigation_pending: await get_tree().process_frame
	await get_tree().process_frame
	var next := AppRouter.top_instance()
	assert_bool(is_instance_valid(source)).is_false()
	assert_bool(next.visitor).is_true()
	assert_bool(next.has_meta("party_travel")).is_true()
	assert_str(next.snapshot.farm_id).is_equal("host-farm")
	assert_str(next.geo_blueprint.layout_patch_id).is_equal(str(_moved().layout_patch_id))
	assert_that(FarmChoice.load()).is_equal(own)
	assert_int(transport.requests.size()).is_equal(1)
	assert_str(transport.requests[0].url).ends_with("/farms/host-farm/snapshot")
	assert_bool(next._relocate_button.visible).is_false()

func test_suspended_owner_marks_geometry_stale_and_never_resumes_old_online_room() -> void:
	var source := await _owner(FakeTransport.new([]))
	var online := OnlineSpace.attach(source, null, "farm", {}, func(): return source.mover, func(): return "idle")
	online.set_process(false)
	source.online = online
	online.active = true
	source.suspend()
	assert_bool(online._suspended).is_true()
	source.session._adopt(_moved())
	assert_bool(source._terrain_stale).is_true()
	assert_str(source.geo_blueprint.layout_patch_id).is_equal("sh_b")
	source.resume()
	assert_bool(online.active).is_false()
	assert_bool(source.party_travel_ready()).is_false()
	# Prevent this failed-network fixture's deferred refresh from starting after assertions.
	source.suspend()
	await get_tree().process_frame
