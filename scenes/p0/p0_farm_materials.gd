class_name P0FarmMaterials
extends Node
## SGODOT-231 on the homestead: the gathering spots (tap when near, 0 Energy, Ready / countdown marks, floats) and the
## workbench. The mine mouth left the farm in 355 b1 (v4q(5) ①: the mines are wild sites, entered from the map). One
## child node of the farm, so p0_farm.gd keeps a few one-line hooks; copy comes from P0MaterialLogic.

const BODY_GAP := 4.0           # px: a card lifted off the player clears its body by this much
const SPOT_REACH := 3.0         # m: finger cards show and taps gather only this close (Arthur, 231)
## The farm's gathering spots: none since SGODOT-355 b1 (v4 #49: they went to the cities, and two stood on new beds).
const SPOTS: Array[String] = []

var farm: Node3D                # p0_farm.gd: actor, cam
var rt: P0Runtime
var _stored_shown := 0.0
var _spots := {}                # spot id → world position (the spot's anchor cell)
var _bench := Vector3.ZERO

func setup(farm_node: Node3D) -> P0FarmMaterials:
	farm = farm_node
	name = "FarmMaterials"
	return self

func _ready() -> void:
	rt = P0Runtime.ensure()
	rt.session.state_changed.connect(_on_state)
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

## Ground distance: the player's y follows the ground (beds, slopes), facilities sit at 0 (Arthur on 231, int5 #11).
static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## This helper's candidates for the farm's open name strip (P0Garden.pick_card, LOCK-07 v2: one at a time; the same
## rule SGODOT-231 and SGODOT-228 each wrote, kept once in P0Garden): the five spots and the workbench.
func card_candidates() -> Array:
	var out: Array = []
	for id in SPOTS: out.append([id, _spots.get(id, Vector3.ZERO), SPOT_REACH])
	out.append(["workbench", _bench, SPOT_REACH])
	return out

## Every frame on the farm: the spots' and the workbench's prompts and the stored notice. `card` is the farm's one
## finger card this frame.
func frame(v: Dictionary, card := "") -> void:
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
		if not _spots.has(id): continue   # a spot the server still lists that is not on the farm (SGODOT-355 b1)
		var at: Vector3 = _spots[id]
		farm.world_prompt(id, P0WorldPrompts.spot(v, m), at, Vector3(0, 1.3, 0), Vector3(0, 0.6, 0))
	farm.world_prompt("workbench", P0WorldPrompts.workbench(), _bench, Vector3(0, 1.4, 0), Vector3(0, 0.8, 0))

## Taps on the farm's material facilities (LOCK-07): a spot gathers when the player stands near it, a locked one
## shows MAT-3; the workbench opens its drawer.
func tap(screen: Vector2) -> bool:
	var cam: Camera3D = farm.cam
	for id in SPOTS:
		var at: Vector3 = _spots.get(id, Vector3.ZERO)
		if cam.unproject_position(at + Vector3(0, 0.6, 0)).distance_to(screen) >= 64: continue
		if flat(farm.actor.position, at) >= SPOT_REACH: return false   # far away: the tap walks / does nothing
		return tap_card(id)
	if cam.unproject_position(_bench + Vector3(0, 0.8, 0)).distance_to(screen) < 64 and flat(farm.actor.position, _bench) < SPOT_REACH:
		return tap_card("workbench")
	return false

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
	if rt.ui.has_modal() and (id in SPOTS or id == "workbench"): return true
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

## A NeedSource Show target this helper owns (a gathering spot, "workbench"), else null (LOCK-08: Show only moves the
## camera there). "mine" is the map's now (no mouth on the farm, 355 b1).
func spot_at(where: String) -> Variant:
	if _spots.has(where): return _spots[where]
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
		"toast":
			rt.ui.toast(str(cmd.get("text", "")))
		_:
			return false
	return true

## A gather floats what went to storage at the spot (the runtime floats what went to the bag).
func _on_state(v: Dictionary, events: Array) -> void:
	if rt.world != farm: return
	for e in events:
		if str(e.get("kind", "")) == "craft": _on_craft(v, e)
	for e in events:
		if str(e.get("kind", "")) == "gather":
			# One item line with the runtime's own (what went to the bag), in the reply's three lines (q(49) ①).
			rt.ui.queue_floats(P0MaterialLogic.gather_floats(v, e).map(func(line: String) -> Dictionary:
				return {kind = "item", key = line, text = line, tone = UiFloatText.Tone.ITEM}), rt.anchor())

