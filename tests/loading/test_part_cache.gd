extends GdUnitTestSuite

func test_put_get_and_touch() -> void:
	var cache := PartCache.new()
	cache.max_bytes = 100
	var r1 := Resource.new()
	cache.put("a", r1, 40)
	assert_object(cache.get_part("a")).is_same(r1)
	assert_int(cache.total_bytes()).is_equal(40)

func test_evicts_lru_when_over_budget() -> void:
	var cache := PartCache.new()
	cache.max_bytes = 100
	cache.put("a", Resource.new(), 40)
	cache.put("b", Resource.new(), 40)
	assert_object(cache.get_part("a")).is_not_null() # touch a，b 变最旧
	cache.put("c", Resource.new(), 40)               # 超预算，踢 b
	assert_object(cache.get_part("b")).is_null()
	assert_object(cache.get_part("a")).is_not_null()
	assert_object(cache.get_part("c")).is_not_null()
	assert_int(cache.total_bytes()).is_equal(80)

func test_oversized_item_still_cached_alone() -> void:
	var cache := PartCache.new()
	cache.max_bytes = 10
	cache.put("big", Resource.new(), 999)
	assert_object(cache.get_part("big")).is_not_null()
	cache.put("b2", Resource.new(), 999)
	assert_object(cache.get_part("big")).is_null()

func test_clear() -> void:
	var cache := PartCache.new()
	cache.put("a", Resource.new(), 10)
	cache.clear()
	assert_object(cache.get_part("a")).is_null()
	assert_int(cache.total_bytes()).is_equal(0)

func test_content_repo_stub_ok() -> void:
	assert_int(ContentRepo.new().ensure_available("anything")).is_equal(OK)
