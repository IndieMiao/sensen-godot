extends GdUnitTestSuite

const MANIFEST := "res://assets/avatar/parts_manifest.json"
const BASE_RIG_SCENE := "res://assets/avatar/base/base_rig.tscn"

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

func test_mesh_part_skin_bind_names_match_base_rig_bones() -> void:
	## 骨骼名一致性守护：mesh 部件的 skin bind 名必须都在基础骨架的骨骼名集合内，
	## 否则装配时 Skeleton3D 会按名找不到骨骼、静默挂空（网格不跟随骨骼动），
	## 肉眼在编辑器里也不一定能立刻发现。
	if not FileAccess.file_exists(MANIFEST) or not FileAccess.file_exists(BASE_RIG_SCENE):
		push_warning("转换产物或基础骨架缺失，跳过")
		return
	var base_scene := load(BASE_RIG_SCENE) as PackedScene
	var base_inst: Node = base_scene.instantiate()
	var skel := _find_skeleton_3d(base_inst)
	if skel == null:
		push_warning("base_rig 场景内找不到 Skeleton3D，跳过")
		base_inst.free()
		return
	var bone_names := {}
	for i in skel.get_bone_count():
		bone_names[skel.get_bone_name(i)] = true
	base_inst.free()

	var cat := PartCatalog.load_from_file(MANIFEST)
	assert_object(cat).is_not_null()
	for id in cat.all_ids():
		var meta := cat.part(id)
		if meta.attach != "mesh":
			continue
		var def := load(meta.res_path) as AvatarPartDef
		if def == null or def.skin == null:
			continue
		var skin: Skin = def.skin
		for i in skin.get_bind_count():
			var bind_name := skin.get_bind_name(i)
			assert_bool(bone_names.has(bind_name)).append_failure_message(
				"%s: skin bind[%d] 名 '%s' 不在 base_rig 骨骼名集合内" % [id, i, bind_name]
			).is_true()

func _find_skeleton_3d(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var found := _find_skeleton_3d(c)
		if found:
			return found
	return null

func test_eyes_material_is_pure_black() -> void:
	## 回归守护（2026-08-29 定案）：T_eye 贴图有瑕疵，眼睛在任何场景一律纯黑——
	## eyes00 的 albedo 必须指向共享黑图 T_black，重跑转换管线也不得回退到 T_eye。
	const EYES := "res://assets/avatar/parts/eyes00.res"
	if not FileAccess.file_exists(EYES):
		return
	var def := load(EYES) as AvatarPartDef
	assert_object(def).is_not_null()
	var mat := def.mesh.surface_get_material(0) as ShaderMaterial
	var tex: Texture2D = mat.get_shader_parameter("albedo_tex")
	assert_object(tex).is_not_null()
	assert_str(tex.resource_path).is_equal("res://assets/avatar/common/T_black.png")
