## 用法: godot --headless --path . --script res://tools/pipeline/inspect_rig.gd -- <res://路径.fbx|.glb>
## 打印场景里的 Skeleton3D 骨骼树（含全局 rest 位置）与 AnimationPlayer 动画清单，
## 用于给新骨架配 Mixamo 重定向映射表前先看清命名与朝向。
extends SceneTree

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("用法: ... -- <res://path>")
		quit(2)
		return
	var scene := load(args[0]) as PackedScene
	if scene == null:
		printerr("加载失败(未导入?): " + args[0])
		quit(1)
		return
	var inst := scene.instantiate()
	root.add_child(inst)
	var skels: Array = []
	var players: Array = []
	_collect(inst, skels, players)
	for s in skels:
		var skel := s as Skeleton3D
		print("Skeleton3D path=%s bones=%d motion_scale=%.3f node_scale=%s" % [inst.get_path_to(skel), skel.get_bone_count(), skel.motion_scale, str(skel.global_transform.basis.get_scale())])
		for i in skel.get_bone_count():
			var g := skel.get_bone_global_rest(i)
			var pos := g.origin
			var depth := 0
			var p := skel.get_bone_parent(i)
			while p >= 0:
				depth += 1
				p = skel.get_bone_parent(p)
			print("  %s%d %s  gpos=(%.3f, %.3f, %.3f)" % ["  ".repeat(depth), i, skel.get_bone_name(i), pos.x, pos.y, pos.z])
	for p in players:
		var ap := p as AnimationPlayer
		print("AnimationPlayer path=%s" % inst.get_path_to(ap))
		for name in ap.get_animation_list():
			var a := ap.get_animation(name)
			print("  anim %s len=%.2fs tracks=%d loop=%d" % [name, a.length, a.get_track_count(), a.loop_mode])
			for t in mini(a.get_track_count(), 4):
				print("    track#%d type=%d path=%s keys=%d" % [t, a.track_get_type(t), a.track_get_path(t), a.track_get_key_count(t)])
	quit(0)

func _collect(n: Node, skels: Array, players: Array) -> void:
	if n is Skeleton3D:
		skels.append(n)
	if n is AnimationPlayer:
		players.append(n)
	for c in n.get_children():
		_collect(c, skels, players)
