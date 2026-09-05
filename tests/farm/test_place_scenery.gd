extends GdUnitTestSuite

const Scenery = preload("res://modules/farm/place_scenery.gd")

func test_places_fit_shared_camera_and_only_create_static_meshes() -> void:
	for place in ["nursery", "bistro", "courtyard"]:
		var root := auto_free(Scenery.build(place, {})) as Node3D
		assert_int(root.get_child_count()).is_less_equal(3)
		for child in root.get_children():
			assert_bool(child is MeshInstance3D).is_true()
			var instance := child as MeshInstance3D
			var bounds := instance.transform * instance.mesh.get_aabb()
			assert_bool(bounds.position.x >= -5.01 and bounds.end.x <= 5.01).is_true()
			assert_bool(bounds.position.z >= -4.01 and bounds.end.z <= 4.01).is_true()
			assert_bool(bounds.position.y >= -0.15 and bounds.end.y <= 3.6).is_true()
			assert_int(instance.mesh.get_surface_count()).is_equal(1)
			assert_int(instance.get_child_count()).is_equal(0)
			assert_bool((instance.material_override as StandardMaterial3D).vertex_color_use_as_albedo).is_true()

func test_nursery_stage_and_appearance_change_visible_geometry_without_changing_state() -> void:
	var geometry := {}
	for stage in ["derelict", "cleared", "built"]:
		for appearance in ["a", "b"]:
			var state := {"nursery": {"stage": stage, "appearance": appearance}}
			var before := state.duplicate(true)
			var root := auto_free(Scenery.build("nursery", state)) as Node3D
			assert_dict(state).is_equal(before)
			var mesh := (root.get_node("ArchitectureAndGarden") as MeshInstance3D).mesh
			geometry[stage + appearance] = mesh.surface_get_arrays(0)
	assert_bool(geometry.derelicta[Mesh.ARRAY_VERTEX] == geometry.cleareda[Mesh.ARRAY_VERTEX]).is_false()
	assert_bool(geometry.cleareda[Mesh.ARRAY_VERTEX] == geometry.builta[Mesh.ARRAY_VERTEX]).is_false()
	assert_bool(geometry.builta[Mesh.ARRAY_VERTEX] == geometry.builtb[Mesh.ARRAY_VERTEX]).is_false()
	assert_bool(geometry.builta[Mesh.ARRAY_COLOR] == geometry.builtb[Mesh.ARRAY_COLOR]).is_false()
