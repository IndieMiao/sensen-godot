extends GdUnitTestSuite

const FarmProps = preload("res://modules/farm/farm_props.gd")

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
		assert_bool(prop.mesh.get_faces().size() / 3 < 2500).is_true()
		var material := prop.material_override as StandardMaterial3D
		assert_bool(material.vertex_color_use_as_albedo and material.vertex_color_is_srgb).is_true()

func test_prop_sizes_stay_within_existing_scene_clearance() -> void:
	var limits := {"house": Vector3(2.0, 1.5, 2.0), "storage": Vector3(0.66, 0.6, 0.65), "well": Vector3(0.70, 0.76, 0.70)}
	for kind in limits:
		var prop := auto_free(FarmProps.build(kind, Vector3.ZERO)) as MeshInstance3D
		var size := prop.mesh.get_aabb().size
		var limit: Vector3 = limits[kind]
		assert_bool(size.x <= limit.x and size.y <= limit.y and size.z <= limit.z).override_failure_message(
			"%s size %s exceeds available clearance %s" % [kind, size, limit]).is_true()
