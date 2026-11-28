class_name AvatarAssemblerMerged
extends AvatarAssembler

## C-248: the merge reads each part's surfaces back from the rendering device. On a fresh install's first launch
## (Android emulator, Vulkan Mobile) parts that had just finished loading on a thread read back as garbage — bone
## indices like 18739 for a skin of a few dozen binds — so `remap[bones[j]]` ran out of bounds and the player was left
## without a body. A later launch read the same parts correctly. So every surface read back is checked before it is
## used; when one is unusable the parts are shown as they are, one MeshInstance3D each (they draw from their own GPU
## buffers and need no read back), and the merge is tried again a few frames later, up to RETRY_FRAMES.size() times.
## Once a merge succeeds the separate parts give way to the single merged mesh.
const MERGED_NAME := "merged_mesh"
const UNMERGED_PREFIX := "unmerged_mesh_"
## Frames to wait before each further merge attempt (about 4 s in all at 60 fps).
const RETRY_FRAMES := [1, 2, 4, 8, 16, 30, 30, 30, 30, 30, 30, 30]

var _generation := 0

func rebuild(rig: AvatarRig, parts: Dictionary) -> void:
	_sync_sockets(rig, parts)
	_generation += 1
	_assemble(rig, parts, _generation, 0)

## Whether `skeleton` shows a body: the merged mesh, or while it is being retried the separate parts.
static func shows_body(skeleton: Skeleton3D) -> bool:
	if skeleton == null: return false
	for child in skeleton.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0: continue
		if String(mi.name) == MERGED_NAME or String(mi.name).begins_with(UNMERGED_PREFIX): return true
	return false

func _assemble(rig: AvatarRig, parts: Dictionary, generation: int, attempt: int) -> void:
	var skeleton := rig.skeleton
	var mesh_defs: Array = []
	for slot in parts:
		var def: AvatarPartDef = parts[slot]
		if def != null and def.attach == "mesh" and def.mesh != null:
			mesh_defs.append(def)
	var mi := skeleton.get_node_or_null(MERGED_NAME) as MeshInstance3D
	if mesh_defs.is_empty():
		_clear_unmerged(skeleton)
		if mi:
			skeleton.remove_child(mi)
			mi.queue_free()
		return
	var result := _merge(mesh_defs, skeleton)
	if result.has("error"):
		# The merged mesh, if any, is the previous outfit: the parts stand in for it until a merge succeeds.
		if mi:
			skeleton.remove_child(mi)
			mi.queue_free()
		_show_unmerged(skeleton, mesh_defs)
		var retry := attempt < RETRY_FRAMES.size()
		push_warning("AvatarAssemblerMerged: unusable read back (%s), attempt %d; %s" % [result.error, attempt + 1,
			"showing the parts unmerged and retrying" if retry else "keeping the parts unmerged"])
		if retry: _retry_later(rig, parts, generation, attempt + 1)
		return
	_clear_unmerged(skeleton)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = MERGED_NAME
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skeleton.add_child(mi)
	# Godot 4.7 起 MeshInstance3D.skeleton 默认为空 NodePath，必须显式绑定
	mi.skeleton = mi.get_path_to(skeleton)
	mi.mesh = result.mesh
	mi.skin = result.skin
	if attempt > 0: print("AVATAR_MERGE_RECOVERED ", JSON.stringify({"attempt": attempt + 1}))

func _retry_later(rig: AvatarRig, parts: Dictionary, generation: int, attempt: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return
	for i in int(RETRY_FRAMES[attempt - 1]):
		await tree.process_frame
	# A newer outfit has been assembled since, or the rig is gone: this attempt is stale.
	if generation != _generation or not is_instance_valid(rig) or rig.skeleton == null: return
	_assemble(rig, parts, generation, attempt)

func _show_unmerged(skeleton: Skeleton3D, defs: Array) -> void:
	_clear_unmerged(skeleton)
	for i in defs.size():
		var def: AvatarPartDef = defs[i]
		var mi := MeshInstance3D.new()
		mi.name = "%s%d" % [UNMERGED_PREFIX, i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skeleton.add_child(mi)
		mi.skeleton = mi.get_path_to(skeleton)
		mi.mesh = def.mesh
		mi.skin = def.skin
		mi.set_meta("part_id", def.id)

func _clear_unmerged(skeleton: Skeleton3D) -> void:
	for child in skeleton.get_children():
		if String(child.name).begins_with(UNMERGED_PREFIX):
			skeleton.remove_child(child)
			child.queue_free()

## 返回 {"mesh": ArrayMesh, "skin": Skin}，读回的面不可用时返回 {"error": String}
func _merge(defs: Array, skeleton: Skeleton3D) -> Dictionary:
	var canonical := Skin.new()
	var bind_by_bone := {}
	var buckets := {}  # key -> {material: Material, list: Array[surface arrays]}
	var bucket_order: Array = []
	for def in defs:
		var remap := _remap_for(def, canonical, bind_by_bone, skeleton)
		var mesh: Mesh = def.mesh
		for s in mesh.get_surface_count():
			var arrays := _surface_arrays(mesh, s)
			var problem := _readback_problem(arrays, remap.size())
			if not problem.is_empty():
				return {"error": "%s surface %d: %s" % [def.id, s, problem]}
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

## The one place the merge reads a surface back (tests stand in a corrupt read back here).
func _surface_arrays(mesh: Mesh, surface: int) -> Array:
	return mesh.surface_get_arrays(surface)

## Why a surface read back cannot be merged, or "" when it can: vertices present; bones and weights one set of 4 or 8
## per vertex; every bone a bind of the part's skin (`bind_count`, 0 for a part without a skin); every index a vertex.
func _readback_problem(arrays: Array, bind_count: int) -> String:
	if arrays.size() != Mesh.ARRAY_MAX: return "%d arrays" % arrays.size()
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	if not vertices is PackedVector3Array or (vertices as PackedVector3Array).is_empty(): return "no vertices"
	var count := (vertices as PackedVector3Array).size()
	var bones = arrays[Mesh.ARRAY_BONES]
	if bones != null:
		var size := (bones as PackedInt32Array).size()
		if size != count * 4 and size != count * 8: return "%d bones for %d vertices" % [size, count]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if weights == null or (weights as PackedFloat32Array).size() != size: return "weights do not match bones"
		if bind_count > 0:
			for b in (bones as PackedInt32Array):
				if b < 0 or b >= bind_count: return "bone %d of %d binds" % [b, bind_count]
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices != null:
		for i in (indices as PackedInt32Array):
			if i < 0 or i >= count: return "index %d of %d vertices" % [i, count]
	return ""

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
