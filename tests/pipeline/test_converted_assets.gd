extends GdUnitTestSuite

const MANIFEST := "res://assets/avatar/parts_manifest.json"

func test_manifest_loads_and_parts_valid() -> void:
	if not FileAccess.file_exists(MANIFEST):
		push_warning("转换产物缺失，跳过（先跑 Task 10/11 管线）")
		return
	var cat := PartCatalog.load_from_file(MANIFEST)
	assert_object(cat).is_not_null()
	assert_int(cat.size()).is_greater(5)
	for id in cat.all_ids():
		var meta := cat.part(id)
		var res := load(meta.res_path)
		assert_object(res).is_not_null()
		var def := res as AvatarPartDef
		assert_object(def).is_not_null()
		assert_str(def.id).is_equal(id)
		if def.attach == "mesh":
			assert_object(def.mesh).is_not_null()
		else:
			assert_object(def.scene).is_not_null()

func test_mesh_parts_have_toon_material() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var cat := PartCatalog.load_from_file(MANIFEST)
	for id in cat.all_ids():
		var def := load(cat.part(id).res_path) as AvatarPartDef
		if def and def.attach == "mesh" and def.mesh:
			var mat := def.mesh.surface_get_material(0)
			assert_object(mat).is_not_null()
			assert_bool(mat is ShaderMaterial).is_true()

func test_socket_scenes_are_not_bloated_with_whole_fbx() -> void:
	## 回归守护：glass0/hairhat0 曾因误配到共享骨架 FBX（SK_DtBase.fbx）而把全身 14 个网格都
	## 打包进 socket 场景。这里对每个 socket 部件的场景做网格数上限断言，防止同类问题
	## （错误 fbx 覆盖、mesh_name 过滤失效）再次静默产出坏资产。
	if not FileAccess.file_exists(MANIFEST):
		return
	var cat := PartCatalog.load_from_file(MANIFEST)
	for id in cat.all_ids():
		var def := load(cat.part(id).res_path) as AvatarPartDef
		if def == null or def.attach != "socket" or def.scene == null:
			continue
		var inst: Node = (def.scene as PackedScene).instantiate()
		var mesh_count := 0
		var stack: Array = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D:
				mesh_count += 1
			for c in n.get_children():
				stack.append(c)
		inst.free()
		assert_int(mesh_count).append_failure_message(
			"%s: socket 场景含 %d 个网格，疑似打包了整套 FBX" % [id, mesh_count]
		).is_less_equal(3)
