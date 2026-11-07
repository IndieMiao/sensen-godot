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
const RECENTER_GAP := 12.0   # host_chrome: the recenter key's margin from the edge and over the host's bottom row
## A MapDestination's name stays this far inside the screen's sides; its disc stays on its point (int9: a selected
## outpost's name ran off the left edge).
const LABEL_EDGE := 8.0
const POI_CACHE_LIMIT := 400
## Anti-flicker: packing tests use a dead zone (incumbents keep their slot until
## overlap exceeds the margin; newcomers need clearance plus the margin), and a
## marker that lost its slot cannot re-enter within the cooldown.
const PACK_MARGIN := 8.0
## A pin wearing a map marker (q(48): Deliverable ✓ > Request ! > New ◆) is packed before the others, so the marker
## above it is not packed away with it (蒙恬 on C30). Entries carry it as `marker`.
const MARKER_ORDER := {"deliverable": 0, "request": 1, "new": 2, "event": 3}   # Event ★ (§9.3.3) last
## The render priority of an outpost pin or a pin wearing a marker: over other art, under the selected pin (2).
const PLACE_PRIORITY := 1
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
## Map marks on pins (plan §9.5.2; SGODOT-227, data from SGODOT-232 U6): [{id, state}] in priority order, state a
## UiStatusBadge key ("deliverable", "request", "new" …). Only the first MARK_LIMIT whose pins are on screen show.
const MARK_LIMIT := 5
const MARK_BADGE := "res://scenes/ui_kit/ui_status_badge.gd"   # UiStatusBadge (SGODOT-221); none in older builds
var marks: Array = []
## state key → Control for one mark; tests swap it. Default: a UiStatusBadge when the build has one.
var mark_factory := Callable()
var displayed: Array = []
## The outpost and marked-pin labels shown this update (local rects): the player's own My Farm label gives way to them.
var _place_labels: Array = []
## Map markers the host gives by pin id (q(48)), asked once per update through its `city_pin_markers()`; an entry's
## own `marker` wins.
var _pin_markers := {}
var subtitle: Label
var status: Label
var info: PanelContainer
var info_title: Label
var info_category: Label
var info_address: Label
var info_art: TextureRect
var info_action: Button
var dock: PanelContainer
## The host draws its own HUD and bottom controls (P0 MAP-1, §10.6.1): the city title, filters, place list and compass,
## the Map / Farm / Me dock and the zoom buttons give way. The pin card and the recenter key sit above `bottom_inset`
## (the host's bottom row). Journey leaves it off.
var host_chrome := false: set = set_host_chrome
## Pins the host draws as MapDestination (P0 MAP-1, LOCK-24): (entry) -> {icon: Texture2D, plate: bool, silhouette:
## bool, label: String (the name under the disc; q(137): P0's short name, "" for none; absent = the whole label),
## rank: int (the fixed packing order, q(137): lower packs first)}, {} to keep the art pin. The disc sits over the
## geographic point, the name under it; a map mark goes on the pin itself.
var destination_style := Callable()
## func(entry) -> bool: the host shows its own card for this pin (P0PlaceSheet), so selecting it opens no info panel.
var host_card := Callable()
## func(entry) -> int: who is in at this pin, the MapDestination's top-right count (P0: an outpost's or a pond's from
## /presence, the pond rooms of 2026-11-02); unset = the entry's own `online`. Not part of destination_style, which the
## host caches: a count changes every presence read, and refresh_pins() asks for it again.
var pin_online := Callable()
## () -> float (screen px): the top of the card the host has open over the map, INF with none, 0 for a page that covers
## it (P0: P0Ui.modal_top). With host_chrome the map's credit line keeps above it (q(133) v3).
var credits_floor := Callable()
## func(entry) -> bool: a pin the host keeps whatever it would cover (P0: the place the player is at, the avatar standing
## beside it); every other pin gives way when it would cover one packed before it or an avatar (SGODOT-269).
var kept_pin := Callable()
## P0 fog (SGODOT-275, §11.7): host-given holes [{at: Vector2 (this view's px), r: px}] round explored cities, asked each
## frame; unset = no fog (Journey). The veil draws under everything this view draws (pins, bubbles, names).
var fog_holes := Callable()
const MapFogLayer := preload("res://modules/map/map_fog_layer.gd")
var fog: ColorRect
## P0 city bubbles (§11.7.1): region id → {text (the line under the name), icon (a small glyph before it, "" none),
## outline (a green ring)}; unset = farm counts as before (Journey).
var bubble_state := Callable()
## () -> Array[Rect2] (screen px): what a city bubble must not overlap (P0: the two HUD rows, the right-hand keys, the
## quick bar). A bubble there, or not wholly on screen, is not drawn — its dot stays — never half of it (不知火舞 on 279).
var bubble_clear_rects := Callable()

func _destination(entry: Dictionary) -> Dictionary:
	return destination_style.call(entry) if destination_style.is_valid() else {}

## The pond card's action (Journey "Enter pond"; P0 "Go", §10.6.1 MAP-1).
var pond_action := "Enter pond"
## A landmark card's `Enter scene` for an authored scene (LandmarkScenes, Journey). P0 hid it (q(213): no way round the
## fog and the passes into the old scene) until q(295) gave its two scenes a Go through P0's own gate.
var landmark_scenes := true
## That key's label: P0 says Go, as on its ponds and outposts (q(295) ②).
var landmark_action := "Enter scene"
## (entry) -> bool: whether a landmark with a scene shows its key (P0: one flag each in its content table); unset = all.
var landmark_open := Callable()

func _landmark_scene(entry: Dictionary) -> String:
	if not landmark_scenes or (landmark_open.is_valid() and not bool(landmark_open.call(entry))): return ""
	return LandmarkScenes.path_for(str(host.region.get("id", "")), entry)
## (entry) -> bool: whether a POI is drawn (P0, q(212) ⑤: only in the cities explored, the fog's holes); unset = all.
var poi_shown := Callable()
## (entry) -> bool: whether a host place pin is drawn now (P0, SGODOT-355: a city's gathering spots only from a level
## nearer than its overview, wild sites from the zoom the server sends them); unset = all. Not asked for the selected.
var place_shown := Callable()
var bottom_inset := 0.0: set = set_bottom_inset
var list_panel: PanelContainer
var list_rows: VBoxContainer
var filters: Dictionary = {}
var recenter: Button
## A host's home key over the recenter key (P0 MAP-1, SGODOT-261): hidden unless the host shows and styles it; it
## asks for action "home", RECENTER_GAP over the recenter key (不知火舞 on 261). The Journey map keeps none.
var home_key: Button
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
## MapDestination packing (q(137)): the discs' centres, discs and names placed this pass (all of a higher rank than
## the pin being placed), and the names shown last pass (they keep their place until 4 px more overlap).
var _dest_centres: Array = []
var _dest_discs: Array = []
var _dest_names: Array = []
var _dest_names_last: Dictionary = {}
var _dest_names_now: Dictionary = {}
## The short names of the MapDestinations on screen this pass (q(141)): a lower-ranked pin of the same name says none.
var _dest_texts: Dictionary = {}
## The names of the always-in MapDestinations this pass (q(137) ⑤: they never give way, so no disc sits on them).
var _dest_kept_names: Array = []
## The always-in MapDestinations this pass, highest priority first (q(146)).
var _dest_always: Array = []
## The view's own controls draw over the pins' names (UiMapDestination.NAME_Z): the keys, credit line and cards.
const CHROME_Z := 2
## The fog's z: under everything this view draws, the flight's route (P0TravelCover.ROUTE_Z −1, q(152) ④) too.
const FOG_Z := -2
## Two discs nearer than this (centre to centre, px) cannot both show: the lower-ranked one hides (q(137)). A pin or
## name shown last pass hides only at DEST_HOLD px more overlap (no flicker on the edge while panning and zooming).
const DEST_NEAR := 36.0
const DEST_HOLD := 4.0
## id -> ticks_msec before which a culled marker may not reappear.
var _hidden_until: Dictionary = {}
## The pins are laid out again only when something _update_markers reads has changed since the last layout
## (SGODOT-260: a still map laid them out every frame, 2.9 ms a frame on a desktop over a busy street, and a warm phone
## fell to 30 fps). Compared by value: the camera (centre, zoom, the zoom's elastic overshoot, bearing, pitch, 3D
## anchor), the view's size and place, the language, and the player's own pins on screen (FarmMarkers: the pins give way
## to them, and its name to theirs). Compared by identity, being replaced, never edited, when they change: the selection
## (select / clear_selection), the entries (refresh_content: the city, the filter, the ponds, a host's places — P0's
## outposts and their counts, the Homestead pin while away), the live POIs (_merge_pois) and the marks (set_marks: P0's
## from each server reply). Then until it settles: a layout that changed which pins show runs again (a pin shown last
## time packs with a smaller margin), as does one whose reappear cooldown runs out (_hidden_until).
var _layout_values: Array = []
var _layout_refs: Array = []
var _layout_settling := true
var _layout_due := 0   # ticks_msec: the first reappear cooldown after the last layout that runs out (0: none)
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
	fog = MapFogLayer.new()
	fog.z_index = FOG_Z
	add_child(fog)
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
	home_key = Button.new()
	home_key.name = "MapHome"
	home_key.focus_mode = Control.FOCUS_NONE
	home_key.visible = false
	home_key.pressed.connect(func(): action_requested.emit("home"))
	add_child(home_key)
	for spec in [["plus", 1.0], ["minus", -1.0]]:
		var b := flat_button(spec[0], "", "MapZoom_" + spec[0])
		compact_round_button(b)
		b.pressed.connect(func(): host._tween_zoom(host.zoom + spec[1]))
		add_child(b)
	# A pin's name draws over every disc (UiMapDestination.NAME_Z, 不知火舞 on #306): the view's own controls (keys,
	# credit line, cards, panels) draw over the names. The fog stays under everything.
	for c in get_children():
		if c is Control and c != fog: (c as Control).z_index = CHROME_Z
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

func set_host_chrome(v: bool) -> void:
	host_chrome = v
	if dock == null: return
	for n in [city_button, subtitle, _underline, dock, get_node("MapLandmarkList"), get_node("MapFilters"), get_node("MapNorth"),
			get_node("MapZoom_plus"), get_node("MapZoom_minus")]:
		(n as CanvasItem).visible = not v
	status.position.y = CONTENT_TOP if v else 94.0   # under the host's HUD
	# q(133) v3: the credit line left-aligned in #2F3A33 at 55 %, Regular, no outline
	var credits: Label = get_node("MapCredits")
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if v else HORIZONTAL_ALIGNMENT_CENTER
	credits.add_theme_color_override(&"font_color", Color(UiTokens.COLOR_TEXT, CREDITS_ALPHA) if v else MUTED)
	credits.add_theme_constant_override(&"outline_size", 0)
	_layout()

## The lowest y the map's own content uses: the dock's top, or the host's bottom row with host_chrome.
func content_bottom() -> float:
	return size.y - bottom_inset if host_chrome else dock.position.y

func set_bottom_inset(v: float) -> void:
	bottom_inset = v
	if dock != null: _layout()

func _layout() -> void:
	if dock == null: return
	var dock_width := minf(300, size.x)
	dock.position = Vector2((size.x - dock_width) * 0.5, size.y - 54)
	dock.size = Vector2(dock_width, 48)
	# With the host's chrome the bottom edge is the host's row (P0's Bag), not the dock.
	var floor_y := content_bottom()
	if not host_chrome:   # Journey's centred line; P0's is laid out each frame (_update_credits, q(133) v3)
		get_node("MapCredits").position = Vector2(0, size.y - 4)
		get_node("MapCredits").size = Vector2(size.x, 12)
	var info_height := maxf(72, info.get_combined_minimum_size().y)
	info.position = Vector2(0, floor_y - 8 - info_height)
	info.size = Vector2(size.x, info_height)
	info.clip_contents = true
	list_panel.position = Vector2(maxf(0, size.x - 212), 44)
	list_panel.size = Vector2(minf(212, size.x), minf(340, size.y - 180))
	# With the host's chrome: right-aligned over its Bag, 12 apart (不知火舞 on 234: 12 from the edge, 12 above Bag).
	var edge := RECENTER_GAP if host_chrome else 0.0
	recenter.position = Vector2(size.x - 44 - edge, (info.position.y if info.visible else floor_y) - 44 - (RECENTER_GAP if host_chrome else 8.0))
	recenter.size = Vector2(44, 44)
	home_key.position = recenter.position - Vector2(0, 44 + RECENTER_GAP)
	home_key.size = Vector2(44, 44)
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

## (entry) -> String: a host's tag after a pin's name ("" = none), e.g. P0's "Pond · 1.6 km"; wins over entry.tag.
var pin_tag := Callable()

func _label_text(entry: Dictionary) -> String:
	if entry.kind == "resident" and str(entry.get("status", "")) == "Ready to deliver":
		return _name(entry) + " · " + L10n.text("Ready to deliver")
	if pin_tag.is_valid():
		var t := str(pin_tag.call(entry))
		if t != "": return _name(entry) + " · " + t
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

## Labels written whole, never cut: an outpost's and any pin's wearing a marker (不知火舞 on C30 / #83); unmarked ponds
## and landmarks keep their cut labels.
func _whole_label(entry: Dictionary) -> bool:
	return entry.get("kind") == "place" or _marker_of(entry) != "" or not _destination(entry).is_empty()

## A whole label's width: its text on one line at the pins' 9 pt, with no cap (不知火舞 on C30), plus the marker
## style's 4 + 4 and 2 to spare.
func _whole_label_width(entry: Dictionary) -> float:
	var font := get_theme_font("font", "Label")
	if font == null: return 48.0
	return ceilf(font.get_string_size(_label_text(entry), HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x) + 10.0

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
	# a host that answered by letting the pin go (P0: a city's card, not the pin's) keeps it so — only the press, the pin
	# back at its size, never raised and left raised (q(212) ⑥, 不知火舞 on 327)
	if str(selected.get("id", "")) != str(entry.get("id", "")):
		_press(str(entry.get("id", "")))
		return
	_animate_focus(str(entry.get("id", "")), FOCUS_SCALE, 0.28)
	_set_marker_front(str(entry.get("id", "")), true)
	if host_card.is_valid() and bool(host_card.call(entry)):
		info.hide()
		_layout()
		if host: host._reset_gesture()
		return
	info_title.text = _name(entry)
	info_category.text = _category_text(str(entry.get("category", "Place")), _place_city(entry))
	info_address.text = str(entry.get("address", ""))
	info_address.visible = not info_address.text.is_empty()
	var landmark_scene := _landmark_scene(entry)
	info_action.visible = entry.kind in ["resident", "pond", "place"] or not landmark_scene.is_empty()
	if entry.kind == "resident":
		info_category.text = L10n.text("Resident") + " · " + L10n.text(str(entry.get("status", "Talk")))
		info_action.text = L10n.text("Visit resident")
		info_action.icon = GameUi.icon("message-circle")
	elif entry.kind == "pond":
		info_category.text = L10n.text(str(SystemPonds.TITLES.get(entry.template_id, "Fishing pond")))
		info_action.text = L10n.text(pond_action)
		info_action.icon = GameUi.icon("fish")
	elif entry.kind == "place":
		info_category.text = L10n.text(str(entry.get("category", "Place")))
		info_action.text = L10n.text(str(entry.get("action", "Enter")))
		info_action.icon = GameUi.icon(str(entry.get("action_icon", "footprints")))
	elif not landmark_scene.is_empty():
		info_action.text = L10n.text(landmark_action)
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
func select_player(entry: Dictionary, portrait: Texture2D, action := "Visit Farm") -> void:
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
	info_action.text = L10n.text(action)
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
			if not _landmark_scene(selected).is_empty():
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

func set_marks(list: Array) -> void:
	marks = list
	_apply_marks(markers.keys().filter(func(id): return bool(markers[id].get("on", false))))

## The marks that show: the first `limit` in priority order whose pins are on screen (§9.5.2: at most 5).
static func pick_marks(list: Array, shown: Array, limit := MARK_LIMIT) -> Dictionary:
	var out := {}
	for m in list:
		if out.size() >= limit: break
		var id := str(m.get("id", ""))
		if shown.has(id) and not out.has(id): out[id] = str(m.get("state", ""))
	return out

func _apply_marks(shown: Array) -> void:
	var on := pick_marks(marks, shown)
	for id in markers:
		var marker: Dictionary = markers[id]
		var want := str(on.get(id, ""))
		if marker.has("dest"):   # MapDestination wears its mark itself (Show mark, LOCK-24)
			(marker.dest as UiMapDestination).mark = want
			continue
		var badge = marker.get("mark")
		if want == "":
			if badge is Control: (badge as Control).visible = false
			continue
		if not (badge is Control) or str(marker.get("mark_state", "")) != want:
			if badge is Control: (badge as Control).queue_free()
			badge = _make_mark(want)
			marker.mark = badge
			marker.mark_state = want
			if badge == null: continue
			(badge as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE   # the pin takes the tap (LOCK-11)
			marker.node.add_child(badge)
		# Top-left of the pin art, overlapping its corner (MAP-1 482:95).
		(badge as Control).position = Vector2(-float(marker.get("art_w", 48.0)) * 0.5 - 8.0, -float(marker.get("art_h", 56.0)) - 6.0)
		(badge as Control).visible = true

func _make_mark(state: String) -> Control:
	if mark_factory.is_valid(): return mark_factory.call(state)
	return status_badge(state)

## A UiStatusBadge (SGODOT-221) in this state, or null when the build has no such component or state.
static func status_badge(state: String) -> Control:
	if not ResourceLoader.exists(MARK_BADGE): return null
	var script := load(MARK_BADGE) as Script
	var states: Dictionary = script.get_script_constant_map().get("State", {})
	if not states.has(state.to_upper()): return null
	var badge: Control = script.new()
	badge.set("state", int(states[state.to_upper()]))
	return badge

## A short attention pulse on one pin (Today's "Show on map", SGODOT-232 U6); no camera move, no selection.
func pulse_pin(id: String, seconds := 0.6) -> void:
	if not markers.has(id) or str(selected.get("id", "")) == id: return
	var marker: Dictionary = markers[id]
	if marker.get("focus_tween") is Tween: (marker.focus_tween as Tween).kill()
	var tween := create_tween()
	marker.focus_tween = tween
	marker.pulse = true   # a MapDestination's pulse scales only its disc (_apply_marker_scale)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var step := func(v: float):
		marker.focus = v
		_apply_marker_scale(marker)
	tween.tween_method(step, 1.0, 1.18, seconds * 0.5)
	tween.tween_method(step, 1.18, 1.0, seconds * 0.5)

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
	if _layout_wanted(): _update_markers()
	else: _show_selected_art()   # a portrait drawn while the map is still
	_update_bubbles()
	_move_ghosts()
	_update_fog()
	_update_credits()
	_update_header()

## q(133) v3 (Q133-V3-MAP 2416:128683): with host_chrome the map's credit is one quiet line at the bottom-left —
## `© Mapbox © OpenStreetMap`, 9 pt Regular #2F3A33 at 55 %, no outline or plate, 16 pt from the left and 6 pt over the
## safe area's bottom (pt / dp: converted by the screen's density) — riding 6 pt above a card the host has open, hidden
## under a full-screen page and where there is no Mapbox map (the desktop). Without host_chrome (Journey) it stays as
## it was, centred at the bottom.
const CREDITS_ALPHA := 0.55
const CREDITS_PT := 9.0
const CREDITS_LEFT_PT := 16.0
const CREDITS_GAP_PT := 6.0
func _update_credits() -> void:
	var credits: Label = get_node("MapCredits")
	if not host_chrome: return
	var mapbox := _attached_bridge != null and _attached_bridge.has_mapbox()
	var floor_y: float = float(credits_floor.call()) if credits_floor.is_valid() else INF
	credits.visible = mapbox and floor_y > 1.0
	if not credits.visible: return
	var k := _px_per_pt()
	var font := maxi(1, roundi(CREDITS_PT * k))
	if credits.get_theme_font_size(&"font_size") != font: credits.add_theme_font_size_override(&"font_size", font)
	var h := credits.get_combined_minimum_size().y
	var bottom := size.y - CREDITS_GAP_PT * k
	if floor_y < INF: bottom = minf(bottom, floor_y - global_position.y - CREDITS_GAP_PT * k)
	credits.position = Vector2(CREDITS_LEFT_PT * k, bottom - h)
	credits.size = Vector2(size.x, h)

## Godot px per pt / dp on this screen (q(133) v3 sizes are in pt / dp): the view's width over the screen's in pt.
func _px_per_pt() -> float:
	var ratio := _attached_bridge.get_pixel_ratio() if _attached_bridge != null else 1.0
	var screen_px := float(DisplayServer.window_get_size().x)
	if screen_px <= 0.0 or ratio <= 0.0: return 1.0
	return get_viewport_rect().size.x / (screen_px / ratio)

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
	var dest := _destination(entry)
	if not dest.is_empty():
		var pin := UiMapDestination.new(dest.get("icon", null), _dest_text(entry), bool(dest.get("plate", false)))
		pin.theme = UiKit.theme()
		node.add_child(pin)
		result.dest = pin
	elif entry.kind == "resident":
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

## Whether the pins need laying out this frame (see _layout_values): what _update_markers reads is read here, cheaply,
## and kept for the next frame.
func _layout_wanted() -> bool:
	var fm = host.get("farm_markers")
	var own := []
	if fm != null and fm.has_method("blocker_rects"):
		# blocker_rects(true) as well: a space pin gives way to the bodies with their names while shown, and whether the
		# player's own name shows is the last layout's own yield (亚瑟 on #189, SGODOT-269).
		own = [fm.blocker_rects(), fm.blocker_rects(true), fm.self_label_rect() if fm.has_method("self_label_rect") else Rect2(),
			fm.global_position]
	# The 3D anchor (the billboards' world points) moves only with the centre today (MapPoc._maybe_reanchor): compared too,
	# so a re-anchor on its own would never leave them where they were (刘邦 on #181).
	var values := [host.center_lat, host.center_lng, host.zoom, host.get("_zoom_elastic"), host.bearing, host.pitch,
		host.anchor_lat, host.anchor_lng, get_viewport_rect().size, global_position, TranslationServer.get_locale(), own]
	var refs := [selected, entries, live_pois, marks]
	var wanted := _layout_settling or values != _layout_values or refs.size() != _layout_refs.size() \
		or (_layout_due > 0 and Time.get_ticks_msec() >= _layout_due)
	for i in refs.size():
		if wanted: break
		wanted = not is_same(refs[i], _layout_refs[i])
	_layout_values = values
	_layout_refs = refs
	return wanted

## The pins drawn again on the next pass with nothing else changed (a pond's count from /presence: its entry is the
## map's own, so no set_places brings it).
func refresh_pins() -> void:
	_layout_refs = []

## A fresh packing from the next pass: no pin holds its place for having been shown (the DEST_HOLD and PACK_MARGIN
## grace), so a view the host has just chosen — P0's opening view — packs as if first seen at its own zoom (不知火舞 on
## #457: a tackle shop 35 px from its pond stayed only because the view before it had shown it).
func forget_shown() -> void:
	_shown_last.clear()
	_layout_settling = true

func _update_markers() -> void:
	displayed.clear()
	_place_labels.clear()
	_pin_markers = host.call("city_pin_markers") if host.has_method("city_pin_markers") else {}
	# Cull only outside the screen plus the artwork's extent. UI panels cover
	# geography; they never move or hide its anchors to make room for themselves.
	var area := Rect2(-global_position, get_viewport_rect().size).grow(120)
	var all := entries.filter(func(e):return e.kind in ["landmark", "resident", "pond", "place"]) + live_pois
	var keep := {}
	var candidates: Array = []
	# 国家/省级视野只剩城市气泡与自己的头像：细节标记全部让出（带消失动画）。
	var detail: bool = host.city_detail_visible()
	var poi_gate := poi_shown.is_valid()
	var place_gate := place_shown.is_valid()
	for entry in all:
		var id := str(entry.id)
		keep[id] = true
		if not detail or not _entry_visible(entry): continue
		var art_key := CityMapData.art_key(entry)
		if entry.kind == "place" and place_gate and selected.get("id", null) != entry.get("id") and not bool(place_shown.call(entry)): continue
		if entry.kind == "poi":
			if poi_gate and not bool(poi_shown.call(entry)): continue
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
		var is_sel: bool = selected.get("id", null) == entry.get("id")
		var pm := _pin_metrics(entry, is_sel)
		var width: float = pm.width
		var art_side: float = pm.art_side
		var top: float = pm.top
		var label_h: float = pm.label_h
		var label_w: float = pm.label_w
		var art_w: float = pm.art_w
		var art_h := top
		var side := maxf(width, art_side)
		var dest := not _destination(entry).is_empty()
		# A MapDestination holds only its disc: its name folds on its own and the pin stays (不知火舞 on 234 A2).
		var below := 0.0 if dest else 3.0 + label_h + 1.0
		# 选中项的占位随果冻放大同步变大，邻居的贴图和名牌为它让位。MapDestination 也一样（SGODOT-261）。
		var k := FOCUS_SCALE if is_sel else 1.0
		side *= k
		top *= k
		below *= k
		var bounds := Rect2(point - Vector2(side * 0.5, top), Vector2(side, top + below))
		candidates.append({"entry": entry, "id": id, "world": world, "point": point,
			"bounds": bounds, "width": width, "art_side": art_side, "art": art_key,
			"label_h": label_h, "label_w": label_w, "art_w": art_w, "art_h": art_h, "k": k})
	# Screen-space packing: anchors never move; a marker either shows in place
	# or yields entirely. Order: selected, landmarks, residents, then POIs by
	# incumbency (anti-flicker), source rank and id — fully deterministic.
	_pack_order(candidates)
	_dest_centres.clear()
	_dest_discs.clear()
	_dest_names.clear()
	_dest_names_now.clear()
	_dest_texts.clear()
	_dest_kept_names.clear()
	_dest_always.clear()
	var blockers := _player_blockers()
	var bodies := _player_blockers(true)   # what a space pin gives way to: the avatars' bodies (SGODOT-269)
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
		if _place_candidate(c, occupied, blockers, now, bodies) and c.entry.kind == "poi" and str(c.art) in DINING_ARTS:
			dining += 1
	for c in deferred:
		_place_candidate(c, occupied, blockers, now, bodies)
	_yield_own_label()
	_dest_names_last = _dest_names_now.duplicate()
	var shown := displayed.map(func(m): return str(m.entry.id))
	var shown_now := {}
	for id in shown: shown_now[id] = true
	_layout_settling = shown_now != _shown_last   # the pins shown now pack differently next time: run once more
	_shown_last = shown_now
	for id in markers.keys():
		_set_marker_shown(markers[id], shown.has(id))
		if not keep.has(id): _free_marker(id)
	_apply_marks(shown)
	_stack_always()
	_raise_selected()
	if _hidden_until.size() > 256:
		for id in _hidden_until.keys():
			if now >= int(_hidden_until[id]): _hidden_until.erase(id)
	_layout_due = 0
	for until in _hidden_until.values():
		if int(until) > now and (_layout_due == 0 or int(until) < _layout_due): _layout_due = int(until)
	if _provider_error.is_empty():
		status.text = L10n.text("No dining places in view. Move or zoom the map.") if filter == "food" and displayed.is_empty() else ""
	_show_selected_art()
	# Keep controls on top even when dynamically creating markers.

## The selected resident's or player's portrait on its card: drawn asynchronously, so looked for every frame, laid out
## or not.
func _show_selected_art() -> void:
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

## One placement attempt. Anchors never move: on success the marker is laid out
## in place, on failure it stays hidden this frame. Dead-zone margins plus the
## reappear cooldown keep boundary oscillation from flickering markers.
func _place_candidate(c: Dictionary, occupied: Array, blockers: Array, now: int, bodies: Array = []) -> bool:
	var entry: Dictionary = c.entry
	var id: String = c.id
	var is_selected: bool = selected.get("id", null) == entry.get("id")
	var incumbent: bool = _shown_last.has(id)
	var label_fits := true
	var dest_pin := not _destination(entry).is_empty()
	# A MapDestination's three always-in kinds (q(105) / q(137)): the selected pin, a marked one and where the player
	# is. Nothing hides them, nor their names.
	var always := is_selected or _marker_of(entry) != "" or (kept_pin.is_valid() and bool(kept_pin.call(entry)))
	if dest_pin and not always:
		# q(137): the pins stay on their points and pack by a fixed rank (_pack_key), so every pass gives the same
		# answer. A disc whose centre is nearer than 36 px to a higher-ranked one shown hides; one shown last pass holds
		# until 4 px nearer. The avatars' bodies keep their claim (SGODOT-269).
		var near := DEST_NEAR - (DEST_HOLD if incumbent else 0.0)
		var centre := _disc_centre(c)
		for other in _dest_centres:
			if centre.distance_to(other) < near: return false
		# nor on an always-in pin's name, which never gives way (周瑜 on #306): a disc right under one hides
		if _hits(_dest_kept_names, c.bounds.grow(-DEST_HOLD * 0.5) if incumbent else c.bounds): return false
		if _hits(bodies, c.bounds.grow(-PACK_MARGIN if incumbent else PACK_MARGIN)): return false
	elif not is_selected and not dest_pin:
		if not incumbent and now < int(_hidden_until.get(id, 0)): return false
		var probe: Rect2 = c.bounds.grow(-PACK_MARGIN if incumbent else PACK_MARGIN)
		# 地标相互之间也做遮挡剔除，但不给玩家 pin 让位；其余标记两者都让。
		# Space pins (P0's outposts, the Homestead pin, ponds) give way as every POI does (用户 via SGODOT-269, 不知火舞:
		# they piled up by home at the city level): to the pins packed before them and to the players' avatars, with the
		# same cooldown and margins. They still pack first (_pack_key), so an outpost yields only to the selected pin, a
		# marked one or an outpost nearer home. Always in: a pin wearing a marker (a task: 不知火舞 on 234 A2) and the
		# host's kept pin (P0: where the player is, the avatar beside it).
		# A space pin keeps clear of the avatar's body only (不知火舞 on 269); a POI's tall artwork, of the margin over it.
		var kept := _marker_of(entry) != "" or (kept_pin.is_valid() and bool(kept_pin.call(entry)))
		var avatars := bodies if not _destination(entry).is_empty() else blockers
		var blocked: bool = not kept and (_hits(occupied, probe) or (entry.kind != "landmark" and _hits(avatars, probe)))
		if blocked:
			if incumbent: _hidden_until[id] = now + REAPPEAR_COOLDOWN_MS
			return false
	var label_rect := Rect2(c.point + Vector2(-c.label_w * 0.5, 3), Vector2(c.label_w, c.label_h))
	var disc_off_screen := false
	var label_above := false
	var above_gap := UiMapDestination.above_gap_for(_marker_of(entry) != "")   # clear of a mark's badge (刘邦 on #111)
	if not _destination(entry).is_empty():
		label_rect.position.y = c.point.y + UiMapDestination.LABEL_GAP   # where the pin draws it
		# The whole name on screen: while any of its disc is on screen it slides in from the edge, the disc stays. A disc
		# packed in the margin off screen shows no name (no name without its pin).
		var screen_x0 := -global_position.x   # the screen's left edge here (the view may be inset by a safe area)
		var screen_w := get_viewport_rect().size.x
		var half := UiMapDestination.DISC * 0.5   # any of the disc on screen
		if c.point.x + half >= screen_x0 and c.point.x - half <= screen_x0 + screen_w:
			var lo := screen_x0 + LABEL_EDGE
			# A selected pin draws its name scaled about its point (k): that drawn name stays on screen.
			var drawn_x := clampf(c.point.x + (label_rect.position.x - c.point.x) * c.k, lo,
				maxf(lo, screen_x0 + screen_w - LABEL_EDGE - c.label_w * c.k))
			label_rect.position.x = c.point.x + (drawn_x - c.point.x) / c.k
		else: disc_off_screen = true
	if dest_pin:
		# q(137): the short name under the disc only. The selected pin's card says its whole name, so it shows none; a
		# name that would cover a higher-ranked disc or name hides (the pin stays), one shown last pass at 4 px more.
		# The always-in kinds keep theirs.
		# q(141): of the pins on screen with one short name only the highest-ranked says it (the always-in kinds keep
		# theirs); the card says each whole.
		# q(146): the always-in kinds among themselves give way too — they pack first, by their own priority (selected >
		# where the player is > marked, by kind), so what is packed before one is higher: its name hides whole on such a
		# disc or name, and comes back once they part (4 px). Other pins' discs and the avatars still never hide it.
		var held := label_rect.grow(-DEST_HOLD * 0.5) if _dest_names_last.has(id) else label_rect
		var same_name := _dest_texts.has(_dest_text(entry))
		var under := _hits(_dest_discs, held) or _hits(_dest_names, held)
		label_fits = not is_selected and c.label_w > 0.0 and (not under if always else not (same_name or under
			or _hits(bodies, held)))
	elif entry.kind == "landmark":
		label_fits = is_selected or not _hits(occupied, Rect2(c.point - Vector2(c.width * 0.5, -3), Vector2(c.width, 20)))
	elif entry.kind == "place":
		# An art place pin (a host without destination_style) keeps its pin; its label shows unless it would cover a
		# pin or a label placed before it, and comes back once zooming in parts them or the pin is selected (C30).
		label_fits = is_selected or not _hits(occupied, label_rect)
	if disc_off_screen: label_fits = false   # no name without its pin on screen
	# The pin lays its name out unscaled (label_shift); a selected one draws it scaled about its point like every pin's
	# art (k, SGODOT-261): what packs after it and the taps keep to where it is drawn.
	var label_shift: float = label_rect.position.x - (c.point.x - c.label_w * 0.5)
	if not _destination(entry).is_empty() and c.k != 1.0:
		label_rect = Rect2(c.point + (label_rect.position - c.point) * c.k, label_rect.size * c.k)
	if dest_pin:
		if always: _dest_always.append(id)   # q(146): their discs draw in this order, the first on top
		# Its disc (scaled when selected) and its name, if shown: the lower-ranked pins and every POI after it keep
		# clear of them, and My Farm's label gives way to the name (不知火舞 on #83).
		occupied.append(c.bounds)
		_dest_discs.append(c.bounds)
		_dest_centres.append(_disc_centre(c))
		var text := _dest_text(entry)
		if text != "" and not disc_off_screen: _dest_texts[text] = true   # on screen, named or not: it has this name
		if label_fits:
			occupied.append(label_rect)
			_dest_names.append(label_rect)
			_place_labels.append(label_rect)
			_dest_names_now[id] = true
			if always: _dest_kept_names.append(label_rect)
	elif entry.kind == "place":
		occupied.append(Rect2(c.point - Vector2(c.art_w * 0.5, c.art_h), Vector2(c.art_w, c.art_h)))
		if label_fits:
			occupied.append(label_rect)
			_place_labels.append(label_rect)
	else:
		occupied.append(c.bounds)
		# A marked pin's whole label reaches past its bounds: what comes after keeps clear of it too, and My Farm's label
		# gives way to it as to an outpost's (不知火舞 on #83).
		if _marker_of(entry) != "":
			occupied.append(label_rect)
			if entry.kind != "poi" or is_selected or host.zoom >= 16: _place_labels.append(label_rect)
	if not markers.has(id):
		markers[id] = _make_marker(entry)
		# Selected before its pin was made (Show on map flies, then selects): the same jelly a tap plays (SGODOT-261).
		if is_selected:
			_animate_focus(id, FOCUS_SCALE, 0.28)
			_set_marker_front(id, true)
	var marker: Dictionary = markers[id]
	marker.entry = entry
	marker.node.position = c.point
	marker.rect = c.bounds
	marker.anchor = c.point
	marker.art_w = float(c.art_w)
	marker.art_h = float(c.art_h)
	if marker.has("dest"):
		# MapDestination: 2D over the map (and so over the 3D avatar), its own name under the disc.
		var dest: Dictionary = _destination(entry)
		var pin: UiMapDestination = marker.dest
		pin.icon = dest.get("icon", null)
		pin.plate = bool(dest.get("plate", false))
		pin.silhouette = bool(dest.get("silhouette", false))   # a fogged city's place: the glyph alone (MAP-2)
		pin.locked = bool(dest.get("locked", false))   # a place not open yet: grey, a lock, its name kept (SGODOT-355)
		pin.text = _dest_text(entry)
		# who is in: the top-right count, none at 0 (q(137))
		pin.online = int(pin_online.call(entry)) if pin_online.is_valid() else int(entry.get("online", 0))
		pin.name_shown = label_fits
		pin.above_gap = above_gap
		pin.label_above = label_above
		pin.label_shift = label_shift
		pin.position = -pin.anchor_offset()
	elif entry.kind == "resident":
		marker.portrait.position = Vector2(-18, -38)
	else:
		_place_art(marker, c)
		# A marker comes and goes with the view: the draw rule follows it (the selected pin keeps its front priority).
		marker.sprite.no_depth_test = _over_avatar(entry)
		if not is_selected: marker.sprite.render_priority = PLACE_PRIORITY if _over_avatar(entry) else 0
	marker.label.text = _label_text(entry)
	# 名牌永远跟随图标居中（出屏也不挪）；选中项长名按词折行，不再省略号截断。
	var whole := _whole_label(entry)   # one line, never cut
	marker.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if is_selected and not whole else TextServer.AUTOWRAP_OFF
	marker.label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if is_selected or whole else TextServer.OVERRUN_TRIM_ELLIPSIS
	marker.label.position = Vector2(-c.label_w * 0.5, 3)
	marker.label.size = Vector2(c.label_w, c.label_h)
	marker.label.add_theme_font_size_override("font_size", 9)
	marker.label.visible = label_fits and (entry.kind != "poi" or is_selected or host.zoom >= 16) and not marker.has("dest")
	# 点击热区只取可见的贴图与名牌，不用（为让位而放大的）占位框：
	# 否则长名选中后旁边的空地也算点中自己，点空白取消不了选择。
	var k: float = c.k
	marker.hit = [Rect2(c.point - Vector2(c.art_w * 0.5, c.art_h) * k, Vector2(c.art_w, c.art_h) * k)]
	if marker.has("dest") and label_fits: marker.hit.append(label_rect)   # where the name is drawn (scaled by k)
	elif marker.label.visible:
		marker.hit.append(Rect2(c.point + Vector2(-c.label_w * 0.5, 3) * k, Vector2(c.label_w, c.label_h) * k))
	displayed.append(marker)
	return true

## Marker scale = pop (appear/disappear) x focus (selection jelly), anchored at
## the geographic point: the 2D node scales around its origin, the billboard and
## shadow scale in world space so camera motion never drags a mid-animation art.
## A MapDestination scales with its selection like every pin (用户 via 奕星, SGODOT-261; it used to keep its size, Figma
## 1802:118612). Only a Show on map pulse (pulse_pin) scales just its disc. Which one is playing is the marker's own
## state, never the selection: the selection is cleared at once while the pin shrinks back after it (the jump on Go).
func _apply_marker_scale(marker: Dictionary) -> void:
	var focus := float(marker.get("focus", 1.0))
	if marker.has("dest"):
		var pulse := bool(marker.get("pulse", false))
		(marker.dest as UiMapDestination).focus = focus if pulse else 1.0
		if pulse: focus = 1.0
	var s := maxf(0.001, float(marker.get("pop", 1.0)) * focus)
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
	_drop_ghost(marker.get("ghost", {}))
	if on:
		marker.node.visible = true
		if marker.has("sprite"):
			marker.sprite.visible = true
			marker.shadow.visible = true
		tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_method(func(v: float):
			marker.pop = v
			_apply_marker_scale(marker), float(marker.get("pop", 0.0)), 1.0, POP_IN_S)
	else:
		# 标签立即让位；世界空间贴图快速缩没（比弹入快），拖动中也不会漂移。A MapDestination's disc shrinks as a ghost (h1).
		if marker.has("dest") and marker.node.visible: marker.ghost = _ghost_pin(marker)
		marker.node.visible = false
		tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_method(func(v: float):
			marker.pop = v
			_apply_marker_scale(marker), float(marker.get("pop", 1.0)), 0.0, POP_OUT_S)
		tween.tween_callback(func():
			if marker.has("sprite"):
				marker.sprite.visible = false
				marker.shadow.visible = false)

## A going MapDestination's disc, as it is drawn (its scale, its silhouette), without its name or marks, shrinking into
## its point where the pin was drawn.
func _ghost_pin(marker: Dictionary) -> Dictionary:
	var pin: UiMapDestination = marker.dest
	var node := Control.new()
	node.name = "PinGhost"
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var disc := UiMapDestination.new(pin.icon, "", pin.plate)
	disc.theme = UiKit.theme()
	disc.name_shown = false
	disc.silhouette = pin.silhouette
	disc.locked = pin.locked
	disc.focus = pin.focus
	node.add_child(disc)
	disc.position = -disc.anchor_offset()
	node.position = marker.node.position
	node.scale = marker.node.scale
	add_child(node, true)
	move_child(node, (marker.node as Node).get_index())
	return _shrink_ghost(node, float(marker.entry.get("lat", 0.0)), float(marker.entry.get("lng", 0.0)), Vector2.ZERO)

## h1: a city bubble and its dot come and go as the pins do — out of the city's point (the bubble from its top middle,
## where it hangs from the dot), into it — and only when one really shows or hides: _update_bubbles has settled them
## for this frame (q(153)'s 4 px hold keeps them off the line), so a pass that keeps one shown or hidden plays nothing.
func _pop_bubbles() -> void:
	for id in bubbles:
		var b: Dictionary = bubbles[id]
		var node: Control = b.node
		_pop(b, "node", node, Vector2(node.size.x * 0.5, -BUBBLE_DROP))
		var dot: Control = b.dot
		_pop(b, "dot", dot, dot.size * 0.5)

func _pop(b: Dictionary, key: String, node: Control, pivot: Vector2) -> void:
	var on := node.visible
	if on == bool(b.get(key + "_on", false)): return
	b[key + "_on"] = on
	# The bubble itself is placed whole at once, for its tap and everything that reads its rect; a ghost of it does the
	# moving, over it while it comes (the bubble clear till then), in its place as it goes.
	var old: Dictionary = b.get(key + "_ghost", {})
	var from := (old.node as Control).scale.x if _ghosts.has(old) and is_instance_valid(old.node) else (0.001 if on else 1.0)
	_drop_ghost(old)
	node.modulate.a = 1.0
	var geo = b.get("geo")
	if not (geo is Vector2): return
	var ghost := node.duplicate() as Control
	ghost.name = ("BubbleGhost" if key == "node" else "DotGhost")
	ghost.visible = true
	ghost.pivot_offset = pivot
	ghost.position = node.position
	ghost.scale = Vector2.ONE * from
	add_child(ghost, true)
	ghost.size = node.size   # a duplicated container comes out taller than its words (88 for 40)
	move_child(ghost, node.get_index() + 1)
	if on:
		node.modulate.a = 0.0
		b[key + "_ghost"] = _ghost_tween(ghost, (geo as Vector2), -pivot, true, func():
			if is_instance_valid(node): node.modulate.a = 1.0)
	else:
		b[key + "_ghost"] = _ghost_tween(ghost, (geo as Vector2), -pivot, false)

func _shrink_ghost(node: Control, lat: float, lng: float, offset: Vector2) -> Dictionary:
	return _ghost_tween(node, Vector2(lat, lng), offset, false)

## A ghost growing out of its point (TRANS_BACK, POP_IN_S, `done` after) or shrinking into it (TRANS_QUAD, POP_OUT_S),
## freed at the end.
func _ghost_tween(node: Control, geo: Vector2, offset: Vector2, grow: bool, done := Callable()) -> Dictionary:
	var g := {node = node, lat = geo.x, lng = geo.y, offset = offset}
	var tween := create_tween()
	if grow: tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else: tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(node, "scale", Vector2.ONE * (1.0 if grow else 0.001), POP_IN_S if grow else POP_OUT_S)
	tween.tween_callback(func():
		_drop_ghost(g, false)
		if done.is_valid(): done.call())
	g.tween = tween
	_ghosts.append(g)
	return g

func _drop_ghost(g: Dictionary, kill := true) -> void:
	if g.is_empty() or not _ghosts.has(g): return
	_ghosts.erase(g)
	if kill and g.tween is Tween: (g.tween as Tween).kill()   # not from its own last step
	if is_instance_valid(g.node): (g.node as Node).queue_free()

## Each ghost on its point as the map moves (the pins and bubbles it stood in for are placed every pass; a hidden one
## is not), so a drag never leaves one behind.
func _move_ghosts() -> void:
	for g in _ghosts:
		var projected = host.geo_to_screen(float(g.lat), float(g.lng))
		if projected != null and is_instance_valid(g.node): (g.node as Control).position = (projected as Vector2) - global_position + (g.offset as Vector2)

## 选中项压在其他标记之上：贴图/剪影提升渲染优先级，名牌移到标记层顶。
## The selected pin's 2D node over every other pin's, pins made after it was selected included: a MapDestination's
## name is 2D, and a neighbour's disc must not cover it.
func _raise_selected() -> void:
	_raise(str(selected.get("id", "")))

## q(146): the always-in discs stacked by priority, the highest on top, so its mark shows whole where they pile up (the
## selected one goes over all after, _raise_selected). Only moved when out of order.
func _stack_always() -> void:
	var ordered := true
	for i in range(1, _dest_always.size()):
		if not markers.has(_dest_always[i]) or not markers.has(_dest_always[i - 1]): continue
		if (markers[_dest_always[i]].node as Node).get_index() > (markers[_dest_always[i - 1]].node as Node).get_index():
			ordered = false
			break
	if ordered and (_dest_always.is_empty() or _is_top(_dest_always[0])): return
	for i in range(_dest_always.size() - 1, -1, -1): _raise(_dest_always[i])

func _is_top(id: String) -> bool:
	if not markers.has(id): return true
	var at := (markers[id].node as Node).get_index()
	return markers.values().all(func(m): return (m.node as Node).get_index() <= at)

## A pin's node over every other pin's (the pins are not the view's only children: a count of pins is no index).
func _raise(id: String) -> void:
	if not markers.has(id): return
	var top := 0
	for m in markers.values(): top = maxi(top, (m.node as Node).get_index())
	var node: Node = markers[id].node
	if node.get_index() < top: move_child(node, top)

func _set_marker_front(id: String, front: bool) -> void:
	if not markers.has(id): return
	var marker: Dictionary = markers[id]
	if marker.has("sprite"):
		marker.sprite.render_priority = 2 if front else (PLACE_PRIORITY if _over_avatar(marker.entry) else 0)
		marker.shadow.render_priority = 1 if front else -1
	if front: _raise(id)

func _animate_focus(id: String, to: float, duration: float) -> void:
	if not markers.has(id): return
	var marker: Dictionary = markers[id]
	if marker.get("focus_tween") is Tween: (marker.focus_tween as Tween).kill()
	var tween := create_tween()
	marker.focus_tween = tween
	marker.pulse = false   # the selection jelly: the whole pin, MapDestination included
	if to > 1.0: tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(v: float):
		marker.focus = v
		_apply_marker_scale(marker), float(marker.get("focus", 1.0)), to, duration)

## A tap's press on a pin that is not selected after it: a quick grow and back to its size.
const PRESS_SCALE := 1.12
func _press(id: String) -> void:
	if not markers.has(id): return
	var marker: Dictionary = markers[id]
	if marker.get("focus_tween") is Tween: (marker.focus_tween as Tween).kill()
	var tween := create_tween()
	marker.focus_tween = tween
	marker.pulse = false
	var scale_to := func(v: float):
		marker.focus = v
		_apply_marker_scale(marker)
	tween.tween_method(scale_to, float(marker.get("focus", 1.0)), PRESS_SCALE, 0.07)
	tween.tween_method(scale_to, PRESS_SCALE, 1.0, 0.14)

const KIND_ORDER := {"place": -1, "landmark": 0, "resident": 1, "pond": 2, "poi": 3}

## Sorts the candidates by _pack_key, each candidate's key made once: made in the comparison, it was made twice per
## comparison, about a thousand times a frame over a busy street (SGODOT-260). The same keys, so the same order.
func _pack_order(candidates: Array) -> void:
	for c in candidates: c["key"] = _pack_key(c)
	candidates.sort_custom(func(a, b): return a.key < b.key)

func _pack_key(c: Dictionary) -> Array:
	var sel := 0 if selected.get("id", null) == c.entry.get("id") else 1
	# MapDestinations (P0's places and ponds) pack before every other pin, by a fixed rank and then id (q(137)), so
	# every pass gives the same answer: the always-in kinds, then the host's rank (beginner pond … silhouette).
	# Within a rank the style's `order` (P0's wild sites: their distance from home, v4q(3) ⑤), then id.
	var dest := _destination(c.entry)
	if not dest.is_empty(): return [sel, 0, _dest_rank(c.entry), float(dest.get("order", 0.0)), c.id]
	# A host place (P0 outpost) goes before everything but the selected pin and a pin wearing a map marker (蒙恬 on
	# C30): the city level shows every outpost (q(72)). Journey has no place pins, so its order is unchanged.
	# Outposts among themselves: nearest home first, then id (不知火舞 on C30) — geography, so panning never reorders them.
	return [sel, 1,
		int(MARKER_ORDER.get(_marker_of(c.entry), MARKER_ORDER.size())),
		KIND_ORDER.get(c.entry.kind, 3),
		_home_distance(c.entry) if c.entry.kind == "place" else 0.0,
		0 if _shown_last.has(c.id) else 1,
		float(c.entry.get("rank", 5)),
		c.id]

## A MapDestination's packing rank (q(137) / q(146)): the always-in kinds first, where the player is (0), then the marked
## ones by their kind's rank (100 +), then the rest by it (200 +); the kind's rank is the style's (P0: 1 beginner pond …
## 7 silhouette), 1 when it gives none. The mark itself (✓ / ! / ◆) does not order them. The selected pin goes before
## all of them (_pack_key).
func _dest_rank(entry: Dictionary) -> int:
	var kind := int(_destination(entry).get("rank", 1))
	if kept_pin.is_valid() and bool(kept_pin.call(entry)): return 0
	if _marker_of(entry) != "": return 100 + kind
	return 200 + kind

## A MapDestination's name: its style's (P0's short name, q(137)) or the whole label.
func _dest_text(entry: Dictionary) -> String:
	var d := _destination(entry)
	return str(d.label) if d.has("label") else _label_text(entry)

## The centre of a MapDestination's disc as packed (its bounds: the disc, scaled when selected).
static func _disc_centre(c: Dictionary) -> Vector2:
	return (c.bounds as Rect2).get_center()

## The map marker a pin wears (q(48): "deliverable" / "request" / "new"), "" for none.
func _marker_of(entry: Dictionary) -> String:
	return str(entry.get("marker", _pin_markers.get(str(entry.get("id", "")), "")))

## Outposts and pins wearing a marker draw over the player's own 3D avatar (no depth test): both pack before everything
## but the selected pin (不知火舞 / 蒙恬 on C30). Only a marked pin, the selected one and the host's kept pin stay on an
## avatar; the rest give way to it (_place_candidate, SGODOT-269).
func _over_avatar(entry: Dictionary) -> bool:
	# A destination pin too: away from home the player's own avatar stands beside the place they are at (P0 MAP-1).
	return entry.get("kind") == "place" or _marker_of(entry) != "" or not _destination(entry).is_empty()

## A pin's sizes at the current zoom, as _update_markers lays it out: {width (its slot), art_side, top (art height
## over the anchor), label_h, label_w, art_w}.
func _pin_metrics(entry: Dictionary, is_sel := false) -> Dictionary:
	if not _destination(entry).is_empty():
		# a silhouette pin has no name: nothing of it packs under the disc
		var d := _destination(entry)
		var ls := Vector2.ZERO if bool(d.get("silhouette", false)) else UiMapDestination.label_size_for(_dest_text(entry), bool(d.get("plate", false)))
		return {width = UiMapDestination.DISC, art_side = UiMapDestination.DISC, top = UiMapDestination.DISC,
			label_h = ls.y, label_w = ls.x, art_w = UiMapDestination.DISC}
	var width := 82.0 if entry.kind == "landmark" else 78.0 if entry.kind == "resident" else 48.0
	# 选中项名牌放宽到完整名称宽度（不再省略号截断）；占位一起变宽让邻居让位。
	if is_sel: width = maxf(width, _label_width(entry))
	# 视野最大（低 zoom）时 POI 也要有存在感：下限 42px（≈原 32 的 1.3 倍）。
	var art_side: float = 88 if entry.kind == "landmark" else lerpf(42, 64, clampf((host.zoom - 13) / 3, 0, 1))
	var art_key := CityMapData.art_key(entry)
	var top := 40.0 if entry.kind == "resident" else 54.0 if art_key in ["hollywood_sign", "griffith_observatory", "santa_monica_pier"] else 80.0 if entry.kind == "landmark" else 56.0
	if entry.kind == "poi": top = maxf(36, art_side * 0.94)
	var label_h := _label_height(entry, width) if is_sel and not _whole_label(entry) else 16.0
	# An outpost's label and a marked pin's are never cut: the whole text on one line (不知火舞 on C30, q(72)).
	var label_w := _whole_label_width(entry) if _whole_label(entry) else width
	return {width = width, art_side = art_side, top = top, label_h = label_h, label_w = label_w,
		art_w = 36.0 if entry.kind == "resident" else art_side}

## What a pin covers around its anchor at the current zoom, unselected: its art over the anchor and its label under
## it (a host frames a view by it, P0 MAP-1).
func pin_footprint(entry: Dictionary) -> Rect2:
	var pm := _pin_metrics(entry)
	var side := maxf(float(pm.width), float(pm.art_side))
	return Rect2(-side * 0.5, -float(pm.top), side, float(pm.top)).merge(
		Rect2(-float(pm.label_w) * 0.5, 3.0, float(pm.label_w), float(pm.label_h)))

## How far a place is from home (degrees, the latitude scaled to the longitude's length): only ever compared.
func _home_distance(entry: Dictionary) -> float:
	var lat := float(host.get("home_lat")) if host.get("home_lat") != null else 0.0
	var lng := float(host.get("home_lng")) if host.get("home_lng") != null else 0.0
	return Vector2((float(entry.lat) - lat) / maxf(0.01, cos(deg_to_rad(lat))), float(entry.lng) - lng).length()

static func _hits_point(rects: Array, point: Vector2) -> bool:
	for r in rects:
		if (r as Rect2).has_point(point): return true
	return false

static func _hits(rects: Array, rect: Rect2) -> bool:
	for r in rects:
		if (r as Rect2).intersects(rect): return true
	return false

## Screen footprints of the player and other players, in this view's space.
## My Farm's label gives way to an outpost or marked-pin label it would touch: at the city level the avatar itself
## says where home is (不知火舞 on C30 / #83).
func _yield_own_label() -> void:
	var fm = host.get("farm_markers")
	if fm == null or not fm.has_method("yield_self_label"): return
	var own: Rect2 = fm.self_label_rect()
	own.position += fm.global_position - global_position
	fm.yield_self_label(own.has_area() and _hits(_place_labels, own))

func _player_blockers(body_only := false) -> Array:
	var result: Array = []
	var fm = host.get("farm_markers")
	if fm == null or not fm.has_method("blocker_rects"): return result
	for r in fm.blocker_rects(body_only):
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

## A tap on a shown host place (P0 outpost) pin selects it before anything drawn with it (the player's own avatar,
## 蒙恬 on C30); false when the tap is not on one.
func activate_place_at(screen: Vector2) -> bool:
	if not host.city_detail_visible(): return false
	var local := screen - global_position
	for marker in displayed:
		if marker.entry.kind == "place" and _hits_point(marker.get("hit", [marker.rect]), local):
			select(marker.entry)
			return true
	return false

## A tap on a city bubble (the region and country views) opens that city before anything drawn under it: the bubbles
## draw over the players' avatars, so a visited city right by home (Chico) takes the tap, not the avatar (李元芳 0.2.1
## smoke, 286 bfae88c7); false when the tap is not on one or the street view is up. The bubble drawn on top under the
## finger takes it; with `slop`, a tap just off every bubble goes to the topmost one whose 6 px margin holds it, so the
## margin never reaches over a neighbour that is drawn there (home's bubble over Chico's at the country view, 293
## 378fd255).
func activate_bubble_at(screen: Vector2, slop := false) -> bool:
	if host.city_detail_visible(): return false
	var local := screen - global_position
	var shown: Array = []
	for id in bubbles:
		var node: Control = bubbles[id].node
		if node.visible: shown.append({"id": str(id), "rect": Rect2(node.position, node.size), "z": node.get_index()})
		# a city's dot opens it as its bubble does (q(153) ①); a dot is drawn under every bubble
		var dot: Control = bubbles[id].dot
		if dot.visible: shown.append({"id": str(id), "rect": Rect2(dot.position, dot.size).grow(4), "z": dot.get_index()})
	shown.sort_custom(func(a, b): return a.z > b.z)   # drawn last first
	for grow in ([0.0, 6.0] if slop else [0.0]):
		for b in shown:
			if (b.rect as Rect2).grow(grow).has_point(local):
				city_requested.emit(b.id)
				return true
	return false

func activate_at(screen: Vector2) -> bool:
	var local := screen - global_position
	if not host.city_detail_visible(): return activate_bubble_at(screen, true)   # after the avatar (map_poc)
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
	if info_settled.is_valid() and info.visible and not selected.is_empty(): info_settled.call(selected)

## (entry) after the info card has its height: P0 moves a landmark's pin above it (q(295)).
var info_settled := Callable()

## Where a selected pin's name ends, in this view's pixels, once its jelly has grown it (FOCUS_SCALE); NAN without a
## shown name.
func selected_name_bottom(id: String) -> float:
	var m: Dictionary = markers.get(id, {})
	if m.is_empty() or not (m.get("label") is Label) or not (m.label as Label).visible: return NAN
	var l: Label = m.label
	return (m.node as Control).global_position.y + (l.position.y + l.size.y) * FOCUS_SCALE

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

func _update_fog() -> void:
	if fog == null: return
	if fog.get_index() != 0: move_child(fog, 0)   # under the bubbles and pins added at 0 since
	var on := fog_holes.is_valid()
	# The view sits inside the HUD's safe-area margins; the veil spans the whole screen, edge to edge, so it is placed
	# at the screen origin and the holes (this view's px) are shifted by the same offset.
	var at := -global_position
	if fog.position != at or fog.size != get_viewport_rect().size:
		fog.set_anchors_preset(Control.PRESET_TOP_LEFT)
		fog.position = at
		fog.size = get_viewport_rect().size
	fog.apply(fog_holes.call() if on else [], float(host.zoom) + float(host._zoom_elastic), on, -at)

func _update_bubbles() -> void:
	var detail: bool = host.city_detail_visible()
	var area := Rect2(-global_position, get_viewport_rect().size).grow(60)
	var clear_rects: Array = bubble_clear_rects.call() if bubble_clear_rects.is_valid() else []   # once a frame (蒙恬 on #281)
	var listed := {}
	var order: Array = []   # the host's priority, highest first
	var states := {}
	for r in host.city_regions():
		var id := str(r.id)
		listed[id] = true
		order.append(id)
		if not bubbles.has(id): bubbles[id] = _make_bubble(id)
		var bubble: Dictionary = bubbles[id]
		var overview: Dictionary = CityMapData.city(id).get("overview", {})
		var projected = host.geo_to_screen(float(overview.get("lat", r.center[0])), float(overview.get("lng", r.center[1])))
		var point: Vector2 = (projected as Vector2) - global_position if projected != null else Vector2(-1e6, -1e6)
		bubble.geo = Vector2(float(overview.get("lat", r.center[0])), float(overview.get("lng", r.center[1])))   # a ghost's point (h1)
		var node: Control = bubble.node
		node.visible = not detail and area.has_point(point)
		bubble.dot.visible = false
		if not node.visible: continue
		var st := _fill_bubble(bubble, id, r)
		if bubble_state.is_valid(): states[id] = st
		# 气泡挂在城市点下方，自己的头像站在点上方，两者在同一城市也不互相遮挡。
		node.position = point + Vector2(-node.size.x * 0.5, BUBBLE_DROP)
		bubble.dot.position = point - Vector2(5, 5)
		bubble.dot.visible = true
		if bubble_clear_rects.is_valid():
			var at := Rect2(node.position + global_position, node.size)   # screen px
			var screen := Rect2(Vector2.ZERO, get_viewport_rect().size)
			if not screen.encloses(at) or clear_rects.any(func(r): return (r as Rect2).intersects(at)):
				node.visible = false   # the dot stays: the city is still there
	# A bubble built for an earlier list (another zoom, another camera city) that this one no longer has hides with its
	# dot; left visible it would stay frozen where it was drawn, over the new city (李元芳 / 司空震, SGODOT-275).
	for id in bubbles:
		if not listed.has(id):
			bubbles[id].node.visible = false
			bubbles[id].dot.visible = false
		elif not bubbles[id].node.visible and not bubble_clear_rects.is_valid(): bubbles[id].dot.visible = false   # Journey: as before
	if not states.is_empty(): _yield_bubbles(order, states)
	_pop_bubbles()

## How far under its city's point a bubble hangs, px.
const BUBBLE_DROP := 6.0

## How long a pin or a city bubble takes to come (TRANS_BACK, out of its point) and to go (TRANS_QUAD, into it): the POI
## art's beat (7dbe7eb), every pin's and bubble's since h1 (the user on 10-13 via 奕星; 不知火舞 on 279). A name or a
## mark comes with its pin, scaled with it, and goes at once (as a POI's label); only the disc or the bubble shrinks.
const POP_IN_S := 0.22
const POP_OUT_S := 0.12

## What is going: {node, lat, lng, offset, tween} — a stand-in shrinking into its point, kept on it as the map moves
## (_move_ghosts), then freed. The pin or bubble itself hides at once, so its taps and the layout never see it go.
var _ghosts: Array = []

## Where region `r`'s bubble stands, reading as it would now (q(157): the flight frames both ends' bubbles whole): its
## city's point [lat, lng] and the bubble's rect from that point, px.
func bubble_extent(r: Dictionary) -> Array:
	var id := str(r.id)
	if not bubbles.has(id):
		bubbles[id] = _make_bubble(id)
		bubbles[id].node.visible = false
		bubbles[id].dot.visible = false
	var node: Control = bubbles[id].node
	_fill_bubble(bubbles[id], id, r)
	var overview: Dictionary = CityMapData.city(id).get("overview", {})
	var at := Vector2(float(overview.get("lat", r.center[0])), float(overview.get("lng", r.center[1])))
	return [at, Rect2(Vector2(-node.size.x * 0.5, BUBBLE_DROP), node.size)]

## A bubble's words for region `r` — its name and the host's line (bubble_state; Journey: its farms) — and its size; the
## host's state ({} without one).
func _fill_bubble(bubble: Dictionary, id: String, r: Dictionary) -> Dictionary:
	var node: Control = bubble.node
	var st := {}
	bubble.name.text = L10n.text(str(r.get("name", id)))
	if bubble_state.is_valid():
		st = bubble_state.call(id)
		bubble.count.text = str(st.get("text", ""))
		bubble.count.visible = bubble.count.text != ""
		# The line keeps a text line's height with the glyph alone (P0's home city at 0 online), so the bubble's
		# bottom does not move as the count comes and goes (不知火舞 on #238). Measured here, in the tree, with the
		# label's own theme font.
		var line := bubble.count.get_parent() as Control
		var text_h: float = bubble.count.get_theme_font("font").get_height(bubble.count.get_theme_font_size("font_size"))
		if line.custom_minimum_size.y != text_h: line.custom_minimum_size.y = text_h
		var glyph := str(st.get("icon", ""))
		bubble.icon.visible = glyph != ""
		if glyph != "": bubble.icon.texture = GameUi.icon(glyph)
		var box := node.get_theme_stylebox("panel") as StyleBoxFlat
		if box != null:
			box.border_color = Color("609f28")
			box.set_border_width_all(2 if bool(st.get("outline", false)) else 0)
	else:
		var count := int(host.city_farm_counts.get(id, -1))
		bubble.count.text = L10n.count_text("%d farm", "%d farms", count) if count >= 0 else ""
		bubble.count.visible = count >= 0
	node.size = node.get_combined_minimum_size()
	return st

## q(153) (不知火舞 on 293 8f407417 / e5ec0cc0), the host's bubbles in its priority order (highest first): a bubble that
## runs into a higher city's bubble or dot hides whole, its dot staying for the cities that keep theirs (`dot_stays`:
## visited and up); one that `keeps` (the city just opened, where the player is, home) never hides. Hidden last pass, a
## bubble comes back only 4 px clear of them, so it does not flicker on the line. Then they stack by priority, the
## highest on top, every dot under every bubble (a lower city's dot under a higher bubble never cuts its words).
const BUBBLE_HOLD := 4.0
var _bubbles_last := {}

func _yield_bubbles(order: Array, states: Dictionary) -> void:
	var taken: Array = []
	var shown_now := {}
	for id in order:
		var b: Dictionary = bubbles[id]
		var st: Dictionary = states.get(id, {})
		var node: Control = b.node
		if node.visible and not bool(st.get("keeps", false)):
			var r := Rect2(node.position, node.size)
			var probe := r if _bubbles_last.has(id) else r.grow(BUBBLE_HOLD)
			if taken.any(func(t): return (t as Rect2).intersects(probe)):
				node.visible = false
				if not bool(st.get("dot_stays", false)): b.dot.visible = false   # the rest give way whole
		if node.visible:
			taken.append(Rect2(node.position, node.size))
			shown_now[id] = true
		if b.dot.visible: taken.append(Rect2(b.dot.position, b.dot.size))
	_bubbles_last = shown_now
	_stack_bubbles(order)

func _stack_bubbles(order: Array) -> void:
	var nodes: Array = []
	for id in order: nodes.append(bubbles[id].dot)
	for i in range(order.size() - 1, -1, -1): nodes.append(bubbles[order[i]].node)
	var at: Array = nodes.map(func(n): return (n as Node).get_index())
	var ordered := true
	for k in range(1, at.size()):
		if int(at[k]) <= int(at[k - 1]):
			ordered = false
			break
	if ordered: return
	var base: int = at.min()
	for k in nodes.size(): move_child(nodes[k], base + k)

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
	var line := HBoxContainer.new()   # a host's glyph before the line (P0: the home city's house)
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph := GameUi.picture(GameUi.icon("house"), 10)
	glyph.visible = false
	line.add_child(glyph)
	line.add_child(count_label)
	column.add_child(line)
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
	return {"node": node, "name": name_label, "count": count_label, "icon": glyph, "dot": dot}

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
