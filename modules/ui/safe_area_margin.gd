class_name SafeAreaMargin
extends MarginContainer
## 按系统安全区设置四边内缩（视口单位）。刘海、挖孔、手势条统一由系统上报值兜住；
## 系统未上报（桌面/老机型）时退回 min_margin，任何情况下都不贴边。

signal margins_applied(margins: Vector4)

@export var min_margin: float = 16.0
## 额外底部内缩：地图 HUD 垫在四 Tab 壳下面时要给底栏让位，系统安全区不知道底栏的存在。
@export var extra_bottom: float = 0.0:
	set(v):
		extra_bottom = v
		if is_inside_tree():
			refresh()

func _ready() -> void:
	refresh()
	get_tree().root.size_changed.connect(refresh)

func refresh() -> void:
	apply_margins(
		DisplayServer.get_display_safe_area() if OS.has_feature("android") or OS.has_feature("ios") else Rect2i(),
		DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size)

## 注入式入口：测试直接传合成值，不依赖真机 DisplayServer。
func apply_margins(safe_area: Rect2i, window_size: Vector2i, viewport_size: Vector2) -> void:
	var m := UIMetrics.safe_margins(safe_area, window_size, viewport_size, min_margin)
	m.w += extra_bottom
	add_theme_constant_override(&"margin_left", roundi(m.x))
	add_theme_constant_override(&"margin_top", roundi(m.y))
	add_theme_constant_override(&"margin_right", roundi(m.z))
	add_theme_constant_override(&"margin_bottom", roundi(m.w))
	margins_applied.emit(m)
