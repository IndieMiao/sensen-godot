extends GdUnitTestSuite

const Scenery := preload("res://modules/farm/farm_scenery.gd")

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

func test_original_48_meter_farm_retains_complete_outer_stone_and_bush_rings() -> void:
	var bp := FarmPlot.blueprint_for()
	assert_float(bp.play_area_m).is_equal(48.0)
	var scenery := _boundary(bp)
	var is_outside := func(transform: Transform3D):
		var point := transform.origin
		return point.x < 0 or point.x > 48 or point.z > 0 or point.z < -48
	assert_int(_transforms(scenery, "BoundaryRocks").filter(is_outside).size()).is_equal(144)
	assert_int(_transforms(scenery, "BoundaryBushes").filter(is_outside).size()).is_equal(72)
