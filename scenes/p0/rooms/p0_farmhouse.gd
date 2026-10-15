extends P0Room
## The farmhouse interior (plan §7.7 / §8.3.1, q(14)): Homestead Lv1–4 live in the Basic Room, whose stove corner is the
## P0 kitchen, Lv5–9 in the Standard Room and Lv10 in the Deluxe Room (ROOMS); the place chip reads
## "San Francisco · Farmhouse" (LOCK-06 K-1). Entered from the farm (the door card's Kitchen row, or walking into the
## doorway); its door leaves back to the farm.
## The Basic Room's kitchen is SGODOT-213's three-burner range (kitchen_range_3), Spice Rack and cookbook, with
## assets/p0/rooms/farmhouse.anchors.json; each stove has its pot (SGODOT-282 stove_pot.glb).
## Cooking is the 3D stove stage (P0Kitchen, LOCK-20 v5): tap the stove → walk there → the cooking drawer.
## The kitchen corner grows with the Homestead (§7.7): the Spice Rack from Lv2 and the Warming Cabinet from Lv3,
## the Basic Room's rack in its layout, the cabinet a model from the anchors file; tapping either opens its sheet (COOK-P0-5 / 6).

const STOVE := "use_stove_1"
## Stoves 2 and 3 (Homestead Lv4 / Lv8, SGODOT-282): their own burners on the range, each tapped and named alone.
const STOVES := ["use_stove_1", "use_stove_2", "use_stove_3"]
const RACK := "use_spice_rack"
const CABINET := "use_warming_cabinet"
const CABINET_GLOW := Color("ffb87a")   # the cabinet's warm inner light (the model has no lamp of its own)
## The room by Homestead level (§8.3.1, q(14); content homestead.rooms [[1, basic], [5, standard], [10, deluxe]]), only ever
## up. Each kit's kitchen corner keeps the P0 names — stoves 1–3 on its cooker, the Spice Rack, the Warming Cabinet — so the
## kitchen, the stage and the sheets work the same in all three; `hits` is hit_nodes (the art that takes each one's tap).
## Basic: the three burners of kitchen_range_3 (SGODOT-213), 1 / 2 / 3 left to right. Standard (282 c62a6ed9 ②; 上官婉儿 on 282): the stoves on the range
## cooker's burners (1 front left, 2 front right, 3 back right), the Spice Rack is the shelf over the sink, the Warming
## Cabinet the Basic Room's placeholder on the west wall facing the camera, as there. Deluxe: its layout.json's kitchen hooks (the range cooker, the
## fittings along the west wall), the file adding badges, stands and shots; the rack and cabinet are inside the one
## kitchen_fittings model, so they take taps round their anchors.
const ROOMS := {
	"basic": {art = "basic_room", anchors = "res://assets/p0/rooms/farmhouse.anchors.json",
		hits = {STOVE: "kitchen_range_3", RACK: "spice_rack", CABINET: "warming_cabinet"}},
	"standard": {art = "standard_room_5", anchors = "res://assets/p0/rooms/farmhouse_standard.anchors.json",
		hits = {STOVE: "range_cooker", RACK: "wall_shelf", CABINET: "warming_cabinet"}},
	"deluxe": {art = "deluxe_room_10", anchors = "res://assets/p0/rooms/farmhouse_deluxe.anchors.json",
		hits = {STOVE: "range_cooker"}},
}
var room_kind := "basic"
const SCENE := "res://scenes/p0/rooms/p0_farmhouse.tscn"
## Upgraded inside (HOME-1 from Profile's farm card is at home here too) to a level with the next room: once the
## level-up's banner and look cards are gone and the stove is idle, the farmhouse opens again in its new room behind the
## loading cover, the player at its door. Once the router takes it (true); while it is busy, the next frame tries again
## (刘邦 on #380). Tests swap the call.
var reopen := func() -> bool:
	if not AppRouter.can_replace(self): return false
	AppRouter.replace_top_instance(self, SCENE, {})
	return true
var _reopening := false

var kitchen: P0Kitchen
## Heat reminders already given (pot id → ring index): once per ring (b84a5e01 ④).
var _reminded := {}
var _edge: Control   # the stage's edge arrow toward the stove whose ring is coming (camera on another pot)
const REMIND_MS := 1000.0   # the reminder comes a second before another stove's ring
const BUZZ_MS := 30
var _sheet: P0StorageSheet
var _pending_tab := ""   # the drawer tab p0_open_kitchen walked to the stove for (see _on_facility)

func _init() -> void:
	anchors_path = "res://assets/p0/rooms/farmhouse.anchors.json"
	place_name = "Farmhouse"
	exit_to = "Farm"   # the door's world prompt: i-door + Farm (SGODOT-250)
	# The stove is the range only; the rack on the wall beside it and the cabinet under that are their own, and where
	# they overlap the smaller takes the tap (int6 C8).
	hit_nodes = (ROOMS.basic.hits as Dictionary).duplicate()

## The room for a Homestead level: the last of content homestead.rooms it has reached ("basic" below them all).
static func room_for(lv: int) -> String:
	var kind := "basic"
	for r in P0Logic.content().get("homestead", {}).get("rooms", []):
		if lv >= int(r[0]) and ROOMS.has(str(r[1])): kind = str(r[1])
	return kind

## The room is chosen before the art is built: by the player's Homestead level (tests and previews set `level`).
func _ready() -> void:
	if use_runtime: level = int(P0Runtime.ensure().session.current().get("homestead", {}).get("level", 1))
	use_room(room_for(level))
	super()

func use_room(kind: String) -> void:
	room_kind = kind
	var r: Dictionary = ROOMS[kind]
	anchors_path = str(r.anchors)
	hit_nodes = (r.hits as Dictionary).duplicate()
	use_art(str(r.art))

## The room the view's Homestead level has (room_for) against the one built: reopen into it once nothing is up — no
## card, banner or sheet, none queued, the stove idle.
func check_room(v: Dictionary) -> void:
	if _reopening or rt == null or not v.has("homestead"): return
	if room_for(int(v.homestead.get("level", level))) == room_kind: return
	if rt.ui.has_modal() or not rt.ui._card_queue.is_empty() or (kitchen != null and kitchen.busy()): return
	_reopening = bool(reopen.call())

## The fire that burns brighter while a pot cooks: the Basic Room's, under stove 1 on its range (fire_1, with the room's
## one lamp); the Standard and Deluxe stoves are range cookers across the room from their fireplaces, so theirs stays as it is.
func stove_fire() -> Node:
	return art.get("fire") as Node if room_kind == "basic" and "fire" in art else null

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

## The stoves share one place to stand, and stove 3 sits behind 1 and 2, so the nearest pot would always be the same
## one: by the hearth the strip that opens is the stove being worked (the last tapped, or the drawer's Stove n/N), one
## at a time (LOCK-07 v2). Away from the hearth the room's own pick applies.
func card_pick(marks: Dictionary) -> String:
	var n := super(marks)
	if kitchen == null or stove_of(n) < 0: return n
	var mine: String = STOVES[kitchen.stove_index]
	if marks.has(mine):
		_card = mine
		return mine
	return n

## 不知火舞 02ad95bc ① / 6e798a27 ②: stove buttons closer than 44 px (centre to centre) overlap, and an open strip covers
## the others. Folded, they go in one row above the hearth, 1 / 2 / 3 left to right, 44 apart, kept 44 from the Spice Rack
## and Warming Cabinet buttons; with a strip open it stays at its own pot and the other stoves' buttons line up above it.
const STOVE_ROW_GAP := 44.0
func _marker_spots(spots: Dictionary) -> Dictionary:
	# only the stoves on screen: the row is kept on screen, and would pull off-screen ones to its edge with no stove there
	# (the Deluxe Room's door is far from its cooker)
	var screen := get_viewport().get_visible_rect()
	var shown: Array = []
	for i in STOVES.size(): if spots.has(STOVES[i]) and screen.has_point(spots[STOVES[i]]): shown.append(i)
	if shown.size() < 2: return spots
	var open := STOVES.find(_card) if stove_of(_card) >= 0 else -1
	var strip := _strip_rect if open >= 0 and shown.has(open) else Rect2()
	var crowded := false
	for a in shown.size():
		for b in range(a + 1, shown.size()):
			if (spots[STOVES[shown[a]]] as Vector2).distance_to(spots[STOVES[shown[b]]]) < STOVE_ROW_GAP: crowded = true
	for i in shown:   # an open strip over another stove's button
		if i != open and strip.has_area() and strip.grow(STOVE_BUTTON * 0.5).has_point(spots[STOVES[i]]): crowded = true
	if not crowded: return spots
	var avoid: Array = []
	for n in [RACK, CABINET]: if spots.has(n): avoid.append(spots[n])
	return stove_row(spots, shown, open, strip, get_viewport().get_visible_rect().size.x, avoid)

var _strip_rect := Rect2()   # the open stove strip on screen last frame (the other stoves line up above it)

## The row (pure, tested). Folded: 1 / 2 / 3 left to right, 44 apart, centred on the stoves' mean x at their highest
## y, kept on screen, then moved right as a whole until every button is 44 or more from each `avoid` spot (the Spice
## Rack and Warming Cabinet buttons). With stove `open`'s strip showing (`strip`, its rect last frame): that stove keeps
## its own spot, and the others, in order, are centred over the strip, 44 apart, 6 px above its top edge, moved the
## shorter way, left or right, to keep 44 from those buttons too (before the strip has a rect, its first frame, the open
## stove still keeps its spot and the rest take their folded places).
const ROW_MARGIN := 22.0
const ABOVE_STRIP := 6.0
const STOVE_BUTTON := 28.0   # UiWorldIconButton's disc
static func stove_row(spots: Dictionary, shown: Array, open: int, strip: Rect2, screen_w: float, avoid := []) -> Dictionary:
	var out := spots.duplicate()
	var row: Array = shown.filter(func(i): return i != open) if open >= 0 and strip.has_area() else shown.duplicate()
	var cx := 0.0
	var y := INF
	if row.size() < shown.size():
		cx = strip.get_center().x
		y = strip.position.y - ABOVE_STRIP - STOVE_BUTTON * 0.5
	else:
		for i in row:
			cx += (spots[STOVES[i]] as Vector2).x
			y = minf(y, (spots[STOVES[i]] as Vector2).y)
		cx /= float(row.size())
	var xs: Array = []
	for k in row.size(): xs.append(cx + (float(k) - float(row.size() - 1) * 0.5) * STOVE_ROW_GAP)
	var shift := 0.0
	if xs.min() < ROW_MARGIN: shift = ROW_MARGIN - xs.min()
	elif xs.max() > screen_w - ROW_MARGIN: shift = screen_w - ROW_MARGIN - xs.max()
	if row.size() == shown.size():   # right, as a whole, past whichever of the rack / cabinet a button is too close to
		shift += _clear_of(xs, shift, y, avoid, 1.0)
	elif not avoid.is_empty():   # over an open strip too (the Standard Room's shelf sits beside its cooker, 282): the shorter way
		var right := _clear_of(xs, shift, y, avoid, 1.0)
		var left := _clear_of(xs, shift, y, avoid, -1.0)
		shift += -left if left < right and float(xs.min()) + shift - left >= ROW_MARGIN else right
	for k in row.size(): out[STOVES[row[k]]] = Vector2(xs[k] + shift, y)
	if shown.has(open): out[STOVES[open]] = spots[STOVES[open]]   # the open strip never moves (its first frame too)
	return out

## How far the row at `xs` + `shift` must move (dir 1 right, −1 left) for every button to be 44 or more from each `avoid` spot.
static func _clear_of(xs: Array, shift: float, y: float, avoid: Array, dir: float) -> float:
	var extra := 0.0
	for _pass in 8:
		var more := 0.0
		for x in xs:
			var at := float(x) + shift + extra * dir
			for a in avoid:
				var dy := absf(y - (a as Vector2).y)
				if dy >= STOVE_ROW_GAP or Vector2(at, y).distance_to(a) >= STOVE_ROW_GAP - 0.01: continue
				var reach := sqrt(STOVE_ROW_GAP * STOVE_ROW_GAP - dy * dy)
				more = maxf(more, ((a as Vector2).x + reach - at) if dir > 0.0 else (at - ((a as Vector2).x - reach)))
		if more <= 0.0: break
		extra += more
	return extra

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
	var view := P0Runtime.ensure().session.current() if use_runtime else {}
	if use_runtime: level = int(view.get("homestead", {}).get("level", 1))
	super()
	# the light at the model's `glow` socket, inside the cabinet behind its open front (SGODOT-282 warming_cabinet.glb)
	var socket := art.get_node("warming_cabinet").find_child("glow", true, false) as Node3D if art.has_node("warming_cabinet") else null
	if socket:
		var glow := OmniLight3D.new()
		glow.name = "warming_cabinet_glow"   # a module of its own: shown with the cabinet
		glow.light_color = CABINET_GLOW
		glow.light_energy = 0.9
		glow.omni_range = 1.1
		glow.shadow_enabled = false
		var t := Transform3D()   # the socket in the art's frame, wherever the room stands the cabinet (in the tree or not)
		var n: Node = socket
		while n != art:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		glow.position = t.origin
		art.add_child(glow)
		module_levels[glow.name] = module_levels.get("warming_cabinet", 3)
	if use_runtime: show_cabinet_plates(P0KitchenLogic.cabinet_plates(view))   # before the first frame: no flash of six (刘邦 on #431)
	_build_pots()

## The Warming Cabinet shows dish_1 … dish_N for the N dishes it holds (q(202)): at once, no animation; its warm light
## stays on, empty or not.
var _plates := -1
func show_cabinet_plates(n: int) -> void:
	if n == _plates or not art.has_node("warming_cabinet"): return
	_plates = n
	var cab := art.get_node("warming_cabinet")
	for i in range(1, P0KitchenLogic.CABINET_PLATES + 1):
		var dish := cab.find_child("dish_%d" % i, true, false) as Node3D
		if dish: dish.visible = i <= n

func _room_ready() -> void:
	kitchen = P0Kitchen.new(self)
	add_child(kitchen)
	show_pots.call_deferred()

## Each stove's pot (SGODOT-282 stove_pot.glb, its manifest's placements): pot_normal, or pot_big while the stove is
## switched to the Big Pot (q(201) ⑦); only the stoves the view has (Homestead Lv4 / Lv8). The stove's drop_pot anchor
## follows the shown pot's mouth, so the ingredient cards, the steam and the plate sit on that pot. In the Basic Room the
## range's iron lids close the burners not yet open (lid_2 / lid_3) and those burners light (fire_2 / fire_3) when they open.
const POT_SCENE := "res://assets/props/stove_pot/stove_pot.glb"
const POT_MANIFEST := "res://assets/props/stove_pot/manifest.json"
const POT_ROOMS := {"basic": "basic_room", "standard": "standard_room_5", "deluxe": "deluxe_room_10"}
const RANGE := "kitchen_range_3"
var _pots: Node3D        # art/stove_pots: stove_pot_1 … _3
var _fires: Array = []   # the Basic Room's fire_2 / fire_3 flames ([] elsewhere)
var _pots_key := ""

## The pots and the Basic Room's extra flames, all hidden until show_pots.
func _build_pots() -> void:
	var place: Dictionary = P0RoomAnchors.read_json(POT_MANIFEST).get("placements", {}).get(POT_ROOMS.get(room_kind, ""), {})
	if place.is_empty() or not ResourceLoader.exists(POT_SCENE): return
	_pots = Node3D.new()
	_pots.name = "stove_pots"
	art.add_child(_pots)
	var scene := load(POT_SCENE) as PackedScene
	var yaws: Array = place.get("yaw_degrees", [])
	for i in (place.xz as Array).size():
		var pot := scene.instantiate() as Node3D
		pot.name = "stove_pot_%d" % (i + 1)
		pot.position = Vector3(float(place.xz[i][0]), float(place.y), float(place.xz[i][1]))
		pot.rotation.y = deg_to_rad(float(yaws[i]) if i < yaws.size() else 0.0)
		pot.visible = false
		_pots.add_child(pot)
	var cooker := art.get_node_or_null(RANGE)
	if cooker == null or not art.has_node("fire"): return
	var flames := Node3D.new()   # a holder: the art's own children take module visibility, these follow the stoves
	flames.name = "stove_fires"
	art.add_child(flames)
	for k in [2, 3]:   # the same flame as stove 1's (basic_room_art), without a lamp of its own: the room keeps one
		var at := cooker.find_child("fire_%d" % k, true, false) as Node3D
		if at == null: continue
		var fire := preload("res://assets/rooms/_shared/fx/fx_hearth_fire.tscn").instantiate()
		fire.name = "fire_%d" % k
		fire.emission_box = Vector3(.18, .005, .035)
		fire.flame_height = .42
		fire.flame_count = 16
		fire.spark_count = 4
		fire.light_energy = 0.0
		fire.position = _in_art(at)
		fire.visible = false
		flames.add_child(fire)
		var lamp = fire.get("light")
		if lamp is Node and (lamp as Node).get_parent() == fire:
			(lamp as Node).free()
			fire.set("light", null)
		_fires.append(fire)

## A node's position in the art's frame, in the tree or not.
func _in_art(n: Node3D) -> Vector3:
	var t := Transform3D()
	var at: Node = n
	while at != null and at != art:
		t = (at as Node3D).transform * t
		at = at.get_parent()
	return t.origin

func show_pots() -> void:
	if _pots == null or kitchen == null or _pots_key == "review": return
	var v := P0Runtime.ensure().session.current() if use_runtime else (rt.session.current() if rt else {})
	var n := _stove_count()
	var big: Array = kitchen.big() if P0KitchenLogic.big_pot(v) else []
	var key := "%d:%s" % [n, big]
	if key == _pots_key: return
	_pots_key = key
	_apply_pots(n, big)

## n stoves' pots shown, `big` the stoves on the Big Pot.
func _apply_pots(n: int, big: Array) -> void:
	for i in _pots.get_child_count():
		var pot := _pots.get_child(i) as Node3D
		pot.visible = i < n
		var variant := "pot_big" if big.has(i) else "pot_normal"
		(pot.get_node("pot_big") as Node3D).visible = variant == "pot_big"
		(pot.get_node("pot_normal") as Node3D).visible = variant == "pot_normal"
		var drop := anchor("drop_pot_%d" % (i + 1))
		var mouth := pot.get_node_or_null(variant + "/mouth") as Node3D
		if drop and mouth: drop.position = art.transform * _in_art(mouth)   # Anchors sits beside the art under Room
	var cooker := art.get_node_or_null(RANGE)
	if cooker:
		for k in [2, 3]:
			var lid := cooker.find_child("lid_%d" % k, true, false) as Node3D
			if lid: lid.visible = n < k
	for f in _fires: (f as Node3D).visible = int(str(f.name).trim_prefix("fire_")) <= n

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
	return stove_marker(v, i, kitchen != null and kitchen.big().has(i))

## One stove's world prompt (pure, tested): i-pot (250 walkthrough). Up close the strip keeps the pot: the state is the
## far button's badge and the fact (Cooking 0:22 / the dish), as on the bench (不知火舞 on #104, 1760:103708); Ready and
## Cooking put their badge in the strip too (02ad95bc ③; on #231: the clock folded and open), Empty keeps the pot. One per
## stove: `Stove 2/3 · Empty` (b84a5e01 ②), over its pot; an empty Big Pot stove `Stove 2/3 · Big Pot` (q(201): cooking or
## ready first, then Big Pot, then Empty).
static func stove_marker(v: Dictionary, i: int, big := false) -> Dictionary:
	var stove := {kind = "facility", icon = P0Logic.icon("pot"), name = P0KitchenLogic.stove_label(v, i), strip_badge = false}
	if P0KitchenLogic.queued(v, i) != null: stove.count = "+1"   # Queue ×2: a pot waits behind this one (q(71), 1760:103578)
	var st = P0KitchenLogic.stove(v, i)
	if st == null: return stove.merged({fact = "Big Pot" if big and P0KitchenLogic.big_pot(v) else "Empty"})
	var left := float(st.get("ready_in", 0))
	if left <= 0.0:   # the ready mark takes the icon's place; the strip names the dish
		var dish = st.get("dish", null)
		# Ready to collect: the strip shows the Ready StatusBadge (22) in the pot's place (LOCK-07 v2, 不知火舞 02ad95bc ③).
		return stove.merged({fact = P0Logic.item_name(v, str(dish)) if dish != null else "Unknown dish", badge = "ready", strip_badge = true}, true)
	# Cooking: the strip keeps the clock badge its button had, so folded and open read the same (不知火舞 on #231).
	return stove.merged({fact = "Cooking " + P0Logic.duration(left), badge = "countdown", strip_badge = true}, true)

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
	# the shot on its own corner (the Standard Room's rack and cabinet stand apart), else the shared one
	var shot := "cam_spice_rack" if kind == "rack" else "cam_warming_cabinet"
	focus(shot if anchor(shot) else "cam_kitchen_corner", {band = band_below_hud(1.0 - h / 800.0 - 0.02), size = view_size() * 0.38, release_on_move = false})

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
			if kitchen.batch_pending:   # a batch's pots catch one after another (q(200), Cook All's way)
				kitchen.on_batch_pot(ev)
				return false
			if ev.has("stove") and not kitchen.busy(): kitchen.select_stove(int(ev.stove))
			var st = P0KitchenLogic.stove(v, kitchen.stove_index)
			if bool(ev.get("queued", false)): kitchen.on_queued()   # Queue ×2: in behind the pot cooking (q(71))
			elif st is Dictionary: kitchen.on_pot(st)
			return false
	return kitchen.on_event(ev)

func _room_frame(v: Dictionary, _dt: float) -> void:
	if _sheet and rt and rt.session.view.get("seq", -1) != _sheet.view.get("seq", -2): _sheet.refresh(rt.session.current())
	check_room(v)
	show_cabinet_plates(P0KitchenLogic.cabinet_plates(v))
	if kitchen == null: return
	show_pots()   # a stove opened (Lv4 / Lv8) or switched to the Big Pot
	kitchen.sync_view(v)
	var st = P0KitchenLogic.stove(v, kitchen.stove_index)
	var cooking: bool = st != null and float(st.get("ready_in", 0)) > 0.0
	if kitchen.phase == "idle" and kitchen.stage.is_cooking() != cooking: kitchen.stage.set_cooking(cooking)
	if kitchen.phase == "serve" and st == null and kitchen.waiting_events(): kitchen.on_collected()   # refused as empty
	_remind_heat(v)
	_strip_rect = Rect2()
	if rt and stove_of(_card) >= 0:   # the open strip on screen, for the row's next layout (①)
		var bar = rt.ui._name_bars.get("room:" + _card)
		if bar != null and (bar as Control).visible:
			_strip_rect = (bar as UiWorldNameBar).full_rect()

## Several stoves (b84a5e01 ④): a second before a ring comes up on a stove the player is not working, that stove's
## prompt grows 1.15× and back and the phone buzzes once; with the camera pushed in on another pot an arrow with an
## i-pot shows at the stage's edge toward it, a tap switching there. The ring itself is judged only on its own pot.
func _remind_heat(v: Dictionary) -> void:
	var n := P0KitchenLogic.stove_count(v)
	if n < 2: return
	for i in n:
		if i == kitchen.stove_index and kitchen.phase in ["watch", "compose"]: continue
		var st = P0KitchenLogic.stove(v, i)
		if st == null: continue
		var k := P0KitchenLogic.ring_soon(st, REMIND_MS)
		if k < 0: continue
		var key := "%s:%d" % [str(st.get("id", i)), k]
		if _reminded.has(key): continue
		_reminded[key] = true
		if OS.get_environment("P0_SHOT") != "": print("P0_HEAT_REMIND stove=", i, " ring=", k, " focused=", is_focused())
		if rt: rt.ui.pulse_marker("room:" + STOVES[i])
		if OS.has_feature("mobile"): Input.vibrate_handheld(BUZZ_MS)
		if is_focused(): _show_edge(i)

func _show_edge(i: int) -> void:
	var from := anchor(STOVES[kitchen.stove_index])
	var to := anchor(STOVES[i])
	if from == null or to == null or rt == null: return
	var left := cam.unproject_position(to.global_position).x < cam.unproject_position(from.global_position).x
	if _edge and is_instance_valid(_edge): _edge.queue_free()
	var y := cam.unproject_position(to.global_position).y   # at that stove's height on screen (不知火舞 02ad95bc ⑤)
	_edge = _EdgeHint.new(left, P0Logic.icon("pot"), y)
	_edge.theme = UiKit.theme()
	rt.ui.root.add_child(_edge)
	rt.ui.root.move_child(_edge, -1)   # over the watch sheet and the heat ring
	(_edge as _EdgeHint).tapped.connect(func(): _switch_to(i))

## A tap on the edge arrow: that stove, the way its own prompt opens it.
func _switch_to(i: int) -> void:
	if kitchen.phase == "watch": kitchen.stop_watching()
	if kitchen.phase == "compose": rt.ui.close_modal()
	_pending_tab = ""
	kitchen.select_stove(i)
	open_stove("cookbook", true)

class _EdgeHint extends Control:
	## 不知火舞 02ad95bc ⑤: a 36 px solid round button (1 px edge, the world icon button's shadow) with the i-pot and a
	## chevron toward that stove, 8 px in from the stage's edge, at the stove's height; it pulses once, then fades.
	signal tapped
	const SIZE := 36.0
	const INSET := 8.0
	var _left := false
	var _y := 0.0
	func _init(left: bool, icon: Texture2D, y: float) -> void:
		_left = left
		_y = y
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b := Panel.new()
		b.name = "EdgeButton"
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.size = Vector2(SIZE, SIZE)
		b.pivot_offset = b.size * 0.5
		var box := UiStyleBox.make(UiTokens.COLOR_SURFACE, SIZE * 0.5, UiTokens.COLOR_BORDER, UiTokens.STROKE_DEFAULT)
		box.shadow_color = UiTokens.COLOR_SHADOW_FLOAT
		box.shadow_size = UiTokens.SIZE_SHADOW_FLOAT_RADIUS
		box.shadow_offset = Vector2(0, UiTokens.SIZE_SHADOW_FLOAT_OFFSET_Y)
		b.add_theme_stylebox_override(&"panel", box)
		var ic := UiKit.icon(icon, 18.0)
		ic.position = Vector2(SIZE * 0.5 - 9.0 + (2.0 if left else -2.0), SIZE * 0.5 - 9.0)
		ic.size = Vector2(18, 18)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		var chev := UiKit.label("‹" if left else "›", UiTokens.STYLE_C12_B, UiTokens.COLOR_SECONDARY)
		chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chev.position = Vector2(2.0 if left else SIZE - 10.0, SIZE * 0.5 - 9.0)
		b.add_child(chev)
		add_child(b)
		b.gui_input.connect(func(e: InputEvent):
			if P0Ui.is_tap(e):
				tapped.emit()
				queue_free())
		resized.connect(func():
			b.position = Vector2(INSET if _left else size.x - SIZE - INSET, clampf(_y - SIZE * 0.5, INSET, size.y - SIZE - INSET)))
		var t := create_tween()
		t.tween_property(b, "scale", Vector2.ONE * 1.15, 0.12)
		t.tween_property(b, "scale", Vector2.ONE, 0.2)
		t.tween_interval(2.4)
		t.tween_property(b, "modulate:a", 0.0, 0.3)
		t.tween_callback(queue_free)

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
		"near":   # near:<anchor> — stand where that facility is used, facing it, so its strip opens (282 shots)
			var stand := P0RoomAnchors.stand_for(step[1], _anchors.keys())
			var m := anchor(stand) if stand != "" else null
			var target := anchor(step[1])
			if m and target:
				var at := m.global_position
				if stove_of(step[1]) > 0: at = Vector3(target.global_position.x, at.y, at.z)   # in front of that pot
				actor.teleport(Vector3(at.x, floor_y, at.z))
				actor.face(target.global_position)
				_focus = actor.position   # as if walked there: the view comes along (the Deluxe Room's stoves are far from its door)
				_follow.held = false
		"stoveprobe":   # where each stove's anchor and badge land on screen and whether its prompt shows (282 shots)
			for i in _stove_count():
				var m := anchor(STOVES[i])
				var bdg := anchor("badge_stove_%d" % (i + 1))
				print("P0_STOVE ", i, " anchor=", m != null, " screen=", cam.unproject_position(bdg.global_position) if bdg else Vector2.INF,
					" tappable=", _tappable().has(STOVES[i]), " card=", _card, " marker=", JSON.stringify(_marker(STOVES[i], rt.session.current()).keys()))
		"uirects":   # world prompts, the pot card's tag and the edge button on screen (282 shots: check layout numerically)
			var out := {}
			for id in rt.ui._icons: if (rt.ui._icons[id] as Control).visible: out["icon " + str(id)] = [(rt.ui._icons[id] as Control).get_global_rect().get_center(), (rt.ui._icons[id] as UiWorldIconButton).status]
			for id in rt.ui._name_bars: if (rt.ui._name_bars[id] as Control).visible: out["strip " + str(id)] = [(rt.ui._name_bars[id] as Control).get_global_rect(), (rt.ui._name_bars[id] as UiWorldNameBar).status]
			var top := get_tree().root
			for c in top.find_children("Tag", "Label", true, false): if (c as Control).is_visible_in_tree(): out["tag " + (c as Label).text] = (c as Control).get_global_rect()
			for c in top.find_children("EdgeButton", "Panel", true, false): if (c as Control).is_visible_in_tree(): out["edge"] = (c as Control).get_global_rect()
			for c in top.find_children("*", "UiPotSlot", true, false): if (c as Control).is_visible_in_tree(): out["slot " + str((c as UiPotSlot).quantity)] = (c as Control).get_global_rect()
			for c in rt.ui.root.find_children("*", "UiStatusBadge", true, false): if (c as Control).is_visible_in_tree(): out["badge " + str(c.get_path()).get_file()] = (c as Control).get_global_rect()
			print("P0_UI_RECTS ", out)
		"uitexts":   # print every visible label / button text on screen (282 shots: check frames without looking)
			var out: Array = []
			for c in rt.ui.root.find_children("*", "Control", true, false):
				if not (c as Control).is_visible_in_tree(): continue
				if c is Label and (c as Label).text != "": out.append((c as Label).text)
				elif c is Button and (c as Button).text != "": out.append("[" + (c as Button).text + "]")
			print("P0_UI_TEXTS ", JSON.stringify(out))
		"pickstove": if kitchen and not kitchen.busy(): kitchen.select_stove(int(step[1]))   # pickstove:<i> (282 shots)
		"bigpot":   # the Big Pot key tapped, Cookbook's or Experiment's (282 shots, q(201))
			if kitchen.drawer: kitchen.drawer.dev_big_pot()
		"batch":   # batch:<n> — the stepper set to n pots, as taps on + would (282 shots, q(200))
			if kitchen.drawer: kitchen.drawer.dev_batch(int(step[1]))
		"cookgo":   # the recipe card's Cook, as a tap on it (282 shots)
			if kitchen.drawer: kitchen.drawer.dev_cook()
		"confirmgo":   # the Rare / Legendary confirm's key (282 shots)
			if is_instance_valid(kitchen.confirm_sheet): kitchen.confirm_sheet.cook_button.pressed.emit()
		"kitchen": p0_open_kitchen(step[1] if step.size() > 1 else "cookbook")
		"cabinetglowoff":   # the Warming Cabinet's warm light off (282 shots: with and without, 上官婉儿)
			if art.has_node("warming_cabinet_glow"): (art.get_node("warming_cabinet_glow") as Node3D).visible = false
		"cardrects":   # the recipe card's parts and the pot card on screen (282 shots: layout by numbers)
			var out := {}
			if kitchen.drawer: out.merge(kitchen.drawer.dev_card_rects())
			if is_instance_valid(kitchen.confirm_sheet): out["confirm"] = kitchen.confirm_sheet.get_global_rect()
			for f in rt.ui.root.find_children("*", "UiFloatText", true, false): out["float " + (f as UiFloatText).text] = (f as Control).get_global_rect()
			out["screen"] = rt.ui.root.size
			print("P0_CARD_RECTS ", out)
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
		"roomkind": print("P0_ROOM_KIND ", room_kind, " Lv", level)   # which room this farmhouse built (282 shots)
		"closeup":   # closeup:<cam anchor> — pushed in on that point, held (art review shots of the pots)
			focus(step[1], {size = view_size() * 0.22, release_on_move = false, band = band_below_hud(0.5)})
		"potreview":   # potreview[:i/j] — all three pots, stoves i, j on the Big Pot, every burner open (art review shots only)
			if _pots:
				_pots_key = "review"
				_apply_pots(_pots.get_child_count(), Array(step[1].split("/")).map(func(x): return int(x)) if step.size() > 1 else [])
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
