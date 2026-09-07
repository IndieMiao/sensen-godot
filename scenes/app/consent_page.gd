extends AppPage
## 条款与隐私同意（R3，08-30 调研 §5.1#2 / §5.2#3）：注册 / 首次发 UGC 前强制同意含"零容忍"条款的 EULA；
## 版本号记录到本地（服务端回写归 D2）；条款改版后重新征求。链接用 OS.shell_open 跳外部浏览器。

var first_run: FirstRun
var auth: AuthSession
var navigate: Callable

var agree: CheckBox
var continue_button: Button

func _init() -> void:
	page_title = "Before you start"

func _build_body() -> void:
	placeholder(tr("This community has zero tolerance for abusive content or behavior. Content you post can be reported and removed, and repeat offenders are banned."))
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 8)
	body.add_child(links)
	var privacy := GameUi.button("book-open", tr("Privacy policy"), LegalLinks.PRIVACY_URL)
	privacy.name = "Privacy"
	privacy.disabled = not LegalLinks.has_privacy()
	privacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	privacy.pressed.connect(func(): LegalLinks.open(LegalLinks.PRIVACY_URL))
	links.add_child(privacy)
	var terms := GameUi.button("book-open", tr("Terms of service"), LegalLinks.TERMS_URL)
	terms.name = "Terms"
	terms.disabled = not LegalLinks.has_terms()
	terms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terms.pressed.connect(func(): LegalLinks.open(LegalLinks.TERMS_URL))
	links.add_child(terms)
	agree = CheckBox.new()
	agree.name = "Agree"
	agree.text = tr("I have read and agree to the Terms of Service and Privacy Policy.")
	agree.focus_mode = Control.FOCUS_NONE
	agree.toggled.connect(func(_on): _refresh())
	body.add_child(agree)
	continue_button = GameUi.button("check", tr("Continue"), "record consent", true)
	continue_button.name = "Continue"
	continue_button.pressed.connect(_on_continue)
	body.add_child(continue_button)
	_refresh()

func _state() -> FirstRun:
	if first_run == null:
		first_run = FirstRun.load_state()
	return first_run

func _session() -> AuthSession:
	return auth if auth != null else Net.auth

func _refresh() -> void:
	continue_button.disabled = not agree.button_pressed

func _on_continue() -> void:
	if not agree.button_pressed:
		return
	_state().record_consent()
	var s := _session()
	var route := AppRoutes.SHELL if (s != null and s.is_signed_in()) else AppRoutes.LOGIN
	if navigate.is_valid():
		navigate.call(route)
	else:
		AppRouter.go_to_route(route)
