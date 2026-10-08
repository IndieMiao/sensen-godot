class_name UiInboxNotice
extends PanelContainer
## InboxNotice 1860:104768 (BAG-5-2 482:146, FARM-LV2-2 1368:91701; §10.4.8, LOCK-14, q(87); SGODOT-234): a passive
## reward that did not fit the bag went to the Inbox. 282 × 74 on the cream surface, radius 14, no edge and no shadow.
## Next to a 24 px icon, three lines: the title (C12 ExtraBold); the item (C11 Bold) with its ×N on the right (C12
## ExtraBold); the third line (C10 Bold, secondary) with › at the right. Copy and icon come from the owner
## (P0Logic.parcel_notice: `Sent to Inbox` / `Inbox full · waiting`, `+1 more · Expires in 24h`; the shared parcel
## icon). A tap anywhere emits `tapped` (the owner opens the Inbox on Parcels); where it hangs and how long it stays are
## the owner's (P0Ui: under the bell, MOTION_TOAST_BASE_MS). The sizes are not tokens yet (PENDING "inboxNotice"):
## constants here until the next export.

signal tapped

const WIDTH := 282.0
const HEIGHT := 74.0
const _PAD_LEFT := 10.0
const _PAD_TOP := 8.0
const _PAD_RIGHT := 9.0   # › ends at 273
const _ICON := 24.0
const _ICON_TOP := 4.0   # the icon at y 12
const _GAP := 8   # the text at x 42
## Each line's slot, top to top: Nunito's line box here is a little taller than Figma's text boxes, so a slot's text
## starts at its top and may run past its foot rather than push the next line down.
const _TITLE_ROW := 20.0   # the title at y 8, the item at y 28
const _ITEM_ROW := 21.0   # the third line at y 49
const _QTY_RIGHT := 5.0   # ×N ends at 268, 5 inside ›

var _icon: TextureRect
var _title: Label
var _item: Label
var _qty: Label
var _line: Label
var _down_at := Vector2.INF
var _down_ms := 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)
	add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD).with_margins(_PAD_LEFT, _PAD_TOP, _PAD_RIGHT, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", _GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	var icon_box := MarginContainer.new()
	icon_box.add_theme_constant_override(&"margin_top", int(_ICON_TOP))
	icon_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_box)
	_icon = UiKit.icon(null, _ICON)
	icon_box.add_child(_icon)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override(&"separation", 0)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lines)
	_title = _text(UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT)
	_slot(lines, _TITLE_ROW).add_child(_title)
	_fill_width(_title)
	var item_row := _row(_slot(lines, _ITEM_ROW))
	_item = _text(UiTokens.STYLE_C11_B, UiTokens.COLOR_TEXT)
	_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_row.add_child(_item)
	var qty_box := MarginContainer.new()
	qty_box.add_theme_constant_override(&"margin_right", int(_QTY_RIGHT))
	qty_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_row.add_child(qty_box)
	_qty = _text(UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT, false)
	qty_box.add_child(_qty)
	var line_row := _row(_slot(lines, 0.0))
	_line = _text(UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_row.add_child(_line)
	var chevron := _text(UiTokens.STYLE_C13_XB, UiTokens.COLOR_SECONDARY, false)
	chevron.text = "›"
	line_row.add_child(chevron)

## A line's slot: a plain Control of the line's height (h 0: the rest of the card), so what it holds is not laid out
## by the column and keeps its own height.
static func _slot(parent: Control, h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size.y = h
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL if h <= 0.0 else Control.SIZE_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)
	return s

static func _row(slot: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override(&"separation", 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(r)
	_fill_width(r)
	return r

## Across its slot, top-aligned, as tall as it needs.
static func _fill_width(c: Control) -> void:
	c.anchor_right = 1.0
	c.grow_vertical = Control.GROW_DIRECTION_END

## A line's label, top-aligned in its row. `trims`: a name or line cut with … at the card's edge; ×N and › never are.
static func _text(style: StringName, color: Color, trims := true) -> Label:
	var l := UiKit.label("", style, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	l.clip_text = trims
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if trims else TextServer.OVERRUN_NO_TRIMMING
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## spec: {title, item, quantity ("×7"), line ("Expires in 24h", "+1 more · Claim a parcel first"); › is the card's own}.
func show_notice(spec: Dictionary, icon: Texture2D) -> void:
	_title.text = str(spec.get("title", ""))
	_item.text = str(spec.get("item", ""))
	_qty.text = str(spec.get("quantity", ""))
	_line.text = str(spec.get("line", ""))
	_icon.texture = icon

func title_text() -> String: return _title.text
func item_text() -> String: return _item.text
func quantity_text() -> String: return _qty.text
func line_text() -> String: return _line.text
func icon_texture() -> Texture2D: return _icon.texture

## A tap on release within GestureArbiter's slop and time, as UiTipCard: a press that drags on leaves it up. One event
## family only (mouse buttons; raw touches only without touchscreen emulation).
func _gui_input(e: InputEvent) -> void:
	var is_mouse: bool = e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT
	var is_touch: bool = e is InputEventScreenTouch and not DisplayServer.is_touchscreen_available()
	if not (is_mouse or is_touch): return
	accept_event()
	if e.pressed:
		_down_at = e.position
		_down_ms = Time.get_ticks_msec()
		return
	var tap: bool = _down_at != Vector2.INF and e.position.distance_to(_down_at) <= GestureArbiter.TAP_SLOP \
		and Time.get_ticks_msec() - _down_ms <= GestureArbiter.TAP_MAX_MS
	_down_at = Vector2.INF
	if tap: tapped.emit()
