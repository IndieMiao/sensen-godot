extends GdUnitTestSuite

const FarmProps = preload("res://modules/farm/farm_props.gd")
const Art = preload("res://modules/farm/farm_art.gd")

func test_scenery_is_one_colored_mesh_per_anchor_with_no_gameplay_nodes() -> void:
	for kind in ["house", "storage", "well"]:
		var position := Vector3(4.25, 0, -8.775)
		var prop := auto_free(FarmProps.build(kind, position, 1.5)) as MeshInstance3D
		assert_that(prop.position).is_equal(position)
		assert_that(prop.scale).is_equal(Vector3.ONE * 1.5)
		assert_int(prop.get_child_count()).is_equal(0)
		assert_int(prop.mesh.get_surface_count()).is_equal(1)
		assert_bool(prop.mesh.get_aabb().position.y >= -0.001).is_true()
		var arrays := prop.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		assert_int(vertices.size()).is_greater(36)
		assert_int(colors.size()).is_equal(vertices.size())
		var palette := {}
		for color in colors: palette[color.to_html()] = true
		assert_int(palette.size()).is_greater(4)
		assert_bool(prop.mesh.get_faces().size() / 3 < 16000).is_true()
		var material := prop.material_override as StandardMaterial3D
		assert_bool(material.vertex_color_use_as_albedo).is_true()
		assert_bool(material.vertex_color_is_srgb).is_false()

func test_prop_sizes_stay_within_existing_scene_clearance() -> void:
	var limits := {"house": Vector3(2.4, 2.8, 2.4), "storage": Vector3(0.66, 0.6, 0.65), "well": Vector3(0.97, 1.02, 0.72)}
	for kind in limits:
		var prop := auto_free(FarmProps.build(kind, Vector3.ZERO)) as MeshInstance3D
		var size := prop.mesh.get_aabb().size
		var limit: Vector3 = limits[kind]
		assert_bool(size.x <= limit.x and size.y <= limit.y and size.z <= limit.z).override_failure_message(
			"%s size %s exceeds available clearance %s" % [kind, size, limit]).is_true()

func test_all_reference_styles_have_one_surface_and_share_cached_resources() -> void:
	for style in Art.STYLES:
		var a := auto_free(FarmProps.build("house", Vector3.ZERO, 1.0, style)) as MeshInstance3D
		var b := auto_free(FarmProps.build("house", Vector3.ONE, 1.0, style)) as MeshInstance3D
		assert_object(a.mesh).is_same(b.mesh)
		assert_object(a.material_override).is_same(b.material_override)
		assert_int(a.mesh.get_surface_count()).is_equal(1)
		assert_bool(a.mesh.get_faces().size() / 3 < 16000).is_true()
		var bounds := a.mesh.get_aabb()
		assert_bool(bounds.position.y >= -0.001).is_true()
		assert_bool(bounds.size.x < 2.5 and bounds.size.z < 2.5 and bounds.size.y < 2.85).is_true()

func test_unknown_style_uses_the_default_without_loading_an_arbitrary_resource() -> void:
	var house := auto_free(FarmProps.build("house", Vector3.ZERO, 1.0, "../../unknown")) as MeshInstance3D
	assert_object(house.mesh).is_same(Art.mesh_for("house_cottage"))
