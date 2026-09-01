class_name MarkerLayer
extends Control
## 地图留言 marker 与气泡（demo 假数据，接口形状对齐 Unity 的 QueryNewMapMarkerReponse）。
##
## 坐标存"相对 home 的米偏移"而非绝对经纬度：写死经纬度的话，用户定位到任何非
## 上海的位置，marker 会全部落到屏幕外——与 pawn 同一个坑，见 map_poc._resolve_home()。
##
## 渲染在 Godot Control 层（方案 spec §5.4 的归属决策：气泡归 Godot，
## POI/静态标注才归地图 style 侧）。

const DATA_PATH := "res://scenes/map_poc/demo_markers.json"
const DATA_VERSION := 1
const PIN_SIZE := Vector2(28, 28)
const BUBBLE_W := 180.0

## 每项：{east_m, north_m, author, text, pin: Button, bubble: PanelContainer}
var markers: Array[Dictionary] = []
var home_lat := 0.0
var home_lng := 0.0
var _open := -1

static func load_specs(path: String = DATA_PATH) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("MarkerLayer: 数据文件缺失 %s" % path)
		return []
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or int(data.get("version", 0)) != DATA_VERSION:
		push_warning("MarkerLayer: 数据版本/格式非法 %s" % path)
		return []
	var raw = data.get("markers")
	return raw if typeof(raw) == TYPE_ARRAY else []

## 锚点确定后才建节点——建早了 home 还是 0,0，marker 会摆在几内亚湾。
func set_home(lat: float, lng: float) -> void:
	home_lat = lat
	home_lng = lng
	if markers.is_empty():
		_build()

func _build() -> void:
	for spec in load_specs():
		var m := {
			"east_m": float(spec.get("east_m", 0.0)),
			"north_m": float(spec.get("north_m", 0.0)),
			"author": str(spec.get("author", "")),
			"text": str(spec.get("text", "")),
		}
		var pin := Button.new()
		pin.theme_type_variation = &"RoundButton"
		pin.custom_minimum_size = PIN_SIZE
		pin.size = PIN_SIZE
		pin.focus_mode = Control.FOCUS_NONE
		pin.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		pin.text = "!"
		pin.visible = false
		add_child(pin)
		var bubble := _make_bubble(m.author, m.text)
		add_child(bubble)
		m["pin"] = pin
		m["bubble"] = bubble
		var idx := markers.size()
		pin.pressed.connect(func(): _toggle(idx))
		markers.append(m)

func _make_bubble(author: String, text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"ChipPanel"
	p.visible = false
	p.custom_minimum_size.x = BUBBLE_W
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	p.add_child(v)
	var a := Label.new()
	a.text = author
	a.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	a.add_theme_color_override("font_color", DesignTokens.INK_SUB)
	v.add_child(a)
	var t := Label.new()
	t.text = text
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = BUBBLE_W
	t.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	t.add_theme_color_override("font_color", DesignTokens.INK)
	v.add_child(t)
	return p

## 同时只开一个气泡；再点同一个收起。
func _toggle(index: int) -> void:
	if _open >= 0 and _open < markers.size():
		(markers[_open].bubble as Control).visible = false
	_open = -1 if _open == index else index
	if _open >= 0:
		(markers[_open].bubble as Control).visible = true

## marker 的世界坐标（米，相对给定锚点）。世界系 x=东、-z=北，与 MapGeoMath 一致。
func world_position(index: int, anchor_lat: float, anchor_lng: float) -> Vector3:
	var m := markers[index]
	var base := MapGeoMath.geo_to_world(home_lat, home_lng, anchor_lat, anchor_lng)
	return base + Vector3(m.east_m, 0.0, -m.north_m)

## 跟随相机把 marker 投到屏幕。与 pawn 同一套剔除口径（距地图中心 > cull_r 隐藏），
## 外加相机背后与出屏两道过滤——unproject_position 对背后的点会给出镜像坐标。
func sync(cam: Camera3D, anchor_lat: float, anchor_lng: float, cull_r: float,
		center_world: Vector3) -> void:
	var rect := get_viewport_rect()
	for i in markers.size():
		var m := markers[i]
		var pin := m.pin as Control
		var bubble := m.bubble as Control
		var w := world_position(i, anchor_lat, anchor_lng)
		var on := w.distance_to(center_world) <= cull_r and not cam.is_position_behind(w)
		var sp := Vector2.ZERO
		if on:
			sp = cam.unproject_position(w)
			on = rect.has_point(sp)
		pin.visible = on
		bubble.visible = on and _open == i
		if not on:
			continue
		pin.position = sp - PIN_SIZE * 0.5
		bubble.position = sp - Vector2(bubble.size.x * 0.5, bubble.size.y + PIN_SIZE.y * 0.6)
