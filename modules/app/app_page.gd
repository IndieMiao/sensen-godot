class_name AppPage
extends Control
## 壳内 Tab 页与压栈子页的共同基类：统一主题、纸色背景、安全区、标题栏，
## 以及 AppShell 的 Tab 显隐回调与 AppRouter 的 suspend/resume 协议。
## 子类只实现 _build_body()，往 body 里放控件。

## 标题栏文案（A2 i18n 落地后走 tr）。
@export var page_title := ""
## 压栈子页有返回按钮（AppRouter.pop_instance）；Tab 页没有——Tab 级返回由壳处理。
@export var stacked := false
## 软键盘避让方式：默认整页平移；输入框固定在底部、中间是列表的页（聊天）改 SHRINK，见 KeyboardAvoider。
@export var keyboard_mode := KeyboardAvoider.Mode.SHIFT

var shown_count := 0
var hidden_count := 0
var body: VBoxContainer
var title_label: Label
var keyboard_avoider: KeyboardAvoider
## 由 AppShell 在 add_child 前置 true：壳已经按系统安全区内缩过，页面再套一层就是双倍留白（真机截图）。
var in_shell := false

func _ready() -> void:
	theme = GameUi.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = GameUi.PAPER
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var safe: MarginContainer
	if in_shell:
		safe = MarginContainer.new()
		for side in ["left", "right"]:
			safe.add_theme_constant_override("margin_%s" % side, 16)
		safe.add_theme_constant_override("margin_top", DesignTokens.SPACE_2)
		safe.add_theme_constant_override("margin_bottom", 0)
	else:
		safe = SafeAreaMargin.new()
	safe.name = "SafeArea"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_3)
	safe.add_child(column)
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", DesignTokens.SPACE_2)
	column.add_child(header)
	if stacked:
		var back := GameUi.button("arrow-left", "", tr("Back"))
		back.name = "Back"
		back.pressed.connect(_on_back)
		header.add_child(back)
	title_label = GameUi.label(tr(page_title), DesignTokens.UI_FONT_TITLE)
	title_label.name = "Title"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)
	body = VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", DesignTokens.SPACE_3)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	# 软键盘避让：所有带输入框的页面（登录 / 聊天 / 发布器 / 资料编辑）统一在这里挂，A5 专项。
	keyboard_avoider = KeyboardAvoider.new()
	keyboard_avoider.name = "KeyboardAvoider"
	keyboard_avoider.mode = keyboard_mode
	# SHRINK 收的是 SafeArea 的底边（父节点是本页这个普通 Control，offset 不会被容器盖掉）。
	keyboard_avoider.target = safe if keyboard_mode == KeyboardAvoider.Mode.SHRINK else column
	add_child(keyboard_avoider)
	_build_body()

## 子类填充页面内容。
func _build_body() -> void:
	pass

## 点输入框以外的地方让输入框失焦——LineEdit 失焦时 Godot 才会收起软键盘。
## 走 _input 而不是 gui_input：不管被哪个控件（滚动列表、按钮、空白）吃掉，按下都先经过这里。
## 2026-09-08 真机：「我的」页拉起键盘后没有任何办法收回，就是因为页面上没有东西让它失焦。
func _input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if not pressed or not is_visible_in_tree():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or not (focus is LineEdit or focus is TextEdit):
		return
	if not focus.get_global_rect().has_point(event.position):
		focus.release_focus()

## 占位说明：哪张卡会把这页做实。
func placeholder(text: String) -> Label:
	var l := GameUi.label(text, DesignTokens.UI_FONT_BODY, GameUi.MUTED)
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
