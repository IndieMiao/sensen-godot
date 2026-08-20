extends GdUnitTestSuite

func test_load_valid() -> void:
	var cat := PartCatalog.load_from_file("res://tests/fixtures/manifest_valid.json")
	assert_object(cat).is_not_null()
	assert_int(cat.size()).is_equal(3)
	assert_bool(cat.has_part("fx_cloth_a")).is_true()
	var meta := cat.part("fx_cloth_a")
	assert_str(String(meta.slot)).is_equal("cloth")
	assert_str(meta.attach).is_equal("mesh")
	assert_int(cat.parts_for_slot(&"cloth").size()).is_equal(2)
	assert_int(cat.parts_for_slot(&"shoes").size()).is_equal(0)

func test_load_missing_file_returns_null() -> void:
	assert_object(PartCatalog.load_from_file("res://tests/fixtures/nope.json")).is_null()

func test_load_bad_schema_returns_null() -> void:
	assert_object(PartCatalog.load_from_file("res://tests/fixtures/manifest_bad.json")).is_null()

func test_duplicate_id_returns_null() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/manifest_valid.json")
	var data = JSON.parse_string(text)
	data.parts.append(data.parts[0])
	var tmp := "user://dup_manifest.json"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_object(PartCatalog.load_from_file(tmp)).is_null()
