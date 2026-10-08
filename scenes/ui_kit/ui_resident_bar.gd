class_name UiResidentBar
extends UiDialogueCard
## Resident dialogue bar (SGODOT-225; ResidentDialogue 1213:83392, LOCK-18). Tapping a resident always opens this
## first: greet, then choose. Half-body portrait + `Name · Role ›` (the portrait and the name open the RES-*
## profile, a secondary page) + affinity stage, meter and progress to the next stage + one line + Gift (primary)
## and Request (secondary); Today’s meal and Recipe lesson only when available.
## A reason on Gift or Request turns the button unavailable with the reason as its label (LOCK-10, e.g.
## `Gift already given today`) and stacks both buttons on full-width rows
## (Choices=Stacked), so the reason fits.
## data: {portrait, name, role, stage, stage_index, have, need, next, line, gift_reason, request_label, request_reason, meal, lesson,
## meal_note}
## (P0Logic.resident_bar builds it from the server view, SGODOT-228; `request_label` defaults to Request.)

signal gift_pressed
signal request_pressed
signal meal_pressed
signal lesson_pressed

const _STAGE_PAD := Vector2(8, 2)    # AffinityMeter row: stage pill padding
const _STAGE_RADIUS := 11.0
const _METER := Vector2(36, 5)       # AffinityMeter 1216:104725: 36 × 5, 10 % steps
const _CHOICE_GAP := 8.0             # Gift ↔ Request, Today’s meal ↔ Recipe lesson

var data := {}

var _gift: UiCommandButton
var _request: UiCommandButton

func _init(data_: Dictionary = {}) -> void:
	super(data_.get("portrait", null), str(data_.get("name", "")), str(data_.get("role", "")), str(data_.get("line", "")))
	data = data_
	portrait_size = RESIDENT_PORTRAIT
	profile_link = true
	if str(data.get("stage", "")) != "": extra.add_child(_affinity())
	var stacked := str(data.get("gift_reason", "")) != "" or str(data.get("request_reason", "")) != ""
	var choices: BoxContainer = VBoxContainer.new() if stacked else HBoxContainer.new()
	choices.add_theme_constant_override(&"separation", int(_CHOICE_GAP if not stacked else UiTokens.SPACE_WITHIN))
	_gift = UiCommandButton.new("Gift", UiCommandButton.Kind.PRIMARY)
	_gift.reason = str(data.get("gift_reason", ""))
	_gift.activated.connect(func(): gift_pressed.emit())
	_request = UiCommandButton.new(str(data.get("request_label", "Request")), UiCommandButton.Kind.SECONDARY)
	_request.reason = str(data.get("request_reason", ""))
	_request.activated.connect(func(): request_pressed.emit())
	for b in [_gift, _request]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.fit_text = stacked   # a long reason fills the row, as on NPC-5
		choices.add_child(b)
	content.add_child(choices)
	var today := HBoxContainer.new()
	today.add_theme_constant_override(&"separation", int(_CHOICE_GAP))
	if bool(data.get("meal", false)):
		var meal := UiNavButton.new("Today’s meal", true)
		meal.pressed.connect(func(): meal_pressed.emit())
		today.add_child(meal)
	if bool(data.get("lesson", false)):
		var lesson := UiNavButton.new("Recipe lesson", true)
		lesson.pressed.connect(func(): lesson_pressed.emit())
		today.add_child(lesson)
	if today.get_child_count() > 0: content.add_child(today)
	else: today.free()
	if str(data.get("meal_note", "")) != "":   # e.g. `Bag full · free a slot for Pip's meal` (SGODOT-228)
		var note := UiKit.label(str(data.meal_note), UiTokens.STYLE_C10_B, UiTokens.COLOR_WARNING)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(note)

## The affinity stage's tone, by its place in content affinity.stages (用户 on 225 验收; 不知火舞's palette, 197 / 225):
## [fill, ink]. The bar's stage pill and the profile's StateBadge read the same table; no edge, sizes as they were.
## Kindred's ink is text, not goldInk (3.6:1 on gold). The meter keeps its own fill: the pill says the stage.
const STAGE_TONES := [
	[UiTokens.COLOR_TILE_CORE, UiTokens.COLOR_SECONDARY],             # Stranger
	[UiTokens.COLOR_PRIMARY_TINT, UiTokens.COLOR_PRIMARY],            # Acquainted
	[UiTokens.COLOR_ROLE_TACKLE_TINT, UiTokens.COLOR_ROLE_TACKLE],    # Familiar
	[UiTokens.COLOR_ROLE_MARKET_TINT, UiTokens.COLOR_ROLE_MARKET],    # Trusted
	[UiTokens.COLOR_GOLD, UiTokens.COLOR_TEXT],                       # Kindred
]

## A stage index out of the table (unknown) reads as Stranger.
static func stage_tone(index: int) -> Array:
	return STAGE_TONES[index] if index >= 0 and index < STAGE_TONES.size() else STAGE_TONES[0]

## The AffinityMeter row's stage pill (C10 ExtraBold) in its stage's tone.
static func stage_pill(stage: String, index: int) -> PanelContainer:
	var tone := stage_tone(index)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(tone[0], _STAGE_RADIUS)
		.with_margins(_STAGE_PAD.x, _STAGE_PAD.y, _STAGE_PAD.x, _STAGE_PAD.y))
	pill.add_child(UiKit.label(stage, UiTokens.STYLE_C10_XB, tone[1]))
	return pill

## Stage pill · meter · `52/90 · next Trusted`.
func _affinity() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_QUICK_BAR_GAP))
	row.add_child(stage_pill(str(data.stage), int(data.get("stage_index", 0))))
	var meter := _Meter.new()
	meter.progress = progress()
	meter.custom_minimum_size = _METER
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(meter)
	var tail := "%d/%d" % [int(data.get("have", 0)), int(data.get("need", 0))]
	if str(data.get("next", "")) != "": tail += " · next " + str(data.next)
	row.add_child(UiKit.label(tail, UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY))
	return row

## Affinity toward the next stage, floored to 10 % like the AffinityMeter main.
func progress() -> float:
	var need := int(data.get("need", 0))
	if need <= 0: return 1.0
	return clampf(floorf(float(data.get("have", 0)) * 10.0 / float(need)) / 10.0, 0.0, 1.0)

func gift_button() -> UiCommandButton: return _gift
func request_button() -> UiCommandButton: return _request

class _Meter extends Control:
	var progress := 0.0

	func _draw() -> void:
		var r := size.y * 0.5
		draw_style_box(UiStyleBox.make(UiTokens.COLOR_BORDER, UiTokens.RADIUS_TRACK), Rect2(Vector2.ZERO, size))
		if progress > 0.0:
			draw_style_box(UiStyleBox.make(UiTokens.COLOR_PRIMARY, UiTokens.RADIUS_TRACK),
				Rect2(Vector2.ZERO, Vector2(maxf(r * 2.0, size.x * progress), size.y)))
