extends GdUnitTestSuite

const Scenery := preload("res://modules/farm/farm_scenery.gd")
var _layouts: Array[String] = []

func after_test() -> void:
	for id in _layouts:
		FarmPlot.document().layouts.erase(id)
		FarmPlot._cache.erase(id)
		FarmPlot._kinds.erase(id)
	_layouts.clear()

func _plot(id: String, water: Array = []) -> FarmBlueprint:
	# Synthetic raster fixtures isolate boundary art from geography fetching and generation.
	FarmPlot.document().layouts[id] = {"revision": 1, "grid": [40, 40], "cell_mm": 800,
		"default_kind": "soil", "anchors": {"spawn": [24, 27], "house": [24, 30], "mine": [21, 28]},
		"regions": water}
	_layouts.append(id)
	return FarmPlot.blueprint_for(id)

func _boundary(bp: FarmBlueprint) -> Node3D:
	var scenery := auto_free(Scenery.new()) as Node3D
	add_child(scenery)
	scenery._build_boundary(bp)
	return scenery

func _transforms(scenery: Node3D, layer: String) -> Array[Transform3D]:
	var multimesh: MultiMesh = scenery.get_node(layer).multimesh
	var result: Array[Transform3D] = []
	for index in multimesh.instance_count: result.append(multimesh.get_instance_transform(index))
	return result

func test_dry_geographic_edges_keep_the_legacy_boundary_arrangement() -> void:
	var old := _boundary(_plot("boundary_legacy_dry"))
	var generated := _boundary(_plot("geo_boundary_dry"))
	assert_int(_transforms(old, "BoundaryRocks").size()).is_equal(96)
	assert_int(_transforms(old, "BoundaryBushes").size()).is_equal(48)
	assert_that(_transforms(generated, "BoundaryRocks")).is_equal(_transforms(old, "BoundaryRocks"))
	assert_that(_transforms(generated, "BoundaryBushes")).is_equal(_transforms(old, "BoundaryBushes"))

func test_lake_edge_has_no_outer_rock_or_bush_fence_and_dry_edges_keep_their_positions() -> void:
	var water := [{"kind": "water", "rect": [0, 0, 2, 40]}]
	var old := _boundary(_plot("boundary_legacy_coast", water))
	var generated := _boundary(_plot("geo_boundary_coast", water))
	for layer in ["BoundaryRocks", "BoundaryBushes"]:
		var original := _transforms(old, layer)
		var current := _transforms(generated, layer)
		assert_int(current.size()).is_less(original.size())
		assert_int(original.filter(func(t): return t.origin.x < 0).size()).is_greater(0)
		assert_int(current.filter(func(t): return t.origin.x < 0).size()).is_zero()
		for transform in current: assert_bool(original.has(transform)).is_true()
	# The dry eastern edge stays complete while the west opens onto the lake.
	assert_int(_transforms(generated, "BoundaryRocks").filter(func(t): return t.origin.x > 32).size()).is_equal(24)

func test_water_one_cell_inside_the_edge_and_water_on_all_sides_clear_cluster_footprints() -> void:
	var adjacent := _boundary(_plot("geo_boundary_adjacent", [{"kind": "water", "rect": [1, 0, 1, 40]}]))
	assert_int(_transforms(adjacent, "BoundaryRocks").filter(func(t): return t.origin.x < 0).size()).is_zero()
	assert_int(_transforms(adjacent, "BoundaryBushes").filter(func(t): return t.origin.x < 0).size()).is_zero()
	var island := _boundary(_plot("geo_boundary_island", [
		{"kind": "water", "rect": [0, 0, 2, 40]}, {"kind": "water", "rect": [38, 0, 2, 40]},
		{"kind": "water", "rect": [0, 0, 40, 2]}, {"kind": "water", "rect": [0, 38, 40, 2]}]))
	assert_int(_transforms(island, "BoundaryRocks").size()).is_zero()
	assert_int(_transforms(island, "BoundaryBushes").size()).is_zero()

func test_original_48_meter_farm_retains_complete_outer_stone_and_bush_rings() -> void:
	var bp := FarmPlot.blueprint_for()
	assert_float(bp.play_area_m).is_equal(48.0)
	var scenery := _boundary(bp)
	var is_outside := func(transform: Transform3D):
		var point := transform.origin
		return point.x < 0 or point.x > 48 or point.z > 0 or point.z < -48
	assert_int(_transforms(scenery, "BoundaryRocks").filter(is_outside).size()).is_equal(144)
	assert_int(_transforms(scenery, "BoundaryBushes").filter(is_outside).size()).is_equal(72)
