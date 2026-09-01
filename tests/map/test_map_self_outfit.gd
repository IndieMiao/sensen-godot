extends GdUnitTestSuite
## 回归：地图上"我"的角色必须读换装房存档，而不是默认装扮。
## 历史缺陷：map_poc.gd 写死 Avatar.slot_table.default_config()，换装闭环是断的。

const MapPoc := preload("res://scenes/map_poc/map_poc.gd")
const TEST_USER := "test_map_self"
const SAVE_PATH := "user://avatar/outfit_%s.json" % TEST_USER

var _prev_user := ""

func before_test() -> void:
	_prev_user = Avatar.user_id
	Avatar.user_id = TEST_USER

func after_test() -> void:
	Avatar.user_id = _prev_user
	DirAccess.remove_absolute(SAVE_PATH)

func test_self_config_reads_saved_outfit() -> void:
	var pool := Avatar.catalog.parts_for_slot(&"hairHat")
	if pool.size() < 2:
		push_warning("转换产物缺失或部件不足，跳过")
		return
	var cfg := Avatar.slot_table.default_config()
	var want: String = pool[pool.size() - 1].id
	cfg.slots[&"hairHat"] = want
	assert_int(Avatar.save_outfit(cfg)).is_equal(OK)

	var node = auto_free(MapPoc.new())
	assert_str(str(node.self_config().slots[&"hairHat"])).is_equal(want)

func test_self_config_falls_back_when_no_save() -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	var node = auto_free(MapPoc.new())
	assert_object(node.self_config()).is_not_null()
