class_name AvatarThumb
extends TextureRect
## 形象缩略图控件：先放占位图标，再异步向 AvatarPortraits 要这套装扮的「证件照」。
## avatar 参数就是服务端 profile / 成员卡 / 作者卡里的 avatar 字段（AvatarConfig 的 JSON 字典，可为 null）。
## 渲不出来（headless、部件缺失、配置为空）就一直是占位图标；texture_ready 供按钮把 icon 换成真图。

signal texture_ready(texture: Texture2D)

const PLACEHOLDER_ICON := "user-round"

var side := 40.0
var config: AvatarConfig
var ready_texture: Texture2D

func _init(p_side := 40.0) -> void:
	side = p_side
	custom_minimum_size = Vector2(side, side)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture = placeholder_icon()

func placeholder_icon() -> Texture2D:
	return GameUi.icon(PLACEHOLDER_ICON)

## 服务端字段 → AvatarConfig；不是合法字典就当没有形象。
static func config_from(avatar: Variant) -> AvatarConfig:
	if not (avatar is Dictionary) or (avatar as Dictionary).is_empty():
		return null
	return AvatarConfig.from_json_text(JSON.stringify(avatar))

## 返回是否拿到了真图。
func show_avatar(avatar: Variant) -> bool:
	config = config_from(avatar)
	texture = placeholder_icon()
	ready_texture = null
	if config == null:
		return false
	var portraits := AvatarPortraits.shared()
	if portraits == null:
		return false
	var tex: Texture2D = await portraits.portrait(config)
	if tex == null or not is_instance_valid(self):
		return false
	# 期间可能已换成别人的形象。
	if config == null or AvatarPortraits.cache_key(config) != AvatarPortraits.cache_key(AvatarThumb.config_from(avatar)):
		return false
	texture = tex
	ready_texture = tex
	texture_ready.emit(tex)
	return true
