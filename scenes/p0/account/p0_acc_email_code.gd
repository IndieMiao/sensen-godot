class_name P0AccEmailCode
extends P0AccShell
## ACC-EMAIL-CODE (SGODOT-497; 不知火舞's email spec v1 §3 and her six on 497 d9f14578, q(323); 安其拉's row 163:
## cooling down 716:201506, wrong code 717:201503, five tries 717:201550, keyboard 717:201587): after ACC-EMAIL, on
## ACC-SHELL, its card at 190. The ‹ back to ACC-EMAIL with the address kept (Back and `Change email` the same),
## `Check your email`, `We sent a 6-digit code to <the address>.` — the whole address, the text colour, never masked so
## a typo shows; past ADDRESS_MAX its middle goes, its domain kept — 20, six cells, the number keyboard, focused on
## entry. Six digits (typed or pasted) say it at once (entered; no key), the cells locked meanwhile, no spinner.
## Under the cells a 44 row, left: `Resend code in 0:42` (Caption 12, secondary) for 60 s, then `Resend code` (Bold
## 14, info). Above it, when there is one, the red (Caption 12, danger; the six cells' edges red): a wrong code keeps
## its digits, all selected, so the next ones typed replace them, and one changed takes the red away; five tries or an
## expired code grey the cells empty till `Resend code`. Then `Change email`, and `Didn't get it? Check your spam
## folder.` at the card's foot. Nothing here talks to the server: the host asks and answers (code_sent, show_error,
## set_busy).

signal entered(code: String)
signal resend_pressed
signal change_pressed
signal back_pressed

const TITLE := "Check your email"
const SENT := "We sent a 6-digit code to %s."
const WAIT := "Resend code in %s"
const RESEND := "Resend code"
const CHANGE := "Change email"
const SPAM := "Didn't get it? Check your spam folder."
const WRONG := "That code didn't work. %d tries left."
const WRONG_ONE := "That code didn't work. 1 try left."
const SPENT := "Too many tries. Get a new code."
const EXPIRED := "That code has expired. Get a new code."
const DIGITS := 6
const RESEND_S := 60.0
const ADDRESS_MAX := 40   # letters of the address shown whole; past it the middle of its name goes (spec §3)
const TOP := 190.0
const CELL_H := 52.0
const CELL_GAP := 6.0
const CELL_RADIUS := 10.0
const DIGIT_SIZE := 22
const ROW_H := 44.0       # the resend row, fixed so nothing jumps when it turns into the key (d9f14578)
const SMALL_SIZE := 12
const RESEND_SIZE := 14

var email := ""
var input: LineEdit       # one field under the six cells: the keyboard, paste, iOS's code suggestion
var cells: Array[PanelContainer] = []
var digits: Array[Label] = []
var sent_line: RichTextLabel
var red: Label
var red_gap: Control
var wait_line: Label
var resend_key: Button
var change_key: UiDismissButton
var back_key: Button
var left := 0.0           # seconds till `Resend code`
var locked := false       # five tries or expired: grey and empty till a new code
var _wrong := false       # the red on the cells: the digits kept and selected
var _busy := false

func _init(email_ := "", resend_in := RESEND_S) -> void:
	super()
	name = "AccEmailCode"
	email = email_
	card_top = TOP
	add_gap(P0AccEmail.TITLE_TOP - PAD.y)
	add_title(TITLE)
	add_gap(P0AccEmail.GAP)
	sent_line = RichTextLabel.new()
	sent_line.name = "Body"
	sent_line.bbcode_enabled = true
	sent_line.fit_content = true
	sent_line.scroll_active = false
	sent_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sent_line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # its template translated here, the address never
	sent_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sent_line.add_theme_font_override(&"normal_font", UiKit.font(&"bold"))
	sent_line.add_theme_font_size_override(&"normal_font_size", 14)
	sent_line.add_theme_color_override(&"default_color", UiTokens.COLOR_SECONDARY)
	col.add_child(sent_line)
	_write_sent()
	add_gap(P0AccEmail.ROOM)
	col.add_child(_cells())
	add_gap(CELL_GAP)
	red = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_DANGER)
	red.name = "Red"
	red.add_theme_font_size_override(&"font_size", SMALL_SIZE)
	red.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	red.visible = false
	col.add_child(red)
	red_gap = add_gap(CELL_GAP)
	red_gap.visible = false
	var row := _resend_row()
	col.add_child(row)
	keep_above_keyboard = row   # no key here: the cells, the red and Resend stay over the keyboard (不知火舞 11-14, #1057)
	change_key = UiDismissButton.new(CHANGE)
	change_key.name = "Change"
	change_key.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	change_key.pressed.connect(func(): change_pressed.emit())
	col.add_child(change_key)
	add_gap(4)
	var spam := UiKit.label(SPAM, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	spam.name = "Spam"
	spam.add_theme_font_size_override(&"font_size", SMALL_SIZE)
	spam.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spam.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(spam)
	back_key = P0AccEmail.back_key_on(self)
	back_key.pressed.connect(func(): back_pressed.emit())
	code_sent(resend_in)

func _ready() -> void:
	input.grab_focus.call_deferred()   # this page asks one thing: the keyboard up on entry (spec §3)

func _layout() -> void:
	super()
	if back_key: back_key.position = card.position + Vector2(P0AccEmail.BACK_IN, P0AccEmail.BACK_IN)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and sent_line != null: _write_sent()

## The host's: a code went out (on entry, and after `Resend code`) — the cells empty and open, the red gone, `Resend
## code in` from `resend_in` seconds (email_start's resend_in).
func code_sent(resend_in := RESEND_S) -> void:
	_busy = false
	locked = false
	_wrong = false
	input.text = ""
	_set_red("")
	left = maxf(resend_in, 0.0)
	set_process(left > 0.0)
	_paint()
	if is_inside_tree(): input.grab_focus()

## The host's, while sign_in or email_start is out: the cells locked, as they are.
func set_busy(on: bool) -> void:
	_busy = on
	_paint()

## The host's: the no, by its code (contract v1.5; spec §3). `bad_code` {attempts_left} (none left: as five tries),
## `code_expired`, `rate_limited` {retry_in: seconds} (Resend's wait from it), `email_unavailable` /
## `provider_unavailable` (Resend could not send), anything else as the network (the digits kept, one changed sends
## them again).
func show_error(code: String, detail := {}) -> void:
	_busy = false
	match code:
		"bad_code":
			var n := int(detail.get("attempts_left", 1))
			if n <= 0: _lock(SPENT)
			else: _keep_wrong(WRONG_ONE if n == 1 else WRONG % n)
		"code_expired": _lock(EXPIRED)
		"rate_limited":
			var s := float(detail.get("retry_in", RESEND_S))
			_set_red(P0AccEmail.RATE % P0Logic.span(s * 1000.0))
			left = s
			set_process(true)
		"email_unavailable", "provider_unavailable": _set_red(P0AccEmail.UNAVAILABLE)
		_: _keep_wrong(P0AccEmail.OFFLINE)
	_paint()

## The six digits typed so far.
func code() -> String:
	return input.text

func _process(delta: float) -> void:
	tick(delta)

## The wait running down (tests drive it).
func tick(seconds: float) -> void:
	if left <= 0.0: return
	left = maxf(left - seconds, 0.0)
	if left <= 0.0: set_process(false)
	_paint_row()

func _lock(why: String) -> void:
	locked = true
	_wrong = false
	input.text = ""
	_set_red(why)

func _keep_wrong(why: String) -> void:
	_wrong = true
	_set_red(why)
	if is_inside_tree(): input.grab_focus()
	input.select_all()

func _set_red(why: String) -> void:
	red.text = why
	red.visible = why != ""
	red_gap.visible = red.visible

func _on_typed(t: String) -> void:
	var only := ""
	for c in t:   # a paste of `482 719` or `Code: 482719` keeps its digits
		if c >= "0" and c <= "9": only += c
	only = only.left(DIGITS)
	if only != t:
		input.text = only
		input.caret_column = only.length()
	if _wrong or (red.visible and not locked):   # one changed: the red goes (a wait from rate_limited stays in the row)
		_wrong = false
		_set_red("")
	_paint()
	if only.length() == DIGITS and not _busy and not locked:
		_busy = true
		_paint()
		entered.emit(only)

func _on_resend() -> void:
	if _busy or left > 0.0: return
	locked = false
	_wrong = false
	input.text = ""
	_set_red("")
	_busy = true
	_paint()
	resend_pressed.emit()

## `We sent a 6-digit code to %s.`: the template through the table (李白's #1031), the address put in after, in the
## text colour, its brackets kept as letters.
func _write_sent() -> void:
	var shown := short_address(email).replace("[", "[lb]")
	sent_line.text = tr(SENT) % ("[color=#%s]%s[/color]" % [UiTokens.COLOR_TEXT.to_html(false), shown])

## The address as the line shows it: whole up to ADDRESS_MAX letters; past it the middle of its name goes, `…` in its
## place, the domain kept (spec §3: the domain is where a typo is read).
static func short_address(a: String) -> String:
	if a.length() <= ADDRESS_MAX: return a
	var at := a.rfind("@")
	if at <= 0: return a.left(ADDRESS_MAX - 1) + "…"
	var domain := a.substr(at)
	var room := ADDRESS_MAX - domain.length() - 1
	if room < 4: return a.left(ADDRESS_MAX - 1) + "…"
	var head := ceili(room / 2.0)
	var name_ := a.left(at)
	return name_.left(head) + "…" + name_.right(room - head) + domain

func _cells() -> Control:
	var box := Control.new()
	box.name = "Cells"
	box.custom_minimum_size.y = CELL_H
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(CELL_GAP))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(row)
	for i in DIGITS:
		var cell := PanelContainer.new()
		cell.name = "Cell%d" % i
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d := UiKit.label("", UiTokens.STYLE_TITLE_XB20)
		d.add_theme_font_size_override(&"font_size", DIGIT_SIZE)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		d.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cell.add_child(d)
		row.add_child(cell)
		cells.append(cell)
		digits.append(d)
	# Over the cells, unseen: what the keyboard types into, a tap anywhere on them its focus.
	input = LineEdit.new()
	input.name = "Input"
	input.max_length = DIGITS
	input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	input.context_menu_enabled = true   # paste
	input.caret_blink = false
	input.select_all_on_focus = false
	for state in [&"normal", &"focus", &"read_only"]: input.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for c in [&"font_color", &"font_uneditable_color", &"font_selected_color", &"caret_color", &"selection_color", &"font_placeholder_color"]:
		input.add_theme_color_override(c, Color.TRANSPARENT)
	input.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input.text_changed.connect(_on_typed)
	input.focus_entered.connect(_paint)
	input.focus_exited.connect(_paint)
	box.add_child(input)
	return box

func _resend_row() -> Control:
	var row := Control.new()
	row.name = "ResendRow"
	row.custom_minimum_size.y = ROW_H
	wait_line = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	wait_line.name = "Wait"
	wait_line.add_theme_font_size_override(&"font_size", SMALL_SIZE)
	wait_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wait_line.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	row.add_child(wait_line)
	resend_key = Button.new()
	resend_key.name = "Resend"
	resend_key.text = RESEND
	resend_key.flat = true
	resend_key.focus_mode = Control.FOCUS_NONE
	resend_key.alignment = HORIZONTAL_ALIGNMENT_LEFT
	resend_key.add_theme_font_override(&"font", UiKit.font(&"bold"))
	resend_key.add_theme_font_size_override(&"font_size", RESEND_SIZE)
	for state in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		resend_key.add_theme_color_override(state, UiTokens.COLOR_INFO)
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed"]:
		resend_key.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	resend_key.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	resend_key.pressed.connect(_on_resend)
	row.add_child(resend_key)
	return row

func _paint() -> void:
	input.editable = not (_busy or locked)
	var n := input.text.length()
	for i in DIGITS:
		digits[i].text = input.text[i] if i < n else ""
		var fill := UiTokens.COLOR_DISABLED if locked else UiTokens.COLOR_SURFACE
		var edge := UiTokens.COLOR_BORDER
		var width := UiTokens.STROKE_DEFAULT
		if locked: edge = UiTokens.COLOR_DISABLED
		elif _wrong:
			edge = UiTokens.COLOR_DANGER
			width = 2
		elif input.has_focus() and i == mini(n, DIGITS - 1) and n < DIGITS:
			edge = UiTokens.COLOR_PRIMARY
			width = 2
		cells[i].add_theme_stylebox_override(&"panel", UiStyleBox.make(fill, CELL_RADIUS, edge, width).with_margins(0, 0, 0, 0))
	_paint_row()

func _paint_row() -> void:
	var waiting := left > 0.0
	wait_line.visible = waiting
	resend_key.visible = not waiting
	resend_key.disabled = _busy
	if waiting: wait_line.text = WAIT % P0Logic.duration(left * 1000.0)
