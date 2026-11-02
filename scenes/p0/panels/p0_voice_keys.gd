extends Control
## Voice controls in a room (SGODOT-383; q(274); 不知火舞's spec 383 6d206dfb §1–2): under the HUD's second row on the
## right, 16 from the edge, on the Creel pill's line — the space's own layer, not the HUD (LOCK-06 unchanged). Left
## the mic key, a 40 round icon key with no words (as ⇄): off the mic-off icon, secondary on the surface disc; on the
## mic icon, white on the primary disc. Right, 8 apart, the people pill: the map pins' person and how many others are
## in this layer (q(137) ③), the Creel pill's look (UiCreelBadge); a tap opens the layer's people drawer.

signal mic_pressed
signal people_pressed

const SIDE := 40.0
const GAP := 8.0
const ICON := 20.0
const MIC := preload("res://assets/ui/icons/game/mic.svg")
const MIC_OFF := preload("res://assets/ui/icons/game/mic-off.svg")
const PERSON := preload("res://assets/ui/kit_icons/count_person.svg")

var mic: Button
var people: UiCreelBadge
var mic_on := false
var _right := 0.0
var _top := 0.0

func _init() -> void:
	name = "VoiceKeys"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mic = Button.new()
	mic.name = "Mic"
	mic.focus_mode = Control.FOCUS_NONE
	mic.size = Vector2(SIDE, SIDE)
	mic.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mic.add_theme_constant_override(&"icon_max_width", int(ICON))
	mic.pressed.connect(func(): mic_pressed.emit())
	add_child(mic)
	people = UiCreelBadge.new(PERSON)
	people.name = "People"
	people.pressed.connect(func(): people_pressed.emit())
	add_child(people)
	set_mic(false)
	set_count(0)

## The mic as Voice has it now.
func set_mic(on: bool) -> void:
	mic_on = on
	mic.icon = MIC if on else MIC_OFF
	var box := UiStyleBox.make(UiTokens.COLOR_PRIMARY if on else UiTokens.COLOR_SURFACE, SIDE * 0.5,
		Color.TRANSPARENT if on else UiTokens.COLOR_BORDER, 0.0 if on else 1.0)
	for s in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]: mic.add_theme_stylebox_override(s, box)
	var tint := Color.WHITE if on else UiTokens.COLOR_SECONDARY
	for c in [&"icon_normal_color", &"icon_hover_color", &"icon_pressed_color", &"icon_focus_color", &"icon_hover_pressed_color"]:
		mic.add_theme_color_override(c, tint)

## Others in the layer (not counting the player).
func set_count(n: int) -> void:
	people.text = str(n)
	place(_right, _top)   # the pill grows to the left: the row keeps its right edge

## Right-aligned at `right` (the screen's x less 16), the row's top at `top`; the mic key and the pill share its middle.
func place(right: float, top: float) -> void:
	_right = right
	_top = top
	var w := people.get_combined_minimum_size().x
	var h := maxf(SIDE, people.get_combined_minimum_size().y)
	position = Vector2(right - w - GAP - SIDE, top)
	size = Vector2(w + GAP + SIDE, h)
	_layout()

func _layout() -> void:
	var p := people.get_combined_minimum_size()
	var h := maxf(SIDE, p.y)
	mic.position = Vector2(0, (h - SIDE) * 0.5)
	people.position = Vector2(SIDE + GAP, (h - p.y) * 0.5)
	people.size = p
