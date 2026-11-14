class_name UiSystemCard
extends PanelContainer
## SystemCard 1237:87229 (E-03 / D-10 error template; WP6, SGODOT-233): a 328-wide card centred on a dimmed backdrop,
## no HUD, no ✕. Icon disc 64 (a 32 icon), the title (what happened), one body line (only facts the system knows),
## the primary command (Retry, never Try again) and one optional secondary under it — a CommandButton Kind=secondary,
## as wide and tall as the primary (Go back on SYS-LOADING-SCENE-FAIL 1780:103778).
##   Kind.BLOCKING  whole-screen system states: SYS-MAINT, SYS-UPDATE, SYS-LOADING Can't connect (primaryTint disc)
##   Kind.ERROR     recoverable failures: a place that would not open (disabled-grey disc)
## show_card({icon, title, body, note, primary, secondary}): "" hides that part. Emits primary_pressed / secondary_pressed;
## `note` is the small line under the body (Caption Bold 12, secondary: ACC-SUSPENDED's `Support code AB12C-3DE45`,
## 645:197762), the whole line a tap (note_pressed).

signal primary_pressed
signal secondary_pressed
signal note_pressed

enum Kind { BLOCKING, ERROR }

const WIDTH := 328.0
# Kind=Blocking 1237:87229: padding 28 / 21 / 20 / 21, gap 10, disc 64 with a 32 icon, 6 more above the button; the
# card's 0 10 28 shadow as the moment banner draws it. Constants until the next token export adds them.
const _PAD_TOP := 28.0
const _PAD_X := 21.0
const _PAD_BOTTOM := 20.0
const _GAP := 10
const _DISC := 64.0
const _ICON := 32.0
const _BUTTON_GAP := 6.0
const _SHADOW_SIZE := 14.0
const _SHADOW_Y := 10.0

var kind: Kind = Kind.BLOCKING
var icon_rect: TextureRect
var title: Label
var body: Label
var note: Label
var primary: UiCommandButton
var secondary: UiCommandButton

var _disc: Panel
var _gap: Control

func _init(kind_: Kind = Kind.BLOCKING) -> void:
	kind = kind_
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_SHEET, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.shadow_color = UiTokens.COLOR_SHADOW_CARD
	box.shadow_size = _SHADOW_SIZE
	box.shadow_offset = Vector2(0, _SHADOW_Y)
	add_theme_stylebox_override(&"panel", box.with_margins(_PAD_X, _PAD_TOP, _PAD_X, _PAD_BOTTOM))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", _GAP)
	add_child(col)
	_disc = Panel.new()
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.custom_minimum_size = Vector2(_DISC, _DISC)
	_disc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(
		UiTokens.COLOR_PRIMARY_TINT if kind == Kind.BLOCKING else UiTokens.COLOR_DISABLED, _DISC * 0.5))
	col.add_child(_disc)
	icon_rect = UiKit.icon(null, _ICON)
	icon_rect.position = Vector2.ONE * (_DISC - _ICON) * 0.5
	icon_rect.size = Vector2(_ICON, _ICON)
	_disc.add_child(icon_rect)
	title = _line(UiTokens.STYLE_TITLE_XB20, UiTokens.COLOR_TEXT)
	col.add_child(title)
	body = _line(UiTokens.STYLE_BODY_B14, UiTokens.COLOR_SECONDARY)
	col.add_child(body)
	note = _line(UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	note.name = "Note"
	note.mouse_filter = Control.MOUSE_FILTER_STOP
	note.gui_input.connect(func(e: InputEvent): if UiShopRow._released(e): note_pressed.emit())
	col.add_child(note)
	_gap = Control.new()
	_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gap.custom_minimum_size.y = _BUTTON_GAP - _GAP   # 6 above the button on top of the column's 10
	col.add_child(_gap)
	primary = UiCommandButton.new("", UiCommandButton.Kind.PRIMARY)
	primary.activated.connect(func(): primary_pressed.emit())
	col.add_child(primary)
	secondary = UiCommandButton.new("", UiCommandButton.Kind.SECONDARY)
	secondary.activated.connect(func(): secondary_pressed.emit())
	col.add_child(secondary)

static func _line(style: StringName, color: Color) -> Label:
	var l := UiKit.label("", style, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - _PAD_X * 2.0   # wraps at the card's width from the first measure, never at 0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Draw one card: {icon (Texture2D), icon_tint (Color, for a white glyph), title, body, note, primary, secondary}.
func show_card(d: Dictionary) -> void:
	icon_rect.texture = d.get("icon", null)
	icon_rect.self_modulate = d.get("icon_tint", Color.WHITE)
	_disc.visible = icon_rect.texture != null
	title.text = str(d.get("title", ""))
	body.text = str(d.get("body", ""))
	body.visible = body.text != ""
	note.text = str(d.get("note", ""))
	note.visible = note.text != ""
	primary.label = str(d.get("primary", ""))
	primary.visible = primary.label != ""
	_gap.visible = primary.visible
	secondary.label = str(d.get("secondary", ""))
	secondary.visible = secondary.label != ""
