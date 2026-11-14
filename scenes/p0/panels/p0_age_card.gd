extends UiDrawer
## The 13+ gate before voice (SGODOT-383; q(274) ④, its way still for the user to confirm; 不知火舞's spec 383 6d206dfb
## §7): a bottom card the first time the mic key is tapped. `Voice chat`, then `What year were you born?` over a year
## wheel, and `Continue`, grey until a year is picked. The age is worked out here and only yes / no leaves (answered);
## the year itself is never kept.
## The wheel is UiYearWheel (V5, 383 50108c43), the one the first launch's AGE page turns too (SGODOT-491).

signal answered(ok: bool)

const HEIGHT := 380.0
const YEARS := UiYearWheel.YEARS
const MIN_AGE := 14   # this year less the birth year (the user, 11-02 via 奕星: way (a), the year alone, never under 13)
const TITLE := "Voice chat"
const QUESTION := "What year were you born?"
const CONTINUE := "Continue"
const NEXT := UiYearWheel.NEXT
const STEP := UiYearWheel.STEP

var year: int:          # the year picked, 0 until one is
	get: return wheel.year
var this_year := 0
var go: UiCommandButton
var wheel: UiYearWheel

## `title`: what the gate stands before — `Voice chat` (the mic key), `Voice Profile` (its row on Android, q(281) ④).
func _init(this_year_: int = 0, title_ := TITLE) -> void:
	super(HEIGHT)
	pad = UiTokens.SPACE_PAGE
	wheel = UiYearWheel.new(this_year_)
	this_year = wheel.this_year
	var title := UiKit.label(title_, UiTokens.STYLE_TITLE_XB20)
	title.name = "Title"
	body.add_child(title)
	var ask := UiKit.label(QUESTION, UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
	ask.name = "Question"
	body.add_child(ask)
	body.add_child(_spacer())
	body.add_child(wheel)
	body.add_child(_spacer())
	go = UiCommandButton.new(CONTINUE, UiCommandButton.Kind.PRIMARY)
	go.name = "Continue"
	go.disabled = true
	go.activated.connect(func(): if year > 0: answered.emit(ok_for(year, this_year)))
	body.add_child(go)
	wheel.picked.connect(func(_y: int): go.disabled = false)

func _ready() -> void:
	wheel.animate = animate   # the card laid out at once (tests): the wheel settles at once too
	super()

## Old enough: born MIN_AGE or more years before `now`'s year. A year alone cannot tell a 12-year-old born late in the
## year from a 13-year-old (后裔 on #657), so 14 by the year: everyone it lets through is 13 or more (COPPA's side).
static func ok_for(born: int, now: int) -> bool:
	return now - born >= MIN_AGE

## The year picked: the wheel stops on it and Continue lights.
func pick(y: int) -> void: wheel.pick(y)

## The year in the band now.
func centred() -> int: return wheel.centred()

func _wheel_input(e: InputEvent) -> void: wheel.wheel_input(e)

static func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s
