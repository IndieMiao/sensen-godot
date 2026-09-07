class_name PhotoPicker
extends RefCounted
## C3：系统选图器的统一入口。后端按可用性选：
## 1. 原生单例 SensenPhotoPicker（iOS PHPicker GDExtension，native/photo_picker；Android Photo Picker 插件同名）：
##    不弹相册权限，选完在原生层缩图转 JPEG 落临时目录，只回路径；
## 2. DisplayServer 原生文件框（桌面 macOS / Windows；Android 4.4+ 是系统文档选择器）；
## 3. 都没有 → {ok:false, code:"UNSUPPORTED"}。
## 选完统一过 ImagePrep（长边 2048、JPEG、带尺寸），feed 发布器与 IM 图片消息直接拿 bytes 上传。
## picker 可注入（func(max_count) -> 路径数组，可 await），测试不依赖真机。

const MAX_COUNT := 9
const SINGLETON := "SensenPhotoPicker"

var picker: Callable
var max_side := ImagePrep.DEFAULT_MAX_SIDE
var jpeg_quality := ImagePrep.DEFAULT_QUALITY

static func native_available() -> bool:
	if not Engine.has_singleton(SINGLETON):
		return false
	return bool(Engine.get_singleton(SINGLETON).call("is_available"))

static func dialog_available() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)

static func available() -> bool:
	return native_available() or dialog_available()

## 选图并预处理。返回 {ok, code, items: [{path, bytes, width, height, mime}]}；用户取消 → ok=true、items 空。
func pick(max_count := MAX_COUNT) -> Dictionary:
	var count := clampi(max_count, 1, MAX_COUNT)
	var paths := PackedStringArray()
	if picker.is_valid():
		paths = PackedStringArray(await picker.call(count))
	elif native_available():
		paths = await _pick_native(count)
	elif dialog_available():
		paths = await _pick_dialog(count)
	else:
		return {"ok": false, "code": "UNSUPPORTED", "items": []}
	var items: Array = []
	for p in paths:
		var prepared := ImagePrep.prepare(str(p), max_side, jpeg_quality)
		if prepared.is_empty():
			continue
		items.append(prepared)
		if items.size() >= count:
			break
	return {"ok": true, "code": "", "items": items}

func _pick_native(count: int) -> PackedStringArray:
	var s: Object = Engine.get_singleton(SINGLETON)
	if not bool(s.call("pick_images", count, max_side, jpeg_quality)):
		return PackedStringArray()
	var result: Array = await s.picked
	if result.size() >= 2 and not str(result[1]).is_empty():
		push_warning("PhotoPicker: native picker failed: %s" % str(result[1]))
		return PackedStringArray()
	return PackedStringArray(result[0]) if result.size() > 0 else PackedStringArray()

## 桌面：系统文件框。lambda 捕获的是副本，结果要放进字典这种引用类型才带得出来。
func _pick_dialog(count: int) -> PackedStringArray:
	var box := {"done": false, "paths": PackedStringArray()}
	var on_done := func(status: bool, selected: PackedStringArray, _filter: int) -> void:
		if status:
			box["paths"] = selected
		box["done"] = true
	var mode := DisplayServer.FILE_DIALOG_MODE_OPEN_FILES if count > 1 else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE
	DisplayServer.file_dialog_show(tr("Choose photos"), "", "", false, mode, PackedStringArray(["*.jpg,*.jpeg,*.png,*.webp,*.bmp;Images"]), on_done)
	var tree := Engine.get_main_loop() as SceneTree
	while not bool(box["done"]) and tree != null:
		await tree.process_frame
	var paths: PackedStringArray = box["paths"]
	if paths.size() > count:
		paths.resize(count)
	return paths
