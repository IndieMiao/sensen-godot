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
