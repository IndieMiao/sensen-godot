class_name P0Kitchen
extends Node
## The farmhouse stove corner's cooking flow (SGODOT-226, LOCK-20 v5; plan §7.2.2 / §7.2.4 / §7.2.7):
##   compose  the cooking drawer (P0KitchenDrawer, 60 %) opens with the camera pushed onto the stove in the band
##            above it; the slot bar and the preview capsule sit just above the drawer (COOK-2a / 2b); picks fly
##            into the 3D pot (P0KitchenStage); Cookbook pages show their ingredients as ghosts.
##   watch    Cook closes the drawer; the ingredients sink into the pot, the stove steams, the heat ring sits on
##            the pot and the bottom sheet counts down (COOK-3 / COOK-P0-3). A tap anywhere on the scene is the heat
##            tap (the whole pot is the target, §7.2.4), sent at once as `heat`. Walking away or × stops watching:
##            the pot keeps cooking and the unwatched rings count as misses (Plain, §7.2.3).
##   serve    at the end the plate slides out with its rarity glow, then `collect` goes to the server once.
##   card     the result card (COOK-4 New recipe! / COOK-6 Mystery Dish / COOK-P0-9 Dish ready): Eat or Keep.
##            The server already kept the portions (Warming Cabinet → bag → stove, PR #20); Eat eats one from
##            where it went, Keep or a tap outside says where it went (KEEP-STATES). Li Bai, 226 250e4ef1.
## The server owns the stove (`view.cooking.stove`): leaving and coming back shows Ready, collect happens once.

const BAND_TOP_DRAWER := 0.29     # engineering default, WP7 v2: pot band ends above the slot bar
const BAND_TOP_WATCH := 0.40      # COOK-3: the pot sits high, under the HUD, above the watch sheet
const FOCUS_SIZE := 0.42          # pushed-in view: 42 % of the room's accepted width
const WATCH_FOCUS_SIZE := 0.34    # COOK-3 pushes in further on the pot (approved kitchen camera ×1.85)
const OVERLAY_GAP := 6.0          # preview above the drawer top, slot bar above the preview
const SLOT_BAR_GAP := 3.0
const SLOT_GAP := 8.0
const WATCH_SHEET_H := 196.0      # COOK-3 sheet: dish, Cooking, m:ss remaining, the heat hint
const CLOSE_GAP := 6.0            # × sits this far above the sheet's top edge (COOK-3: 554 → 604)
const CARD_TOP := 0.425           # RewardMoment top at 340 of 800 (COOK-4)
const PLATE := preload("res://assets/p0/kitchen/reveal/plate.svg")
const CookAgainSheet := preload("res://scenes/p0/kitchen/p0_cook_again_sheet.gd")
const SPARKLE := preload("res://assets/p0/kitchen/reveal/sparkle.svg")
## COOK-4 reveal over the card, in 360 × 800 design px: [x, y, side_x, side_y]. The glow is the blurred ellipse
## (200 × 140 + its blur), the plate keeps its shadow margin, the dish icon is 96.
const REVEAL_GLOW := [52.0, 142.0, 256.0, 196.0]
const REVEAL_PLATE := [95.0, 228.0, 170.0, 82.0]
const REVEAL_DISH := [132.0, 186.0, 96.0, 96.0]
const REVEAL_SPARKLES := [[96.0, 180.0, 20.0], [262.0, 196.0, 16.0], [248.0, 282.0, 14.0], [104.0, 280.0, 12.0]]
const REVEAL_POP_MS := 220.0
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
var phase := "idle"               # idle | compose | again | watch | serve | card
## The last pot's page when it was a known recipe ("" after a Mystery Dish): Cook Again (COOK-P0-7) offers it.
var last_page := ""

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
var _sheet: UiDrawer
var _sheet_header: UiObjectHeader
var _close: UiCloseButton
var _events: Array = []            # this collect's reply, for the card and the Keep toast
var _from_stove := false
var _card_dish := ""
var _card_where := ""
var _card_done := false
var _left_card := false            # the card is for a portion waiting on the stove (COOK-P0-9 from leftovers)
var _retrying := false             # Keep sent a collect for leftovers: its reply says where they went
var _card: UiRewardMoment

func _init(room_: P0Room) -> void:
	room = room_
	name = "Kitchen"

func _ready() -> void:
	stage = P0KitchenStage.new()
	stage.name = "Stage"
	stage.cam = room.cam
	stage.glow_light = room.room.find_child("HearthGlow", true, false)
	stage.fire_fx = room.art.get("fire") as Node if "fire" in room.art else null
	var mouth := room.anchor("drop_pot_1")
	if mouth: mouth.add_child(stage)
	else: room.add_child(stage)

func busy() -> bool: return phase != "idle"

# ---------------------------------------------------------------- compose
## COOK-P0-7 / P0-8: the last known page again (Cooking Lv2 Cook Again). Choose recipe › and Details › go to its
## Cookbook page; Cook Again sends the page's cook (nothing is taken before that, An Qi La on 226).
func open_again(page_id: String) -> void:
	if rt == null or busy(): return
	var facts := P0KitchenLogic.cook_again(rt.session.current(), page_id)
	if facts.is_empty():
		open("cookbook")
		return
	var sheet := CookAgainSheet.new(facts)
	sheet.safe_bottom = rt.ui.safe_bottom()
	sheet.close_requested.connect(func(): rt.ui.close_modal())
	sheet.unavailable.connect(func(r: String): rt.ui.toast(r))
	sheet.cook.connect(func(cmd: Dictionary): rt.session.send(cmd, P0Session.ui_key(cmd)))
	var to_page := func():
		rt.ui.close_modal()
		open("cookbook", page_id)
	sheet.choose_recipe.connect(to_page)
	sheet.details.connect(to_page)
	rt.ui._open_modal(sheet, 0.0, true)
	rt.ui.modal_kind = "cook_again"
	phase = "again"
	sheet.tree_exited.connect(func():
		if phase != "again": return
		phase = "idle"
		room.release_focus()
		_hide_player(false))
	_hide_player(true)
	room.focus("cam_stove", {band = room.band_below_hud(1.0 - CookAgainSheet.HEIGHT / 800.0 - 0.02), size = room.view_size() * FOCUS_SIZE, release_on_move = false})

## Opens the cooking drawer on `tab` (Cookbook / Experiment) with the camera on the stove.
func open(tab := "cookbook", page_id := "") -> void:
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
	if page_id != "" and not drawer.page(page_id).is_empty(): drawer.select_page(page_id)
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
				s.title = "Add ingredient"
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
	if not P0Logic.item(P0KitchenLogic.with_rack(v), id).get("cook", false):
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
	if phase == "again":
		phase = "idle"   # closing the Cook Again sheet must not release the camera before watching
		rt.ui.close_modal()
	if phase == "compose":
		phase = "idle"   # closing must not clear what is in the pot
		rt.ui.close_modal()
		drawer = null
		_overlay = null
	stage.clear_ghosts()
	stage.clear_ingredients()   # COOK-3: once the fire is lit the ingredients are in the pot
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
	room.focus("cam_stove", {band = room.band_below_hud(BAND_TOP_WATCH), size = room.view_size() * WATCH_FOCUS_SIZE, release_on_move = false})
	if _ring == null:
		_ring = UiHeatRing.new()
		_ring.theme = UiKit.theme()
		rt.ui.root.add_child(_ring)
	_ring.visible = false
	_show_sheet(stove)

## COOK-3 bottom sheet: ObjectHeader (dish · Cooking · m:ss remaining) and the heat hint, × above it. Not modal:
## taps on the scene above stay heat taps.
func _show_sheet(stove: Dictionary) -> void:
	if _sheet == null:
		_sheet = UiDrawer.new(WATCH_SHEET_H)
		_sheet.theme = UiKit.theme()
		_sheet.safe_bottom = rt.ui.safe_bottom()
		_sheet.close_requested.connect(stop_watching)
		_sheet_header = UiObjectHeader.new()
		_sheet.body.add_child(_sheet_header)
		var hint := UiKit.label("Tap when the needle reaches gold.", UiTokens.STYLE_EFFECT_B15)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sheet.body.add_child(hint)
		rt.ui.root.add_child(_sheet)
		_close = UiCloseButton.new()
		_close.theme = UiKit.theme()
		_close.pressed.connect(stop_watching)
		rt.ui.root.add_child(_close)
	var dish = stove.get("dish", null)
	_sheet_header.title = P0Logic.item_name(rt.session.current(), str(dish)) if dish != null else "Unknown dish"
	_sheet_header.state = "Cooking"
	_sheet_header.quantity_label = "remaining"
	_update_sheet()

func _update_sheet() -> void:
	if _sheet == null: return
	var left := maxf(0.0, float(_stove.get("ms", 0)) - elapsed())
	_sheet_header.quantity = "%d:%02d" % [int(left / 60000.0), int(left / 1000.0) % 60]
	var top := rt.ui.root.size.y - WATCH_SHEET_H - _sheet.safe_bottom
	_close.position = Vector2(rt.ui.root.size.x - UiTokens.SPACE_PAGE - UiTokens.SIZE_CLOSE, top - CLOSE_GAP - UiTokens.SIZE_CLOSE)

func _hide_sheet() -> void:
	if _sheet and is_instance_valid(_sheet): _sheet.queue_free()
	if _close and is_instance_valid(_close): _close.queue_free()
	_sheet = null
	_close = null

## Stop watching (walked away / left): the pot keeps cooking on the server; unjudged rings are misses.
func stop_watching() -> void:
	if phase != "watch": return
	phase = "idle"
	_hide_ring()
	_hide_sheet()
	room.release_focus()
	_hide_player(false)

func _hide_ring() -> void:
	if _ring: _ring.visible = false

func elapsed() -> float: return float(Time.get_ticks_msec() - _start_ms)

## A tap while watching is the heat tap (anywhere: the whole pot is the target). Returns true when consumed.
func tap() -> bool:
	if phase == "serve" or phase == "card": return true
	if phase != "watch": return false
	var e := elapsed()
	var heats: Array = _stove.get("heats", [])
	for i in heats.size():
		var h: Dictionary = heats[i]
		if _judged.has(i) or e < float(h.at) or e > float(h.at) + float(h.spin): continue
		_taps.append(roundi(e))
		var hit := P0Logic.heat_hit(h, e)
		_judged[i] = hit
		# S5 (SGODOT-232): the server keeps each ring's first tap, so an automatic Keep judges it too.
		if P0KitchenLogic.cooking(rt.session.current()).has("conveniences"): rt.session.send(_with_pot({"type": "heat", "taps": [roundi(e)]}, _stove))
		if _ring: _ring.result = 1 if hit else 0
		rt.ui.float_text("Nice heat! ★" if hit else "Missed · still cooking", _ring_center(), UiTokens.COLOR_GOLD_INK if hit else UiTokens.COLOR_SECONDARY)
		if hit: Input.vibrate_handheld(40)
		return true
	return true

## S5 Queue ×2 (PR #22): heat and collect name the pot they are for, so a pot the server already kept on its own
## answers stale_pot instead of judging the next one.
static func _with_pot(cmd: Dictionary, pot: Dictionary) -> Dictionary:
	if pot.get("id", null) != null: cmd["pot"] = pot.id
	return cmd

## The ring sits on the pot (COOK-3: the whole pot is the target, §7.2.4).
func _ring_center() -> Vector2:
	var mouth := room.anchor("drop_pot_1")
	if mouth == null: return room.get_viewport().get_visible_rect().size * 0.5
	return room.cam.unproject_position(mouth.global_position)

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
	_update_sheet()
	if e >= total + 250.0: serve(_taps.duplicate())

# ---------------------------------------------------------------- serve
## The dish comes out of the pot, then collect is sent once (taps: the heat taps of this watch, [] otherwise).
## from_stove: the player came back to a Ready stove (COOK-P0-9 says Collected from Stove 1).
func serve(taps: Array, from_stove := false) -> void:
	if phase == "serve" or phase == "card": return
	var v := rt.session.current()
	var st = P0KitchenLogic.stove(v)
	if st == null: return
	phase = "serve"
	_from_stove = from_stove
	_events.clear()
	_hide_ring()
	_hide_sheet()
	var dish = st.get("dish", null)
	var rarity := int(st.get("rarity", 1))
	var glow: Color = UiItemCell.RARITY_COLORS[clampi(rarity - 1, 0, 3)]
	stage.serve(P0Logic.icon(str(dish) if dish != null else "dish_mystery"), rarity, glow, func():
		await room.get_tree().create_timer(SERVE_HOLD_S).timeout
		rt.session.send(_with_pot({"type": "collect", "taps": taps}, st), P0Session.ui_key({"type": "collect"})))

## A collect's events in order (cabinet / item / plate / dish / first / mishap): the card is built once the
## whole reply is in. Returns true when the kitchen shows the result itself (no old dish card).
func on_event(ev: Dictionary) -> bool:
	match str(ev.get("kind", "")):
		"dish":
			var known := not bool(ev.get("mystery", false)) and not bool(ev.get("none", false))
			last_page = str(ev.get("dish", "")) if known else ""
			if bool(ev.get("auto", false)):   # S5 Queue ×2 kept it on its own: the toast only, no card
				_toast_keep.call_deferred(ev, P0KitchenLogic.routes(_events + [ev]))
				return true
			_events.append(ev)
			if phase == "serve": _show_card.call_deferred()
			return true
		"cabinet", "item", "plate", "first", "mishap":
			if _retrying and str(ev.kind) in ["cabinet", "item", "plate"]:
				_retrying = false
				var r := P0KitchenLogic.routes([ev])
				var id := str(r.keys()[0]) if not r.is_empty() else _card_dish
				rt.ui.toast(str(P0KitchenLogic.keep_line(rt.session.current(), id, str(r.get(id, "bag"))).text))
				return false
			_events.append(ev)
	return false

## The server settled the pot without a card (refused as empty): back to idle, the plate goes away.
func on_collected() -> void:
	if phase == "serve" or phase == "watch":
		phase = "idle"
		room.release_focus()
		_hide_player(false)
	_hide_sheet()
	stage.clear_plate()
	stage.clear_ingredients()
	stage.set_cooking(false)

# ---------------------------------------------------------------- the result card (COOK-4 / 6 / P0-9)
func _show_card() -> void:
	_left_card = false
	var dish_ev: Dictionary = {}
	var first_xp := 0
	for ev in _events:
		if str(ev.kind) == "dish": dish_ev = ev.duplicate()
		if str(ev.kind) == "first" and str(ev.get("what", "")).begins_with("cook:"): first_xp = int(ev.xp)
		if str(ev.kind) == "mishap": dish_ev["clue"] = ev.get("clue", null)
	if dish_ev.is_empty(): return
	var v := rt.session.current()
	var fields := P0KitchenLogic.dish_card(v, dish_ev, first_xp, _from_stove)
	_card_dish = str(fields.dish_id)
	_card_where = str(P0KitchenLogic.routes(_events).get(_card_dish, "bag"))
	_open_card(fields)

## The P0-9 card for a portion already waiting on the stove (nothing to judge): Eat takes it from the stove,
## Keep tries the cabinet and the bag again.
func show_left(id: String) -> void:
	if rt == null or busy(): return
	var v := rt.session.current()
	var base := id.get_slice("@", 0)
	var quality := ["plain", "good", "perfect"].find(id.get_slice("@", 1)) if id.contains("@") else 0
	_events.clear()
	_from_stove = true
	var fields := P0KitchenLogic.dish_card(v, {dish = base, quality = maxi(quality, 0), mystery = base == "dish_mystery"}, 0, true)
	_card_dish = id
	_card_where = "stove"
	_left_card = true
	_hide_player(true)
	room.focus("cam_stove", {band = room.band_below_hud(BAND_TOP_WATCH), size = room.view_size() * FOCUS_SIZE, release_on_move = false})
	_open_card(fields)

func _open_card(fields: Dictionary) -> void:
	var v := rt.session.current()
	var card := UiRewardMoment.new()
	_card = card
	card.theme = UiKit.theme()
	var none := bool(fields.get("none", false))   # nothing came out (a refunded trial pot): OK only, no Keep
	fields.erase("dish_id")
	fields.erase("none")
	card.show_fields(fields)
	if none:
		_card_done = true
		card.primary = "OK"
		card.primary_pressed.connect(func(): rt.ui.close_modal())
	else:
		card.secondary = "Keep"
		var eat := P0KitchenLogic.eat_state(v, _card_dish)
		card.primary = str(eat.text)
		card.primary_reason = str(eat.reason)
		card.primary_pressed.connect(_on_eat)
	card.unavailable_pressed.connect(func(reason: String): rt.ui.toast(reason))
	card.secondary_pressed.connect(func(): rt.ui.close_modal())
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not none: wrap.add_child(_reveal(card.icon, card.rarity, card.tone == UiRewardMoment.Tone.NEUTRAL))
	wrap.add_child(card)
	stage.clear_plate()   # the 3D plate hands over to the reveal
	var place := func(): card.position = Vector2((wrap.size.x - card.size.x) * 0.5, wrap.size.y * CARD_TOP)
	card.resized.connect(place)
	wrap.resized.connect(place)
	phase = "card"
	_card_done = none
	rt.ui._open_modal(wrap, UiTokens.OPACITY_SCRIM_MODAL, true)
	rt.ui.modal_kind = "kitchen_card"
	wrap.tree_exited.connect(_on_card_closed)

## True while a collect's reply has not produced its card yet (the stove view goes empty in the same reply).
func waiting_events() -> bool: return _events.is_empty()

## Dev steps: tap the card's primary button.
func press_eat() -> void:
	if _card and is_instance_valid(_card): _card.primary_pressed.emit() if _card.primary_reason == "" else _card.unavailable_pressed.emit(_card.primary_reason)

## COOK-4 / COOK-6 in-scene reveal above the card: the rarity glow (rarity-dot colour; Common and the Mystery Dish
## have none), the plate, the dish at 96 and sparkles, popping in. Placed in 360 × 800 design px, scaled.
func _reveal(dish_icon: Texture2D, rarity: int, mystery: bool) -> Control:
	var r := Control.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parts: Array = []   # [node, rect]
	if rarity >= 2 and not mystery:
		var g := Gradient.new()
		var c: Color = UiRewardMoment.RARITY_COLORS[clampi(rarity - 1, 0, 3)]
		g.set_color(0, Color(c, 0.55))
		g.set_color(1, Color(c, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		parts.append([_reveal_rect(tex), REVEAL_GLOW])
	parts.append([_reveal_rect(PLATE), REVEAL_PLATE])
	parts.append([_reveal_rect(dish_icon), REVEAL_DISH])
	if rarity >= 2 and not mystery:
		for sp in REVEAL_SPARKLES: parts.append([_reveal_rect(SPARKLE), [sp[0], sp[1], sp[2], sp[2]]])
	for p in parts: r.add_child(p[0])
	var place := func():
		var k := r.size.x / 360.0
		var ky := r.size.y / 800.0
		for p in parts:
			var rect: Array = p[1]
			var node: Control = p[0]
			node.size = Vector2(rect[2], rect[3]) * k
			node.position = Vector2(r.size.x * 0.5 + (float(rect[0]) - 180.0) * k, float(rect[1]) * ky)
			node.pivot_offset = node.size * 0.5
	r.resized.connect(place)
	r.modulate.a = 0.0
	var t := r.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(r, ^"modulate:a", 1.0, UiKit.secs(REVEAL_POP_MS))
	return r

static func _reveal_rect(tex: Texture2D) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

## Eat: one portion from where the server kept it (the button already says what it gives, q(10)).
func _on_eat() -> void:
	_card_done = true
	var cmd := P0KitchenLogic.eat_command(_card_dish, _card_where)
	rt.session.send(cmd, P0Session.ui_key(cmd))
	rt.ui.close_modal()

## Keep (or a tap outside, or walking off): say where it went (KEEP-STATES); a portion still on the stove is
## tried again the Keep way, and that reply says where it went.
func _on_card_closed() -> void:
	if phase != "card": return
	phase = "idle"
	if not _card_done:
		var v := rt.session.current()
		if _left_card and P0KitchenLogic.keep_room(v, _card_dish):
			_retrying = true   # room again: try the Keep way; the reply's routing event says where it went
			var cmd := {"type": "collect"}
			rt.session.send(cmd, P0Session.ui_key(cmd))
		else: rt.ui.toast(str(P0KitchenLogic.keep_line(v, _card_dish, _card_where).text))
	_card_done = true
	_events.clear()
	room.release_focus()
	_hide_player(false)
	stage.clear_plate()
	stage.clear_ingredients()
	stage.set_cooking(false)

func _toast_keep(ev: Dictionary, routes: Dictionary) -> void:
	var base := str(ev.get("dish", ""))
	var q := int(ev.get("quality", 0))
	var id := base if q == 0 else "%s@%s" % [base, ["plain", "good", "perfect"][q]]
	rt.ui.toast(str(P0KitchenLogic.keep_line(rt.session.current(), id, str(routes.get(id, "bag"))).text))

func _exit_tree() -> void:
	if _ring and is_instance_valid(_ring): _ring.queue_free()
	_hide_sheet()
