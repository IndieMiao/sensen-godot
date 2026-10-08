class_name UiQuickBar
extends Control
## Quick bar (SGODOT-221, LOCK-04 / 05; plan §10.3, WP7-B F-04 §3): five QuickSlot cells and the Bag / Close
## end (Compact/QuickEnd/Bag 907:72112), or the collapsed handle (page-14 frames 676:63515–7) with the Bag end
## when no action is chosen. Data in, intents out; the caller owns selection, pins and the bag.
##   tap a slot → slot_tapped(id) (select, tap again to clear); tap an empty ghost → ghost_tapped(index)
##   hold 450 ms → the slot floats (LIFTED) with a light vibration. Where the finger lets go decides, never how far
##   it moved (LOCK-04 / 05 v1.10, BAR-DRAG-1…5; GestureArbiter.drop_on_bar):
##     its own slot (+8 px; dragged out and back too) → pin_toggled(id, pinned)
##     past 16 px it drags: the slot rides 24 px above the finger, its place shows a gap, the BarRemoveZone fades
##     in 96 px over the bar; another slot (+6 px) shows DROP_TARGET → slots_swapped(a, b) (both pinned)
##     the remove zone (within 48 px; it darkens, one light tick, the slot shrinks to 80 %) → the slot flies into it
##     and slot_removed(id)
##     anywhere else, a second finger or cancel_drag() (app paused, a drawer opening) → it flies back, nothing changes
##   swipe up before floating → bag_requested; Bag → bag_requested, Close → close_requested
##   collapsed handle → handle_tapped (same as the switch key, §10.3.4)
## Each cell arbitrates its own touch (GestureArbiter SLOT mode, SGODOT-212); this bar turns the outcomes into
## the intents above. With cells shown the backing is MOUSE_FILTER_STOP: cells sit outside a scroll container, so
## without it their touches would also reach _unhandled_input (the map's tap handling, SGODOT-212 note). Collapsed
## or bag-only, the backing lets touches through: only the handle and the end take them, the gap stays world.

signal slot_tapped(id: String)
signal ghost_tapped(index: int)
signal pin_toggled(id: String, pinned: bool)
signal slots_swapped(from_index: int, to_index: int)
signal slot_removed(id: String)
signal bag_requested
signal close_requested
signal handle_tapped

const SLOTS := 5
const BAG_GLYPH := preload("res://assets/p0/icons/bag.svg")
const CLOSE_GLYPH := preload("res://assets/ui/kit_icons/close.svg")

# Positions inside the Bag end main 907:72112 (56×68) and the collapsed frame 676:63515 (BAR-1-2):
const _END_ICON_TOP := 16.0       # i-bag 22 px at (17, 16) of the 56×64 surface below a 4 px lift gap
const _END_LABEL_TOP := 42.0      # "Bag" 11 px text box at y 42, 14 high
const _END_LABEL_H := 14.0
const _END_DOT_X := 41.0          # capacity warning 7×7 at (41, 11)
const _END_DOT_Y := 11.0
const _HANDLE_RISE := 4.0         # the 44 px touch target starts 4 px above the bar's top edge

## One dictionary per slot, up to SLOTS: {id, icon: Texture2D, title, quantity: int, pinned: bool}; a missing or
## empty entry is an empty slot. An entry without id but with ghost = true draws the A-08 ghost: {ghost, icon,
## title} = the family icon and its one-word name ("Seeds", "Bait"). Tapping any slot without id → ghost_tapped.
var slots: Array = []: set = set_slots
## The selected id, drawn lifted with the green outline (§10.3.1).
var selected := "": set = set_selected
## No action chosen: the five slots fold into the handle (§10.3.1 收起态).
var collapsed := false: set = set_collapsed
## The bag drawer is open: the end reads Close (LOCK-04).
var bag_open := false: set = set_bag_open
## Bag at ≥ 90% capacity: amber dot on the end (§10.3.1).
var capacity_warning := false: set = set_capacity_warning
## Spaces without a quick bar (kitchen, counters, the map): only the Bag end stays (plan §10.3.5, MAP-1).
var bag_only := false: set = set_bag_only
## Vibrate on lift; off in tests and the gallery.
var haptics := true

var _cells: Array[UiItemCell] = []
var _row: HBoxContainer
var _end: Button
var _end_icon: TextureRect
var _end_label: Label
var _end_dot: Panel
var _handle: Button
var _ghost: UiItemCell
var _zone: UiBarRemoveZone
var _dragging := -1
var _target := -1

const _RIDE_ABOVE := 24.0       # the dragged slot rides this far above the finger (LOCK-04 v1.10)
const _HOVER_SCALE := 0.8       # …and shrinks to this over the remove zone
const _FLY_BACK_MS := 200       # cancel: back to its place, ease-out
const _FLY_IN_MS := 150         # remove: into the zone's centre

func _init() -> void:
	custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_BAR_W, UiTokens.SIZE_QUICK_BAR_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_QUICK_BAR_GAP))
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	for i in SLOTS:
		var cell := UiItemCell.new(UiItemCell.Density.QUICK)
		cell.tapped.connect(_on_tapped.bind(i))
		cell.gesture.connect(_on_gesture.bind(i))
		_cells.append(cell)
		_row.add_child(cell)
	_end = _build_end()
	_row.add_child(_end)
	_handle = _build_handle()
	add_child(_handle)
	_refresh()

func set_slots(v: Array) -> void: slots = v; _refresh()
func set_selected(v: String) -> void: selected = v; _refresh()
func set_collapsed(v: bool) -> void: collapsed = v; _refresh()
func set_bag_open(v: bool) -> void: bag_open = v; _refresh()
func set_capacity_warning(v: bool) -> void: capacity_warning = v; _refresh()
func set_bag_only(v: bool) -> void: bag_only = v; _refresh()

func cells() -> Array[UiItemCell]: return _cells
func end_button() -> Button: return _end
func handle_button() -> Button: return _handle
func is_dragging() -> bool: return _dragging >= 0

func slot(i: int) -> Dictionary:
	return slots[i] if i < slots.size() and slots[i] is Dictionary else {}

# ------------------------------------------------------------------ build

func _build_end() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_END_W, UiTokens.SIZE_QUICK_SLOT_H)
	var lift := UiTokens.SIZE_QUICK_SLOT_H - UiTokens.SIZE_QUICK_SLOT_SURFACE_H
	var surface := UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CELL, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	surface.inset = Vector4(0, lift, 0, 0)
	var pressed := UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, UiTokens.RADIUS_CELL, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	pressed.inset = surface.inset
	for s in [&"normal", &"hover", &"focus", &"disabled"]: b.add_theme_stylebox_override(s, surface)
	for s in [&"pressed", &"hover_pressed"]: b.add_theme_stylebox_override(s, pressed)
	_end_icon = UiKit.icon(null, UiTokens.SIZE_QUICK_SLOT_ICON)
	_end_icon.position = Vector2((UiTokens.SIZE_QUICK_END_W - UiTokens.SIZE_QUICK_SLOT_ICON) * 0.5, lift + _END_ICON_TOP)
	b.add_child(_end_icon)
	_end_label = UiKit.label("", UiTokens.STYLE_C11_B)
	_end_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end_label.anchor_right = 1.0
	_end_label.offset_top = lift + _END_LABEL_TOP
	_end_label.offset_bottom = lift + _END_LABEL_TOP + _END_LABEL_H
	b.add_child(_end_label)
	_end_dot = Panel.new()
	_end_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_dot.position = Vector2(_END_DOT_X, lift + _END_DOT_Y)
	_end_dot.size = Vector2(UiTokens.SIZE_CAPACITY_DOT, UiTokens.SIZE_CAPACITY_DOT)
	_end_dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_WARNING, UiTokens.SIZE_CAPACITY_DOT * 0.5))
	b.add_child(_end_dot)
	b.pressed.connect(func(): if bag_open: close_requested.emit() else: bag_requested.emit())
	return b

func _build_handle() -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(UiTokens.SIZE_QUICK_HANDLE_TOUCH_W, UiTokens.SIZE_QUICK_HANDLE_TOUCH_H)
	# Centred on the bar (and the 360 screen): BAR-1-2 puts the 120 px target at x 120 of 360, the bar at 12.
	b.position = Vector2((UiTokens.SIZE_QUICK_BAR_W - UiTokens.SIZE_QUICK_HANDLE_TOUCH_W) * 0.5, -_HANDLE_RISE)
	var box := UiStyleBox.make(UiTokens.COLOR_QUICK_HANDLE, UiTokens.RADIUS_QUICK_HANDLE, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	box.visual_height = UiTokens.SIZE_QUICK_HANDLE_H
	box.inset = Vector4((UiTokens.SIZE_QUICK_HANDLE_TOUCH_W - UiTokens.SIZE_QUICK_HANDLE_W) * 0.5, 0,
		(UiTokens.SIZE_QUICK_HANDLE_TOUCH_W - UiTokens.SIZE_QUICK_HANDLE_W) * 0.5, 0)
	for s in [&"normal", &"hover", &"focus", &"pressed", &"hover_pressed", &"disabled"]: b.add_theme_stylebox_override(s, box)
	var grip := Panel.new()
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.size = Vector2(UiTokens.SIZE_QUICK_HANDLE_GRIP_W, UiTokens.SIZE_QUICK_HANDLE_GRIP_H)
	grip.position = (b.size - grip.size) * 0.5
	grip.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_QUICK_HANDLE_GRIP, UiTokens.SIZE_QUICK_HANDLE_GRIP_H * 0.5))
	b.add_child(grip)
	b.pressed.connect(func(): handle_tapped.emit())
	return b

# ------------------------------------------------------------------ refresh

func _refresh() -> void:
	if _row == null: return
	for i in SLOTS:
		var cell := _cells[i]
		cell.visible = not collapsed and not bag_only
		if i == _dragging: continue
		var d := slot(i)
		var id := str(d.get("id", ""))
		cell.icon = d.get("icon", null)
		cell.title = str(d.get("title", ""))
		var qty := int(d.get("quantity", 0))
		cell.quantity = "×%d" % qty if id != "" else ""
		cell.pinned = bool(d.get("pinned", false)) and id != ""
		if id == "": cell.state = UiItemCell.State.GHOST if bool(d.get("ghost", false)) else UiItemCell.State.EMPTY
		elif i == _target: cell.state = UiItemCell.State.DROP_TARGET
		elif id == selected: cell.state = UiItemCell.State.SELECTED
		elif qty <= 0 and cell.pinned: cell.state = UiItemCell.State.ZERO
		else: cell.state = UiItemCell.State.DEFAULT
	_handle.visible = collapsed and not bag_only
	mouse_filter = Control.MOUSE_FILTER_IGNORE if collapsed or bag_only else Control.MOUSE_FILTER_STOP
	# Collapsed or bag-only: the end stays at the right (BAR-1-2); the handle sits centred when collapsed.
	_row.alignment = BoxContainer.ALIGNMENT_END if collapsed or bag_only else BoxContainer.ALIGNMENT_BEGIN
	_end_icon.texture = CLOSE_GLYPH if bag_open else BAG_GLYPH
	_end_icon.self_modulate = UiTokens.COLOR_TEXT if bag_open else Color.WHITE
	_end_label.text = "Close" if bag_open else "Bag"
	_end_dot.visible = capacity_warning and not bag_open

# ------------------------------------------------------------------ gestures

func _on_tapped(i: int) -> void:
	var id := str(slot(i).get("id", ""))
	if id == "": ghost_tapped.emit(i)
	else: slot_tapped.emit(id)

func _on_gesture(o: Dictionary, i: int) -> void:
	var id := str(slot(i).get("id", ""))
	match o.kind:
		&"lift":
			if id == "": return
			_cells[i].state = UiItemCell.State.LIFTED
			_tick()
		&"pin_toggle":
			if id != "": pin_toggled.emit(id, not bool(slot(i).get("pinned", false)))
			_end_drag()
		&"drag_start":
			if id == "": return
			_start_drag(i, o.pos)
		&"drag_move":
			if _dragging == i: _move_drag(o.pos)
		&"drop":
			if _dragging == i: _drop(o.pos)
			else: _end_drag()
		&"swipe_up":
			bag_requested.emit()
		&"cancel":
			if _dragging == i: _fly_back()
			else: _end_drag()

## Drop a drag in progress as if released nowhere: the slot flies back (app paused, a drawer opening).
func cancel_drag() -> void:
	if _dragging >= 0: _fly_back()

## The remove zone while a slot is dragged (null otherwise).
func remove_zone() -> UiBarRemoveZone: return _zone

func _tick() -> void:
	if haptics and OS.has_feature("mobile"): Input.vibrate_handheld(20)

func _start_drag(i: int, global_pos: Vector2) -> void:
	_dragging = i
	_ghost = UiItemCell.new(UiItemCell.Density.QUICK)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := slot(i)
	_ghost.icon = d.get("icon", null)
	_ghost.title = str(d.get("title", ""))
	_ghost.quantity = "×%d" % int(d.get("quantity", 0))
	_ghost.pinned = bool(d.get("pinned", false))
	_ghost.state = UiItemCell.State.LIFTED
	_ghost.top_level = true
	_ghost.pivot_offset = _ghost.custom_minimum_size * 0.5
	add_child(_ghost)
	_cells[i].state = UiItemCell.State.EMPTY
	_zone = UiBarRemoveZone.new()
	_zone.theme = theme
	add_child(_zone)
	_zone.center = zone_center()
	_zone.appear()
	_move_drag(global_pos)

## Where the remove zone sits: screen x-centre, 96 px above the bar (scene y 612 on 360 × 800).
func zone_center() -> Vector2:
	var vp := get_viewport_rect().size.x if is_inside_tree() else 360.0
	return GestureArbiter.remove_zone_center(get_global_rect(), vp)

func _move_drag(global_pos: Vector2) -> void:
	if _ghost: _ghost.global_position = global_pos - Vector2(_ghost.custom_minimum_size.x * 0.5, _ghost.custom_minimum_size.y + _RIDE_ABOVE)
	var over := _zone != null and global_pos.distance_to(_zone.center) <= GestureArbiter.REMOVE_ZONE_HIT
	if _zone and over != _zone.hover:
		_zone.hover = over
		if over: _tick()
		if _ghost: _ghost.scale = Vector2.ONE * (_HOVER_SCALE if over else 1.0)
	var rects := _slot_rects()
	var t := -1
	for k in rects.size():
		if k != _dragging and (rects[k] as Rect2).grow(GestureArbiter.DROP_SLOT_GROW).has_point(global_pos): t = k
	if t != _target:
		_target = t
		_refresh()

func _drop(global_pos: Vector2) -> void:
	var from := _dragging
	var id := str(slot(from).get("id", ""))
	var where := GestureArbiter.drop_on_bar(global_pos, from, _slot_rects(), zone_center())
	match where.kind:
		&"pin_toggle":
			_end_drag()
			pin_toggled.emit(id, not bool(slot(from).get("pinned", false)))
		&"swap":
			_end_drag()
			slots_swapped.emit(from, int(where.index))
		&"remove":
			_fly_into_zone()
			slot_removed.emit(id)
		_:
			_fly_back()

func _slot_rects() -> Array:
	return _cells.map(func(c: UiItemCell) -> Rect2: return c.get_global_rect())

## Cancel: the dragged slot flies back to its place (200 ms ease-out), then the bar is as it was.
func _fly_back() -> void:
	var ghost := _ghost
	var home := _cells[_dragging].global_position if _dragging >= 0 else Vector2.ZERO
	_ghost = null
	_end_drag()
	if ghost == null: return
	ghost.scale = Vector2.ONE
	var t := ghost.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(ghost, ^"global_position", home, UiKit.secs(_FLY_BACK_MS))
	t.tween_callback(ghost.queue_free)

## Remove: the slot flies into the zone's centre (150 ms) while the zone fades out (200 ms).
func _fly_into_zone() -> void:
	var ghost := _ghost
	var zone := _zone
	_ghost = null
	_zone = null
	_end_drag()
	if zone: zone.vanish()
	if ghost == null: return
	var target := (zone.center if zone else zone_center()) - ghost.custom_minimum_size * 0.5
	var t := ghost.create_tween().set_parallel(true)
	t.tween_property(ghost, ^"global_position", target, UiKit.secs(_FLY_IN_MS))
	t.tween_property(ghost, ^"scale", Vector2.ONE * 0.4, UiKit.secs(_FLY_IN_MS))
	t.chain().tween_callback(ghost.queue_free)

func _end_drag() -> void:
	_dragging = -1
	_target = -1
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _zone:
		_zone.vanish()
		_zone = null
	_refresh()

