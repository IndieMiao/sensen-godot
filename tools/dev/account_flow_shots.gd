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
	await _shot("游客点「建农场」时弹出的登录墙（注册，含确认密码）")
	_type(p, "Email", email)
	_type(p, "Password", "correct horse")
	_type(p, "ConfirmPassword", "correct horsy")
	await _press(p, "sign_up")
	await _shot("两次密码不一致：本地校验，不发请求")
	_type(p, "ConfirmPassword", "correct horse")
	await _press(p, "sign_up")
	await _shot("注册成功，进入邮箱验证")
	_type(p, "Code", "000000")
	await _press(p, "verify")
	await _shot("验证码错误")
	_type(p, "Code", "424242")
	await _press(p, "verify")
	await _shot("验证通过后补资料：昵称必填，性别、生日选填")
	_type(p, "Nickname", "Ada")
	var gender := p.find_child("Gender", true, false) as OptionButton
	gender.select(4)
	gender.item_selected.emit(4)
	_type(p, "GenderCustom", "Genderfluid")
	(p.find_child("Month", true, false) as OptionButton).select(2)
	(p.find_child("Day", true, false) as OptionButton).select(29)
	(p.find_child("Year", true, false) as OptionButton).select(26)
	await _shot("填写资料：自行描述性别 + 生日")
	await _press(p, "save_profile")
	p = AccountPanel.open(host, "account")
	await _shot("我的账号：昵称、邮箱验证状态、性别与年龄")
	await _press(p, "to_password")
	_type(p, "Password", "correct horse")
	_type(p, "NewPassword", "another pass")
	_type(p, "ConfirmPassword", "another pass")
	(p.find_child("ShowPasswords", true, false) as CheckBox).button_pressed = true
	await _shot("修改密码：当前密码 + 新密码两次（已打开「显示密码」）")
	await _press(p, "change_password")
	await _shot("修改成功，回到我的账号")
	await _press(p, "sign_out")
	p = AccountPanel.open(host, "sign_in")
	_type(p, "Email", email)
	_type(p, "Password", "wrong password")
	await _press(p, "sign_in")
	await _shot("退出后重新登录：密码错误")
	await _press(p, "to_forgot")
	await _press(p, "send_reset")
	await _shot("找回密码：已发送验证码，填写验证码和新密码两次")
	await _press(p, "to_sign_in")
	_type(p, "Email", email)
	_type(p, "Password", "another pass")
	await _press(p, "sign_in")
	p = AccountPanel.open(host, "account")
	await _press(p, "delete")
	await _shot("删除账号：需再输一次密码确认")
	_type(p, "Password", "another pass")
	await _press(p, "delete_now")
	print("account_flow: cleaned up demo account, guest=", Net.is_guest())
	get_tree().quit()

func _type(p: AccountPanel, field: String, text: String) -> void:
	var edit := p.find_child(field, true, false) as LineEdit
	edit.text = text
	edit.text_changed.emit(text) # what real typing does

func _press(p: AccountPanel, button: String) -> void:
	p.action_button(button).pressed.emit()
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
