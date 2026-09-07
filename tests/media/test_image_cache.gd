extends GdUnitTestSuite
## ImageCache：按魔数解码、同 URL 只取一次、失败不缓存、并发等待合并。

var fetches: Array = []
var bytes_by_url: Dictionary = {}

func before_test() -> void:
	fetches = []
	bytes_by_url = {}

func _png_bytes(w: int, h: int) -> PackedByteArray:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.SEA_GREEN)
	return img.save_png_to_buffer()

func _cache() -> ImageCache:
	return ImageCache.new(func(url: String) -> ApiClient.Response:
		fetches.append(url)
		if not bytes_by_url.has(url):
			return ApiClient.Response.new(true, 404, {}, "")
		var r := ApiClient.Response.new(true, 200, {}, "")
		r.bytes = bytes_by_url[url]
		return r)

func test_decodes_png_and_jpeg_by_magic_and_caches_per_url() -> void:
	bytes_by_url["http://x/a.png"] = _png_bytes(8, 4)
	var jpg := Image.create_empty(6, 3, false, Image.FORMAT_RGB8)
	jpg.fill(Color.RED)
	bytes_by_url["http://x/b.jpg"] = jpg.save_jpg_to_buffer(0.9)
	var c := _cache()
	var a: Texture2D = await c.get_texture("http://x/a.png")
	assert_object(a).is_not_null()
	assert_int(a.get_width()).is_equal(8)
	var b: Texture2D = await c.get_texture("http://x/b.jpg")
	assert_int(b.get_height()).is_equal(3)
	var again: Texture2D = await c.get_texture("http://x/a.png")
	assert_object(again).is_same(a)
	assert_int(fetches.size()).is_equal(2)

func test_failure_is_not_cached_and_garbage_is_rejected() -> void:
	var c := _cache()
	assert_object(await c.get_texture("http://x/missing.png")).is_null()
	assert_object(await c.get_texture("http://x/missing.png")).is_null()
	assert_int(fetches.size()).is_equal(2)
	bytes_by_url["http://x/junk"] = PackedByteArray([1, 2, 3, 4, 5, 6])
	assert_object(await c.get_texture("http://x/junk")).is_null()
	assert_object(await c.get_texture("")).is_null()
	assert_object(ImageCache.decode(PackedByteArray())).is_null()
