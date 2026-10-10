class_name P0KitchenDrawer
extends UiDrawer
## The cooking drawer, LOCK-20 v5 (SGODOT-226; Figma COOK-2a Cookbook / COOK-2b Experiment, 360×480 from y 320):
##   heading   `Stove 1/1` · `Cooking Lv1` · `Empty` (q(31) order) and the 44 px close
##   modes     SegmentTab `Cookbook n/N` | `Experiment`
##   Cookbook  filter chips, the selected page's Compact/Kitchen/Recipe card with Cook (or the gap on the button,
##             LOCK-10; unknown pages only `Try in Experiment ›`), and the five-column page grid
##   Experiment `From your bag` · `n / m slots used`, family chips, the bag as kitchen cells (tap = into the
##             pot, no detail card, F-07; tap again = back), `Info ›` and Cook
## The stage above (pot, slot bar, preview) belongs to the kitchen controller; this drawer only reports:
## `page_selected`, `ingredient_tapped`, `cook_requested`.

signal page_selected(page: Dictionary)
signal ingredient_tapped(id: String, from_screen: Vector2)
signal cook_requested(cmd: Dictionary)
signal tab_changed(tab: String)
signal info_requested
## The heading's `Stove 2/3 ›` pill (SGODOT-282, b84a5e01 ②): the next stove, 3 back to 1.
signal stove_cycle_requested

const HEIGHT := 480.0
const _HEAD_H := 18.0
const _CLOSE_OVERHANG := 10.0
const _GAP := 4.0
const _GRID_GAP := 8.0
const _RECIPE := Vector2(336, 72)
const _RECIPE_BUTTON := Vector2(90, 44)
const _RECIPE_BUTTON_AT := Vector2(238, 28)   # Cook at (250, 470) in a card at (12, 442)
const _RECIPE_PAD := 8.0          # the button's right edge at 328; also its gap to the text column (C3)
const _RECIPE_ROW_GAP := 4.0      # a button too long for the corner: its own row under the facts (44 hit, 34 drawn)
const _RECIPE_MAYBE_TOP := 43.4   # "You might have what it takes" under the fact line (226 33725b5e)
const _COOK_W := 164.0
const _FACTS_X := 57.4            # the title, state and effect lines start here
const _MEDALLION := Rect2(9.4, 15.4, 38, 38)
const _DISH_ICON := 27.0

var view := {}
var tab := "cookbook": set = set_tab
var cookbook_chip := "All"
var experiment_chip := "All"
var selected_page := ""
## Item ids in the pot, one per unit (owned by the controller; set it, then refresh()).
var pot: Array = []
## Queue ×2 (Cooking Lv5, q(71)): opened from the watch sheet's Queue next ›, the primary buttons read `Queue`; the
## same cook command goes out and the server puts the pot behind the one on the stove.
var queue_mode := false: set = set_queue_mode
## Which stove this drawer is for (0-based; the heading, Stove busy and the pot all read it).
var stove_index := 0: set = set_stove_index
var _stove_pill: PanelContainer
const _PILL_H := 28.0                    # Stove n/N › pill (Figma 2152:33666): 28 high, 10 / 8 side padding, radius 12
const _PILL_PAD := Vector2(10.0, 8.0)
const _PILL_RADIUS := 12.0
const _PILL_EDGE := Color("E1DAC8")
## Big Pot Double (Homestead Lv6, b84a5e01 ③; COOK-DOUBLE-BOOK-ON 2149:136516): remembered per stove; the Cookbook card
## has it under Cook (right-aligned, its own row), Experiment left of Cook on the cook row.
var doubles := {}   # stove index → on
var _book_double: _DoubleToggle
var _exp_double: _DoubleToggle
const _DOUBLE_ROW := 32.0
signal unavailable(reason: String)
## Double was switched (the pot card above the drawer shows ×2 on its slots and its corner tag).
signal double_changed(on: bool)

var _stove: Label
var _level: Label
var _state: Label
var _modes: UiSegmentTab
var _cookbook: VBoxContainer
var _experiment: VBoxContainer
var _recipe_wrap: Control
var _recipe: Panel
var _recipe_maybe: Label
var _recipe_icon: TextureRect
var _recipe_title: Label
var _recipe_state: Label
var _recipe_buff: PanelContainer   # Legendary pages: the empty Buff slot at the end of the state line (不知火舞 540d59df)
var _recipe_effect: Label
var _effect_parts: Array = []   # `+40 Energy`, `15 s`, `Soup`: as many as fit the effect line (_fit_effect)
var _recipe_button: UiCommandButton
var _recipe_nav: UiNavButton
var _pages: UiInventoryGrid
var _bag: UiInventoryGrid
var _slots_used: Label
var _cook: UiCommandButton
var _foot: HBoxContainer   # Experiment's Cook row
var _pot_energy: Label
var _tried: Label


## q(16): the toast sits above the Cook row in Experiment, above the recipe's Cook on a Cookbook page.
func action_area() -> Control:
	for c in [_foot, _recipe_button]:
		if c != null and (c as Control).is_visible_in_tree(): return c
	return null

func _init(view_: Dictionary = {}, tab_ := "cookbook") -> void:
	super(HEIGHT)
	view = view_
	body.add_child(_heading())
	_modes = UiSegmentTab.new([{label = "Cookbook", count = P0KitchenLogic.cookbook_count(view)}, {label = "Experiment"}])
	_modes.changed.connect(func(i: int): set_tab("cookbook" if i == 0 else "experiment"))
	body.add_child(_modes)
	_cookbook = _build_cookbook()
	body.add_child(_cookbook)
	_experiment = _build_experiment()
	body.add_child(_experiment)
	tab = tab_
	refresh()

func set_queue_mode(v: bool) -> void:
	queue_mode = v
	if _cook:
		_cook.label = _verb()
		_cook.reason = P0KitchenLogic.experiment_reason(view, pot, queue_mode, stove_index)
	if _recipe_button and selected_page != "": _show_page(selected_page)   # relabel and lay the card out again

func _verb() -> String: return "Queue" if queue_mode else "Cook"

func set_tab(v: String) -> void:
	var changed := v != tab
	tab = v
	if _modes == null: return
	_modes.selected = 0 if tab == "cookbook" else 1
	_cookbook.visible = tab == "cookbook"
	_experiment.visible = tab == "experiment"
	if changed: tab_changed.emit(tab)

## Redraw from `view` and `pot`; selections and scroll positions survive.
func refresh() -> void:
	var h := P0KitchenLogic.header(view, stove_index)
	var several := P0KitchenLogic.stove_count(view) > 1
	_stove.text = h.stove + (" ›" if several else "")
	if _stove_pill:   # a pill only when there is another stove to go to (COOK-STOVES 2152:33518; 不知火舞 02ad95bc ②)
		_stove_pill.mouse_filter = Control.MOUSE_FILTER_STOP if several else Control.MOUSE_FILTER_IGNORE
		var box := _stove_pill.get_theme_stylebox(&"panel") as UiStyleBox
		box.border_color = _PILL_EDGE if several else Color.TRANSPARENT
		box.bg_color = UiTokens.COLOR_SURFACE if several else Color.TRANSPARENT
		box.content_margin_left = _PILL_PAD.x if several else 0.0
		box.content_margin_right = _PILL_PAD.y if several else 0.0
		_stove_pill.custom_minimum_size.y = _PILL_H if several else 0.0
	_level.text = h.level
	_state.text = h.state
	var count: Label = _modes.tabs()[0].find_child("Count", true, false)
	if count: count.text = P0KitchenLogic.cookbook_count(view)
	_refresh_cookbook()
	_refresh_experiment()

func _doubled(cmd: Dictionary, t: _DoubleToggle) -> Dictionary:
	if t.visible and t.enabled and is_double(): cmd["double"] = true
	return cmd

func set_stove_index(v: int) -> void:
	stove_index = v
	if _stove != null: refresh()

## Where the heading's stove pill sits on screen (shots, tests).
func stove_pill_rect() -> Rect2: return _stove_pill.get_global_rect() if _stove_pill else Rect2()

func page(id: String) -> Dictionary:
	for p in P0KitchenLogic.pages(view):
		if str(p.id) == id: return p
	return {}

# ---------------------------------------------------------------- heading
func _heading() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_ROW))
	_stove = UiKit.label("", UiTokens.STYLE_C14_XB)
	_level = UiKit.label("", UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	_state = UiKit.label("", UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	# `Stove 2/3 ›` is a tappable pill once there are several stoves (white, 1 px outline); with one it reads as before.
	_stove_pill = PanelContainer.new()
	var pill := UiStyleBox.make(Color.TRANSPARENT, _PILL_RADIUS, Color.TRANSPARENT, UiTokens.STROKE_DEFAULT)
	_stove_pill.add_theme_stylebox_override(&"panel", pill)
	_stove_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stove_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # 28 high, centred in the heading row (2152:33666)
	_stove_pill.gui_input.connect(func(e: InputEvent): if P0Ui.is_tap(e): stove_cycle_requested.emit())
	_stove_pill.add_child(_stove)
	row.add_child(_stove_pill)
	for l in [_stove, _level, _state]:
		(l as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if l != _stove: row.add_child(l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var close := UiCloseButton.new()
	close.pressed.connect(func(): close_requested.emit())
	row.add_child(close)
	# COOK-2a / 2b: the 18 px heading sits at y 15 and the 44 px close at y 2; let the close overhang the pad.
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override(&"margin_top", -int(_CLOSE_OVERHANG))
	wrap.add_theme_constant_override(&"margin_bottom", -int(_CLOSE_OVERHANG))
	wrap.add_child(row)
	return wrap

# ---------------------------------------------------------------- Cookbook
func _build_cookbook() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", int(_GAP))
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_chips(P0KitchenLogic.COOKBOOK_CHIPS, func(i: int):
		cookbook_chip = P0KitchenLogic.COOKBOOK_CHIPS[i]
		_refresh_cookbook()))
	v.add_child(_build_recipe())
	_pages = UiInventoryGrid.new()
	_pages.density = UiItemCell.Density.KITCHEN
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages.on_select = func(item: Dictionary): _select_page(str(item.id))
	v.add_child(_pages)
	return v

func _build_recipe() -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = _RECIPE
	_recipe_wrap = wrap
	_recipe = Panel.new()
	_recipe.size = _RECIPE
	_recipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recipe.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER, UiTokens.STROKE_CELL_HAIRLINE))
	wrap.add_child(_recipe)
	var medallion := Panel.new()
	medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medallion.position = _MEDALLION.position
	medallion.size = _MEDALLION.size
	medallion.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT, _MEDALLION.size.x * 0.5))
	_recipe.add_child(medallion)
	_recipe_icon = UiKit.icon(null, _DISH_ICON)
	_recipe_icon.position = (_MEDALLION.size - Vector2(_DISH_ICON, _DISH_ICON)) * 0.5
	_recipe_icon.size = Vector2(_DISH_ICON, _DISH_ICON)
	medallion.add_child(_recipe_icon)
	_recipe_title = _text(_recipe, UiTokens.STYLE_C14_XB, UiTokens.COLOR_TEXT, Rect2(57.4, 8.4, 180, 18))
	_recipe_state = _text(_recipe, UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY, Rect2(57.4, 28.4, 150, 13))
	_recipe_effect = _text(_recipe, UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT, Rect2(57.4, 48.4, 142, 15))
	_recipe_buff = _buff_capsule()
	_recipe.add_child(_recipe_buff)
	_recipe_maybe = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_NEW_INK)
	_recipe_maybe.position = Vector2(57.4, _RECIPE_MAYBE_TOP)
	_recipe_maybe.visible = false
	_recipe.add_child(_recipe_maybe)
	_recipe_button = UiCommandButton.new("Cook", UiCommandButton.Kind.PRIMARY, true)
	_recipe_button.sends = true   # cook (§10.7.1 Offline)
	_recipe_button.position = _RECIPE_BUTTON_AT
	_recipe_button.size = _RECIPE_BUTTON
	_recipe_button.activated.connect(func():
		var p := page(selected_page)
		if not p.is_empty(): cook_requested.emit(_doubled({"type": "cook", "recipe": str(p.id)}, _book_double)))
	wrap.add_child(_recipe_button)
	_book_double = _make_double()
	wrap.add_child(_book_double)
	_recipe_nav = UiNavButton.new("Try in Experiment", true)
	_recipe_nav.position = Vector2(_RECIPE.x - 150, _RECIPE_BUTTON_AT.y)
	_recipe_nav.size = Vector2(146, _RECIPE_BUTTON.y)
	_recipe_nav.pressed.connect(func(): set_tab("experiment"))
	wrap.add_child(_recipe_nav)
	return wrap

## SGODOT-282 / §7.14.4 (不知火舞 540d59df): Legendary pages (41–48) show their Buff slot as a display-only capsule:
## secondary C10 Bold `Buff · coming later`, a 1 px dashed outline, no fill, a 12 px hollow gold star on the left
## (P3 brings the Buffs). Not a button: it never takes a tap.
class _HollowStar extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(12, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var outer := minf(size.x, size.y) * 0.5 - 0.75
		var pts := PackedVector2Array()
		for i in 11:
			var a := -PI * 0.5 + float(i) * PI / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else outer * 0.45))
		draw_polyline(pts, UiTokens.COLOR_GOLD_DEEP, 1.2, true)

static func _buff_capsule() -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := UiStyleBox.make(Color.TRANSPARENT, UiTokens.RADIUS_PILL, UiTokens.COLOR_SECONDARY, UiTokens.STROKE_DEFAULT)
	box.dashed = true
	box.dash = UiTokens.DASH_KITCHEN[0]
	box.gap = UiTokens.DASH_KITCHEN[1]
	box.content_margin_left = 5.0
	box.content_margin_right = 6.0
	cap.add_theme_stylebox_override(&"panel", box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 2)
	var star := _HollowStar.new()
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(star)
	var text := UiKit.label(P0KitchenLogic.BUFF_LATER, UiTokens.STYLE_C10_B, UiTokens.COLOR_SECONDARY)
	text.name = "buff_text"
	row.add_child(text)
	cap.add_child(row)
	cap.visible = false
	return cap

static func _text(parent: Control, style: StringName, color: Color, r: Rect2) -> Label:
	var l := UiKit.label("", style, color)
	l.position = r.position
	l.size = r.size
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(l)
	return l

func _refresh_cookbook() -> void:
	var order := P0KitchenLogic.cookbook_order(view, cookbook_chip)
	_pages.capacity = order.size()
	_pages.items = order.map(func(p): return P0KitchenLogic.page_cell(view, p))
	if selected_page == "" or page(selected_page).is_empty():
		selected_page = str(order[0].id) if not order.is_empty() else ""
	_show_page(selected_page)
	if selected_page != "": _pages.selected_id = selected_page

func _select_page(id: String) -> void:
	selected_page = id
	_show_page(id)
	page_selected.emit(page(id))

## Opens on a given Cookbook page (Cook Again's Choose recipe ›): select it in the grid and show its card.
func select_page(id: String) -> void:
	if page(id).is_empty(): return
	selected_page = id
	if _pages: _pages.selected_id = id
	_show_page(id)

func _show_page(id: String) -> void:
	var p := page(id)
	_recipe.visible = not p.is_empty()
	_recipe_button.visible = false
	_recipe_nav.visible = false
	if p.is_empty(): return
	var card := P0KitchenLogic.page_card(view, p)
	_recipe_icon.texture = card.icon if card.icon != null else UiItemCell.SILHOUETTE
	_recipe_icon.self_modulate = Color.WHITE if card.icon != null else UiTokens.COLOR_DISABLED
	_recipe_title.text = card.title
	_recipe_state.text = card.state
	_recipe_buff.visible = str(card.get("buff", "")) != ""
	_effect_parts = card.effect_parts
	_recipe_maybe.text = card.maybe
	_recipe_maybe.visible = card.maybe != ""
	if card.nav != "":
		_recipe_nav.visible = true
	else:
		_recipe_button.visible = true
		_recipe_button.reason = card.reason
		_recipe_button.label = _verb()
	_apply_double(_book_double, _recipe_button, P0KitchenLogic.double_state(view, p) if card.nav == "" else {shown = false, enabled = false, toast = ""},
		p.get("in", []))
	_layout_recipe()

## The card grows with what it says (int6 C3 / C41, 不知火舞 on 226): the might-have line pushes the effect line
## down; the button keeps the bottom-right corner, right-aligned at 328 and as wide as its text, and when that
## text would run into the facts it takes a full-width row of its own under them. Text never shrinks or wraps.
func _layout_recipe() -> void:
	var b := _recipe_button
	var w := maxf(_RECIPE_BUTTON.x, b.get_combined_minimum_size().x)
	var right := _RECIPE.x - _RECIPE_PAD
	# The fact lines run up to 8 px short of what sits in the corner (不知火舞, 256 follow-up: not the 142 of the text box).
	var beside := (right - w if b.visible else _RECIPE.x - 150.0) - _RECIPE_PAD - _FACTS_X
	_fit_effect(beside)
	var corner := not b.visible or (_text_width(_recipe_state) <= beside and _text_width(_recipe_effect) <= beside)
	var room := beside if corner else right - _FACTS_X
	# The Buff capsule (Legendary) ends the state line when both fit; otherwise it takes a row of its own under it.
	var cap := _recipe_buff.get_combined_minimum_size() if _recipe_buff.visible else Vector2.ZERO
	var inline := cap.x > 0.0 and _text_width(_recipe_state) + 4.0 + cap.x <= room
	var buff_h := cap.y + 2.0 if cap.x > 0.0 and not inline else 0.0
	_recipe_maybe.position.y = _RECIPE_MAYBE_TOP + buff_h
	var extra := buff_h + (_recipe_maybe.get_combined_minimum_size().y + 2.0 if _recipe_maybe.visible else 0.0)
	_recipe_effect.position.y = 48.4 + extra
	var h := _RECIPE.y + extra
	_recipe_nav.position = Vector2(_RECIPE.x - 150, _RECIPE_BUTTON_AT.y + extra)
	_recipe_state.size.x = room
	if cap.x > 0.0:
		_recipe_buff.size = cap
		if inline:
			var text_w := _text_width(_recipe_state)
			_recipe_state.size.x = text_w
			_recipe_buff.position = Vector2(_FACTS_X + text_w + 4.0, _recipe_state.position.y + (_recipe_state.size.y - cap.y) * 0.5)
		else:
			_recipe_buff.position = Vector2(_FACTS_X, _RECIPE_MAYBE_TOP)
	if corner:
		b.position = Vector2(right - w, _RECIPE_BUTTON_AT.y + extra)
		b.size = Vector2(w, _RECIPE_BUTTON.y)
	else:   # a row of its own under the facts; the facts take the card's width
		_fit_effect(right - _FACTS_X)
		var top := _recipe_effect.position.y + _recipe_effect.size.y + _RECIPE_ROW_GAP
		b.position = Vector2(_RECIPE_PAD, top)
		b.size = Vector2(_RECIPE.x - _RECIPE_PAD * 2.0, _RECIPE_BUTTON.y)
		h = top + _RECIPE_BUTTON.y + _RECIPE_ROW_GAP
	if _book_double.visible:   # Double under Cook, right-aligned, a row of its own (COOK-DOUBLE-BOOK-ON)
		var dw := _book_double.get_combined_minimum_size().x
		_book_double.size = Vector2(dw, _DOUBLE_ROW)
		_book_double.position = Vector2(right - dw, h)
		h += _DOUBLE_ROW + _RECIPE_ROW_GAP
	_recipe.size = Vector2(_RECIPE.x, h)
	_recipe_wrap.custom_minimum_size = Vector2(_RECIPE.x, h)

## The card is first laid out in _init, before the drawer has its theme (the fact lines measured in the default font
## size read wider, and a long one, Fine · First cook +20 XP, sent Cook to a row of its own): lay it out again once the
## theme is there.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _recipe_wrap != null and _recipe.visible: _layout_recipe.call_deferred()

## The effect line in `room` px (不知火舞, 256 follow-up): `+40 Energy · 15 s · Soup`, the dish style dropped first and
## then the time when it does not fit; the energy always stays.
func _fit_effect(room: float) -> void:
	_recipe_effect.size.x = room
	var parts := _effect_parts.duplicate()
	_recipe_effect.text = " · ".join(PackedStringArray(parts))
	while parts.size() > 1 and _text_width(_recipe_effect) > room:
		parts.pop_back()
		_recipe_effect.text = " · ".join(PackedStringArray(parts))

## How wide a clipped label's text really is (clip_text makes its minimum width 0).
static func _text_width(l: Label) -> float:
	return l.get_theme_font(&"font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size(&"font_size")).x

# ---------------------------------------------------------------- Experiment
func _build_experiment() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", int(_GAP))
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_child(UiKit.label("From your bag", UiTokens.STYLE_C13_XB))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	_slots_used = UiKit.label("", UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY)
	head.add_child(_slots_used)
	v.add_child(head)
	v.add_child(_chips(P0KitchenLogic.EXPERIMENT_CHIPS, func(i: int):
		experiment_chip = P0KitchenLogic.EXPERIMENT_CHIPS[i]
		_refresh_experiment()))
	_bag = UiInventoryGrid.new()
	_bag.density = UiItemCell.Density.KITCHEN
	_bag.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag.on_select = func(item: Dictionary):
		_bag.clear_selection()   # Experiment cells have no selection: a tap moves one unit (F-07)
		var cell := _bag.cell_for(str(item.id))
		var at := cell.get_global_rect().get_center() if cell else Vector2.INF
		ingredient_tapped.emit(str(item.id), at)
	v.add_child(_bag)
	# A mix that failed before (§7.2.7; An Qi La, 226 e8e5617a): one line right above the Cook row, Cook stays live.
	_tried = UiKit.label("Tried before · not a recipe", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
	_tried.visible = false
	v.add_child(_tried)
	var foot := HBoxContainer.new()
	_foot = foot
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override(&"separation", int(UiTokens.SPACE_ROW))
	_pot_energy = UiKit.label("", UiTokens.STYLE_C12_B)   # Compact/Kitchen Cook decision: "+20 Energy" for a known page
	_pot_energy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pot_energy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_pot_energy)
	var info := UiNavButton.new("Info", true)
	info.pressed.connect(func(): info_requested.emit())
	foot.add_child(info)
	_exp_double = _make_double()
	foot.add_child(_exp_double)
	_cook = UiCommandButton.new("Cook", UiCommandButton.Kind.PRIMARY, true)
	_cook.sends = true   # cook (§10.7.1 Offline)
	_cook.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cook.activated.connect(func(): if not pot.is_empty(): cook_requested.emit(_doubled({"type": "cook", "items": pot.duplicate()}, _exp_double)))
	var cook_box := MarginContainer.new()   # the button resets its own minimum size; the box holds the 164 width
	cook_box.custom_minimum_size.x = _COOK_W
	cook_box.add_child(_cook)
	foot.add_child(cook_box)
	v.add_child(foot)
	return v

func _refresh_experiment() -> void:
	_slots_used.text = P0KitchenLogic.slots_used_line(view, pot)
	var items := P0KitchenLogic.experiment_items(view, pot, experiment_chip)
	_bag.capacity = maxi(10, ceili(items.size() / 5.0) * 5)
	_bag.items = items
	_cook.reason = P0KitchenLogic.experiment_reason(view, pot, queue_mode, stove_index)
	_cook.label = _verb()
	_apply_double(_exp_double, _cook, P0KitchenLogic.double_state(view, {}, pot), pot)
	_pot_energy.text = P0KitchenLogic.pot_energy(view, pot)
	_tried.visible = P0KitchenLogic.tried(view, pot)

func _chips(labels: Array, picked: Callable) -> Control:
	var scroll := TouchScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	scroll.add_child(UiFilterChip.row(PackedStringArray(labels), 0, picked))
	return scroll

## The drawer's top edge in screen pixels (the slot bar and preview sit above it).
func top_y() -> float:
	return get_global_rect().position.y

# ---------------------------------------------------------------- Big Pot Double (b84a5e01 ③)
func is_double() -> bool: return bool(doubles.get(stove_index, false))
## Whether the Double the player sees is on and usable for what is selected (the pot card's ×2 follows it).
func big_pot_shown() -> bool:
	var t := _book_double if tab == "cookbook" else _exp_double
	return t != null and t.visible and t.enabled

## `Double` + a switch (placeholder from kit parts until the Toggle main, 1236:107861, is in the kit). Grey: a tap says
## why (`toast`), it never flips.
class _DoubleToggle extends HBoxContainer:
	signal toggled(on: bool)
	signal refused(reason: String)
	var on := false: set = set_on
	var enabled := true: set = set_enabled
	var toast := ""
	var _track: Panel
	var _knob: Panel
	var _label: Label
	func _init() -> void:
		add_theme_constant_override(&"separation", 6)
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size.y = 32.0
		_label = UiKit.label("Double", UiTokens.STYLE_C12_B)
		_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		add_child(_label)
		_track = Panel.new()
		_track.custom_minimum_size = Vector2(36, 20)
		_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_track)
		_knob = Panel.new()
		_knob.size = Vector2(16, 16)
		_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_knob.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, 8.0))
		_track.add_child(_knob)
		gui_input.connect(func(e: InputEvent):
			if not P0Ui.is_tap(e): return
			if not enabled:
				refused.emit(toast)
				return
			on = not on
			toggled.emit(on))
		_restyle()
	func set_on(v: bool) -> void:
		on = v
		_restyle()
	func set_enabled(v: bool) -> void:
		enabled = v
		_restyle()
	func _restyle() -> void:
		if _track == null: return
		var lit := on and enabled
		_track.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY if lit else UiTokens.COLOR_DISABLED, 10.0))
		_knob.position = Vector2(18 if lit else 2, 2)
		_label.add_theme_color_override(&"font_color", UiTokens.COLOR_TEXT if enabled else UiTokens.COLOR_DISABLED)

func _make_double() -> _DoubleToggle:
	var t := _DoubleToggle.new()
	t.visible = false
	t.toggled.connect(func(on: bool):
		doubles[stove_index] = on
		refresh()
		double_changed.emit(on))
	t.refused.connect(func(r: String): unavailable.emit(r))
	return t

## Show the toggle for what is selected and set the main key: `Cook ×2` / `Queue ×2`, or the gap for two portions.
func _apply_double(t: _DoubleToggle, b: UiCommandButton, st: Dictionary, tokens: Array) -> void:
	t.visible = bool(st.shown)
	t.enabled = bool(st.enabled)
	t.toast = str(st.toast)
	t.on = is_double()
	if not (st.shown and st.enabled and is_double()) or b.reason != "": return
	var gap := P0KitchenLogic.double_gap(view, tokens)
	if gap != "": b.reason = gap
	else: b.label = P0KitchenLogic.double_label(queue_mode)
