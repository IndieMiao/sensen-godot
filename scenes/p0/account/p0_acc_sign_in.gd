class_name P0AccSignIn
extends P0AccShell
## ACC-SIGNIN (SGODOT-491; 不知火舞's account spec §1.6, q(313); 安其拉's iOS 636:197174 / Android 636:197202): `Already
## have a farm? Sign in` from NAME, on ACC-SHELL, its card at 190. A 44 ‹ in the card's corner (5 in) back to NAME (the
## Android Back the same: P0AccFlow.back), `Sign in to your farm` (left), and the platform's keys, 50 high, 12 apart, the
## brand marks from assets/ui/icons/brand: iPhone `Continue with Apple` (black, first, never smaller — Apple's HIG) and
## `Continue with Google` (outlined); Android Google's alone. An Android phone without Google Play services has no key,
## only `Sign-in isn't available on this phone.` A tap says which (provider_pressed); the system's sign-in sheet and
## what it finds are the host's.

signal provider_pressed(provider: String)
signal back_pressed

const TITLE := "Sign in to your farm"
const NONE := "Sign-in isn't available on this phone."
const APPLE_ICON := preload("res://assets/ui/icons/brand/apple.svg")
const GOOGLE_ICON := preload("res://assets/ui/icons/brand/google.svg")
const KEYS := {"apple": ["Continue with Apple", APPLE_ICON], "google": ["Continue with Google", GOOGLE_ICON]}
const APPLE_INK := Color("121212")
const TOP := 190.0
const BACK_SIDE := 44.0
const BACK_IN := 5.0
const TITLE_TOP := 58.0   # the title's top from the card's (636:197174)
const BRAND_KEY_H := 50.0   # a provider's key (the shell's KEY_H is the primary's 48)
const LOGO := 18.0
const GAP := 12.0

var back_key: Button

## `providers`: the keys this phone offers, in order — ["apple", "google"] on an iPhone, ["google"] on Android, [] with
## no Google Play services.
func _init(providers: Array = ["google"]) -> void:
	super()
	name = "AccSignIn"
	card_top = TOP
	add_gap(TITLE_TOP - PAD.y)   # the title under the ‹
	add_title(TITLE)
	if providers.is_empty():
		add_gap(GAP)
		add_body(NONE).name = "None"
	for p in providers:
		if not KEYS.has(str(p)): continue
		add_gap(GAP)
		col.add_child(_key(str(p)))
	back_key = Button.new()
	back_key.name = "Back"
	back_key.text = "‹"
	back_key.focus_mode = Control.FOCUS_NONE
	back_key.size = Vector2(BACK_SIDE, BACK_SIDE)
	back_key.add_theme_font_override(&"font", UiKit.font(&"extrabold"))
	back_key.add_theme_font_size_override(&"font_size", 24)
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		back_key.add_theme_color_override(state, UiTokens.COLOR_TEXT)
	var round := UiStyleBox.make(UiTokens.COLOR_SURFACE, BACK_SIDE * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	for state in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]: back_key.add_theme_stylebox_override(state, round)
	back_key.pressed.connect(func(): back_pressed.emit())
	add_child(back_key)

func _layout() -> void:
	super()
	if back_key: back_key.position = card.position + Vector2(BACK_IN, BACK_IN)

## A provider's key: its mark (18 in a 20 box) and its words, centred, 10 apart; Apple's black with white words,
## Google's the surface with a 1 px edge.
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
	var logo := UiKit.icon(KEYS[provider][1], LOGO)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(logo)
	var words := UiKit.label(str(KEYS[provider][0]), UiTokens.STYLE_TITLE_XB20, Color.WHITE if apple else UiTokens.COLOR_TEXT)
	words.add_theme_font_size_override(&"font_size", 15)
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	b.add_child(row)
	return b
