extends GdUnitTestSuite

const RIG_SCENE := "res://assets/avatar/base/base_rig.tscn"

func test_base_rig_structure() -> void:
	if not FileAccess.file_exists(RIG_SCENE):
		push_warning("base_rig 未生成，跳过")
		return
	var rig := (load(RIG_SCENE) as PackedScene).instantiate() as AvatarRig
	add_child(auto_free(rig))
	assert_object(rig.skeleton).is_not_null()
	assert_int(rig.skeleton.get_bone_count()).is_equal(62)
	assert_int(rig.skeleton.find_bone("Head_M")).is_not_equal(-1)
	assert_int(rig.skeleton.find_bone("Wrist_L")).is_not_equal(-1)

func test_animations_present_and_play() -> void:
	if not FileAccess.file_exists(RIG_SCENE):
		return
	var rig := (load(RIG_SCENE) as PackedScene).instantiate()
	add_child(auto_free(rig))
	var ap := rig.get_node("AnimationPlayer") as AnimationPlayer
	for anim_name in ["idle", "walk", "run"]:
		assert_bool(ap.has_animation(anim_name)).is_true()
		ap.play(anim_name)
		for i in 5:
			await get_tree().process_frame
		assert_bool(ap.is_playing()).is_true()

func test_slot_table_bones_exist_in_skeleton() -> void:
	if not FileAccess.file_exists(RIG_SCENE):
		return
	var rig := (load(RIG_SCENE) as PackedScene).instantiate() as AvatarRig
	add_child(auto_free(rig))
	var table: AvatarSlotTable = load("res://modules/avatar/data/slot_table.tres")
	for s in table.slots:
		assert_int(rig.skeleton.find_bone(s.attach_bone)).is_not_equal(-1)
