class_name P0AccSignIn
extends P0AccShell
## ACC-SIGNIN (SGODOT-491; 不知火舞's spec v2 §1, the user's q(321) — sign-in a must; 安其拉's row 164 719:201561 /
## 719:201585 / 719:201610 / 719:201641, row 163 715:201422 / 715:201465 / 715:201498): every first launch passes here.
## On ACC-SHELL, the card at 190; no ‹ (Android's Back: the home screen, as the launch's). Its head — the title (XB20)
## and 12 under it the line (Body Bold 14, secondary): a new phone `Sign in to play` / `Your farm is saved to your
## account, so you can keep it on a new phone.`; an old farm on this phone `Keep your farm` / `Sign in to save this farm
## to your account.` Then, 12 under the line, maybe a hint (Caption 12 Bold, text colour; §1.3: the farm's own way in,
## the way last used, or Apple's not on Android yet), and 20 under the head (12 under a hint) the keys, 50 high (as the
## approved Apple / Google ones; 不知火舞 on 497), 12 apart, in `providers`' order: Apple black, Google and email
## outlined with their marks (email's the kit's `@`, SignInButton Provider=Email 9:104976). An Android phone without
## Google Play services has, in Google's place, `Google sign-in isn't available on this phone.` (Caption 12, secondary).
## Last, the test code: the OSS build's outlined secondary key 12 under the keys, the store build's quiet text key
## (Dismiss, 15 Bold secondary) 8 under them. No terms links (AGE agreed). A tap says which (provider_pressed,
## test_code_pressed); the system's sheet, what it finds and a failure's toast are the host's.

signal provider_pressed(provider: String)
signal test_code_pressed

const TITLE := {false: "Sign in to play", true: "Keep your farm"}
const LINE := {false: "Your farm is saved to your account, so you can keep it on a new phone.",
	true: "Sign in to save this farm to your account."}
const NO_GOOGLE := "Google sign-in isn't available on this phone."
const TEST_CODE := "Use a test code"
## §1.3's hints, whole sentences (李白: a sign-in's name never by `%s` — the table's Apple is the fruit).
const FARM_USES := {"apple": "This farm uses Apple sign-in.", "google": "This farm uses Google sign-in.",
	"email": "This farm uses email sign-in."}
const LAST_TIME := {"apple": "You signed in with Apple last time.", "google": "You signed in with Google last time.",
	"email": "You signed in with email last time.", "code": "You signed in with a test code last time."}
const APPLE_NOT_HERE := "This farm uses Apple sign-in, which isn't on Android yet."
const APPLE_ICON := preload("res://assets/ui/icons/brand/apple.svg")
const GOOGLE_ICON := preload("res://assets/ui/icons/brand/google.svg")
const KEYS := {"apple": "Continue with Apple", "google": "Continue with Google", "email": "Continue with email"}
const APPLE_INK := Color("121212")
const TOP := 190.0
const BRAND_KEY_H := 50.0   # a provider's key (the shell's KEY_H is the primary's 48)
const LOGO := 18.0
const GAP := 12.0
const HEAD_GAP := 20.0
const QUIET_GAP := 8.0

var hint: Label
var keys: VBoxContainer
var _hint_gap: Control
var _head_gap: Control

## `providers`: this phone's keys in order — ["apple", "google", "email"] on an iPhone, ["google", "email"] on Android,
## "email" only when the server has it (hello.email); "no_google" stands where Google's key would on an Android phone
## without Google Play services. `returning`: an old farm on this phone (`Keep your farm`). `hint_`: {line: "farm_uses" |
## "last_time", with: "apple" | "google" | "email" | "code"} (set_hint). `store`: the store build's quiet test-code key.
func _init(providers: Array = ["google"], returning := false, hint_ := {}, store := P0Build.store()) -> void:
	super()
	name = "AccSignIn"
	card_top = TOP
	add_title(str(TITLE[returning]))
	add_gap(GAP)
	add_body(str(LINE[returning]))
	_hint_gap = add_gap(GAP)
	hint = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_TEXT)
	hint.name = "Hint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)
	_head_gap = add_gap(GAP)
	keys = VBoxContainer.new()
	keys.name = "Keys"
	keys.add_theme_constant_override(&"separation", int(GAP))
	col.add_child(keys)
	for p in providers:
		if str(p) == "no_google":
			var none := UiKit.label(NO_GOOGLE, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
			none.name = "NoGoogle"
			none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			keys.add_child(none)
		elif KEYS.has(str(p)): keys.add_child(_key(str(p)))
	if store:
		add_gap(QUIET_GAP)
		var quiet := UiDismissButton.new(TEST_CODE)
		quiet.name = "TestCode"
		quiet.custom_minimum_size.y = UiTokens.SIZE_TOUCH
		quiet.pressed.connect(func(): test_code_pressed.emit())
		col.add_child(quiet)
	else:
		add_gap(GAP)
		var code := UiCommandButton.new(TEST_CODE, UiCommandButton.Kind.SECONDARY)
		code.name = "TestCode"
		code.custom_minimum_size.y = KEY_H
		code.sends = false
		code.activated.connect(func(): test_code_pressed.emit())
		col.add_child(code)
	set_hint(str(hint_.get("line", "")), str(hint_.get("with", "")))

## §1.3's line (the host's, as it learns: claimed's linked, a sign-out's way): "farm_uses" — this farm's way in (Apple's
## on Android: not here yet); "last_time" — the way last used; "" none (the head's 20 to the keys again).
func set_hint(line: String, with: String, os_name := OS.get_name()) -> void:
	var text := ""
	match line:
		"farm_uses": text = APPLE_NOT_HERE if with == "apple" and os_name == "Android" else str(FARM_USES.get(with, ""))
		"last_time": text = str(LAST_TIME.get(with, ""))
	hint.text = text
	hint.visible = text != ""
	_hint_gap.visible = hint.visible
	_head_gap.custom_minimum_size.y = GAP if hint.visible else HEAD_GAP

## While the system's sheet is up (the flow's, from a key's tap till the host answers): every key and the test code
## greyed and deaf (no spinner: the sheet is over it), so a second tap opens no second sheet.
var busy := false: set = set_busy
func set_busy(v: bool) -> void:
	busy = v
	for b in keys.get_children() + [col.find_child("TestCode", false, false)]:
		if b is BaseButton: (b as BaseButton).disabled = v
	keys.modulate.a = 0.5 if v else 1.0

## A provider's key, 50 high: its mark (18 in a 20 box; email's the kit's `@`, ExtraBold 18) and its words, centred, 10
## apart; Apple's black with white words, Google's and email's the surface with a 1 px edge.
func _key(provider: String) -> Button:
	var apple := provider == "apple"
	var b := Button.new()
	b.name = provider.capitalize()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = BRAND_KEY_H
	var box := UiStyleBox.make(APPLE_INK if apple else UiTokens.COLOR_SURFACE, BRAND_KEY_H * 0.5,
		APPLE_INK if apple else UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	for state in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]: b.add_theme_stylebox_override(state, box)
	b.pressed.connect(func(): provider_pressed.emit(provider))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ink := Color.WHITE if apple else UiTokens.COLOR_TEXT
	if provider == "email":
		var at := UiKit.label("@", UiTokens.STYLE_TITLE_XB20, ink)
		at.add_theme_font_size_override(&"font_size", 18)
		at.custom_minimum_size = Vector2(20, 20)
		at.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		at.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		at.mouse_filter = Control.MOUSE_FILTER_IGNORE
		at.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		row.add_child(at)
	else:
		var logo := UiKit.icon(APPLE_ICON if apple else GOOGLE_ICON, LOGO)
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(logo)
	var words := UiKit.label(str(KEYS[provider]), UiTokens.STYLE_TITLE_XB20, ink)
	words.add_theme_font_size_override(&"font_size", 15)
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	b.add_child(row)
	return b
