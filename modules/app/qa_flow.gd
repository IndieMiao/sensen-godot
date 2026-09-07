class_name QaFlow
extends Node
## QA 流程步行器：人不在设备旁时自动走一遍社交主线并逐页截图。
##
## 触发：启动参数 `--qa-flow=social`（桌面 / Android）或环境变量 `SENSEN_QA_FLOW=social`
## （iOS 模拟器：`xcrun simctl launch` 用 SIMCTL_CHILD_ 前缀传环境变量）。AppRouter 在非测试进程里
## 发现请求就把本节点挂到自己下面（autoload 跨场景常驻）。截图与报告写到 `user://qa/`，
## 模拟器用 simctl get_app_container 拿，真机用 devicectl copy from 拉回来。
##
## 走的是页面上真正的处理函数（_on_continue / show_tab / push_instance…），不是模拟点击：
## 触控在模拟器里没法从外面注入，而这些函数就是按钮回调，覆盖到的逻辑一样。

const OUT_DIR := "user://qa"
const SETTLE_S := 0.35

var flow := ""
var report := {"flow": "", "started_at": "", "steps": [], "errors": [], "done": false}
var _index := 0

## 从参数或环境变量里取要跑的流程名；没有返回空串。
static func requested(args: PackedStringArray, env_value: String) -> String:
	for a in args:
		if str(a).begins_with("--qa-flow="):
			return str(a).trim_prefix("--qa-flow=").strip_edges().to_lower()
	return env_value.strip_edges().to_lower()

func _ready() -> void:
	report.flow = flow
	report.started_at = Time.get_datetime_string_from_system()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	call_deferred("_run")

func _run() -> void:
	match flow:
		"social":
			await run_social()
		_:
			_error("unknown flow: %s" % flow)
	report.done = true
	_write_report()
	print("QaFlow: done, %d steps, %d errors" % [report.steps.size(), report.errors.size()])
	if OS.get_environment("SENSEN_QA_QUIT") == "1":
		get_tree().quit()

## 年龄门 → 同意页 → 登录（Dev）→ 四个 Tab → 设置 → 探针页 → 切中文 → 切回 → 登出。
func run_social() -> void:
	# 干净起点：清掉首启裁决与会话，否则从上次的状态接着走。
	FirstRun.clear()
	if Net.auth != null:
		Net.auth.sign_out()
	AppRouter.go_to_route(AppRoutes.AGE_GATE)
	await settle()
	await shot("age_gate_empty")
	var gate := current()
	if not _expect(gate, AppRoutes.AGE_GATE):
		return
	gate._on_continue()
	await settle()
	await shot("age_gate_missing_selection")
	select_id(gate.year, 2000)
	select_id(gate.month, 1)
	select_id(gate.day, 1)
	await settle()
	await shot("age_gate_filled")
	gate._on_continue()
	await settle()
	var consent := current()
	if not _expect(consent, AppRoutes.CONSENT):
		return
	await shot("consent")
	consent.agree.button_pressed = true
	consent._refresh()
	await settle()
	await shot("consent_agreed")
	consent._on_continue()
	await settle()
	var login := current()
	if not _expect(login, AppRoutes.LOGIN):
		return
	await shot("login")
	if login.dev_button == null or not login.dev_button.visible:
		_error("login page has no Dev continue (release build?)")
		return
	login._on_dev_continue()
	await settle()
	var shell := current()
	if not _expect(shell, AppRoutes.SHELL):
		return
	for tab in AppRoutes.TABS:
		shell.show_tab(tab)
		await settle()
		await shot("tab_%s" % tab)
	AppRouter.push_instance(AppRoutes.SETTINGS)
	await settle()
	await shot("settings")
	AppRouter.push_instance(AppRoutes.LIFECYCLE_PROBE)
	await settle()
	await shot("lifecycle_probe")
	AppRouter.pop_instance()
	await settle()
	var settings := AppRouter.top_instance()
	if settings == null or not settings.has_method("_on_language"):
		_error("settings page not on top after popping the probe")
		return
	settings._on_language()
	await settle()
	await settle()
	await shot("shell_%s" % AppLocale.current())
	AppLocale.apply("en")
	AppRouter.reload_shell()
	await settle()
	await settle()
	await shot("shell_en_again")
	AppRouter.push_instance(AppRoutes.SETTINGS)
	await settle()
	var settings2 := AppRouter.top_instance()
	if settings2 == null or not settings2.has_method("_on_sign_out"):
		_error("settings page missing before sign out")
		return
	settings2._on_sign_out()
	await settle()
	await shot("signed_out_login")
	_expect(current(), AppRoutes.LOGIN)

func current() -> Node:
	return get_tree().current_scene

static func select_id(o: OptionButton, id: int) -> void:
	o.select(o.get_item_index(id))

## 等布局、延迟导航和一帧渲染都落定。
func settle() -> void:
	for i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(SETTLE_S).timeout
	await get_tree().process_frame

## 截当前视口存 PNG，并记一条步骤（场景路径 + 栈顶 + 耗时）。
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	_index += 1
	var file := "%s/%02d_%s.png" % [OUT_DIR, _index, name]
	var img := get_viewport().get_texture().get_image()
	var err := OK if img == null else img.save_png(file)
	var top := AppRouter.top_instance()
	report.steps.append({
		"index": _index, "name": name, "file": file.get_file(), "saved": img != null and err == OK,
		"scene": current().scene_file_path if current() else "",
		"top": top.scene_file_path if top else "",
		"locale": TranslationServer.get_locale(),
		"at_ms": Time.get_ticks_msec(),
	})
	_write_report()

func _expect(node: Node, scene_path: String) -> bool:
	if node != null and node.scene_file_path == scene_path:
		return true
	_error("expected %s but current scene is %s" % [scene_path, node.scene_file_path if node else "null"])
	return false

func _error(msg: String) -> void:
	push_error("QaFlow: " + msg)
	report.errors.append({"after_step": _index, "message": msg})
	_write_report()

func _write_report() -> void:
	var f := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
