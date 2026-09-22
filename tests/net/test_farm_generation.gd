extends GdUnitTestSuite

func _session(responses: Array) -> Array:
	var transport := FakeTransport.new(responses)
	return [FarmSession.new(ApiClient.new("https://farm-generation.test/v1", transport.callable())), transport]

func _terrain() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_compact_farm_terrain.json"))

func _body() -> Dictionary:
	var terrain := _terrain()
	return {"farm_id": "generated-farm", "layout_patch_id": terrain.layout_id, "blueprint_revision": 1,
		"region_id": "shanghai", "location": terrain.source.center, "farm_terrain": terrain,
		"version": 0, "state": {"wallet": 30}}

func after_test() -> void:
	FarmChoice.clear()

func test_map_generation_is_capability_gated_and_sends_no_template() -> void:
	var body := _body()
	var pair := _session([{ "status": 404, "json": {"code": "NO_FARM"}},
		{"status": 200, "json": {"farm_generation_version": 2}}, {"status": 201, "json": body}])
	var session: FarmSession = pair[0]
	var transport: FakeTransport = pair[1]
	assert_bool(await session.ensure_generated_farm("shanghai", body.location)).is_true()
	assert_int(int(transport.last_body().generation_version)).is_equal(2)
	assert_bool(transport.last_body().has("layout_patch_id")).is_false()
	assert_bool(transport.last_body().has("blueprint_revision")).is_false()
	assert_that(transport.last_body().location).is_equal(body.location)
	assert_that(session.farm_terrain).is_equal(body.farm_terrain)
	FarmChoice.save_choice(session.farm_choice())
	var restored := FarmBlueprint.load_choice(FarmChoice.load())
	assert_object(restored).is_not_null()
	if restored == null: return
	assert_str(restored.layout_patch_id).is_equal(str(body.layout_patch_id))

func test_old_server_cannot_silently_generate_from_a_template() -> void:
	var pair := _session([{"status": 404, "json": {}}, {"status": 200, "json": {"farm_placement_version": 1}}])
	var session: FarmSession = pair[0]
	assert_bool(await session.ensure_generated_farm("shanghai", {"lat": 31.23, "lng": 121.47})).is_false()
	assert_str(session.last_error_code).is_equal("GENERATION_UNSUPPORTED")
	assert_int(pair[1].requests.size()).is_equal(2)
	assert_bool(session.has_farm()).is_false()

func test_unsuitable_land_and_missing_data_never_adopt_or_cache_a_farm() -> void:
	for code in ["LOCATION_ALL_WATER", "LOCATION_ALL_DESERT", "LOCATION_UNSUITABLE", "GEOGRAPHY_UNAVAILABLE", "GEOGRAPHY_INCOMPLETE"]:
		var pair := _session([{"status": 404, "json": {}}, {"status": 200, "json": {"farm_generation_version": 2}},
			{"status": 503 if code == "GEOGRAPHY_UNAVAILABLE" else 422, "json": {"code": code}}])
		var session: FarmSession = pair[0]
		assert_bool(await session.ensure_generated_farm("shanghai", {"lat": 31.23, "lng": 121.47})).is_false()
		assert_str(session.last_error_code).is_equal(code)
		assert_bool(session.has_farm()).is_false()
		assert_bool(session.farm_terrain.is_empty()).is_true()
		assert_bool(FarmChoice.load().is_empty()).is_true()

func test_retry_after_lost_create_response_adopts_server_farm_without_regeneration() -> void:
	var body := _body()
	var pair := _session([{"status": 404, "json": {}}, {"status": 200, "json": {"farm_generation_version": 2}},
		{"error": "reply lost"}, {"status": 200, "json": body}])
	var session: FarmSession = pair[0]
	assert_bool(await session.ensure_generated_farm("shanghai", body.location)).is_false()
	assert_bool(await session.ensure_generated_farm("shanghai", {"lat": 31.24, "lng": 121.48})).is_true()
	assert_that(session.location).is_equal(body.location)
	assert_int(pair[1].requests.size()).is_equal(4)
	assert_str(pair[1].requests[3].method).is_equal("GET")

func test_old_farm_reuse_preserves_save_and_removes_generated_metadata() -> void:
	var state := {"wallet": 77, "cells": {"20,20": {"crop": "R", "ready_at": 123456}}}
	var pair := _session([{"status": 200, "json": {"farm_id": "legacy-farm", "layout_patch_id": "sh_b",
		"blueprint_revision": 2, "version": 8, "state": state}}])
	var session: FarmSession = pair[0]
	session.farm_terrain = _terrain()
	assert_bool(await session.ensure_generated_farm("shanghai", {"lat": 31.23, "lng": 121.47})).is_true()
	assert_str(session.layout_patch_id).is_equal("sh_b")
	assert_that(session.state).is_equal(state)
	assert_bool(session.farm_terrain.is_empty()).is_true()
	assert_int(pair[1].requests.size()).is_equal(1)

func test_party_visit_loads_private_generated_geometry_without_changing_own_farm() -> void:
	FarmChoice.save("sh_b", 2, {"lat": 31.23, "lng": 121.47})
	var saved := FarmChoice.load()
	var terrain := _terrain()
	terrain.erase("source")
	var session := FarmSession.new(ApiClient.new())
	session.farm_id = "my-farm"
	session.layout_patch_id = "sh_b"
	var snapshot := {"farm_id": "other-farm", "layout_patch_id": terrain.layout_id,
		"blueprint_revision": 1, "farm_terrain": terrain}
	var manifest := snapshot.duplicate(true)
	manifest.merge({"kind": "farm", "channel": 1, "ticket": "permission-checked-ticket", "snapshot": snapshot})
	var args := PartyTravel.scene_args(manifest, session)
	assert_bool(args.visitor).is_true()
	assert_object(args.blueprint).is_not_null()
	assert_str(args.blueprint.layout_patch_id).is_equal(str(terrain.layout_id))
	assert_str(args.online_join.travel_ticket).is_equal("permission-checked-ticket")
	assert_that(FarmChoice.load()).is_equal(saved)
	assert_str(session.layout_patch_id).is_equal("sh_b")
	assert_bool(args.snapshot.has("location")).is_false()
	assert_str(PartyTravel.scene_path(manifest)).is_equal(AppRouter.FARM)

func test_generated_farm_requires_matching_geometry_in_cached_choice() -> void:
	var body := _body()
	var choice := {"layout_patch_id": body.layout_patch_id, "revision": 1}
	assert_object(FarmBlueprint.load_choice(choice)).is_null()
	var pair := _session([{"status": 404, "json": {}}, {"status": 200, "json": {"farm_generation_version": 2}},
		{"status": 201, "json": choice.merged({"farm_id": "incomplete-farm", "version": 0, "state": {}})}])
	var session: FarmSession = pair[0]
	assert_bool(await session.ensure_generated_farm("shanghai", body.location)).is_false()
	assert_bool(session.has_farm()).is_false()
	assert_str(session.last_error_code).is_equal("INVALID_FARM_TERRAIN")

func test_generated_choice_rejects_mismatched_outer_layout_or_revision() -> void:
	var good := _body()
	assert_object(FarmBlueprint.load_choice(good)).is_not_null()
	for fields in [{"layout_patch_id": "geo_00000000000000000000"}, {"layout_patch_id": "sh_a"},
		{"blueprint_revision": 2}, {"blueprint_revision": 1.5}, {"revision": 2}, {"farm_terrain": "invalid"}]:
		assert_object(FarmBlueprint.load_choice(good.merged(fields, true))).is_null()
	var absent := good.duplicate(true)
	absent.erase("blueprint_revision")
	assert_object(FarmBlueprint.load_choice(absent)).is_null()

func test_malformed_existing_generated_farm_preserves_all_previously_valid_state() -> void:
	var malformed := _body()
	malformed.layout_patch_id = "geo_00000000000000000000"
	malformed.version = 9
	malformed.server_time = 999999
	var missing := _body()
	missing.erase("farm_terrain")
	for body in [malformed, missing]:
		var pair := _session([{"status": 200, "json": body}])
		var session: FarmSession = pair[0]
		var prior := {"farm_id": "original", "layout_patch_id": "sh_b", "blueprint_revision": 2,
			"region_id": "shanghai", "location": {"lat": 31.23, "lng": 121.47},
			"version": 7, "server_time": 123456, "state": {"wallet": 77, "cells": {"20,20": {"ready_at": 345678}}}}
		assert_bool(session._adopt(prior)).is_true()
		FarmChoice.save_choice(session.farm_choice())
		var saved := FarmChoice.load()
		assert_bool(await session.ensure_generated_farm("shanghai", prior.location)).is_false()
		assert_str(session.last_error_code).is_equal("INVALID_FARM_TERRAIN")
		assert_str(session.farm_id).is_equal("original")
		assert_str(session.layout_patch_id).is_equal("sh_b")
		assert_int(session.blueprint_revision).is_equal(2)
		assert_int(session.version).is_equal(7)
		assert_int(session._server_time_ms).is_equal(123456)
		assert_that(session.location).is_equal(prior.location)
		assert_that(session.state).is_equal(prior.state)
		assert_that(FarmChoice.load()).is_equal(saved)
		assert_int(pair[1].requests.size()).is_equal(1)

func test_generated_refresh_rejects_missing_metadata_and_recovers_with_valid_dto() -> void:
	var good := _body()
	var invalid := good.duplicate(true)
	invalid.erase("layout_patch_id")
	invalid.erase("farm_terrain")
	invalid.version = 3
	invalid.state.wallet = 500
	var pair := _session([{"status": 200, "json": invalid}, {"status": 200, "json": good}])
	var session: FarmSession = pair[0]
	assert_bool(session._adopt(good)).is_true()
	var before := session.farm_choice()
	assert_bool(await session.refresh()).is_false()
	assert_bool(session.offline).is_true()
	assert_that(session.farm_choice()).is_equal(before)
	assert_int(session.state.wallet).is_equal(30)
	assert_int(session.version).is_zero()
	assert_bool(await session.refresh()).is_true()
	assert_bool(session.offline).is_false()
	assert_that(session.farm_choice()).is_equal(before)

func test_generation_v1_server_cannot_silently_create_an_oversized_farm() -> void:
	var pair := _session([{"status": 404, "json": {}}, {"status": 200, "json": {"farm_generation_version": 1}}])
	var session: FarmSession = pair[0]
	assert_bool(await session.ensure_generated_farm("shanghai", {"lat": 31.23, "lng": 121.47})).is_false()
	assert_str(session.last_error_code).is_equal("GENERATION_UNSUPPORTED")
	assert_int(pair[1].requests.size()).is_equal(2)
	assert_bool(session.has_farm()).is_false()

func test_existing_v1_generated_farm_is_loaded_at_original_size_without_capability_request() -> void:
	var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_farm_terrain.json"))
	var body := {"farm_id": "saved-v1", "layout_patch_id": terrain.layout_id, "blueprint_revision": 1,
		"farm_terrain": terrain, "region_id": "shanghai", "location": terrain.source.center,
		"version": 12, "state": {"wallet": 187, "cells": {"50,50": {"crop": "R", "ready_at": 1923456789123}}}}
	var pair := _session([{"status": 200, "json": body}])
	var session: FarmSession = pair[0]
	assert_bool(await session.ensure_generated_farm("shanghai", {"lat": 31.23, "lng": 121.47})).is_true()
	assert_that(session.state).is_equal(body.state)
	assert_float(FarmBlueprint.load_choice(session.farm_choice()).play_area_m).is_equal(48.0)
	assert_int(pair[1].requests.size()).is_equal(1)
