extends GdUnitTestSuite

const TABLE := preload("res://modules/avatar/data/slot_table.tres")

func test_has_14_slots() -> void:
	assert_int(TABLE.slots.size()).is_equal(14)

func test_required_slots_have_defaults() -> void:
	for s in TABLE.slots:
		if s.required:
			assert_str(s.default_part).is_not_empty()

func test_lookup() -> void:
	assert_object(TABLE.slot(&"cloth")).is_not_null()
	assert_object(TABLE.slot(&"nope")).is_null()

func test_default_config_covers_all_slots() -> void:
	var cfg := TABLE.default_config()
	assert_int(cfg.slots.size()).is_equal(14)
	assert_str(cfg.slots[&"body"]).is_equal("body00")
	assert_str(cfg.slots[&"backpack"]).is_equal("")
