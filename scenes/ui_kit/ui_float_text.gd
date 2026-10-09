class_name UiFloatText
extends Control
## FloatText 1178:82191 (SGODOT-225, for 亚瑟's float_text in 224; §16.1.2 feedback layer). A soft cream pill
## (82 %) with an optional 14 icon and one ExtraBold 15 line in its tone colour: XP cyan, ENERGY_GAIN green
## (eating, refunds), ENERGY_COST red-orange, COINS gold, AFFINITY rose with a heart (`+2 · first chat today`
## over the resident bar), ITEM ink with the item's icon, MUTED secondary ink for a line that gives nothing
## (`No XP · 3rd today`, `Missed · still cooking`; 不知火舞 on #158: the XP colour reads as a reward). Layout HUG = one line, auto width; WRAP = at most 320
## wide, centred, up to 2 lines, longer copy cut with …. Never takes input.
## play(at, stack_index): `at` is the bottom centre (the caller puts it 40 above the object). Motion (不知火舞
## 2026-10-07, SGODOT-204 c 45754a94) = pop → settle → rise → fade, 1100 ms, pivot bottom centre: ×0.5 → ×1.3 in
## 140 ms (cubic out), → ×1.0 by 700 ms (quad out); rise 48 over 1100 ms (cubic out); fade in over 80 ms, out
## 650 → 1100 ms (quad in). The peak is never wider than 336 (peak = min(×1.3, 336 ÷ width)). stack_index n
## starts 28·n higher and 60·n ms later, at most 3 lines. bump(text) merges an update into a live line: ×1.0 →
## ×1.12 → ×1.0 in 200 ms, the line holds its height and the fade restarts 650 ms after the bump.
## Laid out at the peak size and scaled down, so the ×1.3 peak stays sharp. Emits `finished`, then frees itself.

signal finished

enum Tone { XP, ENERGY_GAIN, ENERGY_COST, COINS, AFFINITY, ITEM, MUTED }
enum Layout { HUG, WRAP }

const HEART := preload("res://assets/ui/kit_icons/heart.svg")

# FloatText main and its motion board (not exported as tokens yet; see UiTokens.PENDING "wp1b"; suggested names
# in SGODOT-204 c 45754a94):
const _BACKING_ALPHA := 0.82    # Soft cream backing
const _RADIUS := 12.0
const _PAD := Vector2(8, 3)
const _ICON := 14.0
const _ICON_GAP := 4.0
const _WRAP_MAX := 320.0        # Layout=Wrap: max width, 2 lines
const _WRAP_LINES := 2
const _PEAK := 1.3              # motion/float/peakScale
const _START := 0.5             # motion/float/startScale
const _PEAK_MAX_W := 336.0      # the peak never wider than this
const _POP_MS := 140.0          # motion/float/popMs
const _SETTLE_MS := 700.0       # motion/float/settleMs (ends at ×1.0)
const _TOTAL_MS := 1100.0       # motion/float/durationMs
const _RISE := 48.0             # motion/float/rise
const _FADE_IN_MS := 80.0
const _FADE_OUT_AT_MS := 650.0
const _STACK_RISE := 28.0       # each extra line starts 28 higher …
const _STACK_DELAY_MS := 60.0   # … and 60 ms later
const _STACK_MAX := 3
const _BUMP := 1.12
const _BUMP_MS := 200.0

const TONE_COLORS := {
	Tone.XP: UiTokens.COLOR_FLOAT_XP, Tone.ENERGY_GAIN: UiTokens.COLOR_FLOAT_ENERGY_GAIN,
	Tone.ENERGY_COST: UiTokens.COLOR_FLOAT_ENERGY_COST, Tone.COINS: UiTokens.COLOR_FLOAT_COINS,
	Tone.AFFINITY: UiTokens.COLOR_FLOAT_AFFINITY, Tone.ITEM: UiTokens.COLOR_TEXT, Tone.MUTED: UiTokens.COLOR_SECONDARY,
}

var text := "": set = set_text
var tone: Tone = Tone.XP
var layout: Layout = Layout.HUG
var icon: Texture2D

var _pill: PanelContainer
var _icon_rect: TextureRect
var _label: Label
var _unit := 1.0 / _PEAK        # scale that shows the pill at its ×1.0 size
var _peak := _PEAK              # the pop's peak, capped by width
var _tween: Tween
var _fade: Tween
var _base_y := 0.0

func _init(text_: String = "", tone_: Tone = Tone.XP, icon_: Texture2D = null, layout_: Layout = Layout.HUG) -> void:
	tone = tone_
	layout = layout_
	icon = icon_ if icon_ != null else (HEART if tone_ == Tone.AFFINITY else null)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pill = _compose(tone, icon, _PEAK)
	add_child(_pill)
	_icon_rect = _pill.get_child(0).get_child(0)
	_label = _pill.get_child(0).get_child(1)
	scale = Vector2.ONE * _unit
	_pill.minimum_size_changed.connect(_fit)
	text = text_

## The FloatText look without motion, at ×1.0: e.g. the reward pills inside a RewardMoment card (哪吒, 226).
static func pill(text_: String, tone_: Tone, icon_: Texture2D = null) -> PanelContainer:
	var p := _compose(tone_, icon_ if icon_ != null else (HEART if tone_ == Tone.AFFINITY else null), 1.0)
	(p.get_child(0).get_child(1) as Label).text = text_
	return p

## Backing pill, icon and line, every length multiplied by `k` (the animated float lays out at the ×1.3 peak).
static func _compose(tone_: Tone, icon_: Texture2D, k: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(Color(UiTokens.COLOR_SURFACE, _BACKING_ALPHA), _RADIUS * k)
	p.add_theme_stylebox_override(&"panel", box.with_margins(_PAD.x * k, _PAD.y * k, _PAD.x * k, _PAD.y * k))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", roundi(_ICON_GAP * k))
	p.add_child(row)
	var ic := UiKit.icon(icon_, _ICON * k)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.visible = icon_ != null
	row.add_child(ic)
	var l := UiKit.label("", UiTokens.STYLE_ROW_TITLE_XB15, TONE_COLORS[tone_])
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(l)
	return p

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED: _relayout()

func set_text(v: String) -> void:
	text = v
	if _label != null:
		_label.text = v
		_relayout()

## The pill at its ×1.0 size in screen px (it is laid out ×1.3 larger and scaled down).
func shown_size() -> Vector2: return size * _unit

## Lays the pill out at the peak size: font ×1.3, Wrap capped at 320 × 1.3 and two lines.
func _relayout() -> void:
	if _label == null or not is_inside_tree(): return
	_label.remove_theme_font_size_override(&"font_size")
	_label.add_theme_font_size_override(&"font_size", roundi(_label.get_theme_font_size(&"font_size") * _PEAK))
	if layout == Layout.WRAP:
		_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_label.max_lines_visible = _WRAP_LINES
		_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var room := _WRAP_MAX * _PEAK - (_PAD.x * 2.0 + (_ICON + _ICON_GAP if icon != null else 0.0)) * _PEAK
		_label.custom_minimum_size.x = 0.0
		var one_line := _label.get_theme_font(&"font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
			_label.get_theme_font_size(&"font_size")).x
		_label.custom_minimum_size.x = floorf(minf(one_line, room))   # the label rounds its width up
	_fit()

## Size follows the pill's minimum (fonts and wraps settle a frame late); the bottom centre stays where it was.
func _fit() -> void:
	var old := pivot_offset
	size = _pill.get_combined_minimum_size()
	_pill.size = size
	pivot_offset = Vector2(size.x * 0.5, size.y)
	if old != Vector2.ZERO: position += old - pivot_offset
	# The pop's peak never makes the pill wider than 336 on screen.
	_peak = minf(_PEAK, _PEAK_MAX_W / maxf(1.0, size.x * _unit))

## Shows the float with its bottom centre at `at` (in the parent's space), the `stack_index`th line of one moment.
func play(at: Vector2, stack_index := 0) -> void:
	_relayout()
	var n := clampi(stack_index, 0, _STACK_MAX - 1)
	position = at - pivot_offset - Vector2(0, _STACK_RISE * n)
	_base_y = position.y
	scale = Vector2.ONE * _unit * _START
	modulate.a = 0.0
	var delay := UiKit.secs(_STACK_DELAY_MS * n)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, ^"scale", Vector2.ONE * _unit * _peak, UiKit.secs(_POP_MS)) \
		.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"scale", Vector2.ONE * _unit, UiKit.secs(_SETTLE_MS - _POP_MS)) \
		.set_delay(delay + UiKit.secs(_POP_MS)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"position:y", _base_y - _RISE, UiKit.secs(_TOTAL_MS)) \
		.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"modulate:a", 1.0, UiKit.secs(_FADE_IN_MS)).set_delay(delay)
	_fade_out(delay + UiKit.secs(_FADE_OUT_AT_MS))

## A merged line (`+48 XP · 12 plants`) updates in place: new text, a ×1.12 bump, the same height, and the fade
## restarts 650 ms after this update.
func bump(new_text: String) -> void:
	text = new_text
	if _tween != null and _tween.is_valid(): _tween.kill()   # holds its height from here
	scale = Vector2.ONE * _unit
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_property(self, ^"scale", Vector2.ONE * _unit * _BUMP, UiKit.secs(_BUMP_MS * 0.5)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, ^"scale", Vector2.ONE * _unit, UiKit.secs(_BUMP_MS * 0.5)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_out(UiKit.secs(_FADE_OUT_AT_MS))

func _fade_out(after: float) -> void:
	if _fade != null and _fade.is_valid(): _fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, ^"modulate:a", 0.0, UiKit.secs(_TOTAL_MS - _FADE_OUT_AT_MS)) \
		.set_delay(after).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade.tween_callback(func():
		finished.emit()
		queue_free())
