extends GdUnitTestSuite
## 全链路：默认装 → 换件 → 保存 → 重建 rig → 读档恢复。依赖转换产物，缺失则跳过。

var _saved_base_dir: String
var _saved_user_id: String
var _saved_navigation_pending: bool

func before_test() -> void:
	## Avatar 是全局 autoload 单例：本套用例会改写 store.base_dir/user_id 来隔离存档
	## 目录，若不还原会污染同一次运行里其它测试套件观察到的单例状态。
	_saved_base_dir = Avatar.store.base_dir
	_saved_user_id = Avatar.user_id
	_saved_navigation_pending = AppRouter._navigation_pending

func after_test() -> void:
	Avatar.store.base_dir = _saved_base_dir
	Avatar.user_id = _saved_user_id
	AppRouter._navigation_pending = _saved_navigation_pending

func _instantiate_room() -> Node:
	var room := (load("res://scenes/dressing_room/dressing_room.tscn") as PackedScene).instantiate()
	add_child(auto_free(room))
	return room

func _clean_dir(name: String) -> void:
	var user_dir := DirAccess.open("user://")
	if user_dir and user_dir.dir_exists(name):
		for file in DirAccess.get_files_at("user://" + name):
			user_dir.remove(name + "/" + file)
		user_dir.remove(name)

## cloth 槽里任意一个不等于 current 的部件。以前这里写死 "cloth1"/"cloth87" 二选一，
## cloth87 因材质原因下架后就成了指向不存在部件的死分支——equip 会静默失败，
## 而断言的是"换成了 target"，target 恰好是活着的那个，于是测试照样绿。
func _other_cloth_than(current: String) -> String:
	for meta in Avatar.catalog.parts_for_slot(&"cloth"):
		if meta.id != current:
			return meta.id
	return ""


func _wait_until_idle(rig: AvatarRig, frames := 600) -> void:
	for i in frames:
		if not rig.is_busy():
			return
		await get_tree().process_frame

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

func test_back_discards_draft_without_overwriting_saved_outfit() -> void:
	Avatar.store.base_dir = "user://test_dressing_back"
	Avatar.user_id = "back_user"
	_clean_dir("test_dressing_back")
	var baseline := Avatar.slot_table.default_config()
	assert_int(Avatar.save_outfit(baseline)).is_equal(OK)
	var room := _instantiate_room()
	await _wait_until_idle(room.rig)
	var target := _other_cloth_than(baseline.slots[&"cloth"])
	assert_str(target).is_not_empty()
	room.rig.equip(&"cloth", target)
	await _wait_until_idle(room.rig)
	assert_str(room.rig.current_config().slots[&"cloth"]).is_equal(target)
	# 拦住真实换场，只验证 Back 的持久化语义。
	AppRouter._navigation_pending = true
	room._on_back()
	assert_str(Avatar.load_outfit().slots[&"cloth"]).is_equal(baseline.slots[&"cloth"])

func test_done_waits_for_pending_assembly_before_saving() -> void:
	Avatar.store.base_dir = "user://test_dressing_done"
	Avatar.user_id = "done_user"
	_clean_dir("test_dressing_done")
	var room := _instantiate_room()
	await _wait_until_idle(room.rig)
	var before: String = room.rig.current_config().slots[&"cloth"]
	var target := _other_cloth_than(before)
	assert_str(target).is_not_empty()
	room.rig.equip(&"cloth", target)
	assert_bool(room.rig.is_busy()).is_true()
	AppRouter._navigation_pending = true
	assert_bool(room.is_back_navigation_locked()).is_false()
	room._on_done()
	assert_bool(room.done_button.disabled).is_true()
	assert_bool(room.is_back_navigation_locked()).is_true()
	assert_bool(AppRouter.scene_locks_back_navigation(room)).is_true()
	var loaded: AvatarConfig = null
	for i in 600:
		await get_tree().process_frame
		loaded = Avatar.store.load_outfit(Avatar.user_id)
		if loaded and String(loaded.slots.get(&"cloth", "")) == target:
			break
	assert_object(loaded).is_not_null()
	assert_str(loaded.slots[&"cloth"]).is_equal(target)

func test_save_failure_keeps_room_open_with_feedback() -> void:
	var blocker := "test_dressing_save_blocker"
	var user_dir := DirAccess.open("user://")
	if user_dir:
		user_dir.remove(blocker)
	var file := FileAccess.open("user://" + blocker, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string("not a directory")
	file.close()
	Avatar.store.base_dir = "user://" + blocker
	Avatar.user_id = "failure_user"
	var room := _instantiate_room()
	await _wait_until_idle(room.rig)
	room._on_done()
	for i in range(4):
		await get_tree().process_frame
	assert_bool(room.feedback_panel.visible).is_true()
	assert_bool(room.feedback_label.text.contains("Couldn't save")).is_true()
	assert_bool(room._committing).is_false()
	if user_dir:
		user_dir.remove(blocker)

func test_new_selection_clears_previous_failure_feedback() -> void:
	var room := _instantiate_room()
	await _wait_until_idle(room.rig)
	room._show_feedback("Couldn't load this style. Previous look kept.")
	assert_bool(room.feedback_panel.visible).is_true()
	var slot: StringName = room.parts_panel.current_slot
	var part_id: String = room.rig.desired_part(slot)
	room.parts_panel._select_part(slot, part_id)
	assert_bool(room.feedback_panel.visible).is_false()
