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
var out_dir := OUT_DIR
var watch_interval_s := 3.0
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	clear_output()
	if not flow.is_empty():
		call_deferred("_run")

func _run() -> void:
	match flow:
		"social":
			await run_social()
		"login":
			await run_login()
		_:
			_error("unknown flow: %s" % flow)
	await stay()
	await watch()
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
	# SENSEN_QA_PICK=1：在探针页弹系统选图器（C3 真机验证）。人选完图流程才继续，结果打在页上再截一张。
	if OS.get_environment("SENSEN_QA_PICK") == "1":
		var probe := AppRouter.top_instance()
		if probe != null and probe.has_method("pick_photos"):
			await probe.pick_photos()
			await settle()
			await shot("photos_picked")
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

## 用真实账号登录并留在壳里（M2 alpha 端到端用）：SENSEN_QA_LOGIN=email:password；
## 可选 SENSEN_QA_DM=@handle 直接打开与某人的单聊，SENSEN_QA_SAY=文字 再发一句。
## 首启合规裁决直接写成通过（这是 QA 实例，不是用户）。
func run_login() -> void:
	var cred := parse_credentials(OS.get_environment("SENSEN_QA_LOGIN"))
	if cred.is_empty():
		_error("SENSEN_QA_LOGIN must be email:password")
		return
	var fr := FirstRun.load_state()
	fr.record_age_gate({"year": 2000, "month": 1, "day": 1}, Time.get_date_dict_from_system())
	fr.record_consent()
	var r: Dictionary = await Net.firebase.sign_in_with_password(cred.email, cred.password)
	if not bool(r.get("ok", false)):
		_error("firebase sign-in failed: %s" % str(r.get("code", "")))
		return
	Net.auth.complete_sign_in(str(r.user_id), str(r.id_token), str(r.refresh_token), int(r.expires_in_s), "password", str(r.email))
	var a: Dictionary = await Net.account.sign_in()
	if bool(a.get("ok", false)):
		Net.auth.set_server_user(str(a.get("user_id", "")))
	else:
		_error("account link failed: %s %s" % [str(a.get("code", "")), str(a.get("reason", ""))])
		return
	Net.connect_im()
	AppRouter.go_to_shell()
	await settle()
	var shell := current()
	if not _expect(shell, AppRoutes.SHELL):
		return
	# SENSEN_QA_ME=1：先进「我的」Tab 拉资料（顺带把本地装扮同步到服务端，B7），截一张；
	# SENSEN_QA_FOLLOWERS=1 再压栈自己的关注者列表截一张。
	if OS.get_environment("SENSEN_QA_ME") == "1":
		shell.show_tab(AppRoutes.TAB_PROFILE)
		await settle()
		var me_page = shell.page(AppRoutes.TAB_PROFILE)
		if me_page != null and me_page.has_method("refresh_profile"):
			await me_page.refresh_profile()
		await settle()
		await shot("me_tab")
		if OS.get_environment("SENSEN_QA_FOLLOWERS") == "1":
			AppRouter.push_instance(AppRoutes.FOLLOW_LIST, {"user_id": Net.auth.server_user_id, "kind": "followers"})
			await settle()
			await settle()
			await shot("followers")
			AppRouter.pop_instance()
			await settle()
	# SENSEN_QA_MAP=1：进地图 Tab（B5），等角色装配几秒再截；SENSEN_QA_FAKE_LOCATION=lat,lng 模拟一次定位
	# （桌面没有 GPS、iOS 桥暂无定位）：地图落锚 + 页面按真实路径上报服务端。
	if OS.get_environment("SENSEN_QA_MAP") == "1":
		shell.show_tab(AppRoutes.TAB_MAP)
		await settle()
		var map_page = shell.page(AppRoutes.TAB_MAP)
		var fake := OS.get_environment("SENSEN_QA_FAKE_LOCATION").split(",", false)
		if fake.size() == 2 and map_page != null and map_page.map_scene != null and map_page.map_scene.has_method("_on_location_update"):
			map_page.map_scene._on_location_update(float(fake[0]), float(fake[1]), 10.0)
			await settle()
			if map_page.has_method("refresh_friends"):
				await map_page.refresh_friends()
		for i in 4:
			await settle()
		await shot("map_tab")
		# SENSEN_QA_MAP_ROUNDTRIP=1：地图 → 我的 → 地图，复现「切回来全黑」；每步都带 view 字段。
		if OS.get_environment("SENSEN_QA_MAP_ROUNDTRIP") == "1":
			shell.show_tab(AppRoutes.TAB_PROFILE)
			await settle()
			await shot("roundtrip_me")
			shell.show_tab(AppRoutes.TAB_MAP)
			for i in 3:
				await settle()
			await shot("map_back")
	shell.show_tab(AppRoutes.TAB_IM)
	await settle()
	await shot("im_tab")
	var dm := OS.get_environment("SENSEN_QA_DM").strip_edges()
	if dm.is_empty():
		return
	var page = shell.page(AppRoutes.TAB_IM)
	page.handle_edit.text = dm
	if not await page.start_chat():
		_error("start_chat failed: %s" % page.status.text)
		return
	await settle()
	await shot("chat_open")
	var chat := AppRouter.top_instance()
	if chat == null or not chat.has_method("send"):
		_error("chat page not on top")
		return
	var say := OS.get_environment("SENSEN_QA_SAY")
	if not say.is_empty():
		chat.composer.text = say
		if not await chat.send():
			_error("send failed: %s" % chat.status.text)
		await settle()
		await shot("chat_sent")
	# SENSEN_QA_PROFILE=1：顺手压栈对方的用户主页截一张（关注 / 发消息 / 举报 / 拉黑 + 动态列表），再弹回聊天页。
	if OS.get_environment("SENSEN_QA_PROFILE") == "1":
		AppRouter.push_instance(AppRoutes.USER, {"handle": dm})
		await settle()
		await settle()
		await shot("user_page")
		AppRouter.pop_instance()
		await settle()
	# SENSEN_QA_PHOTO=<路径>（user:// 或绝对路径）：不弹系统选图器，直接把这张图当选中的发出去——
	# 图片消息的上传 / 发送 / 渲染整条链在桌面和真机上都能自动跑。
	var photo := OS.get_environment("SENSEN_QA_PHOTO").strip_edges()
	if not photo.is_empty():
		var pp := PhotoPicker.new()
		pp.picker = func(_n: int) -> PackedStringArray: return PackedStringArray([photo])
		chat.picker = pp
		if not await chat.attach_photo():
			_error("attach failed: %s" % chat.status.text)
		await settle()
		await shot("photo_sent")

## "email:password" → {email, password}；密码里可以带冒号（只按第一个冒号切）。
static func parse_credentials(raw: String) -> Dictionary:
	var i := raw.find(":")
	if i <= 0 or i == raw.length() - 1:
		return {}
	return {"email": raw.substr(0, i).strip_edges(), "password": raw.substr(i + 1)}

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

## 清掉上一轮的截图与报告：步骤编号从 1 重排，短的一轮会留下上一轮的尾巴，按文件名分析就会混进旧帧
## （2026-09-07 观察窗第三轮里混入了第二轮的 197–200 号）。
func clear_output() -> void:
	var dir := DirAccess.open(out_dir)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".png") or f == "report.json":
			dir.remove(f)

## SENSEN_QA_STAY=map|feed|im|profile：观察窗开始前切到这个 Tab 并停在那儿——
## 真人要在某一页上手动操作（地图手势、系统权限弹窗）时，别让步行器把页面停在别处。
func stay(tab: String = OS.get_environment("SENSEN_QA_STAY").strip_edges()) -> bool:
	if tab.is_empty() or not AppRoutes.is_tab(tab):
		return false
	var shell := current()
	if shell == null or not shell.has_method("show_tab"):
		return false
	shell.show_tab(tab)
	await settle()
	await shot("stay_%s" % tab)
	return true

## SENSEN_QA_WATCH=<秒>：流程跑完后在这段时间里每隔 watch_interval_s 补拍一张（watch_NN）。
## 给真机上必须手点的验证留观察窗——键盘弹起、系统权限弹窗这类，镜像不弹软键盘，
## devicectl 也拿不到屏幕；人点完，拉回截图看视口有没有按预期位移。
func watch(secs: int = int(OS.get_environment("SENSEN_QA_WATCH"))) -> void:
	if secs <= 0:
		return
	var deadline := Time.get_ticks_msec() + secs * 1000
	var n := 0
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(watch_interval_s).timeout
		n += 1
		await shot("watch_%02d" % n)

## 截当前视口存 PNG，并记一条步骤（场景路径 + 栈顶 + 耗时）。
func shot(name: String) -> void:
	# 不等 frame_post_draw：被完全遮挡的窗口（测试进程常见）不出帧会永远等下去；同步强制画一帧再截。
	RenderingServer.force_draw()
	_index += 1
	var file := "%s/%02d_%s.png" % [out_dir, _index, name]
	var img := get_viewport().get_texture().get_image()
	var err := OK if img == null else img.save_png(file)
	var top := AppRouter.top_instance()
	report.steps.append({
		"index": _index, "name": name, "file": file.get_file(), "saved": img != null and err == OK,
		"scene": current().scene_file_path if current() else "",
		"top": top.scene_file_path if top else "",
		"locale": TranslationServer.get_locale(),
		"at_ms": Time.get_ticks_msec(),
		"view": view_state(),
	})
	_write_report()

## 视口 / 地图层状态：排查「地图回来全黑」这类问题时，截图里看不到原生层，只能靠这些字段。
func view_state() -> Dictionary:
	var vp := get_viewport()
	var d := {"transparent_bg": vp.transparent_bg, "clear": RenderingServer.get_default_clear_color().to_html()}
	var shell := current()
	if shell != null and shell.has_method("page") and shell.has_page(AppRoutes.TAB_MAP):
		var page = shell.page(AppRoutes.TAB_MAP)
		var m = page.map_scene if page != null and "map_scene" in page else null
		if m != null and is_instance_valid(m):
			d["map"] = {
				"visible": m.visible, "process": m.process_mode, "hud": m.get_node("HUD").visible,
				"cam_current": m.cam.current, "env": m.world_env.environment != null,
				"bridge": m.map != null, "ready": m._map_is_ready, "home": m._home_resolved,
				"pawns": m._pawns.size(), "queue": m._spawn_queue.size(), "friends": m.friend_count(),
				"cam": [snappedf(m.center_lat, 0.000001), snappedf(m.center_lng, 0.000001),
					snappedf(m.zoom, 0.01), snappedf(m.bearing, 0.1), snappedf(m.pitch, 0.1)],
			}
	return d

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
	var f := FileAccess.open("%s/report.json" % out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
