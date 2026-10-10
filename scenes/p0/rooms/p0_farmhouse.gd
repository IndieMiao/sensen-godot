extends P0Room
## The farmhouse interior (plan §7.7 / q(14)): Homestead Lv1–4 live in the Basic Room, whose stove corner is the
## P0 kitchen; the place chip reads "San Francisco · Farmhouse" (LOCK-06 K-1). Entered from the farm (the door card's
## Kitchen row, or walking into the doorway); its door leaves back to the farm.
## Placeholder period: the accepted Basic Room art with assets/p0/rooms/farmhouse.anchors.json; the final
## farmhouse_lv1 (SGODOT-213) swaps the art and brings the anchors in its own layout.json.
## Cooking is the 3D stove stage (P0Kitchen, LOCK-20 v5): tap the stove → walk there → the cooking drawer.
## The kitchen corner grows with the Homestead (§7.7): the Spice Rack from Lv2 and the Warming Cabinet from Lv3,
## placeholder props from the anchors file until farmhouse_lv1; tapping either opens its sheet (COOK-P0-5 / 6).

const STOVE := "use_stove_1"
## Stoves 2 and 3 (Homestead Lv4 / Lv8, SGODOT-282): their own pot spots on the hearth, each tapped and named alone.
const STOVES := ["use_stove_1", "use_stove_2", "use_stove_3"]
const RACK := "use_spice_rack"
const CABINET := "use_warming_cabinet"
const CABINET_GLOW := Color("ffb87a")   # the cabinet's warm inner light (placeholder; the art brings its own)
const CABINET_GLOW_AT := Vector3(-2.13, 0.75, -1.69)   # in front of the cabinet door

var kitchen: P0Kitchen
var _sheet: P0StorageSheet
var _pending_tab := ""   # the drawer tab p0_open_kitchen walked to the stove for (see _on_facility)

func _init() -> void:
	anchors_path = "res://assets/p0/rooms/farmhouse.anchors.json"
	place_name = "Farmhouse"
	exit_to = "Farm"   # the door's world prompt: i-door + Farm (SGODOT-250)
	# The stove is its body and pot only; the shelf on the wall beside it and the cabinet under that are their own,
	# and where they overlap the smaller takes the tap (int6 C8). The final farmhouse_lv1 art renames these nodes.
	hit_nodes = {STOVE: "hearth", RACK: "spice_rack", CABINET: "warming_cabinet"}

## Stove i for a use_stove_N anchor, -1 for anything else.
static func stove_of(n: String) -> int: return STOVES.find(n)

## The stoves the view has (1 before Homestead Lv4): the others' anchors are not tappable.
func _stove_count() -> int:
	return P0KitchenLogic.stove_count(rt.session.current()) if rt else 1

func _tappable() -> PackedStringArray:
	var out := PackedStringArray()
	var n := _stove_count()
	for a in super():
		var i := stove_of(a)
		if i < 0 or i < n: out.append(a)
	return out

## The hearth's box takes the tap for every stove on it (int6 C8): with several, the pot nearest the finger wins.
func pick(screen: Vector2) -> String:
	var n := super(screen)
	if stove_of(n) < 0 or _stove_count() < 2: return n
	var best := n
	var best_d := INF
	for i in _stove_count():
		var m := anchor(STOVES[i])
		if m == null: continue
		var d := cam.unproject_position(m.global_position).distance_to(screen)
		if d < best_d:
			best_d = d
			best = STOVES[i]
	return best

## The space commands are sent from (SGODOT-228 PR #16, Rest needs ≥ 2 h away, q(41)): the farmhouse is home.
func p0_space() -> String: return "home"

## The props show from the player's Homestead level (read before the walkable grid is built).
func _dress_art() -> void:
	if use_runtime: level = int(P0Runtime.ensure().session.current().get("homestead", {}).get("level", 1))
	super()
	if art.has_node("warming_cabinet"):
		var glow := OmniLight3D.new()
		glow.name = "warming_cabinet_glow"   # a module of its own: shown with the cabinet
		glow.light_color = CABINET_GLOW
		glow.light_energy = 0.9
		glow.omni_range = 1.1
		glow.shadow_enabled = false
		glow.position = CABINET_GLOW_AT
		art.add_child(glow)
		module_levels[glow.name] = module_levels.get("warming_cabinet", 3)

func _room_ready() -> void:
	kitchen = P0Kitchen.new(self)
	add_child(kitchen)

# ---------------------------------------------------------------- stove (COOK-1)
## Finger card and STATE-ICONS badge over the stove: Empty / countdown / Ready (plan §7.2.2 step 1).
func _marker(n: String, v: Dictionary) -> Dictionary:
	if kitchen and kitchen.busy(): return {}   # the drawer or the pot owns the screen
	if _sheet: return {}
	# World prompts (SGODOT-250, LOCK-07 v2, q(62)): an icon button, the nearest opens into a name strip; no Tap to.
	if n == RACK: return {kind = "facility", icon = P0Logic.icon("spice_rack"), name = "Spice Rack"}   # i-spice-rack 1714:102645
	if n == CABINET:   # i-cabinet 1265:89122; from afar its button hangs the count, 4/6 or Full, none when empty (C21, q(31))
		return {kind = "facility", icon = P0Logic.icon("cabinet"), name = "Warming Cabinet", fact = P0KitchenLogic.cabinet_badge(v),
			count = P0KitchenLogic.cabinet_count(v)}
	var i := stove_of(n)
	if i < 0: return super(n, v)
	# i-pot (250 walkthrough). Up close the strip keeps the pot: the state is the far button's badge and the fact
	# (Cooking 0:22 / the dish), as on the bench (不知火舞 on #104, 1760:103708). One per stove: `Stove 2/3 · Empty`
	# (b84a5e01 ②), hung over its own pot.
	var stove := {kind = "facility", icon = P0Logic.icon("pot"), name = P0KitchenLogic.stove_label(v, i), strip_badge = false}
	if P0KitchenLogic.queued(v, i) != null: stove.count = "+1"   # Queue ×2: a pot waits behind this one (q(71), 1760:103578)
	var st = P0KitchenLogic.stove(v, i)
	if st == null: return stove.merged({fact = "Empty"})
	var left := float(st.get("ready_in", 0))
	if left <= 0.0:   # the ready mark takes the icon's place; the strip names the dish
		var dish = st.get("dish", null)
		return stove.merged({fact = P0Logic.item_name(v, str(dish)) if dish != null else "Unknown dish", badge = "ready"})
	return stove.merged({fact = "Cooking " + P0Logic.duration(left), badge = "countdown"})

func _on_facility(n: String) -> void:
	if stove_of(n) >= 0:
		if kitchen and not kitchen.busy(): kitchen.select_stove(stove_of(n))
		# Sent here with a tab (the rack's Open Experiment ›, the Energy card's Cook): open on it,
		# not on Cookbook or Cook Again (PR #54 review). A plain tap on the stove has none.
		var tab := _pending_tab
		_pending_tab = ""
		open_stove(tab if tab != "" else "cookbook", tab == "")
	elif n == RACK: open_sheet("rack")
	elif n == CABINET: open_sheet("cabinet")

## COOK-P0-5 / P0-6: the corner's sheet with the camera on it; commands go out, the sheet follows the view.
func open_sheet(kind: String) -> void:
	if rt == null or (kitchen and kitchen.busy()): return
	_sheet = P0StorageSheet.new(kind, rt.session.current())
	_sheet.safe_bottom = rt.ui.safe_bottom()
	_sheet.close_requested.connect(func(): rt.ui.close_modal())
	_sheet.command.connect(func(cmd: Dictionary):
		if cmd.has("_toast"): rt.ui.toast(str(cmd._toast))
		else: rt.session.send(cmd, P0Session.ui_key(cmd)))
	_sheet.open_experiment.connect(func():
		rt.ui.close_modal()
		p0_open_kitchen("experiment"))
	_sheet.details.connect(func(): rt.ui.toast("Spice Rack · seasonings off your bag · Homestead Lv2"))
	rt.ui._open_modal(_sheet, 0.0, true)
	rt.ui.modal_kind = "storage"
	_sheet.tree_exited.connect(func():
		_sheet = null
		release_focus()
		if actor: actor.visible = true)
	if actor: actor.visible = false
	var h := P0StorageSheet.RACK_H if kind == "rack" else P0StorageSheet.CABINET_H
	focus("cam_kitchen_corner", {band = band_below_hud(1.0 - h / 800.0 - 0.02), size = view_size() * 0.38, release_on_move = false})

## Empty → the cooking drawer; cooking → watch the pot; ready → the dish comes out and COOK-P0-9 asks Eat or Keep
## (unwatched rings are misses: Plain); portions left on the stove (no room earlier) → the same card for them.
## A tap on the free stove after a known pot offers Cook Again first (COOK-P0-7, Cooking Lv2; An Qi La on 226).
func open_stove(tab := "cookbook", tapped := false) -> void:
	if rt == null or kitchen == null or kitchen.busy(): return
	var v := rt.session.current()
	var st = P0KitchenLogic.stove(v, kitchen.stove_index)
	var left := P0KitchenLogic.stove_left(v, kitchen.stove_index)
	# Sent from a Today cook row (q(99)): the drawer opens on that page, not on Cook Again's last one.
	if st == null and tapped and kitchen.last_page != "" and P0KitchenLogic.cook_again_on(v) and rt.ui.cook_page_from_today == "":
		kitchen.open_again(kitchen.last_page)
	elif st == null: kitchen.open(tab)
	elif not left.is_empty(): kitchen.show_left(str(left[0]))
	elif float(st.get("ready_in", 0)) <= 0.0: kitchen.serve([], true)
	else: kitchen.watch(st)

## The cooking drawer from elsewhere (the Energy card's Cook tile, dev steps): walk to the stove first. Arriving
## runs _on_facility, which opens the drawer on this tab; any other tap or the stick drops it.
func p0_open_kitchen(tab := "cookbook") -> void:
	_pending_tab = tab if tab != "" else "cookbook"
	walk_to(STOVES[P0KitchenLogic.free_stove(rt.session.current()) if rt else 0])   # the first free stove (§7.2.3)

## Returns true when the kitchen shows the result itself (the runtime then skips its old dish card).
## Floats rise over the plate while the pot's result is on screen (COOK-4: the XP chip above the plate), else over
## the player as in any room.
func p0_anchor() -> Vector2:
	if kitchen and kitchen.phase in ["serve", "card"]: return get_viewport().get_visible_rect().size * Vector2(0.5, P0Kitchen.FLOAT_AT)
	if kitchen and kitchen.phase in ["rotate", "watch"]: return kitchen.ring_center()   # the turn-over's floats rise from the pot
	return super()

## Whether this reply's result card is coming: its strip carries the first-cook XP, so the runtime keeps that bonus off
## the floats. A normal serve, or a turn-over whose next pot did not fire (no `queue` event: no room, q(46)) and so
## falls back to the card (后裔 on #108). A turn-over or a pot kept on its own has no card: the bonus floats (q(85)).
func p0_cook_card_coming(events: Array) -> bool:
	if kitchen == null: return false
	if kitchen.phase == "serve": return true
	return kitchen.phase == "rotate" and not events.any(func(e): return str(e.get("kind", "")) == "queue")

func p0_event(ev: Dictionary, v: Dictionary) -> bool:
	if kitchen == null: return false
	match str(ev.get("kind", "")):
		"pot":
			if ev.has("stove") and not kitchen.busy(): kitchen.select_stove(int(ev.stove))
			var st = P0KitchenLogic.stove(v, kitchen.stove_index)
			if bool(ev.get("queued", false)): kitchen.on_queued()   # Queue ×2: in behind the pot cooking (q(71))
			elif st is Dictionary: kitchen.on_pot(st)
			return false
	return kitchen.on_event(ev)

func _room_frame(v: Dictionary, _dt: float) -> void:
	if _sheet and rt and rt.session.view.get("seq", -1) != _sheet.view.get("seq", -2): _sheet.refresh(rt.session.current())
	if kitchen == null: return
	kitchen.sync_view(v)
	var st = P0KitchenLogic.stove(v, kitchen.stove_index)
	var cooking: bool = st != null and float(st.get("ready_in", 0)) > 0.0
	if kitchen.phase == "idle" and kitchen.stage.is_cooking() != cooking: kitchen.stage.set_cooking(cooking)
	if kitchen.phase == "serve" and st == null and kitchen.waiting_events(): kitchen.on_collected()   # refused as empty

func p0_tap(screen: Vector2) -> void:
	if kitchen and kitchen.tap(): return
	_pending_tab = ""   # a new target: whatever sent us to the stove with a tab no longer applies
	super(screen)

## Walking away from the pot stops watching it; the pot keeps cooking (§7.2.3).
func _on_joystick(v: Vector2) -> void:
	if v != Vector2.ZERO: _pending_tab = ""
	if v != Vector2.ZERO and kitchen and kitchen.phase == "watch": kitchen.stop_watching()

## Back while watching the pot steps back from it; then the room's own Back (drawer, then the door).
func is_back_navigation_locked() -> bool:
	if kitchen and kitchen.phase == "watch":
		kitchen.stop_watching()
		return true
	if kitchen and kitchen.phase == "serve": return true
	return super()   # the result card is a modal: the base closes it, which keeps the dish

func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"stove": open_stove(step[1] if step.size() > 1 else "cookbook")
		"stoveat":   # stoveat:<i> — a tap on stove i (0-based): walk there and open it (SGODOT-282 shots)
			_pending_tab = ""
			walk_to(STOVES[int(step[1])])
		"cyclestove": if kitchen.drawer: kitchen.drawer.stove_cycle_requested.emit()   # the drawer's Stove n/N › pill
		"kitchen": p0_open_kitchen(step[1] if step.size() > 1 else "cookbook")
		"queue": kitchen.open_queue()   # Queue next › on the watch sheet (shots)
		"heattap": kitchen.dev_heat_tap()   # a heat tap now: until:gold first (shots)
		"heatband": kitchen.dev_band_press()   # a press on the queue drawer's pot band (shots)
		"page":   # a Cookbook page picked, as a tap on its cell (its card, ghosts and pot card; shots)
			if kitchen.drawer:
				kitchen.drawer.select_page(step[1])
				kitchen._on_page(kitchen.drawer.page(step[1]))
		"slottap": kitchen.dev_slot_tap(int(step[1]))   # a tap on the pot card's slot i (shots)
		"again": kitchen.open_again(step[1])   # Cook Again on a page, as after a pot of it (shots)
		"againlock":   # a tap on the Cook Again sheet's locked slot (shots)
			for sl in rt.ui.root.find_children("*", "Control", true, false):
				if sl is UiPotSlot and (sl as UiPotSlot).state == UiPotSlot.State.LOCKED: (sl as UiPotSlot).locked_tapped.emit()
		"rects": print("P0_KITCHEN_RECTS ", JSON.stringify(kitchen.dev_rects().merged({hud = HUD_BOTTOM, view = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]})))   # shots
		"put":
			if kitchen.phase != "compose": kitchen.open("experiment")
			if kitchen.drawer and kitchen.drawer.tab != "experiment": kitchen.drawer.tab = "experiment"
			kitchen._on_ingredient(step[1], Vector2.INF)
		"keep": if kitchen.phase == "card": rt.ui.close_modal()
		"rack": open_sheet("rack")
		"cabinet": open_sheet("cabinet")
		"level":
			level = int(step[1])
			refresh_modules()
		"eat": if kitchen.phase == "card": kitchen.press_eat()
		_: return super(step)
	return true

func p0_until(n: String) -> bool:
	match n:
		"cooking": return kitchen != null and kitchen.phase == "watch"
		"turned": return kitchen != null and kitchen.phase == "watch" and P0KitchenLogic.queued(rt.session.current(), kitchen.stove_index) == null   # Queue ×2 turned over
		"card": return kitchen != null and kitchen.phase == "card"
		"floating": return rt != null and not rt.ui.root.find_children("*", "UiFloatText", true, false).is_empty()   # a float is up (shots)
		"compose": return kitchen != null and kitchen.phase == "compose"
		"gold": return kitchen != null and kitchen.at_gold()   # a ring's needle on gold (shots)
		"goldsoon": return kitchen != null and kitchen.at_gold(800.0)   # on gold when the next step runs (0.8 s on)
		"earlysoon": return kitchen != null and kitchen.ring_at(800.0, 0.1, 0.2)   # in its window before gold (an early tap)
		"tailsoon": return kitchen != null and kitchen.ring_at(400.0, 1.03, 1.15)   # just turned, still showing, at the shot
		"growsoon": return kitchen != null and kitchen.ring_growing(800.0)   # a ring growing when the next step runs
		"idle": return (kitchen == null or not kitchen.busy()) and super(n)
	return super(n)
