class_name NearbyPanel
extends PanelContainer
## Nearby Farmers（PRD §3.3）：横向卡片 → 选中一个 → 底部静态快照预览 → Visit Farm。
##
## 同时只能选中一张卡、只开一张预览。预览绑 farm_id，不绑任何经纬度——面板在地图 UI 里，
## 不贴合、不连线到现实地块。
##
## 走 BottomSheet，不碰顶栏与侧栏：TopPanel 被测试钉在 ≤220×64。界面文案一律英文。

signal farm_focused(farm_id: String)
signal visit_requested(farm_id: String)
signal place_requested(place_id: String)

const CARD_MIN := Vector2(124, 52)
const PREVIEW_H := 64.0
const STAGE_LABEL := {"derelict": "Wild plot", "cleared": "Cleared plot", "built": "Nursery"}
const WEATHER_LABEL := {"sunny": "Sunny", "rain": "Rain", "wind": "Wind"}

var focused_id := ""
var entries: Array = []

var _title: Label
var _subtitle: Label
var _row: HBoxContainer
var _cards: Array[Button] = []
var _group := ButtonGroup.new()
var _preview: PanelContainer
var _preview_img: TextureRect
var _preview_text: Label
var _preview_name: Label
var _card_images := {}
var _group_ids: Array = []
var _group_back: Button
var _count := 0
var _scroll: ScrollContainer
var visit_button: Button
var _places: VBoxContainer
var _farm_content: VBoxContainer
var _place_buttons: Dictionary = {}
var _place_tab: Button
var _farm_tab: Button
var places_open := false

func _init() -> void:
	name = "NearbyPanel"
	theme_type_variation = &"BottomSheet"
	minimum_size_changed.connect(_apply_bottom_preset)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	add_child(vbox)
	var tabs := HBoxContainer.new()
	vbox.add_child(tabs)
	_farm_tab = GameUi.button("users-round", "Farmers", "Nearby farmers")
	_place_tab = GameUi.button("map-pin", "Places", "Neighbourhood places")
	for tab in [_farm_tab, _place_tab]:
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
	_farm_tab.pressed.connect(func(): show_places(false))
	_place_tab.pressed.connect(func(): show_places(true))
	_farm_content = VBoxContainer.new()
	vbox.add_child(_farm_content)
	_places = VBoxContainer.new()
	vbox.add_child(_places)
	for place in PlaceCatalog.all():
		var button := GameUi.button(str(place.icon), str(place.name), str(place.name))
		button.pressed.connect(func(): place_requested.emit(str(place.id)))
		_place_buttons[str(place.id)] = button
		_places.add_child(button)
	show_places(false)
	_title = Label.new()
	_title.text = "Nearby Farmers"
	_title.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	var heading := HBoxContainer.new()
	_farm_content.add_child(heading)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_title)
	_group_back = GameUi.button("x", "", "Show all nearby farms")
	_group_back.custom_minimum_size = Vector2(32, 32)
	_group_back.visible = false
	_group_back.pressed.connect(func(): show_group([]))
	heading.add_child(_group_back)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_subtitle.visible = false
	_farm_content.add_child(_subtitle)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = CARD_MIN.y + 4.0
	_farm_content.add_child(scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	scroll.add_child(_row)
	_build_preview(_farm_content)
	_apply_bottom_preset()

func show_places(open: bool) -> void:
	places_open = open
	_places.visible = open
	_farm_content.visible = not open
	_farm_tab.theme_type_variation = &"TabButton" if open else &"TabSelectedButton"
	_place_tab.theme_type_variation = &"TabSelectedButton" if open else &"TabButton"
	_apply_bottom_preset()

func set_place_state(state: Dictionary) -> void:
	for place in PlaceCatalog.all():
		var button: Button = _place_buttons[str(place.id)]
		button.disabled = not PlaceCatalog.available(str(place.id), state)
		button.text = str(place.name) if not button.disabled else "%s · Ch. %d" % [place.name, int(place.chapter) + 1]
		button.tooltip_text = "Connect to load your chapter" if state.is_empty() else str(place.intro)

func _build_preview(parent: Node) -> void:
	_preview = PanelContainer.new()
	_preview.name = "Preview"
	_preview.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_preview.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	_preview.add_child(h)
	_preview_img = TextureRect.new()
	_preview_img.custom_minimum_size = Vector2(PREVIEW_H, PREVIEW_H)
	# 忽略纹理原始尺寸：512×512 的 preview.png 曾把 G0 的卡片撑到整屏。
	_preview_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(_preview_img)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	_preview_name = GameUi.label("", 15)
	_preview_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_preview_name)
	_preview_text = Label.new()
	# **不要 autowrap**：首帧容器宽度还是 1 px 时，autowrap 标签会按每字一行算最小高度
	# （26 个字 ≈ 470 px），面板被一次性撑到 668 高，之后也不会自动缩回。单行 + 省略号。
	_preview_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_preview_text.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_preview_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_preview_text)
	visit_button = Button.new()
	visit_button.text = "Visit Farm"
	visit_button.icon = GameUi.icon("house")
	visit_button.theme_type_variation = &"AccentButton"
	visit_button.custom_minimum_size.y = 44.0
	visit_button.pressed.connect(func(): if not focused_id.is_empty(): visit_requested.emit(focused_id))
	h.add_child(visit_button)
	visit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	visit_button.text = "Visit"
	parent.add_child(_preview)

## 与 SelectPanel 同一个坑：PRESET_MODE_MINSIZE 按调用时刻的最小尺寸算 offset_top，
## 子节点变了必须重算，否则面板长到父容器底边以下。
func _apply_bottom_preset() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)

## `count` 是同城开放访问的总人数（人数簇）；`offline` 为真时说明条目来自随包样例。
func set_entries(p_entries: Array, count: int, offline := false) -> void:
	for c in _cards:
		_row.remove_child(c)
		c.queue_free()
	_cards.clear()
	_card_images.clear()
	entries = p_entries
	_count = count
	_group_ids.clear()
	_group_back.visible = false
	focused_id = ""
	_preview.visible = false
	_title.text = "Nearby Farmers · %d" % count
	_subtitle.visible = offline or p_entries.is_empty()
	_subtitle.text = "Offline · sample farms" if offline else ("No open farms nearby yet" if p_entries.is_empty() else "")
	for e in p_entries:
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = _group
		card.custom_minimum_size = CARD_MIN
		card.theme_type_variation = &"ChoiceButton"
		card.set_meta("farm_id", str(e.farm_id))
		card.pressed.connect(_on_card_pressed.bind(card))
		_build_card(card, e)
		_row.add_child(card)
		_cards.append(card)
	_apply_bottom_preset()

func _build_card(card: Button, e: Dictionary) -> void:
	var ref := str(e.get("avatar_ref", "seed:unknown"))
	var v := HBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	var thumbnail := TextureRect.new()
	thumbnail.name = "FarmThumbnail"
	thumbnail.custom_minimum_size = Vector2(34, 34)
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(thumbnail)
	_card_images[str(e.farm_id)] = thumbnail
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(col)
	var name_l := Label.new()
	name_l.text = SeededOutfit.short_name(ref)
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.add_theme_font_size_override("font_size", 12)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_l)
	var stage_l := Label.new()
	stage_l.text = str(STAGE_LABEL.get(str(e.get("nursery_stage", "derelict")), "Plot"))
	stage_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stage_l.add_theme_font_size_override("font_size", 11)
	stage_l.add_theme_color_override("font_color", GameUi.MUTED)
	stage_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stage_l)

func _on_card_pressed(card: Button) -> void:
	focus(str(card.get_meta("farm_id")))

func clear_focus() -> void:
	focused_id = ""
	_preview.visible = false
	for c in _cards:
		c.set_pressed_no_signal(false)
		if c.has_focus(): c.release_focus()
		c.theme_type_variation = &"ChoiceButton"
	_apply_bottom_preset()

func focus(farm_id: String) -> void:
	if not entries.any(func(e): return str(e.farm_id) == farm_id):
		return
	if not _group_ids.is_empty() and not _group_ids.has(farm_id):
		show_group([])
	if focused_id == farm_id:
		return
	focused_id = farm_id
	for c in _cards:
		var selected := str(c.get_meta("farm_id")) == farm_id
		c.set_pressed_no_signal(selected)
		c.theme_type_variation = &"ChoiceSelectedButton" if selected else &"ChoiceButton"
	_preview.visible = true
	_preview_img.texture = null
	_preview_text.text = "Finding farm..."
	for e in entries:
		if str(e.farm_id) == farm_id:
			_preview_name.text = SeededOutfit.short_name(str(e.get("avatar_ref", "seed:unknown")))
	visit_button.disabled = true
	_apply_bottom_preset()
	farm_focused.emit(farm_id)

## 静态预览：蓝图缩略图 + 一行作物摘要。快照是冻结的，不跟主人的时间走。
func set_preview(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or str(snapshot.get("farm_id", "")) != focused_id:
		return
	var png := FarmBlueprint.asset_path(str(snapshot.layout_patch_id), int(snapshot.blueprint_revision)).get_base_dir() + "/preview.png"
	_preview_img.texture = load(png) if ResourceLoader.exists(png) else null
	set_thumbnail(snapshot)
	var counts := crop_counts(snapshot)
	_preview_text.text = "%d growing · %d ripe" % [counts.x, counts.y]
	_preview.visible = true
	visit_button.disabled = false
	_apply_bottom_preset()

func set_thumbnail(snapshot: Dictionary) -> void:
	var id := str(snapshot.get("farm_id", ""))
	if not _card_images.has(id): return
	var path := FarmBlueprint.asset_path(str(snapshot.get("layout_patch_id", "")), int(snapshot.get("blueprint_revision", 2))).get_base_dir() + "/preview.png"
	(_card_images[id] as TextureRect).texture = load(path) if ResourceLoader.exists(path) else null

func show_group(ids: Array) -> void:
	_group_ids = ids
	_group_back.visible = not ids.is_empty()
	_title.text = "%d farms here" % ids.size() if not ids.is_empty() else "Nearby Farmers · %d" % _count
	for card in _cards:
		card.visible = ids.is_empty() or ids.has(str(card.get_meta("farm_id")))
	_scroll.scroll_horizontal = 0
	_apply_bottom_preset()

## 预览拿不到（线上失败且没有随包）：卡还在，但说清楚。
func set_preview_unavailable() -> void:
	_preview_img.texture = null
	_preview_text.text = "Farm unavailable right now"
	_preview.visible = true
	visit_button.disabled = true
	_apply_bottom_preset()

static func summary(snapshot: Dictionary) -> String:
	var counts := crop_counts(snapshot)
	var parts := ["%d growing" % counts.x, "%d ripe" % counts.y,
		str(WEATHER_LABEL.get(str(snapshot.get("weather_snapshot", "")), "—"))]
	return " · ".join(parts)

static func crop_counts(snapshot: Dictionary) -> Vector2i:
	var growing := 0
	var ripe := 0
	for c in snapshot.get("cells", []):
		if bool(c.get("ripe", false)):
			ripe += 1
		elif str(c.get("state", "")) == "growing" or str(c.get("state", "")) == "sown":
			growing += 1
	return Vector2i(growing, ripe)

func cards() -> Array[Button]:
	return _cards

func card_count() -> int:
	return _cards.size()
