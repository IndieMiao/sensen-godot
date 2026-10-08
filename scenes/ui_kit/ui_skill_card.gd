class_name UiSkillCard
extends BaseButton
## Profile skill ring (SGODOT-225; SkillRing 1251:109246, LOCK-22): a raised card with a 40 ring (progress to the
## next level, floored to 10 % like the main's Progress variants), the skill icon on a cream core, the skill name
## and `Lv3`. The three cards sit in one row on the profile; tapping one opens that skill's details (`pressed`).

# SkillRing main (WP1b, not exported as tokens yet; see UiTokens.PENDING "wp1b"):
const _SIZE := Vector2(107, 56)
const _RADIUS := 10.0
const _RING := 40.0
const _RING_AT := Vector2(8, 8)
const _INNER := 0.85          # ring inner radius ratio → a 3 px stroke on 40
const _CORE := 32.0
const _ICON := 20.0
const _TEXT_X := 56.0

var skill := "": set = set_skill
var level := 1: set = set_level
var progress := 0.0: set = set_progress
var icon: Texture2D: set = set_icon

var _ring: _Ring
var _icon: TextureRect
var _name: Label
var _level: Label

func _init(skill_ := "", level_ := 1, progress_ := 0.0, icon_: Texture2D = null) -> void:
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = _SIZE
	var bg := Panel.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _RADIUS))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_ring = _Ring.new()
	_ring.card = self
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.position = _RING_AT
	_ring.size = Vector2(_RING, _RING)
	add_child(_ring)
	_icon = UiKit.icon(null, _ICON)
	_icon.position = Vector2(_RING - _ICON, _RING - _ICON) * 0.5
	_icon.size = Vector2(_ICON, _ICON)
	_ring.add_child(_icon)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 2)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = _TEXT_X
	add_child(col)
	_name = UiKit.label("", UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	col.add_child(_name)
	_level = UiKit.label("", UiTokens.STYLE_C12_XB)
	col.add_child(_level)
	skill = skill_
	level = level_
	progress = progress_
	icon = icon_

func set_skill(v: String) -> void: skill = v; if _name: _name.text = v
func set_level(v: int) -> void: level = v; if _level: _level.text = "Lv%d" % v
func set_icon(v: Texture2D) -> void: icon = v; if _icon: _icon.texture = v
func set_progress(v: float) -> void:
	progress = v
	if _ring: _ring.queue_redraw()

## Ring fill: progress floored to 10 %.
func shown_progress() -> float: return floorf(clampf(progress, 0.0, 1.0) * 10.0) / 10.0

class _Ring extends Control:
	var card: UiSkillCard

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		var t := r * (1.0 - UiSkillCard._INNER)
		draw_arc(c, r - t * 0.5, 0.0, TAU, 64, UiTokens.COLOR_BORDER, t, true)
		var p := card.shown_progress()
		if p > 0.0:
			draw_arc(c, r - t * 0.5, -PI * 0.5, -PI * 0.5 + TAU * p, maxi(8, int(64 * p)), UiTokens.COLOR_PRIMARY, t, true)
		draw_circle(c, UiSkillCard._CORE * 0.5, UiTokens.COLOR_TILE_CORE, true, -1.0, true)
