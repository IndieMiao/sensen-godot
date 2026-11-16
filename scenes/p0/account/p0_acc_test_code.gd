extends P0AccShell
## q(322), ACC-TESTCODE row162: code input only. The host owns session/code and consent; never log the code.
signal submitted(code: String)
signal back_pressed
const TITLE := "Enter your test code"
const BODY := "Only for testers and app reviewers."
const PLACEHOLDER := "XXXX-XXXX-XXXX"
const BAD := "That code didn't work. Check it and try again."
const RATE := "Too many tries. Wait a minute and try again."
const OFFLINE := "Check your connection and try again."
const FAILED := "Didn't go through · try again"
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const LENGTH := 12
var field: UiTextField
var go: UiCommandButton
var back_key: Button
var busy := false
var authenticated := false # after session/code succeeds, Continue only retries consent; the verified code stays fixed
var _accepted := ""
var _why := ""
var _refused := false

func _init() -> void:
	super()
	name = "AccTestCode"
	card_top = 190.0
	add_gap(58.0 - PAD.y)
	add_title(TITLE)
	add_gap(12)
	add_body(BODY)
	add_gap(20)
	field = UiTextField.new("", PLACEHOLDER, "")
	field.input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	field.input.add_theme_color_override(&"font_uneditable_color", UiTokens.COLOR_TEXT)   # verified code stays readable while consent retries
	field.text_changed.connect(_typed)
	field.submitted.connect(func(_s: String): _submit())
	col.add_child(field)
	add_gap(20)
	go = add_primary("Continue")
	go.activated.connect(_submit)
	back_key = _back_button()
	back_key.pressed.connect(func(): if not busy: back_pressed.emit())
	_refresh()

func _layout() -> void:
	super()
	if back_key: back_key.position = card.position + Vector2(5, 5)

static func canonical(text: String) -> String:
	var result := ""
	for c in text.to_upper():
		if c in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ":
			result += "1" if c in "IL" else "0" if c == "O" else c
	return result

static func formatted(code: String) -> String:
	var out := ""
	for i in code.length():
		if i > 0 and i % 4 == 0: out += "-"
		out += code[i]
	return out

static func valid(code: String) -> bool:
	if code.length() != LENGTH: return false
	for c in code:
		if not c in ALPHABET: return false
	return true

func entered() -> String: return canonical(field.text)

func _typed(text: String) -> void:
	if busy or authenticated:
		field.text = _accepted
		return
	var raw_caret := field.input.caret_column
	var count := canonical(text.substr(0, raw_caret)).length()
	var code := canonical(text)
	# Do not silently turn an overlong paste into a different valid credential.
	if code.length() > LENGTH:
		field.text = _accepted
		field.input.caret_column = mini(raw_caret, _accepted.length())
		field.set_error(_why)
		return
	# Backspacing a separator removes the preceding digit instead of trapping the caret at a reinserted dash.
	if code == canonical(_accepted) and text.length() == _accepted.length() - 1 and raw_caret < _accepted.length() \
		and _accepted[raw_caret] == "-" and count > 0:
		code = code.substr(0, count - 1) + code.substr(count)
		count -= 1
	var changed := code != canonical(_accepted)
	_accepted = formatted(code)
	field.text = _accepted
	field.input.caret_column = mini(count + maxi(0, count - 1) / 4, _accepted.length())
	if changed:
		_why = ""
		_refused = false
	field.set_error(_why)
	_refresh()

func mark_authenticated() -> void:
	authenticated = true
	_refresh()

func set_busy(on: bool) -> void:
	busy = on
	_refresh()

func refuse(reply: Dictionary) -> void:
	busy = false
	var code := str(reply.get("code", "service"))
	_why = BAD if code == "bad_code" else RATE if code == "rate_limited" else OFFLINE if code == "network" else FAILED
	_refused = code == "bad_code"
	field.set_error(_why)
	_refresh()

func _refresh() -> void:
	go.disabled = busy or _refused or not valid(entered())
	field.input.editable = not busy and not authenticated
	back_key.disabled = busy
	field.helper_line.visible = _why != ""

func _submit() -> void:
	if go.disabled or busy: return
	set_busy(true)
	submitted.emit(entered())

func _back_button() -> Button:
	var b := Button.new()
	b.name = "Back"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(44, 44)
	b.size = Vector2(44, 44)
	var style := UiStyleBox.make(UiTokens.COLOR_SURFACE, 22, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(0, 0, 0, 0)
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]: b.add_theme_stylebox_override(state, style)
	var glyph := UiKit.label("‹", UiTokens.STYLE_TITLE_XB20)
	glyph.add_theme_font_size_override(&"font_size", 24)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(glyph)
	add_child(b)
	return b
