class_name SelectPanel
extends PanelContainer
## 底部候选卡片（PRD §4.3 / §10.2）：三张卡容量文案一致，只有名字与缩略图不同。

signal candidate_focused(id: String)
signal confirmed(id: String)

const CAPACITY_TEXT := "9 格起步 · 首周可扩到 12 格"
## 卡片最小尺寸——刻意硬编码的一次性屏幕度量，不是要纳入 DesignTokens 的通用值
## （plan 第 18 行的约束只管 UI 颜色：「UI 颜色只取 DesignTokens」，尺寸不在此列）。
const CARD_MIN := Vector2(104, 156)

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
	title.text = "选一片街区，生成你的农场"
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_LABEL)
	vbox.add_child(title)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	vbox.add_child(_row)
	confirm_button = Button.new()
	confirm_button.text = "确认创建"
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
		card.text = "%s\n%s" % [item.name, CAPACITY_TEXT]
		card.icon = item.get("preview")
		card.expand_icon = true
		card.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		card.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.set_meta("id", item.id)
		card.pressed.connect(_on_card_pressed.bind(card))
		_row.add_child(card)
		_cards.append(card)
	# 候选卡是面板真正的高度大头（CARD_MIN.y=156 远大于标题/按钮），必须在它们
	# 都挂好之后重算一次 offset_top，否则仍然按 _init() 时刻（还没有卡片）的
	# 尺寸定住，卡片撑高的部分照样会长到父容器底边以下（C2，2026-09-04 终审）。
	_apply_bottom_preset()

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
