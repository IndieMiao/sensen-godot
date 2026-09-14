extends GdUnitTestSuite

const Art = preload("res://modules/farm/farm_art.gd")
const Scenery = preload("res://modules/farm/farm_scenery.gd")

func test_regional_styles_are_stable_and_preview_overrides_do_not_change_the_default() -> void:
	assert_str(Art.style_for("shanghai", "sh_b")).is_equal("east_asian")
	assert_str(Art.style_for("los_angeles", "la_a")).is_equal("barn")
	assert_str(Art.style_for("shanghai", "sh_a")).is_equal("cottage")
	assert_str(Art.style_for("", "la_b")).is_equal("windmill")
	assert_str(Art.style_for("shanghai", "future_layout")).is_equal("east_asian")
	assert_str(Art.style_for("unknown", "unknown")).is_equal("cottage")
	assert_str(Art.style_for("shanghai", "sh_a", "mushroom")).is_equal("mushroom")
	assert_str(Art.style_for("shanghai", "sh_a", "invalid")).is_equal("cottage")
	assert_str(Art.style_for("shanghai", "sh_a")).is_equal("cottage")

func _blueprint() -> FarmBlueprint:
	return FarmInterior.new(FarmBlueprint.load_file("res://assets/blueprints/sh_a/r2/farm_blueprint.json")).blueprint

func test_scenery_has_bounded_batches_and_expansion_never_draws_locked_paths() -> void:
	var scenery := auto_free(Scenery.new()) as Node3D
	add_child(scenery)
	scenery.build(_blueprint(), "cottage")
	assert_int(scenery.get_child_count()).is_less_equal(20)
	var base: Transform3D = scenery._garden_path.transform
	scenery.set_expanded(true)
	assert_float(scenery._garden_path.scale.z).is_greater(base.basis.get_scale().z)
	assert_float(scenery._garden_path.position.z).is_equal_approx(base.origin.z + 0.65, 0.001)
	scenery.set_expanded(false)
	assert_bool(scenery._garden_path.transform.is_equal_approx(base)).is_true()
	assert_bool(scenery.is_processing()).is_false()
	for child in scenery.get_children():
		assert_bool(child is MeshInstance3D or child is MultiMeshInstance3D).is_true()
		if child is MultiMeshInstance3D:
			assert_int(child.multimesh.mesh.get_surface_count()).is_equal(1)
			assert_int(child.multimesh.instance_count).is_less_equal(260)

func test_new_obstacles_preserve_access_to_all_twelve_working_edges_and_the_exit() -> void:
	var bp := _blueprint()
	var grid := BlueprintGrid.new(bp)
	for cell in Scenery.TREE_CELLS: assert_bool(bp.is_walkable(cell)).is_false()
	for kind in ["house", "storage", "well"]: assert_bool(bp.is_walkable(bp.anchor(kind))).is_false()
	assert_bool(grid.path(bp.anchor("spawn"), bp.anchor("exit")).is_empty()).is_false()
	for bed in bp.beds() + [bp.reserved_bed()]:
		for cell in bed.cells:
			var edges := 0
			for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if bp.is_walkable(cell + delta) and not grid.path(bp.anchor("spawn"), cell + delta).is_empty(): edges += 1
			assert_int(edges).override_failure_message("Unreachable plot: %s" % cell).is_greater_equal(2)

func test_rounded_plot_top_matches_crop_origin_and_fits_its_path() -> void:
	var bed := Art.mesh_for("plot").get_aabb()
	assert_float(bed.end.y).is_equal_approx(0.155, 0.006)
	assert_float(bed.size.x).is_less(1.0)
	assert_float(bed.size.z).is_less(1.0)
	var path := Art.mesh_for("path_tile").get_aabb()
	assert_float(path.size.x).is_less(1.3)
	assert_float(path.size.x).is_greater(bed.size.x)
	assert_float(path.size.y).is_less(0.02)

func test_windmill_rotor_moves_without_changing_obstacles_or_additional_lights() -> void:
	var scenery := auto_free(Scenery.new()) as Node3D
	add_child(scenery)
	var bp := _blueprint()
	var mask: Array = bp.masks.walkable.duplicate()
	scenery.build(bp, "windmill")
	assert_object(scenery._rotor).is_not_null()
	var before: Basis = scenery._rotor.basis
	scenery._process(0.5)
	assert_bool(before.is_equal_approx(scenery._rotor.basis)).is_false()
	assert_that(bp.masks.walkable).is_equal(mask)
	assert_int(scenery.find_children("*", "Light3D", true, false).size()).is_equal(0)
