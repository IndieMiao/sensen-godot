extends GdUnitTestSuite

func _entries() -> Array:
	var seen := {}
	var entries := []
	for entry in SystemPonds.data().locations:
		if seen.has(entry.template_id): continue
		seen[entry.template_id] = true
		entries.append(entry)
	return entries

func _cells_payload(cells: Dictionary) -> Dictionary:
	return {"version": 2, "catalog_revision": SystemPonds.revision(), "available": true, "cell_deg": 0.5, "cells": cells}

func _server_only(overrides := {}) -> Dictionary:
	var row := {"id": "pond_san_francisco_01", "region_id": "gn-5391959", "name": "Willow Pond", "kind": "pond",
		"category": "Fishing pond", "lat": 37.7695, "lng": -122.4863, "template_id": "gourd", "decoration_seed": 12345,
		"layout_revision": 1, "generation_version": 1, "enabled": true}
	row.merge(overrides, true)
	return row

func test_fixed_catalog_and_three_city_shapes() -> void:
	# Frozen: shipped builds compare this hash; new cities live on the server (tools/ponds/add_pond_locations.py).
	assert_str(SystemPonds.revision()).is_equal("2c6e2a2f5f6efa3742912257fa8a0b4844cbf89277e5867ac88157784770a187")
	assert_int(SystemPonds.data().locations.size()).is_equal(12)
	for region in ["shanghai", "los_angeles"]:
		var entries: Array = SystemPonds.data().locations.filter(func(p): return p.region_id == region)
		var seen := {}
		for entry in entries: seen[entry.template_id] = true
		assert_int(seen.size()).is_equal(3)

func test_cells_match_the_server_grid() -> void:
	assert_str(SystemPonds.cell_key(SystemPonds.cell_of(37.7694, -122.4862))).is_equal("75:-245")
	assert_str(SystemPonds.cell_key(SystemPonds.cell_of(31.2145, 121.5558))).is_equal("62:243")
	assert_str(SystemPonds.cell_key(SystemPonds.cell_of(-0.2, -0.2))).is_equal("-1:-1")

func test_cell_directory_accepts_bundled_and_server_only_ponds() -> void:
	var bundled: Dictionary = SystemPonds.data().locations[0]
	var sf := _server_only()
	var cells := SystemPonds.validated_cells(_cells_payload({"1:1": [bundled, sf, sf], "2:2": []}), ["1:1", "2:2"])
	assert_array(cells["1:1"].map(func(e): return e.id)).is_equal([bundled.id, sf.id])
	assert_array(cells["2:2"]).is_empty()
	var entered := SystemPonds.location(sf.id)
	assert_str(str(entered.template_id)).is_equal("gourd")
	assert_bool(SystemPonds.site(entered).is_empty()).is_false()
	assert_object(SystemPonds.blueprint(entered)).is_not_null()
	var stale := _cells_payload({"1:1": [sf]})
	stale.catalog_revision = "stale"
	assert_dict(SystemPonds.validated_cells(stale, ["1:1"])).is_empty()
	var missing := SystemPonds.validated_cells(_cells_payload({}), ["1:1"])
	assert_dict(missing).is_empty()

func test_tampered_or_unhostable_records_are_rejected() -> void:
	var row: Dictionary = SystemPonds.data().locations[0].duplicate(true)
	row.lat += .01
	assert_dict(SystemPonds.accept(row)).is_empty()
	assert_dict(SystemPonds.accept(_server_only({"id": "pond_nowhere_01", "template_id": "lagoon"}))).is_empty()
	assert_dict(SystemPonds.accept(_server_only({"id": "pond_nowhere_02", "layout_revision": 2}))).is_empty()
	assert_dict(SystemPonds.accept(_server_only({"id": "pond_nowhere_03", "enabled": false}))).is_empty()
	assert_dict(SystemPonds.accept(_server_only({"id": "../pond"}))).is_empty()
	for id in ["pond_nowhere_01", "pond_nowhere_02", "pond_nowhere_03", "../pond", "pond_unknown"]:
		assert_bool(SystemPonds.location(id).is_empty()).is_true()

func test_party_ticket_carries_a_server_only_pond() -> void:
	var sf := _server_only({"id": "pond_san_francisco_04", "template_id": "crescent"})
	var args := PartyTravel.scene_args({"kind": "pond", "ticket": "t", "farm_id": sf.id, "channel": 2,
		"pond_id": sf.id, "catalog_revision": SystemPonds.revision(), "pond": sf}, null)
	assert_str(str(args.get("pond_id", ""))).is_equal(sf.id)
	assert_str(str(SystemPonds.location(sf.id).template_id)).is_equal("crescent")

func test_all_shapes_have_reachable_shores_and_continuous_casts() -> void:
	for entry in _entries():
		var bp := SystemPonds.blueprint(entry)
		var grid := BlueprintGrid.new(bp)
		var spec := SystemPonds.site(entry)
		var spawn := bp.cell_to_world(bp.anchor("spawn"))
		assert_bool(bp.is_walkable(bp.anchor("spawn"))).is_true()
		var plan := FishingModel.plan(str(entry.id), spawn, Vector3.INF, grid, spec)
		assert_bool(plan.is_empty()).is_false()
		assert_bool(FishingModel.valid_cast(str(entry.id), plan.origin, plan.target, grid, spec)).is_true()
		assert_bool(FishingModel.valid_cast(str(entry.id), plan.target, plan.target, grid, spec)).is_false()
		assert_bool(grid.point_path(spawn, plan.origin).is_empty()).is_false()
		for y in range(0, bp.grid.y, 2):
			for x in range(0, bp.grid.x, 2):
				var cell := Vector2i(x, y)
				if FishingModel.contains(str(entry.id), bp.cell_to_world(cell), 0, spec): assert_bool(bp.is_walkable(cell)).is_false()

func test_scene_water_uses_the_matching_polygon_depth_and_preview() -> void:
	for entry in _entries():
		var water: FishingWater = auto_free(FishingWater.build(str(entry.id), SystemPonds.site(entry)))
		assert_bool(water.water_material.get_shader_parameter("polygon_water")).is_true()
		assert_object(water.get_node("FishingWaterSurface").mesh).is_not_null()
		assert_object(SystemPonds.texture(str(entry.template_id))).is_not_null()
		assert_int(water.get_node("NaturalWaterBank").get_child_count()).is_equal(3)

func test_scene_loads_saved_outfit_and_free_camera_without_farming() -> void:
	var scene: FishingPondScene = auto_free(load(SystemPonds.SCENE).instantiate())
	scene.setup({"pond_id": str(SystemPonds.data().locations[0].id), "session": null})
	add_child(scene)
	await await_idle_frame()
	assert_bool(scene.camera_pan.free_pan).is_true()
	assert_bool(scene.site_spec.space == "pond").is_true()
	assert_object(scene.player).is_not_null()
	assert_object(scene.fishing_panel).is_not_null()
	assert_object(scene.online).is_null()
	assert_bool(scene.is_back_navigation_locked()).is_false()
	assert_bool(scene.ui.get_node("PondFish").visible).is_true()
	var position := scene.mover.position
	scene.toggle_overview()
	assert_bool(scene._overview).is_true()
	assert_vector(scene.mover.position).is_equal(position)

func test_camera_gestures_stop_on_background_and_recenter_without_moving_player() -> void:
	var scene: FishingPondScene = auto_free(load(SystemPonds.SCENE).instantiate())
	scene.setup({"pond_id": str(SystemPonds.data().locations[0].id), "session": null})
	add_child(scene)
	await await_idle_frame()
	var start := scene.mover.position
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.position = Vector2(120, 300)
	press.pressed = true
	scene._unhandled_input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(230, 360)
	drag.relative = Vector2(110, 60)
	scene.camera_pan.step(.04, scene.cam)
	scene._input(drag)
	assert_bool(scene.camera_pan.dragged).is_true()
	var second := InputEventScreenTouch.new()
	second.index = 1
	second.position = Vector2(290, 360)
	second.pressed = true
	scene._unhandled_input(second)
	drag.index = 1
	drag.position = Vector2(335, 360)
	drag.relative = Vector2(45, 0)
	scene._input(drag)
	assert_float(scene.camera_pan.zoom).is_greater(1.0)
	scene._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_int(scene.camera_pan.pointers.size()).is_equal(0)
	assert_vector(scene.camera_pan.velocity).is_equal(Vector3.ZERO)
	assert_vector(scene.mover.position).is_equal(start)
	scene.camera_pan.offset = Vector3(40, 0, 0)
	scene._update_camera()
	assert_bool(scene._focus_button.visible).is_true()
	scene.recenter_on_player()
	await await_millis(450)
	assert_float(scene._focus.distance_to(start)).is_less(.01)
	assert_vector(scene.mover.position).is_equal(start)
