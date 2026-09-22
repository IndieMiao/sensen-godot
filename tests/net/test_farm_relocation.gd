extends GdUnitTestSuite

var _directory := ""

func before_test() -> void:
	_directory = "user://test_relocation_" + Crypto.new().generate_random_bytes(8).hex_encode()

func after_test() -> void:
	for directory in [_directory.path_join("relocations"), _directory]:
		if not DirAccess.dir_exists_absolute(directory): continue
		for file in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(file))
		DirAccess.remove_absolute(directory)

func _old() -> Dictionary:
	return {"farm_id": "old-farm", "region_id": "shanghai", "layout_patch_id": "sh_b", "blueprint_revision": 2,
		"version": 8, "state": {"wallet": 187, "cells": {"20,20": {"crop": "R", "ready_at": 1923456789123}}},
		"relocation": {"available": true, "used": false}}

func _preview() -> Dictionary:
	var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_farm_terrain.json"))
	return {"preview_id": "preview-1", "base_version": 8, "expires_at": 1923456789123,
		"farm_terrain": terrain, "location": terrain.source.center, "moved_cells": 1, "moved_decorations": 0}

func _confirmed() -> Dictionary:
	var body := _old()
	body.merge({"farm_terrain": _preview().farm_terrain, "layout_patch_id": _preview().farm_terrain.layout_id,
		"blueprint_revision": 1, "version": 9, "location": _preview().location,
		"relocation": {"available": false, "used": true}}, true)
	return body

func _session(responses: Array) -> Array:
	var transport := FakeTransport.new(responses)
	var session := FarmSession.new(ApiClient.new("https://relocation.test/v1", transport.callable()), _directory)
	session._adopt(_old())
	return [session, transport]

func test_preview_keeps_current_farm_and_roundtrips_precise_coordinates() -> void:
	var pair := _session([{"status": 200, "json": {"farm_generation_version": 2}}, {"status": 200, "json": _preview()}])
	var session: FarmSession = pair[0]
	var placement := {"lat": 31.234567, "lng": 121.456789}
	assert_bool((await session.preview_relocation("shanghai", placement)).is_empty()).is_false()
	assert_that(pair[1].last_body().location).is_equal(placement)
	assert_int(int(pair[1].last_body().generation_version)).is_equal(2)
	assert_str(session.layout_patch_id).is_equal("sh_b")
	assert_int(session.version).is_equal(8)
	assert_that(session.state).is_equal(_old().state)
	assert_bool(session.relocation_available()).is_true()

func test_missing_capability_and_wrong_city_cannot_submit_relocation() -> void:
	var pair := _session([])
	var session: FarmSession = pair[0]
	assert_bool((await session.preview_relocation("tokyo", _preview().location)).is_empty()).is_true()
	assert_str(session.last_error_code).is_equal("LOCATION_OUTSIDE_REGION")
	session._adopt(_old().merged({"relocation": {}}, true))
	assert_bool((await session.preview_relocation("shanghai", _preview().location)).is_empty()).is_true()
	assert_str(session.last_error_code).is_equal("RELOCATION_UNAVAILABLE")
	assert_int(pair[1].requests.size()).is_zero()

func test_invalid_land_and_data_leave_entitlement_and_assets_intact() -> void:
	for code in ["LOCATION_ALL_WATER", "LOCATION_ALL_DESERT", "GEOGRAPHY_UNAVAILABLE", "GEOGRAPHY_INCOMPLETE", "RELOCATION_NO_SPACE"]:
		var pair := _session([{"status": 200, "json": {"farm_generation_version": 2}}, {"status": 422, "json": {"code": code}}])
		var session: FarmSession = pair[0]
		assert_bool((await session.preview_relocation("shanghai", _preview().location)).is_empty()).is_true()
		assert_str(session.last_error_code).is_equal(code)
		assert_that(session.state).is_equal(_old().state)
		assert_bool(session.relocation_available()).is_true()
		assert_bool(session.farm_terrain.is_empty()).is_true()

func test_uncertain_confirm_blocks_writes_and_retries_exact_request() -> void:
	var pair := _session([{"error": "lost"}, {"error": "lost"}, {"status": 200, "json": _confirmed()}])
	var session: FarmSession = pair[0]
	assert_bool(await session.confirm_relocation(_preview())).is_false()
	assert_bool(session.relocation_pending()).is_true()
	assert_bool(await session.send("buy_seeds", {"crop": "R", "qty": 1})).is_false()
	assert_bool(await session.confirm_relocation({"preview_id": "different", "base_version": 100})).is_true()
	assert_int(pair[1].requests.size()).is_equal(3)
	assert_that(pair[1].requests[0].body).is_equal(pair[1].requests[1].body)
	assert_that(pair[1].requests[0].body).is_equal(pair[1].requests[2].body)
	assert_bool(session.relocation_pending()).is_false()
	assert_bool(session.relocation_available()).is_false()
	assert_that(session.state).is_equal(_old().state)

func test_conflict_resolves_pending_but_keeps_old_farm_and_chance() -> void:
	var pair := _session([{"status": 409, "json": {"code": "RELOCATION_CONFLICT"}}])
	var session: FarmSession = pair[0]
	assert_bool(await session.confirm_relocation(_preview())).is_false()
	assert_bool(session.relocation_pending()).is_false()
	assert_bool(session.relocation_available()).is_true()
	assert_str(session.layout_patch_id).is_equal("sh_b")

func test_restart_recovers_same_persisted_confirmation_before_other_writes() -> void:
	var transport := FakeTransport.new([{"status": 200, "json": {"player_id": "p", "token": "t"}},
		{"status": 200, "json": _old()}, {"error": "lost"}, {"error": "lost"}])
	var session := FarmSession.new(ApiClient.new("https://relocation.test/v1", transport.callable()), _directory)
	assert_bool(await session.login()).is_true()
	assert_bool(await session.refresh()).is_true()
	assert_bool(await session.confirm_relocation(_preview())).is_false()
	var envelope: Dictionary = transport.last_body().duplicate(true)
	var recovery := FakeTransport.new([{"status": 200, "json": {"player_id": "p", "token": "t"}},
		{"status": 200, "json": _confirmed()}, {"status": 200, "json": _confirmed()}])
	var restarted := FarmSession.new(ApiClient.new("https://relocation.test/v1", recovery.callable()), _directory)
	assert_bool(await restarted.login()).is_true()
	assert_bool(await restarted.refresh()).is_true()
	assert_that(recovery.last_body()).is_equal(envelope)
	assert_bool(restarted.has_unconfirmed_command()).is_false()
	assert_bool(restarted.relocation_available()).is_false()
	assert_str(restarted.farm_id).is_equal("old-farm")
	assert_int(restarted.state.wallet).is_equal(187)

signal release_first_write

func _send_intent(session: FarmSession, result: Dictionary) -> void:
	result.accepted = await session.send("till_cells", {"cell_ids": ["20,20"]})

func test_version_conflict_from_relocation_never_rebases_old_coordinate_intent() -> void:
	var moved := _confirmed().merged({"code": "VERSION_CONFLICT"}, true)
	var pair := _session([{"status": 409, "json": moved}])
	var session: FarmSession = pair[0]
	assert_bool(await session.send("till_cells", {"cell_ids": ["20,20"]})).is_false()
	assert_str(session.last_error_code).is_equal("FARM_RELOCATED")
	assert_int(pair[1].requests.size()).is_equal(1)
	assert_str(session.layout_patch_id).is_equal(str(_confirmed().layout_patch_id))
	assert_bool(session.has_unconfirmed_command()).is_false()

func test_generated_coordinate_write_keeps_checksum_through_conflict_and_lost_reply() -> void:
	var state := _confirmed()
	var pair := _session([{"status": 409, "json": state.merged({"version": 10, "code": "VERSION_CONFLICT"}, true)},
		{"error": "lost"}, {"status": 200, "json": state.merged({"version": 11, "outcome": "applied"}, true)}])
	var session: FarmSession = pair[0]
	session._adopt(state)
	assert_bool(await session.send("save_decorations", {"placements": []})).is_true()
	assert_int(pair[1].requests.size()).is_equal(3)
	for request in pair[1].requests:
		assert_str(request.body.terrain_checksum).is_equal(str(state.farm_terrain.plot.checksum))
	assert_that(pair[1].requests[1].body).is_equal(pair[1].requests[2].body)
	assert_str(pair[1].requests[0].body.idempotency_key).is_not_equal(pair[1].requests[1].body.idempotency_key)

func test_queued_intent_cannot_silently_target_a_relocated_map() -> void:
	var session := _session([])[0] as FarmSession
	var requests := []
	session.client.transport = func(_method, _url, _headers, body):
		requests.append(JSON.parse_string(body))
		await release_first_write
		return ApiClient.Response.new(true, 409, _confirmed().merged({"code": "VERSION_CONFLICT"}, true))
	var first := {}
	var second := {}
	_send_intent(session, first)
	_send_intent(session, second)
	await get_tree().process_frame
	release_first_write.emit()
	for index in 3: await get_tree().process_frame
	assert_that(first).is_equal({"accepted": false})
	assert_that(second).is_equal({"accepted": false})
	assert_int(requests.size()).is_equal(1)
	assert_str(session.last_error_code).is_equal("FARM_RELOCATED")

func test_server_geometry_guard_refreshes_authoritative_dto_without_retrying_write() -> void:
	var pair := _session([{"status": 422, "json": {"code": "FARM_RELOCATED"}}, {"status": 200, "json": _confirmed()}])
	var session: FarmSession = pair[0]
	assert_bool(await session.send("till_cells", {"cell_ids": ["20,20"]})).is_false()
	assert_str(session.last_error_code).is_equal("FARM_RELOCATED")
	assert_that(pair[1].requests.map(func(request): return request.method)).is_equal(["POST", "GET"])
	assert_str(session.layout_patch_id).is_equal(str(_confirmed().layout_patch_id))

func test_restart_retains_geometry_checksum_in_unconfirmed_coordinate_command() -> void:
	var current := _confirmed()
	var first := FakeTransport.new([{"status": 200, "json": {"player_id": "p", "token": "t"}},
		{"status": 200, "json": current}, {"error": "lost"}, {"error": "lost"}])
	var session := FarmSession.new(ApiClient.new("https://relocation.test/v1", first.callable()), _directory)
	await session.login()
	await session.refresh()
	assert_bool(await session.send("till_cells", {"cell_ids": ["20,20"]})).is_false()
	var sent: Dictionary = first.last_body().duplicate(true)
	assert_str(sent.terrain_checksum).is_equal(str(current.farm_terrain.plot.checksum))
	var committed := current.merged({"version": 10, "outcome": "applied"}, true)
	var second := FakeTransport.new([{"status": 200, "json": {"player_id": "p", "token": "t"}},
		{"status": 200, "json": current}, {"status": 200, "json": committed}, {"status": 200, "json": committed}])
	var restarted := FarmSession.new(ApiClient.new("https://relocation.test/v1", second.callable()), _directory)
	await restarted.login()
	assert_bool(await restarted.refresh()).is_true()
	assert_that(second.requests[2].body).is_equal(sent)
	assert_bool(restarted.has_unconfirmed_command()).is_false()
	assert_int(restarted.version).is_equal(10)

func test_older_generator_cannot_preview_relocation_at_a_different_size() -> void:
	var pair := _session([{"status": 200, "json": {"farm_generation_version": 1}}])
	var session: FarmSession = pair[0]
	assert_bool((await session.preview_relocation("shanghai", _preview().location)).is_empty()).is_true()
	assert_str(session.last_error_code).is_equal("GENERATION_UNSUPPORTED")
	assert_int(pair[1].requests.size()).is_equal(1)
	assert_str(pair[1].requests[0].method).is_equal("GET")
	assert_bool(session.relocation_available()).is_true()
	assert_that(session.state).is_equal(_old().state)

func test_compact_relocation_preview_does_not_resize_legacy_state_until_confirmed() -> void:
	var preview := _preview()
	preview.farm_terrain = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_compact_farm_terrain.json"))
	var pair := _session([{"status": 200, "json": {"farm_generation_version": 2}}, {"status": 200, "json": preview}])
	var session: FarmSession = pair[0]
	var result := await session.preview_relocation("shanghai", preview.location)
	assert_int(int(pair[1].last_body().generation_version)).is_equal(2)
	assert_float(FarmSession.relocation_blueprint(result, "shanghai").play_area_m).is_equal(32.0)
	assert_str(session.layout_patch_id).is_equal("sh_b")
	assert_that(session.state).is_equal(_old().state)
	assert_bool(session.relocation_available()).is_true()

func test_successful_preview_with_invalid_geometry_has_its_own_error_and_keeps_quota() -> void:
	var invalid := _preview()
	invalid.farm_terrain.plot.checksum = "0".repeat(64)
	var pair := _session([{"status": 200, "json": {"farm_generation_version": 2}}, {"status": 200, "json": invalid}])
	var session: FarmSession = pair[0]
	var location := {"lat": 31.234567, "lng": 121.456789}
	assert_bool((await session.preview_relocation("shanghai", location)).is_empty()).is_true()
	assert_str(session.last_error_code).is_equal("INVALID_FARM_TERRAIN")
	assert_bool(session.relocation_available()).is_true()
	assert_bool(session.relocation_pending()).is_false()
	assert_bool(session.offline).is_false()
	assert_that(session.state).is_equal(_old().state)
	assert_str(session.layout_patch_id).is_equal("sh_b")
	assert_that(pair[1].last_body().location).is_equal(location)
