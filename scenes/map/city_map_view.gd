class_name CityMapView
extends Control
## Geographic browsing UI. All marker taps are resolved after the map's tap-slop guard.
signal focus_requested(entry: Dictionary)
signal resident_requested(entry: Dictionary)
signal landmark_requested(entry: Dictionary)
signal pond_requested(entry: Dictionary)
## A marker was selected (its info card opens); hosts can start loading what Enter will need.
signal entry_selected(entry: Dictionary)
## A host-defined place pin (kind "place": own art_path, category, action label) was entered.
signal place_requested(entry: Dictionary)

var pond_locations: Array = []
## Host-defined place pins: {id, kind: "place", name, category, lat, lng, art_path, action,
## action_icon, filter, tag} — e.g. the P0 outposts. They lay out like pond pins; a non-empty tag
## follows the name on the pin ("Lotus Tea House · 5 online").
var extra_places: Array = []
## Pond directory by fixed 0.5° cells around the map centre (SystemPonds.CELL_DEG), not by active
## city: roaming San Francisco from a Shanghai farm still shows the ponds there.
var _pond_cells: Dictionary = {}      # "y:x" -> {"at": msec, "entries": Array}
var _pond_view := ""                  # the 3×3 block currently shown
var _pond_pending := false
var _pond_retry_at := 0
var _pond_error := false
## P0: pins come from the bundled catalog only (preload_ponds), no directory requests.
var bundled_ponds := false
const POND_CELL_TTL_MS := 300000
const POND_RETRY_MS := 30000
## Below this zoom a 3×3 block is far smaller than the view; ponds are city-scale content anyway.
const POND_MIN_ZOOM := 9.0
## 玩家详情卡上的“拜访农场”按钮：跳转到该玩家的空间（访客实例）。
signal player_visit_requested(farm_id: String)
## 玩家详情卡被关闭（点 X、切筛选、开列表等）：宿主借此清掉 pin 选中与 3D 角色。
signal player_deselected
signal action_requested(action: String)
## 城市面板选中或低 zoom 点城市气泡：宿主飞到该城总览。
signal city_requested(region_id: String)
signal sheet_opened
const INK := Color("232b30")
const MUTED := Color("69716e")
const LIME := Color("cafa91")
const CONTENT_TOP := 108.0
const POI_CACHE_LIMIT := 400
## Anti-flicker: packing tests use a dead zone (incumbents keep their slot until
## overlap exceeds the margin; newcomers need clearance plus the margin), and a
## marker that lost its slot cannot re-enter within the cooldown.
const PACK_MARGIN := 8.0
const REAPPEAR_COOLDOWN_MS := 400
## Display diversity: once this many dining markers are placed, remaining dining
## candidates wait until every non-dining candidate had its chance at the space.
const DINING_QUOTA := 4
const DINING_ARTS := ["restaurant", "chinese_restaurant", "cafe", "bakery"]
## Design: the shadow is the artwork's own silhouette — the same transparent
## layer tinted translucent ink, offset down-right beneath the art.
const SHADOW_TINT := Color(0.07, 0.1, 0.07, 0.24)
const SHADOW_OFFSET := Vector2(0.035, 0.055) # 相对贴图高度的右/下偏移
## 选中项果冻放大倍数；占位与渲染层级同步提升，压在其他标记之上。
const FOCUS_SCALE := 1.6
var host: Node
var filter := "all"
var selected: Dictionary = {}
var entries: Array = []
var live_pois: Array = []
var markers: Dictionary = {}
var displayed: Array = []
var subtitle: Label
var status: Label
var info: PanelContainer
var info_title: Label
var info_category: Label
var info_address: Label
var info_art: TextureRect
var info_action: Button
var dock: PanelContainer
var list_panel: PanelContainer
var list_rows: VBoxContainer
var filters: Dictionary = {}
var recenter: Button
var _last_state := ""
var _timer := 0.0
var _request := 0
var _pending := false
var _request_age := 0.0
var _last_pose := ""
var _received_pose := ""
var _provider_error := ""
var _attached_bridge: MapBridge
var _nav_icons: Dictionary = {}
var _nav_labels: Dictionary = {}
## POI/landmark artwork lives in the 3D world (billboards), so avatars and
## buildings occlude each other by depth instead of UI always winning.
var _art_root: Node3D
## Ids displayed last frame: ties in screen-space packing keep the incumbent,
## so pan/zoom never flickers between two equally-ranked neighbours.
var _shown_last: Dictionary = {}
## id -> ticks_msec before which a culled marker may not reappear.
var _hidden_until: Dictionary = {}
## 左上角标题：随中心所在位置变化（已开通城市名 / 瓦片地名）。
var city_button: Button
var _underline: ColorRect
var _header_key := ""
## 标题地名来源（反向地理编码）；测试可直接写 places 覆盖。
var geocoder: PlaceGeocoder
var places: Dictionary = {}
## 城市气泡：region_id -> {node, name, count}；只在国家/省级视野显示。
var bubbles: Dictionary = {}
var city_panel: PanelContainer
var city_rows: VBoxContainer
static func surface(color := Color(1, 1, 1, 0.97), radius := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	s.shadow_color = Color(0.2, 0.23, 0.2, 0.09)
	s.shadow_size = 2 if color.a > 0.1 else 0
	s.shadow_offset = Vector2(0, 2)
	return s

static func marker_style() -> StyleBoxFlat:
	var style := surface(Color(1, 1, 1, 0.93), 8)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	style.shadow_size = 0
	return style

static func filter_style(active: bool) -> StyleBoxFlat:
	var style := surface(LIME if active else Color.TRANSPARENT, 15)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	style.expand_margin_top = -7
	style.expand_margin_bottom = -7
	style.shadow_size = 0
	return style

static func compact_round_button(button: Button) -> void:
	# Draw a 32px disc inside an unchanged 44px touch target.
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_constant_override("icon_max_width", 16)
	for state in ["normal", "hover", "focus", "disabled", "pressed", "hover_pressed"]:
		button.add_theme_color_override("icon_" + state + "_color", MUTED if state == "disabled" else INK)
		var style := surface(LIME if state in ["pressed", "hover_pressed"] else Color.WHITE, 16)
		style.set_content_margin_all(0)
		style.set_expand_margin_all(-6)
		style.shadow_size = 1
		button.add_theme_stylebox_override(state, style)

static func flat_button(symbol: String, text: String, control_name: String) -> Button:
	var b := GameUi.button(symbol, text, text)
	b.name = control_name
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("icon_pressed_color", INK)
	b.add_theme_color_override("icon_hover_color", INK)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("icon_normal_color", INK)
	b.add_theme_constant_override("icon_max_width", 17)
	for s in ["normal", "hover", "focus", "disabled"]: b.add_theme_stylebox_override(s, surface())
	b.add_theme_stylebox_override("pressed", surface(LIME))
	b.add_theme_stylebox_override("hover_pressed", surface(LIME))
	return b

func _ready() -> void:
	name = "CityMap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var city_name := str(host.region.get("name", "Los Angeles")) if host else "Los Angeles"
	var city := flat_button("chevron-down", L10n.text(city_name), "MapCity")
	city.alignment = HORIZONTAL_ALIGNMENT_LEFT
	city.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	city.add_theme_font_size_override("font_size", 22)
	city.add_theme_constant_override("icon_max_width", 12)
	# 标题是纯文字入口：任何状态都不画底板（按下时曾露出白色 focus 底）。
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]: city.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	city.pressed.connect(func(): action_requested.emit("city"))
	city.position = Vector2(5, 0)
	city.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(city)
	city_button = city
	city.size = Vector2(city.get_combined_minimum_size().x, 44)
	subtitle = GameUi.label(city_name, 10, MUTED)
	subtitle.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	subtitle.position = Vector2(6, 34)
	add_child(subtitle)
	var underline := ColorRect.new()
	underline.color = LIME
	underline.position = Vector2(4, 31)
	underline.size = Vector2(maxf(40.0, city.size.x - 22.0), 4)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_underline = underline
	add_child(underline)
	move_child(underline, 0)
	var places := flat_button("list-checks", "", "MapLandmarkList")
	compact_round_button(places)
	places.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	places.offset_left = -44
	places.offset_bottom = 44
	places.pressed.connect(_toggle_places)
	add_child(places)
	var filter_panel := PanelContainer.new()
	filter_panel.name = "MapFilters"
	var filter_surface := surface()
	filter_surface.content_margin_left = 5
	filter_surface.content_margin_right = 5
	filter_surface.content_margin_top = 0
	filter_surface.content_margin_bottom = 0
	filter_surface.expand_margin_top = -7
	filter_surface.expand_margin_bottom = -7
	filter_panel.add_theme_stylebox_override("panel", filter_surface)
	add_child(filter_panel)
	filter_panel.position = Vector2(0, 46)
	filter_panel.size = Vector2(260, 44)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	filter_panel.add_child(row)
	for spec in [["all", "All"], ["landmark", "Landmarks"], ["food", "Dining"], ["resident", "Residents"], ["pond", "Fishing"]]:
		var b := flat_button("", L10n.text(spec[1]), "MapFilter_" + spec[0])
		b.custom_minimum_size = Vector2(48, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): set_filter(spec[0]))
		row.add_child(b)
		filters[spec[0]] = b
	var north := flat_button("", "", "MapNorth")
	compact_round_button(north)
	north.add_theme_font_size_override("font_size", 10)
	north.tooltip_text = L10n.text("North up")
	north.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	north.offset_left = -44
	north.offset_top = 44
	north.offset_bottom = 88
	north.pressed.connect(func(): action_requested.emit("north"))
	add_child(north)
	var north_arrow := GameUi.picture(GameUi.icon("arrow-up"), 15)
	north_arrow.name = "Arrow"
	north_arrow.modulate = INK
	north_arrow.position = Vector2(14.5, 8)
	north_arrow.size = Vector2(15, 15)
	north_arrow.pivot_offset = Vector2(7.5, 7.5)
	north.add_child(north_arrow)
	var north_label := GameUi.label("N", 8, INK)
	north_label.position = Vector2(19, 23)
	north.add_child(north_label)
	status = GameUi.label("", 10, MUTED)
	status.position = Vector2(6, 94)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	var credits := GameUi.label("© Mapbox © OpenStreetMap", 9, MUTED)
	credits.name = "MapCredits"
	credits.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(credits)
	dock = PanelContainer.new()
	var dock_surface := surface(Color.WHITE, 24)
	dock_surface.content_margin_top = 2
	dock_surface.content_margin_bottom = 2
	dock.add_theme_stylebox_override("panel", dock_surface)
	add_child(dock)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 1)
	dock.add_child(nav)
	for spec in [["map", "map-pin", "Map"], ["farm", "sprout", "Farm"], ["outfit", "user-round", "Me"]]:
		var b := flat_button("", "", "MapNav_" + spec[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(48, 44)
		for state in ["normal", "hover", "focus"]: b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.pressed.connect(func(): action_requested.emit(spec[0]))
		nav.add_child(b)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 1)
		b.add_child(column)
		var icon := GameUi.picture(GameUi.icon(spec[1]), 18)
		icon.modulate = Color("609f28") if spec[0] == "map" else MUTED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(icon)
		_nav_icons[spec[0]] = icon
		var label := GameUi.label(L10n.text(spec[2]), 10, INK if spec[0] == "map" else MUTED)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(label)
		_nav_labels[spec[0]] = label
	_build_info()
	_build_list()
	_build_city_panel()
	recenter = flat_button("locate-fixed", "", "MapRecenter")
	compact_round_button(recenter)
	recenter.pressed.connect(func(): action_requested.emit("recenter"))
	add_child(recenter)
	for spec in [["plus", 1.0], ["minus", -1.0]]:
		var b := flat_button(spec[0], "", "MapZoom_" + spec[0])
		compact_round_button(b)
		b.pressed.connect(func(): host._tween_zoom(host.zoom + spec[1]))
		add_child(b)
	resized.connect(_layout)
	_layout()
	set_filter("all")
	refresh_content()

func _build_info() -> void:
	info = PanelContainer.new()
	info.name = "MapInfo"
	info.add_theme_stylebox_override("panel", surface())
	add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	info.add_child(row)
	info_art = GameUi.picture(GameUi.icon("map-pin"), 64)
	info_art.custom_minimum_size = Vector2(64, 64)
	row.add_child(info_art)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	info_title = GameUi.label("", 13, INK)
	info_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_title.custom_minimum_size.x = 100
	text.add_child(info_title)
	info_category = GameUi.label("", 10, MUTED)
	info_category.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(info_category)
	info_address = GameUi.label("", 10, MUTED)
	info_address.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(info_address)
	info_action = flat_button("message-circle", L10n.text("Visit resident"), "MapVisitResident")
	info_action.custom_minimum_size = Vector2(104, 44)
	info_action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for state in ["normal", "hover", "focus", "pressed"]:
		var action_style := surface(LIME, 14)
		action_style.expand_margin_top = -4
		action_style.expand_margin_bottom = -4
		action_style.shadow_size = 0
		info_action.add_theme_stylebox_override(state, action_style)
	info_action.pressed.connect(_on_info_action)
	text.add_child(info_action)
	var close := flat_button("x", "", "MapCloseInfo")
	compact_round_button(close)
	for state in ["normal", "hover", "focus"]: close.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(clear_selection)
	row.add_child(close)
	info.hide()
	info.minimum_size_changed.connect(_layout.call_deferred)

func _build_list() -> void:
	list_panel = PanelContainer.new()
	list_panel.name = "MapPlaces"
	list_panel.add_theme_stylebox_override("panel", surface())
	add_child(list_panel)
	var scroll := TouchScrollContainer.new()
	list_panel.add_child(scroll)
	list_rows = VBoxContainer.new()
	list_rows.add_theme_constant_override("separation", 2)
	list_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_rows)
	list_panel.hide()

func _layout() -> void:
	if dock == null: return
	var dock_width := minf(300, size.x)
	dock.position = Vector2((size.x - dock_width) * 0.5, size.y - 54)
	dock.size = Vector2(dock_width, 48)
	get_node("MapCredits").position = Vector2(0, size.y - 4)
	get_node("MapCredits").size = Vector2(size.x, 12)
	var info_height := maxf(72, info.get_combined_minimum_size().y)
	info.position = Vector2(0, dock.position.y - 8 - info_height)
	info.size = Vector2(size.x, info_height)
	info.clip_contents = true
	list_panel.position = Vector2(maxf(0, size.x - 212), 44)
	list_panel.size = Vector2(minf(212, size.x), minf(340, size.y - 180))
	recenter.position = Vector2(size.x - 44, (info.position.y if info.visible else dock.position.y) - 52)
	recenter.size = Vector2(44, 44)
	for index in 2:
		var b := get_node("MapZoom_" + ("plus" if index == 0 else "minus")) as Button
		b.position = recenter.position - Vector2(0, 48 * (2 - index))
		b.size = Vector2(44, 44)

func set_filter(value: String) -> void:
	filter = value
	_last_state = ""
	refresh_content()
	if filter == "pond": status.text = L10n.text("Ponds unavailable. Try again shortly.") if _pond_error else ""
	for key in filters:
		for state in ["normal", "hover", "focus", "pressed"]: filters[key].add_theme_stylebox_override(state, filter_style(key == filter))
	clear_selection()
	if list_panel: list_panel.hide()
	if host: host._reset_gesture()

func _toggle_places() -> void:
	var opening := not list_panel.visible
	if opening:
		sheet_opened.emit()
		clear_selection()
		city_panel.hide()
	list_panel.visible = opening
	if host: host._reset_gesture()

func dismiss_overlays() -> void:
	if list_panel: list_panel.hide()
	if city_panel: city_panel.hide()
	clear_selection()

func clear_selection() -> void:
	# 取消时快速缩回（比选中弹入快，见设计反馈 #7）。
	if not selected.is_empty():
		_animate_focus(str(selected.get("id", "")), 1.0, 0.14)
		_set_marker_front(str(selected.get("id", "")), false)
		if str(selected.get("kind", "")) == "player": player_deselected.emit()
	selected = {}
	if info: info.hide()
	if is_instance_valid(recenter): _layout()

func refresh_content() -> void:
	if host == null: return
	var state: Dictionary = Net.session.state if Net and Net.session else {}
	var region_id := str(host.region.get("id", ""))
	var roaming := _roaming_landmarks()
	var key := region_id + JSON.stringify(state.get("journey", {})) + JSON.stringify(state.get("residents", {})) + str(state.get("clock", {}).get("chapter_index", -1)) + str(Net.session.version if Net and Net.session else -1) + ",".join(roaming.map(func(g): return str(g.id)))
	if key == _last_state: return
	_last_state = key
	var own := CityMapData.landmarks(region_id)
	var own_ids := own.map(func(p): return str(p.get("id", "")))
	entries = own + roaming.filter(func(g): return not own_ids.has(str(g.id))) + CityMapData.residents(region_id, state)
	entries += pond_locations + extra_places
	for child in list_rows.get_children():
		list_rows.remove_child(child)
		child.queue_free()
	for entry in entries:
		if not _entry_visible(entry): continue
		var b := flat_button("map-pin" if entry.kind == "landmark" else "user-round", _name(entry), "MapPlace_" + str(entry.id))
		if entry.kind in ["landmark", "pond", "place"]:
			b.icon = CityMapData.art_texture(entry)
			b.add_theme_constant_override("icon_max_width", 28)
			for state_name in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
				b.add_theme_color_override("icon_" + state_name + "_color", Color.WHITE)
		b.add_theme_font_size_override("font_size", 11)
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.pressed.connect(func(): list_panel.hide(); select(entry); focus_requested.emit(entry))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		for sty in ["normal", "hover", "focus"]: b.add_theme_stylebox_override(sty, StyleBoxEmpty.new())
		list_rows.add_child(b)
	if not selected.is_empty() and selected.kind == "resident" and not entries.any(func(p): return p.id == selected.id): clear_selection()

## 漫游到别的城市也要看到地标：不论中心是否落在已开通城市，地图中心 reach_km 内的
## 设计地标都上图、入列表。以前只按激活 region 取——在旧金山、纽约漫游时 region 还是
## 自己农场所在的城市，整座城一个地标都没有（2026-09-29 Joey 真机反馈）。
func _roaming_landmarks() -> Array:
	var lat = host.get("center_lat")
	var lng = host.get("center_lng")
	if not (lat is float) or not (lng is float): return []
	var out := CityMapData.landmarks_near(lat, lng)
	for g in out: g.kind = "landmark"
	return out

## 详情卡的城市名：设计地标带自己的城市；其他条目按坐标落在哪座已开通城市取名；
## 都不在（漫游到未开通城市）就用标题栏查到的瓦片地名；连地名都没有就只显示类别。
## 以前一律取激活 region——在纽约点博物馆会写成“博物馆 · 上海”。
func _place_city(entry: Dictionary) -> String:
	if not str(entry.get("city", "")).is_empty(): return L10n.text(str(entry.city))
	var region_id := str(host.region.get("id", ""))
	var region_name := L10n.text(str(host.region.get("name", "")))
	if not (entry.has("lat") and entry.has("lng")) or not host.has_method("city_id_at"): return region_name
	var id: String = host.city_id_at(float(entry.lat), float(entry.lng))
	if id == region_id: return region_name
	for r in host.city_regions():
		if str(r.get("id", "")) == id: return L10n.text(str(r.get("name", "")))
	return str(places.get("settlement", ""))

func _category_text(category: String, city: String) -> String:
	return L10n.text(category) + (" · " + city if not city.is_empty() else "")

func _name(entry: Dictionary) -> String:
	if entry.get("kind") == "pond": return L10n.text(str(entry.name))
	return str(entry.get("zh", entry.name)) if TranslationServer.get_locale().begins_with("zh") else str(entry.name)

func _label_text(entry: Dictionary) -> String:
	if entry.kind == "resident" and str(entry.get("status", "")) == "Ready to deliver":
		return _name(entry) + " · " + L10n.text("Ready to deliver")
	if not str(entry.get("tag", "")).is_empty(): return _name(entry) + " · " + str(entry.tag)
	return _name(entry)

## 选中项名牌宽度：按 9 号字实测文本宽 + 样式内边距；超过上限就折行而不是继续变宽。
const LABEL_MAX_W := 120.0
const LABEL_PAD := 18.0
## Measured the way the name tag renders: GameUi.label(…, 10) inside marker_style()'s 4 + 4 px margins.
const LABEL_FONT := 10
const LABEL_MARGIN := 8.0
func _label_width(entry: Dictionary) -> float:
	var font := get_theme_font("font", "Label")
	if font == null: return 48.0
	return minf(LABEL_MAX_W, font.get_string_size(_label_text(entry), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT).x + LABEL_PAD)

## 名牌在给定宽度下按词折行需要的高度（最多 3 行）。
func _label_height(entry: Dictionary, width: float) -> float:
	var font := get_theme_font("font", "Label")
	if font == null: return 16.0
	var h := font.get_multiline_string_size(_label_text(entry), HORIZONTAL_ALIGNMENT_CENTER, width - LABEL_MARGIN, LABEL_FONT, 3).y
	return maxf(16.0, h + 4.0)

func select(entry: Dictionary) -> void:
	sheet_opened.emit()
	list_panel.hide()
	# 果冻式弹起标记选中项；换选时旧项快速缩回。
	if not selected.is_empty() and str(selected.get("id", "")) != str(entry.get("id", "")):
		_animate_focus(str(selected.get("id", "")), 1.0, 0.14)
		_set_marker_front(str(selected.get("id", "")), false)
	selected = entry
	entry_selected.emit(entry)
	_animate_focus(str(entry.get("id", "")), FOCUS_SCALE, 0.28)
	_set_marker_front(str(entry.get("id", "")), true)
	info_title.text = _name(entry)
	info_category.text = _category_text(str(entry.get("category", "Place")), _place_city(entry))
	info_address.text = str(entry.get("address", ""))
	info_address.visible = not info_address.text.is_empty()
	var landmark_scene := LandmarkScenes.path_for(str(host.region.get("id", "")), entry)
	info_action.visible = entry.kind in ["resident", "pond", "place"] or not landmark_scene.is_empty()
	if entry.kind == "resident":
		info_category.text = L10n.text("Resident") + " · " + L10n.text(str(entry.get("status", "Talk")))
		info_action.text = L10n.text("Visit resident")
		info_action.icon = GameUi.icon("message-circle")
	elif entry.kind == "pond":
		info_category.text = L10n.text(str(SystemPonds.TITLES.get(entry.template_id, "Fishing pond")))
		info_action.text = L10n.text("Enter pond")
		info_action.icon = GameUi.icon("fish")
	elif entry.kind == "place":
		info_category.text = L10n.text(str(entry.get("category", "Place")))
		info_action.text = L10n.text(str(entry.get("action", "Enter")))
		info_action.icon = GameUi.icon(str(entry.get("action_icon", "footprints")))
	elif not landmark_scene.is_empty():
		info_action.text = L10n.text("Enter scene")
		info_action.icon = GameUi.icon("footprints")
	info_art.texture = CityMapData.art_texture(entry)
	info_art.modulate = Color.WHITE
	if entry.kind == "resident" and markers.has(entry.id): info_art.texture = markers[entry.id].portrait.portrait.texture
	info.show()
	_layout()
	_settle_info.call_deferred()
	if host: host._reset_gesture()

## 选中其他玩家：底部详情卡与 POI 同款，行动按钮“拜访农场”跳到对方的空间。
## 不发 sheet_opened——那个信号会让宿主清空玩家选中，与本卡互斥。
func select_player(entry: Dictionary, portrait: Texture2D) -> void:
	list_panel.hide()
	if not selected.is_empty() and str(selected.get("id", "")) != str(entry.get("id", "")):
		_animate_focus(str(selected.get("id", "")), 1.0, 0.14)
		_set_marker_front(str(selected.get("id", "")), false)
	selected = entry
	info_title.text = str(entry.get("name", ""))
	info_category.text = _category_text("Farm", _place_city(entry))
	info_address.text = ""
	info_address.visible = false
	info_action.visible = true
	info_action.text = L10n.text("Visit Farm")
	info_action.icon = GameUi.icon("footprints")
	info_art.texture = portrait if portrait != null else GameUi.icon("user-round")
	info_art.modulate = Color.WHITE
	info.show()
	_layout()
	_settle_info.call_deferred()
	if host: host._reset_gesture()

func _on_info_action() -> void:
	match str(selected.get("kind", "")):
		"player": player_visit_requested.emit(str(selected.get("farm_id", "")))
		"resident": resident_requested.emit(selected)
		"pond": pond_requested.emit(selected)
		"place": place_requested.emit(selected)
		"landmark":
			if not LandmarkScenes.path_for(str(host.region.get("id", "")), selected).is_empty():
				landmark_requested.emit(selected)

func _pond_view_cells() -> Array:
	var lat = host.get("center_lat")
	var lng = host.get("center_lng")
	var zoom = host.get("zoom")
	if not (lat is float and lng is float) or (zoom is float and zoom < POND_MIN_ZOOM): return []
	var centre := SystemPonds.cell_of(lat, lng)
	var keys := []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]: keys.append(SystemPonds.cell_key(centre + Vector2i(dx, dy)))
	return keys

func _show_pond_cells(keys: Array) -> void:
	var shown := []
	var seen := {}
	for key in keys:
		for entry in (_pond_cells.get(key, {}) as Dictionary).get("entries", []):
			if seen.has(entry.id): continue
			seen[entry.id] = true
			shown.append(entry)
	var ids := ",".join(shown.map(func(e): return str(e.id)))
	if ids == ",".join(pond_locations.map(func(e): return str(e.id))): return
	pond_locations = shown
	_last_state = ""
	if selected.get("kind") == "pond" and not seen.has(str(selected.get("id", ""))): clear_selection()
	refresh_content()

func _refresh_pond_directory() -> void:
	var keys := _pond_view_cells()
	var view := ",".join(keys)
	if view != _pond_view:
		_pond_view = view
		_show_pond_cells(keys)
	if bundled_ponds or keys.is_empty() or _pond_pending or Net.session == null or not Net.session.logged_in(): return
	var now := Time.get_ticks_msec()
	var missing := keys.filter(func(k): return not _pond_cells.has(k) or now - int(_pond_cells[k].at) > POND_CELL_TTL_MS)
	if missing.is_empty() or now < _pond_retry_at: return
	_pond_pending = true
	var response := await Net.session.client.request("GET", "/ponds/cells?cells=" + ",".join(missing))
	var cells := {}
	if response.status == 404:
		# Server predates the cell directory: fall back to the active city's bundled ponds so an
		# early client never shows fewer ponds than before. Filed under the cells they fall in.
		var region := str(host.region.get("id", ""))
		var legacy := await Net.session.client.request("GET", "/ponds?region_id=" + region.uri_encode())
		if legacy.is_success() and legacy.json is Dictionary and legacy.json.get("catalog_revision") == SystemPonds.revision() and legacy.json.get("available", false):
			for key in missing: cells[key] = []
			for entry in SystemPonds.validated_region(legacy.json, region):
				var key := SystemPonds.cell_key(SystemPonds.cell_of(float(entry.lat), float(entry.lng)))
				if cells.has(key): cells[key].append(entry)
	else:
		cells = SystemPonds.validated_cells(response.json if response.is_success() and response.json is Dictionary else {}, missing)
	_pond_pending = false
	if not is_inside_tree(): return
	_pond_error = cells.is_empty()
	if _pond_error:
		_pond_retry_at = Time.get_ticks_msec() + POND_RETRY_MS
	else:
		for key in cells: _pond_cells[key] = {"at": Time.get_ticks_msec(), "entries": cells[key]}
		# The view may have moved while the request was in flight; show whatever is current.
		_show_pond_cells(_pond_view_cells())
	if filter == "pond": status.text = L10n.text("Ponds unavailable. Try again shortly.") if _pond_error else ""

## File bundled catalog entries under their directory cells and stop asking the server (P0 map).
func preload_ponds(locations: Array) -> void:
	bundled_ponds = true
	for entry in locations:
		if not entry.get("enabled", true): continue
		var key := SystemPonds.cell_key(SystemPonds.cell_of(float(entry.lat), float(entry.lng)))
		if not _pond_cells.has(key): _pond_cells[key] = {"at": 0, "entries": []}
		(_pond_cells[key].entries as Array).append(entry.duplicate(true))
	_pond_view = ""
	_refresh_pond_directory()

func set_places(places: Array) -> void:
	extra_places = places.duplicate(true)
	_last_state = ""
	refresh_content()

func attach_bridge(bridge: MapBridge) -> void:
	if bridge == _attached_bridge: return
	if _attached_bridge and _attached_bridge.pois_received.is_connected(_on_pois): _attached_bridge.pois_received.disconnect(_on_pois)
	_attached_bridge = bridge
	if bridge:
		bridge.set_city_style(true)
		bridge.pois_received.connect(_on_pois)
	_received_pose = ""

func tick(dt: float) -> void:
	if host == null: return
	_refresh_pond_directory()
	attach_bridge(host.map)
	# 地图桥在城市层之后才创建；桌面/测试没有桥（也就没有 token），标题回落 Explore。
	if geocoder == null and host.map:
		var token: String = host._load_token()
		if not token.is_empty():
			geocoder = PlaceGeocoder.new()
			geocoder.token = token
			add_child(geocoder)
	get_node("MapNorth").tooltip_text = L10n.text("North up")
	get_node("MapNorth/Arrow").rotation = deg_to_rad(-host.bearing)
	_timer += dt
	_request_age += dt
	if _timer >= 0.7:
		_timer = 0
		refresh_content()
		var pose := "%.4f,%.4f,%.2f,%.1f,%.1f,%s,%s" % [host.center_lat, host.center_lng, host.zoom,
			host.bearing, host.pitch, get_viewport().get_visible_rect().size, TranslationServer.get_locale()]
		if _pending and _request_age > 8: _pending = false; _received_pose = ""
		if not _pending and _attached_bridge and host._map_is_ready and host.city_detail_visible() and host._touch_count == 0 and host._fling_vel.length() <= host.FLING_MIN_SPEED and (pose != _received_pose or _request_age > 15):
			_request += 1
			_pending = true
			_request_age = 0
			_last_pose = pose
			_attached_bridge.request_pois(_request)
		# 标题地名只在手指离开、惯性停下后查（与 POI 同一节奏）。
		if geocoder and host._touch_count == 0 and host._fling_vel.length() <= host.FLING_MIN_SPEED:
			geocoder.lookup(host.center_lat, host.center_lng, host.zoom, TranslationServer.get_locale())
	if geocoder: places = geocoder.places
	_update_markers()
	_update_bubbles()
	_update_header()

func _on_pois(id: int, payload: String) -> void:
	if id != _request: return
	_pending = false
	var data = JSON.parse_string(payload)
	if not data is Dictionary: return
	_received_pose = _last_pose
	if OS.is_debug_build() and data.has("error"): print("CITY_POI ", data.error)
	var incoming := CityMapData.normalize(data.get("features", [])).filter(func(p):
		return not entries.any(func(e): return e.kind == "landmark" and (str(p.name).to_lower() == str(e.name).to_lower() or str(p.name) == str(e.get("zh", "")))))
	_merge_pois(incoming)
	_provider_error = str(data.get("error", ""))
	if filter != "pond": status.text = L10n.text("Places unavailable. Move the map to retry.") if not _provider_error.is_empty() else ""
	# Provider geometry replaces authored geometry only for that provider object.
	# Authored landmark IDs and NPC anchors never depend on changing search results.

func _merge_pois(incoming: Array) -> void:
	# Loaded tiles are partial observations, not a new authoritative list. Retain
	# known coordinates through panning, empty/error responses and tile changes.
	var known := {}
	for entry in live_pois: known[str(entry.id)] = entry
	for entry in incoming:
		var id := str(entry.id)
		if known.has(id):
			entry.lat = known[id].lat
			entry.lng = known[id].lng
			# Rank keeps its first-seen value: filterrank drifts between tile
			# zoom levels and would otherwise toggle displayed markers mid-pan.
			if known[id].has("rank"): entry.rank = known[id].rank
			known.erase(id)
		known[id] = entry
	# Bounded in-memory cache; evict oldest offscreen entries only.
	for id in known.keys():
		if known.size() <= POI_CACHE_LIMIT: break
		if selected.get("id") == id or (markers.has(id) and markers[id].node.visible): continue
		known.erase(id)
	live_pois = known.values()

func _entry_visible(entry: Dictionary) -> bool:
	if filter == "pond": return entry.kind == "pond" or str(entry.get("filter", "")) == "pond"
	if filter == "landmark": return entry.kind == "landmark"
	if filter == "resident": return entry.kind == "resident"
	if filter == "food": return entry.kind == "poi" and CityMapData.art_key(entry) in ["restaurant", "chinese_restaurant", "cafe", "bakery"]
	return true

func _art_parent() -> Node3D:
	if _art_root == null or not is_instance_valid(_art_root):
		_art_root = Node3D.new()
		_art_root.name = "CityMarkerArt"
		host.add_child(_art_root)
	return _art_root

func _exit_tree() -> void:
	if is_instance_valid(_art_root): _art_root.queue_free()

func _make_marker(entry: Dictionary) -> Dictionary:
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.name = "CityMarker_" + str(entry.id).validate_node_name()
	add_child(node)
	move_child(node, 0)
	var result := {"node": node, "entry": entry, "rect": Rect2(), "on": false, "pop": 0.0, "focus": 1.0}
	if entry.kind == "resident":
		var portrait := MapPortrait.new()
		portrait.npc = true
		portrait.config = ResidentCast.outfit(str(entry.id))
		node.add_child(portrait)
		result.portrait = portrait
	else:
		var texture := CityMapData.art_texture(entry)
		var sprite := Sprite3D.new()
		sprite.name = "CityArt_" + str(entry.id).validate_node_name()
		sprite.texture = texture
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# Base world height 1m at scale 1; bottom overhangs the anchor by 6%,
		# matching the previous 2D layout (art top = anchor - 0.94 * side).
		sprite.pixel_size = 1.0 / maxf(1.0, texture.get_height())
		sprite.offset = Vector2(0, texture.get_height() * 0.44)
		_art_parent().add_child(sprite)
		result.sprite = sprite
		# 阴影 = 素材自身的剪影：同一张贴图染成半透明墨色，右下偏移垫底，
		# 形状永远与素材吻合、边缘沿用贴图自带的柔边。
		var shadow := Sprite3D.new()
		shadow.name = "CityShadow_" + str(entry.id).validate_node_name()
		shadow.texture = texture
		shadow.modulate = SHADOW_TINT
		shadow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		shadow.pixel_size = sprite.pixel_size
		shadow.offset = sprite.offset
		shadow.render_priority = -1 # 永远垫在建筑贴图之下
		_art_parent().add_child(shadow)
		result.shadow = shadow
	var label := GameUi.label(_name(entry), 10, INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_stylebox_override("normal", marker_style())
	node.add_child(label)
	result.label = label
	return result

func _update_markers() -> void:
	displayed.clear()
	# Cull only outside the screen plus the artwork's extent. UI panels cover
	# geography; they never move or hide its anchors to make room for themselves.
	var area := Rect2(-global_position, get_viewport_rect().size).grow(120)
	var all := entries.filter(func(e):return e.kind in ["landmark", "resident", "pond", "place"]) + live_pois
	var keep := {}
	var candidates: Array = []
	# 国家/省级视野只剩城市气泡与自己的头像：细节标记全部让出（带消失动画）。
	var detail: bool = host.city_detail_visible()
	for entry in all:
		var id := str(entry.id)
		keep[id] = true
		if not detail or not _entry_visible(entry): continue
		var art_key := CityMapData.art_key(entry)
		if entry.kind == "poi":
			# 只有高频 maki 才有图标；其余（含通用 marker）不上图，只留在搜索/列表。
			if CityMapData.icon_key(entry).is_empty(): continue
			var rank := float(entry.get("rank", 5))
			if art_key in DINING_ARTS:
				# 餐饮供给过剩：z13 以下不上图，中档 zoom 收紧预算。
				if host.zoom < 13.0: continue
				var rank_limit := 2 if host.zoom < 15 else 3 if host.zoom < 16 else 5
				if rank > rank_limit: continue
			elif host.zoom < 13.0 and rank > 3.0:
				# 非餐饮是稀缺内容：低 zoom 放行高价值条目填补全景，
				# 中高 zoom 不设 rank 门槛——密度全部交给屏幕打包。
				continue
		var world := MapGeoMath.geo_to_world(float(entry.lat), float(entry.lng), host.anchor_lat, host.anchor_lng)
		var projected = host.geo_to_screen(float(entry.lat), float(entry.lng))
		if projected == null: continue
		var point: Vector2 = (projected as Vector2) - global_position
		if not area.has_point(point): continue
		var width := 82.0 if entry.kind == "landmark" else 78.0 if entry.kind == "resident" else 48.0
		var is_sel: bool = selected.get("id", null) == entry.get("id")
		# 选中项名牌放宽到完整名称宽度（不再省略号截断）；占位一起变宽让邻居让位。
		if is_sel: width = maxf(width, _label_width(entry))
		# 视野最大（低 zoom）时 POI 也要有存在感：下限 42px（≈原 32 的 1.3 倍）。
		var art_side: float = 88 if entry.kind == "landmark" else lerpf(42, 64, clampf((host.zoom - 13) / 3, 0, 1))
		var top := 40.0 if entry.kind == "resident" else 54.0 if art_key in ["hollywood_sign", "griffith_observatory", "santa_monica_pier"] else 80.0 if entry.kind == "landmark" else 56.0
		if entry.kind == "poi": top = maxf(36, art_side * 0.94)
		var label_h := _label_height(entry, width) if is_sel else 16.0
		var art_w := 36.0 if entry.kind == "resident" else art_side
		var art_h := top
		var side := maxf(width, art_side)
		var below := 3.0 + label_h + 1.0
		# 选中项的占位随果冻放大同步变大，邻居的贴图和名牌为它让位。
		var k := FOCUS_SCALE if is_sel else 1.0
		side *= k
		top *= k
		below *= k
		var bounds := Rect2(point - Vector2(side * 0.5, top), Vector2(side, top + below))
		candidates.append({"entry": entry, "id": id, "world": world, "point": point,
			"bounds": bounds, "width": width, "art_side": art_side, "art": art_key,
			"label_h": label_h, "art_w": art_w, "art_h": art_h, "k": k})
	# Screen-space packing: anchors never move; a marker either shows in place
	# or yields entirely. Order: selected, landmarks, residents, then POIs by
	# incumbency (anti-flicker), source rank and id — fully deterministic.
	candidates.sort_custom(func(a, b): return _pack_key(a) < _pack_key(b))
	var blockers := _player_blockers()
	var now := Time.get_ticks_msec()
	var occupied: Array = []
	# Dining quota: deferred dining candidates fill whatever space remains after
	# every non-dining candidate was offered its spot (skipped under the food filter).
	var deferred: Array = []
	var dining := 0
	for c in candidates:
		if filter != "food" and c.entry.kind == "poi" and dining >= DINING_QUOTA and str(c.art) in DINING_ARTS:
			deferred.append(c)
			continue
		if _place_candidate(c, occupied, blockers, now) and c.entry.kind == "poi" and str(c.art) in DINING_ARTS:
			dining += 1
	for c in deferred:
		_place_candidate(c, occupied, blockers, now)
	var shown := displayed.map(func(m): return str(m.entry.id))
	_shown_last = {}
	for id in shown: _shown_last[id] = true
	for id in markers.keys():
		_set_marker_shown(markers[id], shown.has(id))
		if not keep.has(id): _free_marker(id)
	if _hidden_until.size() > 256:
		for id in _hidden_until.keys():
			if now >= int(_hidden_until[id]): _hidden_until.erase(id)
	if _provider_error.is_empty():
		status.text = L10n.text("No dining places in view. Move or zoom the map.") if filter == "food" and displayed.is_empty() else ""
	if selected.get("kind") == "resident" and markers.has(selected.id):
		var portrait: MapPortrait = markers[selected.id].portrait
		if not portrait._shown_key.is_empty() and portrait._shown_key == portrait._desired_key:
			info_art.texture = portrait.portrait.texture
	elif selected.get("kind") == "player":
		# 玩家头像是异步装配的：卡片打开时可能还没画好，好了就补上。
		var fm = host.get("farm_markers")
		if fm and fm.has_method("portrait_texture"):
			var tex: Texture2D = fm.portrait_texture(str(selected.get("farm_id", "")))
			if tex != null: info_art.texture = tex
	# Keep controls on top even when dynamically creating markers.

## One placement attempt. Anchors never move: on success the marker is laid out
## in place, on failure it stays hidden this frame. Dead-zone margins plus the
## reappear cooldown keep boundary oscillation from flickering markers.
func _place_candidate(c: Dictionary, occupied: Array, blockers: Array, now: int) -> bool:
	var entry: Dictionary = c.entry
	var id: String = c.id
	var is_selected: bool = selected.get("id", null) == entry.get("id")
	var incumbent: bool = _shown_last.has(id)
	var label_fits := true
	if not is_selected:
		if not incumbent and now < int(_hidden_until.get(id, 0)): return false
		var probe: Rect2 = c.bounds.grow(-PACK_MARGIN if incumbent else PACK_MARGIN)
		# 地标相互之间也做遮挡剔除，但不给玩家 pin 让位；其余标记两者都让。
		var blocked: bool = _hits(occupied, probe) or (entry.kind != "landmark" and _hits(blockers, probe))
		if blocked:
			if incumbent: _hidden_until[id] = now + REAPPEAR_COOLDOWN_MS
			return false
	if entry.kind == "landmark":
		label_fits = is_selected or not _hits(occupied, Rect2(c.point - Vector2(c.width * 0.5, -3), Vector2(c.width, 20)))
	occupied.append(c.bounds)
	if not markers.has(id): markers[id] = _make_marker(entry)
	var marker: Dictionary = markers[id]
	marker.entry = entry
	marker.node.position = c.point
	marker.rect = c.bounds
	marker.anchor = c.point
	if entry.kind == "resident":
		marker.portrait.position = Vector2(-18, -38)
	else:
		_place_art(marker, c)
	marker.label.text = _label_text(entry)
	# 名牌永远跟随图标居中（出屏也不挪）；选中项长名按词折行，不再省略号截断。
	marker.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if is_selected else TextServer.AUTOWRAP_OFF
	marker.label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if is_selected else TextServer.OVERRUN_TRIM_ELLIPSIS
	marker.label.position = Vector2(-c.width * 0.5, 3)
	marker.label.size = Vector2(c.width, c.label_h)
	marker.label.add_theme_font_size_override("font_size", 9)
	marker.label.visible = label_fits and (entry.kind != "poi" or is_selected or host.zoom >= 16)
	# 点击热区只取可见的贴图与名牌，不用（为让位而放大的）占位框：
	# 否则长名选中后旁边的空地也算点中自己，点空白取消不了选择。
	var k: float = c.k
	marker.hit = [Rect2(c.point - Vector2(c.art_w * 0.5, c.art_h) * k, Vector2(c.art_w, c.art_h) * k)]
	if marker.label.visible:
		marker.hit.append(Rect2(c.point + Vector2(-c.width * 0.5, 3) * k, Vector2(c.width, c.label_h) * k))
	displayed.append(marker)
	return true

## Marker scale = pop (appear/disappear) x focus (selection jelly), anchored at
## the geographic point: the 2D node scales around its origin, the billboard and
## shadow scale in world space so camera motion never drags a mid-animation art.
func _apply_marker_scale(marker: Dictionary) -> void:
	var s := maxf(0.001, float(marker.get("pop", 1.0)) * float(marker.get("focus", 1.0)))
	marker.node.scale = Vector2.ONE * s
	if marker.has("sprite"):
		var h := float(marker.get("world_h", 1.0))
		marker.sprite.scale = Vector3.ONE * h * s
		marker.shadow.scale = Vector3.ONE * h * s

func _set_marker_shown(marker: Dictionary, on: bool) -> void:
	if bool(marker.get("on", false)) == on: return
	marker.on = on
	if marker.get("pop_tween") is Tween: (marker.pop_tween as Tween).kill()
	var tween := create_tween()
	marker.pop_tween = tween
	if on:
		marker.node.visible = true
		if marker.has("sprite"):
			marker.sprite.visible = true
			marker.shadow.visible = true
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_method(func(v: float):
			marker.pop = v
			_apply_marker_scale(marker), float(marker.get("pop", 0.0)), 1.0, 0.22)
	else:
		# 标签立即让位；世界空间贴图快速缩没（比弹入快），拖动中也不会漂移。
		marker.node.visible = false
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_method(func(v: float):
			marker.pop = v
			_apply_marker_scale(marker), float(marker.get("pop", 1.0)), 0.0, 0.12)
		tween.tween_callback(func():
			if marker.has("sprite"):
				marker.sprite.visible = false
				marker.shadow.visible = false)

## 选中项压在其他标记之上：贴图/剪影提升渲染优先级，名牌移到标记层顶。
func _set_marker_front(id: String, front: bool) -> void:
	if not markers.has(id): return
	var marker: Dictionary = markers[id]
	if marker.has("sprite"):
		marker.sprite.render_priority = 2 if front else 0
		marker.shadow.render_priority = 1 if front else -1
	if front: move_child(marker.node, maxi(0, markers.size() - 1))

func _animate_focus(id: String, to: float, duration: float) -> void:
	if not markers.has(id): return
	var marker: Dictionary = markers[id]
	if marker.get("focus_tween") is Tween: (marker.focus_tween as Tween).kill()
	var tween := create_tween()
	marker.focus_tween = tween
	if to > 1.0: tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(v: float):
		marker.focus = v
		_apply_marker_scale(marker), float(marker.get("focus", 1.0)), to, duration)

func _pack_key(c: Dictionary) -> Array:
	var kind_order := {"landmark": 0, "resident": 1, "pond": 2, "place": 2.5, "poi": 3}
	return [0 if selected.get("id", null) == c.entry.get("id") else 1,
		kind_order.get(c.entry.kind, 3),
		0 if _shown_last.has(c.id) else 1,
		float(c.entry.get("rank", 5)),
		c.id]

static func _hits_point(rects: Array, point: Vector2) -> bool:
	for r in rects:
		if (r as Rect2).has_point(point): return true
	return false

static func _hits(rects: Array, rect: Rect2) -> bool:
	for r in rects:
		if (r as Rect2).intersects(rect): return true
	return false

## Screen footprints of the player and other players, in this view's space.
func _player_blockers() -> Array:
	var result: Array = []
	var fm = host.get("farm_markers")
	if fm == null or not fm.has_method("blocker_rects"): return result
	for r in fm.blocker_rects():
		result.append(Rect2((r as Rect2).position + fm.global_position - global_position, (r as Rect2).size))
	return result

## Position and size the world-space billboard so it stays glued to the 2D
## anchor: world height h keeps the artwork at art_side logical pixels.
func _place_art(marker: Dictionary, c: Dictionary) -> void:
	var world: Vector3 = c.world
	var dist := maxf(0.01, host.cam.global_position.distance_to(world))
	var viewport_h := maxf(1.0, get_viewport_rect().size.y)
	var world_h: float = c.art_side * 2.0 * dist * tan(deg_to_rad(host.cam.fov) * 0.5) / viewport_h
	marker.world_h = world_h
	marker.sprite.position = world
	# 剪影阴影沿相机轴向右下偏移，任意 bearing/pitch 下方向一致。
	var down: Vector3 = -host.cam.global_transform.basis.y
	var right: Vector3 = host.cam.global_transform.basis.x
	marker.shadow.position = world + down * (world_h * SHADOW_OFFSET.y) + right * (world_h * SHADOW_OFFSET.x)
	_apply_marker_scale(marker)

func _free_marker(id: String) -> void:
	var marker: Dictionary = markers[id]
	if marker.get("pop_tween") is Tween: (marker.pop_tween as Tween).kill()
	if marker.get("focus_tween") is Tween: (marker.focus_tween as Tween).kill()
	marker.node.queue_free()
	if marker.has("sprite"):
		marker.sprite.queue_free()
		marker.shadow.queue_free()
	markers.erase(id)
	_hidden_until.erase(id)

func activate_at(screen: Vector2) -> bool:
	var local := screen - global_position
	if not host.city_detail_visible():
		for id in bubbles:
			var node: Control = bubbles[id].node
			if node.visible and Rect2(node.position, node.size).grow(6).has_point(local):
				city_requested.emit(str(id))
				return true
		return false
	for marker in displayed:
		if _hits_point(marker.get("hit", [marker.rect]), local): select(marker.entry); return true
	return false

func consume_back() -> bool:
	if city_panel.visible: city_panel.hide(); return true
	if list_panel.visible: list_panel.hide(); return true
	if not selected.is_empty(): clear_selection(); return true
	return false

func _settle_info() -> void:
	await get_tree().process_frame
	if not is_inside_tree(): return
	_layout()

## —— 城市切换 UI（spec 2026-09-23）——————————————————————————————————

## 宿主轻量切城后调用：换标题、地标居民；地理 POI 缓存与城市无关，保留。
func region_changed() -> void:
	_last_state = ""
	_header_key = ""
	clear_selection()
	refresh_content()
	_update_header()

## 标题口径：中心在已开通城市里 → 城市名；否则按 zoom 取瓦片地名（城市/省州/国家），
## 未开通地点副标题提示没有农场。没有地名数据（iOS/桌面）时显示 Explore。
static func header_for(in_city: bool, city_name: String, zoom: float, place_names: Dictionary) -> Array:
	if in_city: return [L10n.text(city_name), city_name]
	var tier := "settlement" if zoom >= 7.0 else "state" if zoom >= 4.0 else "country"
	var order: Array = {"settlement": ["settlement", "state", "country"], "state": ["state", "country"], "country": ["country"]}[tier]
	var title := ""
	for key in order:
		title = str(place_names.get(key, ""))
		if not title.is_empty(): break
	if title.is_empty(): title = L10n.text("Explore")
	return [title, L10n.text("No farms here yet") if tier == "settlement" else L10n.text("Zoom in to explore")]

func _update_header() -> void:
	if city_button == null: return
	var h := header_for(host.in_active_city(), str(host.region.get("name", "")), float(host.zoom), places)
	var key := str(h) + TranslationServer.get_locale()
	if key == _header_key: return
	_header_key = key
	city_button.text = str(h[0])
	subtitle.text = str(h[1])
	# 按字体实测宽度（开了省略号后 Button 的最小尺寸不含文字）；长地名在右侧按钮前截断。
	var font := city_button.get_theme_font("font")
	var text_w := font.get_string_size(city_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x if font else 120.0
	var width := minf(text_w + 34.0, maxf(120.0, size.x - 140.0))
	city_button.size = Vector2(width, 44)
	_underline.size.x = maxf(40.0, width - 22.0)

func _update_bubbles() -> void:
	var detail: bool = host.city_detail_visible()
	var area := Rect2(-global_position, get_viewport_rect().size).grow(60)
	for r in host.city_regions():
		var id := str(r.id)
		if not bubbles.has(id): bubbles[id] = _make_bubble(id)
		var bubble: Dictionary = bubbles[id]
		var overview: Dictionary = CityMapData.city(id).get("overview", {})
		var projected = host.geo_to_screen(float(overview.get("lat", r.center[0])), float(overview.get("lng", r.center[1])))
		var point: Vector2 = (projected as Vector2) - global_position if projected != null else Vector2(-1e6, -1e6)
		var node: Control = bubble.node
		node.visible = not detail and area.has_point(point)
		if not node.visible: continue
		bubble.name.text = L10n.text(str(r.get("name", id)))
		var count := int(host.city_farm_counts.get(id, -1))
		bubble.count.text = L10n.count_text("%d farm", "%d farms", count) if count >= 0 else ""
		bubble.count.visible = count >= 0
		node.size = node.get_combined_minimum_size()
		# 气泡挂在城市点下方，自己的头像站在点上方，两者在同一城市也不互相遮挡。
		node.position = point + Vector2(-node.size.x * 0.5, 6)
		bubble.dot.position = point - Vector2(5, 5)
		bubble.dot.visible = true
	for id in bubbles:
		if not bubbles[id].node.visible: bubbles[id].dot.visible = false

func _make_bubble(id: String) -> Dictionary:
	var node := PanelContainer.new()
	node.name = "MapCityBubble_" + id.validate_node_name()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := surface(Color.WHITE, 14)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	node.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(column)
	var name_label := GameUi.label("", 12, INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	var count_label := GameUi.label("", 9, MUTED)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(count_label)
	add_child(node)
	move_child(node, 0)
	var dot := Panel.new()
	dot.name = "MapCityDot_" + id.validate_node_name()
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.size = Vector2(10, 10)
	var dot_style := StyleBoxFlat.new()
	dot_style.bg_color = Color("609f28")
	dot_style.border_color = Color.WHITE
	dot_style.set_border_width_all(2)
	dot_style.set_corner_radius_all(5)
	dot.add_theme_stylebox_override("panel", dot_style)
	add_child(dot)
	move_child(dot, 0)
	return {"node": node, "name": name_label, "count": count_label, "dot": dot}

func _build_city_panel() -> void:
	city_panel = PanelContainer.new()
	city_panel.name = "MapCityPanel"
	var style := surface()
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	city_panel.add_theme_stylebox_override("panel", style)
	city_panel.position = Vector2(4, 48)
	city_panel.custom_minimum_size = Vector2(200, 0)
	city_rows = VBoxContainer.new()
	city_rows.add_theme_constant_override("separation", 0)
	city_panel.add_child(city_rows)
	city_panel.hide()
	add_child(city_panel)

## 左上角城市名：打开/收起地图内城市面板（已开通城市 + 农场数），不再离开地图页。
func toggle_city_panel() -> void:
	var opening := not city_panel.visible
	if opening:
		sheet_opened.emit()
		clear_selection()
		list_panel.hide()
		_fill_city_rows()
	city_panel.visible = opening
	city_panel.size = city_panel.get_combined_minimum_size()
	if host: host._reset_gesture()

func _fill_city_rows() -> void:
	for child in city_rows.get_children():
		city_rows.remove_child(child)
		child.queue_free()
	var header := GameUi.label(L10n.text("Cities"), 10, MUTED)
	header.custom_minimum_size.y = 22
	city_rows.add_child(header)
	for r in host.city_regions():
		var id := str(r.id)
		var current: bool = id == str(host.region.get("id", "")) and host.in_active_city()
		var count := int(host.city_farm_counts.get(id, -1))
		var text := L10n.text(str(r.get("name", id)))
		if count >= 0: text += "  ·  " + L10n.count_text("%d farm", "%d farms", count)
		var b := flat_button("check" if current else "map-pin", text, "MapCityRow_" + id)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(188, 44)
		for sty in ["normal", "hover", "focus"]: b.add_theme_stylebox_override(sty, StyleBoxEmpty.new())
		b.pressed.connect(func():
			city_panel.hide()
			city_requested.emit(id))
		city_rows.add_child(b)
	host._refresh_city_counts()
