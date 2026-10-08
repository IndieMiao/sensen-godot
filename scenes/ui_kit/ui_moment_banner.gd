class_name UiMomentBanner
extends PanelContainer
## MomentBanner 1226:104630 (SGODOT-233; §4.8.3 / §4.8.6, q(49) ③④): the heavy result moment under the HUD — a skill
## level-up, HOME-2, a crafted tool. 328 wide, top to bottom:
##   accent  6 px: gold for LEVEL_UP, primary for COMPLETE
##   head    disc 48 (LEVEL_UP: gold with the level number; COMPLETE: primary tint with a check) · title (22 ExtraBold)
##           over the subtitle (13 Bold, secondary)
##   rewards UiFloatText pills, centred (at most three; [] hides the row)
##   detail  13 Bold, centred ("" hides it)
##   tip     12 Bold, secondary, centred ("" hides it)
##   action  one primary CommandButton ("" hides it): only the next step in place, never a jump (LOCK-08)
## The host times it (≤ 3 s, 1.5 s for later levels) and closes it on a tap; it never covers the main key or the bar.

signal action_pressed

enum Kind { LEVEL_UP, COMPLETE }

const WIDTH := 328.0
# MomentBanner main (WP2; not exported as tokens yet, like the RewardMoment's):
const _RADIUS := 20.0
const _ACCENT_H := 6.0
const _GAP := 10.0
const _PAD_X := 16.0
const _PAD_BOTTOM := 14.0
const _HEAD_TOP := 4.0
const _HEAD_GAP := 12.0
const _DISC := 48.0
const _DISC_ICON := 26.0
const _TITLE_GAP := 2.0
const _TITLE_SIZE := 22   # 22 ExtraBold: the Title XB20 style one step up (title and disc number)
const _REWARD_GAP := 8.0
const _SHADOW_SIZE := 14.0
const _SHADOW_Y := 10.0
const CHECK_GLYPH := preload("res://assets/ui/kit_icons/check.svg")

var kind: Kind = Kind.LEVEL_UP: set = set_kind
var level := "": set = set_level
var title := "": set = set_title
var subtitle := "": set = set_subtitle
## Float pills built by the caller (UiFloatText.pill); the banner owns the pills it is given.
var rewards: Array = []: set = set_rewards
var detail := "": set = set_detail
var tip := "": set = set_tip
var action := "": set = set_action

var _accent: ColorRect
var _disc: PanelContainer
var _level: Label
var _check: TextureRect
var _title: Label
var _subtitle: Label
var _rewards: HFlowContainer
var _rewards_box: MarginContainer
var _detail: Label
var _tip: Label
var _action_box: MarginContainer
var _action: UiCommandButton

func _init() -> void:
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_CARD   # Figma 0 10 28 at 20 %; the card shadow token (16 %) like RewardMoment
	box.shadow_size = _SHADOW_SIZE
	box.shadow_offset = Vector2(0, _SHADOW_Y)
	add_theme_stylebox_override(&"panel", box.with_margins(0, 0, 0, _PAD_BOTTOM))
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW   # the accent follows the rounded top
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", int(_GAP))
	add_child(col)
	_accent = ColorRect.new()
	_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_accent.custom_minimum_size.y = _ACCENT_H
	col.add_child(_accent)
	var pad := _pad(_HEAD_TOP)
	col.add_child(pad)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_constant_override(&"separation", int(_HEAD_GAP))
	pad.add_child(head)
	_disc = PanelContainer.new()
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.custom_minimum_size = Vector2(_DISC, _DISC)
	_disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_disc)
	_level = _big("")
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_disc.add_child(_level)
	_check = UiKit.icon(CHECK_GLYPH, _DISC_ICON)
	_check.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_check.self_modulate = UiTokens.COLOR_PRIMARY
	_disc.add_child(_check)
	var titles := VBoxContainer.new()
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	titles.add_theme_constant_override(&"separation", int(_TITLE_GAP))
	head.add_child(titles)
	_title = _big("")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_title)
	_subtitle = UiKit.label("", UiTokens.STYLE_C13_B, UiTokens.COLOR_SECONDARY)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_subtitle)
	# Pills that don't fit one row wrap under it (three item pills with icons are wider than Figma's 79 each);
	# the banner keeps its 328.
	_rewards = HFlowContainer.new()
	_rewards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rewards.alignment = FlowContainer.ALIGNMENT_CENTER
	_rewards.add_theme_constant_override(&"h_separation", int(_REWARD_GAP))
	_rewards.add_theme_constant_override(&"v_separation", int(_REWARD_GAP))
	var rpad := _pad(0.0)
	rpad.add_child(_rewards)
	col.add_child(rpad)
	_rewards_box = rpad
	_detail = _line(UiTokens.STYLE_C13_B, UiTokens.COLOR_TEXT)
	col.add_child(_detail)
	_tip = _line(UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	col.add_child(_tip)
	_action_box = _pad(0.0)
	col.add_child(_action_box)
	_action = UiCommandButton.new("")
	_action.activated.connect(func(): action_pressed.emit())
	_action_box.add_child(_action)
	_refresh()

func set_kind(v: Kind) -> void: kind = v; _refresh()
func set_level(v: String) -> void: level = v; _refresh()
func set_title(v: String) -> void: title = v; _refresh()
func set_subtitle(v: String) -> void: subtitle = v; _refresh()
func set_detail(v: String) -> void: detail = v; _refresh()
func set_tip(v: String) -> void: tip = v; _refresh()
func set_action(v: String) -> void: action = v; _refresh()
func set_rewards(v: Array) -> void:
	for old in rewards:
		if is_instance_valid(old) and not v.has(old): (old as Node).queue_free()
	rewards = v
	if _rewards == null: return
	for c in _rewards.get_children(): _rewards.remove_child(c)
	for p in rewards: _rewards.add_child(p)
	_refresh()

func _refresh() -> void:
	if _accent == null: return
	var up := kind == Kind.LEVEL_UP
	_accent.color = UiTokens.COLOR_QUALITY_GOLD if up else UiTokens.COLOR_PRIMARY
	_disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_QUALITY_GOLD if up else UiTokens.COLOR_PRIMARY_TINT, _DISC * 0.5))
	_level.text = level
	_level.visible = up
	_check.visible = not up
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = subtitle != ""
	_rewards_box.visible = not rewards.is_empty()
	_detail.text = detail
	_detail.visible = detail != ""
	_tip.text = tip
	_tip.visible = tip != ""
	_action.label = action
	_action_box.visible = action != ""

func _pad(top: float) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override(&"margin_left", int(_PAD_X))
	m.add_theme_constant_override(&"margin_right", int(_PAD_X))
	m.add_theme_constant_override(&"margin_top", int(top))
	return m

func _line(style: StringName, color: Color) -> Label:
	var l := UiKit.label("", style, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - _PAD_X * 2.0
	return l

static func _big(text: String) -> Label:
	var l := UiKit.label(text, UiTokens.STYLE_TITLE_XB20)
	l.add_theme_font_size_override(&"font_size", _TITLE_SIZE)
	return l
