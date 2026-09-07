class_name ImagePrep
extends RefCounted
## 选图后的统一预处理：读文件 → 长边缩到 max_side → JPEG。返回 {path, bytes, width, height, mime}，读不出返回 {}。
## 用户相册里的图动辄 12MP / HEIC；上传前压到 2048 边、约 85% 质量，一张几百 KB，R2 与流量都省。
## HEIC / EXIF 方向在原生层（iOS PHPicker 桥）已经转成正向 JPEG；这里只认 Image 能读的格式。

const DEFAULT_MAX_SIDE := 2048
const DEFAULT_QUALITY := 0.85

static func prepare(path: String, max_side := DEFAULT_MAX_SIDE, quality := DEFAULT_QUALITY) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var img := Image.new()
	if img.load(path) != OK or img.is_empty():
		return {}
	return from_image(img, path, max_side, quality)

static func from_image(img: Image, path: String, max_side := DEFAULT_MAX_SIDE, quality := DEFAULT_QUALITY) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var longest := maxi(w, h)
	if longest <= 0:
		return {}
	if max_side > 0 and longest > max_side:
		var f := float(max_side) / float(longest)
		img.resize(maxi(1, roundi(w * f)), maxi(1, roundi(h * f)), Image.INTERPOLATE_LANCZOS)
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	var bytes := img.save_jpg_to_buffer(clampf(quality, 0.1, 1.0))
	if bytes.is_empty():
		return {}
	return {"path": path, "bytes": bytes, "width": img.get_width(), "height": img.get_height(), "mime": "image/jpeg"}
