class_name UiFarmCard
extends BaseButton
## Farm overview on the profile (SGODOT-225; "Farm overview" of PROFILE-1, LOCK-22): a 62 thumbnail of the farm,
## its name, `Level 1` (plus `· Friends only` on the full profile) and one status line (`Radishes ready 3h 32m`).
## On someone else's profile it leads to Visit farm (WP5); on your own it opens HOME-1 (`pressed` is left to the
## caller). `chevron` puts a › at the right when the card leads somewhere.

# Farm overview block of PROFILE-1 (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _H := 76.0
const _RADIUS := 12.0
const _THUMB := 62.0
const _THUMB_RADIUS := 10.0
const _PAD := 7.0
const _TEXT_X := 80.0
const _CHEVRON_W := 12.0

var thumb: Texture2D: set = set_thumb
var title := "": set = set_title
var level_line := "": set = set_level_line
var status := "": set = set_status
var chevron := false: set = set_chevron

var _thumb: TextureRect
var _title: Label
var _level: Label
var _status: Label
var _col: VBoxContainer
var _chevron: Label

func _init(title_ := "", level_line_ := "", status_ := "", thumb_: Texture2D = null) -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.y = _H
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _RADIUS))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	frame.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_TILE_CORE, _THUMB_RADIUS))
	frame.position = Vector2(_PAD, _PAD)
	frame.size = Vector2(_THUMB, _THUMB)
	add_child(frame)
	_thumb = TextureRect.new()
	_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(_thumb)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 2)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = _TEXT_X
	col.offset_right = -_PAD
	add_child(col)
	_col = col
	_title = UiKit.label("", UiTokens.STYLE_C12_XB)
	col.add_child(_title)
	_level = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	col.add_child(_level)
	_status = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(_status)
	_chevron = UiKit.label("›", UiTokens.STYLE_C13_XB, UiTokens.COLOR_SECONDARY)   # as UiNoticeRow's
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chevron.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_chevron.offset_left = -_PAD - _CHEVRON_W
	_chevron.offset_right = -_PAD
	_chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_chevron)
	title = title_
	level_line = level_line_
	status = status_
	thumb = thumb_
	chevron = chevron

func set_thumb(v: Texture2D) -> void: thumb = v; if _thumb: _thumb.texture = v
func set_title(v: String) -> void: title = v; if _title: _title.text = v
func set_level_line(v: String) -> void:
	level_line = v
	if _level:
		_level.text = v
		_level.visible = v != ""
func set_status(v: String) -> void:
	status = v
	if _status:
		_status.text = v
		_status.visible = v != ""

func set_chevron(v: bool) -> void:
	chevron = v
	if _chevron == null: return
	_chevron.visible = v
	_col.offset_right = -_PAD - (_CHEVRON_W + _PAD if v else 0.0)   # the status line ends short of the ›
