extends GdUnitTestSuite

## 构造一个 T1 socket 部件的真实节点形态：
## <attach_parent> -> socket_<slot>(BoneAttachment3D) -> SocketPart(Node3D) -> AnimationPlayer
## 与 assembler.gd::_sync_sockets + tools/pipeline/extract_parts.gd 产出的结构一致。
func _build_socket_player(attach_parent: Node, slot: String) -> AnimationPlayer:
	var attach := BoneAttachment3D.new()
	attach.name = "socket_%s" % slot
	attach_parent.add_child(attach)
	var socket_part := Node3D.new()
	socket_part.name = "SocketPart"
	attach.add_child(socket_part)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	var anim := Animation.new()
	anim.length = 1.0
	var lib := AnimationLibrary.new()
	lib.add_animation("t1_anim", anim)
	player.add_animation_library("", lib)
	socket_part.add_child(player)
	return player

func test_levels_by_distance() -> void:
	var act := RigActivity.new()
	act.reduced_distance = 8.0
	act.sleep_distance = 16.0
	assert_int(act.level_for(3.0, true)).is_equal(RigActivity.Level.ACTIVE)
	assert_int(act.level_for(10.0, true)).is_equal(RigActivity.Level.REDUCED)
	assert_int(act.level_for(20.0, true)).is_equal(RigActivity.Level.SLEEP)
	assert_int(act.level_for(3.0, false)).is_equal(RigActivity.Level.SLEEP)
	act.free()

func test_apply_level_pauses_players() -> void:
	var rig := AvatarRig.new()
	var t := AvatarSlotTable.new()
	rig.slot_table = t
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	skel.add_bone("Root_M")
	rig.add_child(skel)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	rig.add_child(ap)
	add_child(auto_free(rig))
	rig.skeleton = skel
	var act := RigActivity.new()
	rig.add_child(act)
	act.apply_level(RigActivity.Level.SLEEP)
	assert_bool(ap.playback_active).is_false()
	act.apply_level(RigActivity.Level.ACTIVE)
	assert_bool(ap.playback_active).is_true()

## 稳态 ACTIVE 下 apply_level 仍必须启动 T1 socket 动画（不只是"档位变化时"才生效）。
func test_active_apply_starts_socket_animation() -> void:
	var rig := Node3D.new()
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	rig.add_child(skel)
	var player := _build_socket_player(skel, "hairHat")
	add_child(auto_free(rig))
	var act := RigActivity.new()
	rig.add_child(act)
	act.apply_level(RigActivity.Level.ACTIVE)
	assert_bool(player.is_playing()).is_true()
	act.apply_level(RigActivity.Level.SLEEP)
	assert_bool(player.playback_active).is_false()

## 装配变化（slot_applied）后必须重新按当前档位应用一次，
## 否则异步换装/初次装配挂上的 T1 socket 动画永远不会被启动。
func test_reapply_on_slot_applied() -> void:
	var rig := AvatarRig.new()
	var t := AvatarSlotTable.new()
	var sdef := AvatarSlotDef.new()
	sdef.slot_name = &"glass"
	sdef.attach_bone = "Bone_A"
	sdef.required = false
	sdef.default_part = ""
	t.slots.append(sdef)
	rig.slot_table = t
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	skel.add_bone("Bone_A")
	rig.add_child(skel)
	add_child(auto_free(rig))
	rig.skeleton = skel
	var player := _build_socket_player(skel, "glass")
	var act := RigActivity.new()
	rig.add_child(act)
	rig.slot_applied.emit(&"glass", "x")
	assert_bool(player.is_playing()).is_true()
