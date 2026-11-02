extends UiDrawer
## The 13+ gate before voice (SGODOT-383; q(274) ④, its way still for the user to confirm; 不知火舞's spec 383 6d206dfb
## §7): a bottom card the first time the mic key is tapped. `Voice chat`, then `What year were you born?` over a year
## wheel — a scrolling column of years, this year down a hundred, none picked to begin with (the question stays
## neutral: nothing nudges an answer) — and `Continue`, grey until a year is picked. The age is worked out here and
## only yes / no leaves (answered: 13 or more this year); the year itself is never kept.

signal answered(ok: bool)

const HEIGHT := 447.0
const ROW_H := 44.0
const YEARS := 100
const MIN_AGE := 13
const TITLE := "Voice chat"
const QUESTION := "What year were you born?"
const CONTINUE := "Continue"

var year := 0          # the year picked, 0 until one is
var this_year := 0
var go: UiCommandButton
var list: VBoxContainer
var _scroll: TouchScrollContainer

func _init(this_year_: int = 0) -> void:
	super(HEIGHT)
	pad = UiTokens.SPACE_PAGE
	this_year = this_year_ if this_year_ > 0 else int(Time.get_date_dict_from_system().year)
	var title := UiKit.label(TITLE, UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	body.add_child(title)
	var ask := UiKit.label(QUESTION, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	ask.name = "Question"
	body.add_child(ask)
	_scroll = TouchScrollContainer.new()
	_scroll.name = "Wheel"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	list = VBoxContainer.new()
	list.name = "Years"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 0)
	_scroll.add_child(list)
	for k in YEARS: list.add_child(_year_row(this_year - k))
	go = UiCommandButton.new(CONTINUE, UiCommandButton.Kind.PRIMARY)
	go.name = "Continue"
	go.disabled = true
	go.activated.connect(func(): if year > 0: answered.emit(ok_for(year, this_year)))
	body.add_child(go)

## 13 or more in `now`'s year counts as old enough (the spec's rule: the year alone is asked).
static func ok_for(born: int, now: int) -> bool:
	return now - born >= MIN_AGE

func pick(y: int) -> void:
	year = y
	go.disabled = false
	for b in list.get_children(): _paint(b as Button, int((b as Button).get_meta(&"year")) == y)

func _year_row(y: int) -> Button:
	var b := Button.new()
	b.name = "Year_%d" % y
	b.set_meta(&"year", y)
	b.text = str(y)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = ROW_H
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(func(): pick(y))
	_paint(b, false)
	return b

func _paint(b: Button, on: bool) -> void:
	var box := UiStyleBox.make(UiTokens.COLOR_PRIMARY if on else Color.TRANSPARENT, 12.0)
	for s in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]: b.add_theme_stylebox_override(s, box)
	var ink := Color.WHITE if on else UiTokens.COLOR_TEXT
	for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		b.add_theme_color_override(c, ink)
