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
