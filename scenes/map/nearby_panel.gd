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

const CARD_MIN := Vector2(76, 86)   # 三行内容（色块 + 名字 + 苗圃阶段）72 高会裁掉最后一行
const PREVIEW_H := 72.0
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
var visit_button: Button

func _init() -> void:
	name = "NearbyPanel"
	theme_type_variation = &"BottomSheet"
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	add_child(vbox)
	_title = Label.new()
	_title.text = "Nearby Farmers"
	_title.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	vbox.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_subtitle.visible = false
	vbox.add_child(_subtitle)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = CARD_MIN.y + 4.0
	vbox.add_child(scroll)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	scroll.add_child(_row)
	_build_preview(vbox)
	_apply_bottom_preset()

func _build_preview(parent: Node) -> void:
	_preview = PanelContainer.new()
	_preview.name = "Preview"
	_preview.theme_type_variation = &"ChipPanel"
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
	_preview_text = Label.new()
	# **不要 autowrap**：首帧容器宽度还是 1 px 时，autowrap 标签会按每字一行算最小高度
	# （26 个字 ≈ 470 px），面板被一次性撑到 668 高，之后也不会自动缩回。单行 + 省略号。
	_preview_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_preview_text.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	_preview_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_preview_text)
	visit_button = Button.new()
	visit_button.text = "Visit Farm"
	visit_button.theme_type_variation = &"AccentButton"
	visit_button.custom_minimum_size.y = 44.0
	visit_button.pressed.connect(func(): if not focused_id.is_empty(): visit_requested.emit(focused_id))
	col.add_child(visit_button)
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
	entries = p_entries
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
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	var badge := ColorRect.new()
	badge.color = SeededOutfit.badge_color(ref)
	badge.custom_minimum_size = Vector2(28, 28)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(badge)
	var name_l := Label.new()
	name_l.text = SeededOutfit.short_name(ref)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", DesignTokens.FONT_MICRO)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var stage_l := Label.new()
	stage_l.text = str(STAGE_LABEL.get(str(e.get("nursery_stage", "derelict")), "Plot"))
	stage_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_l.add_theme_font_size_override("font_size", DesignTokens.FONT_MICRO)
	stage_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stage_l)

func _on_card_pressed(card: Button) -> void:
	focus(str(card.get_meta("farm_id")))

func focus(farm_id: String) -> void:
	if focused_id == farm_id:
		return
	focused_id = farm_id
	for c in _cards:
		c.set_pressed_no_signal(str(c.get_meta("farm_id")) == farm_id)
	_preview.visible = false
	farm_focused.emit(farm_id)

## 静态预览：蓝图缩略图 + 一行作物摘要。快照是冻结的，不跟主人的时间走。
func set_preview(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or str(snapshot.get("farm_id", "")) != focused_id:
		return
	var png := FarmBlueprint.asset_path(str(snapshot.layout_patch_id), int(snapshot.blueprint_revision)).get_base_dir() + "/preview.png"
	_preview_img.texture = load(png) if ResourceLoader.exists(png) else null
	_preview_text.text = summary(snapshot)
	_preview.visible = true
	visit_button.disabled = false
	_apply_bottom_preset()

## 预览拿不到（线上失败且没有随包）：卡还在，但说清楚。
func set_preview_unavailable() -> void:
	_preview_img.texture = null
	_preview_text.text = "Farm unavailable right now"
	_preview.visible = true
	visit_button.disabled = true
	_apply_bottom_preset()

static func summary(snapshot: Dictionary) -> String:
	var growing := 0
	var ripe := 0
	for c in snapshot.get("cells", []):
		if bool(c.get("ripe", false)):
			ripe += 1
		elif str(c.get("state", "")) == "growing" or str(c.get("state", "")) == "sown":
			growing += 1
	var parts := ["%d growing" % growing, "%d ripe" % ripe,
		str(WEATHER_LABEL.get(str(snapshot.get("weather_snapshot", "")), "—"))]
	return " · ".join(parts)

func cards() -> Array[Button]:
	return _cards

func card_count() -> int:
	return _cards.size()
