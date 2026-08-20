extends GdUnitTestSuite

## 构造一个绑定到指定骨骼名的最小蒙皮三角面 mesh + skin
func _make_skinned_def(id: String, slot: StringName, bone_names: Array, mat: Material) -> AvatarPartDef:
	var st_arrays := []
	st_arrays.resize(Mesh.ARRAY_MAX)
	st_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	st_arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for v in 3:
		bones.append_array(PackedInt32Array([v % bone_names.size(), 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
	st_arrays[Mesh.ARRAY_BONES] = bones
	st_arrays[Mesh.ARRAY_WEIGHTS] = weights
	st_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st_arrays)
	mesh.surface_set_material(0, mat)
	var skin := Skin.new()
	for bn in bone_names:
		skin.add_named_bind(bn, Transform3D.IDENTITY)
	var def := AvatarPartDef.new()
	def.id = id
	def.slot = slot
	def.attach = "mesh"
	def.mesh = mesh
	def.skin = skin
	return def

func _skeleton() -> Skeleton3D:
	var s := Skeleton3D.new()
	s.add_bone("Root_M")
	s.add_bone("Head_M")
	return auto_free(s)

func test_same_material_surfaces_concat_to_one() -> void:
	var mat := StandardMaterial3D.new()
	var a := _make_skinned_def("a", &"cloth", ["Root_M"], mat)
	var b := _make_skinned_def("b", &"shoes", ["Root_M"], mat)
	var merged := AvatarAssemblerMerged.new()._merge([a, b], _skeleton())
	var mesh: ArrayMesh = merged.mesh
	assert_int(mesh.get_surface_count()).is_equal(1)
	var arrays := mesh.surface_get_arrays(0)
	assert_int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(6)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_int(idx.size()).is_equal(6)
	assert_int(idx[3]).is_equal(3)  # 第二段索引被偏移

func test_different_materials_stay_separate() -> void:
	var a := _make_skinned_def("a", &"cloth", ["Root_M"], StandardMaterial3D.new())
	var b := _make_skinned_def("b", &"shoes", ["Root_M"], StandardMaterial3D.new())
	var merged := AvatarAssemblerMerged.new()._merge([a, b], _skeleton())
	assert_int((merged.mesh as ArrayMesh).get_surface_count()).is_equal(2)

func test_bone_indices_remapped_by_name() -> void:
	var mat := StandardMaterial3D.new()
	# a 的 bind0=Root_M；b 的 bind 顺序相反：bind0=Head_M, bind1=Root_M
	var a := _make_skinned_def("a", &"cloth", ["Root_M", "Head_M"], mat)
	var b := _make_skinned_def("b", &"shoes", ["Head_M", "Root_M"], mat)
	var merged := AvatarAssemblerMerged.new()._merge([a, b], _skeleton())
	var skin: Skin = merged.skin
	assert_int(skin.get_bind_count()).is_equal(2)
	var canon := {}
	for i in skin.get_bind_count():
		canon[String(skin.get_bind_name(i))] = i
	var arrays := (merged.mesh as ArrayMesh).surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	# a: 顶点0→bind0(Root_M) 顶点1→bind1(Head_M)；b: 顶点0(全局3)→源bind0=Head_M
	assert_int(bones[0]).is_equal(canon["Root_M"])
	assert_int(bones[4]).is_equal(canon["Head_M"])
	assert_int(bones[3 * 4]).is_equal(canon["Head_M"])

func test_rebuild_creates_single_mesh_instance() -> void:
	var rig := AvatarRig.new()
	var t := AvatarSlotTable.new()
	for n in [&"cloth", &"shoes"]:
		var sd := AvatarSlotDef.new()
		sd.slot_name = n
		sd.attach_bone = "Root_M"
		t.slots.append(sd)
	rig.slot_table = t
	var skel := _skeleton()
	skel.name = "Skeleton3D"
	rig.add_child(skel)
	add_child(auto_free(rig))
	rig.skeleton = skel
	var mat := StandardMaterial3D.new()
	var parts := {
		&"cloth": _make_skinned_def("a", &"cloth", ["Root_M"], mat),
		&"shoes": _make_skinned_def("b", &"shoes", ["Root_M"], mat),
	}
	var asm := AvatarAssemblerMerged.new()
	asm.rebuild(rig, parts)
	var mi: MeshInstance3D = skel.get_node("merged_mesh")
	assert_object(mi).is_not_null()
	assert_int((mi.mesh as ArrayMesh).get_surface_count()).is_equal(1)
	assert_object(mi.skin).is_not_null()
	asm.rebuild(rig, {&"cloth": parts[&"cloth"]})
	assert_int(((skel.get_node("merged_mesh") as MeshInstance3D).mesh as ArrayMesh).get_surface_count()).is_equal(1)

func test_default_assembler_is_merged() -> void:
	assert_bool(AvatarRig.new().assembler is AvatarAssemblerMerged).is_true()
