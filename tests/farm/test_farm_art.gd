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
	return FarmPlot.blueprint_for()

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

func test_placeable_lawn_renders_as_grass_and_roads_keep_their_own_surface() -> void:
	var bp := FarmPlot.blueprint_for()
	var surface := auto_free(PlotSurface.new(bp)) as PlotSurface
	add_child(surface)
	assert_int(surface._image.get_pixelv(Vector2i(24, 38)).r8).is_equal(PlotSurface.KIND_GRASS)
	assert_int(surface._image.get_pixelv(Vector2i(29, 35)).r8).is_equal(PlotSurface.KIND_PATH)
	assert_int(surface._image.get_pixelv(bp.anchor("spawn")).r8).is_equal(PlotSurface.KIND_SOIL)
