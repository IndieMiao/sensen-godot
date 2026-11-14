class_name UiYearWheel
extends Control
## The year wheel as 安其拉's V5 has it (383 50108c43, Figma row 124; q(274) 补记二), out of the voice age card
## (SGODOT-383) so the first launch's AGE page (SGODOT-491, 不知火舞's account spec v1 §1.1) turns the same one: years run
## down to this year, a hundred of them; the one in the middle sits on a primary-tint band, large, two either side fade
## out (55 %, 30 %). It opens on this year with nothing picked (the question stays neutral: nothing nudges an answer); a
## drag that settles, a tap on a year or the mouse wheel picks the year it stops on, and says so (picked).

signal picked(year: int)

const YEARS := 100
const BAND_H := 40.0
const NEXT := 26.0       # the band's middle to its neighbours' (V5) …
const STEP := 23.0       # … and on from one neighbour to the next
const SHOWN := 2         # neighbours each side
const WHEEL_H := BAND_H + 2.0 * (NEXT + (SHOWN - 1) * STEP)
const DRAG_SLOP := 6.0
const SETTLE_SECS := 0.15

var year := 0          # the year picked, 0 until one is
var this_year := 0
var at := 0.0          # the wheel's place: the index (0 = a hundred years ago … YEARS − 1 = this year) in the band
## Settles with a short ease; off, a stop picks at once (tests, a card laid out off the tree).
var animate := true
var _labels: Array[Label] = []
var _down := false
var _moved := false
var _down_y := 0.0
var _down_at := 0.0
var _settle: Tween

func _init(this_year_: int = 0) -> void:
	name = "Wheel"
	this_year = this_year_ if this_year_ > 0 else int(Time.get_date_dict_from_system().year)
	at = YEARS - 1
	custom_minimum_size.y = WHEEL_H
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta(UiDrawer.KEEP_INPUT, true)   # its drags turn the wheel, never pull a card down
	gui_input.connect(wheel_input)
	resized.connect(_layout)
	var band := Panel.new()
	band.name = "Band"
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, 12.0))
	band.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
	band.offset_top = -BAND_H * 0.5
	band.offset_bottom = BAND_H * 0.5
	add_child(band)
	for k in SHOWN * 2 + 3:
		var l := UiKit.label("", UiTokens.STYLE_BODY_B14)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(l)
		_labels.append(l)
	_layout()

## The year picked: the wheel stops on it.
func pick(y: int) -> void:
	year = clampi(y, year_at(0), this_year)
	at = index_of(year)
	_layout()
	picked.emit(year)

## Back on `y` with nothing new picked (the AGE page's `Change`: the wheel where it was).
func show_year(y: int) -> void:
	year = clampi(y, year_at(0), this_year)
	at = index_of(year)
	_layout()

func year_at(i: int) -> int: return this_year - (YEARS - 1) + i
func index_of(y: int) -> int: return y - year_at(0)

## The year in the band now.
func centred() -> int: return year_at(clampi(roundi(at), 0, YEARS - 1))

## A row `d` places from the band (fractions while turning): how far its middle is from the band's.
static func offset_of(d: float) -> float:
	var a := absf(d)
	return signf(d) * (a * NEXT if a <= 1.0 else NEXT + (a - 1.0) * STEP)

## And back: the rows from the band a point `dy` from its middle lies.
static func rows_at(dy: float) -> float:
	var a := absf(dy)
	return signf(dy) * (a / NEXT if a <= NEXT else 1.0 + (a - NEXT) / STEP)

func _layout() -> void:
	var mid := size.y * 0.5 if size.y > 0.0 else WHEEL_H * 0.5
	var first := roundi(at) - SHOWN - 1
	for k in _labels.size():
		var l := _labels[k]
		var i := first + k
		var d := float(i) - at
		l.visible = i >= 0 and i < YEARS and absf(d) < SHOWN + 0.6
		if not l.visible: continue
		var band := absf(d) < 0.5
		l.text = str(year_at(i))
		l.theme_type_variation = UiTokens.STYLE_TITLE_XB20 if band else UiTokens.STYLE_BODY_B14
		l.add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT if band else UiTokens.COLOR_SECONDARY)
		var a := absf(d)   # the band's year full, its neighbours 55 %, the next 30 %, then out (V5)
		if band: l.modulate.a = 1.0
		elif a <= 1.0: l.modulate.a = lerpf(1.0, 0.55, a)
		elif a <= 2.0: l.modulate.a = lerpf(0.55, 0.3, a - 1.0)
		else: l.modulate.a = lerpf(0.3, 0.0, (a - 2.0) / 0.6)
		l.size = Vector2(size.x, BAND_H)
		l.position = Vector2(0.0, mid + offset_of(d) - BAND_H * 0.5)

func wheel_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		if e.pressed: _settle_on(roundi(at) + (-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1))
		accept_event()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if e.pressed:
			if _settle: _settle.kill()
			_down = true
			_moved = false
			_down_y = e.position.y
			_down_at = at
			return
		if not _down: return
		_down = false
		# a tap picks the year under it; a drag the one it stops on
		_settle_on(roundi(at) if _moved else roundi(at + rows_at(e.position.y - size.y * 0.5)))
	elif e is InputEventMouseMotion and _down:
		accept_event()
		var dy: float = e.position.y - _down_y
		if absf(dy) > DRAG_SLOP: _moved = true
		if _moved:
			at = clampf(_down_at - dy / STEP, 0.0, YEARS - 1)
			_layout()

func _settle_on(i: int) -> void:
	i = clampi(i, 0, YEARS - 1)
	if _settle: _settle.kill()
	if not is_inside_tree() or not animate:
		pick(year_at(i))
		return
	_settle = create_tween()
	_settle.tween_method(func(v: float):
		at = v
		_layout(), at, float(i), SETTLE_SECS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_settle.tween_callback(func(): pick(year_at(i)))
