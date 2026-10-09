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
var _recipe_effect: Label
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
		_cook.reason = P0KitchenLogic.experiment_reason(view, pot, queue_mode)
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
	var h := P0KitchenLogic.header(view)
	_stove.text = h.stove
	_level.text = h.level
	_state.text = h.state
	var count: Label = _modes.tabs()[0].find_child("Count", true, false)
	if count: count.text = P0KitchenLogic.cookbook_count(view)
	_refresh_cookbook()
	_refresh_experiment()

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
	for l in [_stove, _level, _state]:
		(l as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)
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
		if not p.is_empty(): cook_requested.emit({"type": "cook", "recipe": str(p.id)}))
	wrap.add_child(_recipe_button)
	_recipe_nav = UiNavButton.new("Try in Experiment", true)
	_recipe_nav.position = Vector2(_RECIPE.x - 150, _RECIPE_BUTTON_AT.y)
	_recipe_nav.size = Vector2(146, _RECIPE_BUTTON.y)
	_recipe_nav.pressed.connect(func(): set_tab("experiment"))
	wrap.add_child(_recipe_nav)
	return wrap

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
	_recipe_effect.text = card.effect
	_recipe_maybe.text = card.maybe
	_recipe_maybe.visible = card.maybe != ""
	if card.nav != "":
		_recipe_nav.visible = true
	else:
		_recipe_button.visible = true
		_recipe_button.reason = card.reason
		_recipe_button.label = _verb()
	_layout_recipe()

## The card grows with what it says (int6 C3 / C41, 不知火舞 on 226): the might-have line pushes the effect line
## down; the button keeps the bottom-right corner, right-aligned at 328 and as wide as its text, and when that
## text would run into the facts it takes a full-width row of its own under them. Text never shrinks or wraps.
func _layout_recipe() -> void:
	var extra := _recipe_maybe.get_combined_minimum_size().y + 2.0 if _recipe_maybe.visible else 0.0
	_recipe_effect.position.y = 48.4 + extra
	var h := _RECIPE.y + extra
	_recipe_nav.position = Vector2(_RECIPE.x - 150, _RECIPE_BUTTON_AT.y + extra)
	var b := _recipe_button
	var w := maxf(_RECIPE_BUTTON.x, b.get_combined_minimum_size().x)
	var right := _RECIPE.x - _RECIPE_PAD
	var facts := 57.4 + maxf(_text_width(_recipe_state), _text_width(_recipe_effect)) + _RECIPE_PAD
	if right - w >= facts:
		b.position = Vector2(right - w, _RECIPE_BUTTON_AT.y + extra)
		b.size = Vector2(w, _RECIPE_BUTTON.y)
	else:
		var top := _recipe_effect.position.y + _recipe_effect.size.y + _RECIPE_ROW_GAP
		b.position = Vector2(_RECIPE_PAD, top)
		b.size = Vector2(_RECIPE.x - _RECIPE_PAD * 2.0, _RECIPE_BUTTON.y)
		if b.visible: h = top + _RECIPE_BUTTON.y + _RECIPE_ROW_GAP
	_recipe.size = Vector2(_RECIPE.x, h)
	_recipe_wrap.custom_minimum_size = Vector2(_RECIPE.x, h)

## The card is first laid out in _init, before the drawer has its theme (the fact lines measured in the default font
## size read wider, and a long one, Fine · First cook +20 XP, sent Cook to a row of its own): lay it out again once the
## theme is there.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _recipe_wrap != null and _recipe.visible: _layout_recipe.call_deferred()

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
	_cook = UiCommandButton.new("Cook", UiCommandButton.Kind.PRIMARY, true)
	_cook.sends = true   # cook (§10.7.1 Offline)
	_cook.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cook.activated.connect(func(): if not pot.is_empty(): cook_requested.emit({"type": "cook", "items": pot.duplicate()}))
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
	_cook.reason = P0KitchenLogic.experiment_reason(view, pot, queue_mode)
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
