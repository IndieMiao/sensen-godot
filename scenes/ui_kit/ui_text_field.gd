class_name UiTextField
extends VBoxContainer
## TextField 9:104839 (Gensen Refactor, E-02; the first launch's NAME, SGODOT-491 — 635:197051 / 635:197082): a label
## (Bold 12, secondary), 6, a 48 field (surface, radius 12, 14 in, Bold 15; its placeholder secondary), 6, one helper
## line (Bold 12, secondary). Its edge: border 1; focused, primary 2; an error, danger 2 with the reason in danger on
## the helper line, in place of the helper (no line added) — till the text changes, then the helper again.
## `max_graphemes`: a cap counted in what the eye calls letters (a grapheme cluster: 👍🏽, é as e + ◌́), not code
## points; past it nothing more goes in.

signal text_changed(text: String)
signal submitted(text: String)

const FIELD_H := 48.0
const RADIUS := 12.0
const PAD_X := 14
const GAP := 6
const TEXT_SIZE := 15
const SMALL_SIZE := 12

var input: LineEdit
var label: Label
var helper_line: Label
var helper := ""
var error := ""
var max_graphemes := 0
var _kept := ""

func _init(label_ := "", placeholder := "", helper_ := "") -> void:
	name = "TextField"
	helper = helper_
	add_theme_constant_override(&"separation", GAP)
	label = _small(label_)
	label.name = "Label"
	label.visible = label_ != ""
	add_child(label)
	input = LineEdit.new()
	input.name = "Input"
	input.placeholder_text = placeholder
	input.custom_minimum_size.y = FIELD_H
	input.add_theme_font_override(&"font", UiKit.font(&"bold"))
	input.add_theme_font_size_override(&"font_size", TEXT_SIZE)
	input.add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT)
	input.add_theme_color_override(&"font_placeholder_color", UiTokens.COLOR_SECONDARY)
	input.add_theme_color_override(&"caret_color", UiTokens.COLOR_PRIMARY)
	input.select_all_on_focus = false
	input.text_changed.connect(_on_changed)
	input.text_submitted.connect(func(t: String): submitted.emit(t))
	input.focus_entered.connect(_restyle)
	input.focus_exited.connect(_restyle)
	add_child(input)
	helper_line = _small(helper_)
	helper_line.name = "Helper"
	helper_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(helper_line)
	_restyle()

var text: String:
	get: return input.text
	set(v):
		input.text = v
		_kept = v

## The reason in red under the field, its edge red, till the text changes ("" clears it).
func set_error(reason: String) -> void:
	error = reason
	_restyle()

## How many letters the eye counts in `s`.
static func graphemes(s: String) -> int:
	if s.is_empty(): return 0
	return TextServerManager.get_primary_interface().string_get_character_breaks(s).size()

func _on_changed(t: String) -> void:
	if max_graphemes > 0 and graphemes(t) > max_graphemes:   # one more than it takes: put the last text back
		var at := input.caret_column - (t.length() - _kept.length())
		input.text = _kept
		input.caret_column = clampi(at, 0, _kept.length())
		return
	_kept = t
	if error != "": set_error("")
	text_changed.emit(t)

func _restyle() -> void:
	var bad := error != ""
	var on := input.has_focus()
	var edge := UiTokens.COLOR_DANGER if bad else (UiTokens.COLOR_PRIMARY if on else UiTokens.COLOR_BORDER)
	var sb := UiStyleBox.make(UiTokens.COLOR_SURFACE, RADIUS, edge, 2 if bad or on else UiTokens.STROKE_DEFAULT) \
		.with_margins(PAD_X, 0, PAD_X, 0)
	for state in [&"normal", &"focus", &"read_only"]: input.add_theme_stylebox_override(state, sb)
	helper_line.text = error if bad else helper
	helper_line.add_theme_color_override(&"font_color", UiTokens.COLOR_DANGER if bad else UiTokens.COLOR_SECONDARY)

static func _small(t: String) -> Label:
	var l := UiKit.label(t, UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	l.add_theme_font_size_override(&"font_size", SMALL_SIZE)
	return l
