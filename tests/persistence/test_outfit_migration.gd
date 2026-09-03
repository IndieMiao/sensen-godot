extends GdUnitTestSuite
## 存档里引用了目录里已经没有的部件时，读档必须降级而不是崩在脸上。
##
## 真实触发场景（2026-09-02 真机复现）：把 cloth87/hairhat101 这批特殊材质部件下架后，
## 装了旧包、存过档的机器再打开换装房，存档仍写着 "cloth87"。旧行为是把这个 id 原样
## 交给 rig，装配失败弹出 `Couldn't load Outfits Style 1. Previous look kept.`——
## 演示机上一进换装房就是一条报错。部件池本来就会随版本增删，读档必须自己兜住。

const USER := "migration_user"

var _service: Node


func before_test() -> void:
	Avatar.store.base_dir = "user://test_outfit_migration"
	Avatar.user_id = USER
	_clean()


func after_test() -> void:
	_clean()
	Avatar.store.base_dir = "user://avatar"
	Avatar.user_id = "local"


func _clean() -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.dir_exists("test_outfit_migration"):
		for f in DirAccess.get_files_at("user://test_outfit_migration"):
			dir.remove("test_outfit_migration/" + f)
		dir.remove("test_outfit_migration")


## 直接写盘，绕开 save_outfit——要造的正是"这个 id 现在已经不存在了"的存档，
## 而 save_outfit 之后若有清洗逻辑就写不进去了。
func _write_raw(slots: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://test_outfit_migration")
	var cfg := AvatarConfig.new()
	cfg.slots = slots
	var f := FileAccess.open("user://test_outfit_migration/outfit_%s.json" % USER, FileAccess.WRITE)
	f.store_string(cfg.to_json_text())
	f.close()


func test_unknown_part_in_required_slot_falls_back_to_default() -> void:
	_write_raw({&"cloth": "cloth87", &"hairHat": "hairhat0", &"shoes": "shoes0",
		&"body": "body00", &"eyes": "eyes00"})
	var cfg := Avatar.load_outfit()
	assert_object(cfg).is_not_null()
	var expected: String = Avatar.slot_table.slot(&"cloth").default_part
	assert_str(cfg.slots[&"cloth"]).is_equal(expected)
	assert_bool(Avatar.catalog.has_part(cfg.slots[&"cloth"])).is_true()


func test_unknown_part_in_optional_slot_becomes_empty() -> void:
	_write_raw({&"glass": "glass4", &"cloth": "cloth0"})
	var cfg := Avatar.load_outfit()
	assert_str(cfg.slots[&"glass"]).is_empty()


func test_known_parts_and_empty_slots_are_left_alone() -> void:
	var keep: String = Avatar.catalog.parts_for_slot(&"cloth")[0].id
	_write_raw({&"cloth": keep, &"glass": ""})
	var cfg := Avatar.load_outfit()
	assert_str(cfg.slots[&"cloth"]).is_equal(keep)
	assert_str(cfg.slots[&"glass"]).is_empty()


func test_every_slot_of_a_loaded_outfit_is_wearable() -> void:
	## 兜底不变量：读回来的每个非空槽位都必须能在目录里找到。
	_write_raw({&"cloth": "cloth87", &"hairHat": "hairhat101", &"glass": "glass4",
		&"shoes": "shoes0", &"body": "body00", &"eyes": "eyes00"})
	var cfg := Avatar.load_outfit()
	for slot in cfg.slots:
		var id := String(cfg.slots[slot])
		if id.is_empty():
			continue
		assert_bool(Avatar.catalog.has_part(id)).append_failure_message(
			"槽位 %s 读回了目录里没有的部件 %s" % [slot, id]).is_true()
