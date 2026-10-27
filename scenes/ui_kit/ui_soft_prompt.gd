class_name UiSoftPrompt
extends PanelContainer
## SoftPrompt 9:104997 (NOTIF-ASK 9:119628; q(235), q(236) ④, SGODOT-350): the game's own ask before the system's
## notification dialog. Cream surface, 1 px border, radius 18, padding 16 / 14; a 40 disc (primary tint) with the 22 px
## bell, 12 before the ExtraBold 15 question; 12 under it two CommandButtons 10 apart sharing the width — `Not now`
## (secondary) and `Allow` (primary). 328 wide. Its owner places it (under the HUD, x16 y108) and keeps it until
## answered; it never closes by itself and does not block the scene around it.
## Comes in fading and sliding down 12 over MOTION_DRAWER_MS ease-out; goes out fading over MOTION_DISSOLVE_MS
## (不知火舞 350 7bffafd7). The shadow is lighter than the main's literal 20 %, as UiTipCard's, for Godot's spread.

signal answered(allow: bool)

const WIDTH := 328.0
const _PAD_X := 16.0
const _PAD_Y := 14.0
const _GAP := 12
const _BUTTON_GAP := 10
const _RADIUS := 18.0
const _DISC := 40.0
const _ICON := 22.0
const _SLIDE := 12.0
const _SHADOW := Color(UiTokens.COLOR_TEXT, 0.1)
const _SHADOW_BLUR := 14.0
const _SHADOW_OFFSET := Vector2(0, 10)
const ICON_BELL := preload("res://assets/p0/icons/bell.svg")

var question := "": set = set_question
var not_now: UiCommandButton
var allow: UiCommandButton
var _text: Label
var _tween: Tween

func _init(question_ := "") -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT).with_margins(_PAD_X, _PAD_Y, _PAD_X, _PAD_Y)
	box.shadow_color = _SHADOW
	box.shadow_size = int(_SHADOW_BLUR)
	box.shadow_offset = _SHADOW_OFFSET
	add_theme_stylebox_override(&"panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", _GAP)
	add_child(column)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", _GAP)
	column.add_child(top)
	var disc := PanelContainer.new()
	disc.custom_minimum_size = Vector2(_DISC, _DISC)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, _DISC * 0.5))
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(disc)
	var icon := UiKit.icon(ICON_BELL, _ICON)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_child(icon)
	_text = UiKit.label("", UiTokens.STYLE_ROW_TITLE_XB15)
	_text.name = "Question"
	_text.add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", _BUTTON_GAP)
	column.add_child(buttons)
	not_now = UiCommandButton.new("Not now", UiCommandButton.Kind.SECONDARY)
	not_now.name = "NotNow"
	allow = UiCommandButton.new("Allow", UiCommandButton.Kind.PRIMARY)
	allow.name = "Allow"
	for b in [not_now, allow]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(b)
	not_now.pressed.connect(func(): answered.emit(false))
	allow.pressed.connect(func(): answered.emit(true))
	minimum_size_changed.connect(_fit)
	set_question(question_)

func set_question(v: String) -> void:
	question = v
	if _text: _text.text = v
	_fit()

## Back to its content: the question first measured at zero width wraps a word a line, and a card outside a container
## never shrinks by itself (as P0Ui.show_moment's).
func _fit() -> void:
	size = Vector2(WIDTH, get_combined_minimum_size().y)

## In at `at` (its resting top-left): from 12 higher and clear.
func come_in(at: Vector2) -> void:
	_stop()
	position = at - Vector2(0, _SLIDE)
	modulate.a = 0.0
	_tween = create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "position", at, UiTokens.MOTION_DRAWER_MS / 1000.0)
	_tween.tween_property(self, "modulate:a", 1.0, UiTokens.MOTION_DRAWER_MS / 1000.0)

## Out, then freed.
func go_out() -> void:
	_stop()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b in [not_now, allow]: b.disabled = true
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, UiTokens.MOTION_DISSOLVE_MS / 1000.0)
	_tween.tween_callback(queue_free)

func _stop() -> void:
	if _tween and _tween.is_valid(): _tween.kill()
