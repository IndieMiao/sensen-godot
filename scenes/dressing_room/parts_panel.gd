extends VBoxContainer
## 只展示确实存在选择空间的槽位；资源 ID 仅作为内部值，不进入界面文案。

signal selection_failed(message: String)
signal selection_started
## 仅在用户主动点分类标签时发出。setup() 的首次 _show_slot 与测试/预览的直接调用
## 都不发——否则一进房相机就推到头部，而进场应当先看到完整角色。
signal slot_changed(slot: StringName)

const TOUCH_HEIGHT := 48.0

## expand_icon keeps the source thumbnail size out of the grid's layout budget.
const THUMB_CELL_HEIGHT := 98.0
const COMPACT_CELL_HEIGHT := 82.0
## "无"选项没有部件可渲，用一个灰色禁止符占位，保证格子高度与其它项一致。
const ICON_NONE := preload("res://assets/ui/icons/none.svg")

const SLOT_LABELS := {
	&"hairHat": "Hair",
	&"cloth": "Outfits",
	&"shoes": "Shoes",
	&"messengerBag": "Bags",
	&"glass": "Glasses",
}
const SLOT_ICONS := {&"hairHat": "scissors", &"cloth": "shirt", &"shoes": "footprints", &"messengerBag": "shopping-bag", &"glass": "glasses"}

const PART_LABELS := {
	"hairhat0": "Silver Crop",
	"hairhat20": "Playful Hood",
	"hairhat41": "Chestnut Long",
	"hairhat43": "Blonde Bob",
	"hairhat51": "Straw Bucket",
	"hairhat70": "Propeller Cap",
	"cloth0": "Mint Casual",
	"cloth1": "Cream Suit",
	"cloth1_1": "Blue Stripe",
	"cloth11": "Garden Apron",
	"cloth28": "Navy Utility",
	"cloth42": "Blue Overalls",
	"shoes0": "Gray Sneakers",
	"shoes1": "Cream Loafers",
	"shoes2": "Coral Sneakers",
	# 两列格子在 360dp 下每格内宽约 132 单位；14 号字约 18 字符就顶满并被
	# clip_text 截断（真机上会看到 "Black Teal Runne"）。新增文案请控制在 16 字符内。
	"shoes3": "Black Runners",
	"shoes4": "Graffiti Tops",
	"shoes5": "Sand Boots",
	"messengerbag1": "Coral Satchel",
	"messengerbag2": "Court Sling",
	"messengerbag3": "Explorer Kit",
	"messengerbag4": "Playful Pack",
	"glass0": "Classic Black",
	"glass1": "Minimal Square",
	"glass3": "Gold Rounds",
	"glass5": "Lime Frames",
	"glass8": "Sharp Shades",
}

var rig: AvatarRig
var thumbnailer: PartThumbnailer
var current_slot: StringName = &""
var _interaction_enabled := true
var _compact := false
var _tab_buttons: Dictionary = {}
var _choice_buttons: Dictionary = {}
## 每次 _show_slot 自增；异步补缩略图时用来判断"这批还是不是当前这批"，
## 否则快速连点分类会把上一个分类的图贴到新按钮上。
var _slot_generation := 0

@onready var tabs: HBoxContainer = $TabsScroll/SlotTabs
@onready var grid: GridContainer = $PartsScroll/PartsGrid


func setup(p_rig: AvatarRig) -> void:
	rig = p_rig
	_clear(tabs)
	_tab_buttons.clear()
	for slot_def in Avatar.slot_table.slots:
		var parts: Array = Avatar.catalog.parts_for_slot(slot_def.slot_name)
		var choice_count := parts.size() + (0 if slot_def.required else 1)
		if choice_count <= 1:
			continue
		var button := Button.new()
		button.text = _slot_label(slot_def.slot_name)
		button.icon = GameUi.icon(SLOT_ICONS.get(slot_def.slot_name, "shirt"))
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.custom_minimum_size.y = TOUCH_HEIGHT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.expand_icon = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_PASS
		button.theme_type_variation = &"TabButton"
		button.pressed.connect(_show_slot.bind(slot_def.slot_name, true))
		tabs.add_child(button)
		_tab_buttons[slot_def.slot_name] = button

	rig.slot_applied.connect(_on_slot_applied)
	rig.part_load_failed.connect(_on_part_load_failed)
	rig.busy_changed.connect(_on_busy_changed)
	if not _tab_buttons.is_empty():
		_show_slot(_tab_buttons.keys()[0])


func set_interaction_enabled(enabled: bool) -> void:
	_interaction_enabled = enabled
	_refresh_state()


func set_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	for button in _choice_buttons.values():
		_size_choice(button)


func _size_choice(button: Button) -> void:
	button.custom_minimum_size.y = COMPACT_CELL_HEIGHT if _compact else THUMB_CELL_HEIGHT
	button.add_theme_constant_override("icon_max_width", 40 if _compact else 52)


func refresh() -> void:
	_refresh_state()


func visible_slot_names() -> Array[StringName]:
	var result: Array[StringName] = []
	for slot in _tab_buttons:
		result.append(slot)
	return result


func _show_slot(slot: StringName, user_initiated := false) -> void:
	if not _tab_buttons.has(slot):
		return
	current_slot = slot
	if user_initiated:
		slot_changed.emit(slot)
	_clear(grid)
	_choice_buttons.clear()
	_slot_generation += 1
	var slot_def := Avatar.slot_table.slot(slot)
	if slot_def and not slot_def.required:
		_add_choice("", _none_label(slot))
	var index := 0
	for meta in Avatar.catalog.parts_for_slot(slot):
		_add_choice(meta.id, _part_label(slot, meta.id, index))
		index += 1
	_refresh_state()
	_fill_thumbnails(_slot_generation)


func _add_choice(part_id: String, label: String) -> void:
	var button := Button.new()
	button.text = label
	_size_choice(button)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	# 短按由按钮处理，拖动继续冒泡给 ScrollContainer。
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.clip_text = true
	button.expand_icon = true
	button.theme_type_variation = &"ThumbChoiceButton"
	button.tooltip_text = label
	# 图在上、文案在下。图标先留空，由 _fill_thumbnails 渲好后回填；
	# 渲染失败也不影响可用性——文案一直都在。
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	if part_id.is_empty():
		button.icon = ICON_NONE
	button.set_meta(&"part_id", part_id)
	button.pressed.connect(_select_part.bind(current_slot, part_id))
	grid.add_child(button)
	_choice_buttons[part_id] = button


## 逐个渲缩略图并回填。串行是有意的：共用一个 SubViewport，而且一次只渲一个
## 部件对帧时间的影响可控（首次进入某分类时图会在几帧内陆续出现）。
func _fill_thumbnails(generation: int) -> void:
	if thumbnailer == null:
		return
	for part_id in _choice_buttons.keys():
		if part_id.is_empty():
			continue
		var texture: Texture2D = await thumbnailer.thumbnail(part_id)
		# 期间用户可能已经切走：换了分类就丢弃这一批结果。
		if generation != _slot_generation or not is_inside_tree():
			return
		var button := _choice_buttons.get(part_id) as Button
		if texture != null and is_instance_valid(button):
			button.icon = texture


func _select_part(slot: StringName, part_id: String) -> void:
	if not _interaction_enabled or rig == null:
		return
	selection_started.emit()
	if part_id.is_empty():
		rig.unequip(slot)
	else:
		rig.equip(slot, part_id)
	_refresh_state()


func _refresh_state() -> void:
	for slot in _tab_buttons:
		var tab := _tab_buttons[slot] as Button
		tab.disabled = not _interaction_enabled
		tab.theme_type_variation = &"TabSelectedButton" if slot == current_slot else &"TabButton"
	if rig == null or current_slot == &"":
		return
	var selected := rig.desired_part(current_slot)
	for part_id in _choice_buttons:
		var choice := _choice_buttons[part_id] as Button
		choice.disabled = not _interaction_enabled
		choice.theme_type_variation = (&"ThumbChoiceSelectedButton" if part_id == selected
			else &"ThumbChoiceButton")
	# 原来这里还有一行 "Selected: X" 文案。它说的三件事各自都已经有更直接的表达：
	# 选中项有薄荷描边、角色身上已经穿着、忙碌态 Done 按钮会显示 "Trying on..."。
	# 删掉它省下的一整行页脚（48 单位）还给了部件列表。


func _on_slot_applied(_slot: StringName, _part_id: String) -> void:
	_refresh_state()


func _on_busy_changed(_busy: bool) -> void:
	_refresh_state()


func _on_part_load_failed(slot: StringName, part_id: String, _err: int) -> void:
	var label := _part_label(slot, part_id)
	selection_failed.emit("Couldn't load %s. Previous look kept." % label)
	# AvatarRig 在发出失败信号后才回退 desired，延迟刷新才能读到最终目标态。
	call_deferred("_refresh_state")


func _slot_label(slot: StringName) -> String:
	return String(SLOT_LABELS.get(slot, "Other"))


func _part_label(slot: StringName, part_id: String, fallback_index := -1) -> String:
	if PART_LABELS.has(part_id):
		return String(PART_LABELS[part_id])
	if fallback_index < 0:
		var parts: Array = Avatar.catalog.parts_for_slot(slot)
		for i in parts.size():
			if parts[i].id == part_id:
				fallback_index = i
				break
	return "%s Style %d" % [_slot_label(slot), maxi(fallback_index + 1, 1)]


func _none_label(slot: StringName) -> String:
	match slot:
		&"glass":
			return "No Glasses"
		&"messengerBag":
			return "No Bag"
		_:
			return "None"


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
