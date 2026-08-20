extends GdUnitTestSuite

var rig: AvatarRig
var loader: PartLoader

## 测试用槽位表：只留 cloth(required)/glass/mask，避免依赖美术资产
func _mini_slot_table() -> AvatarSlotTable:
	var t := AvatarSlotTable.new()
	for def in [[&"cloth", true, "fx_mesh_cloth"], [&"glass", false, ""], [&"mask", false, ""]]:
		var s := AvatarSlotDef.new()
		s.slot_name = def[0]
		s.attach_bone = "Bone_A"
		s.required = def[1]
		s.default_part = def[2]
		t.slots.append(s)
	return t

func before_test() -> void:
	loader = PartLoader.new()
	loader.catalog = PartCatalog.load_from_file("res://tests/fixtures/manifest_rig.json")
	loader.cache = PartCache.new()
	add_child(loader)
	rig = AvatarRig.new()
	rig.slot_table = _mini_slot_table()
	rig.assembler = AvatarAssemblerDirect.new()  # 本套用例断言 Direct 策略的节点结构，不随默认策略变化
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	skel.add_bone("Bone_A")
	rig.add_child(skel)
	add_child(rig)
	rig.setup(loader)

func after_test() -> void:
	rig.queue_free()
	loader.queue_free()

func _await_signal(sig: Signal, frames := 300) -> Array:
	var hits: Array = []
	var cb := func(a = null, b = null, c = null): hits.append([a, b, c])
	sig.connect(cb)
	for i in frames:
		if hits.size() > 0:
			break
		await get_tree().process_frame
	sig.disconnect(cb)
	return hits

func test_apply_config_atomic_show() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth"
	cfg.slots[&"glass"] = "fx_socket_glass"
	rig.apply_config(cfg)
	assert_bool(rig.visible).is_false()
	var hits := await _await_signal(rig.config_applied)
	assert_int(hits.size()).is_equal(1)
	assert_bool(rig.visible).is_true()
	assert_object(rig.skeleton.get_node_or_null("mesh_cloth")).is_not_null()
	assert_object(rig.skeleton.get_node_or_null("socket_glass")).is_not_null()

func test_equip_switch_and_current_config() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied)
	rig.equip(&"cloth", "fx_mesh_cloth2")
	await _await_signal(rig.slot_applied)
	assert_str(rig.current_config().slots[&"cloth"]).is_equal("fx_mesh_cloth2")
	var mi: MeshInstance3D = rig.skeleton.get_node("mesh_cloth")
	assert_str(String(mi.get_meta("part_id"))).is_equal("fx_mesh_cloth2")

func test_rapid_switch_last_wins() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied)
	rig.equip(&"cloth", "fx_mesh_cloth2")
	rig.equip(&"cloth", "fx_mesh_cloth")
	for i in 120:
		await get_tree().process_frame
	assert_str(rig.current_config().slots[&"cloth"]).is_equal("fx_mesh_cloth")

func test_failed_part_keeps_slot_and_emits() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied)
	var fails := []
	rig.part_load_failed.connect(func(s, p, e): fails.append([s, p, e]))
	rig.equip(&"mask", "fx_broken")
	for i in 300:
		if fails.size() > 0:
			break
		await get_tree().process_frame
	assert_int(fails.size()).is_equal(1)
	assert_str(rig.current_config().slots.get(&"mask", "")).is_equal("")

func test_unequip_required_falls_back_to_default() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth2"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied)
	rig.unequip(&"cloth")
	for i in 120:
		await get_tree().process_frame
	assert_str(rig.current_config().slots[&"cloth"]).is_equal("fx_mesh_cloth")

func test_unequip_optional_clears_socket() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_mesh_cloth"
	cfg.slots[&"glass"] = "fx_socket_glass"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied)
	rig.unequip(&"glass")
	for i in 60:
		await get_tree().process_frame
	assert_object(rig.skeleton.get_node_or_null("socket_glass")).is_null()

func test_initial_required_failure_falls_back_wrong_type() -> void:
	var fails := []
	var cb := func(s, p, e): fails.append([s, p, e])
	rig.part_load_failed.connect(cb)
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_wrongtype"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied, 600)
	rig.part_load_failed.disconnect(cb)
	assert_bool(rig.visible).is_true()
	assert_str(rig.current_config().slots[&"cloth"]).is_equal("fx_mesh_cloth")
	assert_int(fails.size()).is_greater(0)

func test_initial_required_failure_falls_back_load_error() -> void:
	var fails := []
	var cb := func(s, p, e): fails.append([s, p, e])
	rig.part_load_failed.connect(cb)
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "fx_broken"
	rig.apply_config(cfg)
	await _await_signal(rig.config_applied, 600)
	rig.part_load_failed.disconnect(cb)
	assert_bool(rig.visible).is_true()
	assert_str(rig.current_config().slots[&"cloth"]).is_equal("fx_mesh_cloth")
	assert_int(fails.size()).is_greater(0)
