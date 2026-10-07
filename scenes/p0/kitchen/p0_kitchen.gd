class_name P0Kitchen
extends Node
## The farmhouse stove corner's cooking flow (SGODOT-226, LOCK-20 v5; plan §7.2.2 / §7.2.4 / §7.2.7):
##   compose  the cooking drawer (P0KitchenDrawer, 60 %) opens with the camera pushed onto the stove in the band
##            above it; the slot bar and the preview capsule sit just above the drawer (COOK-2a / 2b); picks fly
##            into the 3D pot (P0KitchenStage); Cookbook pages show their ingredients as ghosts.
##   watch    Cook closes the drawer; the stove steams, the heat ring hangs over the pot and a tap anywhere on the
##            screen is the heat tap (the whole pot is the target, §7.2.4). Walking away stops watching: the pot
##            keeps cooking and the missed rings count as misses (Plain, §7.2.3).
##   serve    at the end the plate slides out with its rarity glow, then `collect` goes to the server once.
## The server owns the stove (`view.cooking.stove`): leaving and coming back shows Ready, collect happens once.

const BAND_TOP_DRAWER := 0.29     # engineering default, WP7 v2: pot band ends above the slot bar
const BAND_TOP_WATCH := 0.75      # with the drawer closed the band runs to three quarters of the screen
const FOCUS_SIZE := 0.42          # pushed-in view: 42 % of the room's accepted width
const OVERLAY_GAP := 6.0          # preview above the drawer top, slot bar above the preview
const SLOT_BAR_GAP := 3.0
const SLOT_GAP := 8.0
const RING_GAP := 14.0            # screen px between the ring's lower edge and the top of the pot cards
const RING_EARLY_MS := 1000.0     # rings grow in during the second before they start
const SERVE_HOLD_S := 0.35        # the plate stays a moment before the result card
## Dev playtests: tap the middle of each gold arc.
static var auto_play := false

var room: P0Room
var rt: P0Runtime:   # the room attaches to the runtime after its _room_ready, so read it through the room
	get: return room.rt if room else null
var stage: P0KitchenStage
var drawer: P0KitchenDrawer
var pot: Array = []               # composing: ids in the pot, one per unit
var phase := "idle"               # idle | compose | watch | serve

var _wrap: Control
var _overlay: Control
var _slots: HBoxContainer
var _preview: UiKitchenPreview
var _ring: UiHeatRing
var _stove: Dictionary = {}
var _start_ms := 0
var _taps: Array = []
var _judged := {}
var _cook_sent := false

func _init(room_: P0Room) -> void:
	room = room_
	name = "Kitchen"

func _ready() -> void:
	stage = P0KitchenStage.new()
	stage.name = "Stage"
	stage.cam = room.cam
	stage.glow_light = room.room.find_child("HearthGlow", true, false)
	var mouth := room.anchor("drop_pot_1")
	if mouth: mouth.add_child(stage)
	else: room.add_child(stage)

func busy() -> bool: return phase != "idle"

# ---------------------------------------------------------------- compose
## Opens the cooking drawer on `tab` (Cookbook / Experiment) with the camera on the stove.
func open(tab := "cookbook") -> void:
	if rt == null or phase in ["watch", "serve"]: return
	pot.clear()
	stage.clear_ingredients()
	stage.clear_ghosts()
	_cook_sent = false
	_wrap = Control.new()
	_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrap.theme = UiKit.theme()
	drawer = P0KitchenDrawer.new(rt.session.current(), tab)
	drawer.safe_bottom = rt.ui.safe_bottom()
	drawer.close_requested.connect(func(): rt.ui.close_modal())
	drawer.page_selected.connect(_on_page)
	drawer.tab_changed.connect(_on_tab)
	drawer.ingredient_tapped.connect(_on_ingredient)
	drawer.cook_requested.connect(_on_cook)
	drawer.info_requested.connect(func(): rt.ui.toast("Mix 1–%d ingredients · unknown mixes may become a Mystery Dish" % P0KitchenLogic.slots(rt.session.current())))
	_wrap.add_child(drawer)
	_overlay = _build_overlay()
	_wrap.add_child(_overlay)
	rt.ui._open_modal(_wrap, 0.0, true)
	rt.ui.modal_kind = "kitchen"
	_wrap.tree_exited.connect(_on_closed)
	phase = "compose"
	_hide_player(true)
	room.focus("cam_stove", {band = room.band_below_hud(BAND_TOP_DRAWER), size = room.view_size() * FOCUS_SIZE, release_on_move = false})
	if tab == "cookbook" and drawer.selected_page != "": _on_page(drawer.page(drawer.selected_page))
	_refresh_overlay()

func _on_closed() -> void:
	if phase != "compose": return
	phase = "idle"
	drawer = null
	_overlay = null
	pot.clear()
	stage.clear_ingredients()
	stage.clear_ghosts()
	room.release_focus()
	_hide_player(false)

## COOK-2a / 2b show the stove alone: the player steps out of the pushed-in shot and back when it ends.
func _hide_player(on: bool) -> void:
	if room.actor: room.actor.visible = not on

func _build_overlay() -> Control:
	var o := Control.new()
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots = HBoxContainer.new()
	_slots.add_theme_constant_override(&"separation", int(SLOT_GAP))
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	o.add_child(_slots)
	_preview = UiKitchenPreview.new()
	o.add_child(_preview)
	o.resized.connect(_place_overlay)
	return o

func _place_overlay() -> void:
	if _overlay == null or drawer == null: return
	var top := _overlay.size.y - drawer.height - drawer.safe_bottom
	_preview.position = Vector2((_overlay.size.x - _preview.custom_minimum_size.x) * 0.5, top - OVERLAY_GAP - _preview.custom_minimum_size.y)
	var bar := _slots.get_combined_minimum_size()
	_slots.size = bar
	_slots.position = Vector2((_overlay.size.x - bar.x) * 0.5, _preview.position.y - SLOT_BAR_GAP - bar.y)

## Slot bar and preview: Experiment shows the pot (filled slots, empty ones, the locked 3rd); Cookbook shows the
## selected page's ingredients.
func _refresh_overlay() -> void:
	if _overlay == null: return
	var v := rt.session.current()
	for c in _slots.get_children(): c.queue_free()
	_slots.get_children().map(func(c): _slots.remove_child(c))
	if drawer.tab == "experiment":
		var open := P0KitchenLogic.slots(v)
		for i in maxi(open, 3):
			var s := UiKitchenSlot.new()
			if i < pot.size():
				s.state = UiKitchenSlot.State.FILLED
				s.icon = P0Logic.icon(str(pot[i]))
				s.title = P0Logic.item_name(v, str(pot[i]))
				s.quantity = "×1"
				var index := i
				s.tapped.connect(func(): _take_out(index, s.ring_center()))
			elif i < open:
				s.state = UiKitchenSlot.State.EMPTY
				s.title = "Add from bag"
			else:
				s.state = UiKitchenSlot.State.LOCKED
				s.title = P0KitchenLogic.locked_slot_label(v)
			_slots.add_child(s)
		var p := P0KitchenLogic.preview(v, pot)
		_preview.show_facts(p.title, p.state, p.time)
	else:
		var page := drawer.page(drawer.selected_page)
		for ing in P0KitchenLogic.page_ingredients(v, page):
			var s := UiKitchenSlot.new(UiKitchenSlot.State.FILLED)
			s.icon = ing.icon
			s.title = ing.name
			s.quantity = "×1"
			s.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_slots.add_child(s)
		var pp := P0KitchenLogic.page_preview(v, page) if not page.is_empty() else {title = "", state = "", time = ""}
		_preview.show_facts(pp.title, pp.state, pp.time)
	_place_overlay.call_deferred()

func _on_tab(tab: String) -> void:
	stage.clear_ghosts()
	if tab == "cookbook":
		for id in pot.duplicate(): stage.remove_ingredient(str(id))
		pot.clear()
		drawer.pot = pot
		drawer.refresh()
		var page := drawer.page(drawer.selected_page)
		if not page.is_empty(): _on_page(page)
	_refresh_overlay()

func _on_page(page: Dictionary) -> void:
	if drawer == null or drawer.tab != "cookbook": return
	stage.show_ghosts(P0KitchenLogic.page_ingredients(rt.session.current(), page).map(func(i): return i.icon))
	_refresh_overlay()

## Experiment: a tap moves one unit into the pot; tapping an item already in the pot takes it back (F-07).
func _on_ingredient(id: String, from_screen: Vector2) -> void:
	var v := rt.session.current()
	if not P0Logic.item(v, id).get("cook", false):
		rt.ui.toast("Not for cooking")
		return
	if pot.has(id):
		_take_out(pot.rfind(id), from_screen)
		return
	if pot.size() >= P0KitchenLogic.slots(v):
		rt.ui.toast("The pot is full · tap an ingredient to take it out")
		return
	if not P0KitchenLogic.can_add(v, pot, id): return
	pot.append(id)
	stage.add_ingredient(id, P0Logic.icon(id), from_screen)
	_after_pot_change()

func _take_out(index: int, to_screen: Vector2) -> void:
	if index < 0 or index >= pot.size(): return
	var id := str(pot[index])
	pot.remove_at(index)
	stage.remove_ingredient(id, to_screen)
	_after_pot_change()

func _after_pot_change() -> void:
	drawer.pot = pot
	drawer.refresh()
	_refresh_overlay()

func _on_cook(cmd: Dictionary) -> void:
	if _cook_sent: return
	_cook_sent = true
	rt.session.send(cmd, P0Session.ui_key(cmd))

# ---------------------------------------------------------------- server: the fire is lit
## `pot` event: the stove started. Close the drawer and watch the pot.
func on_pot(stove: Dictionary) -> void:
	var keep := pot.duplicate()
	var page := drawer.page(drawer.selected_page) if drawer else {}
	if phase == "compose":
		phase = "idle"   # closing must not clear what is in the pot
		rt.ui.close_modal()
		drawer = null
		_overlay = null
	if keep.is_empty() and not page.is_empty():
		stage.clear_ghosts()
		for ing in P0KitchenLogic.page_ingredients(rt.session.current(), page):
			stage.add_ingredient(str(ing.id), ing.icon)
	watch(stove)

## Watch a cooking stove: camera on the pot, heat ring over it, taps judged locally and sent at collect.
func watch(stove: Dictionary) -> void:
	_stove = stove
	_start_ms = Time.get_ticks_msec() - int(float(stove.get("elapsed", 0)))
	_taps.clear()
	_judged.clear()
	phase = "watch"
	_hide_player(true)
	stage.set_cooking(true)
	room.focus("cam_stove", {band = room.band_below_hud(BAND_TOP_WATCH), size = room.view_size() * FOCUS_SIZE, release_on_move = false})
	if _ring == null:
		_ring = UiHeatRing.new()
		_ring.theme = UiKit.theme()
		rt.ui.root.add_child(_ring)
	_ring.visible = false

## Stop watching (walked away / left): the pot keeps cooking on the server; unjudged rings are misses.
func stop_watching() -> void:
	if phase != "watch": return
	phase = "idle"
	_hide_ring()
	room.release_focus()
	_hide_player(false)

func _hide_ring() -> void:
	if _ring: _ring.visible = false

func elapsed() -> float: return float(Time.get_ticks_msec() - _start_ms)

## A tap while watching is the heat tap (anywhere: the whole pot is the target). Returns true when consumed.
func tap() -> bool:
	if phase == "serve": return true
	if phase != "watch": return false
	var e := elapsed()
	var heats: Array = _stove.get("heats", [])
	for i in heats.size():
		var h: Dictionary = heats[i]
		if _judged.has(i) or e < float(h.at) or e > float(h.at) + float(h.spin): continue
		_taps.append(roundi(e))
		var hit := P0Logic.heat_hit(h, e)
		_judged[i] = hit
		if _ring: _ring.result = 1 if hit else 0
		rt.ui.float_text("Nice heat! ★" if hit else "Missed · still cooking", _ring_center(), UiTokens.COLOR_GOLD_INK if hit else UiTokens.COLOR_SECONDARY)
		if hit: Input.vibrate_handheld(40)
		return true
	return true

## The ring hangs over the pot (§7.2.4) without covering it or the cards in it.
func _ring_center() -> Vector2:
	var mouth := room.anchor("drop_pot_1")
	if mouth == null: return room.get_viewport().get_visible_rect().size * 0.5
	var pot := room.cam.unproject_position(mouth.global_position)
	var half := (_ring.size.y if _ring else 120.0) * 0.5
	return pot - Vector2(0, P0KitchenStage.CARD_PX + RING_GAP + half)

func _process(_dt: float) -> void:
	if phase != "watch": return
	var e := elapsed()
	var total := float(_stove.get("ms", 5000))
	var heats: Array = _stove.get("heats", [])
	var active := -1
	for i in heats.size():
		var h: Dictionary = heats[i]
		if auto_play and not _judged.has(i) and e >= float(h.at) + (float(h.gold) + float(h.width) * 0.5) * float(h.spin): tap()
		if not _judged.has(i) and e > float(h.at) + float(h.spin):
			_judged[i] = false
			rt.ui.float_text("Missed · still cooking", _ring_center(), UiTokens.COLOR_SECONDARY)
		if e >= float(h.at) - RING_EARLY_MS and e <= float(h.at) + float(h.spin) + 350.0: active = i
	if _ring:
		_ring.visible = active >= 0
		if active >= 0:
			var h: Dictionary = heats[active]
			_ring.gold = float(h.gold)
			_ring.width = float(h.width)
			_ring.grow = clampf(1.0 - (float(h.at) - e) / RING_EARLY_MS, 0.0, 1.0)
			_ring.turn = clampf((e - float(h.at)) / float(h.spin), 0.0, 1.0)
			_ring.result = (1 if _judged[active] else 0) if _judged.has(active) else -1
			_ring.position = _ring_center() - _ring.size * 0.5
	if e >= total + 250.0: serve(_taps.duplicate())

# ---------------------------------------------------------------- serve
## The dish comes out of the pot, then collect is sent once (taps: the heat taps of this watch, [] otherwise).
func serve(taps: Array) -> void:
	if phase == "serve": return
	var v := rt.session.current()
	var st = P0KitchenLogic.stove(v)
	if st == null: return
	phase = "serve"
	_hide_ring()
	var dish = st.get("dish", null)
	var rarity := int(st.get("rarity", 1))
	var glow: Color = UiItemCell.RARITY_COLORS[clampi(rarity - 1, 0, 3)]
	stage.serve(P0Logic.icon(str(dish) if dish != null else "dish_mystery"), rarity, glow, func():
		await room.get_tree().create_timer(SERVE_HOLD_S).timeout
		rt.session.send({"type": "collect", "taps": taps}, P0Session.ui_key({"type": "collect"})))

## The server settled the pot (`dish` event or the stove went empty): back to idle, the plate goes away.
func on_collected() -> void:
	if phase == "serve" or phase == "watch":
		phase = "idle"
		room.release_focus()
		_hide_player(false)
	stage.clear_plate()
	stage.clear_ingredients()
	stage.set_cooking(false)

func _exit_tree() -> void:
	if _ring and is_instance_valid(_ring): _ring.queue_free()
