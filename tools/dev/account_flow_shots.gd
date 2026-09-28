extends Node
## 登录流程逐步截图：真实面板 + 真 HTTP 本地服（SGODOT-135）。每一步都是面板真实点击后的状态。
##
##   ACCOUNT_SHOTS=/tmp/flow E2E_BASE=http://127.0.0.1:3117/v1 SENSEN_OFFLINE=1 SENSEN_LANGUAGE=zh_CN \
##     godot --path . --resolution 360x800 tools/dev/ui_preview.tscn -- res://tools/dev/account_flow_shots.tscn notch
##
## 服务端需 QA_EMAIL_DOMAIN=qa.sensen.test、QA_EMAIL_CODE=424242。结束时删掉演示账号。

const ACCOUNT := "user://shots_account.json"
var out := "/tmp/account_flow"
var step := 0
var host: Control

func _ready() -> void:
	out = OS.get_environment("ACCOUNT_SHOTS") if OS.has_environment("ACCOUNT_SHOTS") else out
	DirAccess.make_dir_recursive_absolute(out)
	var base := OS.get_environment("E2E_BASE") if OS.has_environment("E2E_BASE") else "http://127.0.0.1:3117/v1"
	Net.use_transport(ApiClient.make_http_transport(Net), base, ACCOUNT)
	await Net.boot()
	host = (load("res://scenes/city_select/city_select.tscn") as PackedScene).instantiate()
	add_child(host)
	var tokyo: ApiClient.Response = await Net.client.request("POST", "/cities/resolve", {"location": {"lat": 35.6812, "lng": 139.7671}})
	host.show_suggestion(tokyo.json.city)
	var listed: ApiClient.Response = await Net.client.request("GET", "/cities")
	host._show_popular(listed.json.cities)
	await _shot("游客进入选城页（右上角是账号入口）")
	var email := "demo-%d@qa.sensen.test" % Time.get_unix_time_from_system()
	# Login wall, as opened when a guest confirms a farm location.
	var p := AccountPanel.open(host, "sign_up", L10n.text("Sign in to create your farm."))
	await _shot("游客点「建农场」时弹出的登录墙（注册）")
	_type(p, "Email", email)
	_type(p, "Password", "short")
	await _press(p, "Primary")
	await _shot("密码太短：本地校验，不发请求")
	_type(p, "Password", "correct horse")
	await _press(p, "Primary")
	await _shot("注册成功，进入邮箱验证")
	_type(p, "Code", "000000")
	await _press(p, "Primary")
	await _shot("验证码错误")
	_type(p, "Code", "424242")
	await _press(p, "Primary")
	p = AccountPanel.open(host, "account")
	await _shot("验证通过后的「我的账号」")
	await _press(p, "Tertiary")
	p = AccountPanel.open(host, "sign_in")
	_type(p, "Email", email)
	_type(p, "Password", "wrong password")
	await _press(p, "Primary")
	await _shot("退出后重新登录：密码错误")
	await _press(p, "Tertiary")
	await _press(p, "Primary")
	await _shot("找回密码：已发送验证码，填写验证码和新密码")
	await _press(p, "Secondary")
	_type(p, "Email", email)
	_type(p, "Password", "correct horse")
	await _press(p, "Primary")
	p = AccountPanel.open(host, "account")
	await _press(p, "Danger")
	await _shot("删除账号：需再输一次密码确认")
	_type(p, "Password", "correct horse")
	await _press(p, "Primary")
	print("account_flow: cleaned up demo account, guest=", Net.is_guest())
	get_tree().quit()

func _type(p: AccountPanel, field: String, text: String) -> void:
	(p.find_child(field, true, false) as LineEdit).text = text

func _press(p: AccountPanel, button: String) -> void:
	(p.find_child(button, true, false) as Button).pressed.emit()
	for i in 120:
		await get_tree().process_frame
		if not is_instance_valid(p) or not p.busy: break
	for i in 4: await get_tree().process_frame

func _shot(caption: String) -> void:
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	step += 1
	var path := "%s/%02d.png" % [out, step]
	get_viewport().get_texture().get_image().save_png(path)
	print("account_flow: %s %s" % [path, caption])
