class_name P0StorageSheet
extends Control
## COOK-P0-5 Spice Rack / COOK-P0-6 Warming Cabinet (SGODOT-226; plan §7.7, appendix B.7, q(46)): the sheet over
## the kitchen corner with × above it. The rack lists the stored seasonings (real count) with Open Experiment ›
## and Details ›; the cabinet lists its dishes, and the selected row carries Eat · +N Energy / Take one.
## Facts come from P0KitchenLogic; the owner sends the commands.

signal command(cmd: Dictionary)
signal open_experiment
signal details
signal close_requested

const RACK_H := 484.0          # COOK-P0-5 sheet 316 → 800
const CABINET_H := 369.0       # COOK-P0-6 sheet 431 → 800
const CLOSE_GAP := 6.0         # × 44 sits 6 above the sheet's top edge
const _INSET := 4.0            # the drawer's 12 + 4 = the sheet's 16 content inset (COOK-P0-5 main content x 16)
const _SELECTED_RADIUS := 12.0

var kind := "rack"             # rack | cabinet
var view: Dictionary = {}
var selected := ""
var safe_bottom := 0.0

var _drawer: UiDrawer
var _close: UiCloseButton
var _list: VBoxContainer
var _rows := {}            # cabinet row id → its button (the guide's row pulse, SGODOT-368)
var _eat: Control          # the selected row's Eat

func _init(kind_: String, view_: Dictionary) -> void:
	kind = kind_
	view = view_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.theme()

func _ready() -> void:
	_drawer = UiDrawer.new(RACK_H if kind == "rack" else CABINET_H)
	_drawer.safe_bottom = safe_bottom
	_drawer.close_requested.connect(func(): close_requested.emit())
	add_child(_drawer)
	var inset := MarginContainer.new()
	for side in [&"margin_left", &"margin_top", &"margin_right"]: inset.add_theme_constant_override(side, int(_INSET))
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_drawer.body.add_child(inset)
	var scroll := TouchScrollContainer.new()   # drags that start on a row still scroll (0.10.3)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inset.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", int(UiTokens.SPACE_OVERLAY_BODY))
	scroll.add_child(_list)
	_close = UiCloseButton.new()
	_close.pressed.connect(func(): close_requested.emit())
	add_child(_close)
	resized.connect(_place_close)
	refresh(view)

func _place_close() -> void:
	var h := (RACK_H if kind == "rack" else CABINET_H) + safe_bottom
	_close.position = Vector2(size.x - UiTokens.SPACE_PAGE - UiTokens.SIZE_CLOSE, size.y - h - CLOSE_GAP - UiTokens.SIZE_CLOSE)

func refresh(view_: Dictionary) -> void:
	view = view_
	if _list == null: return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows = {}
	_eat = null
	if kind == "rack": _build_rack()
	else: _build_cabinet()
	_place_close.call_deferred()

func _build_rack() -> void:
	_list.add_child(UiObjectHeader.new({title = "Spice Rack", state = "Storage", effect = "Keep seasonings ready for cooking."}))
	for r in P0KitchenLogic.rack_rows(view):
		_list.add_child(UiItemRow.new({icon = P0Logic.icon(str(r.id)), title = str(r.title), quantity = str(r.quantity), quantity_label = str(r.unit)}))
	var exp := UiNavButton.new("Open Experiment")
	exp.pressed.connect(func(): open_experiment.emit())
	_list.add_child(exp)
	var info := UiNavButton.new("Details")
	info.pressed.connect(func(): details.emit())
	_list.add_child(info)

func _build_cabinet() -> void:
	var sheet := P0KitchenLogic.cabinet_sheet(view)
	_list.add_child(UiObjectHeader.new({title = str(sheet.get("title", "Warming Cabinet"))}))
	var rows: Array = sheet.get("rows", [])
	if rows.is_empty():
		_list.add_child(UiEmptyState.new(str(sheet.get("empty", "No dishes yet")), P0Logic.icon("dish_mystery"), "", UiEmptyState.Kind.ROW))
		return
	if selected == "" or not rows.any(func(r): return r.id == selected): selected = str(rows[0].id)
	for r in rows:
		_list.add_child(_cabinet_row(r))
		if str(r.id) == selected: _list.add_child(_cabinet_actions(str(r.id)))

## A row is a button: tapping it selects the dish (selected = primary tint with a primary edge, COOK-P0-6).
func _cabinet_row(r: Dictionary) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var on := str(r.id) == selected
	var box := UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT if on else UiTokens.COLOR_SURFACE, _SELECTED_RADIUS,
		UiTokens.COLOR_PRIMARY if on else UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	for st in [&"normal", &"hover", &"pressed", &"focus", &"hover_pressed"]: b.add_theme_stylebox_override(st, box)
	var row := UiItemRow.new({icon = P0Logic.icon(str(r.id).get_slice("@", 0)), title = str(r.title), state = str(r.state),
		effect = str(r.effect), quantity = str(r.quantity)})
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override(&"margin_left", int(UiTokens.SPACE_ROW))
	row.add_theme_constant_override(&"margin_right", int(UiTokens.SPACE_ROW))
	b.add_child(row)
	b.custom_minimum_size.y = row.get_combined_minimum_size().y
	row.minimum_size_changed.connect(func(): b.custom_minimum_size.y = row.get_combined_minimum_size().y)
	var id := str(r.id)
	_rows[id] = b
	b.pressed.connect(func():
		selected = id
		refresh(view))
	return b

func _cabinet_actions(id: String) -> Control:
	var a := P0KitchenLogic.cabinet_actions(view, id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", int(UiTokens.SPACE_OVERLAY_BODY))
	var eat: Dictionary = a.eat
	var eat_b := UiCommandButton.new(str(eat.text))
	eat_b.reason = str(eat.reason)
	eat_b.sends = true   # eat (§10.7.1 Offline)
	eat_b.activated.connect(func(): command.emit({"type": "eat", "item": id, "from": "cabinet"}))
	_eat = eat_b
	eat_b.unavailable_pressed.connect(func(reason): command.emit({"_toast": reason}))
	box.add_child(eat_b)
	var take := UiCommandButton.new(str(a.take), UiCommandButton.Kind.SECONDARY)
	take.reason = str(a.take_reason)
	take.sends = true   # cabinet_take (§10.7.1 Offline)
	take.activated.connect(func(): command.emit({"type": "cabinet_take", "item": id}))
	take.unavailable_pressed.connect(func(reason): command.emit({"_toast": reason}))
	box.add_child(take)
	return box

## The guide's S8 targets (SGODOT-368) for a dish's base recipe: its row while another row is selected, else null.
func guide_row(base: String) -> Control:
	if P0Logic.base_id(selected) == base: return null
	for id in _rows:
		if P0Logic.base_id(str(id)) == base: return _rows[id]
	return null

## ...and the selected row's Eat when that row is the dish.
func guide_eat(base: String) -> Control:
	return _eat if _eat != null and P0Logic.base_id(selected) == base else null
