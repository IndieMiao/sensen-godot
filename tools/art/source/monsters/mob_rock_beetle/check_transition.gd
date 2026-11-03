extends SceneTree
const MODEL := "res://assets/monsters/mob_rock_beetle/mob_rock_beetle.glb"
var checks := []
func _initialize() -> void: run.call_deferred()
func state(skeleton: Skeleton3D) -> Array:
	var result := []
	for i in skeleton.get_bone_count():
		result.append([skeleton.get_bone_pose_position(i),skeleton.get_bone_pose_rotation(i),skeleton.get_bone_pose_scale(i)])
	return result
func play_at(model: Node, name_: String) -> void:
	var player: AnimationPlayer = model.find_children("*","AnimationPlayer",true,false)[0]
	player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(name_)
	player.advance(player.get_animation(name_).length*.35)
func run() -> void:
	var args := OS.get_cmdline_user_args()
	assert(args.size()>=1)
	var reference = load(MODEL).instantiate()
	var current = load(MODEL).instantiate()
	root.add_child(reference);root.add_child(current)
	for i in 3: await process_frame
	var source: AnimationPlayer = current.find_children("*","AnimationPlayer",true,false)[0]
	var skeleton: Skeleton3D = current.find_children("*","Skeleton3D",true,false)[0]
	var reference_skeleton: Skeleton3D = reference.find_children("*","Skeleton3D",true,false)[0]
	var names: Array[String] = []
	for name_ in source.get_animation_list():
		if name_!="RESET": names.append(name_)
	for target in names:
		reference.find_children("*","AnimationPlayer",true,false)[0].stop(true)
		reference_skeleton.reset_bone_poses()
		play_at(reference,target)
		var expected := state(reference_skeleton)
		for previous in names:
			if previous==target: continue
			source.stop(true)
			skeleton.reset_bone_poses()
			play_at(current,previous)
			play_at(current,target)
			var actual := state(skeleton)
			var maximum := 0.0
			var stale := []
			for i in expected.size():
				var error := maxf(actual[i][0].distance_to(expected[i][0]),actual[i][2].distance_to(expected[i][2]))
				error=maxf(error,actual[i][1].angle_to(expected[i][1]))
				maximum=maxf(maximum,error)
				if error>.001: stale.append(skeleton.get_bone_name(i))
			checks.append({"from":previous,"to":target,"passed":maximum<.001,"max_error":maximum,"stale_bones":stale})
	var passed := checks.all(func(c): return c.passed)
	var config := ConfigFile.new()
	assert(config.load(MODEL+".import")==OK)
	var config_ok: bool = config.get_value("params","animation/remove_immutable_tracks",true)==false
	config_ok = config_ok and config.get_value("params","nodes/use_name_suffixes",false)==true
	config_ok = config_ok and config.get_value("params","meshes/ensure_tangents",true)==false
	config_ok = config_ok and config.get_value("params","meshes/create_shadow_meshes",true)==false
	config_ok = config_ok and config.get_value("params","_subresources",{}).is_empty()
	config_ok = config_ok and config.get_value("remap","uid","")=="uid://crslv7oobgd44"
	passed = passed and config_ok
	var report := {"passed":passed,"checks":checks,"uid":config.get_value("remap","uid",""),
		"import_contract_passed":config_ok,"remove_immutable_tracks":config.get_value("params","animation/remove_immutable_tracks",true)}
	FileAccess.open(args[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	var move_hit: Dictionary = checks.filter(func(c): return c.from=="move" and c.to=="hit")[0]
	print("BEETLE_TRANSITIONS ",passed," pairs=",checks.size()," move_to_hit=",move_hit)
	reference.queue_free();current.queue_free()
	await process_frame
	quit(0 if passed else 1)
