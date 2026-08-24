extends GdUnitTestSuite
## socket 部件落位回归。
##
## 历史缺陷：转换管线只烘叶节点的局部变换（extract_parts.gd 的 mi.transform），
## 而两族源 FBX 落在不同坐标系里——
##   SM_*（静态网格）：网格挂在 FBX 自带骨架的 BoneAttachment3D 下，顶点等价于在
##                     "Head_M 骨骼系"里建模，全局变换 =(0,90,90.65)；
##   SK_*（蒙皮网格）：网格直接挂 Skeleton3D 下，顶点在根坐标系，全局变换 = 单位阵。
## 装配时两者都被直接绑到 Head_M，于是 SK_ 那族凭空多吃一次骨骼旋转，躺倒并甩出头顶。
## 实测 hairhat37 水平偏出 0.292m、落在头骨同高度（+-0），而正常件是 0.013~0.147m / +0.22~+0.35m。
##
## 下面的阈值取自实测：坏件 0.292/-0.002，最差的正常件 0.147/+0.224，中间留出清晰间隔。

const MAX_HORIZONTAL := 0.20   ## 水平偏移上限（正常件最大 0.147）
const MIN_ABOVE_BONE := 0.10   ## 头发中心至少高于头骨这么多（正常件最小 +0.224）

func test_every_hairhat_sits_on_the_head() -> void:
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		push_warning("转换产物缺失，跳过")
		return
	var metas := Avatar.catalog.parts_for_slot(&"hairHat")
	assert_int(metas.size()).is_greater(0)

	var rig := Avatar.create_rig()
	add_child(auto_free(rig))
	rig.apply_config(Avatar.load_outfit())
	for i in 600:
		await get_tree().process_frame
		if rig.visible:
			break
	var skel: Skeleton3D = rig.skeleton
	var bone_idx := skel.find_bone(Avatar.slot_table.slot(&"hairHat").attach_bone)
	assert_int(bone_idx).is_greater_equal(0)
	var bone := skel.get_bone_global_pose(bone_idx)

	var bad: Array[String] = []
	for meta in metas:
		rig.equip(&"hairHat", meta.id)
		var sock: Node = null
		for i in 600:
			await get_tree().process_frame
			sock = skel.get_node_or_null("socket_hairHat")
			if sock and sock.get_child_count() > 0 and String(sock.get_meta("part_id", "")) == meta.id:
				break
		for i in 8:
			await get_tree().process_frame
		assert_object(sock).is_not_null()

		var box := _world_aabb(sock)
		assert_float(box.size.y).is_greater(0.0)
		var c := box.position + box.size * 0.5
		var horizontal := Vector2(c.x - bone.origin.x, c.z - bone.origin.z).length()
		var above := c.y - bone.origin.y
		if horizontal > MAX_HORIZONTAL or above < MIN_ABOVE_BONE:
			bad.append("%s(水平%.3f 高%.3f)" % [meta.id, horizontal, above])

	assert_array(bad).override_failure_message(
		"这些 hairHat 部件没有端正落在头骨上: %s" % str(bad)).is_empty()

func _world_aabb(n: Node) -> AABB:
	var out := AABB()
	var found := false
	for mi in _meshes(n):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
		if found:
			out = out.merge(b)
		else:
			out = b
			found = true
	return out

func _meshes(n: Node) -> Array:
	var out := []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out
