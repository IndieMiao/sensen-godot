extends GdUnitTestSuite

const COMPACT := "res://tests/fixtures/generated_compact_farm_terrain.json"
const ORIGINAL := "res://tests/fixtures/generated_farm_terrain.json"

func _terrain(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func after_test() -> void:
	FarmChoice.clear()

func test_compact_server_checksum_navigation_and_fishing_agree_at_32_meters() -> void:
	var terrain := _terrain(COMPACT)
	var bp := FarmPlot.register_terrain(terrain)
	assert_object(bp).is_not_null()
	if bp == null: return
	assert_vector(bp.grid).is_equal(Vector2i(40, 40))
	assert_int(bp.cell_mm).is_equal(800)
	assert_float(bp.play_area_m).is_equal(32.0)
	assert_bool(FarmPlot.verify_checksum(bp)).is_true()
	assert_bool(bp.in_bounds(Vector2i(39, 39))).is_true()
	assert_bool(bp.in_bounds(Vector2i(40, 39))).is_false()
	for key in ["spawn", "exit", "house", "storage", "well", "mine", "stall"]:
		assert_bool(bp.in_bounds(bp.anchor(key))).is_true()
	var grid := BlueprintGrid.new(bp)
	var spawn := bp.cell_to_world(bp.anchor("spawn"))
	var mine := bp.cell_to_world(bp.anchor("mine") + Vector2i(0, -2))
	assert_array(grid.point_path(spawn, mine)).is_not_empty()
	assert_bool(FishingModel.plan("farm_pond", spawn, Vector3(6.4, 0, -26.4), grid).is_empty()).is_false()

func test_loading_compact_farm_keeps_original_geography_and_cached_choice_unchanged() -> void:
	var old := _terrain(ORIGINAL)
	var original := FarmPlot.register_terrain(old)
	var checksum := original.checksum
	var masks := original.masks.duplicate(true)
	var choice := {"layout_patch_id": old.layout_id, "revision": 1, "farm_terrain": old,
		"region_id": "shanghai", "location": old.source.center}
	FarmChoice.save_choice(choice)
	var stored := FarmChoice.load()
	assert_object(FarmPlot.register_terrain(_terrain(COMPACT))).is_not_null()
	assert_object(FarmPlot.register_terrain(old)).is_same(original)
	assert_vector(original.grid).is_equal(Vector2i(64, 64))
	assert_float(original.play_area_m).is_equal(48.0)
	assert_str(original.checksum).is_equal(checksum)
	assert_that(original.masks).is_equal(masks)
	assert_that(FarmChoice.load()).is_equal(stored)
	assert_float(FarmBlueprint.load_choice(stored).play_area_m).is_equal(48.0)

func test_compact_source_area_and_saved_original_area_use_their_own_grid_size() -> void:
	for path in [COMPACT, ORIGINAL]:
		var terrain := _terrain(path)
		var bp := FarmPlot.geography_for(terrain, "shanghai")
		assert_object(bp).is_not_null()
		if bp == null: continue
		var ring: PackedVector2Array = bp.overlay.blocks[0]
		var north_south_extent := absf(ring[2].x - ring[0].x) * FarmPlacement.METERS_PER_DEGREE
		assert_float(north_south_extent).is_equal_approx(float(terrain.source.extent_m), 1.0)
		var center_cell := Vector2.ONE * (float(bp.grid.x) * 0.5 - 0.5)
		assert_vector(FarmPlot._geographic_point(center_cell, bp.overlay.center, float(terrain.source.extent_m), bp.grid.x)).is_equal(bp.overlay.center)
		var private_terrain := terrain.duplicate(true)
		private_terrain.erase("source")
		var private_bp := FarmPlot.geography_for(private_terrain)
		assert_vector(private_bp.grid).is_equal(bp.grid)
		assert_array(private_bp.overlay.blocks).is_empty()

func test_compact_validation_rejects_wrong_dimensions_or_outside_anchors() -> void:
	var terrain := _terrain(COMPACT)
	assert_bool(FarmPlot._valid_source(terrain.plot)).is_true()
	for grid in [[40, 64], [48, 48], [39, 39], [40.5, 40.5], [32, 32]]:
		var invalid: Dictionary = terrain.plot.duplicate(true)
		invalid.grid = grid
		assert_bool(FarmPlot._valid_source(invalid)).is_false()
	for anchor in [[40, 28], [21, 40], [-1, 20], [21.5, 28]]:
		var invalid: Dictionary = terrain.plot.duplicate(true)
		invalid.anchors.mine = anchor
		assert_bool(FarmPlot._valid_source(invalid)).is_false()

func test_compact_surface_uses_40_pixel_state_and_32_meter_geometry() -> void:
	var bp := FarmPlot.register_terrain(_terrain(COMPACT))
	assert_object(bp).is_not_null()
	if bp == null: return
	var surface := auto_free(PlotSurface.new(bp)) as PlotSurface
	add_child(surface)
	assert_int(surface._image.get_width()).is_equal(40)
	assert_int(surface._image.get_height()).is_equal(40)
	assert_vector((surface.mesh as PlaneMesh).size).is_equal(Vector2(32, 32))
	assert_vector(surface._material.get_shader_parameter("grid_size")).is_equal(Vector2(40, 40))
	assert_vector((surface.get_node("GeographicWater").mesh as PlaneMesh).size).is_equal(Vector2(32, 32))
	var preview := auto_free(FarmRelocationPreview.new()) as FarmRelocationPreview
	add_child(preview)
	assert_bool(preview.configure({"farm_terrain": _terrain(COMPACT)}, "shanghai")).is_true()
	assert_str(preview.terrain_caption.text).contains("32 × 32")

func test_compact_water_shore_and_panel_keep_geometry_local_when_old_farm_is_also_loaded() -> void:
	var original := FishingModel.site("farm_pond").duplicate(true)
	var bp := FarmPlot.register_terrain(_terrain(COMPACT))
	var pond := FishingModel.site_for_plot("farm_pond", bp)
	var compact := auto_free(FishingWater.build("farm_pond", pond)) as FishingWater
	var legacy := auto_free(FishingWater.build("farm_pond")) as FishingWater
	var compact_mesh := compact.get_node("FishingWaterSurface") as MeshInstance3D
	var legacy_mesh := legacy.get_node("FishingWaterSurface") as MeshInstance3D
	assert_vector(compact_mesh.mesh.get_aabb().get_center()).is_equal_approx(Vector3(6.4, 0.055, -26.4), Vector3.ONE * 0.0001)
	assert_vector(legacy_mesh.mesh.get_aabb().get_center()).is_equal_approx(Vector3(9, 0.055, -30.75), Vector3.ONE * 0.0001)
	assert_that(compact.water_material.get_shader_parameter("basin")).is_equal(Vector4(6.4, -26.4, 3.84, 2.48))
	var bank := compact.get_node("NaturalWaterBank/BankStones") as MeshInstance3D
	var bank_center := bank.mesh.get_aabb().get_center()
	assert_float(absf(bank_center.x - 6.4)).is_less(0.5)
	assert_float(absf(bank_center.z + 26.4)).is_less(0.5)
	var surface := auto_free(PlotSurface.new(bp)) as PlotSurface
	add_child(surface)
	assert_bool(surface.get_node("GeographicWater").material_override.get_shader_parameter("exclude_farm_basin")).is_false()
	var panel := auto_free(FishingPanel.new()) as FishingPanel
	add_child(panel)
	var session := FarmSession.new(null)
	session.farm_id = "local-water-context"
	panel.open(session, "farm_pond", Vector3.INF, pond)
	assert_bool(FishingModel.contains("farm_pond", panel.landing, 0, pond)).is_true()
	assert_that(panel.site_spec.center).is_equal(pond.center)
	panel.open(session, "farm_pond")
	assert_that(panel.site_spec).is_equal(original)
	assert_bool(FishingModel.contains("farm_pond", panel.landing)).is_true()
	assert_that(FishingModel.site("farm_pond")).is_equal(original)
	await get_tree().process_frame

func test_compact_decoration_default_finds_free_ground_without_changing_old_catalog_or_assets() -> void:
	var bp := FarmPlot.register_terrain(_terrain(COMPACT))
	var original: Array = DecorationLayout.data().props.crate.default_cell.duplicate()
	assert_bool(bp.in_bounds(Vector2i(original[0], original[1]))).is_false()
	var first: Vector2i = DecorationLayout.first_position("crate", [], bp)
	assert_bool(DecorationLayout.cell_allowed(bp, {}, {}, "crate", first)).is_true()
	var planted := {"%d,%d" % [first.x, first.y]: {"crop": "R", "ready_at": 1923456789123}}
	var preserved := planted.duplicate(true)
	var second: Vector2i = DecorationLayout.first_position("crate", [], bp, planted)
	assert_vector(second).is_not_equal(first)
	assert_bool(DecorationLayout.cell_allowed(bp, planted, {}, "crate", second)).is_true()
	assert_that(planted).is_equal(preserved)
	assert_that(DecorationLayout.data().props.crate.default_cell).is_equal(original)
	assert_vector(DecorationLayout.first_position("crate", [])).is_equal(Vector2i(original[0], original[1]))
