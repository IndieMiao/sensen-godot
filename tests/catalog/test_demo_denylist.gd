extends GdUnitTestSuite
## demo denylist：剔除的部件不得出现在 parts_for_slot()——换装列表与地图随机
## 路人配置池都走它。
##
## 名单必须独立于 assets/avatar/parts_manifest.json：后者是管线产物，
## tools/pipeline/extract_parts.gd:25-32 每次转换全量重建后覆写，
## 手工写进去的字段会被静默擦除，隐藏部件下次转换后又冒出来。

const MANIFEST := "res://assets/avatar/parts_manifest.json"
const TMP := "user://test_denylist.json"

func after_test() -> void:
	DirAccess.remove_absolute(TMP)

func _write(text: String) -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func test_denied_part_disappears_from_slot_pool() -> void:
	var cat := PartCatalog.load_from_file(MANIFEST)
	if cat == null:
		push_warning("转换产物缺失，跳过")
		return
	var pool := cat.parts_for_slot(&"hairHat")
	assert_bool(pool.size() >= 2).is_true()
	var victim: String = pool[0].id
	var before := pool.size()
	assert_int(cat.apply_denylist(PackedStringArray([victim]))).is_equal(1)
	assert_int(cat.parts_for_slot(&"hairHat").size()).is_equal(before - 1)
	assert_bool(cat.has_part(victim)).is_false()

func test_unknown_id_is_ignored_not_error() -> void:
	var cat := PartCatalog.load_from_file(MANIFEST)
	if cat == null:
		return
	assert_int(cat.apply_denylist(PackedStringArray(["no_such_part"]))).is_equal(0)

func test_load_denylist_parses_ids() -> void:
	_write('{"version": 1, "hidden": ["a", "b"]}')
	var ids := PartCatalog.load_denylist(TMP)
	assert_int(ids.size()).is_equal(2)
	assert_str(ids[0]).is_equal("a")

func test_load_denylist_rejects_bad_version() -> void:
	_write('{"version": 99, "hidden": ["a"]}')
	assert_int(PartCatalog.load_denylist(TMP).size()).is_equal(0)

func test_missing_file_is_empty_not_error() -> void:
	assert_int(PartCatalog.load_denylist("user://definitely_not_here.json").size()).is_equal(0)

func test_shipped_denylist_file_is_valid() -> void:
	## 不能只调一次 load_denylist 就算验过：它对"格式正确但名单为空"和"格式写坏"
	## 都返回空数组，两者观察不到区别。所以独立解析一遍 JSON 做对照。
	## Step 7 要人工手改这个文件，写坏了只会静默变成"没剔除任何东西"。
	var path := "res://assets/avatar/demo_denylist.json"
	assert_bool(FileAccess.file_exists(path)).is_true()
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_int(typeof(data)).is_equal(TYPE_DICTIONARY)
	assert_int(int(data.get("version", -1))).is_equal(PartCatalog.DENYLIST_VERSION)
	assert_int(typeof(data.get("hidden"))).is_equal(TYPE_ARRAY)
	var hidden: Array = data.get("hidden")
	assert_int(PartCatalog.load_denylist(path).size()).is_equal(hidden.size())
