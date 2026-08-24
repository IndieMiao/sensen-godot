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

func test_reframe_pulls_back_further_for_tall_hat() -> void:
	var plain := Node3D.new(); add_child(auto_free(plain))
	plain.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	var hatted := Node3D.new(); add_child(auto_free(hatted))
	hatted.add_child(_box(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 1.6, 0.4)))
	hatted.add_child(_box(Vector3(-0.5, 1.6, -0.5), Vector3(1.0, 0.6, 1.0)))
	var a := _cam(); a.reframe(plain, Vector2(360, 800))
	var b := _cam(); b.reframe(hatted, Vector2(360, 800))
	assert_float(b.position.z).is_greater(a.position.z)

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
