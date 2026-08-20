extends GdUnitTestSuite

var loader: PartLoader
var finished: Array = []
var failed: Array = []

func before_test() -> void:
	loader = PartLoader.new()
	loader.catalog = PartCatalog.load_from_file("res://tests/fixtures/manifest_valid.json")
	loader.cache = PartCache.new()
	add_child(loader)
	finished = []
	failed = []
	loader.load_finished.connect(func(rid, pid, res): finished.append([rid, pid, res]))
	loader.load_failed.connect(func(rid, pid, err): failed.append([rid, pid, err]))

func after_test() -> void:
	loader.queue_free()

func _pump(frames := 300) -> void:
	for i in frames:
		if finished.size() + failed.size() > 0:
			return
		await get_tree().process_frame

func test_load_success() -> void:
	var rid := loader.request_part("fx_cloth_a")
	await _pump()
	assert_int(finished.size()).is_equal(1)
	assert_int(finished[0][0]).is_equal(rid)
	assert_str(finished[0][1]).is_equal("fx_cloth_a")
	assert_object(finished[0][2]).is_not_null()

func test_unknown_part_fails() -> void:
	loader.request_part("nope")
	await _pump()
	assert_int(failed.size()).is_equal(1)
	assert_int(failed[0][2]).is_equal(ERR_DOES_NOT_EXIST)

func test_cache_hit_second_load() -> void:
	loader.request_part("fx_cloth_a")
	await _pump()
	finished.clear()
	loader.request_part("fx_cloth_a")
	await _pump()
	assert_int(finished.size()).is_equal(1)
	assert_object(loader.cache.get_part("fx_cloth_a")).is_not_null()

func test_cancel_suppresses_signal() -> void:
	var rid := loader.request_part("fx_cloth_b")
	loader.cancel(rid)
	for i in 60:
		await get_tree().process_frame
	assert_int(finished.size()).is_equal(0)
	assert_int(failed.size()).is_equal(0)

func test_concurrent_same_part_merged() -> void:
	var r1 := loader.request_part("fx_glass_a")
	var r2 := loader.request_part("fx_glass_a")
	for i in 300:
		if finished.size() >= 2:
			break
		await get_tree().process_frame
	assert_int(finished.size()).is_equal(2)
	assert_bool(r1 != r2).is_true()

func test_shared_res_path_per_part_id() -> void:
	var manifest_text = """
	{
		"version": 1,
		"parts": [
			{ "id": "sh_a", "slot": "shared", "attach": "mesh", "tier": 0, "pack": "builtin",
			  "res": "res://tests/fixtures/parts/fx_cloth_a.tres", "thumb": "", "unity_guid": "aa" },
			{ "id": "sh_b", "slot": "shared", "attach": "mesh", "tier": 0, "pack": "builtin",
			  "res": "res://tests/fixtures/parts/fx_cloth_a.tres", "thumb": "", "unity_guid": "bb" }
		]
	}
	"""
	var manifest_path = "user://test_manifest_shared.json"
	var file = FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(manifest_text)
	file = null

	loader.catalog = PartCatalog.load_from_file(manifest_path)

	var r1 := loader.request_part("sh_a")
	var r2 := loader.request_part("sh_b")

	for i in 300:
		if finished.size() >= 2:
			break
		await get_tree().process_frame

	assert_int(finished.size()).is_equal(2)
	# Find the signals by rid to check part_ids
	var sig_a = finished.filter(func(s): return s[0] == r1)
	var sig_b = finished.filter(func(s): return s[0] == r2)
	assert_int(sig_a.size()).is_equal(1)
	assert_int(sig_b.size()).is_equal(1)
	assert_str(sig_a[0][1]).is_equal("sh_a")
	assert_str(sig_b[0][1]).is_equal("sh_b")
	# Both should be cached separately
	assert_object(loader.cache.get_part("sh_a")).is_not_null()
	assert_object(loader.cache.get_part("sh_b")).is_not_null()

	# Cleanup
	DirAccess.remove_absolute(manifest_path)
