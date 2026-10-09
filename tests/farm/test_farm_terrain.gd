extends GdUnitTestSuite

const FIXTURE := "res://tests/fixtures/generated_farm_terrain.json"

func _terrain() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))

func test_server_generated_layout_matches_checksum_and_preserves_required_facilities() -> void:
	var terrain := _terrain()
	var bp := FarmPlot.register_terrain(terrain)
	assert_object(bp).is_not_null()
	if bp == null: return
	assert_bool(FarmPlot.verify_checksum(bp)).is_true()
	assert_float(bp.play_area_m).is_equal(48.0)
	assert_int(bp.cell_mm).is_equal(750)
	assert_str(FarmPlot.kind_at(bp.layout_patch_id, Vector2i(42, 44))).is_equal("water")
	assert_str(FarmPlot.kind_at(bp.layout_patch_id, Vector2i(46, 47))).is_equal("soil")
	assert_str(FarmPlot.kind_at(bp.layout_patch_id, Vector2i(38, 10))).is_equal("lawn")
	var grid := BlueprintGrid.new(bp)
	var spawn := bp.cell_to_world(bp.anchor("spawn"))
	var mine := bp.cell_to_world(bp.anchor("mine") + Vector2i(0, -2))
	assert_array(grid.point_path(spawn, mine)).is_not_empty()
	assert_bool(FishingModel.plan("farm_pond", spawn, Vector3(9, 0, -29), grid).is_empty()).is_false()

func test_generated_geography_loads_without_template_and_private_snapshots_hide_location() -> void:
	var terrain := _terrain()
	var bp := FarmBlueprint.load_choice({"layout_patch_id": terrain.layout_id, "revision": 1, "farm_terrain": terrain, "region_id": "shanghai"})
	assert_object(bp).is_not_null()
	if bp == null: return
	assert_vector(bp.overlay.center).is_equal(Vector2(31.2304, 121.4737))
	assert_array(bp.overlay.paths).is_not_empty()
	assert_array(bp.overlay.blocks).has_size(1)
	assert_str(bp.region_id).is_equal("shanghai")
	terrain.erase("source")
	var private_bp := FarmBlueprint.load_choice({"layout_patch_id": terrain.layout_id, "revision": 1, "farm_terrain": terrain})
	assert_object(private_bp).is_not_null()
	assert_array(private_bp.overlay.paths).is_empty()
	assert_array(private_bp.overlay.blocks).is_empty()
	assert_object(FarmBlueprint.load_choice({"layout_patch_id": terrain.layout_id})).is_null()

func test_invalid_or_changed_server_terrain_never_falls_back_to_the_default_farm() -> void:
	var terrain := _terrain()
	terrain.plot.cell_mm = 500
	assert_object(FarmPlot.register_terrain(terrain)).is_null()
	terrain = _terrain()
	terrain.plot.checksum = "0".repeat(64)
	assert_object(FarmPlot.register_terrain(terrain)).is_null()
	terrain = _terrain()
	terrain.plot.regions.append({"kind": "water", "polygon": [[0, 0], [1, "bad"], [3, 3]]})
	assert_object(FarmPlot.register_terrain(terrain)).is_null()

func test_continuous_mask_renders_real_water_and_keeps_the_island_dry() -> void:
	var bp := FarmPlot.register_terrain(_terrain())
	assert_object(bp).is_not_null()
	if bp == null: return
	var texture := FarmTerrainMask.texture_for(bp)
	var image := texture.get_image()
	var water := image.get_pixel(42 * 8 + 4, 44 * 8 + 4)
	var island := image.get_pixel(46 * 8 + 4, 47 * 8 + 4)
	assert_float(water.b).is_equal(1.0)
	assert_float(water.a).is_greater(0.0)
	assert_float(island.b).is_equal(0.0)
	assert_float(island.a).is_equal(0.0)
	assert_object(FarmTerrainMask.texture_for(bp)).is_same(texture)
	var surface := auto_free(PlotSurface.new(bp)) as PlotSurface
	add_child(surface)
	assert_object(surface.get_node_or_null("GeographicWater")).is_not_null()
	assert_int(surface._image.get_pixel(42, 44).r8).is_equal(PlotSurface.KIND_BLOCKED)
	assert_int(surface._image.get_pixel(46, 47).r8).is_equal(PlotSurface.KIND_SOIL)

func test_polygon_boundaries_and_island_holes_match_server_rules() -> void:
	var region := {"polygon": [[0, 0], [8, 0], [8, 8], [0, 8]], "holes": [[[2, 2], [6, 2], [6, 6], [2, 6]]]}
	for point in [Vector2.ZERO, Vector2(8, 5), Vector2(1, 1)]:
		assert_bool(FarmPlot.region_contains(region, point, PackedVector2Array())).is_true()
	for point in [Vector2(2, 4), Vector2(4, 4), Vector2(-1, 0)]:
		assert_bool(FarmPlot.region_contains(region, point, PackedVector2Array())).is_false()

func test_disjoint_water_polygons_keep_both_islands_dry_in_navigation_and_rendering() -> void:
	var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_multipolygon_farm_terrain.json"))
	var bp := FarmPlot.register_terrain(terrain)
	assert_object(bp).is_not_null()
	if bp == null: return
	assert_bool(FarmPlot.verify_checksum(bp)).is_true()
	var image := FarmTerrainMask.texture_for(bp).get_image()
	for cell in [Vector2i(9, 9), Vector2i(46, 47)]:
		assert_bool(bp.is_walkable(cell)).is_true()
		var pixel := image.get_pixel(cell.x * 8 + 4, cell.y * 8 + 4)
		assert_float(pixel.b).is_equal(0.0)
		assert_float(pixel.a).is_equal(0.0)
	for cell in [Vector2i(5, 5), Vector2i(42, 45)]:
		assert_bool(bp.is_walkable(cell)).is_false()
		assert_float(image.get_pixel(cell.x * 8 + 4, cell.y * 8 + 4).b).is_equal(1.0)

func test_geographic_polygon_and_road_boundaries_retain_server_double_precision() -> void:
	# TS-generated checksum includes a polygon starting at x=9.0000002 and a
	# road centred at y=25.5000101. Float32 incorrectly claims the adjacent cells.
	var terrain: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generated_precision_farm_terrain.json"))
	var bp := FarmPlot.register_terrain(terrain)
	assert_object(bp).is_not_null()
	if bp == null: return
	assert_bool(FarmPlot.verify_checksum(bp)).is_true()
	assert_str(FarmPlot.kind_at(bp.layout_patch_id, Vector2i(9, 10))).is_equal("soil")
	assert_str(FarmPlot.kind_at(bp.layout_patch_id, Vector2i(10, 10))).is_equal("water")
	assert_str(FarmPlot.kind_at(bp.layout_patch_id, Vector2i(10, 25))).is_equal("soil")
	assert_str(FarmPlot.kind_at(bp.layout_patch_id, Vector2i(10, 26))).is_equal("path")
	var outside := [[9.0000002, 5], [11.7, 5], [11.7, 15], [9.0000002, 15]]
	var boundary := [[9.00000005, 5], [11.7, 5], [11.7, 15], [9.00000005, 15]]
	assert_bool(FarmPlot.ring_contains(outside, Vector2(9, 10))).is_false()
	assert_bool(FarmPlot.ring_contains(boundary, Vector2(9, 10))).is_true()

func test_cached_terrain_rejects_changed_source_but_accepts_private_region_labels() -> void:
	var terrain := _terrain()
	var original := FarmPlot.register_terrain(terrain)
	assert_object(original).is_not_null()
	if original == null: return
	# A claimed unchanged checksum must not bypass validation on a warm cache.
	var changed := terrain.duplicate(true)
	changed.plot.anchors.mine = [50, 50]
	assert_object(FarmPlot.register_terrain(changed)).is_null()
	changed = terrain.duplicate(true)
	for region in changed.plot.regions:
		if region.get("kind") == "water" and region.has("polygon"):
			region.polygon[0][0] += 0.25
			break
	assert_object(FarmPlot.register_terrain(changed)).is_null()
	# Rejections preserve the previously validated layout and its kind cache.
	assert_object(FarmPlot.register_terrain(terrain)).is_same(original)
	assert_str(FarmPlot.kind_at(original.layout_patch_id, Vector2i(42, 44))).is_equal("water")
	var private_terrain := terrain.duplicate(true)
	private_terrain.erase("source")
	for i in private_terrain.plot.regions.size(): private_terrain.plot.regions[i].id = "region_%d" % i
	assert_object(FarmPlot.register_terrain(private_terrain)).is_same(original)

## SGODOT-270: a layout patch placed in another city (P0's sh_a at the San Francisco homestead) takes that city's region,
## so the map lands on it there; the farm itself is the same. A choice without a region_id (every Journey choice of a
## patch) keeps the patch's own.
func test_a_placed_patch_takes_the_region_it_is_placed_in() -> void:
	var own := FarmBlueprint.load_choice({"layout_patch_id": "sh_a", "revision": 2})
	assert_str(own.region_id).is_equal("shanghai")
	var at := {"lat": 37.7558, "lng": -122.4345}
	var placed := FarmBlueprint.load_choice({"layout_patch_id": "sh_a", "revision": 2, "location": at, "region_id": "san_francisco"})
	assert_str(placed.region_id).is_equal("san_francisco")
	assert_float((placed.overlay.center as Vector2).x).is_equal_approx(37.7558, 1e-5)   # a float32 Vector2
	assert_float((placed.overlay.center as Vector2).y).is_equal_approx(-122.4345, 1e-4)
	assert_str(placed.checksum).is_equal(own.checksum)
	assert_str(FarmBlueprint.load_choice({"layout_patch_id": "sh_a", "revision": 2, "location": at}).region_id).is_equal("shanghai")
