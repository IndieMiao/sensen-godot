extends VBoxContainer
## 槽位标签页 + 部件网格。数据只来自 slot_table 与 PartCatalog（元数据+缩略图）。

const THUMB_SIZE := Vector2(72, 72)  # 基准单位≈dp；1080 宽屏实际 216px
## 是否在部件按钮上显示缩略图。**当前为 false**：assets/avatar/thumbs/ 下 25 张
## 缩略图是同一张 64×64 / 168 字节占位图（管线缺口，见 tools/pipeline/extract_parts.gd
## 的 _write_thumb —— thumb_src 对所有部件都没解析到真实图），信息量为零；而主题给
## Button 的 content_margin 是 16（48dp 触摸标准），包在 64px 图标外面会把每格最小宽
## 顶到 96，4 列就撑破安全区（test_drawer_does_not_overflow_safe_area_on_four_part_slot）。
## 管线能产出真实缩略图之后，把这里改 true 即可；届时需要同步放宽格子尺寸并重跑那条布局回归。
const SHOW_THUMBNAILS := false

var rig: AvatarRig
var current_slot: StringName

@onready var tabs: HBoxContainer = $TabsScroll/SlotTabs
@onready var grid: GridContainer = $PartsScroll/PartsGrid

func setup(p_rig: AvatarRig) -> void:
	rig = p_rig
	for slot_def in Avatar.slot_table.slots:
		if Avatar.catalog.parts_for_slot(slot_def.slot_name).is_empty():
			continue
		var b := Button.new()
		b.text = String(slot_def.slot_name)
		# 触摸滚动关键：按钮默认 STOP 会把按压事件截断在自己身上，ScrollContainer
		# 收不到就永远不会开始拖拽跟踪（scroll_container.cpp 按压起跟踪、越死区后
		# 广播 NOTIFICATION_SCROLL_BEGIN 取消子按钮按压）。PASS 让事件继续冒泡：
		# 短按=点击，划动=滚动，两者由全局滚动死区(24)仲裁。
		b.mouse_filter = Control.MOUSE_FILTER_PASS
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
		none_btn.custom_minimum_size = THUMB_SIZE
		none_btn.mouse_filter = Control.MOUSE_FILTER_PASS # 同 tabs：让列表可从按钮上起滑
		none_btn.pressed.connect(func(): rig.unequip(slot))
		grid.add_child(none_btn)
	for meta in Avatar.catalog.parts_for_slot(slot):
		var b := Button.new()
		b.custom_minimum_size = THUMB_SIZE
		b.mouse_filter = Control.MOUSE_FILTER_PASS # 同 tabs：让列表可从按钮上起滑
		b.tooltip_text = meta.id
		# id 文案是当前唯一有信息量的内容——缩略图全是同一张占位图（见 SHOW_THUMBNAILS）。
		b.text = meta.id
		b.clip_text = true # id 过长时省略号截断，不撑大格子
		b.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
		if SHOW_THUMBNAILS:
			var tex: Texture2D = load(meta.thumb_path) if meta.thumb_path != "" and ResourceLoader.exists(meta.thumb_path) else null
			if tex:
				b.icon = tex
				b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
				b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(func(): rig.equip(current_slot, meta.id))
		grid.add_child(b)
