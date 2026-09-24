extends GdUnitTestSuite

func _entries() -> Array:
	var seen := {}
	var entries := []
	for entry in SystemPonds.data().locations:
		if seen.has(entry.template_id): continue
		seen[entry.template_id] = true
		entries.append(entry)
	return entries

func test_fixed_catalog_and_three_city_shapes() -> void:
	assert_int(SystemPonds.data().locations.size()).is_equal(12)
	assert_int(SystemPonds.revision().length()).is_equal(64)
	for region in ["shanghai", "los_angeles"]:
		var entries: Array = SystemPonds.data().locations.filter(func(p): return p.region_id == region)
		var seen := {}
		for entry in entries: seen[entry.template_id] = true
		assert_int(seen.size()).is_equal(3)
		var payload := {"version": 1, "catalog_revision": SystemPonds.revision(), "available": true, "locations": entries}
		assert_int(SystemPonds.validated_locations(payload, region).size()).is_equal(6)
		payload.catalog_revision = "stale"
		assert_array(SystemPonds.validated_locations(payload, region)).is_empty()

func test_tampered_or_cross_city_entries_are_rejected() -> void:
	var row: Dictionary = SystemPonds.data().locations[0].duplicate(true)
	row.lat += .01
	var payload := {"version": 1, "catalog_revision": SystemPonds.revision(), "available": true, "locations": [row]}
	assert_array(SystemPonds.validated_locations(payload, str(row.region_id))).is_empty()
	assert_bool(SystemPonds.location("pond_unknown").is_empty()).is_true()

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
