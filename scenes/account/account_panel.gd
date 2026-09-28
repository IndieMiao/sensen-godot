class_name AccountPanel
extends CanvasLayer
## 账号面板（SGODOT-135）：一个模态层里切换登录、注册、找回密码、验证邮箱、资料、改密码、
## 我的账号、删号确认。
##
## 游客点"建农场"时由登录墙弹出（决定 2）；也可从地图 / 选城页右上角账号按钮进入。关闭时发
## closed，signed_in 表示此刻是否已登录（验证邮箱不阻塞进入游戏）。
##
## 面板贴顶而不是居中：手机软键盘从底部升起，贴顶的输入框不会被盖住。
## 背景整屏不透明（与选城页同一张 3D 地图）：同一时间只看得到这一个窗口，底下的界面既不透出也点不到。
##
## 每个状态的按钮不同，所以按钮列表按状态重建：按钮节点名就是动作 id（测试与截图脚本按名字点）。

signal closed(signed_in: bool)

const MODES := ["sign_in", "sign_up", "forgot", "verify", "profile", "password", "account", "delete"]
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const MIN_AGE := 13

var mode := "sign_in"
var reason := ""
var busy := false
## 从"我的账号"进入的子页面，保存 / 返回后回到账号页；从登录流程进入的则直接关闭。
var from_account := false
var _reset_code_sent := false
## 测试替身：func(nonce_hash) -> 原生回包；空则走 iOS 原生桥。
var apple_transport: Callable = Callable()

var _title: Label
var _subtitle: Label
var _email: LineEdit
var _password: LineEdit
var _confirm_password: LineEdit
var _code: LineEdit
var _new_password: LineEdit
var _nickname: LineEdit
var _gender: OptionButton
var _gender_custom: LineEdit
var _birthday: HBoxContainer
var _month: OptionButton
var _day: OptionButton
var _year: OptionButton
var _show_passwords: CheckBox
var _status: Label
var _actions: VBoxContainer
var _close: Button
var _fields: VBoxContainer
var _field_list: Array[Control] = []

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
	var background_path := "res://assets/ui/backgrounds/map-social.png"
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
	margin.add_theme_constant_override("margin_top", 72)
	margin.add_theme_constant_override("margin_bottom", 24)
	scrim.add_child(margin)
	var holder := VBoxContainer.new()
	holder.alignment = BoxContainer.ALIGNMENT_BEGIN
	margin.add_child(holder)
	# The focused field and the button right below it stay above the soft keyboard.
	KeyboardAvoider.attach(margin, 64.0)
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
	head.add_child(GameUi.picture(GameUi.icon("user-round"), 28))
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
	_nickname = _line("Nickname", "Nickname (2–24 characters)")
	_nickname.max_length = 24
	_email = _line("Email", "Email", false, LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS)
	_password = _line("Password", "Password", true)
	_code = _line("Code", "6-digit code", false, LineEdit.KEYBOARD_TYPE_NUMBER)
	_code.max_length = 6
	_new_password = _line("NewPassword", "New password (8+ characters)", true)
	_confirm_password = _line("ConfirmPassword", "Confirm password", true)
	_gender = _option("Gender", ["Gender (optional)"] + AccountSession.GENDERS.map(func(g): return g[1]))
	_gender.item_selected.connect(func(_i): _gender_custom.visible = _selected_gender() == "self_describe")
	_gender_custom = _line("GenderCustom", "How do you describe your gender?")
	_gender_custom.max_length = 32
	_birthday = HBoxContainer.new()
	_birthday.name = "Birthday"
	_birthday.add_theme_constant_override("separation", 6)
	_fields.add_child(_birthday)
	_field_list.append(_birthday)
	var this_year: int = Time.get_date_dict_from_system().year
	_month = _option("Month", ["Month"] + MONTHS, _birthday)
	var days := ["Day"]
	for d in range(1, 32): days.append(str(d))
	_day = _option("Day", days, _birthday)
	var years := ["Year"]
	for y in range(this_year - MIN_AGE, this_year - 121, -1): years.append(str(y))
	_year = _option("Year", years, _birthday)
	for o in [_month, _day, _year]: o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_show_passwords = CheckBox.new()
	_show_passwords.name = "ShowPasswords"
	_show_passwords.text = L10n.text("Show passwords")
	_show_passwords.focus_mode = Control.FOCUS_NONE
	# A plain checkbox, not the theme's filled toggle look.
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		_show_passwords.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_show_passwords.add_theme_color_override("font_color", GameUi.MUTED)
	_show_passwords.add_theme_color_override("font_pressed_color", GameUi.MUTED)
	_show_passwords.add_theme_color_override("font_hover_color", GameUi.INK)
	_show_passwords.add_theme_font_size_override("font_size", 13)
	_show_passwords.toggled.connect(func(on: bool):
		for f in [_password, _confirm_password, _new_password]: f.secret = not on)
	_fields.add_child(_show_passwords)
	_field_list.append(_show_passwords)
	_status = GameUi.label("", 13, GameUi.CORAL)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 260
	column.add_child(_status)
	_actions = VBoxContainer.new()
	_actions.name = "Actions"
	_actions.add_theme_constant_override("separation", 10)
	column.add_child(_actions)
	if Net and Net.account.signed_in() and mode in ["sign_in", "sign_up"]: mode = "account"
	if Net and Net.account.signed_in(): _email.text = Net.account.email
	set_mode(mode)

func _line(node_name: String, placeholder: String, secret := false, keyboard := LineEdit.KEYBOARD_TYPE_DEFAULT) -> LineEdit:
	# Once a field has text its placeholder is gone, so a small caption above keeps it identifiable.
	var caption := GameUi.label("", 11, GameUi.MUTED)
	caption.name = node_name + "Caption"
	caption.visible = false
	_fields.add_child(caption)
	var edit := LineEdit.new()
	edit.name = node_name
	edit.placeholder_text = L10n.text(placeholder)
	edit.secret = secret
	edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD if secret else keyboard
	edit.custom_minimum_size = Vector2(260, 44)
	edit.text_submitted.connect(func(_t): _submit_primary())
	edit.text_changed.connect(func(_t): _sync_caption(edit))
	edit.set_meta("caption", caption)
	_fields.add_child(edit)
	_field_list.append(edit)
	return edit

func _sync_caption(edit: LineEdit) -> void:
	var caption: Label = edit.get_meta("caption")
	caption.text = edit.placeholder_text
	caption.visible = edit.visible and not edit.text.is_empty()

func _option(node_name: String, labels: Array, parent: Control = null) -> OptionButton:
	var o := OptionButton.new()
	o.name = node_name
	o.custom_minimum_size = Vector2(0, 44)
	o.focus_mode = Control.FOCUS_NONE
	o.fit_to_longest_item = false
	for label in labels: o.add_item(L10n.text(str(label)))
	GameUi.register_modal(o.get_popup())
	if parent == null:
		_fields.add_child(o)
		_field_list.append(o)
	else:
		parent.add_child(o)
	return o

## 状态切换：显示哪些输入框、标题文案、按钮列表。
func set_mode(next: String) -> void:
	mode = next
	_status.text = ""
	_status.visible = false
	_status.add_theme_color_override("font_color", GameUi.CORAL)
	_email.editable = mode in ["sign_in", "sign_up", "forgot"]
	_password.placeholder_text = L10n.text("Password (8+ characters)" if mode == "sign_up" else "Current password" if mode == "password" else "Password")
	_new_password.placeholder_text = L10n.text("New password (8+ characters)")
	_confirm_password.placeholder_text = L10n.text("Confirm new password" if mode in ["forgot", "password"] else "Confirm password")
	var account := Net.account if Net else AccountSession.new()
	for f in [_password, _new_password, _confirm_password]: _sync_caption(f)
	match mode:
		"sign_in":
			_show([_email, _password, _show_passwords])
			_texts("Sign in", reason if not reason.is_empty() else "Sign in with your email to keep your farm on every device.")
			_set_actions(_with_apple([["sign_in", "Sign in", "accent"], ["to_sign_up", "Create an account"], ["to_forgot", "Forgot password?"]]))
		"sign_up":
			_show([_email, _password, _confirm_password, _show_passwords])
			_texts("Create account", reason if not reason.is_empty() else "Your farm is saved to this account.")
			_set_actions(_with_apple([["sign_up", "Create account", "accent"], ["to_sign_in", "I already have an account"]]))
		"forgot":
			if _reset_code_sent:
				_show([_email, _code, _new_password, _confirm_password, _show_passwords])
				_texts("Reset password", "Enter the code from the email and choose a new password.")
				_set_actions([["reset", "Reset password", "accent"], ["to_sign_in", "Back to sign in"], ["resend_reset", "Send a new code"]])
			else:
				_show([_email])
				_texts("Reset password", "We'll email you a 6-digit code.")
				_set_actions([["send_reset", "Send code", "accent"], ["to_sign_in", "Back to sign in"]])
		"verify":
			_show([_code])
			_texts("Verify email", L10n.format_text("We sent a 6-digit code to %s.", account.email))
			_set_actions([["verify", "Verify", "accent"], ["resend_verify", "Send a new code"], ["later", "Later"]])
		"profile":
			_show([_nickname, _gender, _gender_custom, _birthday])
			_fill_profile(account)
			_texts("Your profile", "Pick a nickname. Gender and birthday are optional.")
			var actions := [["save_profile", "Save", "accent"]]
			if from_account: actions.append(["to_account", "Cancel"])
			_set_actions(actions)
		"password":
			_show([_password, _new_password, _confirm_password, _show_passwords])
			_texts("Change password", "You'll stay signed in here. Other devices will be signed out.")
			_set_actions([["change_password", "Change password", "accent"], ["to_account", "Cancel"]])
		"account":
			_show([])
			_texts("My account", _account_summary(account))
			var actions := [["done", "Done", "accent"], ["edit_profile", "Edit profile"]]
			# Apple-only accounts have no password to change; "Forgot password" can add one later.
			if account.has_password: actions.append(["to_password", "Change password"])
			if not account.email_verified and not account.email.is_empty(): actions.append(["start_verify", "Verify email"])
			actions.append(["sign_out", "Sign out"])
			actions.append(["delete", "Delete account", "danger_link"])
			_set_actions(actions)
		"delete":
			_password.text = ""
			_password.placeholder_text = L10n.text("Password")
			if account.has_password:
				_show([_password])
				_texts("Delete account?", "This permanently deletes your account and your farm. Enter your password to confirm.")
			else:
				_show([])
				_texts("Delete account?", "This permanently deletes your account and your farm. This can't be undone.")
			_set_actions([["delete_now", "Delete permanently", "danger"], ["to_account", "Keep my account"]])

func _account_summary(account: AccountSession) -> String:
	var lines := []
	if not account.display_name.is_empty(): lines.append(account.display_name)
	lines.append(account.email if not account.email.is_empty() else L10n.text("Signed in with Apple"))
	var extra := []
	if not account.email.is_empty(): extra.append(L10n.text("Verified" if account.email_verified else "Not verified yet"))
	var g := AccountSession.gender_label(account.gender, account.gender_custom)
	if not g.is_empty(): extra.append(L10n.text(g) if account.gender != "self_describe" else g)
	if account.age >= 0: extra.append(L10n.format_text("Age %d", account.age))
	if not extra.is_empty(): lines.append(" · ".join(extra))
	return "\n".join(lines)

func _fill_profile(account: AccountSession) -> void:
	_nickname.text = account.display_name
	var index := 0
	for i in AccountSession.GENDERS.size():
		if AccountSession.GENDERS[i][0] == account.gender: index = i + 1
	_gender.select(index)
	_gender_custom.text = account.gender_custom
	_gender_custom.visible = account.gender == "self_describe"
	_month.select(0)
	_day.select(0)
	_year.select(0)
	var parts := account.birth_date.split("-")
	if parts.size() == 3:
		_month.select(int(parts[1]))
		_day.select(int(parts[2]))
		for i in _year.item_count:
			if _year.get_item_text(i) == parts[0]: _year.select(i)

func _show(visible_fields: Array) -> void:
	for f in _field_list:
		f.visible = f in visible_fields
		if f is LineEdit: _sync_caption(f)
	if _gender in visible_fields: _gender_custom.visible = _selected_gender() == "self_describe"
	_fields.visible = not visible_fields.is_empty()

func _texts(title: String, subtitle: String) -> void:
	_title.text = L10n.text(title)
	_subtitle.text = L10n.text(subtitle)

## iOS 上登录 / 注册页都给 Apple 登录，紧跟主按钮（App Store 4.8：与其它登录方式同等显眼）。
func _with_apple(list: Array) -> Array:
	if AppleSignIn.available(): list.insert(1, ["apple", "Sign in with Apple", "apple"])
	return list

## 每项 [动作 id, 文案, 样式]：accent 主按钮、danger 红色主按钮、danger_link 红字次按钮。
func _set_actions(list: Array) -> void:
	for c in _actions.get_children():
		_actions.remove_child(c)
		c.queue_free()
	for spec in list:
		var style: String = spec[2] if spec.size() > 2 else ""
		var b := GameUi.button("trash-2" if style == "danger_link" else "", L10n.text(spec[1]), "", style == "accent")
		b.name = spec[0]
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 48 if style in ["accent", "danger"] else 44
		if style == "danger": _paint_danger(b)
		if style == "apple":
			b.custom_minimum_size.y = 48
			_paint_solid(b, Color.BLACK)
		if style == "danger_link": b.add_theme_color_override("font_color", GameUi.CORAL)
		b.pressed.connect(_on_action.bind(str(spec[0])))
		_actions.add_child(b)

## 删除确认的主按钮是珊瑚红，不能和"注册 / 登录"用同一种绿色。
func _paint_danger(b: Button) -> void:
	_paint_solid(b, GameUi.CORAL)

## 实心色按钮、白字：删除用珊瑚红，Apple 登录按 Apple 规范用黑色。
func _paint_solid(b: Button, fill: Color) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := GameUi.surface(fill, 10, 14)
		if state == "pressed": style.bg_color = fill.lightened(0.15) if fill.v < 0.2 else fill.darkened(0.12)
		b.add_theme_stylebox_override(state, style)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(color, Color.WHITE)

func action_button(id: String) -> Button:
	return _actions.get_node_or_null(id) as Button

func _submit_primary() -> void:
	if _actions.get_child_count() > 0: _on_action(str(_actions.get_child(0).name))

func _say(message: String, ok := false) -> void:
	_status.text = L10n.text(message)
	_status.visible = not message.is_empty()
	_status.add_theme_color_override("font_color", GameUi.GREEN if ok else GameUi.CORAL)

func _set_busy(value: bool) -> void:
	busy = value
	_close.disabled = value
	for b in _actions.get_children(): (b as Button).disabled = value

func dismiss() -> void:
	if busy: return
	var signed := Net != null and Net.account.signed_in()
	closed.emit(signed)
	queue_free()

func _on_action(id: String) -> void:
	if busy: return
	match id:
		"sign_in": await _submit_login(false)
		"apple": await _submit_apple()
		"sign_up": await _submit_login(true)
		"to_sign_up": set_mode("sign_up")
		"to_sign_in":
			_reset_code_sent = false
			set_mode("sign_in")
		"to_forgot":
			_reset_code_sent = false
			set_mode("forgot")
		"send_reset", "resend_reset": await _send_reset_code()
		"reset": await _submit_reset()
		"verify": await _submit_verify()
		"resend_verify": await _send_code(Net.account.email, "verify")
		"later": _after_sign_in()
		"save_profile": await _submit_profile()
		"to_account":
			from_account = false
			set_mode("account")
		"change_password": await _submit_password_change()
		"done": dismiss()
		"edit_profile":
			from_account = true
			set_mode("profile")
		"to_password":
			from_account = true
			_password.text = ""
			_new_password.text = ""
			_confirm_password.text = ""
			set_mode("password")
		"start_verify":
			await _send_code(Net.account.email, "verify")
			set_mode("verify")
		"sign_out":
			_set_busy(true)
			await Net.sign_out()
			_set_busy(false)
			dismiss()
		"delete": set_mode("delete")
		"delete_now": await _submit_delete()

## 登录流程收尾：没昵称就先补资料，否则关闭。
func _after_sign_in() -> void:
	if Net.account.profile_complete(): dismiss()
	else:
		from_account = false
		set_mode("profile")

func _selected_gender() -> String:
	var i := _gender.selected
	return "" if i <= 0 else str(AccountSession.GENDERS[i - 1][0])

## 生日三项要么全选要么全空；返回 "YYYY-MM-DD"、"" 或 null（不完整）。
func _selected_birthday() -> Variant:
	var picked := [_month.selected > 0, _day.selected > 0, _year.selected > 0]
	if not picked.has(true): return ""
	if picked.has(false): return null
	return "%s-%02d-%02d" % [_year.get_item_text(_year.selected), _month.selected, _day.selected]

func _submit_login(create: bool) -> void:
	var email := _email.text.strip_edges()
	if not AccountSession.valid_email(email):
		_say("Enter a valid email address.")
		return
	if create and not AccountSession.valid_password(_password.text):
		_say("Use at least 8 characters for your password.")
		return
	if create and _password.text != _confirm_password.text:
		_say(AccountSession.describe("PASSWORD_MISMATCH"))
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
	_confirm_password.text = ""
	if create and not Net.account.email_verified: set_mode("verify")
	else: _after_sign_in()

func _submit_apple() -> void:
	_set_busy(true)
	_say("Signing in…", true)
	var nonce := AppleSignIn.new_nonce()
	var native := await AppleSignIn.authorize(nonce, apple_transport)
	var result := native
	if native.ok:
		result = await AccountSession.apple_sign_in(Net.client, str(native.identity_token), nonce,
			str(native.given_name), str(native.family_name))
		if result.ok: result.ok = await Net.sign_in_with(result.body)
	_set_busy(false)
	if not result.ok:
		_say(AccountSession.describe(str(result.code)))
		return
	_after_sign_in()

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
	if _new_password.text != _confirm_password.text:
		_say(AccountSession.describe("PASSWORD_MISMATCH"))
		return
	_set_busy(true)
	var result := await AccountSession.reset(Net.client, email, _code.text, _new_password.text)
	if result.ok: result.ok = await Net.sign_in_with(result.body)
	_set_busy(false)
	if not result.ok:
		_say(AccountSession.describe(str(result.code)))
		return
	_new_password.text = ""
	_confirm_password.text = ""
	_after_sign_in()

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
	_code.text = ""
	_after_sign_in()

func _submit_profile() -> void:
	var name := _nickname.text.strip_edges()
	if name.length() < 2:
		_say(AccountSession.describe("INVALID_NAME"))
		return
	var gender := _selected_gender()
	if gender == "self_describe" and _gender_custom.text.strip_edges().is_empty():
		_say(AccountSession.describe("INVALID_GENDER"))
		return
	var birthday = _selected_birthday()
	if birthday == null:
		_say("Pick month, day and year, or leave the birthday empty.")
		return
	_set_busy(true)
	var result := await AccountSession.update_profile(Net.client, {"display_name": name, "gender": gender,
		"gender_custom": _gender_custom.text.strip_edges() if gender == "self_describe" else "", "birth_date": birthday})
	_set_busy(false)
	if not result.ok:
		_say(AccountSession.describe(str(result.code)))
		return
	Net.account.adopt(result.body, Net.account_path)
	if from_account:
		from_account = false
		set_mode("account")
		_say("Profile saved.", true)
	else:
		dismiss()

func _submit_password_change() -> void:
	if _password.text.is_empty():
		_say("Enter your password.")
		return
	if not AccountSession.valid_password(_new_password.text):
		_say("Use at least 8 characters for your password.")
		return
	if _new_password.text != _confirm_password.text:
		_say(AccountSession.describe("PASSWORD_MISMATCH"))
		return
	_set_busy(true)
	var result := await AccountSession.change_password(Net.client, _password.text, _new_password.text)
	if result.ok: result.ok = await Net.sign_in_with(result.body)
	_set_busy(false)
	if not result.ok:
		_say(AccountSession.describe(str(result.code)))
		return
	for f in [_password, _new_password, _confirm_password]: f.text = ""
	from_account = false
	set_mode("account")
	_say("Password changed.", true)

func _submit_delete() -> void:
	if Net.account.has_password and _password.text.is_empty():
		_say("Enter your password.")
		return
	_set_busy(true)
	var result := await Net.delete_account(_password.text)
	_set_busy(false)
	if not result.ok:
		_say(AccountSession.describe(str(result.code)))
		return
	dismiss()
