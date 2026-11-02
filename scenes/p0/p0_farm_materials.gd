class_name P0FarmMaterials
extends Node
## SGODOT-231 on the homestead: the workbench, and the `Stored · …` notice when coming home. The gathering spots left the
## farm with v4q(4) ① (the user, 11-02: gathering is a city's points, from the map) and the mine mouth in 355 b1
## (v4q(5) ①: the mines are wild sites). One child node of the farm, so p0_farm.gd keeps a few one-line hooks; copy
## comes from P0MaterialLogic.

const BODY_GAP := 4.0           # px: a card lifted off the player clears its body by this much
const SPOT_REACH := 3.0         # m: the workbench's finger card shows and a tap opens it only this close (Arthur, 231)

var farm: Node3D                # p0_farm.gd: actor, cam
var rt: P0Runtime
var _stored_shown := 0.0
var _bench := Vector3.ZERO

func setup(farm_node: Node3D) -> P0FarmMaterials:
	farm = farm_node
	name = "FarmMaterials"
	return self

func _ready() -> void:
	rt = P0Runtime.ensure()
	rt.session.state_changed.connect(_on_state)
	_build_bench()
	# Floats for a past auto-store are not news: only arrivals after entering the farm float.
	var auto = rt.session.current().get("storage", {}).get("auto", null)
	if auto is Dictionary: _stored_shown = float(auto.get("at", 0))

func _build_bench() -> void:
	var bp: FarmBlueprint = farm.bp
	_bench = bp.cell_to_world(bp.anchor("workbench"))   # the anchor is the middle of its three cells
	farm.add_child(P0SpotArt.build("workbench", _bench))

func _exit_tree() -> void:
	if rt and rt.session.state_changed.is_connected(_on_state): rt.session.state_changed.disconnect(_on_state)

## Ground distance: the player's y follows the ground (beds, slopes), facilities sit at 0 (Arthur on 231, int5 #11).
static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## This helper's candidates for the farm's open name strip (P0Garden.pick_card, LOCK-07 v2: one at a time; the same
## rule SGODOT-231 and SGODOT-228 each wrote, kept once in P0Garden): the workbench.
func card_candidates() -> Array:
	return [["workbench", _bench, SPOT_REACH]]

## Every frame on the farm (World prompts, SGODOT-250, LOCK-07 v2): the workbench's icon button within
## P0WorldPrompts.RANGE, its strip `Workbench` when it holds the farm's one finger card; and the stored notice.
func frame(v: Dictionary, _card := "") -> void:
	farm.world_prompt("workbench", P0WorldPrompts.workbench(), _bench, Vector3(0, 1.4, 0), Vector3(0, 0.8, 0))
	var stored := P0MaterialLogic.stored_notice(v, _stored_shown)
	if stored != "":
		_stored_shown = float(v.storage.auto.at)
		rt.ui.toast(stored)   # §4.8.6 回家入库: Toast Info `Stored · 12 Stone · 3 Copper Ore`

## A tap on the workbench (LOCK-07) opens its drawer when the player stands near it.
func tap(screen: Vector2) -> bool:
	var cam: Camera3D = farm.cam
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

## A finger card's tap by id (苏烈's #21 _tap_card dispatch): the workbench opens. False for ids this helper doesn't own.
func tap_card(id: String) -> bool:
	if id != "workbench": return false
	# A tap that reaches the world while a sheet or card is already up (a fast second tap on the button before the
	# frame hides it) opens nothing more (SGODOT-256 ①).
	if rt.ui.has_modal(): return true
	farm.actor.face(_bench)
	_open_workbench()
	return true

## B2-06: the workbench drawer (P0Ui.open_workbench); what a craft shows afterwards is _on_craft's.
func _open_workbench() -> void:
	rt.ui.open_workbench()

## A NeedSource Show target this helper owns ("workbench"), else null (LOCK-08: Show only moves the camera there).
## Gathering and the mines are the map's now (v4q(4) ①, 355 b1).
func spot_at(where: String) -> Variant:
	return _bench if where == "workbench" else null

## What one craft shows (B2-06): a Supply stays in the drawer and floats `+2 Torch` on its card (TORCH-DONE; away from
## the drawer, over the player); the Copper Pickaxe closes the drawer for its `Crafted!` Moment with Equip
## (PICKAXE-DONE). The Gather Gloves and their banner are gone (丁11). The runtime leaves a crafting reply's item floats
## to this.
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

## Commands this helper owns; false lets the farm handle the rest.
func act(cmd: Dictionary) -> bool:
	match str(cmd.get("type", "")):
		"toast":
			rt.ui.toast(str(cmd.get("text", "")))
		_:
			return false
	return true

func _on_state(v: Dictionary, events: Array) -> void:
	if rt.world != farm: return
	for e in events:
		if str(e.get("kind", "")) == "craft": _on_craft(v, e)

