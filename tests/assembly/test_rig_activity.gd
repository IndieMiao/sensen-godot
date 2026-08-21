extends GdUnitTestSuite

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
