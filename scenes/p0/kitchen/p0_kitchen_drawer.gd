class_name P0KitchenDrawer
extends UiDrawer
## The cooking drawer, LOCK-20 v5 (SGODOT-226; Figma COOK-2a Cookbook / COOK-2b Experiment, 360×480 from y 320):
##   heading   `Stove 1/1` · `Cooking Lv1` · `Empty` (q(31) order) and the 44 px close
##   modes     SegmentTab `Cookbook n/N` | `Experiment`
##   Cookbook  the title strip (COOK-TITLES), filter chips, the selected page's Compact/Kitchen/Recipe card with Cook (or the gap on the button,
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
## The Cookbook's title strip (COOK-TITLES 2575:132633 / states 2575:133159; 安其拉, 不知火舞 on 302 2d6a2e9d): a card between
## the mode tabs and the filter chips (where the chips were), as wide as they are, 53 high, radius 12, a 1 px border on
## surfaceRaised, the text 11 in;
## `Home Cook · Line Cook 12/20 · Head Chef · Master Chef` — reached in ink, the next with its count ExtraBold, the rest and
## every ` · ` grey — a 1 px rule 4 under it, then `Muscle Memory 6/10` (grey; reached: the name alone, in ink). Read only.
## 6 above the chips: the chips, the recipe card and the grid move down 59, the grid's bottom stays. On a screen too narrow
## for the line it wraps at a ` · ` and the card grows (安其拉's suggestion).
const _TITLES_RADIUS := 12.0
const _TITLES_PAD := Vector2(11.0, 6.0)   # Figma 11 / 7 to 15-high lines; Nunito 11 sets 16 high here, so 6 keeps the card 53
const _TITLES_ROW_GAP := 4.0              # line, rule, line
const _TITLES_BELOW := 6.0                # to the filter chips
const TITLE_GREY := Color("A9ACA6")       # Figma's unbound grey (P0CityRow.UNVISITED_INK)
const _COOK_W := 164.0
## The recipe card (row 99, S1 2731:153980 / grid 2733:158489; 不知火舞 on 286 20438543), one grid for every page and
## level: 336 × 110, two rows. Row 1 (y 12–56): the dish medallion 44 at x 12 (a grey silhouette for an unknown page);
## name 14 ExtraBold and state 11 Bold as one 34-high block at x 68; `+20 Energy` 12 ExtraBold right-aligned to Cook's
## right edge (x 324); a 1 × 34 divider at x 248. Row 2 (surface y 64–98, touch 44): the stepper (Cooking Lv8) at x 68,
## the Big Pot key (Homestead Lv6) at x 180–248, Cook at x 256–324 — always there, always `Cook`.
const _CARD := Vector2(336, 110)
const _CARD_MEDALLION := Rect2(12, 12, 44, 44)
const _CARD_ICON := 30.0
const _CARD_TITLE := Rect2(68, 15, 172, 19)
const _CARD_STATE := Rect2(68, 36, 172, 15)
const _CARD_EFFECT := Rect2(250, 24, 74, 20)
const _CARD_DIVIDER := Rect2(248, 17, 1, 34)
const _CARD_ROW1_END := 56.0
const _CARD_ROW2 := 59.0           # the 44 touch row around the 34 surface at y 64
const _CARD_STEPPER_X := 68.0
const _CARD_KEY_X := 180.0
const _CARD_COOK := Rect2(256, 59, 68, 44)
const _EXTRA_ROW := 20.0           # the extra line: 16 high, 4 above and below
const _UNKNOWN_MEDALLION := Color("E9E7E0")   # S14 2747:159713: an unknown page's silhouette sits on light grey

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
## The Big Pot is a stove state (q(201), Homestead Lv6): `big_stoves` are the stoves switched to it on this device (the
## kitchen keeps them in user://p0_ui.cfg); the key left of Cook switches the current stove and says so
## (`big_pot_toggled`), the kitchen saving it and changing the pot. Cookbook and Experiment each have the key.
var big_stoves: Array = []: set = set_big_stoves
signal big_pot_toggled(stove: int, on: bool)
signal unavailable(reason: String)
## The batch or the Big Pot changed what the pot card shows (×N, servings): the kitchen redraws it.
signal plan_changed
## Batch Cook (Cooking Lv8, q(200)): how many pots of the selected page; back to 1 on another page or stove.
var batch_n := 1
## Cook All has no key here: paused (user 10-15; 0.2.8 brings a cook-this-page-in-batches on the recipe card), and the
## filter row keeps all six chips where its key used to squeeze Rare / Legendary out (B7 ⑨). The kitchen's sheet and
## firing go with it (0.2.8: Batch Cook on the recipe card, q(200)).

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
var _recipe_button: UiCommandButton
var _recipe_nav: UiNavButton
var _medallion: Panel
var _divider: ColorRect
var _stepper: UiStepper          # q(200) B: `− n +`, Cooking Lv8
var _book_key: UiBigPotKey       # q(201): the Big Pot key left of Cook, Homestead Lv6
var _exp_key: UiBigPotKey
var _exp_info_row: HBoxContainer
var _exp_info: UiNavButton
var _cook_box: MarginContainer
var _saved_said := ""            # the kept-items toast said for this page and count (q(200) ④: once, then on a tap)
var _pages: UiInventoryGrid
var _book_chips: Control   # the Cookbook's filter chips (in their scroll window)
var _bag: UiInventoryGrid
var _slots_used: Label
var _cook: UiCommandButton

var _foot: HBoxContainer   # Experiment's Cook row
var _titles: PanelContainer   # the Cookbook's title strip
var _title_line: HFlowContainer
var _muscle_rule: ColorRect
var _muscle: HBoxContainer
var _pot_energy: Label
var _tried: Label

## Only the page the player has opened can pulse; the guide never changes the selection or filters.
func guide_cook_target(page_id: String) -> Control:
	return _recipe_button if tab == "cookbook" and selected_page == page_id else null


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
	_fit_heading()
	var count: Label = _modes.tabs()[0].find_child("Count", true, false)
	if count: count.text = P0KitchenLogic.cookbook_count(view)
	_refresh_titles()
	_refresh_cookbook()
	_refresh_experiment()

func is_big(i := -1) -> bool: return big_stoves.has(stove_index if i < 0 else i)

## The Big Pot stoves count in the batch's pots (a Big Pot stove takes two sets): set after the card is laid out (the
## kitchen hands them over once the drawer exists), it is laid out again, so the stepper's limit counts them too (0.2.8
## retest, 286 2389195c: opened on an ordinary stove, the stepper went to 3 pots where the stock made 2).
func set_big_stoves(v: Array) -> void:
	big_stoves = v
	if _stove != null: refresh()

func set_stove_index(v: int) -> void:
	if v != stove_index: batch_n = 1
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
	row.resized.connect(_fit_heading)
	var close := UiCloseButton.new()
	close.pressed.connect(func(): close_requested.emit())
	row.add_child(close)
	# COOK-2a / 2b: the 18 px heading sits at y 15 and the 44 px close at y 2; let the close overhang the pad.
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override(&"margin_top", -int(_CLOSE_OVERHANG))
	wrap.add_theme_constant_override(&"margin_bottom", -int(_CLOSE_OVERHANG))
	wrap.add_child(row)
	return wrap

## The heading never widens the drawer nor cuts its state: with `Stove 1/3 ›` and a long state (the Cookbook left open
## on a stove Cook All lit) `Cooking LvN` steps aside, the state stays (不知火舞 on #289).
func _fit_heading() -> void:
	if _state == null or _stove_pill == null: return
	var row := _state.get_parent() as Control
	if row.size.x <= 0.0: return   # not laid out yet: the row's first resize fits it
	var w := row.size.x
	var sep := float(row.get_theme_constant(&"separation"))
	var need := _stove_pill.get_combined_minimum_size().x + _level.get_minimum_size().x + _state.get_minimum_size().x \
		+ UiTokens.SIZE_CLOSE + sep * 3.0
	_level.visible = need <= w

# ---------------------------------------------------------------- Cookbook
func _build_cookbook() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", int(_GAP))
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_build_titles())
	# The filter chips, all six: All · Can cook · Common · Fine · Rare · Legendary (2318:125476).
	var chips := _chips(P0KitchenLogic.COOKBOOK_CHIPS, func(i: int):
		cookbook_chip = P0KitchenLogic.COOKBOOK_CHIPS[i]
		_refresh_cookbook())
	_book_chips = chips.get_child(0)
	_tighten(_book_chips)
	v.add_child(chips)
	v.add_child(_build_recipe())
	_pages = UiInventoryGrid.new()
	_pages.density = UiItemCell.Density.KITCHEN
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages.on_select = func(item: Dictionary): _select_page(str(item.id))
	v.add_child(_pages)
	return v

func _build_titles() -> Control:
	var wrap := MarginContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_theme_constant_override(&"margin_bottom", int(_TITLES_BELOW - _GAP))
	_titles = PanelContainer.new()
	_titles.name = "CookbookTitles"
	_titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_titles.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, _TITLES_RADIUS, UiTokens.COLOR_BORDER,
		UiTokens.STROKE_DEFAULT).with_margins(_TITLES_PAD.x, _TITLES_PAD.y, _TITLES_PAD.x, _TITLES_PAD.y))
	wrap.add_child(_titles)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override(&"separation", int(_TITLES_ROW_GAP))
	_titles.add_child(col)
	_title_line = HFlowContainer.new()
	_title_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_line.add_theme_constant_override(&"h_separation", 0)
	_title_line.add_theme_constant_override(&"v_separation", 0)
	col.add_child(_title_line)
	_muscle_rule = ColorRect.new()
	_muscle_rule.color = UiTokens.COLOR_BORDER
	_muscle_rule.custom_minimum_size.y = 1.0
	_muscle_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_muscle_rule)
	_muscle = HBoxContainer.new()
	_muscle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_muscle.add_theme_constant_override(&"separation", 0)
	col.add_child(_muscle)
	return wrap

## The strip from the view: each title its own unit with the ` · ` after it, so a wrapped line breaks between titles.
func _refresh_titles() -> void:
	for box in [_title_line, _muscle]:
		for c in box.get_children():   # out of the tree and freed now: plain labels, nothing waits on them
			box.remove_child(c)
			c.free()
	var items := P0KitchenLogic.title_strip(view)
	for i in items.size():
		var t: Dictionary = items[i]
		var unit := HBoxContainer.new()
		unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		unit.add_theme_constant_override(&"separation", 0)
		var next := str(t.state) == "next"
		var text := str(t.title) + (" %d/%d" % [int(t.have), int(t.need)] if next else "")
		unit.add_child(_title_label(text, UiTokens.STYLE_C11_XB if next else UiTokens.STYLE_C11_B,
			TITLE_GREY if str(t.state) == "later" else UiTokens.COLOR_TEXT))
		if i < items.size() - 1: unit.add_child(_title_label(" · ", UiTokens.STYLE_C11_B, TITLE_GREY))
		_title_line.add_child(unit)
	var m := P0KitchenLogic.muscle_item(view)
	_muscle_rule.visible = not m.is_empty()
	_muscle.visible = not m.is_empty()
	if m.is_empty(): return
	if bool(m.reached): _muscle.add_child(_title_label(str(m.title), UiTokens.STYLE_C11_B))
	else:
		_muscle.add_child(_title_label(str(m.title) + " ", UiTokens.STYLE_C11_B, TITLE_GREY))
		_muscle.add_child(_title_label("%d/%d" % [int(m.have), int(m.need)], UiTokens.STYLE_C11_XB, TITLE_GREY))

static func _title_label(text: String, style: StringName, color := UiTokens.COLOR_TEXT) -> Label:
	var l := UiKit.label(text, style, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## The strip's texts in order, each [text, state] (tests, shots): the titles line, then Muscle Memory's parts.
func title_texts() -> Array:
	var out: Array = []
	for unit in _title_line.get_children():
		for l in unit.get_children(): out.append((l as Label).text)
	if _muscle.visible:
		out.append("|")
		for l in _muscle.get_children(): out.append((l as Label).text)
	return out

func _build_recipe() -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = _CARD
	_recipe_wrap = wrap
	_recipe = Panel.new()
	_recipe.size = _CARD
	_recipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recipe.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD, UiTokens.COLOR_BORDER, UiTokens.STROKE_CELL_HAIRLINE))
	wrap.add_child(_recipe)
	_medallion = Panel.new()
	_medallion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_recipe.add_child(_medallion)
	_recipe_icon = UiKit.icon(null, _CARD_ICON)
	_medallion.add_child(_recipe_icon)
	_divider = ColorRect.new()   # row 99: 1 × 34 at x 248, y 17–51, color/border, over the Big Pot key's right edge
	_divider.color = UiTokens.COLOR_BORDER
	_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_divider.position = _CARD_DIVIDER.position
	_divider.size = _CARD_DIVIDER.size
	_recipe.add_child(_divider)
	_recipe_title = _text(_recipe, UiTokens.STYLE_C14_XB, UiTokens.COLOR_TEXT, _CARD_TITLE)
	_recipe_state = _text(_recipe, UiTokens.STYLE_C11_B, UiTokens.COLOR_SECONDARY, _CARD_STATE)
	_recipe_effect = _text(_recipe, UiTokens.STYLE_C12_XB, UiTokens.COLOR_TEXT, _CARD_EFFECT)
	_recipe_buff = _buff_capsule()
	_recipe.add_child(_recipe_buff)
	_recipe_maybe = UiKit.label("", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_NEW_INK)
	_recipe_maybe.visible = false
	_recipe.add_child(_recipe_maybe)
	_recipe_button = UiCommandButton.new("Cook", UiCommandButton.Kind.PRIMARY, true)
	_recipe_button.sends = true   # cook (§10.7.1 Offline)
	_recipe_button.activated.connect(func():
		var p := page(selected_page)
		if not p.is_empty(): cook_requested.emit(card_command()))
	wrap.add_child(_recipe_button)
	_stepper = UiStepper.new()
	_stepper.limits_say_why = true
	_stepper.changed.connect(_on_batch_n)
	_stepper.limit_pressed.connect(func(dir: int): if dir > 0: unavailable.emit(P0KitchenLogic.batch_limit_toast(batch_plan())))
	_stepper.visible = false
	wrap.add_child(_stepper)
	_book_key = _make_key()
	wrap.add_child(_book_key)
	_recipe_nav = UiNavButton.new("Try in Experiment", true)
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
	if id != selected_page:
		batch_n = 1
		_saved_said = ""
	selected_page = id
	_show_page(id)
	page_selected.emit(page(id))

## Opens on a given Cookbook page (Cook Again's Choose recipe ›): select it in the grid and show its card.
func select_page(id: String) -> void:
	if page(id).is_empty(): return
	if id != selected_page: batch_n = 1
	selected_page = id
	if _pages: _pages.selected_id = id
	_show_page(id)

func _show_page(id: String) -> void:
	var p := page(id)
	_recipe.visible = not p.is_empty()
	if p.is_empty():
		for n in [_recipe_button, _recipe_nav, _stepper, _book_key]: (n as Control).visible = false
		return
	var card := P0KitchenLogic.page_card(view, p)
	var known := bool(p.get("known", false))
	_recipe_icon.texture = card.icon if card.icon != null else UiItemCell.SILHOUETTE
	_recipe_icon.self_modulate = Color.WHITE if card.icon != null else UiTokens.COLOR_DISABLED
	_recipe_title.text = card.title
	_recipe_state.text = card.state
	_recipe_effect.text = str(card.effect_parts[0])   # `+N Energy` only: the time is on the pot card (row 99)
	# The extra line between the rows (不知火舞 on 286): a Legendary page's `Buff · coming later`, an unknown page's
	# `You might have what it takes`.
	_recipe_buff.visible = str(card.get("buff", "")) != ""
	_recipe_maybe.text = card.maybe
	_recipe_maybe.visible = card.maybe != "" and not _recipe_buff.visible
	# Row 2: a known page's stepper (Cooking Lv8), Big Pot key (Homestead Lv6) and Cook or its gap; an unknown page's
	# `Try in Experiment ›`, or the grey `Cooking Lv4 · 3rd slot` while its 3rd slot is locked.
	_recipe_nav.visible = card.nav != ""
	_recipe_button.visible = card.nav == ""
	_recipe_button.reason = card.reason
	_recipe_button.label = _verb()
	var can := known and str(card.reason) == ""
	_stepper.visible = can and not queue_mode and P0KitchenLogic.batch_on(view)
	if _stepper.visible:
		_stepper.max_value = maxi(1, int(batch_plan().max))
		_stepper.value = clampi(batch_n, 1, _stepper.max_value)
	if known: _apply_key(_book_key, P0KitchenLogic.big_pot_key(view, stove_index, is_big(), queue_mode, int(p.get("rarity", 1)) >= 4, can))
	else: _book_key.visible = false
	_layout_recipe()

## One grid for every page (row 99 S1 2731:153980, grid 2733:158489; 不知火舞 on 286 20438543): 336 wide, row 1 at
## y 12–56, row 2's 34 surface at y 64–98 (touch 44), 110 high; the extra line (16 high, 4 above and below) pushes
## row 2 down 20 and the card to 130. Cook stays at the bottom right, a gap right-aligned there as wide as it says.
func _layout_recipe() -> void:
	var extra := _EXTRA_ROW if _recipe_buff.visible or _recipe_maybe.visible else 0.0
	_medallion.position = _CARD_MEDALLION.position
	_medallion.size = _CARD_MEDALLION.size
	var known := bool(page(selected_page).get("known", false))   # an unknown page's medallion is light grey (S14)
	_medallion.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_PRIMARY_TINT if known else _UNKNOWN_MEDALLION, _CARD_MEDALLION.size.x * 0.5))
	_recipe_icon.position = (_CARD_MEDALLION.size - Vector2(_CARD_ICON, _CARD_ICON)) * 0.5
	_recipe_icon.size = Vector2(_CARD_ICON, _CARD_ICON)
	for pair in [[_recipe_title, _CARD_TITLE], [_recipe_state, _CARD_STATE], [_recipe_effect, _CARD_EFFECT]]:
		(pair[0] as Label).position = (pair[1] as Rect2).position
		(pair[0] as Label).size = (pair[1] as Rect2).size
	_recipe_effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var line_y := _CARD_ROW1_END + 4.0
	if _recipe_buff.visible:
		_recipe_buff.size = _recipe_buff.get_combined_minimum_size()
		_recipe_buff.position = Vector2(_CARD_TITLE.position.x, line_y + (16.0 - _recipe_buff.size.y) * 0.5)
	if _recipe_maybe.visible:
		_recipe_maybe.position = Vector2(_CARD_TITLE.position.x, line_y + (16.0 - _recipe_maybe.get_combined_minimum_size().y) * 0.5)
	var row2 := _CARD_ROW2 + extra
	_stepper.position = Vector2(_CARD_STEPPER_X, row2)
	_stepper.size = _stepper.custom_minimum_size
	_book_key.position = Vector2(_CARD_KEY_X, row2)
	_book_key.size = _book_key.custom_minimum_size
	for b in [_recipe_button, _recipe_nav]:
		var w := maxf(_CARD_COOK.size.x, (b as Control).get_combined_minimum_size().x)
		(b as Control).position = Vector2(_CARD_COOK.end.x - w, row2)
		(b as Control).size = Vector2(w, _CARD_COOK.size.y)
	var h := _CARD.y + extra
	_recipe.size = Vector2(_CARD.x, h)
	_recipe_wrap.custom_minimum_size = Vector2(_CARD.x, h)


# ---------------------------------------------------------------- Batch Cook and the Big Pot (q(200) / q(201))
## The selected page's batch as the server will cook it (P0KitchenLogic.batch_plan): from this stove, `batch_n` pots,
## the Big Pot stoves.
func batch_plan() -> Dictionary:
	return P0KitchenLogic.batch_plan(view, page(selected_page), 1 if queue_mode else batch_n, stove_index, big_stoves, queue_mode)

## What Cook sends: one pot is the plain cook, more is batch_cook (P0KitchenLogic.card_command); never more pots than
## the plan places, so the command is the batch the confirm and the pot card show.
func card_command() -> Dictionary:
	var n := mini(batch_n, maxi(1, (batch_plan().pots as Array).size())) if _stepper.visible else 1
	return P0KitchenLogic.card_command(page(selected_page), n, stove_index, big_stoves, P0KitchenLogic.stove_count(view) > 1)

func _on_batch_n(n: int) -> void:
	var before := batch_n
	batch_n = n
	var p := page(selected_page)
	if n > before:   # crossing into this page's 2nd / 3rd pot today (q(200) ⑥)
		for k in range(before + 1, n + 1):
			var t := P0KitchenLogic.nth_today_toast(P0KitchenLogic.page_pot_today(view, p, k))
			if t != "": unavailable.emit(t)
	_say_saved()
	plan_changed.emit()

## The kept-items toast (q(200) ④): the first time the batch uses an item saved for a request or another page.
func _say_saved() -> void:
	var t := P0KitchenLogic.saved_toast(view, page(selected_page), batch_plan().sets)
	if t != "" and t != _saved_said: unavailable.emit(t)
	_saved_said = t

## The kept-items toast again, for a tap on an amber slot.
func saved_line() -> String: return P0KitchenLogic.saved_toast(view, page(selected_page), batch_plan().sets)

func _make_key() -> UiBigPotKey:
	var k := UiBigPotKey.new()
	k.visible = false
	k.toggled.connect(func(on: bool):
		if on and not big_stoves.has(stove_index): big_stoves.append(stove_index)
		if not on: big_stoves.erase(stove_index)
		big_pot_toggled.emit(stove_index, on)
		refresh()
		plan_changed.emit())
	k.refused.connect(func(r: String): unavailable.emit(r))
	return k

func _apply_key(k: UiBigPotKey, st: Dictionary) -> void:
	k.visible = bool(st.shown)
	k.on = bool(st.on)
	k.enabled = bool(st.enabled)
	k.toast = str(st.toast)

## The card is first laid out in _init, before the drawer has its theme (the fact lines measured in the default font
## size read wider, and a long one, Fine · First cook +20 XP, sent Cook to a row of its own): lay it out again once the
## theme is there.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _recipe_wrap != null and _recipe.visible: _layout_recipe.call_deferred()

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
	# With the Big Pot (Homestead Lv6, S10 2732:178467) `+N Energy` and `Info ›` take a row of their own above, and the
	# cook row is the Big Pot key (x 12–80) and Cook filling the rest; before it, one row as before.
	_exp_info_row = HBoxContainer.new()
	_exp_info_row.add_theme_constant_override(&"separation", int(UiTokens.SPACE_ROW))
	_exp_info_row.visible = false
	v.add_child(_exp_info_row)
	var foot := HBoxContainer.new()
	_foot = foot
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override(&"separation", int(UiTokens.SPACE_ROW))
	_pot_energy = UiKit.label("", UiTokens.STYLE_C12_B)   # Compact/Kitchen Cook decision: "+20 Energy" for a known page
	_pot_energy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pot_energy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_pot_energy)
	_exp_info = UiNavButton.new("Info", true)
	_exp_info.pressed.connect(func(): info_requested.emit())
	foot.add_child(_exp_info)
	_exp_key = _make_key()
	foot.add_child(_exp_key)
	_cook = UiCommandButton.new("Cook", UiCommandButton.Kind.PRIMARY, true)
	_cook.sends = true   # cook (§10.7.1 Offline)
	_cook.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cook.activated.connect(func():
		if pot.is_empty(): return
		var cmd := {"type": "cook", "items": pot.duplicate()}
		if is_big(): cmd["double"] = true
		cook_requested.emit(cmd))
	_cook_box = MarginContainer.new()   # the button resets its own minimum size; the box holds the 164 width
	_cook_box.custom_minimum_size.x = _COOK_W
	_cook_box.size_flags_horizontal = Control.SIZE_FILL
	_cook_box.add_child(_cook)
	foot.add_child(_cook_box)
	v.add_child(foot)
	return v

func _refresh_experiment() -> void:
	_slots_used.text = P0KitchenLogic.slots_used_line(view, pot)
	var items := P0KitchenLogic.experiment_items(view, pot, experiment_chip)
	_bag.capacity = maxi(10, ceili(items.size() / 5.0) * 5)
	_bag.items = items
	_cook.reason = P0KitchenLogic.experiment_reason(view, pot, queue_mode, stove_index)
	_cook.label = _verb()
	var known := P0Logic.match_known(P0KitchenLogic.with_rack(view), pot)
	_apply_key(_exp_key, P0KitchenLogic.big_pot_key(view, stove_index, is_big(), queue_mode,
		not known.is_empty() and int(known.get("rarity", 1)) >= 4))
	_lay_experiment_foot(_exp_key.visible)
	_pot_energy.text = P0KitchenLogic.pot_energy(view, pot)
	_tried.visible = P0KitchenLogic.tried(view, pot)

## S10: with the key, `+N Energy` and `Info ›` move up to their own row (Info first, as the frame has it) and Cook fills
## the cook row after the key; without it they come back to the one row.
func _lay_experiment_foot(with_key: bool) -> void:
	var up := _exp_info.get_parent() == _exp_info_row
	if with_key != up:
		for n in [_exp_info, _pot_energy]:
			n.get_parent().remove_child(n)
		if with_key:
			_exp_info_row.add_child(_exp_info)
			_exp_info_row.add_child(_pot_energy)
			_pot_energy.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			_foot.add_child(_pot_energy)
			_foot.move_child(_pot_energy, 0)
			_foot.add_child(_exp_info)
			_foot.move_child(_exp_info, 1)
			_pot_energy.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_exp_info_row.visible = with_key
	_cook_box.custom_minimum_size.x = 0.0 if with_key else _COOK_W
	_cook_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL if with_key else Control.SIZE_FILL

## The Cookbook's six chips as 2318:125476 draws them, so all fit the 336 row (B7 ⑨): 4 apart, 7 each side of the
## word, at least 40 wide (All · Fine · Rare 40, Can cook 61, Common 60, Legendary 69 here).
const _BOOK_CHIP_GAP := 4
const _BOOK_CHIP_PAD := 7.0
const _BOOK_CHIP_MIN := 40.0

func _tighten(row: Control) -> void:
	row.add_theme_constant_override(&"separation", _BOOK_CHIP_GAP)
	for c in row.get_children():
		var chip := c as UiFilterChip
		chip.custom_minimum_size.x = _BOOK_CHIP_MIN
		# The theme's boxes reach the chip only in the tree: narrow their sides on every theme change there, from the
		# theme's own boxes (overrides off first; adding them notifies again, hence the meta guard).
		chip.theme_changed.connect(func():
			if not chip.is_inside_tree() or chip.get_meta(&"tightening", false): return
			chip.set_meta(&"tightening", true)
			for st in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled", &"focus"]:
				chip.remove_theme_stylebox_override(st)
				var box := chip.get_theme_stylebox(st).duplicate() as StyleBox
				box.content_margin_left = _BOOK_CHIP_PAD
				box.content_margin_right = _BOOK_CHIP_PAD
				chip.add_theme_stylebox_override(st, box)
			chip.set_meta(&"tightening", false))

func _chips(labels: Array, picked: Callable) -> Control:
	var scroll := TouchScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = UiTokens.SIZE_TOUCH
	scroll.add_child(UiFilterChip.row(PackedStringArray(labels), 0, picked))
	return scroll

## The drawer's top edge in screen pixels (the slot bar and preview sit above it).
func top_y() -> float:
	return get_global_rect().position.y

# ---------------------------------------------------------------- Big Pot (q(201))
## Shots / tests: the Big Pot key tapped as a finger does (Cookbook's or Experiment's, whichever shows).
func dev_big_pot() -> void:
	var k := _book_key if tab == "cookbook" else _exp_key
	if k != null and k.visible: k.press()

## The key the player sees on this tab, or null (shots, tests).
func big_pot_key() -> UiBigPotKey:
	var k := _book_key if tab == "cookbook" else _exp_key
	return k if k != null and k.visible else null

## Shots / tests: the stepper at `n` pots, as taps on + would be (each over its limit says why instead).
func dev_batch(n: int) -> void:
	if _stepper == null or not _stepper.visible: return
	while _stepper.value < n and not _stepper.end_grey(1): _stepper._press(1)
	if _stepper.value < n: _stepper._press(1)   # the grey + : its toast

## Shots / tests: the recipe card's Cook (or Experiment's), as a tap.
func dev_cook() -> void:
	var b := _recipe_button if tab == "cookbook" else _cook
	if b and b.visible and b.reason == "": b.activated.emit()

## The recipe card's parts on screen (282 shots: the row 99 grid by numbers).
func dev_card_rects() -> Dictionary:
	var out := {"card": _recipe.get_global_rect()}
	for pair in [["medallion", _medallion], ["title", _recipe_title], ["state", _recipe_state], ["effect", _recipe_effect],
			["divider", _divider], ["stepper", _stepper], ["big pot", _book_key], ["cook", _recipe_button], ["nav", _recipe_nav],
			["buff", _recipe_buff], ["maybe", _recipe_maybe], ["exp key", _exp_key], ["exp cook", _cook]]:
		var n := pair[1] as Control
		if n and n.is_visible_in_tree(): out[pair[0]] = n.get_global_rect()
	return out
