class_name AppShell
extends Control
## 四 Tab 壳（08-30 调研 §3.1）：地图 / 动态 / 消息 / 我的。
## Tab 页只实例化一次，切换靠显隐 + process_mode，页面状态（列表滚动、草稿）天然保留；
## 地图页无论当前 Tab 是什么都常驻——它将来垫着原生 MapView，进出只是显隐。
## 返回键：非首页 Tab → 回地图 Tab；地图 Tab → 交还 AppRouter（回后台）。

signal tab_changed(tab: String)

const TAB_BAR_HEIGHT := 56
const UI_STATE_KEY := "shell_tab"

var current_tab := ""
var _pages := {}
var _buttons := {}
var _page_host: Control
var _tab_bar: HBoxContainer
var _backdrop: ColorRect

func _ready() -> void:
	theme = GameUi.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 壳与页面宿主不吃触摸：地图页的手势靠事件落到 _unhandled_input；其他 Tab 页自己的根 Control 会兜住。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = GameUi.PAPER
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_backdrop = backdrop
	var safe := SafeAreaMargin.new()
	safe.name = "SafeArea"
	safe.min_margin = 0.0
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	safe.add_child(column)
	_page_host = Control.new()
	_page_host.name = "Pages"
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.clip_contents = true
	_page_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_page_host)
	_tab_bar = HBoxContainer.new()
	_tab_bar.name = "TabBar"
	_tab_bar.custom_minimum_size.y = TAB_BAR_HEIGHT
	_tab_bar.add_theme_constant_override("separation", 0)
	column.add_child(_tab_bar)
	for tab in AppRoutes.TABS:
		var b := Button.new()
		b.name = "Tab_%s" % tab
		b.text = tr(AppRoutes.tab_title(tab))
		b.icon = GameUi.icon(AppRoutes.tab_icon(tab))
		b.theme_type_variation = &"TabButton"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = TAB_BAR_HEIGHT
		b.focus_mode = Control.FOCUS_NONE
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.expand_icon = false
		b.pressed.connect(show_tab.bind(tab))
		_tab_bar.add_child(b)
		_buttons[tab] = b
	var saved := str(UiState.read().get(UI_STATE_KEY, ""))
	show_tab(saved if AppRoutes.is_tab(saved) else AppRoutes.home_tab())
	_ensure_page(AppRoutes.home_tab())

func show_tab(tab: String) -> void:
	if not AppRoutes.is_tab(tab) or tab == current_tab:
		return
	var previous := current_tab
	current_tab = tab
	var page := _ensure_page(tab)
	for id in _pages:
		var p: AppPage = _pages[id]
		var on: bool = id == tab
		p.visible = on
		p.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	# 地图页要让原生 MapView 从底下透上来：壳自己的纸色底只在其他 Tab 画。
	_backdrop.visible = tab != AppRoutes.TAB_MAP
	if not previous.is_empty() and _pages.has(previous):
		(_pages[previous] as AppPage).on_tab_hidden()
	page.on_tab_shown()
	for id in _buttons:
		(_buttons[id] as Button).theme_type_variation = &"TabSelectedButton" if id == tab else &"TabButton"
	UiState.write({UI_STATE_KEY: tab})
	tab_changed.emit(tab)

func has_page(tab: String) -> bool:
	return _pages.has(tab)

func page(tab: String) -> AppPage:
	return _pages.get(tab) as AppPage

func tab_button(tab: String) -> Button:
	return _buttons.get(tab) as Button

## AppRouter.handle_back 先问壳；返回 true 表示已消费。
func handle_back() -> bool:
	if current_tab != AppRoutes.home_tab():
		show_tab(AppRoutes.home_tab())
		return true
	return false

## 压栈协议：设置 / 语音房等子页压上来时停处理并通知当前 Tab 页（地图页借此隐藏原生 view）。
func suspend() -> void:
	process_mode = Node.PROCESS_MODE_DISABLED
	if _pages.has(current_tab):
		(_pages[current_tab] as AppPage).on_tab_hidden()

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	if _pages.has(current_tab):
		(_pages[current_tab] as AppPage).on_tab_shown()

func _ensure_page(tab: String) -> AppPage:
	if _pages.has(tab):
		return _pages[tab]
	var packed := load(AppRoutes.tab_scene(tab)) as PackedScene
	if packed == null:
		push_error("AppShell 无法加载 Tab 页 %s" % tab)
		return null
	var p := packed.instantiate() as AppPage
	p.name = "Page_%s" % tab
	p.in_shell = true
	p.visible = false
	p.process_mode = Node.PROCESS_MODE_DISABLED
	_page_host.add_child(p)
	_pages[tab] = p
	return p
