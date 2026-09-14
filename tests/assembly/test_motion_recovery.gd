extends GdUnitTestSuite

func test_locomotion_after_every_labour_clip_matches_a_clean_pose() -> void:
	var rig: AvatarRig = auto_free(Avatar.create_rig())
	add_child(rig)
	await get_tree().process_frame
	rig.set_process(false)
	var ap := rig.get_node("AnimationPlayer") as AnimationPlayer
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for locomotion in ["run", "idle", "walk"]:
		ap.stop()
		rig.skeleton.reset_bone_poses()
		rig.play_motion(locomotion)
		ap.advance(0.2)
		var expected := []
		for bone in rig.skeleton.get_bone_count(): expected.append(rig.skeleton.get_bone_pose(bone))
		for labour in ["labour_clear", "labour_till", "labour_sow", "labour_water", "labour_harvest", "labour_drain", "labour_shelter", "emote_wave"]:
			rig.play_motion(labour)
			ap.advance(1.1)
			rig.play_motion(locomotion)
			ap.advance(0.2)
			for bone in rig.skeleton.get_bone_count():
				assert_bool(rig.skeleton.get_bone_pose(bone).is_equal_approx(expected[bone])).override_failure_message("%s -> %s: %s" % [labour, locomotion, rig.skeleton.get_bone_name(bone)]).is_true()
	await get_tree().process_frame
