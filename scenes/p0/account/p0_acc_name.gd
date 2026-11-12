class_name P0AccName
extends P0AccShell
## ACC-NAME (SGODOT-491; 不知火舞's account spec §1.5, q(313); 安其拉's 635:197051 / -ERR 635:197082): the first launch's
## name, on ACC-SHELL, 12 between its parts. `What should we call you?` (left), `Shown to other players. You can change
## it every 7 days.` (Bold 14, secondary), the Name field (UiTextField: `Your name`, `2–16 letters or numbers`, at most 16
## letters as the eye counts them), the key, `Skip for now`, a 1 px line, and `Already have a farm? Sign in` (the whole
## row the key; not for an old account, `sign_in_row` false). No ‹: nothing before it to go back to.
## The key says what is missing (q(28)): `Enter a name` (grey) under 2 letters; `Try another name` (grey) while the
## name is refused; `Continue`. Continue (or the keyboard's return) asks `check` (the host's: P0Session's name/check,
## nothing made yet) — grey meanwhile, its words kept, no spinner — and a yes says it (named). A no says why in red on
## the helper line (spec §1.5): too short or long, a character that cannot be used (caught here as it is typed, the
## server deciding last), a name not allowed (words, impersonation, mixed alphabets: the server's alone). One letter
## changed and the red goes. `Skip for now` says it too (named "", true): the default `Traveller 8c3f`, the first rename
## free (the server's). A failed check (the network, rate_limited) says so (failed) and the page stays.

signal named(name: String, skip: bool)
signal sign_in_pressed
signal failed(code: String)

const TITLE := "What should we call you?"
const BODY := "Shown to other players. You can change it every 7 days."
const FIELD := "Name"
const PLACEHOLDER := "Your name"
const HELPER := "2–16 letters or numbers"
const ENTER := "Enter a name"
const RETRY := "Try another name"
const CONTINUE := "Continue"
const SKIP := "Skip for now"
const HAVE_FARM := "Already have a farm?"
const SIGN_IN := "Sign in"
const MIN_LETTERS := 2
const MAX_LETTERS := 16
const GAP := 12.0
## The helper line's red, by the server's reasons (name_rejected's `reason`).
const WHY := {"length": HELPER, "chars": "That character can't be used", "blocked": "That name isn't allowed"}
## What cannot be in a name, caught as it is typed (account plan v2 §名字: no emoji, `@` `#` `/` `:`, nothing unseen —
## control, format, zero-width and bidi marks); the server's name/check decides last and alone on words and alphabets.
const BAD_CHARS := "[@#/:\\p{Cc}\\p{Cf}\\p{So}\\p{Sk}\\p{Co}\\p{Cn}\\x{200B}-\\x{200F}\\x{2028}-\\x{202F}\\x{2060}-\\x{206F}\\x{FE00}-\\x{FE0F}]"

## The host's name check: check.call(name, done) and done.call({ok: true} | {ok: false, code, reason?}).
var check := Callable()
var field: UiTextField
var go: UiCommandButton
var skip: UiDismissButton
var sign_in_row: Control
var _rejected := false
var _checking := false
static var _bad: RegEx

func _init(with_sign_in := true) -> void:
	super()
	name = "AccName"
	add_title(TITLE)
	add_gap(GAP)
	var body := add_body(BODY)
	body.theme_type_variation = UiTokens.STYLE_BODY_B14
	add_gap(GAP)
	field = UiTextField.new(FIELD, PLACEHOLDER, HELPER)
	field.max_graphemes = MAX_LETTERS
	field.text_changed.connect(_on_typed)
	field.submitted.connect(func(_t: String): _on_go())
	col.add_child(field)
	add_gap(GAP)
	go = add_primary(ENTER)
	go.sends = false
	go.activated.connect(_on_go)
	add_gap(GAP)
	skip = UiDismissButton.new(SKIP)
	skip.name = "Skip"
	skip.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	skip.pressed.connect(func(): if not _checking: named.emit("", true))
	col.add_child(skip)
	sign_in_row = _sign_in_row()
	sign_in_row.visible = with_sign_in
	col.add_child(sign_in_row)
	_refresh()

## A name typed before (pending_expired: back from Sign in, spec v1.1): in the field as it was.
func prefill(n: String) -> void:
	field.text = n
	_on_typed(n)

## The name as it goes out: spaces at its ends dropped, a run of them one (the server's normalising does the rest).
func entered() -> String:
	var n := field.text.strip_edges()
	while n.contains("  "): n = n.replace("  ", " ")
	return n

static func letters(n: String) -> int: return UiTextField.graphemes(n)

## A character no name may have (BAD_CHARS).
static func bad_chars(n: String) -> bool:
	if _bad == null:
		_bad = RegEx.new()
		_bad.compile(BAD_CHARS)
	return _bad.search(n) != null

func _on_typed(t: String) -> void:
	_rejected = bad_chars(t)
	if _rejected: field.set_error(WHY.chars)
	_refresh()

func _refresh() -> void:
	var n := entered()
	go.label = ENTER if letters(n) < MIN_LETTERS else (RETRY if _rejected else CONTINUE)
	go.disabled = _checking or letters(n) < MIN_LETTERS or _rejected

func _on_go() -> void:
	if _checking: return
	var n := entered()
	if letters(n) < MIN_LETTERS:   # the grey key tapped on one letter: what is wrong, in red (spec §1.5)
		if letters(n) > 0: field.set_error(WHY.length)
		return
	if _rejected: return
	if not check.is_valid():
		named.emit(n, false)
		return
	_checking = true
	_refresh()
	check.call(n, func(r: Dictionary):
		_checking = false
		if n != entered():   # typed on meanwhile: this answer is for another name
			_refresh()
			return
		if bool(r.get("ok", false)):
			_refresh()
			named.emit(n, false)
		elif str(r.get("code", "")) == "name_rejected":
			_rejected = true
			field.set_error(str(WHY.get(str(r.get("reason", "")), WHY.blocked)))
			_refresh()
		else:
			_refresh()
			failed.emit(str(r.get("code", "network"))))

## `Already have a farm? Sign in`: the question secondary, Sign in info, Bold 14, 4 apart, centred; the whole row the
## key (44), under a 1 px line.
func _sign_in_row() -> Control:
	var box := VBoxContainer.new()
	box.name = "SignInRow"
	box.add_theme_constant_override(&"separation", int(GAP))
	var above := Control.new()   # 12 under Skip, gone with the row (an old account's NAME)
	above.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(above)
	var rule := ColorRect.new()
	rule.color = UiTokens.COLOR_BORDER
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	var row := Button.new()
	row.name = "SignIn"
	row.flat = true
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	for state in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]:
		row.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	row.pressed.connect(func(): if not _checking: sign_in_pressed.emit())
	var words := HBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override(&"separation", 4)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for part in [[HAVE_FARM, UiTokens.COLOR_SECONDARY], [SIGN_IN, UiTokens.COLOR_INFO]]:
		var l := UiKit.label(str(part[0]), UiTokens.STYLE_BODY_B14, part[1])
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		words.add_child(l)
	row.add_child(words)
	box.add_child(row)
	return box
