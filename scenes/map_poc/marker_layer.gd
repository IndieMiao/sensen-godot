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
const PIN_SIZE := Vector2(48, 48)
const PIN_FACE_SIZE := Vector2(36, 36)
## 白色留言气泡字形，直接画在珊瑚色圆面上。
## 曾经是墨色的 "!"——珊瑚底 + 近黑感叹号在地图上读起来是"警告/出错"，
## 而这些 marker 其实是别人留下的留言（"今天云不错"、"楼下新出桂花拿铁"）。
const NOTE_GLYPH := preload("res://assets/ui/icons/note.svg")
const NOTE_GLYPH_INSET := 9.0
const BUBBLE_W := 208.0
const BUBBLE_GAP := 8.0

## 每项：{east_m, north_m, author, text, pin: Button, bubble: PanelContainer}
var markers: Array[Dictionary] = []
var home_lat := 0.0
var home_lng := 0.0
var _open := -1
var _safe_margins := Vector4(16.0, 16.0, 16.0, 16.0)

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

func set_safe_margins(margins: Vector4) -> void:
	_safe_margins = margins

func _build() -> void:
	for spec in load_specs():
		var m := {
			"east_m": float(spec.get("east_m", 0.0)),
			"north_m": float(spec.get("north_m", 0.0)),
			"author": str(spec.get("author", "")),
			"text": str(spec.get("text", "")),
		}
		var pin := Button.new()
		pin.custom_minimum_size = PIN_SIZE
		pin.size = PIN_SIZE
		pin.focus_mode = Control.FOCUS_NONE
		pin.flat = true
		pin.text = ""
		pin.tooltip_text = "Open note"
		pin.visible = false
		pin.z_index = 1
		var empty_style := StyleBoxEmpty.new()
		for state in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
			pin.add_theme_stylebox_override(state, empty_style)
		var face := _make_marker_face()
		pin.add_child(face)
		add_child(pin)
		var bubble := _make_bubble(m.author, m.text)
		add_child(bubble)
		m["pin"] = pin
		m["face"] = face
		m["bubble"] = bubble
		var idx := markers.size()
		pin.button_down.connect(func(): _set_marker_face_pressed(face, true))
		pin.button_up.connect(func(): _set_marker_face_pressed(face, false))
		pin.mouse_exited.connect(func(): _set_marker_face_pressed(face, false))
		pin.visibility_changed.connect(func():
			if not pin.visible:
				_set_marker_face_pressed(face, false))
		pin.pressed.connect(func(): _toggle(idx))
		markers.append(m)

func _make_marker_face() -> Panel:
	var face := Panel.new()
	face.custom_minimum_size = PIN_FACE_SIZE
	face.size = PIN_FACE_SIZE
	face.position = (PIN_SIZE - PIN_FACE_SIZE) * 0.5
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override(&"panel", _marker_face_style(DesignTokens.MARKER))
	var mark := TextureRect.new()
	mark.texture = NOTE_GLYPH
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.offset_left = NOTE_GLYPH_INSET
	mark.offset_top = NOTE_GLYPH_INSET
	mark.offset_right = -NOTE_GLYPH_INSET
	mark.offset_bottom = -NOTE_GLYPH_INSET
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.add_child(mark)
	return face

static func _marker_face_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = DesignTokens.SURFACE
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(PIN_FACE_SIZE.x * 0.5))
	style.shadow_color = Color(DesignTokens.INK, 0.16)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 1)
	return style

static func _set_marker_face_pressed(face: Panel, pressed: bool) -> void:
	if not is_instance_valid(face):
		return
	var color := DesignTokens.MARKER_PRESSED if pressed else DesignTokens.MARKER
	face.add_theme_stylebox_override(&"panel", _marker_face_style(color))

func _make_bubble(author: String, text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"TopPanel"
	p.visible = false
	p.custom_minimum_size.x = BUBBLE_W
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 2
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
	t.custom_minimum_size.x = BUBBLE_W - DesignTokens.SPACE_4 * 2
	t.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	t.add_theme_color_override("font_color", DesignTokens.INK)
	v.add_child(t)
	return p

static func bubble_position(anchor: Vector2, bubble_size: Vector2, viewport_rect: Rect2,
		margins: Vector4) -> Vector2:
	var safe_pos := viewport_rect.position + Vector2(margins.x, margins.y)
	var safe_size := Vector2(
		maxf(viewport_rect.size.x - margins.x - margins.z, 0.0),
		maxf(viewport_rect.size.y - margins.y - margins.w, 0.0))
	var safe_rect := Rect2(safe_pos, safe_size)
	var max_x := maxf(safe_rect.position.x, safe_rect.end.x - bubble_size.x)
	var max_y := maxf(safe_rect.position.y, safe_rect.end.y - bubble_size.y)
	var x := clampf(anchor.x - bubble_size.x * 0.5, safe_rect.position.x, max_x)
	var above_y := anchor.y - PIN_SIZE.y * 0.5 - BUBBLE_GAP - bubble_size.y
	var below_y := anchor.y + PIN_SIZE.y * 0.5 + BUBBLE_GAP
	var y := above_y if above_y >= safe_rect.position.y else below_y
	return Vector2(x, clampf(y, safe_rect.position.y, max_y))

static func pin_center_rect(viewport_rect: Rect2, margins: Vector4) -> Rect2:
	var half := PIN_SIZE * 0.5
	var safe_position := viewport_rect.position + Vector2(margins.x, margins.y) + half
	var safe_size := Vector2(
		maxf(viewport_rect.size.x - margins.x - margins.z - PIN_SIZE.x, 0.0),
		maxf(viewport_rect.size.y - margins.y - margins.w - PIN_SIZE.y, 0.0))
	return Rect2(safe_position, safe_size)

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
			on = pin_center_rect(rect, _safe_margins).has_point(sp)
		pin.visible = on
		bubble.visible = on and _open == i
		if not on:
			continue
		pin.position = sp - PIN_SIZE * 0.5
		var bubble_size := Vector2(
			maxf(bubble.size.x, bubble.get_combined_minimum_size().x),
			maxf(bubble.size.y, bubble.get_combined_minimum_size().y))
		bubble.size = bubble_size
		bubble.position = bubble_position(sp, bubble_size, rect, _safe_margins)
