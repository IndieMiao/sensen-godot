extends GdUnitTestSuite

var store: LocalOutfitStore

func before_test() -> void:
	store = LocalOutfitStore.new()
	store.base_dir = "user://test_outfits"

func after_test() -> void:
	var dir := DirAccess.open("user://")
	if dir and dir.dir_exists("test_outfits"):
		for f in DirAccess.get_files_at("user://test_outfits"):
			dir.remove("test_outfits/" + f)
		dir.remove("test_outfits")

func test_save_then_load_roundtrip() -> void:
	var cfg := AvatarConfig.new()
	cfg.slots[&"cloth"] = "cloth1"
	assert_int(store.save_outfit("u1", cfg)).is_equal(OK)
	var back := store.load_outfit("u1")
	assert_object(back).is_not_null()
	assert_str(back.slots[&"cloth"]).is_equal("cloth1")

func test_load_missing_returns_null() -> void:
	assert_object(store.load_outfit("ghost")).is_null()

func test_corrupt_file_backed_up_and_null() -> void:
	DirAccess.make_dir_recursive_absolute("user://test_outfits")
	var f := FileAccess.open("user://test_outfits/outfit_u2.json", FileAccess.WRITE)
	f.store_string("{{{ not json")
	f.close()
	assert_object(store.load_outfit("u2")).is_null()
	assert_bool(FileAccess.file_exists("user://test_outfits/outfit_u2.json.corrupt")).is_true()
	assert_bool(FileAccess.file_exists("user://test_outfits/outfit_u2.json")).is_false()

func test_user_id_sanitized() -> void:
	var cfg := AvatarConfig.new()
	assert_int(store.save_outfit("a/../b", cfg)).is_equal(OK)
	assert_bool(FileAccess.file_exists("user://test_outfits/outfit_a_.._b.json")).is_true()
