class_name P0AccEmail
extends P0AccShell
## ACC-EMAIL (SGODOT-497; 不知火舞's email spec v1 §2, q(323); 安其拉's row 163: empty 715:201534, typed 715:201556,
## rate limited 715:201578): `Continue with email` on Sign in, on ACC-SHELL, its card at 190 as Sign in's. A 44 ‹ in the
## card's corner back to Sign in (the Android Back the same: P0AccFlow.back), `Sign in with email` (left), `We'll email
## you a 6-digit code.`, 20, the field (the NAME / test code field without its label: `you@example.com`, the email
## keyboard, at most 254), 20, the key. The key says what is missing (LOCK-10, as NAME's `Enter a name`): `Enter a
## valid email` (grey) till the address has the server's shape (accounts/email.ts normalizeEmail), then `Continue`; the
## return key the same. Continue says it (submitted, the address trimmed — the server lower-cases it) and the host asks
## P0Session.email_start: meanwhile the key grey, its words kept, no spinner (set_busy). Any address of that shape goes
## on to the code page — the host's code_sent — never a word on whether it has a farm. A no the host passes back
## (show_error) is red under the field, its edge red, the key grey, till one letter changes (spec §2: never a toast).

signal submitted(email: String)
signal back_pressed

const TITLE := "Sign in with email"
const BODY := "We'll email you a 6-digit code."
const PLACEHOLDER := "you@example.com"
const ENTER := "Enter a valid email"
const CONTINUE := "Continue"
## The red, by the server's code (contract v1.5; spec §2). `Try again in` takes a sentence's duration (q(97) ②: `5m`, `1h`).
const RATE := "Too many codes requested. Try again in %s."
const UNAVAILABLE := "We can't send codes right now. Please try again later."
const OFFLINE := "Check your connection and try again."
const MAX_LEN := 254
## The server's shape (normalizeEmail): no spaces, one @, a dot in the domain and two letters after the last one.
const SHAPE := "^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$"
const TOP := 190.0
const TITLE_TOP := 58.0   # the title's top from the card's, under the ‹ (as Sign in's)
const GAP := 12.0         # title → line
const ROOM := 20.0        # line → field → key (spec §2)
const BACK_SIDE := 44.0
const BACK_IN := 5.0

var field: UiTextField
var go: UiCommandButton
var back_key: Button
var _refused := false   # a no from the server shown: the key grey till the address changes
var _busy := false
static var _shape: RegEx

func _init() -> void:
	super()
	name = "AccEmail"
	card_top = TOP
	add_gap(TITLE_TOP - PAD.y)
	add_title(TITLE)
	add_gap(GAP)
	add_body(BODY)
	add_gap(ROOM)
	field = UiTextField.new("", PLACEHOLDER, "")
	field.input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	field.input.max_length = MAX_LEN
	field.text_changed.connect(_on_typed)
	field.submitted.connect(func(_t: String): _on_go())
	col.add_child(field)
	add_gap(ROOM)
	go = add_primary(ENTER)
	go.sends = false
	go.activated.connect(_on_go)
	back_key = back_key_on(self)
	back_key.pressed.connect(func(): back_pressed.emit())
	_refresh()

func _layout() -> void:
	super()
	if back_key: back_key.position = card.position + Vector2(BACK_IN, BACK_IN)

## The address as typed before (back from the code page, `Change email`): in the field as it was.
func prefill(email: String) -> void:
	field.text = email
	_refresh()

## The address as it goes out: its ends' spaces dropped, nothing else (the server normalises).
func entered() -> String:
	return field.text.strip_edges()

static func valid(email: String) -> bool:
	if _shape == null:
		_shape = RegEx.new()
		_shape.compile(SHAPE)
	return email.length() <= MAX_LEN and _shape.search(email) != null

## The host's, while email_start is out: the key grey, its words kept.
func set_busy(on: bool) -> void:
	_busy = on
	_refresh()

## The host's: email_start's no, by its code (contract v1.5) — `rate_limited` {retry_in: seconds}, `email_unavailable`
## and `provider_unavailable` (the switch turned off meanwhile; the host takes the key off Sign in), `schema` (the
## server's shape is this page's: the grey `Enter a valid email`, no red), anything else as the network.
func show_error(code: String, detail := {}) -> void:
	_busy = false
	match code:
		"schema":
			_refresh(true)
			return
		"rate_limited": field.set_error(RATE % P0Logic.span(float(detail.get("retry_in", 60)) * 1000.0))
		"email_unavailable", "provider_unavailable": field.set_error(UNAVAILABLE)
		_: field.set_error(OFFLINE)
	_refused = true
	_refresh()

func _on_typed(_t: String) -> void:
	_refused = false
	_refresh()

func _refresh(bad_shape := false) -> void:
	var ok := valid(entered()) and not bad_shape
	go.label = CONTINUE if ok else ENTER
	go.disabled = _busy or _refused or not ok
	field.helper_line.visible = field.error != ""   # no helper here: the line only for the red

func _on_go() -> void:
	if go.disabled: return
	_busy = true
	_refresh()
	submitted.emit(entered())

## Sign in's ‹ (P0AccSignIn): 44 round, the surface with a 1 px edge, `‹` 24 in its middle; laid in the card's corner
## by the page (BACK_IN).
static func back_key_on(page: Control) -> Button:
	var b := Button.new()   # no text of its own: a glyph's line would stretch the button past 44
	b.name = "Back"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(BACK_SIDE, BACK_SIDE)
	b.size = Vector2(BACK_SIDE, BACK_SIDE)
	var round := UiStyleBox.make(UiTokens.COLOR_SURFACE, BACK_SIDE * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(0, 0, 0, 0)
	for state in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed", &"disabled"]: b.add_theme_stylebox_override(state, round)
	var glyph := UiKit.label("‹", UiTokens.STYLE_TITLE_XB20)
	glyph.name = "Glyph"
	glyph.add_theme_font_size_override(&"font_size", 24)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(glyph)
	page.add_child(b)
	return b
