extends VBoxContainer
## 槽位标签页 + 部件网格。数据只来自 slot_table 与 PartCatalog（元数据+缩略图）。

var rig: AvatarRig
var current_slot: StringName

@onready var tabs: HBoxContainer = $SlotTabs
@onready var grid: GridContainer = $PartsScroll/PartsGrid

func setup(p_rig: AvatarRig) -> void:
	rig = p_rig
	for slot_def in Avatar.slot_table.slots:
		if Avatar.catalog.parts_for_slot(slot_def.slot_name).is_empty():
			continue
		var b := Button.new()
		b.text = String(slot_def.slot_name)
		b.pressed.connect(_show_slot.bind(slot_def.slot_name))
		tabs.add_child(b)
	if tabs.get_child_count() > 0:
		_show_slot(StringName(tabs.get_child(0).text))

func _show_slot(slot: StringName) -> void:
	current_slot = slot
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var slot_def := Avatar.slot_table.slot(slot)
	if slot_def and not slot_def.required:
		var none_btn := Button.new()
		none_btn.text = "卸下"
		none_btn.custom_minimum_size = Vector2(96, 96)
		none_btn.pressed.connect(func(): rig.unequip(slot))
		grid.add_child(none_btn)
	for meta in Avatar.catalog.parts_for_slot(slot):
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 96)
		b.tooltip_text = meta.id
		var tex: Texture2D = load(meta.thumb_path) if meta.thumb_path != "" and ResourceLoader.exists(meta.thumb_path) else null
		if tex:
			b.icon = tex
			b.expand_icon = true
		else:
			b.text = meta.id
		b.pressed.connect(func(): rig.equip(current_slot, meta.id))
		grid.add_child(b)
