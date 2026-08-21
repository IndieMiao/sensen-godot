class_name AvatarAssemblerDirect
extends AvatarAssembler

func rebuild(rig: AvatarRig, parts: Dictionary) -> void:
	_sync_sockets(rig, parts)
	var skeleton := rig.skeleton
	for slot in rig.slot_table.slot_names():
		var node_name := "mesh_%s" % slot
		var existing := skeleton.get_node_or_null(NodePath(node_name))
		var def: AvatarPartDef = parts.get(slot)
		if def == null or def.attach != "mesh" or def.mesh == null:
			if existing:
				skeleton.remove_child(existing)
				existing.queue_free()
			continue
		var mi := existing as MeshInstance3D
		if mi == null:
			mi = MeshInstance3D.new()
			mi.name = node_name
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			skeleton.add_child(mi)
		# Godot 4.7 起 MeshInstance3D.skeleton 默认为空 NodePath，必须显式绑定
		mi.skeleton = mi.get_path_to(skeleton)
		mi.mesh = def.mesh
		mi.skin = def.skin
		mi.set_meta("part_id", def.id)
