class_name UiBarToast
extends PanelContainer
## UI v3 page toast (C-85 pages ①-D and ②-D, C-108): a white card, radius 16, `elevation/e2`, a 4 colour bar down its
## left edge and an 18 glyph of the same colour, the sentence in 13 Bold ink (`type/label`), 16 in on the sides and 10 above and
## below, at most 328 wide; centred under a page's top bar.
##   SUCCESS  primary bar, circle-check   `Look saved`
##   ERROR    danger bar, circle-alert    `Couldn't save. Try again.`
##   WARNING  notify (amber) bar, circle-alert   `Couldn't load %s. Previous look kept.`
## pop() shows it: y −12 → 0 and fades in over 200 (cubic out), holds, then fades out over 160 and frees itself
## (`gone`). A tap takes it away at once. Never holds anything else's input.

signal gone

enum Kind { SUCCESS, ERROR, WARNING }

const MAX_W := 328.0
const RADIUS := 16.0
const BAR := 4
const PAD_X := 16.0
const PAD_Y := 10.0
const ICON := 18.0
const DROP := 12.0
const IN_MS := 200.0
const OUT_MS := 160.0
const _CHECK := preload("res://assets/ui/icons/lucide/circle-check.svg")
const _ALERT := preload("res://assets/ui/icons/lucide/circle-alert.svg")

var kind: Kind = Kind.SUCCESS
var text := ""
var label: Label
var glyph: TextureRect
var _rest_y := 0.0
var _tween: Tween

static func colour(k: Kind) -> Color:
	match k:
		Kind.ERROR: return UiTokens.COLOR_ACTION_DANGER
		Kind.WARNING: return UiTokens.COLOR_BADGE_NOTIFY
	return UiTokens.COLOR_ACTION_PRIMARY

func _init(text_ := "", kind_: Kind = Kind.SUCCESS) -> void:
	text = text_
	kind = kind_
	name = "Toast"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := StyleBoxFlat.new()
	box.bg_color = UiTokens.COLOR_SURFACE_RAISED
	box.set_corner_radius_all(int(RADIUS))
	box.border_width_left = BAR
	box.border_color = colour(kind)
	box.shadow_color = UiTokens.ELEVATION_E2_COLOR
	box.shadow_size = 12
	box.shadow_offset = Vector2(0, 6)
	box.content_margin_left = PAD_X
	box.content_margin_right = PAD_X
	box.content_margin_top = PAD_Y
	box.content_margin_bottom = PAD_Y
	box.anti_aliasing = true
	add_theme_stylebox_override(&"panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", UiTokens.SPACE_S4)
	add_child(row)
	glyph = UiKit.icon(_CHECK if kind == Kind.SUCCESS else _ALERT, ICON)
	glyph.name = "Glyph"
	glyph.modulate = colour(kind)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(glyph)
	label = UiKit.label(text, UiTokens.STYLE_TYPE_LABEL)
	label.name = "Text"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

## Centred in `parent` (a full-width overlay) with its top at `top`, then shows itself for `hold_s` seconds.
func pop(parent: Control, top: float, hold_s: float) -> UiBarToast:
	parent.add_child(self)
	var width := parent.size.x if parent.size.x > 0.0 else get_viewport().get_visible_rect().size.x
	var font := label.get_theme_font(&"font")
	var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size(&"font_size")).x
	var w := minf(MAX_W, minf(width - UiTokens.SIZE_SCREEN_EDGE * 2.0, ceilf(text_w) + ICON + UiTokens.SPACE_S4 + PAD_X * 2.0 + BAR + 1.0))
	var room := maxf(0.0, w - ICON - UiTokens.SPACE_S4 - PAD_X * 2.0 - BAR)
	# One line when it fits (a wrapping Label first asks for its height at no width, which would stand the card tall);
	# a longer sentence wraps at the room left.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF if text_w <= room else TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = room
	size = Vector2(w, 0.0)
	reset_size()
	(func(): if is_instance_valid(self): reset_size()).call_deferred()
	_rest_y = top
	position = Vector2(roundf((width - size.x) * 0.5), top - DROP)
	modulate.a = 0.0
	_tween = UiMotion.tween(self, UiTokens.MOTION_EASING_STANDARD)
	_tween.tween_property(self, "position:y", top, UiMotion.secs(IN_MS))
	_tween.parallel().tween_property(self, "modulate:a", 1.0, UiMotion.secs(IN_MS))
	_tween.tween_interval(hold_s)
	_tween.tween_callback(dismiss)
	return self

## Where it rests once dropped in (its top), whatever the entry motion has reached.
func rest_y() -> float: return _rest_y

## Fades out (160) and frees itself; a second call does nothing.
func dismiss() -> void:
	if is_queued_for_deletion() or has_meta(&"_leaving"): return
	set_meta(&"_leaving", true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _tween != null and _tween.is_valid(): _tween.kill()
	_tween = UiMotion.tween(self, UiTokens.MOTION_EASING_EXIT)
	_tween.tween_property(self, "modulate:a", 0.0, UiMotion.secs(OUT_MS))
	_tween.tween_callback(func():
		gone.emit()
		queue_free())

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		accept_event()
		dismiss()
