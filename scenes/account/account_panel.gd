class_name AccountPanel
extends CanvasLayer
## 账号面板（SGODOT-135）：登录 / 注册 / 找回密码 / 验证邮箱 / 我的账号，一个模态层切五种状态。
##
## 游客点"建农场"时由登录墙弹出（决定 2）；也可从地图右上角账号按钮进入。关闭时发 closed，
## signed_in 表示此刻是否已登录（注册后跳过验证也算已登录：验证不阻塞进入游戏）。
##
## 面板贴顶而不是居中：手机软键盘从底部升起，贴顶的输入框不会被盖住。
## 背景整屏不透明（与选城页同一张风景图）：同一时间只看得到这一个窗口，底下的界面既不透出也点不到。

signal closed(signed_in: bool)

const MODES := ["sign_in", "sign_up", "forgot", "verify", "account"]

var mode := "sign_in"
var reason := ""
var busy := false
var _reset_code_sent := false

var _title: Label
var _subtitle: Label
var _email: LineEdit
var _password: LineEdit
var _code: LineEdit
var _new_password: LineEdit
var _status: Label
var _primary: Button
var _secondary: Button
var _tertiary: Button
var _danger: Button
var _close: Button
var _fields: VBoxContainer
var _confirm_delete := false

static func open(host: Node, p_mode := "sign_in", p_reason := "") -> AccountPanel:
	var panel := AccountPanel.new()
	panel.reason = p_reason
	panel.mode = p_mode if p_mode in MODES else "sign_in"
	host.add_child(panel)
	return panel

func _ready() -> void:
	layer = 70
	GameUi.register_modal(self)
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = GameUi.PAPER
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.theme = GameUi.theme()
	add_child(scrim)
	var background_path := "res://assets/ui/game/city-background.png"
	if not ResourceLoader.exists(background_path): background_path = "res://assets/ui/backgrounds/city-garden.png"
	if ResourceLoader.exists(background_path):
		var scenery := TextureRect.new()
		scenery.name = "Scenery"
		scenery.texture = load(background_path)
		scenery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scenery.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		scenery.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scrim.add_child(scenery)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 96)
	scrim.add_child(margin)
	var holder := VBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(holder)
	var panel := PanelContainer.new()
	panel.name = "Card"
	panel.add_theme_stylebox_override("panel", GameUi.panel_style(18))
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.custom_minimum_size.x = 300
	holder.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	var symbol := GameUi.picture(GameUi.icon("user-round"), 28)
	head.add_child(symbol)
	_title = GameUi.label("", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_title)
	_close = GameUi.button("x", "", L10n.text("Close"))
	_close.name = "Close"
	_close.pressed.connect(func(): dismiss())
	head.add_child(_close)
	_subtitle = GameUi.label("", 13, GameUi.MUTED)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.custom_minimum_size.x = 260
	column.add_child(_subtitle)
	_fields = VBoxContainer.new()
	_fields.add_theme_constant_override("separation", 8)
	column.add_child(_fields)
	_email = _field("Email", false, LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS)
	_email.name = "Email"
	_password = _field("Password", true)
	_password.name = "Password"
	_code = _field("6-digit code", false, LineEdit.KEYBOARD_TYPE_NUMBER)
	_code.name = "Code"
	_code.max_length = 6
	_new_password = _field("New password (8+ characters)", true)
	_new_password.name = "NewPassword"
	_status = GameUi.label("", 13, GameUi.CORAL)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 260
	column.add_child(_status)
	_primary = GameUi.button("", "", "", true)
	_primary.name = "Primary"
	_primary.custom_minimum_size.y = 48
	_primary.pressed.connect(_on_primary)
	column.add_child(_primary)
	_secondary = GameUi.button("", "", "")
	_secondary.name = "Secondary"
	_secondary.pressed.connect(_on_secondary)
	column.add_child(_secondary)
	_tertiary = GameUi.button("", "", "")
	_tertiary.name = "Tertiary"
	_tertiary.pressed.connect(_on_tertiary)
	column.add_child(_tertiary)
	_danger = GameUi.button("trash-2", " ", "")
	_danger.name = "Danger"
	_danger.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_danger.add_theme_color_override("font_color", GameUi.CORAL)
	_danger.pressed.connect(_on_danger)
	column.add_child(_danger)
	if Net and Net.account.signed_in() and mode in ["sign_in", "sign_up"]: mode = "account"
	if Net and Net.account.signed_in(): _email.text = Net.account.email
	set_mode(mode)

func _field(placeholder: String, secret: bool, keyboard := LineEdit.KEYBOARD_TYPE_DEFAULT) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = L10n.text(placeholder)
	edit.secret = secret
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD if secret else keyboard
	edit.custom_minimum_size = Vector2(260, 44)
	edit.select_all_on_focus = false
	edit.text_submitted.connect(func(_t): _on_primary())
	_fields.add_child(edit)
	return edit

func set_mode(next: String) -> void:
	mode = next
	_confirm_delete = false
	_danger_primary(false)
	_status.text = ""
	_status.visible = false
	_status.add_theme_color_override("font_color", GameUi.CORAL)
	_email.editable = mode in ["sign_in", "sign_up", "forgot"]
	var signed := Net != null and Net.account.signed_in()
	match mode:
		"sign_in":
			_show_fields([_email, _password])
			_set_texts("Sign in", reason if not reason.is_empty() else "Sign in with your email to keep your farm on every device.",
				"Sign in", "Create an account", "Forgot password?")
		"sign_up":
			_show_fields([_email, _password])
			_password.placeholder_text = L10n.text("Password (8+ characters)")
			_set_texts("Create account", reason if not reason.is_empty() else "Your farm is saved to this account.",
				"Create account", "I already have an account", "")
		"forgot":
			_show_fields([_email, _code, _new_password] if _reset_code_sent else [_email])
			_set_texts("Reset password", "We'll email you a 6-digit code." if not _reset_code_sent else "Enter the code from the email and choose a new password.",
				"Reset password" if _reset_code_sent else "Send code", "Back to sign in", "Send a new code" if _reset_code_sent else "")
		"verify":
			_show_fields([_code])
			_set_texts("Verify email", L10n.format_text("We sent a 6-digit code to %s.", Net.account.email if signed else ""),
				"Verify", "Send a new code", "Later")
		"account":
			_show_fields([])
			var status := L10n.text("Verified") if signed and Net.account.email_verified else L10n.text("Not verified yet")
			_set_texts("My account", (Net.account.email if signed else "") + "\n" + status,
				"Done", "Verify email" if signed and not Net.account.email_verified else "", "Sign out")
	_danger.visible = mode == "account"
	_danger.text = L10n.text("Delete account")
	_password.placeholder_text = L10n.text("Password (8+ characters)" if mode == "sign_up" else "Password")

func _show_fields(visible_fields: Array) -> void:
	for f in [_email, _password, _code, _new_password]:
		f.visible = f in visible_fields
	_fields.visible = not visible_fields.is_empty()

func _set_texts(title: String, subtitle: String, primary: String, secondary: String, tertiary: String) -> void:
	_title.text = L10n.text(title)
	_subtitle.text = L10n.text(subtitle)
	_primary.text = L10n.text(primary)
	_secondary.text = L10n.text(secondary)
	_secondary.visible = not secondary.is_empty()
	_tertiary.text = L10n.text(tertiary)
	_tertiary.visible = not tertiary.is_empty()

func _say(message: String, ok := false) -> void:
	_status.text = L10n.text(message)
	_status.visible = not message.is_empty()
	_status.add_theme_color_override("font_color", GameUi.GREEN if ok else GameUi.CORAL)

func _set_busy(value: bool) -> void:
	busy = value
	for b in [_primary, _secondary, _tertiary, _danger, _close]:
		b.disabled = value

func dismiss() -> void:
	if busy: return
	var signed := Net != null and Net.account.signed_in()
	closed.emit(signed)
	queue_free()

func _on_primary() -> void:
	if busy: return
	match mode:
		"sign_in": await _submit_login(false)
		"sign_up": await _submit_login(true)
		"forgot":
			if _reset_code_sent: await _submit_reset()
			else: await _send_reset_code()
		"verify": await _submit_verify()
		"account":
			if _confirm_delete: await _submit_delete()
			else: dismiss()

func _on_secondary() -> void:
	if busy: return
	match mode:
		"sign_in": set_mode("sign_up")
		"sign_up": set_mode("sign_in")
		"forgot":
			_reset_code_sent = false
			set_mode("sign_in")
		"verify": await _send_code(Net.account.email, "verify")
		"account":
			if _confirm_delete: set_mode("account")
			else:
				await _send_code(Net.account.email, "verify")
				set_mode("verify")

func _on_tertiary() -> void:
	if busy: return
	match mode:
		"sign_in":
			_reset_code_sent = false
			set_mode("forgot")
		"forgot": await _send_reset_code()
		"verify": dismiss()
		"account":
			_set_busy(true)
			await Net.sign_out()
			_set_busy(false)
			dismiss()

func _on_danger() -> void:
	if busy or mode != "account": return
	# Deletion asks twice and needs the password: it removes the farm for good.
	_confirm_delete = true
	_show_fields([_password])
	_password.text = ""
	_password.placeholder_text = L10n.text("Password")
	_title.text = L10n.text("Delete account?")
	_subtitle.text = L10n.text("This permanently deletes your account and your farm. Enter your password to confirm.")
	_primary.text = L10n.text("Delete permanently")
	_danger_primary(true)
	_secondary.text = L10n.text("Keep my account")
	_secondary.visible = true
	_tertiary.visible = false
	_danger.visible = false

## 删除确认时主按钮变成珊瑚红，不能和"注册 / 登录"用同一种绿色。
func _danger_primary(on: bool) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		if on:
			var style := GameUi.surface(GameUi.CORAL, 10, 14)
			if state == "pressed": style.bg_color = GameUi.CORAL.darkened(0.12)
			_primary.add_theme_stylebox_override(state, style)
		else:
			_primary.remove_theme_stylebox_override(state)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		if on: _primary.add_theme_color_override(color, Color.WHITE)
		else: _primary.remove_theme_color_override(color)

func _submit_login(create: bool) -> void:
	var email := _email.text.strip_edges()
	if not AccountSession.valid_email(email):
		_say("Enter a valid email address.")
		return
	if create and not AccountSession.valid_password(_password.text):
		_say("Use at least 8 characters for your password.")
		return
	if _password.text.is_empty():
		_say("Enter your password.")
		return
	_set_busy(true)
	_say("Signing in…", true)
	var result: Dictionary
	if create: result = await AccountSession.register(Net.client, email, _password.text)
	else: result = await AccountSession.login(Net.client, email, _password.text)
	if result.ok: result.ok = await Net.sign_in_with(result.body)
	_set_busy(false)
	if not result.ok:
		_say(AccountSession.describe(str(result.code)))
		return
	_password.text = ""
	if create and not Net.account.email_verified: set_mode("verify")
	else: dismiss()

func _send_reset_code() -> void:
	var email := _email.text.strip_edges()
	if not AccountSession.valid_email(email):
		_say("Enter a valid email address.")
		return
	_set_busy(true)
	var result := await AccountSession.request_code(Net.client, email, "reset")
	_set_busy(false)
	if not result.ok and str(result.code) != "CODE_COOLDOWN":
		_say(AccountSession.describe(str(result.code)))
		return
	_reset_code_sent = true
	set_mode("forgot")
	_say("If this email has an account, a code is on its way." if result.ok else AccountSession.describe("CODE_COOLDOWN"), result.ok)

func _submit_reset() -> void:
	var email := _email.text.strip_edges()
	if _code.text.strip_edges().length() != 6:
		_say("Enter the 6-digit code.")
		return
	if not AccountSession.valid_password(_new_password.text):
		_say("Use at least 8 characters for your password.")
		return
	_set_busy(true)
	var result := await AccountSession.reset(Net.client, email, _code.text, _new_password.text)
	if result.ok: result.ok = await Net.sign_in_with(result.body)
	_set_busy(false)
	if not result.ok:
		_say(AccountSession.describe(str(result.code)))
		return
	_new_password.text = ""
	dismiss()

func _send_code(email: String, purpose: String) -> void:
	_set_busy(true)
	var result := await AccountSession.request_code(Net.client, email, purpose)
	_set_busy(false)
	if result.ok: _say("A new code is on its way.", true)
	else: _say(AccountSession.describe(str(result.code)))

func _submit_verify() -> void:
	if _code.text.strip_edges().length() != 6:
		_say("Enter the 6-digit code.")
		return
	_set_busy(true)
	var result := await AccountSession.verify(Net.client, _code.text)
	_set_busy(false)
	if not result.ok:
		_say(AccountSession.describe(str(result.code)))
		return
	Net.account.adopt(result.body, Net.account_path)
	dismiss()

func _submit_delete() -> void:
	if _password.text.is_empty():
		_say("Enter your password.")
		return
	_set_busy(true)
	var result := await Net.delete_account(_password.text)
	_set_busy(false)
	if not result.ok:
		_say(AccountSession.describe(str(result.code)))
		return
	dismiss()
