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
		if slot_def and skeleton.find_bone(slot_def.attach_bone) != -1:
			attach.bone_name = slot_def.attach_bone
		var inst := def.scene.instantiate()
		if inst is Node3D:
			inst.position = def.offset_pos
			inst.rotation_degrees = def.offset_rot_deg
			inst.scale = def.offset_scale
		attach.add_child(inst)
