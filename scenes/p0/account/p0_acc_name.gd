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
const WORDS_GAP := 4
## The helper line's red, by the server's reasons (name_rejected's `reason`).
const WHY := {"empty": HELPER, "length": HELPER, "chars": "That character can't be used", "blocked": "That name isn't allowed"}
## What a name may be made of, as the server's name.ts has it (周瑜, q(313) ① ②): each letter as the eye counts it starts
## with a letter of the scripts the fonts draw (Latin, Greek, Cyrillic, Han, kana, Hangul), a digit, a space or `-_.'`,
## and carries at most two marks. Caught here as it is typed, never stricter than the server: full-width letters,
## digits and spaces (a Chinese keyboard's) are read as their half-width selves first, as the server's NFKC does. Latin
## with Greek or Cyrillic in one name reads as not allowed, not as a bad character (不知火舞 on 491: each letter alone
## is fine, and the mix is how a name passes for staff). Words and impersonation are the server's alone.
const LETTER := "^[\\p{scx:Latin}\\p{scx:Greek}\\p{scx:Cyrillic}\\p{scx:Han}\\p{scx:Hiragana}\\p{scx:Katakana}\\p{scx:Hangul}]$"
const MARKS_MAX := 2
## Nothing unseen anywhere in a name: Unicode's default-ignorable code points, as name.ts refuses them (周瑜 a395c320a,
## after 11-13: variation selectors, the joiners, Hangul fillers, Mongolian selectors, Khmer's two, the bidi marks …),
## listed (Godot's RegEx has no \p{DI}).
const UNSEEN := "[\\x{00AD}\\x{034F}\\x{061C}\\x{115F}\\x{1160}\\x{17B4}\\x{17B5}\\x{180B}-\\x{180F}\\x{200B}-\\x{200F}\\x{202A}-\\x{202E}\\x{2060}-\\x{206F}\\x{3164}\\x{FE00}-\\x{FE0F}\\x{FEFF}\\x{FFA0}\\x{FFF0}-\\x{FFF8}\\x{1BCA0}-\\x{1BCA3}\\x{1D173}-\\x{1D17A}\\x{E0000}-\\x{E0FFF}]"

## The host's name check: check.call(name, done) and done.call({ok: true} | {ok: false, code, reason?}).
var check := Callable()
var field: UiTextField
var go: UiCommandButton
var skip: UiDismissButton
var sign_in_row: Control
var _rejected := false
var _checking := false
static var _re := {}

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

## The name as it goes out: full-width spaces and ASCII half-width, spaces at its ends dropped, a run of them one (the
## server's normalising does the rest). All spaces is no name: `Enter a name`, nothing sent.
func entered() -> String:
	var n := fold(field.text).strip_edges()
	while n.contains("  "): n = n.replace("  ", " ")
	return n

static func letters(n: String) -> int: return UiTextField.graphemes(n)

## What this phone can tell of a name before the server does: "" (nothing wrong here), "chars" or "blocked" (mixed
## alphabets). LETTER.
static func local_reason(n: String) -> String:
	n = fold(n)
	if _is(n, UNSEEN): return "chars"
	var latin := false
	var other := false   # Greek or Cyrillic
	var from := 0
	for end in TextServerManager.get_primary_interface().string_get_character_breaks(n):
		var g := n.substr(from, end - from)
		from = end
		var base := g.substr(0, 1)
		if _is(base, "^\\p{L}$") and _is(base, LETTER):
			if _is(base, "^\\p{scx:Latin}$"): latin = true
			if _is(base, "^[\\p{scx:Greek}\\p{scx:Cyrillic}]$"): other = true
		elif not _is(base, "^[0-9 \\-_.']$"): return "chars"
		var marks := g.substr(1)
		if marks.length() > MARKS_MAX or (marks != "" and not _is(marks, "^\\p{M}+$")): return "chars"
	return "blocked" if latin and other else ""

## Full-width ASCII and the ideographic space as their half-width selves (what NFKC makes of them).
static func fold(n: String) -> String:
	var out := ""
	for i in n.length():
		var c := n.unicode_at(i)
		if c >= 0xFF01 and c <= 0xFF5E: c -= 0xFEE0
		elif c == 0x3000: c = 0x20
		out += String.chr(c)
	return out

static func _is(s: String, pattern: String) -> bool:
	if not _re.has(pattern):
		var r := RegEx.new()
		r.compile(pattern)
		_re[pattern] = r
	return (_re[pattern] as RegEx).search(s) != null

func _on_typed(t: String) -> void:
	var why := local_reason(t)
	_rejected = why != ""
	if _rejected: field.set_error(str(WHY[why]))
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

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and sign_in_row != null:
		_space_words(sign_in_row.find_child("Words", true, false) as HBoxContainer)

## The question and Sign in 4 apart in English; under 中文 none (不知火舞 on 491: the full-width ？ brings its own half
## a square, and no space between Chinese and Chinese, q(275) ⑦).
static func _space_words(words: HBoxContainer) -> void:
	if words: words.add_theme_constant_override(&"separation", 0 if TranslationServer.get_locale() == "zh_CN" else WORDS_GAP)

## A no from after the check (guest's name_rejected): why, in red, as the check's own no.
func refuse(reason: String) -> void:
	_rejected = true
	field.set_error(str(WHY.get(reason, WHY.blocked)))
	_refresh()

## `Already have a farm? Sign in`: the question secondary, Sign in info, Bold 14, 4 apart (none in 中文), centred; the
## whole row the key (44), under a 1 px line.
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
	words.name = "Words"
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	_space_words(words)
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
