extends GdUnitTestSuite

func after_test() -> void:
	FarmChoice.clear()

func test_location_validation_rejects_malformed_and_non_finite_values() -> void:
	for value in [null, [], {}, {"lat": "31.2", "lng": 121.4}, {"lat": 31.2},
		{"lat": INF, "lng": 121.4}, {"lat": 31.2, "lng": NAN}, {"lat": 86.0, "lng": 0.0},
		{"lat": 31.2, "lng": 181.0}, {"lat": 31.2, "lng": 121.4, "name": "extra"}]:
		assert_bool(FarmPlacement.is_valid(value)).is_false()
	assert_bool(FarmPlacement.is_valid({"lat": 34.0522, "lng": -118.2437})).is_true()

func test_supported_region_bounds_keep_whole_footprint_inside() -> void:
	var shanghai := FarmRegions.load_default().region("shanghai")
	assert_bool(FarmPlacement.contains(shanghai, {"lat": 31.23, "lng": 121.47})).is_true()
	assert_bool(FarmPlacement.contains(shanghai, {"lat": 34.05, "lng": -118.24})).is_false()
	assert_bool(FarmPlacement.contains(shanghai, {"lat": 30.6701, "lng": 121.47})).is_false()
	assert_bool(FarmPlacement.contains({}, {"lat": 31.23, "lng": 121.47})).is_false()

func test_placement_moves_overlay_without_changing_gameplay_or_source_blueprint() -> void:
	var bp := FarmBlueprint.load_file(FarmBlueprint.asset_path("sh_a", 2))
	var original_center: Vector2 = bp.overlay.center
	var location := {"lat": 31.225, "lng": 121.485}
	var placed := bp.with_location(location)
	assert_that(placed.overlay.center).is_equal(Vector2(31.225, 121.485))
	assert_that(bp.overlay.center).is_equal(original_center)
	assert_str(placed.canonical()).is_equal(bp.canonical())
	assert_bool(placed.verify_checksum()).is_true()
	assert_that(placed.anchor("spawn")).is_equal(bp.anchor("spawn"))
	assert_that(placed.beds()).is_equal(bp.beds())
	var source_point: Vector2 = bp.overlay.paths[0][0]
	var placed_point: Vector2 = placed.overlay.paths[0][0]
	assert_float(placed_point.x - source_point.x).is_equal_approx(31.225 - original_center.x, 0.00001)
	assert_that(placed.overlay.blocks).is_not_equal(bp.overlay.blocks)
	assert_object(bp.with_location({})).is_same(bp)

func test_choice_roundtrip_preserves_location_and_legacy_choice_clears_it() -> void:
	var location := {"lat": 31.225, "lng": 121.485}
	FarmChoice.save("sh_a", 2, location)
	assert_that(FarmChoice.load().location).is_equal(location)
	var placed := FarmBlueprint.load_choice(FarmChoice.load())
	assert_that(placed.overlay.center).is_equal(Vector2(31.225, 121.485))
	FarmChoice.save("sh_a", 2)
	assert_bool(FarmChoice.load().has("location")).is_false()
	var original := FarmBlueprint.load_choice(FarmChoice.load())
	assert_that(original.overlay.center).is_not_equal(placed.overlay.center)
