extends GdUnitTestSuite
## 取景回归：包围盒合并正确、距离随高度/宽度增长、v_offset 把角色抬到上方可用区。

func _cam() -> DressingCamera:
	var c := DressingCamera.new()
	c.drawer_height = 312.0
	c.safe_margin_top = 24.0
	c.safe_margin_bottom = 24.0
	add_child(auto_free(c))
	return c

func _box(pos: Vector3, size: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos + size * 0.5   # BoxMesh 以原点为中心
	return mi

func test_merged_aabb_unions_all_visual_children() -> void:
	var root := Node3D.new()
	add_child(auto_free(root))
	root.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	root.add_child(_box(Vector3(-0.5, 1.6, -0.5), Vector3(1.0, 0.5, 1.0)))  # 高帽子
	var box := DressingCamera.merged_aabb(root)
	assert_float(box.size.y).is_equal_approx(2.1, 0.01)
	assert_float(box.size.x).is_equal_approx(1.0, 0.01)

func test_merged_aabb_of_empty_root_is_degenerate() -> void:
	var root := Node3D.new()
	add_child(auto_free(root))
	assert_float(DressingCamera.merged_aabb(root).size.y).is_equal(0.0)

func test_merged_aabb_ignores_non_geometry_visual_instances() -> void:
	## 回归：RigActivity（modules/avatar/assembly/rig_activity.gd）会给 rig 挂一个
	## VisibleOnScreenNotifier3D 用于可见性节流，其 aabb 是硬编码的通用剔除框
	## AABB((-0.5,0,-0.5),(1,2,1))，与角色实际渲染范围无关。它只继承 VisualInstance3D、
	## 不继承 GeometryInstance3D，_visuals() 必须把它排除，否则会把取景撑大到剔除框的尺寸。
	var root := Node3D.new()
	add_child(auto_free(root))
	root.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.aabb = AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 2.0, 1.0))
	root.add_child(notifier)
	auto_free(notifier)
	var box := DressingCamera.merged_aabb(root)
	assert_float(box.size.y).is_equal_approx(1.6, 0.01)
	assert_float(box.size.x).is_equal_approx(0.4, 0.01)

func test_reframe_sets_flat_perspective_and_no_rotation() -> void:
	var cam := _cam()
	var root := Node3D.new()
	add_child(auto_free(root))
	root.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	cam.reframe(root, Vector2(360, 800))
	assert_float(cam.fov).is_equal(35.0)
	assert_vector(cam.rotation).is_equal_approx(Vector3.ZERO, Vector3(0.001, 0.001, 0.001))
	assert_float(cam.position.z).is_greater(4.0)     # 拉远，透视变平
	assert_bool(cam.v_offset < 0.0).is_true()        # 负值把角色抬到画面上方

func test_reframe_scale_is_identical_regardless_of_equipment() -> void:
	## 产品口径：换发型不能改变角色在画面中的比例。
	## 旧行为是按 merged_aabb 取景，戴高帽子相机就后退（实测 hairhat0 1.721m →
	## hairhat101 1.971m，差 14%，屏幕上肉眼可见地忽大忽小）。现在一律对着
	## reference_box() 取景，距离与 v_offset 必须完全一致。
	var plain := Node3D.new(); add_child(auto_free(plain))
	plain.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	var hatted := Node3D.new(); add_child(auto_free(hatted))
	hatted.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	hatted.add_child(_box(Vector3(-0.5, 1.6, -0.5), Vector3(1.0, 0.6, 1.0)))
	var a := _cam(); a.reframe(plain, Vector2(360, 800))
	var b := _cam(); b.reframe(hatted, Vector2(360, 800))
	assert_float(b.position.z).is_equal_approx(a.position.z, 0.0001)
	assert_float(b.v_offset).is_equal_approx(a.v_offset, 0.0001)
	assert_float(b.position.y).is_equal_approx(a.position.y, 0.0001)

func test_reframe_scale_is_identical_regardless_of_body_rotation() -> void:
	## 拖拽转身会改变包围盒宽度（A 字站姿侧面比正面窄）。按实际包围盒取景时画面
	## 会随转身左右"呼吸"，同样违反比例恒定。
	var facing := Node3D.new(); add_child(auto_free(facing))
	facing.add_child(_box(Vector3(-0.6, 0.0, -0.15), Vector3(1.2, 1.7, 0.3)))
	var turned := Node3D.new(); add_child(auto_free(turned))
	turned.add_child(_box(Vector3(-0.15, 0.0, -0.6), Vector3(0.3, 1.7, 1.2)))
	var a := _cam(); a.reframe(facing, Vector2(360, 800))
	var b := _cam(); b.reframe(turned, Vector2(360, 800))
	assert_float(b.position.z).is_equal_approx(a.position.z, 0.0001)

func test_each_slot_maps_to_a_body_region() -> void:
	assert_int(DressingCamera.region_for_slot(&"hairHat")).is_equal(DressingCamera.Region.HEAD)
	assert_int(DressingCamera.region_for_slot(&"glass")).is_equal(DressingCamera.Region.HEAD)
	assert_int(DressingCamera.region_for_slot(&"cloth")).is_equal(DressingCamera.Region.TORSO)
	assert_int(DressingCamera.region_for_slot(&"messengerBag")).is_equal(DressingCamera.Region.TORSO)
	assert_int(DressingCamera.region_for_slot(&"shoes")).is_equal(DressingCamera.Region.FEET)
	# 未知槽位退回全身，而不是随便推近到某处
	assert_int(DressingCamera.region_for_slot(&"body")).is_equal(DressingCamera.Region.FULL)

func test_zooming_to_a_region_moves_the_camera_closer() -> void:
	var cam := _cam()
	var root := Node3D.new(); add_child(auto_free(root))
	root.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.7, 0.4)))
	cam.reframe(root, Vector2(360, 800))
	var full_z := cam.position.z
	for region in [DressingCamera.Region.HEAD, DressingCamera.Region.TORSO,
			DressingCamera.Region.FEET]:
		cam.focus_region = region
		cam.reframe(root, Vector2(360, 800))
		assert_float(cam.position.z).is_less(full_z)
	# 推近到头部时相机要抬到头的高度，否则是从腰部仰视脸
	cam.focus_region = DressingCamera.Region.HEAD
	cam.reframe(root, Vector2(360, 800))
	assert_float(cam.position.y).is_greater(1.0)

func test_head_region_covers_normal_hair_and_starts_below_the_chin() -> void:
	## HEAD 盒不覆盖最高发型（那样普通发型头顶会空一大块），但**必须**盖住
	## 常见身高 REF_HEIGHT，否则连默认发型都要溢出，推近就没法看了。
	## 最高的几顶溢出到顶栏那条带子里，是否还在画面内由
	## test_dressing_room_layout 的 test_head_zoom_keeps_the_tallest_hair_on_screen 守。
	var head := DressingCamera.region_box(DressingCamera.Region.HEAD)
	assert_float(head.position.y + head.size.y).is_greater_equal(DressingCamera.REF_HEIGHT)
	assert_float(head.position.y + head.size.y).is_less(
		DressingCamera.REF_HEIGHT + DressingCamera.HEAD_OVERFLOW)
	# 下界要含一点肩颈做参照，但不能低到把整个胸口都框进来
	assert_float(head.position.y).is_between(0.9, 1.3)
	assert_float(head.size.x).is_less(DressingCamera.REF_WIDTH)

func test_region_zoom_keeps_scale_constant_within_a_level() -> void:
	## "换发型不改变比例"在分区取景下的正确表述：同一档里换任何部件，
	## 距离必须完全一致——分区盒也是固定的，不读实际包围盒。
	var plain := Node3D.new(); add_child(auto_free(plain))
	plain.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.7, 0.4)))
	var hatted := Node3D.new(); add_child(auto_free(hatted))
	hatted.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.7, 0.4)))
	hatted.add_child(_box(Vector3(-0.5, 1.7, -0.5), Vector3(1.0, 0.27, 1.0)))
	for region in [DressingCamera.Region.FULL, DressingCamera.Region.HEAD,
			DressingCamera.Region.TORSO, DressingCamera.Region.FEET]:
		var a := _cam(); a.focus_region = region; a.reframe(plain, Vector2(360, 800))
		var b := _cam(); b.focus_region = region; b.reframe(hatted, Vector2(360, 800))
		assert_float(b.position.z).is_equal_approx(a.position.z, 0.0001)
		assert_float(b.v_offset).is_equal_approx(a.v_offset, 0.0001)

func test_reference_box_is_body_scaled_and_hair_only_overflows_a_little() -> void:
	## 参考盒按**身体**定，不含高发型余量——否则短发角色要连带缩小 15%，头顶空一大块。
	## 于是两条边界都要守：
	##   1. 光身体（默认装扮）必须装得下 REF_HEIGHT，否则脚或头当场被裁；
	##   2. 最高的发型溢出量不超过 HEAD_OVERFLOW，溢出部分才塞得进顶栏那条透明带子。
	## 新增更高的部件时这里会红，提示重新权衡 REF_HEIGHT / HEAD_OVERFLOW。
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		push_warning("转换产物缺失，跳过")
		return
	var rig: AvatarRig = Avatar.create_rig()
	add_child(auto_free(rig))
	rig.apply_config(Avatar.slot_table.default_config())
	for i in 900:
		if not rig.is_busy():
			break
		await get_tree().process_frame
	assert_float(DressingCamera.merged_aabb(rig).size.y).is_less_equal(DressingCamera.REF_HEIGHT)
	var ceiling := DressingCamera.REF_HEIGHT + DressingCamera.HEAD_OVERFLOW
	for meta in Avatar.catalog.parts_for_slot(&"hairHat"):
		rig.equip(&"hairHat", meta.id)
		for i in 900:
			if not rig.is_busy():
				break
			await get_tree().process_frame
		var box := DressingCamera.merged_aabb(rig)
		assert_float(box.size.y).is_less_equal(ceiling)
		assert_float(box.size.x).is_less_equal(DressingCamera.REF_WIDTH)

func test_reframe_is_noop_for_empty_subject() -> void:
	var cam := _cam()
	cam.position = Vector3(1.0, 2.0, 3.0)
	var root := Node3D.new(); add_child(auto_free(root))
	cam.reframe(root, Vector2(360, 800))
	assert_vector(cam.position).is_equal_approx(Vector3(1.0, 2.0, 3.0), Vector3(0.001, 0.001, 0.001))

func test_reframe_is_noop_when_drawer_fills_screen() -> void:
	var cam := _cam()
	cam.drawer_height = 800.0
	cam.position = Vector3(1.0, 2.0, 3.0)
	var root := Node3D.new(); add_child(auto_free(root))
	root.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	cam.reframe(root, Vector2(360, 800))
	assert_vector(cam.position).is_equal_approx(Vector3(1.0, 2.0, 3.0), Vector3(0.001, 0.001, 0.001))
