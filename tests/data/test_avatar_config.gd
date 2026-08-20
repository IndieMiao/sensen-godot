extends GdUnitTestSuite

func test_roundtrip_json() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "cloth1"
	cfg.slots[&"glass"] = ""
	var text := cfg.to_json_text()
	var back := AvatarConfig.from_json_text(text)
	assert_object(back).is_not_null()
	assert_str(back.slots[&"cloth"]).is_equal("cloth1")
	assert_str(back.slots[&"glass"]).is_equal("")

func test_from_json_rejects_garbage() -> void:
	assert_object(AvatarConfig.from_json_text("not json")).is_null()
	assert_object(AvatarConfig.from_json_text("[1,2]")).is_null()
	assert_object(AvatarConfig.from_json_text('{"version": 99, "slots": {}}')).is_null()
	assert_object(AvatarConfig.from_json_text('{"version": 1, "slots": {"cloth": 5}}')).is_null()

func test_changed_slots() -> void:
	var a := AvatarConfig.new(); a.slots[&"cloth"] = "cloth1"; a.slots[&"shoes"] = "shoes1"
	var b := AvatarConfig.new(); b.slots[&"cloth"] = "cloth2"; b.slots[&"shoes"] = "shoes1"; b.slots[&"glass"] = "glass1"
	var changed := a.changed_slots(b)
	changed.sort()
	assert_array(changed).contains_exactly([&"cloth", &"glass"])
