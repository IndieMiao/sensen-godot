class_name SelectPanel
extends PanelContainer
## 底部候选卡片（PRD §4.3 / §10.2）：三张卡容量文案一致，只有名字与缩略图不同。
##
## 卡片曾经是一个纯 Button：card.text 塞「名字\n容量文案」、card.icon 塞预览图。
## 真机上炸了两个坑（2026-09-04，vivo V2509A，360×800 逻辑视口）：
##   D1 Button 文字默认不折行，容量文案（13 个 CJK 字）撑出 237px 的卡片最小宽度，
##      三张卡 + 两条 8px 间隙 = 727px，远超 360px 视口，2/3 号卡片跑到屏幕外。
##   D2 app_theme.tres 的 Button/colors/icon_normal_color 是给侧栏白色描边 SVG
##      调墨色用的乘色，顺带把预览缩略图乘成近黑色小方块。
## 现在卡片仍然是 Button（要它的 toggle_mode / ButtonGroup 行为），但文字和图像
## 挪到内部一个 MOUSE_FILTER_IGNORE 的 VBoxContainer 里：TextureRect（不经过
## Button 的 icon 乘色）+ 两级字号的 Label（容量行开自动折行，不再撑宽度）。

signal candidate_focused(id: String)
signal confirmed(id: String)

const CAPACITY_TEXT := "9 plots · 12 in week one"
## 卡片最小尺寸——刻意硬编码的一次性屏幕度量，不是要纳入 DesignTokens 的通用值
## （plan 第 18 行的约束只管 UI 颜色：「UI 颜色只取 DesignTokens」，尺寸不在此列）。
##
## x 的推导（2026-09-04 code review 订正：round 1 算错了父容器）。SelectPanel
## 不独占 360 逻辑视口——它是 $HUD/SafeArea/Root 的子节点，SafeArea
## （MarginContainer + SafeAreaMargin 脚本，modules/ui/safe_area_margin.gd）
## 每边至少留 min_margin=16px（modules/ui/ui_metrics.gd 的
## maxf(实测值, min_margin)，「任何情况下都不贴边」），所以 Root 的真实宽度
## 上限是 360-16-16=328，不是 360。预算：
##   360（逻辑视口）
##   - 32（安全区左右各 16，SafeAreaMargin.min_margin）
##   - 32（SB_drawer 面板内边距左右各 16，assets/ui/app_theme.tres）
##   - 16（两条卡间距，2×DesignTokens.SPACE_2）
##   = 280，三等分 ≤93.33。取 88（4dp 栅格对齐）留一点余量——HBoxContainer 的
## SIZE_EXPAND_FILL 会把富余摊给三张卡，实际渲染宽度只会比 88 更宽，不会更窄。
## y 比原来的 156 高，给两行折行的容量文案留够空间；真实层级下垂直方向仍有
## ~460px 富余（Root 高度 800-32=768 远大于面板自身高度 ~300），不需要收紧。
const CARD_MIN := Vector2(88, 172)
## 预览缩略图固定高度：卡片内容区（CARD_MIN 减去内边距）分给预览的那一份。
const CARD_PREVIEW_H := 64.0

var focused_id := ""
var confirm_button: Button
var _cards: Array[Button] = []
var _row: HBoxContainer
var _group := ButtonGroup.new()

func _init() -> void:
	name = "SelectPanel"
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_3)
	add_child(vbox)
	var title := Label.new()
	title.text = "Pick a neighborhood for your farm"
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	vbox.add_child(title)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	vbox.add_child(_row)
	confirm_button = Button.new()
	confirm_button.text = "Create Farm"
	confirm_button.disabled = true
	confirm_button.pressed.connect(func(): if not focused_id.is_empty(): confirmed.emit(focused_id))
	vbox.add_child(confirm_button)
	# 必须放在所有子节点加完之后：PRESET_MODE_MINSIZE（默认档）按调用时刻的
	# get_combined_minimum_size() 算 offset_top，子节点还没挂上去时那是 0，
	# 面板会整个长在父容器底边以下（C2，2026-09-04 终审）。真正的高度大头
	# 是候选卡（在 set_candidates() 里动态加），所以那边也要在加完卡片后重算一次。
	_apply_bottom_preset()

func _apply_bottom_preset() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)

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
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
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
	content.add_child(name_label)

	# D1：容量文案挪到独立 Label，AUTOWRAP_WORD_SMART 折行——CJK 没有空格，
	# 普通 WORD 折行遇到一个装不下的整词会整段不折，SMART 会在词内断开兜底。
	var capacity := Label.new()
	capacity.name = "CapacityLabel"
	capacity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	capacity.text = CAPACITY_TEXT
	capacity.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	capacity.add_theme_color_override("font_color", DesignTokens.INK_SUB)
	capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	capacity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	confirm_button.disabled = false
	candidate_focused.emit(focused_id)

func focus(id: String) -> void:
	for card in _cards:
		if str(card.get_meta("id")) == id:
			_on_card_pressed(card)
			return

func cards() -> Array[Button]:
	return _cards

func card_count() -> int:
	return _cards.size()
