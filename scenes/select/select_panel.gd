class_name SelectPanel
extends PanelContainer
## Two-step farm setup: choose a blueprint, then confirm its position on the map.

signal candidate_focused(id: String)
signal confirmed(id: String)
signal placement_cancelled

## 渐进解锁已退役：地是一整片，开局就能随处开垦，没有「几块田」这回事了。
const CAPACITY_TEXT := "Open ground · till anywhere"
## Three cards fit inside the 328px safe-area width of a 360px phone.
## Shared capacity copy stays below the row, leaving the map visible.
const CARD_MIN := Vector2(88, 104)
## 预览缩略图固定高度：卡片内容区（CARD_MIN 减去内边距）分给预览的那一份。
## 预览 TextureRect 必须 EXPAND_IGNORE_SIZE（见 _build_card_content），否则这个值形同虚设。
const CARD_PREVIEW_H := 44.0
## 名字 / 容量文案的行数上限：CARD_MIN.y 的预算就是按这两个数算的，改一处必须改另一处。
const NAME_MAX_LINES := 2
const CAPACITY_MAX_LINES := 3

var focused_id := ""
var confirm_button: Button
var _cards: Array[Button] = []
var _row: HBoxContainer
var _group := ButtonGroup.new()
var _title: Label
var _capacity: Label
var _cancel: Button
var placing := false
var generation_mode := false
var relocation_mode := false

func _init() -> void:
	name = "SelectPanel"
	add_theme_stylebox_override("panel", GameUi.panel_style(14))
	minimum_size_changed.connect(_apply_bottom_preset)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_3)
	add_child(vbox)
	var title := Label.new()
	_title = title
	title.text = "Choose a farm layout"
	title.add_theme_font_size_override("font_size", 17)
	vbox.add_child(title)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	vbox.add_child(_row)
	_capacity = GameUi.label(CAPACITY_TEXT, 13, GameUi.MUTED)
	vbox.add_child(_capacity)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 9)
	vbox.add_child(actions)
	_cancel = GameUi.button("arrow-left", "", "Change layout")
	_cancel.visible = false
	_cancel.pressed.connect(func(): placement_cancelled.emit())
	actions.add_child(_cancel)
	confirm_button = Button.new()
	confirm_button.text = "Place Farm"
	confirm_button.icon = GameUi.icon("map-pin")
	confirm_button.theme_type_variation = &"AccentButton"
	confirm_button.custom_minimum_size.y = 50
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_button.disabled = true
	confirm_button.pressed.connect(func(): if not focused_id.is_empty(): confirmed.emit(focused_id))
	actions.add_child(confirm_button)
	# 必须放在所有子节点加完之后：PRESET_MODE_MINSIZE（默认档）按调用时刻的
	# get_combined_minimum_size() 算 offset_top，子节点还没挂上去时那是 0，
	# 面板会整个长在父容器底边以下（C2，2026-09-04 终审）。真正的高度大头
	# 是候选卡（在 set_candidates() 里动态加），所以那边也要在加完卡片后重算一次。
	_apply_bottom_preset()

func _apply_bottom_preset() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 4
	offset_right = -4
	offset_bottom = -4
	offset_top = -get_combined_minimum_size().y - 4

func set_candidates(items: Array) -> void:
	# 必须先 remove_child 立即解除父子关系，再 queue_free 释放。queue_free 同帧内不解除父子关系。
	for c in _cards:
		_row.remove_child(c)
		c.queue_free()
	_cards.clear()
	focused_id = ""
	confirm_button.disabled = true
	for item in items:
		var card := Button.new()
		card.toggle_mode = true
		card.theme_type_variation = &"ChoiceButton"
		card.button_group = _group
		card.custom_minimum_size = CARD_MIN
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.set_meta("id", item.id)
		card.pressed.connect(_on_card_pressed.bind(card))
		_build_card_content(card, item)
		_row.add_child(card)
		_cards.append(card)
	# 候选卡是面板真正的高度大头（CARD_MIN.y 远大于标题/按钮），必须在它们
	# 都挂好之后重算一次 offset_top，否则仍然按 _init() 时刻（还没有卡片）的
	# 尺寸定住，卡片撑高的部分照样会长到父容器底边以下（C2，2026-09-04 终审）。
	_apply_bottom_preset()

## Button 不是 Container，子节点不会自动跟着按钮尺寸走，必须手动铺满
## （PRESET_FULL_RECT）再留一圈内边距，否则内容会贴着卡片圆角边框。
## 所有子节点 MOUSE_FILTER_IGNORE：点击要落在 Button 本体上才能触发
## toggle/ButtonGroup，被内容节点吞掉的话卡片就点不亮了。
func _build_card_content(card: Button, item: Dictionary) -> void:
	var content := VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", DesignTokens.SPACE_1)
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = DesignTokens.SPACE_2
	content.offset_top = DesignTokens.SPACE_2
	content.offset_right = -DesignTokens.SPACE_2
	content.offset_bottom = -DesignTokens.SPACE_2
	card.add_child(content)

	# D2：预览图独立成 TextureRect，不再经过 Button 的 icon_normal_color 乘色。
	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.texture = item.get("preview")
	# D3（2026-09-04 真机）：TextureRect 默认 expand_mode=EXPAND_KEEP_SIZE，最小尺寸就是
	# 纹理原始尺寸——preview.png 是 512×512，custom_minimum_size 的 64 只是下限、顶不住 512，
	# 预览撑到整屏高、把两行文案顶出屏幕、盖住「Create Farm」。IGNORE_SIZE 之后最小尺寸
	# 才真正由 custom_minimum_size 决定，KEEP_ASPECT_COVERED + clip 负责把方图裁成横条。
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(0, CARD_PREVIEW_H)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.clip_contents = true
	content.add_child(preview)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = str(item.name)
	name_label.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = NAME_MAX_LINES # 候选名字长度不受我们控制，超出部分不画
	content.add_child(name_label)

	# D1：容量文案挪到独立 Label，AUTOWRAP_WORD_SMART 折行——CJK 没有空格，
	# 普通 WORD 折行遇到一个装不下的整词会整段不折，SMART 会在词内断开兜底。
	var capacity := Label.new()
	capacity.name = "CapacityLabel"
	capacity.visible = false
	capacity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capacity.text = CAPACITY_TEXT
	capacity.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	capacity.add_theme_color_override("font_color", DesignTokens.INK_SUB)
	capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capacity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	capacity.max_lines_visible = CAPACITY_MAX_LINES
	content.add_child(capacity)

## 卡片内承载容量文案的节点——测试断言"三卡容量文案一致"要读它，而不是已经
## 清空的 Button.text（回归测试：谁把文案搬回 Button.text，这条先炸）。
func capacity_label(card: Button) -> Label:
	return card.get_node_or_null("Content/CapacityLabel") as Label

## 卡片内承载名字的节点——name_label 也开了自动折行（候选名字长度不受我们控制）。
func name_label(card: Button) -> Label:
	return card.get_node_or_null("Content/NameLabel") as Label

## 卡片内承载预览图的节点——测试断言"预览不是被主题染色的 Button.icon"要读它。
func preview_node(card: Button) -> TextureRect:
	return card.get_node_or_null("Content/Preview") as TextureRect

func _on_card_pressed(card: Button) -> void:
	focused_id = str(card.get_meta("id"))
	card.button_pressed = true
	for c in _cards:
		c.theme_type_variation = &"ChoiceSelectedButton" if c == card else &"ChoiceButton"
	confirm_button.disabled = false
	candidate_focused.emit(focused_id)

func focus(id: String) -> void:
	for card in _cards:
		if str(card.get_meta("id")) == id:
			_on_card_pressed(card)
			return

func cards() -> Array[Button]:
	return _cards

func set_placement_mode(active: bool, valid := true) -> void:
	placing = active
	_row.visible = not active
	_cancel.visible = active
	_title.text = "Place your farm" if active else "Choose a farm layout"
	_capacity.text = CAPACITY_TEXT if valid else "Outside the farm area"
	_capacity.add_theme_color_override("font_color", GameUi.MUTED if valid else GameUi.CORAL)
	confirm_button.text = "Create Farm" if active else "Place Farm"
	confirm_button.icon = GameUi.icon("house" if active else "map-pin")
	confirm_button.disabled = not valid or focused_id.is_empty()
	if generation_mode:
		_row.hide()
		_cancel.show()
		_cancel.tooltip_text = L10n.text("Change city")
		_title.text = "Choose your farm location"
		_capacity.text = "Move the map to choose an area. Your private farm includes a pond and a mine." if valid else "Choose an area inside this city"
		_capacity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		confirm_button.text = "Generate farm here"
	if relocation_mode:
		_cancel.tooltip_text = L10n.text("Keep current farm")
		_title.text = "Choose a new farm location"
		_capacity.text = "Move the map within your current city. Preview first; your current farm stays unchanged until you confirm." if valid else "Choose an area inside this city"
		confirm_button.text = "Preview this location"
	_apply_bottom_preset()

func set_relocation_mode() -> void:
	relocation_mode = true
	set_generation_mode()

func set_generation_mode() -> void:
	generation_mode = true
	focused_id = "map_selection"
	set_placement_mode(true)

func set_saving(active: bool, error := "") -> void:
	confirm_button.disabled = active
	_cancel.disabled = active
	confirm_button.text = "Saving..." if active else "Create Farm"
	if generation_mode: confirm_button.text = "Checking land and generating…" if active else "Generate farm here"
	if relocation_mode: confirm_button.text = "Checking land and generating…" if active else "Preview this location"
	if not error.is_empty():
		_capacity.text = error
		_capacity.add_theme_color_override("font_color", GameUi.CORAL)
	_apply_bottom_preset()

func card_count() -> int:
	return _cards.size()
