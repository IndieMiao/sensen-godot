extends UiModalPanel
## The blueprint book (C-228, 0.4.7; design SEN-C-227 D-555, README §3, figure 1; owner SEN-Q-344): the blueprints in
## the bag on one page, in the rules' `buildings` order whatever can be built, so any one is placed first. The UI v3
## modal panel (the bag's, C-L4): a `Blueprints` tag, the book's hero, one column of 248 × 128 cards scrolling past
## MAX_SCREEN of the screen's height. A card: the building on blueprint paper with `×N` (the blueprints in the bag),
## its name, its materials as NEED-TILE S (LOCK-10) and one key: `Place` (primary, the host starts the placement) or
## the reason it cannot (`Need 6 more Stone`, `Farm Lv3 needed`) in the neutral look, which only shakes when tapped
## (C-185 M-02's exception) and flashes the short tile. `No blueprints` alone when the bag has none. ✕, the scrim and
## Android Back close it (the host). The Arrange key under the cards comes with moving and storing (C-229).

signal place_requested(type: String)

const HERO := preload("res://assets/ui/v3/hero/hero_blueprints.png")
const CARD := Vector2(248, 128)
const CARD_GAP := 10
const CARD_RADIUS := 16.0
const CARD_PAD := 8.0
## The blueprint paper (README §3): #4F7FB3 with thin white lines every GRID px.
const PAPER := Vector2(92, 112)
const PAPER_COLOR := Color("4F7FB3")
const PAPER_LINE := Color(1, 1, 1, 0.28)
const PAPER_GRID := 12.0
const PAPER_RADIUS := 10.0
const KEY_H := 32.0
## The panel is never taller than this share of the screen; the cards scroll inside it.
const MAX_SCREEN := 0.8
const EMPTY := "No blueprints"

## The entries shown (the host's book_entries()): [{type, name, count, materials: [{item, name, icon, have, need}],
## reason}], reason "" when it can be placed.
var entries: Array = []
var scroll: TouchScrollContainer
var cards: Array[Control] = []
## Each card's key, by type.
var keys := {}
var _list: VBoxContainer
var _thumbs: Callable

## `thumbs`: type -> Texture2D (the building drawn once, BlueprintThumbs), or an empty Callable for none.
func _init(entries_: Array = [], thumbs := Callable()) -> void:
	super("Blueprints", HERO)
	name = "BlueprintBook"
	theme = UiKit.theme()
	entries = entries_
	_thumbs = thumbs
	if entries.is_empty():
		var empty := UiKit.label(EMPTY, UiTokens.STYLE_BODY_B14, UiTokens.COLOR_TEXT_SECONDARY)
		empty.name = "Empty"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(CARD.x, CARD.y * 0.75)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		body.add_child(empty)
		return
	scroll = TouchScrollContainer.new()
	scroll.name = "Cards"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", CARD_GAP)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	for entry: Dictionary in entries:
		var card := _card(entry)
		_list.add_child(card)
		cards.append(card)
	_fit_scroll()

func _ready() -> void:
	get_viewport().size_changed.connect(_fit_scroll)
	_fit_scroll()

## The list as tall as its cards, at most what leaves the panel within MAX_SCREEN of the screen.
func _fit_scroll() -> void:
	if scroll == null: return
	var want := entries.size() * CARD.y + maxi(entries.size() - 1, 0) * CARD_GAP
	var screen := get_viewport().get_visible_rect().size.y if is_inside_tree() else 800.0
	var chrome := UiTokens.SIZE_PANEL_HEADER_H + UiTokens.SIZE_PANEL_PAD_TOP + UiTokens.SPACE_S8
	scroll.custom_minimum_size = Vector2(CARD.x, minf(want, maxf(CARD.y, screen * MAX_SCREEN - chrome)))

## The card of `type`, or null.
func card_of(type: String) -> Control:
	for i in entries.size():
		if entries[i].type == type: return cards[i]
	return null

func _card(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "Card_%s" % entry.type
	card.custom_minimum_size = CARD
	var box := UiStyleBox.make(UiTokens.COLOR_SURFACE_RAISED, CARD_RADIUS, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
	card.add_theme_stylebox_override(&"panel", box.with_margins(CARD_PAD, CARD_PAD, 12.0, CARD_PAD))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	card.add_child(row)
	var paper := _Paper.new()
	paper.name = "Paper"
	paper.custom_minimum_size = PAPER
	paper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(paper)
	var thumb := TextureRect.new()
	thumb.name = "Thumb"
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _thumbs.is_valid(): thumb.texture = _thumbs.call(entry.type)
	paper.add_child(thumb)
	var count := PanelContainer.new()
	count.name = "Count"
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.add_theme_stylebox_override(&"panel", UiClay.padded(UiClay.glass_dark(9.0), 6.0, 0.0))
	count.custom_minimum_size.y = 18
	var n := UiKit.label("×%d" % int(entry.count), UiTokens.STYLE_C11_XB, Color.WHITE)
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.add_child(n)
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	count.offset_right = -4
	count.offset_bottom = -4
	paper.add_child(count)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 4)
	row.add_child(col)
	var title := UiKit.label(str(entry.name), UiTokens.STYLE_ROW_TITLE_XB15)
	title.name = "Name"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(title)
	var tiles: Array = []
	for m: Dictionary in entry.get("materials", []):
		var tile := UiNeedTile.new(str(m.name), int(m.have), int(m.need), UiNeedTile.Size.S, m.get("icon"))
		tile.name = "Need_%s" % m.item
		tiles.append(tile)
	if not tiles.is_empty():
		var flow := UiNeedTile.group(tiles)
		flow.name = "Materials"
		col.add_child(flow)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	var key := UiCommandButton.new("Place", UiCommandButton.Kind.PRIMARY, true)
	key.name = "Key"
	key.custom_minimum_size.y = KEY_H
	key.reason = str(entry.get("reason", ""))
	key.fit_text = true
	var type := str(entry.type)
	key.activated.connect(func(): if not closing: place_requested.emit(type))
	key.unavailable_pressed.connect(func(_r: String): _refused(key, tiles, entry))
	col.add_child(key)
	keys[type] = key
	return card

## A grey key shakes (M-02) and the first short material's tile flashes amber; nothing is sent.
func _refused(key: Control, tiles: Array, entry: Dictionary) -> void:
	UiMotion.shake(key)
	var materials: Array = entry.get("materials", [])
	for i in materials.size():
		if int(materials[i].have) < int(materials[i].need):
			UiMotion.flash(tiles[i], UiTokens.COLOR_AMBER)
			return

## The blueprint paper: the colour, its thin white grid, rounded corners.
class _Paper extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _draw() -> void:
		var box := StyleBoxFlat.new()
		box.bg_color = PAPER_COLOR
		box.set_corner_radius_all(int(PAPER_RADIUS))
		box.anti_aliasing = true
		draw_style_box(box, Rect2(Vector2.ZERO, size))
		var x := PAPER_GRID
		while x < size.x:
			draw_line(Vector2(x, 2), Vector2(x, size.y - 2), PAPER_LINE, 1.0)
			x += PAPER_GRID
		var y := PAPER_GRID
		while y < size.y:
			draw_line(Vector2(2, y), Vector2(size.x - 2, y), PAPER_LINE, 1.0)
			y += PAPER_GRID
