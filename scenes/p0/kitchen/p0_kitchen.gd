class_name P0Kitchen
extends Node
## The farmhouse stove corner's cooking flow (SGODOT-226, LOCK-20 v5; plan §7.2.2 / §7.2.4 / §7.2.7):
##   compose  the cooking drawer (P0KitchenDrawer, 60 %) opens with the camera pushed onto the stove in the band
##            above it; the pot card (slots and the result line, UiPotCard, 256 ⑤ A') sits just above the drawer
##            (COOK-2a / 2b); picks fly into the 3D pot (P0KitchenStage); Cookbook pages show their ingredients as ghosts.
##   watch    Cook closes the drawer; the ingredients sink into the pot, the stove steams, the heat ring sits on
##            the pot and the bottom sheet counts down (COOK-3 / COOK-P0-3). A tap anywhere on the scene is the heat
##            tap (the whole pot is the target, §7.2.4), sent at once as `heat`. Walking away or × stops watching:
##            the pot keeps cooking and the unwatched rings count as misses (Plain, §7.2.3).
##   serve    at the end the plate slides out with its rarity glow, then `collect` goes to the server once.
##   rotate   Queue ×2 (Cooking Lv5, q(71)): the watched pot is done and another waits behind it. `collect` goes out
##            with no plate and no card; the toast says what was kept and what cooks now, and the watch moves on to
##            the next pot. Queue next › on the watch sheet opens the drawer (its Cook reads Queue) over the pot.
##   card     the result card (COOK-4 New recipe! / COOK-6 Mystery Dish / COOK-P0-9 Dish ready): Eat or Keep.
##            The server already kept the portions (Warming Cabinet → bag → stove, PR #20); Eat eats one from
##            where it went, Keep or a tap outside says where it went (KEEP-STATES). Li Bai, 226 250e4ef1.
## The server owns the stove (`view.cooking.stove`): leaving and coming back shows Ready, collect happens once.

const BAND_TOP_DRAWER := 0.29     # engineering default, WP7 v2: pot band ends above the slot bar
const BAND_TOP_WATCH := 0.40      # COOK-3: the pot sits high, under the HUD, above the watch sheet
## The queue drawer (Queue next ›) keeps the heat ring over the pot: the pot sits this much lower than in the cooking
## drawer, so HUD + 8 ≤ the ring's top, its foot + 8 ≤ the pot card and the card + 8 ≤ the drawer (不知火舞 on #142).
const QUEUE_DROP := 14.0
const FOCUS_SIZE := 0.42          # pushed-in view: 42 % of the room's accepted width
const WATCH_FOCUS_SIZE := 0.34    # COOK-3 pushes in further on the pot (approved kitchen camera ×1.85)
const OVERLAY_GAP := 8.0          # the pot card's foot above the drawer top (row 53: 326 → 334)
const WATCH_SHEET_H := 196.0      # COOK-3 sheet: dish, Cooking, m:ss remaining, the heat hint
const CLOSE_GAP := 6.0            # × sits this far above the sheet's top edge (COOK-3: 554 → 604)
const QUEUE_BADGE_AT := Vector2(59, 33)   # COOK-QUEUE-1c 1758:103247: the next pot's dish beside the pot (design px)
const CARD_TOP := 0.425           # RewardMoment top at 340 of 800 (COOK-4)
const FLOAT_AT := 0.205           # result floats (XP) rise from just above the plate: COOK-4 chip at y 150–176 of 800
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
var _pot_card: UiPotCard
var _point_at_remove := false      # the pot is full and a bag cell was tapped: ✕ wears its gold-brown ring (q(64))
var _ring: UiHeatRing
var _stove: Dictionary = {}
## The stove this kitchen works (SGODOT-282: Homestead Lv4 / Lv8 bring stoves 2 and 3), 0-based. The drawer, the
## watch, serve and the 3D stage all follow it; P0Farmhouse picks it when a stove is tapped.
var stove_index := 0
const STOVE_PAN_S := 0.25   # the camera's pan from one pot to the next (b84a5e01 ②, ease-out)
var _start_ms := 0
var _taps: Array = []
var _judged := {}
var _judged_turn := {}   # ring index → the needle's turn (0–1) when it was judged: where its result dot sits (⑩)
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
var _queue_mode := false           # the drawer was opened from Queue next ›: closing it goes back to the watch
var _queue_next: UiNavButton
var _queue_badge: UiWorldIconButton
var _queue_ev: Dictionary = {}     # this reply's `queue` event: the waiting pot just fired

func _init(room_: P0Room) -> void:
	room = room_
	name = "Kitchen"

func _ready() -> void:
	stage = P0KitchenStage.new()
	stage.name = "Stage"
	stage.cam = room.cam
	stage.glow_light = room.room.find_child("HearthGlow", true, false)
	stage.fire_fx = room.call("stove_fire") if room.has_method("stove_fire") else null
	var mouth := room.anchor(drop_name())
	if mouth: mouth.add_child(stage)
	else: room.add_child(stage)

func busy() -> bool: return phase != "idle"

## Anchor names for the working stove: stove 1 keeps the P0 names (drop_pot_1, cam_stove); 2 and 3 have their own.
func drop_name() -> String: return "drop_pot_%d" % (stove_index + 1)
func cam_name() -> String: return "cam_stove" if stove_index == 0 or room.anchor("cam_stove_%d" % (stove_index + 1)) == null else "cam_stove_%d" % (stove_index + 1)

## Switch the stove this kitchen works (a stove tapped, the drawer's Stove n/N pill): the 3D stage moves to that pot.
## Only while nothing is in flight on the current one (idle, or the drawer composing).
func select_stove(i: int) -> void:
	var n := P0KitchenLogic.stove_count(rt.session.current()) if rt else 1
	i = clampi(i, 0, maxi(0, n - 1))
	if i == stove_index: return
	stove_index = i
	var mouth := room.anchor(drop_name())
	if mouth and stage.get_parent() != mouth: stage.reparent(mouth, false)
	stage.set_cooking(P0KitchenLogic.stove(rt.session.current(), stove_index) != null if rt else false)

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
	sheet.cook.connect(func(cmd: Dictionary):
		cmd = with_stove(cmd)
		rt.session.send(cmd, P0Session.ui_key(cmd)))
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
	room.focus(cam_name(), {band = room.band_below_hud(1.0 - CookAgainSheet.HEIGHT / 800.0 - 0.02), size = room.view_size() * FOCUS_SIZE, release_on_move = false})

## Opens the cooking drawer on `tab` (Cookbook / Experiment) with the camera on the stove. A page Today's cook row
## pointed at (P0Ui.cook_page_from_today, q(99)) is the Cookbook's selection this once, unless a page is given.
func open(tab := "cookbook", page_id := "") -> void:
	if rt == null or phase in ["watch", "serve"]: return
	if page_id == "" and tab == "cookbook": page_id = rt.ui.cook_page_from_today
	rt.ui.cook_page_from_today = ""   # spent by any opening of the drawer
	pot.clear()
	stage.clear_ingredients()
	stage.clear_ghosts()
	_cook_sent = false
	_wrap = Control.new()
	_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrap.theme = UiKit.theme()
	drawer = P0KitchenDrawer.new(rt.session.current(), tab)
	drawer.queue_mode = _queue_mode
	drawer.stove_index = stove_index
	drawer.stove_cycle_requested.connect(_cycle_stove)
	drawer.unavailable.connect(func(r: String): rt.ui.toast(r))   # a grey Double says why (b84a5e01 ③)
	drawer.double_changed.connect(func(_on: bool): _refresh_overlay())   # ×2 on the slots and the card (02ad95bc ④)
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
	rt.ui.teach("cook")   # U6: "Tap Cook to grill your first fish" the first time the drawer opens (§14.2)
	_hide_player(true)
	var band := room.band_below_hud(BAND_TOP_DRAWER)
	if _queue_mode: band.position.y += QUEUE_DROP / maxf(room.get_viewport().get_visible_rect().size.y, 1.0)
	room.focus(cam_name(), {band = band, size = room.view_size() * FOCUS_SIZE, release_on_move = false})
	if page_id != "" and not drawer.page(page_id).is_empty(): drawer.select_page(page_id)
	if tab == "cookbook" and drawer.selected_page != "": _on_page(drawer.page(drawer.selected_page))
	_refresh_overlay()

func _on_closed() -> void:
	if phase != "compose": return
	if rt.ui._modal_back == Callable(self, "close_cook_all"): rt.ui._modal_back = Callable()   # the sheet went with the drawer
	cook_all_sheet = null
	_cook_all_close = null
	_cook_all_back = Callable()
	phase = "idle"
	drawer = null
	_overlay = null
	pot.clear()
	stage.clear_ingredients()
	stage.clear_ghosts()
	if _queue_mode:   # opened from Queue next ›: back to the pot on the stove, whether a pot was queued or not (q(71))
		_queue_mode = false
		var st = P0KitchenLogic.stove(rt.session.current(), stove_index)
		if st != null:
			watch(st)
			return
		_hide_ring()   # no pot to go back to: the ring the drawer kept running goes too (刘邦 on #120)
	room.release_focus()
	_hide_player(false)

## The drawer's `Stove 2/3 ›` (b84a5e01 ②): the next stove, 3 back to 1; the camera pans to its pot in 0.25 s and
## the drawer shows that stove. A stove that is cooking or waiting to be collected closes the drawer and shows its pot
## the way a tap on it does (only an empty stove composes).
func _cycle_stove() -> void:
	if phase != "compose" or _queue_mode: return
	var v := rt.session.current()
	var n := P0KitchenLogic.stove_count(v)
	if n < 2: return
	var next := (stove_index + 1) % n
	pot.clear()
	stage.clear_ingredients()
	stage.clear_ghosts()
	select_stove(next)
	if P0KitchenLogic.stove(v, next) != null:
		phase = "idle"   # the drawer's close must not undo the switch
		rt.ui.close_modal()
		drawer = null
		_overlay = null
		room.call("open_stove", "cookbook", false)
		return
	drawer.stove_index = next
	drawer.refresh()
	_refresh_overlay()
	var band := room.band_below_hud(BAND_TOP_DRAWER)
	room.focus(cam_name(), {band = band, size = room.view_size() * FOCUS_SIZE, release_on_move = false, ease_s = STOVE_PAN_S})

## Queue next › (q(71)): the cooking drawer over the pot being watched, its Cook reading Queue. The watch resumes when
## the drawer closes. The queue drawer is not leaving the pot (§7.2.3; 不知火舞 on 226): the heat rings go on over the
## pot in the band above it, drawn over the slot bar and the preview, and a tap on that band inside a ring's window
## judges it with its float, the drawer staying open; rings judged meanwhile stand when the watch resumes.
func open_queue() -> void:
	if phase != "watch" or not P0KitchenLogic.can_queue(rt.session.current(), stove_index): return
	_hide_sheet()
	phase = "idle"
	_queue_mode = true
	open("cookbook")
	if phase != "compose": return
	_band = _heat_band()
	_wrap.add_child(_band)
	_wrap.move_child(_band, 0)   # under the drawer, the slot bar and the preview: they keep their own taps
	if _ring: rt.ui.root.move_child(_ring, -1)   # over the drawer's layer

## The pot band's heat taps while the queue drawer is open: in a ring's window a tap judges it; while a ring shows
## (growing 1 s before its turn, the 350 ms it stays after) a tap outside the window does nothing, as tap() swallows it
## while watching (不知火舞 on 226); with no ring showing it is the scrim's tap, as before (back closes the drawer).
var _band: Control
func _heat_band() -> Control:
	var band := Control.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.mouse_filter = Control.MOUSE_FILTER_STOP
	band.gui_input.connect(func(e: InputEvent):   # STOP: the scrim under it never sees the tap
		if P0Ui.is_tap(e) and not _judge_tap() and not (_ring and _ring.visible): rt.ui.back_modal())
	return band

## The heat rings run while watching and while the queue drawer is open over the pot (open_queue).
func _heat_live() -> bool: return phase == "watch" or (phase == "compose" and _queue_mode)

## Shots (until:gold / until:goldsoon, then heattap): a ring not yet judged has its needle on gold `lead_ms` from now.
func at_gold(lead_ms := 0.0) -> bool:
	if not _heat_live(): return false
	var e := elapsed() + lead_ms
	var heats: Array = _stove.get("heats", [])
	for i in heats.size():
		if not _judged.has(i) and e >= float(heats[i].at) and P0Logic.heat_hit(heats[i], e, 0.0): return true
	return false

## Shots (until:earlysoon / until:tailsoon): a ring not yet judged has its needle `lead_ms` from now between `from` and
## `to` (fractions of its turn; past 1 is the 350 ms it stays after its turn).
func ring_at(lead_ms: float, from: float, to: float) -> bool:
	if not _heat_live(): return false
	var e := elapsed() + lead_ms
	for h in _stove.get("heats", []):
		var f := (e - float(h.at)) / float(h.spin)
		if f >= from and f <= to: return true
	return false

## Shots: the heat tap a player's finger makes now (on the watched pot or the queue drawer's pot band).
func dev_heat_tap() -> void: _judge_tap()

## Shots: where the heat ring, the pot card and the drawer sit (screen px), to check their gaps.
func dev_rects() -> Dictionary:
	var out := {}
	if _ring: out.ring = [_ring_center().y - UiHeatRing.OUTER * _ring.scale.y, _ring_center().y + UiHeatRing.OUTER * _ring.scale.y]
	if is_instance_valid(_pot_card): out.card = [_pot_card.get_global_rect().position.y, _pot_card.get_global_rect().end.y]
	if drawer: out.drawer = drawer.top_y()
	return out

## Shots: a tap on the pot card's slot `i` (a filled one goes back to the bag, the lock says what opens it).
func dev_slot_tap(i: int) -> void:
	if not is_instance_valid(_pot_card) or i < 0 or i >= _pot_card.slots().size(): return
	var s: UiPotSlot = _pot_card.slots()[i]
	if s.state == UiPotSlot.State.LOCKED: s.locked_tapped.emit()
	elif s.removable: s.tapped.emit()

## Shots: a press on the queue drawer's pot band, as a finger makes it.
func dev_band_press() -> void:
	if _band == null or not is_instance_valid(_band): return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	_band.gui_input.emit(press)

## Shots (until:growsoon, then heatband): a ring not yet judged is growing, before its window, `lead_ms` from now.
func ring_growing(lead_ms := 0.0) -> bool:
	if not _heat_live(): return false
	var e := elapsed() + lead_ms
	for h in _stove.get("heats", []):
		if e >= float(h.at) - RING_EARLY_MS + 100.0 and e < float(h.at) - 100.0: return true
	return false

## `pot` event with queued (q(71)): the pot went in behind the one cooking. The ingredients are taken already; the
## drawer closes and the watch resumes, now saying Queued 1 with the next dish beside the pot.
func on_queued() -> void:
	if phase == "compose" and _queue_mode: rt.ui.close_modal()
	elif phase == "watch": _refresh_watch(rt.session.current())
## COOK-2a / 2b show the stove alone: the player steps out of the pushed-in shot and back when it ends.
func _hide_player(on: bool) -> void:
	if room.actor: room.actor.visible = not on

func _build_overlay() -> Control:
	var o := Control.new()
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pot_card = UiPotCard.new()
	o.add_child(_pot_card)
	o.resized.connect(_place_overlay)
	return o

## The pot card centred on the pot axis, its foot OVERLAY_GAP above the drawer.
func _place_overlay() -> void:
	if _overlay == null or drawer == null: return
	var top := _overlay.size.y - drawer.height - drawer.safe_bottom
	var card := _pot_card.get_combined_minimum_size()
	_pot_card.size = card
	_pot_card.position = Vector2((_overlay.size.x - card.x) * 0.5, top - OVERLAY_GAP - card.y)

## The pot card (256 ⑤ A'): Experiment shows the pot — filled slots with ✕, empty ones, the 3rd locked before
## Cooking Lv4 (a tap says what opens it) — and what it makes; Cookbook shows the selected page's ingredients and dish.
func _refresh_overlay() -> void:
	if _overlay == null: return
	var v := rt.session.current()
	var slots: Array = []
	var result := {title = "", rarity = 0, time = ""}
	if drawer.tab == "experiment":
		var open := P0KitchenLogic.slots(v)
		for i in maxi(open, 3):
			var s := UiPotSlot.new()
			if i < pot.size():
				s.state = UiPotSlot.State.FILLED
				s.icon = P0Logic.icon(str(pot[i]))
				s.quantity = "×2" if drawer.is_double() and drawer.big_pot_shown() else "×1"   # Double doubles each slot (b84a5e01 ③)
				s.removable = true
				s.point_at_remove = _point_at_remove
				var index := i
				s.tapped.connect(func(): _take_out(index, s.ring_center()))
			elif i < open:
				s.state = UiPotSlot.State.EMPTY
			else:
				s.state = UiPotSlot.State.LOCKED
				s.locked_tapped.connect(func(): rt.ui.toast(P0KitchenLogic.locked_slot_toast(rt.session.current())))
			slots.append(s)
		result = P0KitchenLogic.preview(v, pot)
	else:
		var page := drawer.page(drawer.selected_page)
		for ing in P0KitchenLogic.page_ingredients(v, page):
			var s := UiPotSlot.new(UiPotSlot.State.FILLED)
			# No names under the slots now (256 ⑤ A'): a family slot (W1, Any Common fish) shows its family icon,
			# as a clue does on the Cookbook cell, not the `?` of a slot nobody knows yet.
			var t := str(ing.id)
			s.icon = UiItemCell.family_icon(t[0]) if t.length() == 2 and t[1].is_valid_int() else ing.icon
			s.quantity = "×2" if drawer.is_double() and drawer.big_pot_shown() else "×1"   # Double doubles each slot (b84a5e01 ③)
			slots.append(s)
		if not page.is_empty(): result = P0KitchenLogic.page_preview(v, page)
	_pot_card.set_slots(slots)
	_pot_card.show_result(result.title, result.rarity, result.time)
	_pot_card.tag = "×2" if drawer.is_double() and drawer.big_pot_shown() else ""
	_pot_card.visible = not slots.is_empty()
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
	# §7.2.7: a tap on a bag cell always puts one more in (Carrot Cake, Salted Potatoes and the two-radish trials need
	# the same ingredient twice); taking one back is the slot bar's tap / ✕ (李元芳, int6).
	if pot.size() >= P0KitchenLogic.slots(v):
		_point_at(true)
		rt.ui.toast(POT_FULL)   # q(64): the pot card sits above the bag
		return
	if not P0KitchenLogic.can_add(v, pot, id): return
	pot.append(id)
	stage.add_ingredient(id, P0Logic.icon(id), from_screen)
	_after_pot_change()

## q(64): with the pot full a bag cell's tap points at ✕ — a gold-brown ring round each one while the toast shows.
const POT_FULL := "The pot is full · tap ✕ above to take one out"
var _point_serial := 0
func _point_at(on: bool) -> void:
	_point_serial += 1
	_point_at_remove = on
	if not is_instance_valid(_pot_card): return
	for s in _pot_card.slots(): (s as UiPotSlot).point_at_remove = on and (s as UiPotSlot).removable
	if not on: return
	get_tree().create_timer(ToastLayer.duration_ms(POT_FULL) / 1000.0).timeout.connect(_point_done.bind(_point_serial))

func _point_done(serial: int) -> void:
	if serial == _point_serial: _point_at(false)

func _take_out(index: int, to_screen: Vector2) -> void:
	if index < 0 or index >= pot.size(): return
	var id := str(pot[index])
	pot.remove_at(index)
	stage.remove_ingredient(id, to_screen)
	_after_pot_change()

func _after_pot_change() -> void:
	_point_at_remove = false   # the pot changed: the ring has done its job
	_point_serial += 1
	drawer.pot = pot
	drawer.refresh()
	_refresh_overlay()

## One Cook per opening; a refusal or a failed send gives the buttons back (see on_event).
func _on_cook(cmd: Dictionary) -> void:
	if _cook_sent: return
	_cook_sent = true
	cmd = with_stove(cmd)
	rt.session.send(cmd, P0Session.ui_key(cmd))

# ---------------------------------------------------------------- Cook All (Cooking Lv8; COOK-P1-4 / COOK-EMPTY, q(124))
## Cook All's sheet over the drawer (paused: no key opens it since 10-15, kept for 0.2.8's batch cook on the recipe card) (P0CookAllSheet from the server's preview); ×, a drag
## down, Back and `Kitchen` close it back to the Cookbook. `Cook All · N pots` sends cook_all and closes it
## at once: the reply's pots catch one stove after another, COOK_ALL_FIRE_S apart, the camera staying put, and what
## they took floats once over the pot card as one item group (`−3 Radish · −2 Pond Crucian`, two a line, q(124) ④).
## Each pot then cooks and comes out on its own stove as Queue does; no card here.
const COOK_ALL_FIRE_S := 0.15
var cook_all_pending := false   # cook_all sent: the reply's pots are Cook All's, not one Cook's watch
var cook_all_sheet: P0CookAllSheet
var _cook_all_close: UiCloseButton
var _cook_all_back := Callable()   # the kitchen's own Back while the sheet is over it
var _cook_all_pots: Array = []
var _cook_all_used := {}           # ingredient → how many this cook_all took (its negative item events)

func open_cook_all() -> void:
	if phase != "compose" or _wrap == null or is_instance_valid(cook_all_sheet): return
	var model := P0KitchenLogic.cook_all(rt.session.current())
	if model.is_empty() or str(model.button) != "": return
	cook_all_sheet = P0CookAllSheet.new(model)
	cook_all_sheet.theme = UiKit.theme()
	cook_all_sheet.safe_bottom = rt.ui.safe_bottom()
	cook_all_sheet.close_requested.connect(close_cook_all)
	cook_all_sheet.back.connect(close_cook_all)
	cook_all_sheet.unavailable.connect(func(r: String): rt.ui.toast(r))
	cook_all_sheet.confirmed.connect(_send_cook_all)
	_wrap.add_child(cook_all_sheet)
	_cook_all_close = UiCloseButton.new()   # 6 above the sheet's top-right corner, 16 in (COOK-P1-4 Close · 44 px)
	_cook_all_close.theme = UiKit.theme()
	_cook_all_close.pressed.connect(close_cook_all)
	_wrap.add_child(_cook_all_close)
	var follow := func():
		if is_instance_valid(_cook_all_close) and is_instance_valid(cook_all_sheet):
			_cook_all_close.position = cook_all_sheet.position + Vector2(cook_all_sheet.size.x - UiTokens.SPACE_PAGE - UiTokens.SIZE_CLOSE, -6.0 - UiTokens.SIZE_CLOSE)
	cook_all_sheet.item_rect_changed.connect(follow)
	follow.call()
	_cook_all_back = rt.ui._modal_back
	rt.ui._modal_back = close_cook_all   # Back and a tap outside close this sheet first

func close_cook_all() -> void:
	if is_instance_valid(cook_all_sheet): cook_all_sheet.queue_free()
	if is_instance_valid(_cook_all_close): _cook_all_close.queue_free()
	cook_all_sheet = null
	_cook_all_close = null
	if rt: rt.ui._modal_back = _cook_all_back
	_cook_all_back = Callable()

func _send_cook_all() -> void:
	if cook_all_pending: return
	cook_all_pending = true
	_cook_all_pots.clear()
	_cook_all_used.clear()
	var cmd := {"type": "cook_all"}
	rt.session.send(cmd, P0Session.ui_key(cmd))
	close_cook_all()

## A pot of the cook_all reply (P0Farmhouse.p0_event): kept for the firing once the whole reply is in.
func on_cook_all_pot(ev: Dictionary) -> void:
	if _cook_all_pots.is_empty(): _cook_all_fire.call_deferred()
	_cook_all_pots.append(ev)

func _cook_all_fire() -> void:
	cook_all_pending = false
	var pots := _cook_all_pots.duplicate()
	var used := _cook_all_used.duplicate()
	_cook_all_pots.clear()
	_cook_all_used.clear()
	var lit := 0
	for ev in pots:
		if bool(ev.get("queued", false)): continue   # waits behind its stove's pot (Stove 1 · next): nothing catches yet
		var i := int(ev.get("stove", 0))
		get_tree().create_timer(COOK_ALL_FIRE_S * lit).timeout.connect(_catch.bind(i))
		lit += 1
	var v := rt.session.current()
	var parts: Array = []
	for id in used:
		parts.append({kind = "item", key = "cook_all:" + str(id), amount = -int(used[id]), fmt = "%s " + P0Logic.item_name(v, str(id)),
			tone = UiFloatText.Tone.ITEM, icon = P0Logic.icon(str(id))})
	rt.ui.queue_floats(parts, cook_all_float_at())

## One stove's pot catches: the working stove's hearth and steam (set_cooking), another stove a puff at its pot.
func _catch(i: int) -> void:
	if not is_inside_tree(): return
	if i == stove_index:
		stage.set_cooking(true)
		return
	var mouth := room.anchor("drop_pot_%d" % (i + 1))
	if mouth: stage.puff_at(mouth)

## Where Cook All's ingredients float (q(124) ④): over the Cookbook, at the stove — just above the pot card (else the
## drawer), centred on the screen.
func cook_all_float_at() -> Vector2:
	var w := rt.ui.root.size.x if rt and rt.ui and rt.ui.root else 360.0
	var top := drawer.top_y() if drawer else 400.0
	if is_instance_valid(_pot_card) and _pot_card.is_visible_in_tree(): top = _pot_card.get_global_rect().position.y
	return Vector2(w * 0.5, top - 8.0)

## A cook names its stove when the kitchen has more than one (the server otherwise takes the first free one).
func with_stove(cmd: Dictionary) -> Dictionary:
	if P0KitchenLogic.stove_count(rt.session.current()) > 1: cmd["stove"] = stove_index
	return cmd

## The drawer redraws from the latest view while it is open (a collect or a sale changes the bag under it); the watch
## sheet follows the queue (Queued 1, Queue next ›).
func sync_view(v: Dictionary) -> void:
	if phase == "watch":
		_refresh_watch(v)
		return
	if phase != "compose" or drawer == null or drawer.view.get("seq", -1) == v.get("seq", -2): return
	drawer.view = v
	drawer.refresh()
	_refresh_overlay()

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
	# Watching the same pot again keeps the heat taps already judged (they go out at collect when the server does
	# not keep them as they come); rings that went by unwatched are misses, without a "Missed" float each.
	if stove.get("id", null) == null or stove.get("id", null) != _stove.get("id", null):
		_taps.clear()
		_judged.clear()
		_judged_turn.clear()
	_stove = stove
	_start_ms = Time.get_ticks_msec() - int(float(stove.get("elapsed", 0)))
	var heats: Array = stove.get("heats", [])
	for i in heats.size():
		if not _judged.has(i) and elapsed() > float(heats[i].at) + float(heats[i].spin):
			_judged[i] = false
			_judged_turn[i] = 1.0
	phase = "watch"
	_hide_player(true)
	stage.set_cooking(true)
	room.focus(cam_name(), {band = room.band_below_hud(BAND_TOP_WATCH), size = room.view_size() * WATCH_FOCUS_SIZE, release_on_move = false})
	if _ring == null:
		_ring = UiHeatRing.new()
		_ring.theme = UiKit.theme()
		rt.ui.root.add_child(_ring)
	_ring.visible = false
	if _queue_badge == null:
		_queue_badge = UiWorldIconButton.new()   # display only: taps on it are heat taps like the rest of the scene
		_queue_badge.theme = UiKit.theme()
		rt.ui.root.add_child(_queue_badge)
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
		_queue_next = UiNavButton.new("Queue next", true)   # COOK-QUEUE-1a 1758:103013: centred under the hint
		_queue_next.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_queue_next.pressed.connect(open_queue)
		_sheet.body.add_child(_queue_next)
		rt.ui.root.add_child(_sheet)
		_close = UiCloseButton.new()
		_close.theme = UiKit.theme()
		_close.pressed.connect(stop_watching)
		rt.ui.root.add_child(_close)
		rt.ui.set_toast_over(_close)   # a toast while watching (the turn-over, q(71)) sits above the sheet and its ×
	var dish = stove.get("dish", null)
	_sheet_header.title = P0Logic.item_name(rt.session.current(), str(dish)) if dish != null else "Unknown dish"
	_sheet_header.quantity_label = "remaining"
	_refresh_watch(rt.session.current())
	_update_sheet()

## The watch sheet's queue facts (q(71)): Cooking · Queued 1 and the next dish beside the pot while one waits;
## Queue next › only when Queue ×2 is open and nothing waits (Lv1–4 or a full queue: no button at all).
func _refresh_watch(v: Dictionary) -> void:
	if _sheet == null: return
	_sheet_header.state = P0KitchenLogic.watch_state(v, stove_index)
	_queue_next.visible = P0KitchenLogic.can_queue(v, stove_index)
	var q = P0KitchenLogic.queued(v, stove_index)
	if _queue_badge:
		_queue_badge.visible = q != null
		if q != null:
			var dish = q.get("dish", null)
			_queue_badge.icon = P0Logic.icon(str(dish)) if dish != null else UiItemCell.SILHOUETTE
func _update_sheet() -> void:
	if _sheet == null: return
	var left := maxf(0.0, float(_stove.get("ms", 0)) - elapsed())
	_sheet_header.quantity = "%d:%02d" % [int(left / 60000.0), int(left / 1000.0) % 60]
	var top := rt.ui.root.size.y - WATCH_SHEET_H - _sheet.safe_bottom
	_close.position = Vector2(rt.ui.root.size.x - UiTokens.SPACE_PAGE - UiTokens.SIZE_CLOSE, top - CLOSE_GAP - UiTokens.SIZE_CLOSE)

func _hide_sheet() -> void:
	if _sheet and rt: rt.ui.set_toast_over(null)
	if _sheet and is_instance_valid(_sheet): _sheet.queue_free()
	if _close and is_instance_valid(_close): _close.queue_free()
	_sheet = null
	_close = null
	if _queue_badge: _queue_badge.visible = false

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
	_judge_tap()
	return true

## Judges the ring whose window is open now, with its float: true when one was judged.
func _judge_tap() -> bool:
	if not _heat_live(): return false
	var e := elapsed()
	var heats: Array = _stove.get("heats", [])
	for i in heats.size():
		var h: Dictionary = heats[i]
		if _judged.has(i) or e < float(h.at) or e > float(h.at) + float(h.spin): continue
		_taps.append(roundi(e))
		var hit := P0Logic.heat_hit(h, e)
		_judged[i] = hit
		_judged_turn[i] = clampf((e - float(h.at)) / float(h.spin), 0.0, 1.0)
		# S5 (SGODOT-232): the server keeps each ring's first tap, so an automatic Keep judges it too.
		if P0KitchenLogic.cooking(rt.session.current()).has("conveniences"): rt.session.send(_with_pot({"type": "heat", "taps": [roundi(e)]}, _stove))
		if _ring:
			_ring.result = 1 if hit else 0
			_ring.mark_turn = _judged_turn[i]
		# A hit is item ink, as it always showed: gold ink is the coins' colour and would read as money; ★ says the hit
		# (不知火舞 on #158). A miss gives nothing: secondary ink.
		rt.ui.float_text(heat_float(hit, _judged.values().count(true)), float_from(_judged_turn[i]), UiFloatText.Tone.ITEM if hit else UiFloatText.Tone.MUTED)
		if hit: Input.vibrate_handheld(40)
		return true
	return false

## A judged ring's float: a hit is `Nice heat! ★`; the one that makes two (Rare and Legendary pots have two rings) is
## Perfect, and the server serves a second portion for it, so it says so: `Perfect! ★★ · Extra portion` (李白, copy
## audit A1). A miss: `Missed · still cooking`.
static func heat_float(hit: bool, hits: int) -> String:
	if not hit: return "Missed · still cooking"
	return "Perfect! ★★ · Extra portion" if hits >= 2 else "Nice heat! ★"

## S5 Queue ×2 (PR #22): heat and collect name the pot they are for, so a pot the server already kept on its own
## answers stale_pot instead of judging the next one.
static func _with_pot(cmd: Dictionary, pot: Dictionary) -> Dictionary:
	if pot.get("id", null) != null: cmd["pot"] = pot.id
	return cmd

## Where a judged ring's float rises from (不知火舞 on #131): its dot (at `turn` of the needle's round) on the upper half
## (an early tap, a ring gone round) would sit under a float rising from the centre, so that float starts at the ring's
## lower edge — its 48 px rise stops short of the centre; a dot on the lower half (a hit, usually) keeps the centre.
func float_from(turn: float) -> Vector2:
	var upper := sin(-PI * 0.5 + TAU * turn) < 0.0
	var radius := UiHeatRing.OUTER * (_ring.scale.y if _ring else 1.0)
	return _ring_center() + (Vector2(0.0, radius) if upper else Vector2.ZERO)

## Where the stove's floats rise from while the pot is watched or turns over (a first-cook XP float, 不知火舞 on 226).
func ring_center() -> Vector2: return _ring_center()

## The ring sits on the pot (COOK-3: the whole pot is the target, §7.2.4).
func _ring_center() -> Vector2:
	var mouth := room.anchor(drop_name())
	if mouth == null: return room.get_viewport().get_visible_rect().size * 0.5
	return room.cam.unproject_position(mouth.global_position)

func _process(_dt: float) -> void:
	if not _heat_live(): return
	var e := elapsed()
	var total := float(_stove.get("ms", 5000))
	var heats: Array = _stove.get("heats", [])
	var active := -1
	for i in heats.size():
		var h: Dictionary = heats[i]
		if auto_play and not _judged.has(i) and e >= float(h.at) + (float(h.gold) + float(h.width) * 0.5) * float(h.spin): _judge_tap()
		if not _judged.has(i) and e > float(h.at) + float(h.spin):
			_judged[i] = false
			_judged_turn[i] = 1.0   # the needle went round untouched: its dot where it stopped
			rt.ui.float_text("Missed · still cooking", float_from(1.0), UiFloatText.Tone.MUTED)
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
			_ring.mark_turn = float(_judged_turn.get(active, -1.0))
			_ring.position = _ring_center() - _ring.size * 0.5
	if phase != "watch": return   # the queue drawer: no sheet; a pot done meanwhile is served when the watch resumes
	if _queue_badge and _queue_badge.visible: _queue_badge.place_at(_ring_center() + QUEUE_BADGE_AT)
	_update_sheet()
	if e >= total + 250.0: serve(_taps.duplicate())

# ---------------------------------------------------------------- serve
## The dish comes out of the pot, then collect is sent once (taps: the heat taps of this watch, [] otherwise).
## from_stove: the player came back to a Ready stove (COOK-P0-9 says Collected from Stove 1).
func serve(taps: Array, from_stove := false) -> void:
	if phase == "serve" or phase == "card": return
	var v := rt.session.current()
	var st = P0KitchenLogic.stove(v, stove_index)
	# Watching: serve the pot being watched. Gone from the stove: nothing to collect here, so the watch ends instead of
	# waiting (PR #54 review). Another pot on it now: the view already shows Queue ×2's turn-over (it settles the
	# stove as the next command will), so collect the watched pot to land it now with its toast, then watch the next
	# one with its rings (q(71)); a command that kept it already answers stale_pot and the watch moves on all the same.
	if phase == "watch" and (st == null or st.get("id", null) != _stove.get("id", null)):
		if st != null and st.get("id", null) != null and float(st.get("ready_in", 1)) > 0.0:
			_rotate(taps)
			return
		stop_watching()
		on_collected()
		return
	# Queue ×2: the watched pot is done and another waits. The stove turns over: no plate, no card (q(71)).
	if phase == "watch" and P0KitchenLogic.queued(v, stove_index) != null:
		_rotate(taps)
		return
	if st == null:
		on_collected()
		return
	# Back at a Ready stove after watching part of this pot: the rings already hit still count.
	if from_stove and taps.is_empty() and st.get("id", null) != null and st.get("id", null) == _stove.get("id", null): taps = _taps.duplicate()
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

## Queue ×2 turns the stove over (q(71)): collect the watched pot with its taps, without the plate; the reply's
## `queue` event is the next pot firing (_after_kept).
func _rotate(taps: Array) -> void:
	phase = "rotate"
	_events.clear()
	_hide_ring()
	rt.session.send(_with_pot({"type": "collect", "taps": taps}, _stove), P0Session.ui_key({"type": "collect"}))

## A collect's events in order (cabinet / item / plate / dish / first / mishap): the card is built once the
## whole reply is in. Returns true when the kitchen shows the result itself (no old dish card).
func on_event(ev: Dictionary) -> bool:
	match str(ev.get("kind", "")):
		"dish":
			var known := not bool(ev.get("mystery", false)) and not bool(ev.get("none", false))
			last_page = str(ev.get("dish", "")) if known else ""
			# Kept without a card: S5 Queue ×2 kept it on its own, or the stove turned over under the watch (q(71)).
			if bool(ev.get("auto", false)) or phase == "rotate":
				# A turn-over keeps the whole reply in _events (cleared when it started): the server sends the dish before
				# its `first`, and a turn-over that falls back to the card needs both (后裔 on #108).
				if phase == "rotate": _events.append(ev)
				_after_kept.call_deferred(ev, _events + ([] if phase == "rotate" else [ev]))
				return true
			_events.append(ev)
			# Once the whole reply is in, and through the card queue: a card already open (an Energy card, a level-up
			# from elsewhere) is not dropped, and this reply's level-up waits behind COOK-4 (PR #54 review).
			if phase == "serve": (func(): rt.ui.queue_card(_show_card)).call_deferred()
			return true
		"refused", "send_failed":   # a cook or collect that did not go through (the runtime toasts why)
			match str(ev.get("cmd", {}).get("type", "")):
				"cook": _cook_sent = false
				"cook_all": cook_all_pending = false
				"collect":
					_retrying = false
					if phase == "serve": _recover()
					elif phase == "rotate":
						# stale_pot after a command kept the watched pot: the next one is on, watch it. Anything else
						# (no network, the same pot, an empty stove) recovers as a failed serve does: camera and player
						# back, no automatic resend; a tap on the stove serves or watches it again (后裔 on #104).
						var st = P0KitchenLogic.stove(rt.session.current(), stove_index)
						if st != null and st.get("id", null) != null and st.get("id", null) != _stove.get("id", null) and float(st.get("ready_in", 1)) > 0.0:
							phase = "idle"
							watch(st)
						else:
							phase = "serve"
							_recover()
			return false
		"queue":   # the waiting pot fired (Queue ×2): the kept toast names it
			_queue_ev = ev
			return false
		"cabinet", "item", "plate", "first", "mishap":
			# What a pot took: Cook All floats it once (q(124) ④); a single Cook's says nothing, as before.
			if str(ev.kind) == "item" and int(ev.get("delta", 0)) < 0 and not str(ev.id).begins_with("dish_"):
				if cook_all_pending: _cook_all_used[str(ev.id)] = int(_cook_all_used.get(str(ev.id), 0)) - int(ev.delta)
				return false
			if _retrying and str(ev.kind) in ["cabinet", "item", "plate"]:
				_retrying = false
				var r := P0KitchenLogic.routes([ev])
				var id := str(r.keys()[0]) if not r.is_empty() else _card_dish
				rt.ui.toast(str(P0KitchenLogic.keep_line(rt.session.current(), id, str(r.get(id, "bag"))).text))
				return false
			_events.append(ev)
	return false

## A collect that failed or was refused (not_ready, stale_pot, no network): the plate goes back, the camera and
## the player return, taps and Back work again; the stove shows its state and a tap serves or watches it again.
func _recover() -> void:
	on_collected()
	stage.set_cooking(P0KitchenLogic.stove(rt.session.current(), stove_index) != null)

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
	if phase != "serve":
		rt.ui.close_modal()   # left the stove before the card's turn: let the next queued card come up
		return
	_left_card = false
	var dish_ev: Dictionary = {}
	var first_xp := 0
	for ev in _events:
		if str(ev.kind) == "dish": dish_ev = ev.duplicate()
		if str(ev.kind) == "first" and str(ev.get("what", "")).begins_with("cook:"): first_xp = int(ev.xp)
		if str(ev.kind) == "mishap": dish_ev["clue"] = ev.get("clue", null)
	if dish_ev.is_empty():
		_recover()
		rt.ui.close_modal()
		return
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
	room.focus(cam_name(), {band = room.band_below_hud(BAND_TOP_WATCH), size = room.view_size() * FOCUS_SIZE, release_on_move = false})
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

## Once the whole reply is in, for a pot kept without a card. The stove turned over (a `queue` event): the toast says
## what was kept and what cooks now, and a watch moves on to the next pot with its rings (q(71)). It did not (the
## next pot had no room: cabinet and bag full, the kept pot stays on the stove, q(46)): a turn-over the player was
## watching falls back to the result card, which says so; a pot kept on its own gets the Keep line.
func _after_kept(ev: Dictionary, events: Array) -> void:
	var v := rt.session.current()
	var turned := not _queue_ev.is_empty()
	var next = _queue_ev.get("dish", null)
	_queue_ev = {}
	if not turned and phase == "rotate":
		phase = "serve"   # _events holds the whole reply by now: the dish, its first and its mishap
		_from_stove = false
		rt.ui.queue_card(_show_card)
		return
	var fresh := P0KitchenLogic.new_recipe_line(v, ev)
	if turned and fresh != "": rt.ui.toast_success(fresh)   # q(85): a new recipe, its first-cook XP floats from the pot
	elif turned: rt.ui.toast(P0KitchenLogic.rotation_line(v, ev, next))
	else:
		var line := P0KitchenLogic.kept_line(v, ev, events)
		if not line.is_empty(): rt.ui.toast(str(line.text))
	if phase in ["rotate", "watch"]:
		var st = P0KitchenLogic.stove(v, stove_index)
		if st != null and float(st.get("ready_in", 1)) > 0.0: watch(st)
		elif phase == "rotate":
			phase = "watch"
			stop_watching()

func _exit_tree() -> void:
	if _ring and is_instance_valid(_ring): _ring.queue_free()
	if _queue_badge and is_instance_valid(_queue_badge): _queue_badge.queue_free()
	_hide_sheet()
