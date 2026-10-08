class_name P0FarmMaterials
extends Node
## SGODOT-231 on the homestead: the mine mouth (LOCK-21 main action key, the EntryCard with New run, "The mine" sheet,
## the world badge and the once-only "Run ended at daily reset"), the five gathering spots (tap when near, 0 Energy,
## Ready / countdown marks, floats) and the workbench. One child node of the farm, so p0_farm.gd keeps a few one-line
## hooks; copy comes from P0MaterialLogic.

const P0_MINE := "res://scenes/p0/p0_mine.tscn"
const MOUTH_REACH := 2.4        # m: the key turns into Enter mine / Continue run, the EntryCard shows
const MOUTH_MARK := Vector3(0, 1.9, 0)   # the mouth's badge / world prompt sits here …
const MOUTH_HIT := Vector3(0, 0.8, 0)    # … and a tap on it is a tap on the gate
const NOTICE_S := 2.0           # "Run ended at daily reset" float (q(44))
const SPOT_REACH := 3.0         # m: finger cards show and taps gather only this close (Arthur, 231)
const SPOTS := ["spot_grove", "spot_rock_pile", "spot_reed_bank", "spot_clay_bank", "spot_herb_patch"]

var farm: Node3D                # p0_farm.gd: actor, cam
var rt: P0Runtime
var mouth := Vector3.ZERO
var _entry: UiEntryCard
var _entry_cmd := {}
var _entry_card := {}
var _reset_shown := 0.0
var _stored_shown := 0.0
var _opening := false
var _spots := {}                # spot id → world position (the spot's anchor cell)
var _bench := Vector3.ZERO

func setup(farm_node: Node3D, mouth_at: Vector3) -> P0FarmMaterials:
	farm = farm_node
	mouth = mouth_at
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

## The key at the mouth (LOCK-21): Enter mine · 2 Energy / Continue run · Free / Enter mine · No runs left.
func action(v: Dictionary) -> Dictionary:
	return P0MaterialLogic.mine_entry_action(v)

## Ground distance: the player's y follows the ground (beds, slopes), facilities sit at 0 (Arthur on 231, int5 #11).
static func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## This helper's candidates for the farm's open name strip (P0Garden.pick_card, LOCK-07 v2: one at a time; the same
## rule SGODOT-231 and SGODOT-228 each wrote, kept once in P0Garden): the five spots and the workbench.
func card_candidates() -> Array:
	var out: Array = []
	for id in SPOTS: out.append([id, _spots.get(id, Vector3.ZERO), SPOT_REACH])
	out.append(["workbench", _bench, SPOT_REACH])
	# The mouth takes the farm's one card when it is nearest: no finger card then, its EntryCard shows instead, so
	# the Herb Patch's card never sits on it (LOCK-07; desktop check of the root-scene fix, #39 follow-up).
	out.append(["mine", mouth, MOUTH_REACH])
	return out

## Every frame on the farm: badge, EntryCard and the reset notice. `card` is the farm's one finger card this frame.
func frame(v: Dictionary, card := "") -> void:
	var cam: Camera3D = farm.cam
	var near := near_mouth()
	var top := cam.unproject_position(mouth + Vector3(0, 1.9, 0))
	# With an unfinished run the mouth keeps its Run 1/2 badge near and far (MINE-P0-5, LOCK-11: a state over the plain
	# icon) and the EntryCard opens when near; without one it is a world prompt like the other facilities — the pickaxe
	# button within 8 m, the strip `The mine · Runs today 0/2` when it holds the farm's card (不知火舞 on 235). Never both.
	var running: bool = v.get("mine", {}).get("run", null) != null
	rt.ui.badge("mine", UiStatusBadge.State.AVAILABLE, top, running and not rt.ui.has_modal(), P0MaterialLogic.mine_badge(v),
		P0Logic.icon("pickaxe"))
	farm.world_prompt("mine", P0WorldPrompts.mine(v), mouth, MOUTH_MARK, MOUTH_HIT, not running)
	if running: top.y -= rt.ui.badge_height("mine")
	var entry := P0MaterialLogic.mine_entry_card(v)
	if _ensure_entry(): _entry.visible = card == "mine" and bool(entry.get("show", false)) and not rt.ui.has_modal()
	if is_instance_valid(_entry) and _entry.visible:
		# LOCK-10: a greyed EntryCard still takes the press and says why (苏烈, #39), so it is never disabled.
		_entry.state = UiEntryCard.State.AVAILABLE if bool(entry.enabled) else UiEntryCard.State.UNAVAILABLE
		_entry.amber = bool(entry.get("amber", false))
		_entry.action = str(entry.label)
		_entry.caption = str(entry.line2)
		_entry_card = entry
		_entry_cmd = entry.cmd
		# Placed as TapCard: the pointer tip on the gate, kept inside the screen, the pointer still on the gate.
		var size := _entry.get_combined_minimum_size()
		var area := Rect2(Vector2.ZERO, rt.ui.root.size)
		var r := WorldAnchor.place(size, top - Vector2(0, UiTokens.SPACE_WITHIN), area, UiTokens.SPACE_WITHIN, true)
		_entry.size = size
		_entry.position = r.position
		_entry.point_at(top.x - r.position.x)
	if near:
		var notice := P0MaterialLogic.reset_notice(v, _reset_shown)
		if notice != "":
			_reset_shown = float(v.mine.ended.at)
			rt.ui.float_text(notice, top + Vector2(0, -8), P0Ui.INK)
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

## A real tap on the EntryCard (it is passive, so the scene layer's tap arrives here first from p0_tap).
func tap_entry(screen: Vector2) -> bool:
	if not is_instance_valid(_entry) or not _entry.visible: return false
	if not _entry.hit_rect().has_point(screen + rt.ui.root.global_position): return false
	_on_entry()
	return true

## Taps on the farm's material facilities (LOCK-07): the mouth shows "The mine" (MINE-P0-1 / P0-8; entering stays on the
## key); a spot gathers when the player stands near it, a locked one shows MAT-3; the workbench opens its drawer.
func tap(screen: Vector2) -> bool:
	var cam: Camera3D = farm.cam
	if cam.unproject_position(mouth + Vector3(0, 0.8, 0)).distance_to(screen) < 60:
		P0MaterialCards.open_mine_sheet(rt.ui, rt.session.current())
		return true
	for id in SPOTS:
		var at: Vector3 = _spots.get(id, Vector3.ZERO)
		if cam.unproject_position(at + Vector3(0, 0.6, 0)).distance_to(screen) >= 64: continue
		if flat(farm.actor.position, at) >= SPOT_REACH: return false   # far away: the tap walks / does nothing
		return tap_card(id)
	if cam.unproject_position(_bench + Vector3(0, 0.8, 0)).distance_to(screen) < 64 and flat(farm.actor.position, _bench) < SPOT_REACH:
		return tap_card("workbench")
	return false

## A finger card's tap by id (苏烈's #21 _tap_card dispatch): a gathering spot gathers / shows MAT-3 / says when it is
## ready; the workbench opens. False for ids this helper doesn't own.
func tap_card(id: String) -> bool:
	if id == "mine":   # the mouth's strip or button (no unfinished run): "The mine" sheet; entering stays on the key
		P0MaterialCards.open_mine_sheet(rt.ui, rt.session.current())
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
		"mine_enter", "mine_new_run":
			rt.session.send(cmd)
		"toast":
			rt.ui.toast(str(cmd.get("text", "")))
		_:
			return false
	return true

## A run starts or continues: open the mine on the floor the server landed it on (Continue run: the deepest paid).
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
		if str(e.get("kind", "")) == "mine" and str(e.get("action", "")) in ["enter", "continue"]:
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
	_entry.pressed.connect(_on_entry)
	_entry.visible = false
	rt.ui.root.add_child(_entry)

func _on_entry() -> void:
	if not bool(_entry_card.get("enabled", false)):
		rt.ui.toast(str(_entry_card.get("toast", _entry_card.get("label", ""))))
		return
	match str(_entry_cmd.get("type", "")):
		"mine_new_run":
			P0MaterialCards.open_new_run(rt.ui, rt.session.current(), func(cmd: Dictionary): rt.session.send(cmd))
		"energy_card":
			rt._on_action(_entry_cmd)
