class_name ImageCache
extends RefCounted
## 网络图片 → Texture2D 的小缓存：同一 URL 只下一次，正在下的合并等待；解码按魔数认 JPEG / PNG / WebP。
## fetcher 可注入（func(url) -> ApiClient.Response，可 await）；默认由 Net 用 client.get_bytes 装配。

signal loaded(url: String)

const MAX_ENTRIES := 64

var fetcher: Callable
var textures: Dictionary = {}
var order: Array = []
var pending: Dictionary = {}
var fetch_count := 0

func _init(p_fetcher := Callable()) -> void:
	fetcher = p_fetcher

## 取图；失败返回 null（不缓存失败，下次再试）。
func get_texture(url: String) -> Texture2D:
	if url.is_empty():
		return null
	if textures.has(url):
		return textures[url]
	if pending.has(url):
		while pending.has(url):
			await loaded
		return textures.get(url)
	pending[url] = true
	var tex: Texture2D = null
	if fetcher.is_valid():
		fetch_count += 1
		var r = await fetcher.call(url)
		if r is ApiClient.Response and r.is_success():
			tex = decode(r.bytes)
	pending.erase(url)
	if tex != null:
		textures[url] = tex
		order.append(url)
		while order.size() > MAX_ENTRIES:
			textures.erase(order.pop_front())
	loaded.emit(url)
	return tex

static func decode(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() < 4:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49:
		err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)
