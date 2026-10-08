class_name UiItemCell
extends Control
## One item cell, four densities (SGODOT-212; WP7-C F-05 "one item_cell, density picks the Figma main"):
##   INVENTORY  Compact/InventoryCell 633:41278  52×52  icon, quantity pill, rarity dot             (LOCK-12)
##   QUICK      Compact/QuickSlot 633:41279      52×68  icon + name + quantity only, pin state     (LOCK-04 / 05)
##   KITCHEN    Compact/Kitchen/Cell 655:58506   52×58  icon, state label, selected / cooked mark  (LOCK-20)
##   GEAR       Compact/GearSlot 663:61299       52×88  role above, equipment name below           (LOCK-13)
## Data in (the fields below), signals out. Each cell runs its own GestureArbiter (QUICK: SLOT mode, others:
## CELL mode, WP7-B F-04 §3 / §4), so a touch is exactly one outcome: `tapped` only for the arbiter's tap;
## everything else (lift, long_press, drag_start / drag_move / drop, swipe_up, cancel) goes out
## through `gesture` for the quick bar / bag drawer, which then sets `state` / `pinned`. mouse_filter is
## PASS, so a TouchScrollContainer still takes vertical drags (CELL mode answers them with cancel).
## Hosts outside a scroll container (the quick bar) need a STOP backing control, or the touch also reaches
## _unhandled_input (the map's tap handling, for one).
## LIFTED, DROP_TARGET and ZERO exist on the QuickSlot main only; other densities draw them as DEFAULT.
## GHOST (QuickSlot State=ghost 1415:94114, A-08) is an empty slot showing what the action can use: dashed like
## EMPTY, the family icon at 35 %, a one-word family name in secondary ink (`title`), no count, never pinned.
## Other densities draw it as EMPTY.

signal tapped
## A GestureArbiter outcome other than tap, e.g. {kind = &"lift", pos}; `pos` is in global coordinates. Pinning is the
## quick bar's drop on its Pin zone (LOCK-05 v1.11), never a cell outcome.
signal gesture(outcome: Dictionary)

enum Density { INVENTORY, QUICK, KITCHEN, GEAR }
enum State { DEFAULT, SELECTED, EMPTY, LIFTED, DROP_TARGET, ZERO, GHOST }

const RARITY_COLORS := [UiTokens.COLOR_RARITY_COMMON, UiTokens.COLOR_RARITY_FINE, UiTokens.COLOR_RARITY_RARE,
	UiTokens.COLOR_RARITY_LEGENDARY]
const PIN_GLYPH := preload("res://assets/ui/kit_icons/pin.svg")
const CHECK_GLYPH := preload("res://assets/ui/kit_icons/check.svg")

# Positions inside the fixed-size mains (layout of one main, not shared tokens):
const _CELL_ICON_TOP := 10.0      # InventoryCell: 27 px icon at y 10 of 52
const _KITCHEN_ICON_TOP := 8.0    # Kitchen/Cell: icon at y 8
const _PILL_INSET := 3.0          # quantity pill 24×13 at (25, 36) of 52×52
const _DOT_INSET := 5.0           # rarity dot at (5, 5); Kitchen/Cell has it at (4, 4)
const _KITCHEN_DOT_INSET := 4.0
const _KITCHEN_LABEL_TOP := 31.0  # "Cell state label" 52×25 at y 31, radius 5, text 13 high at y 1
const _KITCHEN_LABEL_H := 25.0
const _KITCHEN_LABEL_RADIUS := 5.0
const _KITCHEN_MARK_OUT := 2.0    # mark 13×13 at (41, -2): overhangs the top-right corner by 2
const _QUICK_PAD := 4.0           # QuickSlot "Slot surface" padding
const _QUICK_NAME_H := 22.0       # two-line name block, then the 12 px quantity line
const _QUICK_QTY_H := 12.0
const _GEAR_ROLE_H := 11.0        # GearSlot: role 11 high, slot at y 16, name at y 71 (16 high)
const _GEAR_SLOT_TOP := 16.0
const _GEAR_NAME_TOP := 71.0
const _GEAR_NAME_H := 16.0

var density: Density
var state: State = State.DEFAULT: set = set_state
var icon: Texture2D: set = set_icon
## Item name: the two-line QuickSlot name or the GearSlot equipment name. Unused by INVENTORY / KITCHEN.
var title := "": set = set_title
## Count as shown, e.g. "×24"; "" hides it. QUICK shows a plain line, INVENTORY / KITCHEN a pill.
var quantity := "": set = set_quantity
## 0 = no dot, 1–4 = Common / Fine / Rare / Legendary (INVENTORY and KITCHEN).
var rarity := 0: set = set_rarity
## LOCK-05 pin: warm fill, amber strip inside the top edge, amber pin badge over the top centre (QUICK).
var pinned := false: set = set_pinned
## GearSlot role above the slot, e.g. "Fishing".
var role := "": set = set_role
## Kitchen state label over the lower part of the cell, e.g. "Tasted"; "" hides it.
var status := "": set = set_status
## Kitchen check mark for a cooked dish; SELECTED shows it too ("Selected or cooked mark").
var marked := false: set = set_marked

## Milliseconds for the arbiter; tests inject a fake clock.
var clock := Callable(Time, &"get_ticks_msec")

var _arbiter: GestureArbiter
var _surface: Panel
var _icon: TextureRect
var _name: Label
var _qty: Label
var _pill: Panel
var _dot: Panel
var _role: Label
var _status: Panel
var _mark: Panel
var _strip: Panel
var _badge: Panel

func _init(d: Density = Density.INVENTORY) -> void:
	density = d
	mouse_filter = Control.MOUSE_FILTER_PASS
	_arbiter = GestureArbiter.new(GestureArbiter.Mode.SLOT if d == Density.QUICK else GestureArbiter.Mode.CELL)
	set_process(false)
	match density:
		Density.INVENTORY: custom_minimum_size = Vector2(UiTokens.SIZE_INVENTORY_CELL, UiTokens.SIZE_INVENTORY_CELL)
		Density.QUICK: custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_SLOT_W, UiTokens.SIZE_QUICK_SLOT_H)
		Density.KITCHEN: custom_minimum_size = Vector2(UiTokens.SIZE_KITCHEN_CELL_W, UiTokens.SIZE_KITCHEN_CELL_H)
		Density.GEAR: custom_minimum_size = Vector2(UiTokens.SIZE_GEAR_SLOT_W, UiTokens.SIZE_GEAR_SLOT_H)
	_surface = _box(self)
	match density:
		Density.QUICK: _build_quick()
		Density.GEAR: _build_gear()
		_: _build_cell()
	_refresh()

func set_state(v: State) -> void: state = v; _refresh()
func set_icon(v: Texture2D) -> void: icon = v; _refresh()
func set_title(v: String) -> void: title = v; _refresh()
func set_quantity(v: String) -> void: quantity = v; _refresh()
func set_rarity(v: int) -> void: rarity = v; _refresh()
func set_pinned(v: bool) -> void: pinned = v; _refresh()
func set_role(v: String) -> void: role = v; _refresh()
func set_status(v: String) -> void: status = v; _refresh()
func set_marked(v: bool) -> void: marked = v; _refresh()

func _gui_input(event: InputEvent) -> void:
	_emit(_arbiter.feed(event, clock.call()))
	set_process(_arbiter.is_active())

## Long presses fire on time alone, so tick while a finger is down.
func _process(_delta: float) -> void:
	_emit(_arbiter.tick(clock.call()))
	if not _arbiter.is_active(): set_process(false)

func _notification(what: int) -> void:
	# A scroll container took over the drag: this touch is no longer the cell's.
	if what == NOTIFICATION_SCROLL_BEGIN and _arbiter.is_active():
		_arbiter.reset()
		set_process(false)
		gesture.emit({kind = &"cancel"})

func _emit(outcomes: Array) -> void:
	for o: Dictionary in outcomes:
		if o.kind == &"tap":
			tapped.emit()
			continue
		var g := o.duplicate()
		if g.has("pos"): g.pos = get_global_transform() * (g.pos as Vector2)
		gesture.emit(g)

## QuickSlot pin badge pop after a pin toggle on the Pin zone (LOCK-05 v1.11): 1 → 1.3 → 1 over 300 ms.
const _PIN_POP := 1.3
const _PIN_POP_MS := 300.0
func pop_pin() -> void:
	if _badge == null or not _badge.visible: return
	_badge.pivot_offset = _badge.size * 0.5
	var t := _badge.create_tween()
	t.tween_property(_badge, ^"scale", Vector2.ONE * _PIN_POP, UiKit.secs(_PIN_POP_MS * 0.5)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_badge, ^"scale", Vector2.ONE, UiKit.secs(_PIN_POP_MS * 0.5)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

## The state actually drawn: the extra QuickSlot states fall back to DEFAULT (GHOST to EMPTY) on the other mains.
func drawn_state() -> State:
	if density != Density.QUICK and state in [State.LIFTED, State.DROP_TARGET, State.ZERO]: return State.DEFAULT
	if density != Density.QUICK and state == State.GHOST: return State.EMPTY
	return state

# ------------------------------------------------------------------ build

static func _box(parent: Control) -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p

static func _place(c: Control, anchor_x: float, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = anchor_x
	c.anchor_right = anchor_x
	c.offset_left = x
	c.offset_right = x + w
	c.offset_top = y
	c.offset_bottom = y + h

## Label centred on a band: Godot sizes a Label to the font's full line box, so the band may be shorter
## than the label; growing both ways keeps the text centred where the Figma text box sits.
static func _band_label(parent: Control, style: StringName, y: float, h: float, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := UiKit.label("", style)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.anchor_right = 1.0
	l.offset_top = y
	l.offset_bottom = y + h
	parent.add_child(l)
	return l

func _add_icon(parent: Control, side: float, top: float) -> void:
	_icon = UiKit.icon(null, side)
	_place(_icon, 0.5, -side * 0.5, top, side, side)
	parent.add_child(_icon)

func _add_pill(parent: Control) -> void:
	_pill = _box(parent)
	_pill.anchor_left = 1.0
	_pill.anchor_right = 1.0
	_pill.anchor_top = 1.0
	_pill.anchor_bottom = 1.0
	_pill.offset_left = -_PILL_INSET - UiTokens.SIZE_QTY_PILL_W
	_pill.offset_right = -_PILL_INSET
	_pill.offset_top = -_PILL_INSET - UiTokens.SIZE_QTY_PILL_H
	_pill.offset_bottom = -_PILL_INSET
	_pill.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, UiTokens.SIZE_QTY_PILL_H * 0.5))
	_qty = _band_label(_pill, UiTokens.STYLE_C10_XB, 0.0, UiTokens.SIZE_QTY_PILL_H)

func _add_dot(parent: Control, inset: float) -> void:
	_dot = _box(parent)
	_place(_dot, 0.0, inset, inset, UiTokens.SIZE_RARITY_DOT, UiTokens.SIZE_RARITY_DOT)

## INVENTORY and KITCHEN: a square surface with icon, pill and rarity dot; KITCHEN adds label and mark.
func _build_cell() -> void:
	var side := UiTokens.SIZE_INVENTORY_CELL if density == Density.INVENTORY else UiTokens.SIZE_KITCHEN_CELL_W
	_place(_surface, 0.0, 0.0, 0.0, side, side)
	_surface.anchor_right = 1.0
	_surface.offset_right = 0.0
	var kitchen := density == Density.KITCHEN
	_add_icon(_surface, UiTokens.SIZE_INVENTORY_ICON, _KITCHEN_ICON_TOP if kitchen else _CELL_ICON_TOP)
	_add_dot(_surface, _KITCHEN_DOT_INSET if kitchen else _DOT_INSET)
	_add_pill(_surface)
	if not kitchen: return
	_status = _box(self)
	_place(_status, 0.0, 0.0, _KITCHEN_LABEL_TOP, side, _KITCHEN_LABEL_H)
	_status.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, _KITCHEN_LABEL_RADIUS))
	_name = _band_label(_status, UiTokens.STYLE_C10_B, 0.0, UiTokens.SIZE_QTY_PILL_H)
	_name.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY)
	var m := UiTokens.SIZE_KITCHEN_CHECK
	_mark = _box(self)
	_place(_mark, 1.0, _KITCHEN_MARK_OUT - m, -_KITCHEN_MARK_OUT, m, m)
	_mark.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY, m * 0.5))
	var check := UiKit.icon(CHECK_GLYPH, UiTokens.SIZE_KITCHEN_CHECK_ICON)
	check.self_modulate = UiTokens.COLOR_SURFACE_RAISED
	_place(check, 0.5, -UiTokens.SIZE_KITCHEN_CHECK_ICON * 0.5, (m - UiTokens.SIZE_KITCHEN_CHECK_ICON) * 0.5,
		UiTokens.SIZE_KITCHEN_CHECK_ICON, UiTokens.SIZE_KITCHEN_CHECK_ICON)
	_mark.add_child(check)

func _build_quick() -> void:
	_surface.anchor_right = 1.0
	var w := UiTokens.SIZE_QUICK_SLOT_W - _QUICK_PAD * 2.0
	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [&"offset_left", &"offset_top"]: body.set(side, _QUICK_PAD)
	for side in [&"offset_right", &"offset_bottom"]: body.set(side, -_QUICK_PAD)
	_surface.add_child(body)
	_add_icon(body, UiTokens.SIZE_QUICK_SLOT_ICON, 0.0)
	_name = _band_label(body, UiTokens.STYLE_C10_B, 0.0, _QUICK_NAME_H)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible = 2
	_name.custom_minimum_size.x = w
	_qty = _band_label(body, UiTokens.STYLE_C10_XB, 0.0, _QUICK_QTY_H, HORIZONTAL_ALIGNMENT_RIGHT)
	_strip = _box(_surface)
	_strip.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PIN_AMBER, UiTokens.SIZE_PIN_STRIP_H * 0.5))
	var b := UiTokens.SIZE_PIN_BADGE
	_badge = _box(_surface)
	_place(_badge, 0.5, -b * 0.5, -b * 0.5, b, b)
	_badge.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PIN_AMBER, b * 0.5,
		UiTokens.COLOR_SURFACE, UiTokens.STROKE_PIN_BADGE))
	var glyph := UiKit.icon(PIN_GLYPH, UiTokens.SIZE_PIN_ICON)
	glyph.self_modulate = UiTokens.COLOR_SURFACE_RAISED
	_place(glyph, 0.5, -UiTokens.SIZE_PIN_ICON * 0.5, (b - UiTokens.SIZE_PIN_ICON) * 0.5, UiTokens.SIZE_PIN_ICON, UiTokens.SIZE_PIN_ICON)
	_badge.add_child(glyph)

func _build_gear() -> void:
	_role = _band_label(self, UiTokens.STYLE_C9_B, 0.0, _GEAR_ROLE_H)
	_role.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY)
	_place(_surface, 0.0, 0.0, _GEAR_SLOT_TOP, UiTokens.SIZE_GEAR_SLOT_W, UiTokens.SIZE_INVENTORY_CELL)
	var side := UiTokens.SIZE_INVENTORY_ICON
	_add_icon(_surface, side, (UiTokens.SIZE_INVENTORY_CELL - side) * 0.5)
	_name = _band_label(self, UiTokens.STYLE_C9_B, _GEAR_NAME_TOP, _GEAR_NAME_H)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if _surface == null: return
	var s := drawn_state()
	var empty := s == State.EMPTY
	_icon.texture = icon
	_icon.visible = icon != null and not empty
	match density:
		Density.QUICK: _refresh_quick(s)
		Density.GEAR:
			_surface.add_theme_stylebox_override(&"panel", _cell_box(s, UiTokens.RADIUS_INVENTORY_CELL))
			_role.text = role
			_name.text = title
		_:
			_surface.add_theme_stylebox_override(&"panel", _cell_box(s, UiTokens.RADIUS_INVENTORY_CELL))
			_pill.visible = quantity != "" and not empty
			_qty.text = quantity
			_dot.visible = rarity > 0 and not empty
			if rarity > 0:
				_dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(RARITY_COLORS[clampi(rarity - 1, 0, 3)], UiTokens.SIZE_RARITY_DOT * 0.5))
			if density == Density.KITCHEN:
				_surface.modulate.a = UiTokens.OPACITY_KITCHEN_EMPTY if empty else 1.0
				_status.visible = status != "" and not empty
				_name.text = status
				_mark.visible = (marked or s == State.SELECTED) and not empty

## InventoryCell / Kitchen Cell / GearSlot surface: hairline border, 1.5 primary when selected, dashed when empty.
func _cell_box(s: State, radius: float) -> UiStyleBox:
	if s == State.SELECTED:
		return UiStyleBox.make(UiTokens.COLOR_SURFACE, radius, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_SELECTED_CELL)
	if s == State.EMPTY:
		var bg := UiTokens.COLOR_SURFACE
		if density == Density.INVENTORY: bg = UiKit.alpha(UiTokens.COLOR_SURFACE, UiTokens.OPACITY_EMPTY_CELL)
		var dash: Array = UiTokens.DASH_KITCHEN if density == Density.KITCHEN else UiTokens.DASH_INVENTORY
		return _dashed(UiStyleBox.make(bg, radius, UiTokens.COLOR_BORDER, UiTokens.STROKE_CELL_HAIRLINE), dash)
	return UiStyleBox.make(UiTokens.COLOR_SURFACE, radius, UiTokens.COLOR_BORDER, UiTokens.STROKE_CELL_HAIRLINE)

static func _dashed(b: UiStyleBox, pattern: Array) -> UiStyleBox:
	b.dashed = true
	b.dash = pattern[0]
	b.gap = pattern[1]
	return b

func _refresh_quick(s: State) -> void:
	var rest := UiTokens.SIZE_QUICK_SLOT_H - UiTokens.SIZE_QUICK_SLOT_SURFACE_H
	var top := rest
	if s == State.SELECTED: top = rest - UiTokens.SIZE_QUICK_SLOT_LIFT
	elif s == State.LIFTED: top = rest - UiTokens.SIZE_QUICK_SLOT_LIFT_DRAG
	_surface.offset_top = top
	_surface.offset_bottom = top + UiTokens.SIZE_QUICK_SLOT_SURFACE_H
	var fill := UiTokens.COLOR_PIN_WARM if pinned else UiTokens.COLOR_SURFACE
	var box: UiStyleBox
	match s:
		State.SELECTED, State.LIFTED:
			box = UiStyleBox.make(fill, UiTokens.RADIUS_CELL, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_SELECTED)
			if s == State.LIFTED:
				box.shadow_color = UiTokens.COLOR_LIFT_SHADOW
				box.shadow_size = UiTokens.SIZE_LIFT_SHADOW_RADIUS
				box.shadow_offset = Vector2(0.0, UiTokens.SIZE_LIFT_SHADOW_OFFSET_Y)
		State.EMPTY, State.GHOST:
			box = _dashed(UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CELL, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT), UiTokens.DASH_QUICK)
		State.DROP_TARGET:
			box = _dashed(UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, UiTokens.RADIUS_CELL, UiTokens.COLOR_PRIMARY, UiTokens.STROKE_SELECTED), UiTokens.DASH_DROP_TARGET)
		_:
			box = UiStyleBox.make(fill, UiTokens.RADIUS_CELL, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	_surface.add_theme_stylebox_override(&"panel", box)
	var empty := s == State.EMPTY
	var name_top := float(UiTokens.SIZE_QUICK_SLOT_ICON) if _icon.visible else 0.0
	_name.offset_top = name_top
	_name.offset_bottom = name_top + _QUICK_NAME_H
	_qty.offset_top = name_top + _QUICK_NAME_H
	_qty.offset_bottom = name_top + _QUICK_NAME_H + _QUICK_QTY_H
	_name.text = title
	_name.visible = title != "" and not empty
	_qty.text = quantity
	var ghost := s == State.GHOST
	_qty.visible = quantity != "" and not empty and not ghost
	# The ghost's "Icon · dimmed" is the same 35 % as the ×0 icon (no separate token yet).
	_icon.modulate.a = UiTokens.OPACITY_ZERO_ICON if s in [State.ZERO, State.GHOST] else 1.0
	_name.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY if ghost else UiTokens.COLOR_TEXT)
	_qty.add_theme_color_override(&"font_color", UiTokens.COLOR_SECONDARY if s == State.ZERO else UiTokens.COLOR_TEXT)
	var show_pin := pinned and not empty and not ghost
	_strip.visible = show_pin
	_badge.visible = show_pin
	# The amber strip sits inside the outline, so it moves down with the 2 px selected stroke (LOCK-05).
	var w := UiTokens.SIZE_PIN_STRIP_W
	_place(_strip, 0.5, -w * 0.5, box.border_width, w, UiTokens.SIZE_PIN_STRIP_H)
