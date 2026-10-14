extends UiDrawer
## The Passport (PASS-POSTCARDS 2627:134311, PASS-1 · North America 2132:32862's shell; §11.9.3, q(171) ⑥, 不知火舞 on
## 284): a drawer from y 268 of 800, content 12 in —
##   heading  `Passport` (C14 XB) and Close (Compact/Navigation, no ›), 28 high
##   pages    a row of Compact/Filter pills, 36 high, scrolling sideways: `Cities`, `Postcards` (the continents' pages
##            and Outposts join this row later; `Cities` gives way to the continents then)
##   page     Cities: `Cities visited` and `First visits today`, then a row per city reached (its stamp, home first),
##            a city row opening its page (PASS-2); Postcards: P0PostcardsPage (q(171) ⑥)
## Close goes back where the Passport was opened from (the profile), else closes (the Stamp Desk). Preloaded, no
## class_name (a new global class needs an editor import).

signal close_pressed

const Postcards := preload("res://scenes/p0/panels/p0_postcards_page.gd")
const ArrivalCard := preload("res://modules/p0/p0_arrival_card.gd")
const HEIGHT := 532.0        # from y 268 of 800 (PASS-POSTCARDS, as the Fish-dex)
const PAGES := ["cities", "postcards"]
const PAGE_LABELS := ["Cities", "Postcards"]
const _HEADING_H := 28.0
const _PILLS_H := 36.0
const _GAP := 8

var view := {}
var spec := {}
var page := "cities"
var pills: HBoxContainer
var body_scroll: TouchScrollContainer
var postcards: VBoxContainer
var _cities: VBoxContainer

## spec: P0Travel.passport(view) with each row's icon and `pressed` filled in by the P0 UI.
func _init(spec_: Dictionary = {}, view_: Dictionary = {}, page_ := "cities") -> void:
	super(HEIGHT)
	pad = 12.0
	spec = spec_
	view = view_
	page = page_ if PAGES.has(page_) else "cities"
	var heading := Control.new()
	heading.name = "Heading"
	heading.custom_minimum_size.y = _HEADING_H
	var title := UiKit.label("Passport", UiTokens.STYLE_C14_XB)
	title.name = "Title"
	title.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(title)
	var close := UiNavButton.new("Close", true)
	close.name = "Close"
	close.chevron = false
	close.pressed.connect(func(): close_pressed.emit())
	heading.add_child(close)
	close.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	close.offset_top = (_HEADING_H - UiTokens.SIZE_TOUCH) * 0.5
	close.offset_bottom = -close.offset_top
	close.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	body.add_child(heading)
	var pill_scroll := TouchScrollContainer.new()   # more pages later (the continents): the row scrolls sideways
	pill_scroll.name = "Pages"
	pill_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pill_scroll.custom_minimum_size.y = _PILLS_H
	pills = UiFilterChip.row(PackedStringArray(PAGE_LABELS), PAGES.find(page), func(i: int): show_page(str(PAGES[i])))
	pills.name = "Pills"
	pill_scroll.add_child(pills)
	body.add_child(pill_scroll)
	body_scroll = TouchScrollContainer.new()
	body_scroll.name = "Scroll"
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(body_scroll)
	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(holder)
	_cities = _cities_page()
	holder.add_child(_cities)
	postcards = Postcards.new(view)
	holder.add_child(postcards)
	show_page(page)

## Cities: the two facts, then the city rows (home first, then newest first), as PASS-1 had them.
func _cities_page() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "Cities"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", _GAP)
	for f in spec.get("facts", []): col.add_child(UiFactRow.new(str(f[0]), str(f[1])))
	for r in spec.get("rows", []): col.add_child(ArrivalCard.row(r))
	return col

## One page shown, its pill selected; the page scrolls back to its top.
func show_page(p: String) -> void:
	page = p if PAGES.has(p) else "cities"
	_cities.visible = page == "cities"
	postcards.visible = page == "postcards"
	var i := PAGES.find(page)
	if pills and i < pills.get_child_count() and not (pills.get_child(i) as UiFilterChip).button_pressed:
		(pills.get_child(i) as UiFilterChip).button_pressed = true
	if body_scroll: body_scroll.scroll_vertical = 0

## The view moved on: the Postcards page follows it (a postcard just earned shows at once). The cities are the spec's.
func refresh(v: Dictionary) -> void:
	view = v
	postcards.refresh(view)
