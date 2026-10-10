extends GdUnitTestSuite
## SGODOT-289 Harvest ×N's wave (914bcfea §三): a crop's stand-alone copy stands where the field drew it, with the
## same instances, so the field can drop the crop while its copy pops.

## The copy is the field's child at the cell's world point, one instance per plant of that cell. Its instances are the
## field's own for that cell (`_fill`'s, at the cell's world point) moved to the copy's origin. Compared on
## `_cell_instances`, not read back from the MultiMesh: a headless run's dummy renderer reads every instance back as
## identity (哪吒 on #291).
func test_a_ghost_is_the_fields_crop_at_its_cell() -> void:
	var bp := P0Garden.blueprint()
	var field: CropField = auto_free(CropField.new(bp))
	add_child(field)
	await get_tree().process_frame
	var cell := P0Garden.cell_of(7)
	var g := field.ghost(cell, "R")
	assert_object(g.get_parent()).is_same(field)
	assert_that(g.position).is_equal(bp.cell_to_world(cell, field.world_scale))
	var here := field._cell_instances(cell, "R", CropField.STAGES - 1, Vector3.ZERO)
	assert_int((g.get_child(0) as MultiMeshInstance3D).multimesh.instance_count).is_equal(here.size())
	var placed := field._cell_instances(cell, "R", CropField.STAGES - 1, g.position)
	assert_int(placed.size()).is_equal(here.size())
	assert_int(here.size()).is_greater(0)
	for i in here.size():
		assert_that(placed[i].basis).is_equal(here[i].basis)
		assert_vector(placed[i].origin).is_equal_approx(g.position + here[i].origin, Vector3.ONE * 0.001)

## The flights' ×N is what the reply put in the bag, not the plots (a plot may yield two): `+4 Radish` flies ×4. Each
## kind flies from its first plot, in the order the row took them; Seed Saver's seeds come after, one each (哪吒 on #291).
func test_a_rows_flights_count_what_went_in() -> void:
	var farm: GDScript = load("res://scenes/p0/p0_farm.gd")
	var crop_of := {7: "crop_radish", 8: "crop_radish", 9: "crop_carrot", 10: "crop_carrot"}
	var events := [{"kind": "item", "id": "crop_radish", "delta": 2}, {"kind": "item", "id": "seed_radish", "delta": 1},
		{"kind": "seed_saved", "id": "seed_radish", "plot": 7}, {"kind": "item", "id": "crop_radish", "delta": 2},
		{"kind": "item", "id": "crop_carrot", "delta": 1}, {"kind": "harvest_short", "got": 3, "of": 4, "plot": 10}]
	assert_array(farm.row_flights([7, 8, 9], crop_of, events)).is_equal([["crop_radish", 4, 7], ["crop_carrot", 1, 9],
		["seed_radish", 1, 7]])

## A row the server refused as a whole leaves no wave behind: a single harvest right after is not read as its reply.
func test_a_refused_row_forgets_its_wave() -> void:
	var farm: Node3D = auto_free(load("res://scenes/p0/p0_farm.gd").new())
	farm._wave = {"plots": [7, 8, 9], "crops": {7: "crop_radish"}, "at": Time.get_ticks_msec()}
	farm.p0_harvest_refused()
	assert_dict(farm._wave).is_empty()
	assert_float(farm.p0_harvest_wave([{"kind": "item", "id": "crop_radish", "delta": 1}])).is_equal(0.0)
