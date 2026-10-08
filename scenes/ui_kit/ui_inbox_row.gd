class_name UiInboxRow
extends PanelContainer
## InboxRow 1309:89969 (C2-01, LOCK-14; SGODOT-234): one row of the Inbox drawer, 328 wide, a raised card (white,
## radius 16, 1 px border, padding 12 / 14). Kind=Player (PlayerChip, message, To do actions) is P2 social and not
## built here.
##   Kind.ITEM    a parcel: item disc 44 (primaryTint, a 28 icon) · Name ×N (ExtraBold 15) / source / time left
##                (Bold 12 secondary) · Claim (Compact command, secondary; grey `Claim` with the bag full).
##   Kind.SYSTEM  a system line, read only: icon disc 44 (disabled grey, a 24 icon) · title (ExtraBold 14) / sub
##                (Bold 12 secondary) · time (Bold 11 secondary) and the red unread dot (8).
## show_row({key, icon, title, sub, left (ITEM), can_claim (ITEM), time (SYSTEM), unread (SYSTEM)}).

signal claim_pressed(key: String)
signal claim_unavailable(key: String)

enum Kind { ITEM, SYSTEM }

const WIDTH := 328.0
# InboxRow main: radius 16, padding 12 / 14, gap 10; disc 44 with a 28 (Item) or 24 (System) icon; text gap 2;
# the time and its dot 6 apart. Constants until the next token export adds them.
const _RADIUS := 16.0
const _PAD_X := 14.0
const _PAD_Y := 12.0
const _GAP := 10
const _DISC := 44.0
const _ICON_ITEM := 28.0
const _ICON_SYSTEM := 24.0
const _TEXT_GAP := 2
const _META_GAP := 6
const _DOT := 8.0

var kind: Kind = Kind.ITEM
var key := ""
var title: Label
var sub: Label
var left_label: Label
var time_label: Label
var claim: UiCommandButton

var _disc: Panel
var _icon: TextureRect
var _dot: Panel

func _init(kind_: Kind = Kind.ITEM) -> void:
	kind = kind_
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_PASS   # a drag starting on a row still scrolls the list (TouchScrollContainer)
	add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
		.with_margins(_PAD_X, _PAD_Y, _PAD_X, _PAD_Y))
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override(&"separation", _GAP)
	add_child(top)
	_disc = Panel.new()
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.custom_minimum_size = Vector2(_DISC, _DISC)
	_disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_disc.add_theme_stylebox_override(&"panel", UiStyleBox.make(
		UiTokens.COLOR_PRIMARY_TINT if kind == Kind.ITEM else UiTokens.COLOR_DISABLED, _DISC * 0.5))
	top.add_child(_disc)
	var side := _ICON_ITEM if kind == Kind.ITEM else _ICON_SYSTEM
	_icon = UiKit.icon(null, side)
	_icon.position = Vector2.ONE * (_DISC - side) * 0.5
	_icon.size = Vector2(side, side)
	_disc.add_child(_icon)
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override(&"separation", _TEXT_GAP)
	top.add_child(text)
	title = _line(UiTokens.STYLE_ROW_TITLE_XB15 if kind == Kind.ITEM else UiTokens.STYLE_C14_XB, UiTokens.COLOR_TEXT)
	text.add_child(title)
	sub = _line(UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	text.add_child(sub)
	if kind == Kind.ITEM:
		left_label = _line(UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
		text.add_child(left_label)
		claim = UiCommandButton.new("Claim", UiCommandButton.Kind.SECONDARY, true)
		claim.sends = true   # claim_parcel: Offline while offline (§10.7.1)
		claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		claim.activated.connect(func(): claim_pressed.emit(key))
		claim.unavailable_pressed.connect(func(_r: String): claim_unavailable.emit(key))
		top.add_child(claim)
	else:
		var meta := HBoxContainer.new()
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meta.add_theme_constant_override(&"separation", _META_GAP)
		top.add_child(meta)
		time_label = _line(UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
		time_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		meta.add_child(time_label)
		_dot = Panel.new()
		_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_dot.custom_minimum_size = Vector2(_DOT, _DOT)
		_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_DANGER, _DOT * 0.5))
		meta.add_child(_dot)

static func _line(style: StringName, color: Color) -> Label:
	var l := UiKit.label("", style, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func show_row(d: Dictionary) -> void:
	key = str(d.get("key", ""))
	_icon.texture = d.get("icon", null)
	title.text = str(d.get("title", ""))
	sub.text = str(d.get("sub", ""))
	sub.visible = sub.text != ""
	if kind == Kind.ITEM:
		left_label.text = str(d.get("left", ""))
		left_label.visible = left_label.text != ""
		# The bag full: the same grey `Claim` on every row (PARCEL-3); the drawer's Make room says how much.
		claim.reason = "" if bool(d.get("can_claim", true)) else "Claim"
	else:
		time_label.text = str(d.get("time", ""))
		_dot.visible = bool(d.get("unread", false))

func unread() -> bool: return _dot != null and _dot.visible
