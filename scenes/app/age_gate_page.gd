extends AppPage
## 中立年龄门（COPPA，08-30 调研 §5.3）：只问生日，不提"13 岁"；<13 拒绝并持久化，重装前不可重试。
## today / first_run 可注入，测试不依赖真实日期与磁盘。

var first_run: FirstRun
var today: Dictionary = {}
var navigate: Callable

var year: OptionButton
var month: OptionButton
var day: OptionButton
var continue_button: Button
var status: Label
## debug 构建里拦截页上的重置入口：测试期误点年份就会被永久拦截，没有它设备等于死锁。
var reset_button: Button

func _init() -> void:
	page_title = "Welcome"

func _build_body() -> void:
	placeholder(tr("Tell us your date of birth to get started."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	var t := _today()
	year = _picker("Year", range(int(t.year), int(t.year) - 100, -1))
	month = _picker("Month", range(1, 13))
	day = _picker("Day", range(1, 32))
	for p in [year, month, day]:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.item_selected.connect(_on_picked)
		row.add_child(p)
	continue_button = GameUi.button("check", tr("Continue"), "record age gate", true)
	continue_button.name = "Continue"
	continue_button.pressed.connect(_on_continue)
	body.add_child(continue_button)
	status = GameUi.label("", 12, GameUi.MUTED)
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 32
	body.add_child(status)
	if _state().age_gate_blocked:
		_show_blocked()

func _picker(node_name: String, values: Array) -> OptionButton:
	var o := OptionButton.new()
	o.name = node_name
	o.custom_minimum_size.y = 44
	o.focus_mode = Control.FOCUS_NONE
	for v in values:
		o.add_item(str(v), int(v))
	o.select(-1)
	return o

func _state() -> FirstRun:
	if first_run == null:
		first_run = FirstRun.load_state()
	return first_run

func _today() -> Dictionary:
	return today if not today.is_empty() else Time.get_date_dict_from_system()

func selected_birth() -> Dictionary:
	if year.selected < 0 or month.selected < 0 or day.selected < 0:
		return {}
	return {"year": year.get_selected_id(), "month": month.get_selected_id(), "day": day.get_selected_id()}

## 选了日期就把「请选完整生日」的提示收掉；被拦截时提示不动。
func _on_picked(_index: int) -> void:
	if not _state().age_gate_blocked:
		status.text = ""

func _on_continue() -> void:
	var birth := selected_birth()
	if birth.is_empty():
		status.text = tr("Please select your full date of birth.")
		return
	if _state().record_age_gate(birth, _today()):
		_go(AppRoutes.CONSENT)
	else:
		_show_blocked()

func _show_blocked() -> void:
	# 中立措辞：不告诉用户门槛是多少岁，避免改生日重试。
	status.text = tr("Sorry, you're not eligible to use this app.")
	continue_button.disabled = true
	for p in [year, month, day]:
		p.disabled = true
	if OS.is_debug_build() and reset_button == null:
		reset_button = GameUi.button("x", tr("Dev: reset age gate"), "FirstRun.clear()")
		reset_button.name = "DevReset"
		reset_button.pressed.connect(_on_dev_reset)
		body.add_child(reset_button)

## 只在 debug 构建存在；正式包里被拦截就是被拦截。
func _on_dev_reset() -> void:
	FirstRun.clear()
	first_run = FirstRun.new()
	status.text = ""
	continue_button.disabled = false
	for p in [year, month, day]:
		p.disabled = false
		p.select(-1)
	reset_button.queue_free()
	reset_button = null

func _go(route: String) -> void:
	if navigate.is_valid():
		navigate.call(route)
	else:
		AppRouter.go_to_route(route)
