extends GdUnitTestSuite
## Real Shanghai blueprints have different server coordinates but share one playable interior.

const FARM_SCENE := "res://scenes/farm/farm.tscn"
const SOURCE_IDS := {
	"sh_a": ["26,42", "27,42", "28,42", "25,40", "26,40", "27,40", "30,43", "31,43", "32,43", "24,46", "25,46", "26,46"],
	"sh_b": ["30,32", "31,32", "32,32", "30,28", "31,28", "32,28", "30,34", "31,34", "32,34", "34,33", "35,33", "36,33"],
	"sh_c": ["40,34", "41,34", "42,34", "39,36", "40,36", "41,36", "40,32", "41,32", "42,32", "46,35", "47,35", "48,35"],
}
const LOCAL_IDS := ["4,8", "6,8", "8,8", "4,6", "6,6", "8,6", "4,4", "6,4", "8,4", "4,2", "6,2", "8,2"]

func after_test() -> void:
	FarmChoice.clear()
	Net.use_transport(FakeTransport.new([]).callable())
	Net.client.token = ""

func _source(id: String) -> FarmBlueprint:
	return FarmBlueprint.load_file(FarmBlueprint.asset_path(id, 2))

func _state(id: String) -> Dictionary:
	var cells := {}
	for source_id in SOURCE_IDS[id]:
		cells[source_id] = {"state": "wild", "crop": null, "ready_at": null, "care_weather": null}
	return {"cells": cells, "beds_unlocked": 3, "wallet": 180,
		"inventory": {"seeds": {"R": {"bound": 6, "bought": 0}, "L": {"bound": 3, "bought": 0}}, "produce": {}},
		"clock": {"chapter_index": 0, "weather_day_index": 0, "field_condition": "sunny"},
		"xp": {"total": 0, "first_clear_cells": [], "first_harvest_crops": []}, "stall": {"settled": 0}}

func _session(id: String, transport: FakeTransport) -> FarmSession:
	var session := FarmSession.new(ApiClient.new("https://example.test/v1", transport.callable()))
	session.client.token = "tok"
	session.farm_id = "owner-%s" % id
	session.layout_patch_id = id
	session.blueprint_revision = 2
	session.region_id = "shanghai"
	session.version = 0
	session.state = _state(id)
	return session

func _farm(session: FarmSession) -> Node:
	var scene := (load(FARM_SCENE) as PackedScene).instantiate()
	scene.setup({"blueprint": _source(session.layout_patch_id), "session": session})
	add_child(auto_free(scene))
	await get_tree().process_frame
	return scene

func test_all_twelve_real_cells_have_unique_round_trip_mapping() -> void:
	for id in SOURCE_IDS:
		var source := _source(id)
		var before := source.canonical()
		var interior := FarmInterior.new(source)
		var local := interior.local_cells(_state(id).cells)
		assert_int(local.size()).is_equal(12)
		assert_array(local.keys()).contains(LOCAL_IDS)
		for i in LOCAL_IDS.size():
			assert_str(interior.source_id(LOCAL_IDS[i])).override_failure_message("%s local %s" % [id, LOCAL_IDS[i]]).is_equal(SOURCE_IDS[id][i])
		var payload := interior.server_payload({"cell_ids": LOCAL_IDS, "crop": "R", "lot": "bound"})
		assert_array(payload.cell_ids).is_equal(SOURCE_IDS[id])
		assert_str(payload.crop).is_equal("R")
		assert_str(payload.lot).is_equal("bound")
		assert_str(source.canonical()).is_equal(before)
		assert_str(interior.blueprint.layout_patch_id).is_equal(id)
		assert_int(interior.blueprint.revision).is_equal(2)
		assert_str(interior.source_id("0,0")).is_empty()

func test_state_translation_preserves_server_values_without_aliasing() -> void:
	for id in SOURCE_IDS:
		var interior := FarmInterior.new(_source(id))
		var source_cells: Dictionary = _state(id).cells
		var source_id: String = SOURCE_IDS[id][0]
		source_cells[source_id] = {"state": "growing", "crop": "L", "care_weather": "wind",
			"care_done_at": 1700000000123, "ready_at": 1700000045123, "careful": true, "tutorial": false,
			"metadata": {"revision": 7}}
		source_cells["0,0"] = {"state": "wild"}
		var original := source_cells.duplicate(true)
		var translated := interior.local_cells(source_cells)
		assert_int(translated.size()).is_equal(12)
		assert_that(translated["4,8"]).is_equal(source_cells[source_id])
		translated["4,8"].metadata.revision = 9
		translated["4,8"].state = "tilled"
		assert_that(source_cells).is_equal(original)

func test_expansion_unlocks_only_the_three_reserved_cells() -> void:
	for id in SOURCE_IDS:
		var interior := FarmInterior.new(_source(id))
		var predictor := CellPredictor.from_blueprint(interior.blueprint, interior.local_cells(_state(id).cells))
		assert_int(LOCAL_IDS.filter(func(cell): return predictor.is_unlocked(cell)).size()).is_equal(9)
		for cell in LOCAL_IDS.slice(9):
			assert_str(predictor.check("clear_cells", {"cell_ids": [cell]}, 0).error).is_equal("CELL_LOCKED")
		predictor.beds_unlocked = 4
		assert_int(LOCAL_IDS.filter(func(cell): return predictor.is_unlocked(cell)).size()).is_equal(12)
		var payload := interior.server_payload({"cell_ids": LOCAL_IDS.slice(9)})
		assert_array(payload.cell_ids).is_equal(SOURCE_IDS[id].slice(9))

func test_every_plot_has_a_reachable_working_edge_and_cannot_be_walked_through() -> void:
	for id in SOURCE_IDS:
		var bp := FarmInterior.new(_source(id)).blueprint
		var grid := BlueprintGrid.new(bp)
		var beds := bp.beds().duplicate()
		beds.append(bp.reserved_bed())
		for bed in beds:
			for cell in bed.cells:
				assert_bool(bp.is_walkable(cell)).is_false()
				var reachable := false
				for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var stand: Vector2i = cell + delta
					if bp.is_walkable(stand) and not grid.path(bp.anchor("spawn"), stand).is_empty():
						reachable = true
				assert_bool(reachable).override_failure_message("%s: plot %s has no working edge" % [id, cell]).is_true()

func test_custom_map_locations_do_not_migrate_logical_cells_or_change_command_ids() -> void:
	for id in SOURCE_IDS:
		var source := _source(id)
		var original_center: Vector2 = source.overlay.center
		var placed := source.with_location({"lat": 31.235123, "lng": 121.480456})
		var interior := FarmInterior.new(placed)
		assert_vector(interior.blueprint.overlay.center).is_equal(placed.overlay.center)
		assert_vector(source.overlay.center).is_equal(original_center)
		assert_array(interior.server_payload({"cell_ids": LOCAL_IDS}).cell_ids).is_equal(SOURCE_IDS[id])
		interior.blueprint.overlay.center = Vector2.ZERO
		assert_vector(placed.overlay.center).is_not_equal(Vector2.ZERO)

func test_snapshot_translation_preserves_order_and_frozen_stage_without_mutating_input() -> void:
	for id in SOURCE_IDS:
		var snapshot := []
		for i in 9:
			snapshot.append({"cell_id": SOURCE_IDS[id][i], "crop": "R" if i < 6 else "L", "state": "growing", "ripe": i < 6})
		snapshot.append({"cell_id": "0,0", "crop": "C", "state": "growing", "ripe": true})
		var original := snapshot.duplicate(true)
		var translated := FarmInterior.new(_source(id)).local_snapshot(snapshot)
		assert_int(translated.size()).is_equal(9)
		assert_array(translated.map(func(cell): return cell.cell_id)).is_equal(LOCAL_IDS.slice(0, 9))
		assert_int(translated.filter(func(cell): return cell.ripe).size()).is_equal(6)
		translated[0].crop = "H"
		assert_that(snapshot).is_equal(original)

func _assert_command_round_trip(id: String) -> void:
	var first_source: String = SOURCE_IDS[id][0]
	var accepted := _state(id)
	accepted.cells[first_source].state = "cleared"
	var transport := FakeTransport.new([
		{"status": 200, "json": {"version": 1, "state": accepted}},
		{"status": 422, "json": {"code": "WRONG_STATE"}},
	])
	var session := _session(id, transport)
	var farm := await _farm(session)
	await farm._on_cell_done(Vector2i(4, 8), "clear")
	assert_int(transport.requests.size()).is_equal(1)
	assert_array(transport.requests[0].body.payload.cell_ids).is_equal([first_source])
	assert_str(farm.predictor.view()["4,8"].state).is_equal("cleared")
	assert_int(farm.predictor.view().size()).is_equal(12)
	assert_bool(farm.predictor.view().has(first_source)).is_false()
	assert_str(session.state.cells[first_source].state).is_equal("cleared")
	assert_bool(session.state.cells.has("4,8")).is_false()
	await farm._on_cell_done(Vector2i(6, 8), "clear")
	assert_array(transport.requests[1].body.payload.cell_ids).is_equal([SOURCE_IDS[id][1]])
	assert_str(farm.predictor.view()["6,8"].state).is_equal("wild")
	assert_str(farm.predictor.view()["4,8"].state).is_equal("cleared")
	assert_bool(farm.predictor.has_pending()).is_false()

func test_sh_a_command_and_rollback_keep_the_correct_source_cell() -> void:
	await _assert_command_round_trip("sh_a")

func test_sh_b_command_and_rollback_keep_the_correct_source_cell() -> void:
	await _assert_command_round_trip("sh_b")

func test_sh_c_command_and_rollback_keep_the_correct_source_cell() -> void:
	await _assert_command_round_trip("sh_c")

func test_director_response_keeps_local_plot_ids_and_weather_for_the_next_action() -> void:
	var state := _state("sh_c")
	state.cells["40,34"] = {"state": "sown", "crop": "R", "care_weather": "sunny", "ready_at": null}
	state.clock.field_condition = "rain"
	var transport := FakeTransport.new([{"status": 200, "json": {"version": 1, "state": state}}])
	var farm := await _farm(_session("sh_c", transport))
	await farm._on_director_command("qa_set_weather", {"day": "rain"})
	assert_array(farm.predictor.view().keys()).contains(LOCAL_IDS)
	assert_int(farm._actionable_view().size()).is_equal(9)
	assert_str(farm.predictor.view()["4,8"].state).is_equal("sown")
	assert_str(farm._payload_for("care", ["4,8"]).kind).is_equal("water")

func test_visitor_translation_cannot_change_the_owners_session_or_snapshot() -> void:
	var transport := FakeTransport.new([])
	Net.use_transport(transport.callable())
	Net.session = _session("sh_c", transport)
	var owner_before := Net.session.state.duplicate(true)
	var snapshot := PresetSnapshots.snapshot(str(PresetSnapshots.entries("shanghai")[0].farm_id))
	var original := snapshot.duplicate(true)
	var source := _source(str(snapshot.layout_patch_id))
	var farm := (load(FARM_SCENE) as PackedScene).instantiate()
	farm.setup({"blueprint": source, "snapshot": snapshot, "visitor": true})
	add_child(auto_free(farm))
	await get_tree().process_frame
	assert_object(farm.session).is_null()
	assert_object(farm.predictor).is_null()
	assert_str(farm.bp.layout_patch_id).is_equal(str(snapshot.layout_patch_id))
	assert_int(farm._queue_plots([Vector2i(4, 8)])).is_equal(0)
	farm._wave()
	farm._stamp()
	assert_int(transport.requests.size()).is_equal(0)
	assert_that(Net.session.state).is_equal(owner_before)
	assert_that(snapshot).is_equal(original)
	assert_that(farm.snapshot).is_equal(original)
