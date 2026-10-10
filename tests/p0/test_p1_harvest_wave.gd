extends GdUnitTestSuite
## SGODOT-289 Harvest ×N's wave (914bcfea §三): a crop's stand-alone copy stands where the field drew it, with the
## same instances, so the field can drop the crop while its copy pops.

func test_a_ghost_is_the_fields_crop_at_its_cell() -> void:
	var bp := P0Garden.blueprint()
	var field: CropField = auto_free(CropField.new(bp))
	add_child(field)
	await get_tree().process_frame
	var cell := P0Garden.cell_of(7)
	var g := field.ghost(cell, "R")
	assert_object(g.get_parent()).is_same(field)
	assert_that(g.position).is_equal(bp.cell_to_world(cell))
	var mm: MultiMesh = (g.get_child(0) as MultiMeshInstance3D).multimesh
	var want := field._cell_instances(cell, "R", CropField.STAGES - 1, Vector3.ZERO)
	assert_int(mm.instance_count).is_equal(want.size())
	assert_that(mm.get_instance_transform(0)).is_equal(want[0])
	# the field's own instance for that cell, at its world point, is the copy's moved there
	field.sync({P0Garden.cell_id(cell): {"state": "growing", "crop": "R", "ready_at": 0, "watered_at": -1}}, 10)
	var placed := (field._mm["R"] as MultiMeshInstance3D).multimesh.get_instance_transform(0)
	assert_that(placed.origin).is_equal_approx(g.position + want[0].origin, Vector3.ONE * 0.001)
