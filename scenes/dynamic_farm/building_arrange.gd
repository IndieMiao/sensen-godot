extends Control
## The arrange mode (C-229, 0.4.7; design SEN-C-227 D-555 README §5, figure 3; owner SEN-Q-344 D1–D3): moving built
## buildings and storing them back into blueprints, after P0's Decorate (p0_farm_decor.gd): one `Done` when idle, a
## tap on a building opens its card with `Store` and `Move`, and after either the mode stays.
##
## Over the scene, its own canvas layer's full rect, passing what it does not take to the scene. Every building has a
## marker over it (LOCK-07's icon button sizes: a 28 cream clay disc, a 22 four-way arrow, a 44 hit area) that pops in
## from 0.6 (200, each 40 later by its distance from the screen's middle); the selected one is gold. A tap on a marker
## or on a building's cells selects it and slides its card up (220): its picture, name, at most two facts (`4 Sheep`,
## `1 Wool on the ground`) and `Store` (secondary) + `Move` (primary); the cottage has `Move` only (D3). A drop still
## on its way greys Store with `Ready in m:ss`, counting each second and turning back into `Store` when laid (D2).
## C-247: the facts follow the clock too: a drop laid while the card is up shows on it within the second (V-779).
## Store asks first (`Store <name>?`, what goes back into the bag: the blueprint with the animals that go with it, the
## materials, the drops on the ground; D1) with `Cancel` / `Store`. A tap on open ground, ✕ or Back folds the card.
## A drag on the scene pans the camera (LOCK-01's modal edit exception: no stick). The host (dynamic_farm.gd) does the
## sending, the move preview and the building's going; this node asks it through the signals.

signal done
signal move_requested(id: int)
signal store_requested(id: int)

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const MOVE_ICON := preload("res://assets/ui/icons/lucide/move.svg")
## The marker (LOCK-07 icon button): visual disc, glyph and hit area.
const MARKER_DISC := 28.0
const MARKER_GLYPH := 22.0
const MARKER_HIT := 44.0
## The marker sits this far over the building's top (m).
const MARKER_LIFT := 0.35
## Markers pop 0.6 → 1 over POP_MS, each STAGGER_MS later by its distance from the middle (README §8).
const POP_FROM := 0.6
const POP_MS := 200.0
const STAGGER_MS := 40.0
## The card slides up over this long (README §8).
const CARD_MS := 220.0
const CARD_W := 320.0
const THUMB := Vector2(72, 80)
## A press that moves less than this is a tap; past it the drag pans.
const TAP_SLOP := 12.0
## Copy (LOCK-23, English by default; PM finalises it on C-45).
const DONE := "Done"
const MOVE := "Move"
const STORE := "Store"
const CANCEL := "Cancel"
const STORE_ASK := "Store %s?"
const ON_GROUND := "%d %s on the ground"
## The animals' names, one and many (README §6 `4 Sheep`).
const ANIMALS := {"hen_white": ["Hen", "Hens"], "hen_brown": ["Hen", "Hens"], "cow": ["Cow", "Cows"], "sheep": ["Sheep", "Sheep"]}

## The host (dynamic_farm.gd): buildings_state(), drops(), marker_point(id) -> Vector2 or null, thumb(type),
## item_name(id), item_icon(id), now_ms(), building_at_screen(screen) -> id or 0, pan(from, to).
var host: Node
var tray: UiPlaceBar
## Building id -> its marker.
var markers := {}
## The selected building's id, 0 for none.
var selected := 0
## The card (the building's, or Store's question) while up, else null; `asking` while it is the question.
var card: PanelContainer
var asking := false
var move_key: UiCommandButton
var store_key: UiCommandButton
## The card's facts, the question's rows (for tests).
var facts: Array[String] = []
var returns: Array[String] = []
## The card's text column (name, then the facts) while the building's card is up.
var _text: VBoxContainer
var _press := Vector2.ZERO
var _last := Vector2.ZERO
var _finger := -1
var _dragged := false
var _tick := 0.0

func _init(host_: Node) -> void:
	host = host_
	name = "BuildingArrange"
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tray = UiPlaceBar.new()
	tray.theme = UiKit.theme()
	tray.cancel = ""
	tray.confirm = DONE
	tray.confirmed.connect(func(): done.emit())
	add_child(tray)

func _ready() -> void:
	tray.safe_bottom = _safe_bottom()
	refresh()

## Markers follow the buildings standing (after a move or a store); the card follows its building or folds.
func refresh() -> void:
	var standing := {}
	for b: Dictionary in host.buildings_state(): standing[int(b.id)] = b
	for id: int in markers.keys():
		if standing.has(id): continue
		(markers[id] as Control).queue_free()
		markers.erase(id)
	var fresh: Array = []
	for id: int in standing:
		if markers.has(id): continue
		var marker := _Marker.new()
		marker.name = "Marker%d" % id
		add_child(marker)
		move_child(marker, 0)
		markers[id] = marker
		fresh.append(marker)
	_place_markers()
	_pop(fresh)
	if selected != 0 and not standing.has(selected): close_card()
	elif card != null and not asking: _fill_card()

func _pop(fresh: Array) -> void:
	if fresh.is_empty() or UiMotion.reduced or not is_inside_tree(): return
	var middle := get_viewport_rect().size * 0.5
	var far := 1.0
	for m: Control in fresh: far = maxf(far, (m.position + m.size * 0.5).distance_to(middle))
	for m: Control in fresh:
		var order := (m.position + m.size * 0.5).distance_to(middle) / far * float(fresh.size() - 1)
		m.pivot_offset = m.size * 0.5
		m.scale = Vector2.ONE * POP_FROM
		var tw := UiMotion.tween(m, UiTokens.MOTION_EASING_STANDARD)
		tw.tween_interval(UiMotion.secs(STAGGER_MS * order))
		tw.tween_property(m, "scale", Vector2.ONE, UiMotion.secs(POP_MS))

func _process(delta: float) -> void:
	_place_markers()
	_tick += delta
	if _tick >= 1.0 or _tick < 0.0:
		_tick = 0.0
		if card != null and not asking:
			_refresh_facts()
			_refresh_store_key()

func _place_markers() -> void:
	for id: int in markers:
		var at: Variant = host.marker_point(id)
		var marker: Control = markers[id]
		marker.visible = at is Vector2
		if at is Vector2: marker.position = (at as Vector2) - marker.size * 0.5
		marker.selected = id == selected

## Selects building `id` and opens its card (`id` 0 folds it).
func select(id: int) -> void:
	if id == 0 or not markers.has(id):
		close_card()
		return
	selected = id
	asking = false
	_fill_card()

## The selected building's saved state, {} for none.
func building() -> Dictionary:
	for b: Dictionary in host.buildings_state():
		if int(b.id) == selected: return b
	return {}

## Folds the card (or the question back to nothing); false when none was up.
func close_card() -> bool:
	if card == null:
		selected = 0
		return false
	card.queue_free()
	card = null
	_text = null
	asking = false
	selected = 0
	move_key = null
	store_key = null
	tray.visible = true
	_place_markers()
	return true

## Back in the mode: the question goes back to the card, the card folds; false when nothing was up.
func back() -> bool:
	if card != null and asking:
		asking = false
		_fill_card()
		return true
	return close_card()

func _new_card() -> VBoxContainer:
	var slide := card == null
	if card != null: card.queue_free()
	_text = null
	card = PanelContainer.new()
	card.name = "StoreCard" if asking else "BuildingCard"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override(&"panel", UiStyleBox.make(UiTokens.COLOR_SURFACE, UiTokens.RADIUS_CARD)
		.with_margins(UiTokens.SPACE_PAGE, UiTokens.SPACE_ROW, UiTokens.SPACE_PAGE, UiTokens.SPACE_PAGE))
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 1.0
	card.anchor_bottom = 1.0
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.offset_left = -CARD_W * 0.5
	card.offset_right = CARD_W * 0.5
	card.offset_bottom = -UiTokens.SPACE_PAGE - _safe_bottom()
	card.offset_top = card.offset_bottom
	add_child(card)
	tray.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override(&"separation", UiTokens.SPACE_S8)
	card.add_child(col)
	if slide and not UiMotion.reduced and is_inside_tree():
		var rise := 80.0
		card.modulate.a = 0.0
		var at := card.offset_bottom
		card.offset_bottom = at + rise
		card.offset_top = card.offset_bottom
		var tw := UiMotion.tween(card, UiTokens.MOTION_EASING_STANDARD).set_parallel(true)
		tw.tween_property(card, "offset_bottom", at, UiMotion.secs(CARD_MS))
		tw.tween_property(card, "offset_top", at, UiMotion.secs(CARD_MS))
		tw.tween_property(card, "modulate:a", 1.0, UiMotion.secs(CARD_MS))
	return col

## The building's card: picture, name, facts, Store + Move (the cottage: Move).
func _fill_card() -> void:
	var b := building()
	if b.is_empty():
		close_card()
		return
	var col := _new_card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	col.add_child(row)
	var thumb := TextureRect.new()
	thumb.name = "Thumb"
	thumb.custom_minimum_size = THUMB
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture = host.thumb(str(b.type))
	row.add_child(thumb)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var title := UiKit.label(str(Building.kind(str(b.type)).get("name", b.type)), UiTokens.STYLE_ROW_TITLE_XB15)
	title.name = "Name"
	text.add_child(title)
	_text = text
	_show_facts(building_facts(b))
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override(&"separation", 8)
	col.add_child(keys)
	store_key = null
	if str(b.type) != ParcelFarm.HOME_BUILDING:
		store_key = UiCommandButton.new(STORE, UiCommandButton.Kind.SECONDARY)
		store_key.name = "Store"
		store_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		store_key.activated.connect(_ask_store)
		store_key.unavailable_pressed.connect(func(_r: String): UiMotion.shake(store_key))
		keys.add_child(store_key)
	move_key = UiCommandButton.new(MOVE, UiCommandButton.Kind.PRIMARY)
	move_key.name = "Move"
	move_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_key.size_flags_stretch_ratio = 1.4
	var id := selected
	move_key.activated.connect(func(): move_requested.emit(id))
	keys.add_child(move_key)
	_refresh_store_key()

## The fact lines under the name.
func _show_facts(lines: Array[String]) -> void:
	facts = lines
	for old: Node in _text.get_children():
		if old.name.begins_with("Fact"):
			_text.remove_child(old)
			old.queue_free()
	for i in facts.size():
		var fact := UiKit.label(facts[i], UiTokens.STYLE_BODY_B14, UiTokens.COLOR_TEXT_SECONDARY)
		fact.name = "Fact%d" % (i + 1)
		_text.add_child(fact)

## C-247: a drop laid (its ready_at passed) while the card is up: the facts say so now, not on reopening (V-779).
func _refresh_facts() -> void:
	if not is_instance_valid(_text) or selected == 0: return
	var b := building()
	if b.is_empty(): return
	var now := building_facts(b)
	if now != facts: _show_facts(now)

## The card's facts: the animals (`4 Sheep`), the drops on the ground (`1 Wool on the ground`).
func building_facts(b: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var animals: Array = b.get("animals", [])
	if not animals.is_empty(): out.append(animal_line(animals))
	var laid := {}
	var now: int = host.now_ms()
	for d: Dictionary in ParcelFarm.drops_in({"drops": host.drops()}, int(b.id)):
		if int(d.ready_at) <= now: laid[str(d.item)] = int(laid.get(str(d.item), 0)) + int(d.amount)
	for item: String in laid: out.append(ON_GROUND % [int(laid[item]), host.item_name(item)])
	return out.slice(0, 2)

## `4 Sheep`, `3 Hens` (the first animal's kind names them all).
static func animal_line(animals: Array) -> String:
	var names: Array = ANIMALS.get(str(animals[0]), [str(animals[0]), str(animals[0])])
	return "%d %s" % [animals.size(), names[0] if animals.size() == 1 else names[1]]

## Store greys with `Ready in m:ss` while a drop is on its way (D2), else stores.
func _refresh_store_key() -> void:
	if store_key == null or selected == 0: return
	var now: int = host.now_ms()
	var refusal := ParcelFarm.store_refusal(ParcelFarm.rules(), {"buildings": host.buildings_state(), "drops": host.drops()}, selected, now)
	store_key.reason = P0Logic.key_ready(float(int(refusal.detail.ready_at) - now)) if refusal.code == "PRODUCING" else ""

## Store's question: `Store Coop?`, what goes back into the bag, Cancel / Store.
func _ask_store() -> void:
	var b := building()
	if b.is_empty(): return
	asking = true
	var col := _new_card()
	var name_ := str(Building.kind(str(b.type)).get("name", b.type))
	var title := UiKit.label(STORE_ASK % name_, UiTokens.STYLE_ROW_TITLE_XB15)
	title.name = "Question"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	returns = []
	var given: Dictionary = ParcelFarm.store_returns(ParcelFarm.rules(), {"buildings": host.buildings_state(), "drops": host.drops()}, selected)
	for item: String in given:
		var line := "%d %s" % [int(given[item]), host.item_name(item)]
		returns.append(line)
		var row := HBoxContainer.new()
		row.name = "Return"
		row.add_theme_constant_override(&"separation", 8)
		var icon: Texture2D = host.item_icon(item)
		if icon != null: row.add_child(UiKit.icon(icon, 28))
		var words := VBoxContainer.new()
		words.add_theme_constant_override(&"separation", 0)
		words.add_child(UiKit.label(line, UiTokens.STYLE_BODY_B14))
		var animals: Array = b.get("animals", [])
		if item == str(ParcelFarm.rules().buildings.get(str(b.type), {}).get("blueprint", "")) and not animals.is_empty():
			var with_ := UiKit.label(animal_line(animals), UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_TEXT_SECONDARY)
			with_.name = "Animals"
			words.add_child(with_)
			returns.append(animal_line(animals))
		row.add_child(words)
		col.add_child(row)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override(&"separation", 8)
	col.add_child(keys)
	var cancel := UiCommandButton.new(CANCEL, UiCommandButton.Kind.SECONDARY)
	cancel.name = "Cancel"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.activated.connect(back)
	keys.add_child(cancel)
	var ok := UiCommandButton.new(STORE, UiCommandButton.Kind.PRIMARY)
	ok.name = "StoreConfirm"
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var id := selected
	ok.activated.connect(func(): store_requested.emit(id))
	keys.add_child(ok)
	store_key = null
	move_key = null

# ------------------------------------------------------------------ input

## A tap picks the building under it (a marker first), open ground folds the card; a drag pans.
func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventScreenTouch:
		if event.pressed and _finger == -1:
			_finger = event.index
			_begin(event.position)
		elif not event.pressed and event.index == _finger:
			_finger = -1
			_end(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _finger: _drag(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_finger = 999
			_begin(event.position)
		elif _finger == 999:
			_finger = -1
			_end(event.position)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _finger == 999:
		_drag(event.position)

func _begin(at: Vector2) -> void:
	_press = at
	_last = at
	_dragged = false

func _drag(at: Vector2) -> void:
	if not _dragged and at.distance_to(_press) < TAP_SLOP: return
	_dragged = true
	host.pan(_last, at)
	_last = at

func _end(at: Vector2) -> void:
	if _dragged: return
	tap(at)

## A tap at `screen`: the marker under it, else the building on that cell, else nothing (the card folds).
func tap(screen: Vector2) -> void:
	for id: int in markers:
		var m: Control = markers[id]
		if m.visible and Rect2(m.position, m.size).has_point(screen):
			select(id)
			return
	var id: int = host.building_at_screen(screen)
	if id != 0: select(id)
	else: close_card()

func _safe_bottom() -> float:
	if not is_inside_tree() or not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).w

## A building's marker (LOCK-07 icon button sizes): a cream clay disc with the four-way arrow, gold while selected.
class _Marker extends Control:
	var selected := false:
		set(value):
			if selected == value: return
			selected = value
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2.ONE * MARKER_HIT
		size = custom_minimum_size

	func _draw() -> void:
		var middle := size * 0.5
		var r := MARKER_DISC * 0.5
		draw_circle(middle + Vector2(0, 1.5), r, Color(0, 0, 0, 0.18))
		draw_circle(middle, r, UiTokens.COLOR_GOLD if selected else UiTokens.COLOR_SURFACE_RAISED)
		draw_arc(middle, r - 0.5, 0, TAU, 32, UiTokens.COLOR_GOLD_DEEP if selected else UiTokens.COLOR_BORDER, 1.0, true)
		var g := MARKER_GLYPH
		draw_texture_rect(MOVE_ICON, Rect2(middle - Vector2.ONE * g * 0.5, Vector2.ONE * g), false,
			UiTokens.COLOR_GOLD_INK if selected else UiTokens.COLOR_HUD_CLAY_INK)
