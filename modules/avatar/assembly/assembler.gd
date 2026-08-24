class_name AvatarAssembler
extends RefCounted

func rebuild(_rig: AvatarRig, _parts: Dictionary) -> void:
	push_error("AvatarAssembler.rebuild 是抽象方法")

## socket 部件装配对两种策略一致：BoneAttachment3D(名 socket_<slot>) 挂 skeleton 下
func _sync_sockets(rig: AvatarRig, parts: Dictionary) -> void:
	var skeleton := rig.skeleton
	var wanted := {}
	for slot in parts:
		var def: AvatarPartDef = parts[slot]
		if def != null and def.attach == "socket" and def.scene != null:
			wanted[slot] = def
	for child in skeleton.get_children():
		if not String(child.name).begins_with("socket_"):
			continue
		var slot := StringName(String(child.name).trim_prefix("socket_"))
		var def: AvatarPartDef = wanted.get(slot)
		if def != null and String(child.get_meta("part_id", "")) == def.id:
			wanted.erase(slot)
		else:
			skeleton.remove_child(child)
			child.queue_free()
	for slot in wanted:
		var def: AvatarPartDef = wanted[slot]
		var attach := BoneAttachment3D.new()
		attach.name = "socket_%s" % slot
		attach.set_meta("part_id", def.id)
		skeleton.add_child(attach)
		var slot_def := rig.slot_table.slot(slot)
		var bone_idx := skeleton.find_bone(slot_def.attach_bone) if slot_def else -1
		if bone_idx != -1:
			attach.bone_name = slot_def.attach_bone
		var frame := Node3D.new()
		frame.name = "socket_frame"
		frame.transform = socket_frame(skeleton, bone_idx, slot_def)
		attach.add_child(frame)
		var inst := def.scene.instantiate()
		if inst is Node3D:
			inst.position = def.offset_pos
			inst.rotation_degrees = def.offset_rot_deg
			inst.scale = def.offset_scale
		frame.add_child(inst)

## socket 帧：BoneAttachment3D 与部件实例之间的一层，对应 Unity 侧 AvatarStructureConfig
## 里的 *_socket 变换（AvatarIO.LoadSocket 把预制体挂到它下面，再叠加部件自身的偏移）。
##
## 两部分组成：
##  1. 骨骼轴向归一化 = bone global rest 基的逆。把部件从「骨骼系」搬回「模型系」，
##     使部件资产统一按模型坐标建模，不必关心每根骨头的轴向约定。
##     这一项按目标骨架实时推导，而非照搬 Unity 的四元数——两边手性不同。
##  2. 该槽位的授权偏移（slot_def.socket_offset_*），在归一化后的模型系里施加。
static func socket_frame(skeleton: Skeleton3D, bone_idx: int, slot_def: AvatarSlotDef) -> Transform3D:
	var normalize := Basis.IDENTITY
	if skeleton != null and bone_idx >= 0 and bone_idx < skeleton.get_bone_count():
		normalize = skeleton.get_bone_global_rest(bone_idx).basis.orthonormalized().inverse()
	var authored := Transform3D.IDENTITY
	if slot_def != null:
		authored = Transform3D(
			Basis.from_euler(slot_def.socket_offset_rot_deg * (PI / 180.0)),
			slot_def.socket_offset_pos)
	return Transform3D(normalize, Vector3.ZERO) * authored
