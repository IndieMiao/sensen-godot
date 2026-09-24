extends GdUnitTestSuite

func _pond(template: String) -> FishingPondScene:
	var scene: FishingPondScene = auto_free(load(SystemPonds.SCENE).instantiate())
	var entries: Array = SystemPonds.data().locations.filter(func(entry): return entry.template_id == template)
	scene.setup({"pond_id": str(entries[0].id), "session": null})
	add_child(scene)
	for frame in 4: await get_tree().process_frame
	scene.set_process(false)
	return scene

func _activity(rig: AvatarRig) -> RigActivity:
	for child in rig.get_children():
		if child is RigActivity: return child
	return null

func _poses(skeleton: Skeleton3D) -> Array:
	var values := []
	for bone in skeleton.get_bone_count(): values.append(skeleton.get_bone_pose(bone))
	return values

func _changed(skeleton: Skeleton3D, before: Array) -> int:
	var changed := 0
	for bone in skeleton.get_bone_count():
		if not skeleton.get_bone_pose(bone).is_equal_approx(before[bone]): changed += 1
	return changed

func test_visible_pond_idle_and_run_advance_at_the_real_camera_distance() -> void:
	for template in ["crescent", "gourd", "meander"]:
		var pond := await _pond(template)
		var activity := _activity(pond._rig)
		# Headless visibility cannot drive a render notifier. Keep the real scene
		# distance/LOD and explicitly model the character being visible on screen.
		activity.set_process(false)
		var ap := pond._rig.get_node("AnimationPlayer") as AnimationPlayer
		for overview in [false, true]:
			pond._overview = overview
			pond._update_camera()
			var distance := pond.cam.global_position.distance_to(pond._rig.global_position)
			assert_float(distance).is_greater(30.0)
			activity.apply_level(activity.level_for(distance, true))
			assert_bool(ap.playback_active).override_failure_message("%s overview=%s: visible pond avatar is asleep at %.2fm" % [template, overview, distance]).is_true()
			for motion in ["idle", "run"]:
				pond._play(motion)
				await await_millis(30)
				var before := _poses(pond._rig.skeleton)
				var time := ap.current_animation_position
				await await_millis(130)
				assert_str(ap.current_animation).is_equal(motion)
				assert_float(absf(ap.current_animation_position - time)).is_greater(.05)
				assert_int(_changed(pond._rig.skeleton, before)).override_failure_message("%s: %s bone poses did not advance" % [template, motion]).is_greater(2)
		pond.queue_free()
		await get_tree().process_frame

func test_pond_motion_uses_clean_locomotion_after_a_full_body_action() -> void:
	var pond := await _pond("crescent")
	_activity(pond._rig).set_process(false)
	var ap := pond._rig.get_node("AnimationPlayer") as AnimationPlayer
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	pond._rig.play_motion("run")
	ap.advance(.2)
	var expected := _poses(pond._rig.skeleton)
	pond._rig.play_motion("labour_harvest")
	ap.advance(1.1)
	pond._play("run")
	ap.advance(.2)
	assert_int(_changed(pond._rig.skeleton, expected)).is_zero()
