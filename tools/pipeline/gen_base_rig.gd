## 用法: godot --headless --path . --script res://tools/pipeline/gen_base_rig.gd
## 生成 base_rig.tscn —— 所有场景实例化角色的唯一入口：
## AvatarRig 根 + 62 骨 Skeleton3D（无网格子节点）+ idle/walk/run 动画库。
extends SceneTree

const BASE_FBX := "res://assets/avatar/source/base/SK_DtBase.fbx"
const ANIM_FBX := {"idle": "res://assets/avatar/source/base/dt@idle02.fbx",
	"walk": "res://assets/avatar/source/base/dt@walk01.fbx",
	"run": "res://assets/avatar/source/base/dt@run01.fbx"}
const OUT_SCENE := "res://assets/avatar/base/base_rig.tscn"
const OUT_LIB := "res://assets/avatar/base/animations.res"

func _initialize() -> void:
	var base_scene := load(BASE_FBX) as PackedScene
	if base_scene == null:
		push_error("基础 FBX 未导入: " + BASE_FBX)
		quit(1)
		return
	var src := base_scene.instantiate()
	var src_skel := _find_first(src, "Skeleton3D") as Skeleton3D
	if src_skel == null:
		push_error("基础 FBX 无 Skeleton3D")
		src.free()
		quit(1)
		return
	# 根：AvatarRig
	var rig := Node3D.new()
	rig.name = "AvatarRig"
	rig.set_script(load("res://modules/avatar/assembly/avatar_rig.gd"))
	rig.set("slot_table", load("res://modules/avatar/data/slot_table.tres"))
	# 骨架：复制骨骼（不带任何网格子节点）
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	for i in src_skel.get_bone_count():
		skel.add_bone(src_skel.get_bone_name(i))
	for i in src_skel.get_bone_count():
		skel.set_bone_parent(i, src_skel.get_bone_parent(i))
		skel.set_bone_rest(i, src_skel.get_bone_rest(i))
		skel.set_bone_pose_position(i, src_skel.get_bone_rest(i).origin)
		skel.set_bone_pose_rotation(i, src_skel.get_bone_rest(i).basis.get_rotation_quaternion())
	rig.add_child(skel)
	skel.owner = rig
	print("实测骨骼数=%d" % skel.get_bone_count())
	if skel.get_bone_count() > 0:
		print("骨骼清单样本: 0=%s 1=%s last=%s" % [skel.get_bone_name(0), skel.get_bone_name(1 if skel.get_bone_count() > 1 else 0), skel.get_bone_name(skel.get_bone_count() - 1)])
	# 实测该 Skeleton3D 节点在源场景中的完整路径（用于校验/重写动画轨道路径）。
	var skel_path_in_src: NodePath = src.get_path_to(src_skel)
	print("源骨架节点路径(相对根)=%s" % [skel_path_in_src])
	# 动画库
	var lib := AnimationLibrary.new()
	for key in ANIM_FBX:
		var anim_scene := load(ANIM_FBX[key]) as PackedScene
		if anim_scene == null:
			push_error("动画 FBX 未导入: " + ANIM_FBX[key])
			src.free()
			rig.free()
			quit(1)
			return
		var anim_inst := anim_scene.instantiate()
		var player := _find_first(anim_inst, "AnimationPlayer") as AnimationPlayer
		if player == null or player.get_animation_list().is_empty():
			push_error("动画 FBX 无动画: " + ANIM_FBX[key])
			anim_inst.free()
			src.free()
			rig.free()
			quit(1)
			return
		var anim := player.get_animation(player.get_animation_list()[0]).duplicate(true) as Animation
		anim.loop_mode = Animation.LOOP_LINEAR
		# 已知风险对策：动画轨道路径依赖动画 FBX 内骨架节点名与本场景的 Skeleton3D 一致。
		# 实测并按需重写为 "Skeleton3D:骨骼名" 形态。
		_normalize_track_paths(anim, key)
		lib.add_animation(key, anim)
		anim_inst.free()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/avatar/base"))
	ResourceSaver.save(lib, OUT_LIB)
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	rig.add_child(ap)
	ap.owner = rig
	ap.add_animation_library("", load(OUT_LIB))
	var bone_count := skel.get_bone_count()
	var packed := PackedScene.new()
	packed.pack(rig)
	var err := ResourceSaver.save(packed, OUT_SCENE)
	# 注意：rig.free() 会连带释放其子节点 skel；必须先把 bone_count 取出到局部变量，
	# 不能像 brief 基线那样在 free() 之后再调用 skel.get_bone_count()——那样会对
	# 已释放实例调用方法产生 SCRIPT ERROR（"Cannot call method ... on a previously
	# freed instance"），实测在本环境下会导致进程随后挂起数分钟才被强杀，必须避免。
	src.free()
	rig.free()
	print("base_rig 生成完成 err=%d 骨骼数=%d" % [err, bone_count])
	quit(0 if err == OK else 1)

func _normalize_track_paths(anim: Animation, anim_key: String) -> void:
	var samples := 0
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		var path_str := String(path)
		var colon := path_str.find(":")
		if colon == -1:
			continue
		var bone_name := path_str.substr(colon + 1)
		var new_path := NodePath("Skeleton3D:" + bone_name)
		if samples < 3:
			print("[%s] 轨道#%d 原路径=%s -> 新路径=%s" % [anim_key, t, path_str, String(new_path)])
			samples += 1
		if path != new_path:
			anim.track_set_path(t, new_path)

func _find_first(root: Node, klass: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(klass):
			return n
		for c in n.get_children():
			stack.append(c)
	return null
