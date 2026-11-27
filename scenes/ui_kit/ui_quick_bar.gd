class_name UiQuickBar
extends Control
## Quick bar (SGODOT-221, LOCK-04 / 05; plan §10.3, WP7-B F-04 §3): five QuickSlot cells and the Bag / Close
## end (Compact/QuickEnd/Bag 907:72112), or the collapsed handle (page-14 frames 676:63515–7) with the Bag end
## when no action is chosen. Data in, intents out; the caller owns selection, pins and the bag.
##   tap a slot → slot_tapped(id) (select, tap again to clear); tap an empty ghost → ghost_tapped(index)
##   hold 450 ms → the slot floats (LIFTED) with a light vibration and the two BarDropZones fade in 96 px over the
##   bar (Pin / Unpin, Remove). It drags at once: it rides 24 px above the finger, its place shows a gap; over a
##   zone (within 44 px) the zone darkens, one light tick, the slot shrinks to 80 %. Where the finger lets go
##   decides (LOCK-04 / 05 v1.11, 221 b0a83924; GestureArbiter.drop_on_bar):
##     the Pin / Unpin zone → pin_toggled(id, pinned); the slot flies home (150 ms) and its pin badge pops
##     the Remove zone → the slot flies into it and slot_removed(id)
##     another slot (+6 px, DROP_TARGET while over it) → slots_swapped(a, b): places only, pins follow the items
##     its own slot, anywhere else, a second finger or cancel_drag() (app paused, a drawer opening) → it flies
##     back, nothing changes
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
## Farm style: the Seeds end was tapped (the owner opens the bag on the seeds).
signal seeds_pressed

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
## The Bag end (its cell on the bar): where an ItemFly lands (SGODOT-289).
func bag_end() -> Control: return _end

## The bag drawer is open: the end reads Close (LOCK-04).
var bag_open := false: set = set_bag_open
## Bag at ≥ 90% capacity: amber dot on the end (§10.3.1).
var capacity_warning := false: set = set_capacity_warning
## Spaces without a quick bar (kitchen, counters, the map): only the Bag end stays (plan §10.3.5, MAP-1).
var bag_only := false: set = set_bag_only
## The end's Bag icon (the dynamic farm gives C-86's glass-button bag, UiArt.SYS_BAG; P0 keeps its glyph).
var bag_icon: Texture2D = BAG_GLYPH: set = set_bag_icon
## Vibrate on lift; off in tests and the gallery.
var haptics := true
## Docked as the bag drawer's top row (SGODOT-225): the drop zones open under the bar instead of over it (q(61)).
var zones_below := false

var _cells: Array[UiItemCell] = []
var _row: HBoxContainer
var _end: Button
var _end_icon: TextureRect
var _end_label: Label
var _end_dot: Panel
var _handle: Button
var _ghost: UiItemCell
var _pin_zone: UiBarDropZone
var _remove_zone: UiBarDropZone
var _lifted := -1
var _dragging := -1
var _target := -1

const _RIDE_ABOVE := 24.0       # the dragged slot rides this far above the finger (LOCK-04 v1.11)
const _HOVER_SCALE := 0.8       # …and shrinks to this over a drop zone
const FLY_BACK_MS := 200        # cancel: back to its place, ease-out (a lifted bag cell too, P0Ui._bag_cancel)
const _FLY_HOME_MS := 150       # pin toggle: back to its place
const _FLY_IN_MS := 150         # remove: into the zone's centre

## C-186 farm style (C-185 §3.1 D, C-185#79 after the owner's attachment-1820), `UiQuickBar.new(true)`: a Seeds end
## on the left (the seed the key would sow: `seeds_item`), `slot_count` 4 frosted slots and the Bag end on the right;
## the bar frosted white (`bar/frost`, radius 20, a 1.2 white edge), both ends opaque cream clay tiles with the colour
## icon, three yellow sparkles and ink text. The Bag end's capacity dot is the one P0 shows (`capacity_warning`).
## Presses play M-01 on the slots and ends; a count that changes rolls (MS-03); `landing_for` is where a gain lands.
var farm_style := false
var slot_count := SLOTS
## Farm style: {id, icon} of the seed shown on the Seeds end, or {} (the end then shows the bag's seed icon dimmed).
var seeds_item := {}: set = set_seeds_item
var _seeds: Button
var _seeds_icon: TextureRect
var _seeds_label: Label
var _shown_qty := {}
## Farm style: the item ids the slots showed at the last refresh (MS-10 compares the next ones with them).
var _bar_ids: Array = []

## UI v3 (C-Q1, C-105): the bar's dark glass, `radius/lg`, drawn this far outside the slots (it takes no room, so
## every placement keeps its layout); hidden while collapsed or bag-only.
const GLASS_PAD := 6.0
var _glass: Panel

func _init(farm_ := false) -> void:
	farm_style = farm_
	if farm_style: slot_count = UiTokens.SIZE_QUICK_SLOTS_FARM
	custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_BAR_W, UiTokens.SIZE_QUICK_BAR_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_glass = Panel.new()
	_glass.name = "Glass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var lift := UiTokens.SIZE_QUICK_SLOT_H - UiTokens.SIZE_QUICK_SLOT_SURFACE_H
	_glass.offset_left = -GLASS_PAD
	_glass.offset_top = lift - GLASS_PAD
	_glass.offset_right = GLASS_PAD
	_glass.offset_bottom = GLASS_PAD
	if farm_style: _glass.add_theme_stylebox_override(&"panel", UiClay.frost(UiTokens.SIZE_QUICK_FROST_RADIUS))
	else: _glass.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_GLASS_FILL, UiTokens.RADIUS_LG))
	add_child(_glass)
	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_QUICK_BAR_GAP))
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	if farm_style:
		_seeds = _build_seeds()
		_row.add_child(_seeds)
	for i in slot_count:
		var cell := UiItemCell.new(UiItemCell.Density.QUICK)
		cell.frost = farm_style
		cell.tapped.connect(_on_tapped.bind(i))
		cell.gesture.connect(_on_gesture.bind(i))
		if farm_style: cell.gui_input.connect(_press_slot.bind(cell))
		_cells.append(cell)
		_row.add_child(cell)
	_end = _build_end()
	_row.add_child(_end)
	if farm_style:
		# Seeds end + 4 slots + Bag end share the bar's width: spread them across it.
		_row.add_theme_constant_override(&"separation", int((UiTokens.SIZE_QUICK_BAR_W - UiTokens.SIZE_QUICK_END_FARM_W * 2.0 \
			- UiTokens.SIZE_QUICK_SLOT_W * slot_count) / float(slot_count + 1)))
	_handle = _build_handle()
	add_child(_handle)
	_refresh()

func set_slots(v: Array) -> void: slots = v; _refresh()
func set_selected(v: String) -> void: selected = v; _refresh()
func set_collapsed(v: bool) -> void: collapsed = v; _refresh()
func set_bag_open(v: bool) -> void: bag_open = v; _refresh()
func set_capacity_warning(v: bool) -> void: capacity_warning = v; _refresh()
func set_bag_only(v: bool) -> void: bag_only = v; _refresh()
func set_bag_icon(v: Texture2D) -> void: bag_icon = v; _refresh()
func set_seeds_item(v: Dictionary) -> void: seeds_item = v; _refresh()
func seeds_end() -> Button: return _seeds

## Where a gain of `id` lands (MS-04): the slot holding it, the Seeds end for the seed it shows, else the Bag end.
func landing_for(id: String) -> Control:
	var cell := cell_for(id)
	if cell != null: return cell
	if farm_style and _seeds != null and _seeds.visible and str(seeds_item.get("id", "")) == id: return _seeds
	return _end

## M-01 on a frosted slot's surface (the cell itself sits in the row, which resets a scale).
func _press_slot(e: InputEvent, cell: UiItemCell) -> void:
	var down := false
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT: down = e.pressed
	elif e is InputEventScreenTouch: down = e.pressed
	else: return
	UiMotion.press(cell._surface, down)

## Farm style: the Seeds end, a cream clay tile 56 × 68 like the Bag end: the seed's colour icon, sparkles, `Seeds`.
func _build_seeds() -> Button:
	var b := _end_tile("Seeds")
	b.name = "SeedsEnd"
	_seeds_icon = b.get_node("Icon") as TextureRect
	_seeds_label = b.get_node("Label") as Label
	b.pressed.connect(func(): seeds_pressed.emit())
	return b

## A cream clay end tile (farm style): icon 26 at the top, sparkles beside it, its word under it in ink.
func _end_tile(word: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var w := float(UiTokens.SIZE_QUICK_END_FARM_W)
	b.custom_minimum_size = Vector2(w, UiTokens.SIZE_QUICK_SLOT_H)
	var lift := UiTokens.SIZE_QUICK_SLOT_H - UiTokens.SIZE_QUICK_SLOT_SURFACE_H
	var up := UiClay.face(UiTokens.SIZE_HUD_CLAY_RADIUS, UiTokens.COLOR_BAR_END_TILE)
	up.expand_margin_top = -lift
	var down := UiClay.face_pressed(UiTokens.SIZE_HUD_CLAY_RADIUS)
	down.expand_margin_top = -lift
	for st in [&"normal", &"hover", &"focus", &"disabled"]: b.add_theme_stylebox_override(st, up)
	for st in [&"pressed", &"hover_pressed"]: b.add_theme_stylebox_override(st, down)
	var icon := UiKit.icon(null, 26.0)
	icon.name = "Icon"
	icon.position = Vector2((w - 26.0) * 0.5, lift + 9.0)
	b.add_child(icon)
	var sparkle := Control.new()
	sparkle.name = "Sparkle"
	sparkle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sparkle.position = Vector2((w + 26.0) * 0.5 - 1.0, lift + 8.0)
	sparkle.draw.connect(func(): UiClay.draw_sparkle(sparkle, Vector2.ZERO, 0.85))
	b.add_child(sparkle)
	var label := UiKit.label(word, UiTokens.STYLE_C11_B, UiTokens.COLOR_HUD_CLAY_INK)
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.anchor_right = 1.0
	label.offset_top = lift + _END_LABEL_TOP
	label.offset_bottom = lift + _END_LABEL_TOP + _END_LABEL_H
	b.add_child(label)
	UiMotion.press_feedback(b)
	return b

func cells() -> Array[UiItemCell]: return _cells
func end_button() -> Button: return _end
func handle_button() -> Button: return _handle
func is_dragging() -> bool: return _dragging >= 0
## A slot floated by a long press and not moved yet (it drags as soon as the finger moves).
func is_lifted() -> bool: return _lifted >= 0

func slot(i: int) -> Dictionary:
	return slots[i] if i < slots.size() and slots[i] is Dictionary else {}

# ------------------------------------------------------------------ build

func _build_end() -> Button:
	if farm_style:
		var t := _end_tile("Bag")
		t.name = "BagEnd"
		_end_icon = t.get_node("Icon") as TextureRect
		_end_label = t.get_node("Label") as Label
		_end_dot = Panel.new()
		_end_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lift_ := UiTokens.SIZE_QUICK_SLOT_H - UiTokens.SIZE_QUICK_SLOT_SURFACE_H
		_end_dot.position = Vector2(UiTokens.SIZE_QUICK_END_FARM_W - 11.0, lift_ + 4.0)
		_end_dot.size = Vector2(UiTokens.SIZE_CAPACITY_DOT, UiTokens.SIZE_CAPACITY_DOT)
		_end_dot.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_WARNING, UiTokens.SIZE_CAPACITY_DOT * 0.5))
		t.add_child(_end_dot)
		t.pressed.connect(func(): if bag_open: close_requested.emit() else: bag_requested.emit())
		return t
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(UiTokens.SIZE_QUICK_END_W, UiTokens.SIZE_QUICK_SLOT_H)
	var lift := UiTokens.SIZE_QUICK_SLOT_H - UiTokens.SIZE_QUICK_SLOT_SURFACE_H
	# v3: a glass slot like the others (C-Q2); pressed raises the glass (C-R1)
	var surface := UiStyleBox.make(UiTokens.COLOR_GLASS_SLOT, UiTokens.RADIUS_MD)
	surface.inset = Vector4(0, lift, 0, 0)
	var pressed := UiStyleBox.make(UiTokens.COLOR_GLASS_FILL_STRONG, UiTokens.RADIUS_MD)
	pressed.inset = surface.inset
	for s in [&"normal", &"hover", &"focus", &"disabled"]: b.add_theme_stylebox_override(s, surface)
	for s in [&"pressed", &"hover_pressed"]: b.add_theme_stylebox_override(s, pressed)
	_end_icon = UiKit.icon(null, UiTokens.SIZE_QUICK_SLOT_ICON)
	_end_icon.position = Vector2((UiTokens.SIZE_QUICK_END_W - UiTokens.SIZE_QUICK_SLOT_ICON) * 0.5, lift + _END_ICON_TOP)
	b.add_child(_end_icon)
	_end_label = UiKit.label("", UiTokens.STYLE_C11_B, UiTokens.COLOR_TEXT_ON_DARK)
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
	# MS-10: what the slots showed before this refresh (their items and icons), for the refill motion after it.
	var before_ids := _bar_ids
	var before_icons := _cells.map(func(c: UiItemCell): return c.icon)
	var shown := {}   # the counts now on the bar: an item that left it rolls no stale number when it comes back
	for i in slot_count:
		var cell := _cells[i]
		cell.visible = not collapsed and not bag_only
		if i == _dragging:
			var held := str(slot(i).get("id", ""))
			if _shown_qty.has(held): shown[held] = _shown_qty[held]
			continue
		var d := slot(i)
		var id := str(d.get("id", ""))
		cell.icon = d.get("icon", null)
		cell.title = str(d.get("title", ""))
		var qty := int(d.get("quantity", 0))
		# MS-03: a count that changes for the same item rolls to the new number (farm style).
		var was := int(_shown_qty.get(id, -1))
		if farm_style and id != "" and was >= 0 and was != qty and str(cell.get_meta(&"_qty_id", "")) == id \
				and cell.is_inside_tree() and not UiMotion.reduced:
			_roll_qty(cell, was, qty)
		else: cell.quantity = "×%d" % qty if id != "" else ""
		cell.set_meta(&"_qty_id", id)
		if id != "": shown[id] = qty
		if id != "" and str(d.get("cooldown", "")) != "": cell.quantity += " · " + str(d.cooldown)
		cell.pinned = bool(d.get("pinned", false)) and id != ""
		if i == _target: cell.state = UiItemCell.State.DROP_TARGET   # an empty slot too: a bag item lands there (225)
		elif id == "": cell.state = UiItemCell.State.GHOST if bool(d.get("ghost", false)) else UiItemCell.State.EMPTY
		elif id == selected: cell.state = UiItemCell.State.SELECTED
		elif qty <= 0 and cell.pinned: cell.state = UiItemCell.State.ZERO
		else: cell.state = UiItemCell.State.DEFAULT
	_shown_qty = shown
	if farm_style:
		var now_ids := []
		for i in slot_count: now_ids.append("" if i == _dragging else str(slot(i).get("id", "")))
		if not before_ids.is_empty() and _dragging < 0 and not collapsed and not bag_only and not UiMotion.reduced \
				and is_visible_in_tree():
			_refill(before_ids, before_icons, now_ids)
		_bar_ids = now_ids
	_handle.visible = collapsed and not bag_only
	mouse_filter = Control.MOUSE_FILTER_IGNORE if collapsed or bag_only else Control.MOUSE_FILTER_STOP
	# Collapsed or bag-only: the end stays at the right (BAR-1-2); the handle sits centred when collapsed.
	_row.alignment = BoxContainer.ALIGNMENT_END if collapsed or bag_only else BoxContainer.ALIGNMENT_BEGIN
	_end_icon.texture = CLOSE_GLYPH if bag_open else bag_icon
	_end_icon.self_modulate = (UiTokens.COLOR_HUD_CLAY_INK if farm_style else UiTokens.COLOR_TEXT_ON_DARK) if bag_open else Color.WHITE
	if _seeds != null:
		_seeds.visible = not collapsed and not bag_only
		_seeds_icon.texture = seeds_item.get("icon", null)
		_seeds_icon.modulate.a = 1.0 if str(seeds_item.get("id", "")) != "" else UiTokens.OPACITY_ZERO_ICON
	_glass.visible = not collapsed and not bag_only
	_end_label.text = "Close" if bag_open else "Bag"
	_end_dot.visible = capacity_warning and not bag_open

# ------------------------------------------------------------------ MS-10 refill (C-185 §3.1 D / §4, C-211)

## A slot's item used up: its icon fades out where it was (120), then the items after it slide left into the gap
## (`motion/duration/quickBarRefill`, 300, standard). A new item in a slot pops in 0.6 → 1 (200, pop). Reduced: the
## slots simply show their new items (the caller skips this).
func _refill(before: Array, icons: Array, now: Array) -> void:
	var gone := false
	for j in before.size():
		var id := str(before[j])
		if id == "" or id in now or j >= _cells.size(): continue
		gone = true
		_fade_away(_cells[j], icons[j])
	var pitch: float = _cells[1].position.x - _cells[0].position.x if _cells.size() > 1 else UiTokens.SIZE_QUICK_SLOT_W
	for i in now.size():
		var id := str(now[i])
		if id == "":
			# A slot left empty by the slide shows its empty frame once the items have slid past it.
			if i < before.size() and str(before[i]) != "": _empty_after(_cells[i], (UiTokens.MOTION_DURATION_FAST_MS if gone else 0.0) \
				+ UiTokens.MOTION_DURATION_QUICK_BAR_REFILL_MS)
			continue
		var j := before.find(id)
		if j < 0: _pop_in(_cells[i])
		elif j > i: _slide_in(_cells[i], (j - i) * pitch, UiTokens.MOTION_DURATION_FAST_MS if gone else 0.0)

## The used-up item's icon, where its slot drew it, fading out over 120 on top of the bar.
func _fade_away(cell: UiItemCell, icon: Texture2D) -> void:
	if icon == null or cell._icon == null: return
	var ghost := TextureRect.new()
	ghost.name = "RefillGhost"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.texture = icon
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var at := cell._icon.get_global_rect()
	ghost.position = at.position - get_global_rect().position
	ghost.size = at.size
	add_child(ghost)
	var tw := UiMotion.tween(ghost, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_property(ghost, "modulate:a", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	tw.tween_callback(ghost.queue_free)

## A slot now holding the item that sat `offset` to its right: its surface starts there and slides home.
func _slide_in(cell: UiItemCell, offset: float, delay_ms: float) -> void:
	var surface := cell._surface
	UiMotion._kill(surface, &"_ui_refill")
	_kill_empty(surface)
	var home: float = surface.get_meta(&"_refill_home", surface.position.x)
	surface.set_meta(&"_refill_home", home)
	surface.position.x = home + offset
	var tw := UiMotion.tween(surface, UiTokens.MOTION_EASING_STANDARD)
	if delay_ms > 0.0: tw.tween_interval(UiMotion.secs(delay_ms))
	tw.tween_property(surface, "position:x", home, UiMotion.secs(UiTokens.MOTION_DURATION_QUICK_BAR_REFILL_MS))
	tw.tween_callback(func(): surface.remove_meta(&"_refill_home"))
	surface.set_meta(&"_ui_refill", tw)

func _kill_empty(surface: Control) -> void:
	if not surface.has_meta(&"_ui_empty"): return
	UiMotion._kill(surface, &"_ui_empty")
	surface.modulate.a = 1.0

## An emptied slot's frame waits `delay_ms`, then fades in (120).
func _empty_after(cell: UiItemCell, delay_ms: float) -> void:
	var surface := cell._surface
	UiMotion._kill(surface, &"_ui_empty")
	surface.modulate.a = 0.0
	var tw := UiMotion.tween(surface, UiTokens.MOTION_EASING_STANDARD)
	tw.tween_interval(UiMotion.secs(delay_ms))
	tw.tween_property(surface, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	surface.set_meta(&"_ui_empty", tw)

## A new item in its slot: the surface pops 0.6 → 1 (200, pop) from its centre.
func _pop_in(cell: UiItemCell) -> void:
	var surface := cell._surface
	UiMotion._kill(surface, &"_ui_enter")
	_kill_empty(surface)
	surface.pivot_offset = surface.size * 0.5
	surface.scale = Vector2.ONE * UiTokens.MOTION_SCALE_SLOT_ENTER
	var tw := UiMotion.tween(surface, UiTokens.MOTION_EASING_POP)
	tw.tween_property(surface, "scale", Vector2.ONE, UiMotion.secs(UiTokens.MOTION_DURATION_BASE_MS))
	surface.set_meta(&"_ui_enter", tw)

# ------------------------------------------------------------------ gestures

## The slot's `×N` counts from `from` to `to` (400, MS-03); rising, the slot's surface bumps. The cell keeps the
## final count as its `quantity` (its own refreshes write that); the roll writes over it each frame until it ends.
func _roll_qty(cell: UiItemCell, from: int, to: int) -> void:
	cell.quantity = "×%d" % to
	cell._qty.text = "×%d" % from
	UiMotion.roll(cell._qty, from, to, "×%d", cell._surface)

func _on_tapped(i: int) -> void:
	var id := str(slot(i).get("id", ""))
	if id == "": ghost_tapped.emit(i)
	else: slot_tapped.emit(id)

func _on_gesture(o: Dictionary, i: int) -> void:
	var id := str(slot(i).get("id", ""))
	match o.kind:
		&"lift":
			if id == "": return
			_lifted = i
			_cells[i].state = UiItemCell.State.LIFTED
			_tick()
			_show_zones(bool(slot(i).get("pinned", false)))
		&"drag_start":
			if id == "" or _lifted != i: return
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

## Drop a lift or drag in progress as if released nowhere: the slot flies back (app paused, a drawer opening).
func cancel_drag() -> void:
	if _dragging >= 0: _fly_back()
	elif _lifted >= 0: _end_drag()

## The slot under a finger dragging something in from the bag drawer (SGODOT-225): the slot itself, filled or
## empty (gaps stay where they are, LOCK-05 v1.10), grown by DROP_SLOT_GROW like a slot-to-slot drop; -1 off the
## slots, or while collapsed / bag-only.
func slot_at(global_pos: Vector2) -> int:
	if collapsed or bag_only: return -1
	# Grown slots overlap across the gap between neighbours: the nearest centre wins.
	var rects := _slot_rects()
	var best := -1
	for i in rects.size():
		var r: Rect2 = rects[i]
		if not r.grow(GestureArbiter.DROP_SLOT_GROW).has_point(global_pos): continue
		if best < 0 or global_pos.distance_to(r.get_center()) < global_pos.distance_to((rects[best] as Rect2).get_center()): best = i
	return best

## Hover feedback for a drag from outside the bar: that slot shows DROP_TARGET (the slot-to-slot look); -1 clears.
## Ignored while one of the bar's own slots is being dragged (that drag owns the target).
func set_drop_target(index: int) -> void:
	if _dragging >= 0: return
	var t := index if index >= 0 and index < slot_count else -1
	if t == _target: return
	_target = t
	_refresh()

## A first-time item just reached the bar (§10.3.3 ④, §14.2): its slot rings once in color/new (UiItemCell.flash).
## Call after `slots` is set; an id not on the bar, or a folded bar, is ignored.
func flash(id: String) -> void:
	if collapsed or bag_only or id == "": return
	for i in mini(slots.size(), slot_count):
		if str(slot(i).get("id", "")) == id:
			_cells[i].flash()
			return

## The guide may highlight a visible slot, never select or insert it for the player.
func cell_for(id: String) -> UiItemCell:
	if collapsed or bag_only or id == "": return null
	for i in mini(slots.size(), slot_count):
		if str(slot(i).get("id", "")) == id: return _cells[i]
	return null

## The drop zones while a slot is lifted: [Pin / Unpin, Remove], or [] otherwise.
func drop_zones() -> Array[UiBarDropZone]:
	var out: Array[UiBarDropZone] = []
	if _pin_zone: out.append(_pin_zone)
	if _remove_zone: out.append(_remove_zone)
	return out

func _tick() -> void:
	if haptics and OS.has_feature("mobile"): Input.vibrate_handheld(20)

func _show_zones(pinned: bool) -> void:
	var centers := GestureArbiter.drop_zone_centers(get_global_rect(), zones_below)
	_pin_zone = UiBarDropZone.new(UiBarDropZone.Kind.UNPIN if pinned else UiBarDropZone.Kind.PIN)
	_remove_zone = UiBarDropZone.new(UiBarDropZone.Kind.REMOVE)
	for k in 2:
		var z: UiBarDropZone = [_pin_zone, _remove_zone][k]
		z.theme = theme
		add_child(z)
		z.center = centers[k]
		z.appear()

func _hide_zones() -> void:
	for z in drop_zones(): z.vanish()
	_pin_zone = null
	_remove_zone = null

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
	_move_drag(global_pos)

func _move_drag(global_pos: Vector2) -> void:
	if _ghost: _ghost.global_position = global_pos - Vector2(_ghost.custom_minimum_size.x * 0.5, _ghost.custom_minimum_size.y + _RIDE_ABOVE)
	var any := false
	for z in drop_zones():
		var over := global_pos.distance_to(z.center) <= GestureArbiter.DROP_ZONE_HIT
		if over != z.hover:
			z.hover = over
			if over: _tick()
		any = any or over
	if _ghost: _ghost.scale = Vector2.ONE * (_HOVER_SCALE if any else 1.0)
	var rects := _slot_rects()
	var t := -1
	for k in rects.size():
		if k != _dragging and (rects[k] as Rect2).grow(GestureArbiter.DROP_SLOT_GROW).has_point(global_pos): t = k
	if t != _target:
		_target = t
		_refresh()

func _drop(global_pos: Vector2) -> void:
	var from := _dragging
	var d := slot(from)
	var id := str(d.get("id", ""))
	var centers := GestureArbiter.drop_zone_centers(get_global_rect(), zones_below)
	var where := GestureArbiter.drop_on_bar(global_pos, from, _slot_rects(), centers[0], centers[1])
	match where.kind:
		&"pin_toggle":
			_fly_back(_FLY_HOME_MS)
			pin_toggled.emit(id, not bool(d.get("pinned", false)))
			_tick()
			_cells[from].pop_pin.call_deferred()   # after the owner redraws the slot with its new pin state
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

## Back to its place (200 ms ease-out on a cancel, 150 ms after a pin toggle), then the bar is as it was.
func _fly_back(ms := FLY_BACK_MS) -> void:
	var ghost := _ghost
	var home := _cells[_dragging].global_position if _dragging >= 0 else Vector2.ZERO
	_ghost = null
	_end_drag()
	if ghost == null: return
	ghost.scale = Vector2.ONE
	var t := ghost.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(ghost, ^"global_position", home, UiKit.secs(ms))
	t.tween_callback(ghost.queue_free)

## Remove: the slot flies into the Remove zone's centre (150 ms) while the zones fade out (200 ms).
func _fly_into_zone() -> void:
	var ghost := _ghost
	var target := _remove_zone.center if _remove_zone else GestureArbiter.drop_zone_centers(get_global_rect(), zones_below)[1]
	_ghost = null
	_end_drag()
	if ghost == null: return
	var t := ghost.create_tween().set_parallel(true)
	t.tween_property(ghost, ^"global_position", target - ghost.custom_minimum_size * 0.5, UiKit.secs(_FLY_IN_MS))
	t.tween_property(ghost, ^"scale", Vector2.ONE * 0.4, UiKit.secs(_FLY_IN_MS))
	t.chain().tween_callback(ghost.queue_free)

func _end_drag() -> void:
	_dragging = -1
	_lifted = -1
	_target = -1
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_hide_zones()
	_refresh()
