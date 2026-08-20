class_name AvatarAssemblerMerged
extends AvatarAssembler

func rebuild(rig: AvatarRig, parts: Dictionary) -> void:
	_sync_sockets(rig, parts)
	var skeleton := rig.skeleton
	var mi := skeleton.get_node_or_null("merged_mesh") as MeshInstance3D
	var mesh_defs: Array = []
	for slot in parts:
		var def: AvatarPartDef = parts[slot]
		if def != null and def.attach == "mesh" and def.mesh != null:
			mesh_defs.append(def)
	if mesh_defs.is_empty():
		if mi:
			skeleton.remove_child(mi)
			mi.queue_free()
		return
	var result := _merge(mesh_defs, skeleton)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "merged_mesh"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skeleton.add_child(mi)
	mi.mesh = result.mesh
	mi.skin = result.skin

## 返回 {"mesh": ArrayMesh, "skin": Skin}
func _merge(defs: Array, skeleton: Skeleton3D) -> Dictionary:
	var canonical := Skin.new()
	var bind_by_bone := {}
	var buckets := {}  # key -> {material: Material, list: Array[surface arrays]}
	var bucket_order: Array = []
	for def in defs:
		var remap := _remap_for(def, canonical, bind_by_bone, skeleton)
		var mesh: Mesh = def.mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			if remap.size() > 0 and arrays[Mesh.ARRAY_BONES] != null:
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				for j in bones.size():
					bones[j] = remap[bones[j]]
				arrays[Mesh.ARRAY_BONES] = bones
			var mat := mesh.surface_get_material(s)
			var key := _bucket_key(mat, arrays)
			if not buckets.has(key):
				buckets[key] = {"material": mat, "list": []}
				bucket_order.append(key)
			buckets[key].list.append(arrays)
	var merged := ArrayMesh.new()
	for key in bucket_order:
		var b = buckets[key]
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _concat_arrays(b.list))
		merged.surface_set_material(merged.get_surface_count() - 1, b.material)
	return {"mesh": merged, "skin": canonical}

func _remap_for(def: AvatarPartDef, canonical: Skin, bind_by_bone: Dictionary, skeleton: Skeleton3D) -> PackedInt32Array:
	var remap := PackedInt32Array()
	if def.skin == null:
		return remap
	remap.resize(def.skin.get_bind_count())
	for i in def.skin.get_bind_count():
		var bone_name := String(def.skin.get_bind_name(i))
		if bone_name.is_empty():
			var bone_idx := def.skin.get_bind_bone(i)
			bone_name = skeleton.get_bone_name(bone_idx) if bone_idx >= 0 and bone_idx < skeleton.get_bone_count() else "bind_%d" % i
		if not bind_by_bone.has(bone_name):
			bind_by_bone[bone_name] = canonical.get_bind_count()
			canonical.add_named_bind(bone_name, def.skin.get_bind_pose(i))
		remap[i] = bind_by_bone[bone_name]
	return remap

func _bucket_key(mat: Material, arrays: Array) -> String:
	var fmt := ""
	for i in arrays.size():
		fmt += "1" if arrays[i] != null else "0"
	var mat_key := "null"
	if mat != null:
		mat_key = mat.resource_path if not mat.resource_path.is_empty() else str(mat.get_instance_id())
	return mat_key + "|" + fmt

func _concat_arrays(list: Array) -> Array:
	if list.size() == 1:
		return list[0]
	var out: Array = list[0].duplicate()
	for i in range(1, list.size()):
		var arrays: Array = list[i]
		var vertex_offset := (out[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for ch in Mesh.ARRAY_MAX:
			if ch == Mesh.ARRAY_INDEX or arrays[ch] == null:
				continue
			var combined = out[ch]
			combined += arrays[ch]
			out[ch] = combined
		if arrays[Mesh.ARRAY_INDEX] != null and out[Mesh.ARRAY_INDEX] != null:
			var out_idx: PackedInt32Array = out[Mesh.ARRAY_INDEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for j in idx.size():
				out_idx.append(idx[j] + vertex_offset)
			out[Mesh.ARRAY_INDEX] = out_idx
	return out
