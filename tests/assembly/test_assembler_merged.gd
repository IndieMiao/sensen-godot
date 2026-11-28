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
	var rig: AvatarRig = auto_free(AvatarRig.new())
	assert_bool(rig.assembler is AvatarAssemblerMerged).is_true()

func test_mesh_instances_bind_to_skeleton() -> void:
	# 回归：Godot 4.7 MeshInstance3D.skeleton 默认为空 NodePath，必须显式绑定，
	# 否则 mesh 不参与蒙皮、永远停在绑定姿势（实机/桌面均复现过）。
	var mat := StandardMaterial3D.new()
	for strategy in [AvatarAssemblerMerged.new(), AvatarAssemblerDirect.new()]:
		var rig := AvatarRig.new()
		var t := AvatarSlotTable.new()
		var sd := AvatarSlotDef.new()
		sd.slot_name = &"cloth"
		sd.attach_bone = "Root_M"
		t.slots.append(sd)
		rig.slot_table = t
		var skel := Skeleton3D.new()
		skel.name = "Skeleton3D"
		skel.add_bone("Root_M")
		rig.add_child(skel)
		add_child(auto_free(rig))
		rig.skeleton = skel
		strategy.rebuild(rig, {&"cloth": _make_skinned_def("a", &"cloth", ["Root_M"], mat)})
		for child in skel.get_children():
			if child is MeshInstance3D:
				var target := child.get_node_or_null(child.skeleton)
				assert_object(target)\
					.override_failure_message("%s 的 %s 未绑定骨架 (skeleton path='%s')" % [strategy.get_class(), child.name, child.skeleton])\
					.is_same(skel)

## C-248: a fresh install's first launch read a just-loaded part back with bone 18739 for a one-bind skin, and the
## merge stopped on `remap[bones[j]]` out of bounds, leaving the player without a body.
class CorruptReadback extends AvatarAssemblerMerged:
	var corrupt_reads := 0
	var reads := 0
	func _surface_arrays(mesh: Mesh, surface: int) -> Array:
		var arrays := mesh.surface_get_arrays(surface)
		reads += 1
		if corrupt_reads > 0:
			corrupt_reads -= 1
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			bones[0] = 18739
			arrays[Mesh.ARRAY_BONES] = bones
		return arrays

func _rig_with_slots(slots: Array) -> AvatarRig:
	var rig := AvatarRig.new()
	var t := AvatarSlotTable.new()
	for n in slots:
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
	return rig

func _mesh_children(skel: Skeleton3D) -> Array:
	return skel.get_children().filter(func(c): return c is MeshInstance3D)

func test_merge_reports_a_bone_outside_the_skin_instead_of_failing() -> void:
	var asm := CorruptReadback.new()
	asm.corrupt_reads = 1
	var a := _make_skinned_def("a", &"cloth", ["Root_M"], StandardMaterial3D.new())
	var merged := asm._merge([a], _skeleton())
	assert_bool(merged.has("mesh")).is_false()
	assert_str(String(merged.error)).contains("bone 18739 of 1 binds")

func test_readback_checks_indices_and_bone_counts() -> void:
	var asm := AvatarAssemblerMerged.new()
	var arrays := _make_skinned_def("a", &"cloth", ["Root_M"], null).mesh.surface_get_arrays(0)
	assert_str(asm._readback_problem(arrays, 1)).is_empty()
	var bad_index := arrays.duplicate()
	bad_index[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 32549])
	assert_str(asm._readback_problem(bad_index, 1)).contains("index 32549 of 3 vertices")
	var short_bones := arrays.duplicate()
	short_bones[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0])
	assert_str(asm._readback_problem(short_bones, 1)).contains("3 bones for 3 vertices")
	# A part without a skin keeps its bones as they are.
	assert_str(asm._readback_problem(arrays, 0)).is_empty()

func test_unusable_readback_shows_parts_then_merges_on_retry() -> void:
	var rig := _rig_with_slots([&"cloth", &"shoes"])
	var skel := rig.skeleton
	var mat := StandardMaterial3D.new()
	var parts := {
		&"cloth": _make_skinned_def("a", &"cloth", ["Root_M"], mat),
		&"shoes": _make_skinned_def("b", &"shoes", ["Root_M"], mat),
	}
	var asm := CorruptReadback.new()
	asm.corrupt_reads = 1
	asm.rebuild(rig, parts)
	# No merged mesh yet, but the body is there: one instance per part, each with its own skin.
	assert_object(skel.get_node_or_null("merged_mesh")).is_null()
	var shown := _mesh_children(skel)
	assert_int(shown.size()).is_equal(2)
	for mi in shown:
		assert_object((mi as MeshInstance3D).skin).is_not_null()
		assert_object(mi.get_node_or_null((mi as MeshInstance3D).skeleton)).is_same(skel)
	assert_bool(AvatarAssemblerMerged.shows_body(skel)).is_true()
	for i in 4:
		await get_tree().process_frame
	var mi: MeshInstance3D = skel.get_node_or_null("merged_mesh")
	assert_object(mi).is_not_null()
	assert_int((mi.mesh as ArrayMesh).get_surface_count()).is_equal(1)
	await get_tree().process_frame
	assert_array(_mesh_children(skel)).has_size(1)
	assert_bool(AvatarAssemblerMerged.shows_body(skel)).is_true()

func test_retry_gives_up_keeping_the_parts_shown() -> void:
	var rig := _rig_with_slots([&"cloth"])
	var asm := CorruptReadback.new()
	asm.corrupt_reads = 1000
	asm.rebuild(rig, {&"cloth": _make_skinned_def("a", &"cloth", ["Root_M"], StandardMaterial3D.new())})
	var frames := 0
	for f in AvatarAssemblerMerged.RETRY_FRAMES: frames += int(f)
	for i in frames + 5:
		await get_tree().process_frame
	assert_int(asm.reads).is_equal(AvatarAssemblerMerged.RETRY_FRAMES.size() + 1)
	assert_object(rig.skeleton.get_node_or_null("merged_mesh")).is_null()
	assert_bool(AvatarAssemblerMerged.shows_body(rig.skeleton)).is_true()

func test_newer_outfit_cancels_a_pending_retry() -> void:
	var rig := _rig_with_slots([&"cloth", &"shoes"])
	var mat := StandardMaterial3D.new()
	var asm := CorruptReadback.new()
	asm.corrupt_reads = 1
	asm.rebuild(rig, {&"cloth": _make_skinned_def("a", &"cloth", ["Root_M"], mat)})
	asm.rebuild(rig, {&"cloth": _make_skinned_def("a", &"cloth", ["Root_M"], mat), &"shoes": _make_skinned_def("b", &"shoes", ["Root_M"], mat)})
	var mesh: ArrayMesh = (rig.skeleton.get_node("merged_mesh") as MeshInstance3D).mesh
	for i in 4:
		await get_tree().process_frame
	# The stale retry of the first outfit neither rebuilt nor replaced the second outfit's merge.
	assert_int(asm.reads).is_equal(3)
	assert_object((rig.skeleton.get_node("merged_mesh") as MeshInstance3D).mesh).is_same(mesh)
	assert_array(_mesh_children(rig.skeleton)).has_size(1)
