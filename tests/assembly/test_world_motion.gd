extends GdUnitTestSuite
## Verify real bone motion in the shipped world cameras, not just clip names.

func _viewport() -> SubViewport:
	var view := auto_free(SubViewport.new()) as SubViewport
	view.size = Vector2i(390, 844)
	view.own_world_3d = true
	add_child(view)
	return view

func _session() -> FarmSession:
	var session := FarmSession.new(null)
	session.layout_patch_id = "la_a"
	session.blueprint_revision = 2
	session.state = {"cells": {}, "inventory": {"produce": {}, "dishes": {}},
		"journey": {"wood": 0, "materials": {}, "facts": [], "unlocks": [], "contributions": {}, "exploration": {"round": 0, "collected": []}},
		"mine": {"version": 1, "run": 0, "floor": 1, "deepest_floor": 1, "cleared_floors": [], "broken": {}, "elevator_unlocked": false}}
	return session

func _check(scene: Node3D, rig: AvatarRig, camera: Camera3D, clips: Array) -> void:
	for frame in 120:
		await get_tree().process_frame
		if not rig.is_busy(): break
	assert_bool(rig.is_busy()).is_false()
	scene.set_process(false)
	assert_bool(Rect2(Vector2.ZERO, Vector2(390, 844)).has_point(camera.unproject_position(rig.global_position + Vector3.UP * .7))).is_true()
	for child in rig.get_children():
		if child is RigActivity:
			child.set_process(false)
			child.apply_level(child.level_for(camera.global_position.distance_to(rig.global_position), true))
	var ap := rig.get_node("AnimationPlayer") as AnimationPlayer
	assert_bool(ap.playback_active).is_true()
	for clip in clips:
		rig.play_motion(clip)
		await await_millis(30)
		var before := []
		for bone in rig.skeleton.get_bone_count(): before.append(rig.skeleton.get_bone_pose(bone))
		var time := ap.current_animation_position
		await await_millis(130)
		assert_str(ap.current_animation).is_equal(clip)
		assert_float(absf(ap.current_animation_position - time)).override_failure_message("%s: %s timeline stopped" % [scene.scene_file_path, clip]).is_greater(.05)
		var changed := 0
		for bone in rig.skeleton.get_bone_count():
			if not rig.skeleton.get_bone_pose(bone).is_equal_approx(before[bone]): changed += 1
		assert_int(changed).override_failure_message("%s: %s bone poses stopped" % [scene.scene_file_path, clip]).is_greater(0)

func test_farm_locomotion_labour_and_wave_have_live_bone_motion() -> void:
	var scene := load("res://scenes/farm/farm.tscn").instantiate() as Node3D
	scene.setup({"blueprint": FarmPlot.blueprint_for(), "session": null})
	_viewport().add_child(scene)
	await _check(scene, scene._rig, scene.cam, AnimPlaceholders.real_clips())

func test_mine_locomotion_mining_and_attack_clips_have_live_bone_motion() -> void:
	var scene := preload("res://scenes/mine/mine.gd").new()
	scene.setup({"session": _session()})
	_viewport().add_child(scene)
	await _check(scene, scene.rig, scene.cam, ["idle", "walk", "run", "labour_drain", "labour_harvest"])

func test_street_locomotion_and_wave_have_live_bone_motion() -> void:
	var scene := preload("res://scenes/map/journey_street.gd").new()
	scene.setup({"session": _session()})
	_viewport().add_child(scene)
	await _check(scene, scene._rig, scene.cam, ["idle", "walk", "run", "emote_wave"])

func test_griffith_locomotion_has_live_bone_motion() -> void:
	var scene := load("res://scenes/landmark/griffith_observatory.tscn").instantiate() as GriffithObservatory
	_viewport().add_child(scene)
	await _check(scene, scene._rig, scene._camera, ["idle", "walk", "run"])
