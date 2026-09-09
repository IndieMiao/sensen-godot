extends GdUnitTestSuite
## Mixamo → dt 骨架离线重定向（tools/pipeline/mixamo_retarget.gd）。
## 合成源骨架的用例守数学；Xbot 样例（tmp/mixamo_fixture，不入库）存在时再跑一条真数据用例。

const RIG_SCENE := "res://assets/avatar/base/base_rig.tscn"
const FIXTURE := "res://tmp/mixamo_fixture/Xbot.glb"
const EPS := 1e-3

func test_normalize_source_bone_names() -> void:
	assert_str(MixamoRetarget.normalize_source_bone("mixamorig:Hips")).is_equal("Hips")
	assert_str(MixamoRetarget.normalize_source_bone("mixamorig_LeftArm")).is_equal("LeftArm")
	assert_str(MixamoRetarget.normalize_source_bone("mixamorig1_Spine2")).is_equal("Spine2")
	assert_str(MixamoRetarget.normalize_source_bone("Armature:RightHand")).is_equal("RightHand")
	assert_str(MixamoRetarget.normalize_source_bone("Hips")).is_equal("Hips")

func test_bone_map_targets_exist_in_rig() -> void:
	var dst := _rig_skeleton()
	for dname in MixamoRetarget.BONE_MAP:
		assert_int(dst.find_bone(dname)).override_failure_message("映射表里的目标骨 %s 不在 base_rig" % dname).is_not_equal(-1)

func test_rotation_delta_is_carried_in_world_space() -> void:
	var dst := _rig_skeleton()
	var src := _synthetic_source(0.0)
	var stats := {}
	var anim := MixamoRetarget.retarget(src.root, src.skel, src.anim, dst, {"fps": 10, "loop": false, "in_place": true}, stats)
	assert_int(stats.mapped).is_equal(7)
	assert_float(anim.length).is_equal_approx(1.0, EPS)
	assert_int(anim.loop_mode).is_equal(Animation.LOOP_NONE)
	assert_int(anim.get_track_count()).is_equal(dst.get_bone_count() * 2)
	# 末帧：源 LeftArm 绕世界 Z 转了 90°，目标 Shoulder_L 的世界旋转应 = Rz90 × 其世界 rest；
	# 父骨 Scapula_L 映射到的 LeftShoulder 没动，保持 rest。
	var rests := MixamoRetarget.global_rests(dst)
	var sl := dst.find_bone("Shoulder_L")
	var parent_rot := rests[dst.get_bone_parent(sl)].basis.get_rotation_quaternion()
	var expected_global := Quaternion(Vector3(0, 0, 1), PI / 2.0) * rests[sl].basis.get_rotation_quaternion()
	var expected_local := parent_rot.inverse() * expected_global
	var got := _key_at(anim, "Skeleton3D:Shoulder_L", Animation.TYPE_ROTATION_3D, 1.0) as Quaternion
	assert_float(absf(got.dot(expected_local))).override_failure_message("Shoulder_L 末帧局部旋转 %s ≠ 期望 %s" % [got, expected_local]).is_greater(1.0 - EPS)
	# 首帧未动 → 等于 rest。
	var got0 := _key_at(anim, "Skeleton3D:Shoulder_L", Animation.TYPE_ROTATION_3D, 0.0) as Quaternion
	var rest_local := dst.get_bone_rest(sl).basis.get_rotation_quaternion()
	assert_float(absf(got0.dot(rest_local))).is_greater(1.0 - EPS)

func test_unmapped_bones_pinned_to_rest_with_single_key() -> void:
	var dst := _rig_skeleton()
	var src := _synthetic_source(0.0)
	var anim := MixamoRetarget.retarget(src.root, src.skel, src.anim, dst, {"fps": 10})
	var cup := dst.find_bone("Cup_R")
	var t := _track(anim, "Skeleton3D:Cup_R", Animation.TYPE_ROTATION_3D)
	assert_int(anim.track_get_key_count(t)).is_equal(1)
	var q := anim.track_get_key_value(t, 0) as Quaternion
	assert_float(absf(q.dot(dst.get_bone_rest(cup).basis.get_rotation_quaternion()))).is_greater(1.0 - EPS)
	var tp := _track(anim, "Skeleton3D:Cup_R", Animation.TYPE_POSITION_3D)
	assert_int(anim.track_get_key_count(tp)).is_equal(1)
	assert_vector(anim.track_get_key_value(tp, 0)).is_equal_approx(dst.get_bone_rest(cup).origin, Vector3.ONE * EPS)

func test_hips_translation_scaled_by_height_and_in_place_strips_xz() -> void:
	var dst := _rig_skeleton()
	var src := _synthetic_source(0.0)
	var stats := {}
	var kept := MixamoRetarget.retarget(src.root, src.skel, src.anim, dst, {"fps": 10, "in_place": false}, stats)
	var rests := MixamoRetarget.global_rests(dst)
	var hips := dst.find_bone("Root_M")
	var ratio: float = rests[hips].origin.y / 1.0  # 合成源髋高 1.0 m（100 cm × 0.01）
	assert_float(stats.hips_ratio).is_equal_approx(ratio, EPS)
	var parent_inv := rests[dst.get_bone_parent(hips)].affine_inverse()
	# 源髋末帧位移 (+0.2, +0.1, 0) m
	var expected_kept: Vector3 = parent_inv * (rests[hips].origin + Vector3(0.2, 0.1, 0.0) * ratio)
	assert_vector(_key_at(kept, "Skeleton3D:Root_M", Animation.TYPE_POSITION_3D, 1.0)).is_equal_approx(expected_kept, Vector3.ONE * EPS)
	var in_place := MixamoRetarget.retarget(src.root, src.skel, src.anim, dst, {"fps": 10, "in_place": true})
	var expected_in_place: Vector3 = parent_inv * (rests[hips].origin + Vector3(0.0, 0.1, 0.0) * ratio)
	assert_vector(_key_at(in_place, "Skeleton3D:Root_M", Animation.TYPE_POSITION_3D, 1.0)).is_equal_approx(expected_in_place, Vector3.ONE * EPS)

func test_source_facing_backwards_is_corrected() -> void:
	# 源角色整体绕 Y 转 180°（背朝相机），重定向结果必须与正朝时一致。
	var dst := _rig_skeleton()
	var front := _synthetic_source(0.0)
	var back := _synthetic_source(PI)
	var stats_back := {}
	var a := MixamoRetarget.retarget(front.root, front.skel, front.anim, dst, {"fps": 10, "in_place": false})
	var b := MixamoRetarget.retarget(back.root, back.skel, back.anim, dst, {"fps": 10, "in_place": false}, stats_back)
	assert_float(absf(stats_back.facing_fix_deg)).is_equal_approx(180.0, 0.5)
	var qa := _key_at(a, "Skeleton3D:Shoulder_L", Animation.TYPE_ROTATION_3D, 1.0) as Quaternion
	var qb := _key_at(b, "Skeleton3D:Shoulder_L", Animation.TYPE_ROTATION_3D, 1.0) as Quaternion
	assert_float(absf(qa.dot(qb))).is_greater(1.0 - EPS)
	assert_vector(_key_at(b, "Skeleton3D:Root_M", Animation.TYPE_POSITION_3D, 1.0)).is_equal_approx(
		_key_at(a, "Skeleton3D:Root_M", Animation.TYPE_POSITION_3D, 1.0), Vector3.ONE * EPS)

func test_register_real_clips_updates_table() -> void:
	var path := "user://test_anim_placeholders.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": 1, "real_clips": ["idle"],
		"placeholders": {"till": {"clip_id": "labour_till", "status": "placeholder"}}}))
	f.close()
	assert_int(MixamoRetarget.register_real_clips(path, ["labour_till", "idle"])).is_equal(1)
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_array(table.real_clips).contains_exactly(["idle", "labour_till"])
	assert_str(str(table.placeholders.till.status)).is_equal("real")
	assert_int(int(table.format)).is_equal(1)
	# 幂等：再登记一次不重复。
	assert_int(MixamoRetarget.register_real_clips(path, ["labour_till"])).is_equal(0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func test_xbot_fixture_walk_animates_knee() -> void:
	# 真数据回归：骨架不在树里时 pose 全局值不更新曾让整段动画退化成 T-pose。
	if not ResourceLoader.exists(FIXTURE):
		push_warning("Xbot 样例不存在，跳过（tmp/mixamo_fixture/Xbot.glb）")
		return
	var dst := _rig_skeleton()
	var src := (load(FIXTURE) as PackedScene).instantiate()
	auto_free(src)
	var skel := MixamoRetarget.find_first(src, "Skeleton3D") as Skeleton3D
	var ap := MixamoRetarget.find_first(src, "AnimationPlayer") as AnimationPlayer
	var stats := {}
	var anim := MixamoRetarget.retarget(src, skel, ap.get_animation("walk"), dst, {"fps": 30}, stats)
	assert_int(stats.mapped).is_equal(46)
	assert_array(stats.missing_source_bones).is_empty()
	var t := _track(anim, "Skeleton3D:Knee_R", Animation.TYPE_ROTATION_3D)
	var q0 := anim.track_get_key_value(t, 0) as Quaternion
	var spread := 0.0
	for k in anim.track_get_key_count(t):
		spread = maxf(spread, q0.angle_to(anim.track_get_key_value(t, k)))
	assert_float(spread).override_failure_message("走路时膝盖旋转幅度只有 %.3f rad，动画没打进骨骼" % spread).is_greater(0.3)

# ---------- helpers ----------

func _rig_skeleton() -> Skeleton3D:
	var rig := (load(RIG_SCENE) as PackedScene).instantiate()
	auto_free(rig)
	return MixamoRetarget.find_first(rig, "Skeleton3D") as Skeleton3D

## 合成的 Mixamo 风格源：Armature 缩放 0.01（骨骼单位 cm）、可整体绕 Y 转 yaw；
## 只含定位/朝向/测试所需的 6 根映射骨。1 秒动画：LeftArm 绕世界 Z 转 90°，Hips 平移 (+20, +10, 0) cm。
func _synthetic_source(yaw: float) -> Dictionary:
	var root := Node3D.new()
	auto_free(root)
	var armature := Node3D.new()
	armature.name = "Armature"
	armature.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 0.01), Vector3.ZERO)
	root.add_child(armature)
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	armature.add_child(skel)
	var names := ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_LeftShoulder", "mixamorig_LeftArm",
		"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_LeftUpLeg"]
	var parents := [-1, 0, 1, 2, 1, 4, 0]
	var offsets := [Vector3(0, 100, 0), Vector3(0, 20, 0), Vector3(5, 20, 0), Vector3(10, 0, 0),
		Vector3(-5, 20, 0), Vector3(-10, 0, 0), Vector3(8, -5, 0)]
	for i in names.size():
		skel.add_bone(names[i])
	for i in names.size():
		skel.set_bone_parent(i, parents[i])
		skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, offsets[i]))
	skel.reset_bone_poses()
	var anim := Animation.new()
	anim.length = 1.0
	var rt := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(rt, NodePath("Armature/Skeleton3D:mixamorig_LeftArm"))
	anim.rotation_track_insert_key(rt, 0.0, Quaternion.IDENTITY)
	anim.rotation_track_insert_key(rt, 1.0, Quaternion(Vector3(0, 0, 1), PI / 2.0))
	var pt := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pt, NodePath("Armature/Skeleton3D:mixamorig_Hips"))
	anim.position_track_insert_key(pt, 0.0, Vector3(0, 100, 0))
	anim.position_track_insert_key(pt, 1.0, Vector3(20, 110, 0))
	return {"root": root, "skel": skel, "anim": anim}

func _track(anim: Animation, path: String, type: int) -> int:
	for t in anim.get_track_count():
		if String(anim.track_get_path(t)) == path and anim.track_get_type(t) == type:
			return t
	assert_bool(false).override_failure_message("找不到轨道 %s" % path).is_true()
	return -1

func _key_at(anim: Animation, path: String, type: int, time: float) -> Variant:
	var t := _track(anim, path, type)
	var best := 0
	for k in anim.track_get_key_count(t):
		if absf(anim.track_get_key_time(t, k) - time) < absf(anim.track_get_key_time(t, best) - time):
			best = k
	return anim.track_get_key_value(t, best)
