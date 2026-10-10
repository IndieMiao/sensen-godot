class_name P0FarmMaterials
extends Node
## SGODOT-231 on the homestead: the mine mouth (tapped like any facility, SGODOT-266: walk up, then its EntryCard with
## the fee button; "The mine" sheet, the world badge and the once-only "Run ended at daily reset"), the five gathering
## spots (tap when near, 0 Energy, Ready / countdown marks, floats) and the workbench. One child node of the farm, so p0_farm.gd keeps a few one-line
## hooks; copy comes from P0MaterialLogic.

const P0_MINE := "res://scenes/p0/p0_mine.tscn"
const MOUTH_REACH := 2.4        # m: the mouth's strip opens, a tapped walk ends, its EntryCard stays
const MOUTH_MARK := Vector3(0, 1.9, 0)   # the mouth's badge / world prompt sits here …
const MOUTH_HIT := Vector3(0, 0.8, 0)    # … and a tap on it is a tap on the gate
const BODY_GAP := 4.0           # px: a card lifted off the player clears its body by this much
const NOTICE_S := 2.0           # "Run ended at daily reset" float (q(44))
const SPOT_REACH := 3.0         # m: finger cards show and taps gather only this close (Arthur, 231)
const SPOTS := ["spot_grove", "spot_rock_pile", "spot_reed_bank", "spot_clay_bank", "spot_herb_patch", "spot_old_tree"]

var farm: Node3D                # p0_farm.gd: actor, cam
var rt: P0Runtime
var mouth := Vector3.ZERO
var _entry: UiEntryCard
var _entry_card := {}           # P0MaterialLogic.mine_mouth_card while the card shows
var _card_open := false         # the mouth was tapped and walked up to: its card shows until the player leaves it
var _reset_shown := 0.0
var _stored_shown := 0.0
var _opening := false
var _spots := {}                # spot id → world position (the spot's anchor cell)
var _bench := Vector3.ZERO
var _mouth_art: Node3D          # the mouth's model: a tap anywhere on it is a tap on the mouth
var _to_mouth := false          # a tap on the mouth from afar: walking up to it

func setup(farm_node: Node3D, mouth_at: Vector3, art: Node3D = null) -> P0FarmMaterials:
	farm = farm_node
	mouth = mouth_at
	_mouth_art = art
	name = "FarmMaterials"
	return self

func _ready() -> void:
	rt = P0Runtime.ensure()
	rt.session.state_changed.connect(_on_state)
	_ensure_entry()   # may not be possible yet: see _ensure_entry
	_build_spots()
	# Floats for a past auto-store are not news: only arrivals after entering the farm float.
	var auto = rt.session.current().get("storage", {}).get("auto", null)
	if auto is Dictionary: _stored_shown = float(auto.get("at", 0))

func _build_spots() -> void:
	var bp: FarmBlueprint = farm.bp
	for id in SPOTS:
		_spots[id] = bp.cell_to_world(bp.anchor(id))
		farm.add_child(P0SpotArt.build(id, _spots[id]))
		P0Garden.block_points(bp, P0SpotArt.solid_points(id, _spots[id]))   # the grove's trunks
	_bench = bp.cell_to_world(bp.anchor("workbench"))   # the anchor is the middle of its three cells
	farm.add_child(P0SpotArt.build("workbench", _bench))

func _exit_tree() -> void:
	if rt and rt.session.state_changed.is_connected(_on_state): rt.session.state_changed.disconnect(_on_state)
	if is_instance_valid(_entry): _entry.queue_free()

## The card lives on the shared UI layer: hide it whenever the farm is not the active world (the mine, the map).
func _process(_dt: float) -> void:
	if is_instance_valid(_entry) and rt and rt.world != farm: _entry.visible = false

func near_mouth() -> bool:
	return flat(farm.actor.position, mouth) < MOUTH_REACH

## Ground distance: the player's y follows the ground (beds, slopes), facilities sit at 0 (Arthur on 231, int5 #11).
static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## This helper's candidates for the farm's open name strip (P0Garden.pick_card, LOCK-07 v2: one at a time; the same
## rule SGODOT-231 and SGODOT-228 each wrote, kept once in P0Garden): the five spots and the workbench.
func card_candidates() -> Array:
	var out: Array = []
	for id in SPOTS: out.append([id, _spots.get(id, Vector3.ZERO), SPOT_REACH])
	out.append(["workbench", _bench, SPOT_REACH])
	# The mouth takes the farm's one card when it is nearest: its strip, or its EntryCard once tapped, so the Herb
	# Patch's card never sits on it (LOCK-07; desktop check of the root-scene fix, #39 follow-up).
	out.append(["mine", mouth, MOUTH_REACH])
	return out

## Every frame on the farm: badge, EntryCard and the reset notice. `card` is the farm's one finger card this frame.
func frame(v: Dictionary, card := "") -> void:
	var cam: Camera3D = farm.cam
	var near := near_mouth()
	if _to_mouth and not farm.actor.mover.is_moving():   # arrived: the stick cancels the walk (cancel_walk)
		_to_mouth = false
		if near: _at_mouth()
	if _card_open and (not near or P0MaterialLogic.mine_runs_spent(v)): _card_open = false   # walked off: the card folds
	var top := cam.unproject_position(mouth + Vector3(0, 1.9, 0))
	# A world prompt like the other facilities, with or without an unfinished run (Figma MINE-P0-5, 不知火舞 on #190: the
	# Run 1/2 badge is gone): the pickaxe button within 8 m, the strip `The mine · Runs today 1/2` when it holds the
	# farm's card. Once tapped and walked up to, its EntryCard takes the strip's place, the name on the card's title row.
	var open := _card_open and not rt.ui.has_modal()
	farm.world_prompt("mine", P0WorldPrompts.mine(v), mouth, MOUTH_MARK, MOUTH_HIT, not open)
	if _ensure_entry(): _entry.visible = open
	if is_instance_valid(_entry) and _entry.visible:
		_entry_card = P0MaterialLogic.mine_mouth_card(v)
		_show_card(_entry, _entry_card)
		# Placed as TapCard: the pointer tip on the gate, kept inside the screen, the pointer still on the gate.
		var size := _entry.get_combined_minimum_size()
		var area := Rect2(Vector2.ZERO, rt.ui.root.size)
		var r := WorldAnchor.place(size, top - Vector2(0, UiTokens.SPACE_WITHIN), area, UiTokens.SPACE_WITHIN, true)
		# Never over the player: lifted clear of the body by 4, no higher than under the HUD (不知火舞 on #190).
		r = WorldAnchor.lift_clear(r, farm.actor.screen_box(cam), BODY_GAP, rt.ui.card_top())
		_entry.size = size
		_entry.position = r.position
		_entry.point_at(top.x - r.position.x)
	if near:
		var notice := P0MaterialLogic.reset_notice(v, _reset_shown)
		if notice != "":
			_reset_shown = float(v.mine.ended.at)
			rt.ui.float_text(notice, top + Vector2(0, -8), UiFloatText.Tone.ITEM)
	_spot_marks(v, card)
	var stored := P0MaterialLogic.stored_notice(v, _stored_shown)
	if stored != "":
		_stored_shown = float(v.storage.auto.at)
		rt.ui.toast(stored)   # §4.8.6 回家入库: Toast Info `Stored · 12 Stone · 3 Copper Ore`

## World prompts (SGODOT-250, LOCK-07 v2): each gathering spot and the workbench show their icon button within
## P0WorldPrompts.RANGE — a spot's state (Ready, or Locked for Clay Bank before Homestead Lv2) from anywhere, in the
## icon's place — and the one holding the farm's open strip (`card`) opens it: `Timber Grove`, `Clay Bank · Homestead
## Lv2`, `Reed Bank · Ready in 2h 10m`, `Workbench`. A tap on either is the spot's (tap_card, by id).
func _spot_marks(v: Dictionary, card: String) -> void:
	for m in P0MaterialLogic.gather_marks(v):
		var id := str(m.id)
		var at: Vector3 = _spots.get(id, Vector3.ZERO)
		farm.world_prompt(id, P0WorldPrompts.spot(v, m), at, Vector3(0, 1.3, 0), Vector3(0, 0.6, 0))
	farm.world_prompt("workbench", P0WorldPrompts.workbench(), _bench, Vector3(0, 1.4, 0), Vector3(0, 0.8, 0))

## The mouth card's content (mine_mouth_card) on a UiEntryCard. LOCK-10: a grey button still takes the press and says
## why (苏烈, #39), so it is never disabled.
static func _show_card(e: UiEntryCard, c: Dictionary) -> void:
	e.title = str(c.get("title", ""))
	e.title_fact = str(c.get("fact", ""))
	var main: Dictionary = c.get("main", {})
	e.action = str(main.get("label", ""))
	e.state = UiEntryCard.State.AVAILABLE if bool(main.get("enabled", false)) else UiEntryCard.State.UNAVAILABLE
	e.amber = bool(main.get("amber", false))
	var second: Dictionary = c.get("second", {})
	e.second = str(second.get("label", ""))
	e.second_state = UiEntryCard.State.AVAILABLE if bool(second.get("enabled", false)) else UiEntryCard.State.UNAVAILABLE
	e.second_amber = bool(second.get("amber", false))
	var express: Dictionary = c.get("express", {})   # Floor 5 · Express · Free (P1), under New run when a run is open
	e.third = str(express.get("label", ""))
	e.third_state = UiEntryCard.State.AVAILABLE if bool(express.get("enabled", false)) else UiEntryCard.State.UNAVAILABLE
	e.note = str(c.get("note", ""))

## A real tap with the EntryCard up (it is passive, so the scene layer's tap arrives here first from p0_tap): on it,
## its button's; anywhere else the card folds ("点别处就收起", 不知火舞 9ce583a8) and the tap goes on to the farm.
func tap_entry(screen: Vector2) -> bool:
	if not is_instance_valid(_entry) or not _entry.visible: return false
	if _entry.tap_at(screen + rt.ui.root.global_position) != "": return true
	close_card()
	return false

func close_card() -> void:
	_card_open = false
	if is_instance_valid(_entry): _entry.visible = false

## The stick takes over: a walk to the mouth stops there (SGODOT-266: pushing the stick on the way cancels).
func cancel_walk() -> void:
	_to_mouth = false

func card_open() -> bool: return is_instance_valid(_entry) and _entry.visible

## The mouth was tapped and walked up to and its card is meant to show (it may not have drawn yet this frame).
func card_wanted() -> bool: return _card_open

## Taps on the farm's material facilities (LOCK-07): the mouth walks up to it (tap_mouth); a spot gathers when the
## player stands near it, a locked one shows MAT-3; the workbench opens its drawer.
func tap(screen: Vector2) -> bool:
	var cam: Camera3D = farm.cam
	if _mouth_hit(screen):
		# The model's box reaches the Herb Patch's and the bench's tap circles (苏烈 on #156): a tap on both goes to the
		# nearer of the mouth's middle and that facility's point.
		var others: Array = [cam.unproject_position(_bench + Vector3(0, 0.8, 0))]
		for id in SPOTS: others.append(cam.unproject_position(_spots.get(id, Vector3.ZERO) + Vector3(0, 0.6, 0)))
		if mouth_nearest(screen, _mouth_centre(), others):
			tap_mouth()
			return true
	for id in SPOTS:
		var at: Vector3 = _spots.get(id, Vector3.ZERO)
		if cam.unproject_position(at + Vector3(0, 0.6, 0)).distance_to(screen) >= 64: continue
		if flat(farm.actor.position, at) >= SPOT_REACH: return false   # far away: the tap walks / does nothing
		return tap_card(id)
	if cam.unproject_position(_bench + Vector3(0, 0.8, 0)).distance_to(screen) < 64 and flat(farm.actor.position, _bench) < SPOT_REACH:
		return tap_card("workbench")
	return false

## A tap on the mouth — its model, button or strip (不知火舞 on 231, int11 ②; SGODOT-266) — walks the player up to it
## (the stick on the way cancels); there its EntryCard opens with the fee button (`Enter mine · 2 Energy`, or
## `Continue run · Free` and `New run`): the tap itself never spends Energy. With today's runs used up and none
## unfinished the MINE-P0-8 drawer opens instead.
func tap_mouth() -> void:
	if near_mouth():
		_at_mouth()
		return
	for p in mouth_stands(farm.grid, mouth, farm.actor.position):
		if farm.actor.mover.set_target_position(p):
			_to_mouth = true
			return
	_at_mouth()   # nowhere to stand by it (not on the shipped farm): answer from here

func _at_mouth() -> void:
	farm.actor.face(mouth)
	var v := rt.session.current()
	if P0MaterialLogic.mine_runs_spent(v): P0MaterialCards.open_mine_sheet(rt.ui, v)
	else: _card_open = true

## Walkable points by the mouth, well inside MOUTH_REACH, nearest the player first (the mouth's own cell is the gate).
static func mouth_stands(grid: BlueprintGrid, at: Vector3, from: Vector3) -> Array:
	var bp := grid.bp
	var centre := bp.world_to_cell(at)
	var reach := ceili(MOUTH_REACH / bp.cell_m)
	var out: Array = []
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := centre + Vector2i(dx, dy)
			if cell.x < 0 or cell.y < 0 or cell.x >= bp.grid.x or cell.y >= bp.grid.y or grid.astar.is_point_solid(cell): continue
			var p := bp.cell_to_world(cell)
			var d := flat(p, at)
			if d > 0.5 and d < MOUTH_REACH - 0.5: out.append(p)
	out.sort_custom(func(a, b): return flat(a, from) < flat(b, from))
	return out

## Whether a tap on the mouth's box is the mouth's: unless another facility's tap circle holds it with its point nearer.
static func mouth_nearest(screen: Vector2, mouth_at: Vector2, others: Array, radius := 64.0) -> bool:
	var d := screen.distance_to(mouth_at)
	for o in others:
		var e := screen.distance_to(o)
		if e < radius and e < d: return false
	return true

func _mouth_centre() -> Vector2:
	var cam: Camera3D = farm.cam
	if is_instance_valid(_mouth_art):
		var box := screen_box(cam, _mouth_art)
		if box.has_area(): return box.get_center()
	return cam.unproject_position(mouth + MOUTH_HIT)

## The mouth's model on screen (any part of it counts); a circle round the gate without the model.
func _mouth_hit(screen: Vector2) -> bool:
	var cam: Camera3D = farm.cam
	if is_instance_valid(_mouth_art) and _mouth_art.is_visible_in_tree():
		var box := screen_box(cam, _mouth_art)
		if box.has_area(): return box.has_point(screen)
	return cam.unproject_position(mouth + MOUTH_HIT).distance_to(screen) < 60

## A model's bounds projected on screen: every mesh's box corners (geometry only: a light's box is its whole range).
static func screen_box(cam: Camera3D, root: Node3D) -> Rect2:
	var box := Rect2()
	var first := true
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var vi := n as GeometryInstance3D
		var aabb := vi.get_aabb()
		if aabb.size == Vector3.ZERO: continue
		for i in 8:
			var p := cam.unproject_position(vi.global_transform * aabb.get_endpoint(i))
			if first: box = Rect2(p, Vector2.ZERO)
			else: box = box.expand(p)
			first = false
	return box

## A finger card's tap by id (苏烈's #21 _tap_card dispatch): a gathering spot gathers / shows MAT-3 / says when it is
## ready; the workbench opens. False for ids this helper doesn't own.
func tap_card(id: String) -> bool:
	# A tap that reaches the world while a sheet or card is already up (a fast second tap on a spot's button before the
	# frame hides it) opens nothing more (SGODOT-256 ①).
	if rt.ui.has_modal() and (id in SPOTS or id in ["workbench", "mine"]): return true
	if id == "mine":   # the mouth's strip or button
		tap_mouth()
		return true
	if id == "workbench":
		farm.actor.face(_bench)
		_open_workbench()
		return true
	if not _spots.has(id): return false
	var v := rt.session.current()
	for m in P0MaterialLogic.gather_marks(v):
		if str(m.id) != id: continue
		farm.actor.face(_spots[id])
		match str(m.badge):
			"ready": rt.session.send({"type": "gather", "spot": id})
			"locked": P0MaterialCards.open_locked_spot(rt.ui, v, id)
			_: rt.ui.toast(str(m.caption))
		return true
	return false

## B2-06: the workbench drawer (P0Ui.open_workbench); what a craft shows afterwards is _on_craft's.
func _open_workbench() -> void:
	rt.ui.open_workbench()

## A NeedSource Show target this helper owns (a gathering spot, "mine", "workbench"), else null (LOCK-08: Show only
## moves the camera there).
func spot_at(where: String) -> Variant:
	if _spots.has(where): return _spots[where]
	if where == "mine": return mouth
	if where == "workbench": return _bench
	return null

## What one craft shows (B2-06): a Supply stays in the drawer and floats `+2 Torch` on its card (TORCH-DONE; away from
## the drawer, over the player); the Copper Pickaxe closes the drawer for its `Crafted!` Moment with Equip
## (PICKAXE-DONE); the Gather Gloves keep the drawer and get the MomentBanner (GLOVES-DONE). The runtime leaves a
## crafting reply's item floats to this.
func _on_craft(v: Dictionary, e: Dictionary) -> void:
	var item := str(e.get("item", ""))
	match str(e.get("to", "")):
		"bag":
			var line := "+%d %s" % [int(e.get("qty", 1)), P0Logic.item_name(v, item)]
			var drawer := rt.ui.workbench()
			if drawer == null or drawer.float_on(str(e.get("recipe", "")), line, P0Logic.icon(item)) == null:
				rt.ui.queue_floats([{kind = "item", key = item, amount = int(e.get("qty", 1)),
					fmt = "%s " + P0Logic.item_name(v, item), tone = UiFloatText.Tone.ITEM, icon = P0Logic.icon(item)}], rt.anchor())
		"gear":
			if rt.ui.workbench() != null: rt.ui.close_modal()
			rt.ui.queue_card(func(): P0MaterialCards.open_crafted(rt.ui, rt.session.current(), item,
				func(cmd: Dictionary): rt.session.send(cmd)))
		"owned":
			P0MaterialCards.gloves_banner(rt.ui, v)

## Commands this helper owns; false lets the farm handle the rest.
func act(cmd: Dictionary) -> bool:
	match str(cmd.get("type", "")):
		"mine_enter", "mine_new_run", "mine_express":
			close_card()
			rt.session.send(cmd)
		"toast":
			rt.ui.toast(str(cmd.get("text", "")))
		_:
			return false
	return true

## A run starts or continues: open the mine on the floor the server landed it on (Continue run: the deepest paid;
## Express: Floor 5).
## A gather floats what went to storage at the spot (the runtime floats what went to the bag).
func _on_state(v: Dictionary, events: Array) -> void:
	if rt.world != farm or _opening: return
	for e in events:
		if str(e.get("kind", "")) == "craft": _on_craft(v, e)
	for e in events:
		if str(e.get("kind", "")) == "gather":
			# One item line with the runtime's own (what went to the bag), in the reply's three lines (q(49) ①).
			rt.ui.queue_floats(P0MaterialLogic.gather_floats(v, e).map(func(line: String) -> Dictionary:
				return {kind = "item", key = line, text = line, tone = UiFloatText.Tone.ITEM}), rt.anchor())
	for e in events:
		if str(e.get("kind", "")) == "mine" and str(e.get("action", "")) in ["enter", "continue", "express"]:
			_opening = true
			AppRouter.open_instance(P0_MINE, {"floor": int(e.get("floor", 1))})
			get_tree().create_timer(1.0).timeout.connect(func(): _opening = false)
			return

## The EntryCard hangs on the P0 UI's root, which only exists once the UI is in the tree. With the farm as the root
## scene (the first session, desktop P0_SHOT) this helper is ready before the runtime is — P0Runtime.ensure() adds it
## deferred — so the card is built on the first call that can carry it (刘邦 / 奕星 on #39). True once it exists.
func _ensure_entry() -> bool:
	if is_instance_valid(_entry): return true
	if rt == null or rt.ui == null or not rt.ui.is_node_ready() or rt.ui.root == null: return false
	_build_entry_card()
	return true

## EntryCard (UiEntryCard, 1468:94344, MINE-P0-5): over the mouth, only while the mouth holds the farm's one card,
## only with an unfinished run; the whole card is the button (New run · 2 Energy + its consequence; grey with the
## reason when it can't).
func _build_entry_card() -> void:
	_entry = UiEntryCard.new()
	_entry.theme = UiKit.theme()   # the P0 root still carries GameUi's theme
	_entry.passive = true          # a drag starting on it is the joystick; tap_entry() takes the real tap
	_entry.pressed.connect(func(): _press(_entry_card.get("main", {})))
	_entry.second_pressed.connect(func(): _press(_entry_card.get("second", {})))
	_entry.third_pressed.connect(func(): _press(_entry_card.get("express", {})))
	_entry.visible = false
	rt.ui.root.add_child(_entry)

## One of the card's buttons (P0MaterialLogic._button): grey says why; amber opens the Energy card for that fee; Enter
## mine / Continue run go in; New run asks first (MINE-P0-7).
func _press(b: Dictionary) -> void:
	if b.is_empty(): return
	if not bool(b.get("enabled", false)):
		rt.ui.toast(str(b.get("toast", b.get("label", ""))))
		return
	var cmd: Dictionary = b.get("cmd", {})
	match str(cmd.get("type", "")):
		"mine_enter": act(cmd)
		"mine_new_run":
			P0MaterialCards.open_new_run(rt.ui, rt.session.current(), func(c: Dictionary): act(c))
		"mine_express":   # §13.3.9: from the mouth a new run; with one open it ends it, so it asks as New run does
			var v := rt.session.current()
			if v.get("mine", {}).get("run", null) != null:
				P0MaterialCards.open_new_run(rt.ui, v, func(_c: Dictionary): act({"type": "mine_express", "space": "home"}))
			else: act({"type": "mine_express", "space": "home"})
		"energy_card":
			rt.energy_card(int(b.get("need", 0)), str(b.get("verb", "")))
