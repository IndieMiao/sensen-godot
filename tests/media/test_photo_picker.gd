extends GdUnitTestSuite
## C3：ImagePrep 缩图转 JPEG；PhotoPicker 按注入的 picker 取路径、跳过读不出的、按上限截断。

const DIR := "user://qa_test_media"

func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

func after_test() -> void:
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))

func _png(name: String, w: int, h: int, color := Color.ORANGE) -> String:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	var path := "%s/%s.png" % [DIR, name]
	assert_int(img.save_png(path)).is_equal(OK)
	return path

func test_prepare_downscales_long_side_and_encodes_jpeg() -> void:
	var big := _png("big", 3000, 1500)
	var r := ImagePrep.prepare(big, 1024, 0.8)
	assert_int(r.width).is_equal(1024)
	assert_int(r.height).is_equal(512)
	assert_str(r.mime).is_equal("image/jpeg")
	assert_str(r.path).is_equal(big)
	var bytes: PackedByteArray = r.bytes
	assert_bool(bytes.size() > 100).is_true()
	assert_int(bytes[0]).is_equal(0xFF) # JPEG SOI
	assert_int(bytes[1]).is_equal(0xD8)
	var small := _png("small", 100, 50)
	var s := ImagePrep.prepare(small, 1024)
	assert_int(s.width).is_equal(100)
	assert_int(s.height).is_equal(50)
	var back := Image.new()
	assert_int(back.load_jpg_from_buffer(s.bytes)).is_equal(OK)
	assert_int(back.get_width()).is_equal(100)

func test_prepare_rejects_missing_and_unreadable_files() -> void:
	assert_bool(ImagePrep.prepare("%s/nope.png" % DIR).is_empty()).is_true()
	assert_bool(ImagePrep.prepare("").is_empty()).is_true()
	var junk := "%s/junk.png" % DIR
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("not an image")
	f.close()
	assert_bool(ImagePrep.prepare(junk).is_empty()).is_true()

func test_pick_uses_injected_picker_skips_bad_files_and_caps_count() -> void:
	var a := _png("a", 300, 200)
	var b := _png("b", 200, 300, Color.SKY_BLUE)
	var junk := "%s/junk2.png" % DIR
	var f := FileAccess.open(junk, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	var asked: Array = []
	var pp := PhotoPicker.new()
	pp.max_side = 128
	pp.picker = func(count: int) -> PackedStringArray:
		asked.append(count)
		return PackedStringArray([a, junk, b])
	var r: Dictionary = await pp.pick(2)
	assert_bool(r.ok).is_true()
	assert_int(asked[0]).is_equal(2)
	assert_int(r.items.size()).is_equal(2)
	assert_str(r.items[0].path).is_equal(a)
	assert_int(r.items[0].width).is_equal(128)
	assert_int(r.items[0].height).is_equal(85)
	assert_str(r.items[1].path).is_equal(b)
	assert_int(r.items[1].height).is_equal(128)
	var one: Dictionary = await pp.pick(1)
	assert_int(one.items.size()).is_equal(1)
	var over: Dictionary = await pp.pick(99)
	assert_int(asked[-1]).is_equal(PhotoPicker.MAX_COUNT) # 上限 9
	assert_int(over.items.size()).is_equal(2)
	pp.picker = func(count: int) -> PackedStringArray:
		asked.append(count)
		return PackedStringArray()
	var none: Dictionary = await pp.pick(3)
	assert_bool(none.ok).is_true()
	assert_int(none.items.size()).is_equal(0)
	assert_int(asked[-1]).is_equal(3)

## 桌面进程里要么没有原生单例，要么是 macOS 空实现（is_available 恒 false）——两种情况都不能算原生可用。
func test_native_backend_is_not_available_on_desktop() -> void:
	assert_bool(PhotoPicker.native_available()).is_false()
	if Engine.has_singleton(PhotoPicker.SINGLETON):
		assert_bool(bool(Engine.get_singleton(PhotoPicker.SINGLETON).call("pick_images", 1, 2048, 0.85))).is_false()
