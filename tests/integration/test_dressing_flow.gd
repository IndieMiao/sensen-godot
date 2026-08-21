extends GdUnitTestSuite
## 全链路：默认装 → 换件 → 保存 → 重建 rig → 读档恢复。依赖转换产物，缺失则跳过。

func test_slot_table_defaults_exist_in_catalog() -> void:
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		push_warning("转换产物缺失，跳过")
		return
	for s in Avatar.slot_table.slots:
		if s.default_part != "":
			assert_bool(Avatar.catalog.has_part(s.default_part)).is_true()

func test_full_dressing_flow() -> void:
	if not FileAccess.file_exists("res://assets/avatar/parts_manifest.json"):
		push_warning("转换产物缺失，跳过集成测试")
		return
	Avatar.store.base_dir = "user://test_integration"
	Avatar.user_id = "it_user"
	var d := DirAccess.open("user://")
	if d and d.dir_exists("test_integration"):
		for f in DirAccess.get_files_at("user://test_integration"):
			d.remove("test_integration/" + f)
	var rig := Avatar.create_rig()
	add_child(auto_free(rig))
	rig.apply_config(Avatar.load_outfit())
	var applied := []
	rig.config_applied.connect(func(c): applied.append(c))
	for i in 600:
		if applied.size() > 0:
			break
		await get_tree().process_frame
	assert_int(applied.size()).is_equal(1)
	assert_bool(rig.visible).is_true()
	for s in Avatar.slot_table.slots:
		if s.required:
			assert_str(String(rig.current_config().slots.get(s.slot_name, ""))).is_not_empty()
	# 挑一个 cloth 槽的非当前部件换上
	var candidates := Avatar.catalog.parts_for_slot(&"cloth")
	assert_bool(candidates.size() >= 2).is_true()
	var target := ""
	for meta in candidates:
		if meta.id != rig.current_config().slots[&"cloth"]:
			target = meta.id
			break
	rig.equip(&"cloth", target)
	var slots_applied := []
	rig.slot_applied.connect(func(s, p): slots_applied.append([s, p]))
	for i in 600:
		if slots_applied.size() > 0:
			break
		await get_tree().process_frame
	assert_str(rig.current_config().slots[&"cloth"]).is_equal(target)
	# 保存 → 读回
	assert_int(Avatar.save_outfit(rig.current_config())).is_equal(OK)
	var loaded := Avatar.load_outfit()
	assert_str(loaded.slots[&"cloth"]).is_equal(target)
	# 合并策略下骨架下应只有一个 merged_mesh + 若干 socket_*
	var mesh_children := 0
	for c in rig.skeleton.get_children():
		if c is MeshInstance3D:
			mesh_children += 1
	assert_int(mesh_children).is_equal(1)
