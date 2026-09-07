class_name AppPage
extends Control
## 壳内 Tab 页与压栈子页的共同基类：统一主题、纸色背景、安全区、标题栏，
## 以及 AppShell 的 Tab 显隐回调与 AppRouter 的 suspend/resume 协议。
## 子类只实现 _build_body()，往 body 里放控件。

## 标题栏文案（A2 i18n 落地后走 tr）。
@export var page_title := ""
## 压栈子页有返回按钮（AppRouter.pop_instance）；Tab 页没有——Tab 级返回由壳处理。
@export var stacked := false

var shown_count := 0
var hidden_count := 0
var body: VBoxContainer
var title_label: Label

func _ready() -> void:
	theme = GameUi.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = GameUi.PAPER
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var safe := SafeAreaMargin.new()
	safe.name = "SafeArea"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	safe.add_child(column)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)
	if stacked:
		var back := GameUi.button("arrow-left", "", tr("Back"))
		back.name = "Back"
		back.pressed.connect(_on_back)
		header.add_child(back)
	title_label = GameUi.label(tr(page_title), 20)
	title_label.name = "Title"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)
	body = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	_build_body()

## 子类填充页面内容。
func _build_body() -> void:
	pass

## 占位说明：哪张卡会把这页做实。
func placeholder(text: String) -> Label:
	var l := GameUi.label(text, 14, GameUi.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(l)
	return l

func _on_back() -> void:
	AppRouter.pop_instance()

## AppShell 切 Tab 时调用；地图页据此显隐原生 MapView（B5）。
func on_tab_shown() -> void:
	shown_count += 1

func on_tab_hidden() -> void:
	hidden_count += 1

## AppRouter 压栈协议：有子页压在上面时停止处理，弹出后恢复。
func suspend() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
