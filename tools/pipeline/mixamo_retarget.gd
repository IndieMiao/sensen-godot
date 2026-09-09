class_name MixamoRetarget
extends RefCounted
## Mixamo（mixamorig 骨架）动画 → 本项目 dt 62 骨骨架的离线重定向。
##
## 做法是最朴素的"世界空间旋转差分"：对每根映射到的骨骼，取源骨骼相对其 rest 的
## 世界旋转增量，原样叠到目标骨骼的世界 rest 上，再折算回目标骨骼的局部旋转。两边
## 都是 T-pose（dt 骨架实测 T-pose；Mixamo 全部 T-pose），所以增量语义一致，肢体
## 比例不同也不影响。髋骨位移按髋高比例缩放，其余骨骼不搬位移。
##
## 输出的 Animation 轨道路径与 gen_base_rig.gd 产出的 idle/walk/run 完全同形
## （"Skeleton3D:骨骼名"），可直接塞进 assets/avatar/base/animations.res。
## 不依赖 Godot 导入期的 BoneMap 重定向，因此不改 base_rig 的骨骼名与 rest，
## 30 个部件 .res 与 socket 挂点全部原样可用。
##
## 不要用 Blender 做 FBX 往返：Blender 导出会重写关节朝向，导出来的绝对局部旋转
## 与 base_rig 的 rest 对不上；这里直接在 Godot 里对着运行时真正用的骨架算。

## 目标骨 → Mixamo 骨（去掉 mixamorig 前缀后的名字）。
## AdvancedSkeleton 命名的陷阱：Shoulder_* 是上臂、Scapula_* 才是肩/锁骨、Hip_* 是大腿。
const BONE_MAP := {
	"Root_M": "Hips",
	"RootPart1_M": "Spine",
	"Spine1_M": "Spine1",
	"Chest_M": "Spine2",
	"Neck_M": "Neck",
	"Head_M": "Head",
	"Scapula_R": "RightShoulder", "Shoulder_R": "RightArm", "Elbow_R": "RightForeArm", "Wrist_R": "RightHand",
	"Scapula_L": "LeftShoulder", "Shoulder_L": "LeftArm", "Elbow_L": "LeftForeArm", "Wrist_L": "LeftHand",
	"ThumbFinger1_R": "RightHandThumb1", "ThumbFinger2_R": "RightHandThumb2", "ThumbFinger3_R": "RightHandThumb3",
	"IndexFinger1_R": "RightHandIndex1", "IndexFinger2_R": "RightHandIndex2", "IndexFinger3_R": "RightHandIndex3",
	"MiddleFinger1_R": "RightHandMiddle1", "MiddleFinger2_R": "RightHandMiddle2", "MiddleFinger3_R": "RightHandMiddle3",
	"RingFinger1_R": "RightHandRing1", "RingFinger2_R": "RightHandRing2", "RingFinger3_R": "RightHandRing3",
	"ThumbFinger1_L": "LeftHandThumb1", "ThumbFinger2_L": "LeftHandThumb2", "ThumbFinger3_L": "LeftHandThumb3",
	"IndexFinger1_L": "LeftHandIndex1", "IndexFinger2_L": "LeftHandIndex2", "IndexFinger3_L": "LeftHandIndex3",
	"MiddleFinger1_L": "LeftHandMiddle1", "MiddleFinger2_L": "LeftHandMiddle2", "MiddleFinger3_L": "LeftHandMiddle3",
	"RingFinger1_L": "LeftHandRing1", "RingFinger2_L": "LeftHandRing2", "RingFinger3_L": "LeftHandRing3",
	"Hip_R": "RightUpLeg", "Knee_R": "RightLeg", "Ankle_R": "RightFoot", "Toes_R": "RightToeBase",
	"Hip_L": "LeftUpLeg", "Knee_L": "LeftLeg", "Ankle_L": "LeftFoot", "Toes_L": "LeftToeBase",
}
## 目标骨架里搬位移的那根骨（髋）。
const TARGET_HIPS := "Root_M"
const SOURCE_HIPS := "Hips"
## 朝向判定用的一对左右骨（目标 / 源）。
const TARGET_LEFT := "Shoulder_L"
const TARGET_RIGHT := "Shoulder_R"
const SOURCE_LEFT := "LeftArm"
const SOURCE_RIGHT := "RightArm"


## 把 "mixamorig:Hips" / "mixamorig_Hips" / "mixamorig1:Hips" / "Hips" 统一成 "Hips"。
static func normalize_source_bone(name: String) -> String:
	var n := name
	var idx := n.find(":")
	if idx >= 0:
		n = n.substr(idx + 1)
	elif n.begins_with("mixamorig"):
		n = n.substr("mixamorig".length())
		# 前缀后可能还跟着编号与分隔符（mixamorig1_Hips）
		while n.length() > 0 and (n[0] == "_" or n[0].is_valid_int()):
			n = n.substr(1)
	return n


## 源骨架里"规范名 → 骨骼索引"表。
static func source_bone_index(skel: Skeleton3D) -> Dictionary:
	var out := {}
	for i in skel.get_bone_count():
		var key := normalize_source_bone(skel.get_bone_name(i))
		if not out.has(key):
			out[key] = i
	return out


## 源场景里 node 相对 scene_root 的累计变换。不走 global_transform（需要进树），
## 直接乘 transform 链——源场景（如 GLB 的 Armature 节点）常带 0.01 缩放或 180° 旋转。
static func world_of(node: Node3D, scene_root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != scene_root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## 让源角色的左右方向与目标一致：返回一个绕 Y 的修正，左乘到源的世界变换上。
## 两边都面朝 +Z 时返回单位阵；源背朝时返回 180°。
static func facing_fix(src_rest: Array[Transform3D], src_world: Transform3D, src_idx: Dictionary,
		dst_skel: Skeleton3D, dst_rest: Array[Transform3D]) -> Basis:
	var dl := dst_skel.find_bone(TARGET_LEFT)
	var dr := dst_skel.find_bone(TARGET_RIGHT)
	if dl < 0 or dr < 0 or not src_idx.has(SOURCE_LEFT) or not src_idx.has(SOURCE_RIGHT):
		return Basis.IDENTITY
	var dst_side := dst_rest[dl].origin - dst_rest[dr].origin
	var src_side := (src_world * src_rest[src_idx[SOURCE_LEFT]]).origin \
		- (src_world * src_rest[src_idx[SOURCE_RIGHT]]).origin
	dst_side.y = 0.0
	src_side.y = 0.0
	if dst_side.length() < 1e-6 or src_side.length() < 1e-6:
		return Basis.IDENTITY
	var angle := src_side.signed_angle_to(dst_side, Vector3.UP)
	if absf(angle) < deg_to_rad(1.0):
		return Basis.IDENTITY
	return Basis(Vector3.UP, angle)


## 按父先子后把局部变换累乘成全局变换。不用 Skeleton3D.get_bone_global_pose：
## 4.7 里骨架不在场景树中时 pose 的全局值不会重算（实测返回 rest），这里纯数学自算最稳。
static func global_transforms(skel: Skeleton3D, local_of: Callable) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(skel.get_bone_count())
	for b in _parents_first(skel):
		var p := skel.get_bone_parent(b)
		var local: Transform3D = local_of.call(b)
		out[b] = (out[p] * local) if p >= 0 else local
	return out


static func global_rests(skel: Skeleton3D) -> Array[Transform3D]:
	return global_transforms(skel, func(b: int) -> Transform3D: return skel.get_bone_rest(b))


static func global_poses(skel: Skeleton3D) -> Array[Transform3D]:
	return global_transforms(skel, func(b: int) -> Transform3D: return skel.get_bone_pose(b))


## 把 anim 在 time 时刻的骨骼轨道写到 skel 的 pose 上（先复位到 rest）。
## bone_of_track: 轨道索引 → 骨骼索引（-1 表示不是骨骼轨道）。
static func apply_pose(skel: Skeleton3D, anim: Animation, bone_of_track: PackedInt32Array, time: float) -> void:
	skel.reset_bone_poses()
	for t in anim.get_track_count():
		var b := bone_of_track[t]
		if b < 0:
			continue
		match anim.track_get_type(t):
			Animation.TYPE_POSITION_3D:
				skel.set_bone_pose_position(b, anim.position_track_interpolate(t, time))
			Animation.TYPE_ROTATION_3D:
				skel.set_bone_pose_rotation(b, anim.rotation_track_interpolate(t, time))
			Animation.TYPE_SCALE_3D:
				skel.set_bone_pose_scale(b, anim.scale_track_interpolate(t, time))


static func map_tracks_to_bones(skel: Skeleton3D, anim: Animation) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(anim.get_track_count())
	for t in anim.get_track_count():
		var path := anim.track_get_path(t)
		out[t] = skel.find_bone(String(path.get_subname(0))) if path.get_subname_count() > 0 else -1
	return out


## 重定向主入口。
## src_root: 源场景实例根（含 Skeleton3D + AnimationPlayer）；src_anim: 要转的源动画。
## dst_skel: 目标骨架（base_rig.tscn 里的 Skeleton3D，可不在树里）。
## opts: fps(30) / loop(true) / in_place(true) / start(0) / end(源长度) / speed(1.0)
## 返回可直接加进 AnimationLibrary 的 Animation；stats 回填统计信息（可选）。
static func retarget(src_root: Node, src_skel: Skeleton3D, src_anim: Animation, dst_skel: Skeleton3D,
		opts: Dictionary = {}, stats: Dictionary = {}) -> Animation:
	var fps: float = float(opts.get("fps", 30))
	var speed: float = maxf(0.01, float(opts.get("speed", 1.0)))
	var start: float = clampf(float(opts.get("start", 0.0)), 0.0, src_anim.length)
	var end: float = clampf(float(opts.get("end", src_anim.length)), start, src_anim.length)
	var in_place: bool = bool(opts.get("in_place", true))
	var loop: bool = bool(opts.get("loop", true))

	var src_idx := source_bone_index(src_skel)
	var src_rest := global_rests(src_skel)
	var dst_rest := global_rests(dst_skel)
	var src_world := world_of(src_skel, src_root)
	var fix := facing_fix(src_rest, src_world, src_idx, dst_skel, dst_rest)
	src_world = Transform3D(fix, Vector3.ZERO) * src_world
	var bone_of_track := map_tracks_to_bones(src_skel, src_anim)

	# 目标骨 → 源骨索引；缺的源骨（比如源没有 Spine2）就当没映射，保持 rest。
	var dst_count := dst_skel.get_bone_count()
	var src_of_dst := PackedInt32Array()
	src_of_dst.resize(dst_count)
	var mapped := 0
	var missing: PackedStringArray = []
	for d in dst_count:
		src_of_dst[d] = -1
		var dname := dst_skel.get_bone_name(d)
		if BONE_MAP.has(dname):
			var sname: String = BONE_MAP[dname]
			if src_idx.has(sname):
				src_of_dst[d] = src_idx[sname]
				mapped += 1
			else:
				missing.append(sname)

	# 源各骨的世界 rest 旋转；目标各骨的世界 rest。
	var src_rest_rot: Array[Quaternion] = []
	src_rest_rot.resize(src_skel.get_bone_count())
	for s in src_skel.get_bone_count():
		src_rest_rot[s] = (src_world * src_rest[s]).basis.get_rotation_quaternion()
	var dst_rest_rot: Array[Quaternion] = []
	dst_rest_rot.resize(dst_count)
	for d in dst_count:
		dst_rest_rot[d] = dst_rest[d].basis.get_rotation_quaternion()

	# 髋：位移比例与 rest 位置。
	var dst_hips := dst_skel.find_bone(TARGET_HIPS)
	var src_hips: int = src_idx.get(SOURCE_HIPS, -1)
	var hips_ratio := 1.0
	var src_hips_rest_pos := Vector3.ZERO
	if dst_hips >= 0 and src_hips >= 0:
		src_hips_rest_pos = (src_world * src_rest[src_hips]).origin
		var dst_h := dst_rest[dst_hips].origin.y
		var src_h := src_hips_rest_pos.y
		if src_h > 1e-4:
			hips_ratio = dst_h / src_h

	# 输出动画：每根目标骨一条旋转轨 + 一条位移轨，路径与 gen_base_rig 同形。
	var out := Animation.new()
	var length := (end - start) / speed
	out.length = maxf(length, 1.0 / fps)
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	out.step = 1.0 / fps
	var rot_track := PackedInt32Array()
	var pos_track := PackedInt32Array()
	rot_track.resize(dst_count)
	pos_track.resize(dst_count)
	for d in dst_count:
		var path := NodePath("Skeleton3D:" + dst_skel.get_bone_name(d))
		rot_track[d] = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(rot_track[d], path)
		pos_track[d] = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(pos_track[d], path)

	# 未映射骨：一帧 rest 即可（切 clip 时把 idle 留下的姿态覆盖掉）。
	for d in dst_count:
		if src_of_dst[d] < 0:
			var rest := dst_skel.get_bone_rest(d)
			out.rotation_track_insert_key(rot_track[d], 0.0, rest.basis.get_rotation_quaternion())
			out.position_track_insert_key(pos_track[d], 0.0, rest.origin)
		elif d != dst_hips:
			out.position_track_insert_key(pos_track[d], 0.0, dst_skel.get_bone_rest(d).origin)

	var frames := int(ceil(length * fps)) + 1
	var order := _parents_first(dst_skel)
	var global_rot: Array[Quaternion] = []
	global_rot.resize(dst_count)
	for f in frames:
		var t_out := minf(float(f) / fps, length)
		var t_src := start + t_out * speed
		apply_pose(src_skel, src_anim, bone_of_track, t_src)
		var src_pose := global_poses(src_skel)
		# 目标骨的世界旋转：映射骨 = 源增量 × 目标 rest；未映射骨 = 父世界 × 局部 rest。
		for d in order:
			var p := dst_skel.get_bone_parent(d)
			var parent_rot := global_rot[p] if p >= 0 else Quaternion.IDENTITY
			var s := src_of_dst[d]
			if s >= 0:
				var src_now := (src_world * src_pose[s]).basis.get_rotation_quaternion()
				var delta := src_now * src_rest_rot[s].inverse()
				global_rot[d] = (delta * dst_rest_rot[d]).normalized()
				var local_rot := (parent_rot.inverse() * global_rot[d]).normalized()
				out.rotation_track_insert_key(rot_track[d], t_out, local_rot)
			else:
				global_rot[d] = (parent_rot * dst_skel.get_bone_rest(d).basis.get_rotation_quaternion()).normalized()
		# 髋位移：源髋世界位移 × 髋高比，折回髋父骨的（未动画）rest 空间。
		if dst_hips >= 0 and src_hips >= 0:
			var src_now_pos := (src_world * src_pose[src_hips]).origin
			var delta_p := (src_now_pos - src_hips_rest_pos) * hips_ratio
			if in_place:
				delta_p.x = 0.0
				delta_p.z = 0.0
			var target_world := dst_rest[dst_hips].origin + delta_p
			var p := dst_skel.get_bone_parent(dst_hips)
			var parent_xf := dst_rest[p] if p >= 0 else Transform3D.IDENTITY
			out.position_track_insert_key(pos_track[dst_hips], t_out, parent_xf.affine_inverse() * target_world)

	stats["mapped"] = mapped
	stats["missing_source_bones"] = missing
	stats["frames"] = frames
	stats["length"] = out.length
	stats["hips_ratio"] = hips_ratio
	stats["facing_fix_deg"] = rad_to_deg(fix.get_euler().y)
	return out


static func _parents_first(skel: Skeleton3D) -> PackedInt32Array:
	var order := PackedInt32Array()
	var stack: Array = []
	for r in skel.get_parentless_bones():
		stack.append(r)
	while not stack.is_empty():
		var b: int = stack.pop_front()
		order.append(b)
		for c in skel.get_bone_children(b):
			stack.append(c)
	return order


## 场景里第一个 Skeleton3D / AnimationPlayer。
static func find_first(root: Node, klass: String) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.is_class(klass):
			return n
		for c in n.get_children():
			stack.append(c)
	return null


## 把新增的真实 clip 登记进 anim_placeholders.json：加进 real_clips，对应占位条目标 status=real。
## 返回实际新增的 clip 数。
static func register_real_clips(json_path: String, clip_keys: Array) -> int:
	var text := FileAccess.get_file_as_string(json_path)
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("anim_placeholders.json 解析失败: " + json_path)
		return -1
	var table: Dictionary = parsed
	if table.has("format"):
		table["format"] = int(table["format"])
	var real: Array = table.get("real_clips", [])
	var placeholders: Dictionary = table.get("placeholders", {})
	var added := 0
	for key in clip_keys:
		if not real.has(key):
			real.append(key)
			added += 1
		for action in placeholders:
			var entry = placeholders[action]
			if entry is Dictionary and str(entry.get("clip_id", "")) == str(key):
				entry["status"] = "real"
	table["real_clips"] = real
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(table, "  ") + "\n")
	f.close()
	return added


const DEFAULT_MANIFEST := "res://assets/avatar/source/mixamo/clips.json"
const DEFAULT_OUT := "res://assets/avatar/base/animations.res"
const RIG_SCENE := "res://assets/avatar/base/base_rig.tscn"
const PLACEHOLDERS_JSON := "res://assets/avatar/base/anim_placeholders.json"


## 读清单，把每条 Mixamo 源动画重定向到 base_rig 骨架，写进 out_path 动画库（已有同名 clip 覆盖，
## 其余 clip 保留）。register=true 时把新 clip 登记进 anim_placeholders.json 的 real_clips。
## 返回进程退出码：0 全部成功；1 有失败（已成功的仍会写入）；2 清单缺失/格式错。
## 源 FBX/GLB 放进工程后要先跑一次 `godot --headless --import`，否则 load 不到。
static func build_from_manifest(manifest_path: String, out_path: String, register: bool,
		rig_path: String = RIG_SCENE, placeholders_path: String = PLACEHOLDERS_JSON) -> int:
	if not FileAccess.file_exists(manifest_path):
		printerr("清单不存在: %s（把 Mixamo 源文件与 clips.json 放到该目录）" % manifest_path)
		return 2
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not (parsed is Dictionary) or not (parsed.get("clips") is Dictionary):
		printerr("清单格式错误: " + manifest_path)
		return 2
	var manifest: Dictionary = parsed
	var fps := int(manifest.get("fps", 30))
	var base_dir := manifest_path.get_base_dir()

	var rig_scene := load(rig_path) as PackedScene
	if rig_scene == null:
		printerr("base_rig 加载失败: " + rig_path)
		return 1
	var rig := rig_scene.instantiate()
	var dst_skel := find_first(rig, "Skeleton3D") as Skeleton3D
	if dst_skel == null:
		printerr("base_rig 里没有 Skeleton3D")
		rig.free()
		return 1

	var lib: AnimationLibrary = load(out_path) if ResourceLoader.exists(out_path) else null
	if lib == null:
		lib = AnimationLibrary.new()
	var done: Array = []
	var failed: PackedStringArray = []
	var clips: Dictionary = manifest["clips"]
	for key in clips:
		var spec = clips[key]
		if not (spec is Dictionary) or not spec.has("file"):
			printerr("[%s] 条目缺 file" % key)
			failed.append(str(key))
			continue
		var file_path: String = base_dir.path_join(str(spec["file"]))
		var scene := load(file_path) as PackedScene
		if scene == null:
			printerr("[%s] 源文件未导入或不存在: %s" % [key, file_path])
			failed.append(str(key))
			continue
		var src := scene.instantiate()
		var src_skel := find_first(src, "Skeleton3D") as Skeleton3D
		var player := find_first(src, "AnimationPlayer") as AnimationPlayer
		if src_skel == null or player == null or player.get_animation_list().is_empty():
			printerr("[%s] 源文件缺 Skeleton3D 或动画: %s" % [key, file_path])
			failed.append(str(key))
			src.free()
			continue
		var anim_name := str(spec.get("animation", player.get_animation_list()[0]))
		if not player.has_animation(anim_name):
			printerr("[%s] 源文件里没有动画 %s，可选: %s" % [key, anim_name, ", ".join(player.get_animation_list())])
			failed.append(str(key))
			src.free()
			continue
		var opts: Dictionary = (spec as Dictionary).duplicate()
		if not opts.has("fps"):
			opts["fps"] = fps
		var stats := {}
		var anim := retarget(src, src_skel, player.get_animation(anim_name), dst_skel, opts, stats)
		src.free()
		if lib.has_animation(key):
			lib.remove_animation(key)
		lib.add_animation(key, anim)
		done.append(str(key))
		print("[%s] <- %s#%s  映射骨=%d 帧=%d 长=%.2fs 髋比=%.3f 朝向修正=%.0f° 源缺骨=%s" % [key, str(spec["file"]), anim_name,
			stats.mapped, stats.frames, stats.length, stats.hips_ratio, stats.facing_fix_deg, ", ".join(stats.missing_source_bones)])
	rig.free()

	if done.is_empty():
		printerr("没有成功转换任何 clip")
		return 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	var err := ResourceSaver.save(lib, out_path)
	if err != OK:
		printerr("保存动画库失败 err=%d: %s" % [err, out_path])
		return 1
	print("动画库已写入 %s（共 %d 条 clip）" % [out_path, lib.get_animation_list().size()])
	if register:
		var added := register_real_clips(placeholders_path, done)
		print("anim_placeholders.json real_clips 新增 %d 条" % added)
	if failed.size() > 0:
		printerr("失败 %d 条: %s" % [failed.size(), ", ".join(failed)])
		return 1
	return 0
