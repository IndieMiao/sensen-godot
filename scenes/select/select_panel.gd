class_name SelectPanel
extends PanelContainer
## 底部候选卡片（PRD §4.3 / §10.2）：三张卡容量文案一致，只有名字与缩略图不同。

signal candidate_focused(id: String)
signal confirmed(id: String)

const CAPACITY_TEXT := "9 格起步 · 首周可扩到 12 格"
const CARD_MIN := Vector2(104, 156)

var focused_id := ""
var confirm_button: Button
var _cards: Array[Button] = []
var _row: HBoxContainer
var _group := ButtonGroup.new()

func _init() -> void:
	name = "SelectPanel"
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
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

func set_candidates(items: Array) -> void:
	for c in _cards:
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
