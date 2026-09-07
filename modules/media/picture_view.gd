class_name PictureView
extends TextureRect
## 网络图片的小控件：按原图宽高等比算显示框（不超过 box、只缩不放），先占位后填图；加载走 ImageCache。
## 聊天气泡与 feed 卡片共用；loaded 供测试与占位切换。

signal picture_loaded(ok: bool)

var loaded := false

func _init() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_PASS

static func fit(w: int, h: int, box: Vector2) -> Vector2:
	if w <= 0 or h <= 0:
		return Vector2(box.x * 0.6, box.x * 0.6)
	var f := minf(1.0, minf(box.x / float(w), box.y / float(h)))
	return Vector2(maxf(48.0, roundf(w * f)), maxf(48.0, roundf(h * f)))

## 先按尺寸占位，再异步取图。返回是否取到。
func show_picture(cache: ImageCache, url: String, w: int, h: int, box: Vector2) -> bool:
	custom_minimum_size = fit(w, h, box)
	var tex: Texture2D = null
	if cache != null and not url.is_empty():
		tex = await cache.get_texture(url)
	if tex != null and is_instance_valid(self):
		texture = tex
		loaded = true
	picture_loaded.emit(tex != null)
	return tex != null
