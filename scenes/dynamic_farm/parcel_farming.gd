extends Node3D
## Farming inside the owner's own dynamic parcel (C-34, rules Q-39): clear a core obstacle,
## till, sow a carrot and harvest it into the bag. One press of the main key does one step.
## Energy (C-148, P0's numbers): clearing, tilling, sowing and gathering cost it, harvesting is free;
## the key shows the price (`3 Energy`), short of it it turns amber (`Need 3 Energy`, LOCK-10) and a press
## opens P0's Energy card (LOCK-09) instead of sending. The top bar shows P0's Energy chip (LOCK-06);
## at the cottage's door the key rests (+60 once a player day). The store (server or local stand-in) is authoritative; this node
## only checks the spatial rules the server cannot (ParcelSpace) and draws the result.
## Soil and carrots are drawn by ParcelCropArt (C-138: 1×1 dry or wet soil blocks, seven
## carrot stages). Watering (C-151): a sown carrot sits on dry soil and does not grow; at the well the key
## fills the pail (`Fill`, 2 Energy), on a dry carrot it waters it (`Water`, one of the pail's 3) and the soil turns wet. Main-farm pieces are reused read-only: P0 names and icons, and the main
## farm's UI kit (C-74): the quick bar, the action key and item flights into the bag; the bag
## is the UI v3 modal panel and gains the v3 float (C-105). Nothing of P0Ui / P0Runtime; the
## parcel's own coins (C-59) show in the scene's top bar as the main HUD's coins capsule, its
## Energy (C-148) beside them as the main HUD's Energy chip.
## Outer gathering (C-60, ParcelGather): near a tree, flower or rock of the extension the key
## picks it by hand; a picked one stays faded (trees, rocks) or hidden (flowers, which never
## block) until it grows back. Gathering never touches the walk, the layout or collision.
## With a body (the scene, C-73) a press first walks the player beside the cell and plays the
## main farm's labour clip; the command goes out with the clip and its result lands as it ends.
## Livestock (C-154, ParcelLivestock): near a coop's feeder the key reads `Feed` (`1 Energy`); a carrot goes in, and
## the hen lays an egg on the ground `produce_seconds` later. Walking within reach of a laid egg picks it up by
## itself: it flies into the player and on into the Bag (`+1 Egg`), the server checking each egg is taken once.
## The coop's own floor is walked, never farmed: its cells show no key.
## The in-game phone (C-107, design C-85 ⑧): the top bar's task button drops the guide's steps under the bar (C-T1–T3)
## and the phone button at the right opens the phone (Tasks / Inbox / Collection, ParcelPhone); both read the save.
signal state_changed(farm: Dictionary)

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
const Gather = preload("res://modules/dynamic_farm/parcel_gather.gd")
const Guide = preload("res://modules/dynamic_farm/parcel_guide.gd")
const GATHERED_SHADER = preload("res://modules/dynamic_farm/gathered_prop.gdshader")
const CropArt = preload("res://modules/dynamic_farm/parcel_crop_art.gd")
const Livestock = preload("res://scenes/dynamic_farm/parcel_livestock.gd")
const LivestockArt = preload("res://modules/dynamic_farm/farm_livestock.gd")
## How near a feeder (m, its centre on the ground) the key offers Feed (C-154): the bowl is solid, so the player
## stands at least ~0.5 m from its centre.
const FEED_REACH_M := 1.1
const Tasks = preload("res://modules/dynamic_farm/parcel_tasks.gd")
const Phone = preload("res://scenes/dynamic_farm/parcel_phone.gd")
## Which task the player last saw in the drop-down or the phone, per parcel on this device: a newer one marks the task
## and phone buttons (`badge/notify`) until it is seen.
const PHONE_SEEN_PATH := "user://dynamic_farm_local/phone.json"
## The phone's bottom sits this far above its button (C-L5), its right edge this far in from the screen's (C-L5), and the
## phone button this far above the action key (C-L3's column spacing).
const PHONE_ABOVE_BUTTON := UiTokens.SPACE_S4
const PHONE_RIGHT := 14.0
const PHONE_BUTTON_GAP := UiTokens.SPACE_S4
## The drop-down's first row under the top bar (C-T1: 10 under the HUD).
const DROP_DOWN_GAP := 10.0
## Development only: draw every tilled cell as wet soil (C-138 captures). The game draws a watered crop's cell wet (C-151).
const WET_SOIL_SETTING := "sensen/dynamic_farm/preview_wet_soil"
## The tools first (C-151: the pail beside the hoe), then seeds and crops.
const BAG_ORDER := ["hoe_starter", "pail", "seed_carrot", "crop_carrot"]
## Parcel items the main farm's content table does not name (C-74#33, copy per C-45). The icon is a placeholder from
## the existing set (the HUD's home), no new art.
## C-151: `Water` is P0's key (P0Logic, the plot's Water); `Fill` draws the pail at the well (打水, SEN-C-151).
const VERBS := {"clear": "Clear", "till": "Till", "sow": "Sow", "harvest": "Harvest", "rest": "Rest", "gather": "Gather",
	"feed": "Feed", "fill": "Fill", "water": "Water"}
## C-148: Rested today / Energy full are P0's Rest copy (P0Logic.energy_card, rest_state).
## C-151: the pail's refusals in the hoe's form (`Need a hoe`): Need a pail / Pail empty / Pail full.
const REFUSALS := {Space.OUTSIDE: "Not farmland", Space.PATH: "On the path", Space.HOUSE: "House here",
	Space.NO_TOOL: "Need a hoe", Space.NO_SEED: "No seeds", Space.RESTED: "Rested today", Space.FULL: "Energy full",
	Space.NO_PAIL: "Need a pail", Space.PAIL_EMPTY: "Pail empty", Space.PAIL_FULL: "Pail full"}
## The server's pail refusals (C-151), when its state disagreed with the key's: shown as the key would have said.
const POUR_REFUSALS := {"PAIL_EMPTY": Space.PAIL_EMPTY, "PAIL_FULL": Space.PAIL_FULL, "NO_PAIL": Space.NO_PAIL}
## Crop stages follow server time; redraw them this often.
const REDRAW_S := 0.25
## How close (m, ground plane) the player must be to an outer object's bounds to gather it.
const GATHER_REACH_M := 1.2
## Gather refusals: grows back later, or tapped from too far away.
const REGROWING := "regrowing"
const TOO_FAR := "too_far"
## How long one press's labour clip plays; the command's result is shown when it ends.
const LABOUR_S := 1.2
const UNREACHABLE := "Can't reach it"
## The bag panel (UI v3 C-P5): three columns of round slots, at least three rows; the hero is C-86's bag (UiArt).
const BAG_COLUMNS := 3
const BAG_MIN_SLOTS := 9
const BAG_HERO := UiArt.HERO_BAG
## Floats start this far above what they rise from (the caller puts them 40 above the object).
const FLOAT_ABOVE := 40.0
## The action key's bottom sits this far above the quick bar (P0Ui._KEY_ABOVE_BAR, BAR-1).
const KEY_ABOVE_BAR := 40.0
## The guide's card top under the scene's top bar (its 44 row at the v3 safe inset, C-L2) and a page gap.
const TIP_TOP := UiTokens.SIZE_SCREEN_SAFE_INSET + UiTokens.SIZE_TOUCH_MIN + UiTokens.SPACE_PAGE
const LOADING := "Loading your farm…"
const OPEN_FAILED := "Could not open your farm."
## The Energy card's scrim (P0Ui.open_energy_card: UiTokens.OPACITY_SCRIM_MODAL over P0's veil colour).
const SCRIM := Color(0.184, 0.227, 0.2, UiTokens.OPACITY_SCRIM_MODAL)

var store: RefCounted
var rules := {}
var farm := {}
var farm_version := -1
var target := Vector2i(-1, -1)
var current := {}
var picked = null
## Index into `gatherables` of a tapped outer object, -1 when none (cleared when the player moves).
var picked_object := -1
## The parcel's gatherable outer objects (ParcelGather.objects), fixed for the visit.
var gatherables: Array = []
var busy := false
## The farm could not be opened; the key offers Retry.
var unavailable := false
## Another mode owns the screen (house placement, C-33): no key, no target.
var held := false:
	set(value):
		held = value
		if value:
			close_bag()
			close_energy()
			close_phone()
			if drop_down != null: drop_down.fold()
		if _key != null: _refresh_key()
		_refresh_tip()
		_refresh_tasks()
		if not value and _bar != null: _draw_bag()
## The cell a press is walking to or working; the key keeps it while the press runs.
var job = null

var _data: Dictionary
var _walk: RefCounted
var _core_plan: Dictionary
var _recipe: Variant
var _core_root: Node3D
var _proxies: Array = []
## Every cell an uncleared core obstacle covers -> its anchor cell (a tree covers a block).
var _obstacles := {}
## Anchor cell -> index in the core layout; anchors name obstacles in `cleared`.
var _anchors := {}
var _removed := {}
var _path := {}
var _clock_offset_ms := 0
var _crop_art: CropArt
## C-154: the animals and drops of the parcel's livestock buildings.
var livestock: Livestock
## Drop ids whose pick_up is out.
var _picking := []
## Draw tilled soil wet (WET_SOIL_SETTING; probes may set it too).
var wet_soil_preview := false
var _marker: MeshInstance3D
var _marker_material: StandardMaterial3D
var _keys: UiActionKey
var _key: UiSceneAction
var _bar: UiQuickBar
var _toast: ToastLayer
var _ui: Control
## The open bag panel (null when closed; one closing plays out on its own) and its slots by item id.
var _bag: UiModalPanel
var _slots: GridContainer
var _bag_slots := {}
## The selected item in the bag ("" none) and the line naming it under the slots.
var bag_selected := ""
var _picked_name: Label
## Items announced by the last gain (floats and flights): id -> count.
var last_gains := {}
var _side_button: Control
var _redraw_left := 0.0
var _names := {}
var _gather := {}
var _outer_layout: Array = []
var _outer_root: Node3D
var _player := Vector3.ZERO
var _facing := Vector3.ZERO
var _placed := false
## Layout indices drawn as gathered: index -> true.
var _spent := {}
var _spent_material: ShaderMaterial

## The first visit's next step (C-35, ParcelGuide) as the main farm's TipCard, under the top bar.
var _tip: UiTipCard
var _tip_box: CenterContainer
## Where the guide's card starts, in canvas units (the safe top included); the scene sets it under its own top bar
## (two rows since C-108). Negative: TIP_TOP under the status bar.
var tip_top := -1.0
## Where the scene's top bar ends, in canvas units (the safe top included): the drop-down's rows start 10 under it.
## Negative: the one-row bar under the status bar.
var bar_bottom := -1.0
## The step on the card, and the step the player closed with a tap (it comes back only at another step).
var tip_step := ""
var _tip_closed := ""

## C-107: the top bar's task button (the scene puts it in its bar), the phone button, the task drop-down and the open
## phone (null when closed; one closing plays out on its own).
var task_button: UiTaskButton
var phone_button: UiGlassButton
var drop_down: UiTaskDropDown
var phone: Control
## The task last seen and the rows last counted done (PHONE_SEEN_PATH: {block_id: {seen, reached}}), and how many
## rows the drop-down last showed done.
var seen_task := ""
var tasks_reached := 0
var phone_seen_path := PHONE_SEEN_PATH
var _drop_done := -1
var _seen_read := false

## The scene: approach(cells) -> "ok" | "unreachable" | "cancelled", labour(verb, cells, seconds).
var _body: Node
## Hides the parcel until the save is applied: before it, cleared obstacles would still show.
var _cover: ColorRect
var _cover_label: Label

## C-148: P0's Energy chip (the scene puts it in its top bar) and the open Energy card or panel ("" none).
var energy_chip: UiEnergyChip
var energy_modal := ""
var _energy_layer: Control
## Energy the key's action costs (0 none) and whether the player is short of it.
var key_cost := 0
var key_short := false

## `core` is the scene's built core obstacle layer: {plan, root, proxies, recipe}. `body` is the
## scene (C-73), `outer` the drawn outer layer, {layout, root, recipe} (its walk profiles are
## already bound).
func setup(data: Dictionary, walk: RefCounted, core: Dictionary, farm_store: RefCounted, canvas: CanvasLayer,
		body: Node = null, outer := {}) -> void:
	_data = data
	_body = body
	_walk = walk
	_core_plan = core.plan
	_recipe = core.get("recipe")
	_core_root = core.root
	_proxies = core.proxies
	store = farm_store
	rules = ParcelFarm.rules()
	for index in _core_plan.layout.size():
		var item: Dictionary = _core_plan.layout[index]
		_anchors[item.cell] = index
		for cell: Vector2i in item.get("cells", [item.cell]): _obstacles[cell] = item.cell
	_path = Space.protected_path(data)
	_gather = Gather.rules()
	if outer.get("root") is Node3D and outer.get("layout") is Array:
		_outer_layout = outer.layout
		_outer_root = outer.root
		var recipe = outer.get("recipe")
		var version := str(recipe.get("outer_groves", {}).get("version", "")) if recipe is Dictionary else ""
		gatherables = Gather.objects(_outer_layout, walk, data.block_id, _gather, version)
	_names = _item_names()
	_crop_art = CropArt.new(walk.point, data.cell_m)
	_crop_art.name = "ParcelCrops"
	add_child(_crop_art)
	livestock = Livestock.new()
	livestock.setup(walk)
	add_child(livestock)
	wet_soil_preview = bool(ProjectSettings.get_setting(WET_SOIL_SETTING, false))
	_build_marker()
	_build_ui(canvas)

## Opens the owner's farm: the first entry grants the welcome gift once (Q-39).
func enter() -> void:
	if rules.is_empty():
		unavailable = true
		_cover_label.text = OPEN_FAILED
		_toast.show_toast(OPEN_FAILED, ToastLayer.Severity.ERROR)
		return
	busy = true
	_cover_label.text = LOADING
	var result: Dictionary = await store.enter()
	# Entering twice is safe (the gift is granted once); a lost request is retried once before Retry shows.
	if result.get("code") == "NETWORK" and is_inside_tree(): result = await store.enter()
	busy = false
	if not is_inside_tree(): return
	_adopt(result)
	unavailable = farm.is_empty()
	_cover.visible = unavailable
	if unavailable: _cover_label.text = OPEN_FAILED
	_refresh_tip()
	if not result.get("ok", false):
		_toast.show_toast(OPEN_FAILED, ToastLayer.Severity.ERROR)
	elif not (result.get("gift", {}) as Dictionary).is_empty():
		# C-151: everything this entry gave: the first-entry gift and the one-off grants (the well blueprint, the pail).
		announce_gains(result.gift, _player_screen())
	elif result.get("granted", false):
		announce_gains(rules.welcome_gift, _player_screen())

## Core cells of the protected path (Space.protected_path), shared with house placement (C-33).
func protected_path() -> Dictionary:
	return _path

## Cells still holding a core obstacle; cleared ones are gone from the walk and the art.
func obstacle_cells() -> Dictionary:
	var cells := {}
	for cell: Vector2i in _obstacles: cells[cell] = true
	return cells

func server_now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) + _clock_offset_ms

## The save is applied; until then the parcel stays covered and the player does not move.
func loaded() -> bool:
	return not farm.is_empty()

## Called by the scene every frame with the player's cell in front; `steering`: the stick is in
## use. For gathering, also the player's position and facing direction.
func update(delta: float, facing_cell: Vector2i, steering: bool, player = null, facing := Vector3.ZERO) -> void:
	if steering:
		picked = null
		picked_object = -1
	target = job if job != null else (picked if picked != null else facing_cell)
	_placed = player is Vector3
	if _placed:
		_player = player
		_facing = facing
	# C-154: animals move; a laid drop in reach is picked up by itself (not while another command is out or a mode holds).
	if livestock != null and not farm.is_empty():
		var reached: Array = livestock.update(delta, _player, server_now(), busy or held or not _placed or not _picking.is_empty())
		if not reached.is_empty(): pick_up(reached)
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = REDRAW_S
		_draw_crops()
		_draw_gathered()
		_refresh_tip()
		_refresh_tasks()
	_refresh_key()
	_refresh_energy()

## A tap picks an outer object under the ray (`from`, `dir`), else that ground cell, until the
## player moves again. A tap landing on a core cell keeps that cell even when a tall outer
## object's bounds stand in front of it on the slanted view (V-127).
func pick(cell: Vector2i, from := Vector3.ZERO, dir := Vector3.ZERO) -> void:
	var on_core: bool = _data.by_cell.has(cell) and _data.by_cell[cell].zone == "core"
	picked_object = _object_on_ray(from, dir) if not on_core and not dir.is_zero_approx() else -1
	if picked_object >= 0: picked = null
	elif _data.by_cell.has(cell): picked = cell

## The gatherable whose bounds the ray meets first, or -1.
func _object_on_ray(from: Vector3, dir: Vector3) -> int:
	var best := -1
	var nearest := INF
	for i in gatherables.size():
		var hit = (gatherables[i].box as AABB).intersects_ray(from, dir)
		if hit is Vector3 and from.distance_to(hit) < nearest:
			nearest = from.distance_to(hit)
			best = i
	return best

## Ground-plane distance from the player to an object's bounds.
func gap(index: int) -> float:
	var box: AABB = gatherables[index].box
	var dx := maxf(maxf(box.position.x - _player.x, _player.x - box.end.x), 0.0)
	var dz := maxf(maxf(box.position.z - _player.z, _player.z - box.end.z), 0.0)
	return Vector2(dx, dz).length()

## The tapped object, else the one in reach the player faces most; ready ones before regrowing ones.
func gather_target() -> int:
	if picked_object >= 0: return picked_object
	if not _placed: return -1
	var best := -1
	var best_score := INF
	var now := server_now()
	for i in gatherables.size():
		var distance := gap(i)
		if distance > GATHER_REACH_M: continue
		var to: Vector3 = gatherables[i].origin - _player
		to.y = 0.0
		var score := distance - (0.35 * _facing.dot(to.normalized()) if to.length() > 0.001 else 0.35)
		if Gather.ready_at(_gather, farm, gatherables[i].id, now) > 0: score += 100.0
		if score < best_score:
			best_score = score
			best = i
	return best

## The key for gathering object `index`: {verb, refusal, command, object, ready_in_ms?}.
func _gather_action(index: int) -> Dictionary:
	var object: Dictionary = gatherables[index]
	var now := server_now()
	var ready := Gather.ready_at(_gather, farm, object.id, now)
	if ready > 0:
		return {"verb": "gather", "refusal": REGROWING, "command": {}, "object": index, "ready_in_ms": ready - now}
	if gap(index) > GATHER_REACH_M:
		return {"verb": "gather", "refusal": TOO_FAR, "command": {}, "object": index}
	return {"verb": "gather", "refusal": "", "command": {"type": "gather", "object": object.id}, "object": index}

func _refresh_key() -> void:
	if held:
		_marker.visible = false
		_keys.visible = false
		_bar.visible = false
		return
	current = {} if farm.is_empty() else Space.action(rules, _data, _path, _obstacles, farm, target, server_now())
	# C-154: a coop's floor is never farmed (no key there); at its feeder the key feeds.
	if not farm.is_empty() and livestock != null:
		if livestock.covers(target): current = {}
		var feeder := livestock.feeder_near(_player, FEED_REACH_M) if _placed else {}
		if not feeder.is_empty(): current = _feed_action(feeder)
	# A tapped object wins; a nearby one only when no cell was tapped and the cell in front has no step to do.
	var object := -1 if farm.is_empty() else gather_target()
	if object >= 0 and (picked_object >= 0 or (picked == null and (current.is_empty() or not str(current.refusal).is_empty()))):
		current = _gather_action(object)
	_marker.visible = not current.is_empty()
	_keys.visible = _marker.visible or farm.is_empty()
	key_cost = 0
	key_short = false
	if unavailable and not busy:
		_key.verb = "Retry"
		_key.cost = ""
		_key.state = UiSceneAction.State.DEFAULT
		return
	if farm.is_empty() or busy:
		_key.state = UiSceneAction.State.PENDING
		return
	if current.is_empty(): return
	var spot: Vector3 = _walk.point(target)
	if current.has("object"): spot = _walk.point(_walk.cell_at(gatherables[current.object].origin))
	if current.has("feeder"): spot = current.feeder
	_marker.position = spot + Vector3(0, 0.045, 0)
	var refused := not str(current.refusal).is_empty()
	_marker_material.albedo_color = Color(0.86, 0.32, 0.25, 0.42) if refused else Color(1, 0.98, 0.86, 0.42)
	# C-148: the price of what the key does (P0's key: `Sow` over `3 Energy`; free actions carry no price, LOCK-02).
	if not refused: key_cost = ParcelFarm.energy_cost(rules, current.command)
	key_short = key_cost > 0 and energy_value() < key_cost
	if current.refusal == Space.NOT_RIPE:
		_key.verb = "Growing"
		_key.cost = P0Logic.key_ready(float(current.ripe_in_ms))
	elif current.verb == "gather":
		_key.verb = "Regrowing" if current.refusal == REGROWING else "Gather"
		_key.cost = P0Logic.key_ready(float(current.ready_in_ms)) if current.refusal == REGROWING \
			else "Move closer" if current.refusal == TOO_FAR else _price()
	elif current.verb == "rest":
		_key.verb = VERBS.rest
		_key.cost = REFUSALS.get(current.refusal, "+%d Energy" % int(current.get("gain", 0)))
	elif current.verb == "feed":
		_key.verb = VERBS.feed
		_key.cost = str(current.refusal_text) if refused else _price()
	else:
		_key.verb = VERBS[current.verb]
		_key.cost = REFUSALS.get(current.refusal, _price())
	# The key's badge is the tool or item the press uses: the hoe for farming, the feed (a carrot) at a feeder.
	var badge: Texture2D = item_icon(str(current.feed_item)) if current.get("verb") == "feed" else _tool_badge()
	if _keys.tool_icon != badge: _keys.tool_icon = badge
	_key.state = UiSceneAction.State.UNAVAILABLE if refused else UiSceneAction.State.INSUFFICIENT if key_short \
		else UiSceneAction.State.DEFAULT

## The key's second line for a priced action: `3 Energy`, short of it `Need 3 Energy` (LOCK-10); free: none.
func _price() -> String:
	if key_cost <= 0: return ""
	return ("Need %d Energy" if key_short else "%d Energy") % key_cost

func _on_key() -> void:
	if held: return
	if unavailable and not busy:
		await enter()
		return
	if busy or current.is_empty(): return
	if key_short:
		# Short of Energy: the press opens the Energy card and sends nothing (LOCK-09 / LOCK-10).
		open_energy_card(key_cost, VERBS.get(current.verb, ""))
		return
	if not str(current.refusal).is_empty():
		var refusal := "Not ripe yet" if current.refusal == Space.NOT_RIPE else "Not ready yet" if current.refusal == REGROWING else _key.cost
		_toast.show_toast(refusal, ToastLayer.Severity.REFUSED)
		return
	if current.verb == "gather": await gather(current)
	elif current.verb == "feed": await feed(current)
	else: await work(target, current)

## One gather press (C-60): the object is already in reach, so the player only faces it and plays
## the hand-picking (harvest) labour clip while the command goes out (C-73's beat, no walk).
func gather(action: Dictionary) -> Dictionary:
	if _body == null: return await send(action.command)
	_body.labour("harvest", [_walk.cell_at(gatherables[action.object].origin)], LABOUR_S)
	return await send(action.command, LABOUR_S)

## The key at a livestock building's feeder (C-154): Feed, or why not (`Need 1 Carrot`, the art's `Hens are fed` /
## `Pick up eggs first`); {verb, refusal, refusal_text, command, feeder}.
func _feed_action(near: Dictionary) -> Dictionary:
	var b: Dictionary = near.building
	var refusal := ParcelFarm.feed_refusal(rules, farm, b, server_now())
	var rule := ParcelFarm.livestock_of(rules, b)
	var copy: Dictionary = LivestockArt.building_art(str(b.type)).get("copy", {})
	var text := ""
	match refusal:
		"NO_FEED": text = "Need 1 %s" % str(_names.get(str(rule.get("feed", "")), ParcelItems.name_of(str(rule.get("feed", "")))))
		"ANIMALS_FED": text = str(copy.get("fed", "Hens are fed"))
		"GROUND_FULL": text = str(copy.get("full", "Pick up eggs first"))
		"NOT_LIVESTOCK": text = "That didn't work."
	return {"verb": "feed", "refusal": refusal, "refusal_text": text, "feed_item": str(rule.get("feed", "")),
		"command": {"type": "feed", "building": int(b.id)} if refusal.is_empty() else {}, "feeder": near.point}

## One feed press (C-154): the feeder is already in reach, so the player faces it and plays the labour clip while
## the command goes out; the fed hen then comes to peck (ParcelLivestock).
func feed(action: Dictionary) -> Dictionary:
	if _body == null: return await send(action.command)
	_body.labour("harvest", [_walk.cell_at(action.feeder)], LABOUR_S)
	return await send(action.command, LABOUR_S)

## Picks up the drops in reach (C-154): each flies into the player as the pick_up goes out; with the reply the items
## fly on into the Bag (`+1 Egg`, one float and flight per item, merged as ×N). A refused or lost pickup puts the
## drops back; they are taken again only after the player steps away (no retry loop while standing there).
func pick_up(ids: Array) -> void:
	if ids.is_empty() or busy: return
	_picking = ids.duplicate()
	for id: int in ids: livestock.fly(id, _player)
	var started := Time.get_ticks_msec()
	var before: Dictionary = farm.get("bag", {}).duplicate()
	busy = true
	var result: Dictionary = await store.send(farm_version, ids.map(func(id): return {"type": "pick_up", "drop": id}))
	busy = false
	if not is_inside_tree(): return
	# The gain lands once the drops reach the player (the flight's first half), however fast the reply came.
	var flight_ms := int(float(LivestockArt.pickup().flight_s) * 1000.0)
	if Time.get_ticks_msec() - started < flight_ms:
		await get_tree().create_timer((flight_ms - (Time.get_ticks_msec() - started)) / 1000.0).timeout
		if not is_inside_tree(): return
	_adopt(result)
	var ok: bool = result.get("ok", false)
	livestock.settle(ids, not ok and result.get("code") != "VERSION_CONFLICT")
	_picking = []
	if ok:
		var gains := {}
		for id: String in farm.bag:
			var gained := int(farm.bag.get(id, 0)) - int(before.get(id, 0))
			if gained > 0: gains[id] = gained
		announce_gains(gains, _player_screen())

## One press on `cell` (C-73): walk beside it, face it, play the labour clip and send the command
## with it. Nothing is sent when the player cannot get there or steers away first.
func work(cell: Vector2i, action: Dictionary) -> Dictionary:
	if _body == null: return await send(action.command)
	busy = true
	job = cell
	var cells := work_cells(cell, action)
	var reached: String = await _body.approach(cells)
	if not is_inside_tree(): return {"ok": false, "code": "LEFT"}
	if reached != "ok":
		busy = false
		job = null
		if reached == "unreachable": _toast.show_toast(UNREACHABLE, ToastLayer.Severity.REFUSED)
		return {"ok": false, "code": reached.to_upper()}
	# C-151: Fill and Water play C-153's pail actions, as long as they last (the scene's labour_seconds).
	var seconds: float = _body.labour_seconds(action.verb, LABOUR_S) if _body.has_method("labour_seconds") else LABOUR_S
	_body.labour(action.verb, cells, seconds)
	var result := await send(action.command, seconds)
	job = null
	return result

## The cells one press works: the whole block of an obstacle (a tree covers four), else the cell.
func work_cells(cell: Vector2i, action: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	# Rest (C-148): the middle of the cottage's door row, so the player stands at the door.
	var door = Space.door_cell(farm) if action.get("verb") == "rest" else null
	if door != null: cells.append(door)
	# Fill (C-151): the well's own cells, so the player walks up beside the well.
	if action.get("verb") == "fill":
		var wells := Space.well_cells(rules, farm)
		for at: Vector2i in wells:
			if wells[at] == action.get("building"): cells.append(at)
	if action.get("verb") == "clear" and _obstacles.has(cell):
		for at: Vector2i in _obstacles:
			if _obstacles[at] == _obstacles[cell]: cells.append(at)
	if cells.is_empty(): cells.append(cell)
	return cells

## Sends one command; the store's reply replaces the local farm either way. `hold_s`: the reply is
## shown no sooner than this after sending (the labour clip's length).
func send(command: Dictionary, hold_s := 0.0) -> Dictionary:
	busy = true
	var shown_at := Time.get_ticks_msec() + int(hold_s * 1000.0)
	var before: Dictionary = farm.get("bag", {}).duplicate()
	var energy_before := energy_value()
	var result: Dictionary = await store.send(farm_version, [command])
	if is_inside_tree() and Time.get_ticks_msec() < shown_at:
		await get_tree().create_timer((shown_at - Time.get_ticks_msec()) / 1000.0).timeout
	busy = false
	if not is_inside_tree(): return result
	_adopt(result)
	if result.get("ok", false):
		if command.type in ["harvest", "gather"]:
			var gains := {}
			for id: String in farm.bag:
				var gained := int(farm.bag.get(id, 0)) - int(before.get(id, 0))
				if gained > 0: gains[id] = gained
			announce_gains(gains, _gain_screen(command))
		var cost := ParcelFarm.energy_cost(rules, command)
		announce_energy(-cost if cost > 0 else energy_value() - energy_before if command.type == "rest" else 0, _gain_screen(command))
	elif result.get("code") == "NO_ENERGY":
		# The server's clock disagreed with the key's: the same card as a short key (LOCK-09).
		var detail: Dictionary = result.get("detail", {})
		open_energy_card(int(detail.get("need", ParcelFarm.energy_cost(rules, command))), VERBS.get(_verb_of(command), ""))
	elif result.get("code") == "VERSION_CONFLICT":
		_toast.show_toast("Your farm was updated. Try again.", ToastLayer.Severity.INFO)
	elif result.get("code") == "NOT_RESPAWNED":
		_toast.show_toast("Not ready yet", ToastLayer.Severity.REFUSED)
	elif result.get("code") in POUR_REFUSALS:
		_toast.show_toast(REFUSALS[POUR_REFUSALS[result.code]], ToastLayer.Severity.REFUSED)
	else:
		_toast.show_toast("That didn't work.", ToastLayer.Severity.REFUSED)
	return result

# ------------------------------------------------------------------ Energy (C-148)

## The farm's Energy now (server time), settled on a copy; 0 before the save is read.
func energy_now() -> Dictionary:
	if farm.is_empty() or rules.is_empty(): return {}
	var probe := farm.duplicate()
	var now := server_now()
	var e := ParcelFarm.settle_energy(rules, probe, now)
	return {"value": int(e.value), "max": ParcelFarm.max_energy(rules, probe), "next_in": ParcelFarm.next_tick_in(rules, probe, now),
		"regen_ms": ParcelFarm.regen_ms(rules, probe, now), "blessing_left": ParcelFarm.blessing_left(rules, probe, now),
		"rested": ParcelFarm.rested_today(rules, probe, now), "resets_in": ParcelFarm.next_rollover(rules, now) - now}

func energy_value() -> int:
	return int(energy_now().get("value", 0))

## The facts P0's Energy views read (P0Logic.energy_card / energy_panel / hud_state), from the parcel's own save:
## its Energy, the day's one Rest, the Newcomer time; no dishes, fish or tea here (those tiles stay greyed, as P0's).
func energy_view() -> Dictionary:
	var e := energy_now()
	var view := {"energy": {"value": e.get("value", 0), "max": e.get("max", 200), "next_in": e.get("next_in"),
		"regen_ms": e.get("regen_ms", 240000)}, "bag": {"slots": []}, "coins": int(farm.get("coins", 0)),
		"rest": {"used": 1 if e.get("rested", false) else 0, "limit": 1, "resets_in": e.get("resets_in", 0),
			"amount": int(rules.get("energy", {}).get("rest_amount", 60))}}
	if int(e.get("blessing_left", 0)) > 0:
		view.blessing = {"left": e.blessing_left, "regen_mult": float(rules.energy.blessing.regen_mult)}
	return view

## The top bar's chip follows the settled value every frame: `+1 in 2:41` ticks locally between replies (§3.7.1).
func _refresh_energy() -> void:
	if energy_chip == null: return
	var e := energy_now()
	energy_chip.visible = not e.is_empty()
	if e.is_empty(): return
	# The HUD's third line as P0Logic.hud_state words it: `+1 in 2:41`, or `Full`.
	var regen := "Full" if e.next_in == null else "+1 in " + P0Logic.duration(float(e.next_in))
	energy_chip.show_energy(int(e.value), int(e.max), regen, key_cost if key_short else 0)

## P0's Energy card (LOCK-09) for an action short of Energy: facts, the RECOVER tiles that only guide, and the one
## button `Free to do now` that closes it. Only Rest is on the parcel today; away from a cottage it reads `At home`.
## Its guide `Show home` (q(30) before a bench) turns the camera to the cottage.
func open_energy_card(need: int, verb: String) -> void:
	close_energy()
	var facts := P0Logic.energy_card(energy_view(), need, verb, ParcelFarm.has_home(farm))
	for t: Dictionary in facts.tiles:
		t.icon = P0Logic.icon(str(t.icon))
		if t.go == "bench":
			t.guide = "Show home"
			t.go = "home"
	var card := UiEnergyCard.card(facts)
	card.name = "EnergyCard"
	card.free_pressed.connect(close_energy)
	card.tile_pressed.connect(func(go: String):
		close_energy()
		if go == "home" and _body != null and _body.has_method("show_house"): _body.show_house())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)
	_open_energy_layer(center, SCRIM)
	energy_modal = "card"

## Tapping the Energy chip: P0's Energy panel under it (LOCK-09): the pool, the day's Rest, the Newcomer Blessing.
## Meals come with cooking (0.4.7), so their tile is left out here.
func open_energy_panel() -> void:
	if farm.is_empty(): return
	close_energy()
	var facts := P0Logic.energy_panel(energy_view())
	facts.uses = facts.uses.filter(func(u: Dictionary): return u.name != "Meals")
	for u: Dictionary in facts.uses: u.icon = P0Logic.icon(str(u.icon))
	if not facts.blessing.is_empty():
		facts.blessing.detail = "Energy returns %s× faster" % str(snappedf(float(rules.energy.blessing.regen_mult), 0.1))
	var panel := UiEnergyCard.panel(facts)
	panel.name = "EnergyPanel"
	var chip := energy_chip.visual_rect()
	var width := _ui.size.x
	var x := clampf(chip.position.x - UiTokens.SPACE_WITHIN, UiTokens.SIZE_HUD_X, maxf(UiTokens.SIZE_HUD_X, width - UiTokens.SIZE_ENERGY_PANEL_W - UiTokens.SIZE_HUD_X))
	panel.position = Vector2(x, chip.end.y + UiTokens.SPACE_ROW)
	panel.pointer_x = chip.get_center().x - x
	_open_energy_layer(panel, Color(SCRIM, 0.0))
	energy_modal = "panel"

func _open_energy_layer(content: Control, scrim: Color) -> void:
	_bar.cancel_drag()
	_energy_layer = Control.new()
	_energy_layer.name = "EnergyLayer"
	_energy_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_energy_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var veil := ColorRect.new()
	veil.name = "Scrim"
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = scrim
	veil.gui_input.connect(func(event: InputEvent):
		if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed: close_energy())
	_energy_layer.add_child(veil)
	_energy_layer.add_child(content)
	_ui.add_child(_energy_layer)
	_ui.move_child(_toast, -1)

## Closes the Energy card or panel; false when neither was open.
func close_energy() -> bool:
	if _energy_layer == null: return false
	_energy_layer.queue_free()
	_energy_layer = null
	energy_modal = ""
	return true

## The Energy a reply spent or gave as one float over what it was spent on: `−3 Energy` / `+60 Energy` (P0's tones).
func announce_energy(delta: int, from: Vector2) -> void:
	if delta == 0: return
	var line := UiGainFloat.new(("+%d Energy" if delta > 0 else "−%d Energy") % absi(delta),
		UiGainFloat.Tone.ENERGY_GAIN if delta > 0 else UiGainFloat.Tone.ENERGY_COST)
	line.name = "EnergyFloat"
	line.theme = UiKit.theme()
	_ui.add_child(line)
	line.play(from - Vector2(0, FLOAT_ABOVE * 2.0), 0)

## The key's verb for a command (the Energy card's `Sow needs 3 Energy`).
static func _verb_of(command: Dictionary) -> String:
	return {"clear_obstacle": "clear", "till": "till", "sow": "sow", "gather": "gather", "rest": "rest", "feed": "feed",
		"draw_water": "fill", "water": "water"}.get(command.get("type", ""), "")

func _adopt(result: Dictionary) -> void:
	var next := ParcelFarm.normalize(result.get("farm"))
	if next.is_empty(): return
	if result.get("server_time") is int or result.get("server_time") is float:
		_clock_offset_ms = int(result.server_time) - int(Time.get_unix_time_from_system() * 1000.0)
	farm = next
	farm_version = int(result.get("farm_version", farm_version))
	_drop_cleared()
	_draw_crops()
	_draw_gathered()
	if livestock != null: livestock.sync(farm, rules, server_now())
	_draw_bag()
	_refresh_tip()
	_refresh_tasks()
	state_changed.emit(farm.duplicate(true))

## Cleared obstacles leave the walk and the art (the layer is redrawn without them).
func _drop_cleared() -> void:
	var gone := {}
	for key: String in farm.cleared:
		var cell = ParcelFarm.parse_key(key)
		if cell != null and _anchors.has(cell) and not _removed.has(cell): gone[cell] = true
	if gone.is_empty(): return
	var remaining := {"layout": _core_plan.layout.filter(func(item): return not _removed.has(item.cell) and not gone.has(item.cell))}
	var art := Scenery.build(remaining, _walk, _recipe, false)
	if not art.ok: return
	# Release the walk only once the redrawn art exists, so art and walk never disagree.
	for cell: Vector2i in gone:
		var proxy = _proxies[_anchors[cell]]
		if proxy != null: _walk.remove_prop(proxy)
		_removed[cell] = true
	art.root.name = _core_root.name
	var parent := _core_root.get_parent()
	var index := _core_root.get_index()
	parent.remove_child(_core_root)
	_core_root.free()
	parent.add_child(art.root)
	parent.move_child(art.root, index)
	_core_root = art.root
	for cell: Vector2i in _obstacles.keys():
		if _removed.has(_obstacles[cell]): _obstacles.erase(cell)

## Redraws the outer layer when the set of gathered objects changes: picked trees and rocks
## fade, picked flowers (non-blocking) are hidden, all come back once grown. Art only: the walk
## keeps every profile bound at load, so reach and collision never change.
func _draw_gathered() -> void:
	if _outer_root == null or farm.is_empty(): return
	var now := server_now()
	var spent := {}
	for object: Dictionary in gatherables:
		if Gather.ready_at(_gather, farm, object.id, now) > 0: spent[object.index] = true
	if spent == _spent: return
	var fresh := []
	var faded := []
	for i in _outer_layout.size():
		if not spent.has(i): fresh.append(_outer_layout[i])
		elif _outer_layout[i].solid: faded.append(_outer_layout[i])
	var art := Scenery.build({"layout": fresh}, _walk, _recipe, false)
	var picked_art := Scenery.build({"layout": faded}, _walk, _recipe, false)
	if not art.ok or not picked_art.ok:
		for built: Dictionary in [art, picked_art]:
			if built.ok: built.root.free()
		return
	_spent = spent
	for child in _outer_root.get_children():
		_outer_root.remove_child(child)
		child.queue_free()
	for child in art.root.get_children():
		art.root.remove_child(child)
		_outer_root.add_child(child)
	if _spent_material == null:
		_spent_material = ShaderMaterial.new()
		_spent_material.shader = GATHERED_SHADER
	for child in picked_art.root.get_children():
		picked_art.root.remove_child(child)
		child.name = "Gathered" + child.name
		(child as GeometryInstance3D).material_override = _spent_material
		_outer_root.add_child(child)
	art.root.free()
	picked_art.root.free()

func _draw_crops() -> void:
	if farm.is_empty(): return
	var soil := {}
	# C-151: a watered crop's cell is wet; tilled soil with nothing sown, or a crop not watered yet, is dry.
	for key: String in farm.tilled:
		var crop = farm.crops.get(key)
		var wet: bool = crop is Dictionary and not ParcelFarm.is_dry(crop)
		soil[key] = CropArt.WET if wet or wet_soil_preview else CropArt.DRY
	_crop_art.sync(soil, farm.crops, server_now())

## The bag's items in bar order: the farming items first, then anything else with a name.
func bag_ids() -> Array:
	var ids: Array = BAG_ORDER.filter(func(id): return int(farm.get("bag", {}).get(id, 0)) > 0)
	for id: String in farm.get("bag", {}):
		if id not in ids and _names.has(id) and int(farm.bag[id]) > 0: ids.append(id)
	return ids

## Quick bar and bag drawer follow the save: counts change as each reply lands.
func _draw_bag() -> void:
	var ids := bag_ids()
	var slots := []
	for id: String in ids:
		if slots.size() >= UiQuickBar.SLOTS: break
		slots.append({"id": id, "icon": item_icon(id), "title": _names.get(id, id), "quantity": int(farm.bag[id])})
	_bar.slots = slots
	if _bag == null and phone == null: _bar.visible = not farm.is_empty() and not held
	_keys.tool_icon = _tool_badge()
	if _bag != null: _draw_bag_slots(ids)

## The key's tool badge: the hoe while the bag holds it.
func _tool_badge() -> Texture2D:
	return item_icon(str(rules.get("till_tool", ""))) if int(farm.get("bag", {}).get(str(rules.get("till_tool", "")), 0)) > 0 else null

## The bag panel's slots follow the save: one per item in the bag's order, then empty ones to fill the rows.
func _draw_bag_slots(ids: Array) -> void:
	var count := maxi(BAG_MIN_SLOTS, ceili(float(ids.size()) / BAG_COLUMNS) * BAG_COLUMNS)
	while _slots.get_child_count() < count:
		var slot := UiBagSlot.new()
		slot.tapped.connect(_on_bag_slot)
		_slots.add_child(slot)
	while _slots.get_child_count() > count:
		var extra := _slots.get_child(_slots.get_child_count() - 1)
		_slots.remove_child(extra)
		extra.queue_free()
	_bag_slots = {}
	for i in count:
		var slot := _slots.get_child(i) as UiBagSlot
		if i < ids.size():
			var id: String = ids[i]
			slot.name = "Slot_" + id
			slot.item = {"id": id, "icon": item_icon(id), "qty": int(farm.bag[id])}
			_bag_slots[id] = slot
		else:
			slot.name = "Slot_%d" % i
			slot.item = {}
	if not _bag_slots.has(bag_selected): bag_selected = ""
	_show_selected()

## A tap selects an item (its ring, its name under the slots); the same one again clears it.
func _on_bag_slot(id: String) -> void:
	select_bag_item("" if id == bag_selected else id)

func select_bag_item(id: String) -> void:
	bag_selected = id if _bag_slots.has(id) else ""
	_show_selected()

func _show_selected() -> void:
	for id: String in _bag_slots:
		(_bag_slots[id] as UiBagSlot).state = UiBagSlot.State.SELECTED if id == bag_selected else UiBagSlot.State.FILLED
	if _picked_name != null:
		_picked_name.text = "" if bag_selected == "" else "%s ×%d" % [_names.get(bag_selected, bag_selected),
			int(farm.get("bag", {}).get(bag_selected, 0))]

## An item's icon: the parcel's adapter (ParcelItems, C-59: blueprints show the recipe card), else the main farm's.
func item_icon(id: String) -> Texture2D:
	return ParcelItems.icon_of(id)

## A gain (the welcome gift, a harvest; C-33's blueprints and C-59 / C-60 later): one float line per item rising from
## `from` (screen point of what gave it) and the item flying into the quick bar's Bag, which bumps as it lands.
## Items without a name or icon in the content table are skipped.
func announce_gains(gains: Dictionary, from: Vector2) -> void:
	last_gains = {}
	var lines := 0
	for id: String in gains:
		var count := int(gains[id])
		if count <= 0 or not _names.has(id): continue
		last_gains[id] = count
		var icon := item_icon(id)
		var line := UiGainFloat.new("+%d %s" % [count, _names[id]], UiGainFloat.Tone.ITEM, icon)
		line.name = "Gain_" + id
		line.theme = UiKit.theme()
		_ui.add_child(line)
		line.play(from - Vector2(0, FLOAT_ABOVE), lines)
		var bag := _bar.bag_end()
		UiItemFly.launch(_ui, from, bag, icon, count, lines * UiItemFly.DELAY_STEP_S, func(): UiItemFly.bump(bag))
		lines += 1
	if lines > 0: _draw_bag()

func _player_screen() -> Vector2:
	if _body != null and _body.has_method("screen_point"): return _body.screen_point(_body.player_position(), 1.9)
	return _ui.size * Vector2(0.5, 0.42)

## Where a command's gain rises from: the harvested cell, the gathered object (C-60), else the player.
func _gain_screen(command: Dictionary) -> Vector2:
	if command.has("cell"):
		var cell = ParcelFarm.parse_key(str(command.cell))
		if cell != null: return _cell_screen(cell)
	if command.has("object") and _body != null and _body.has_method("screen_point"):
		for object: Dictionary in gatherables:
			if object.id == command.object: return _body.screen_point(object.origin, 0.6)
	return _player_screen()

func _cell_screen(cell: Vector2i) -> Vector2:
	if _body != null and _body.has_method("screen_point"): return _body.screen_point(_walk.point(cell), 0.3)
	return _player_screen()

## Opens the bag (UI v3 C-P1–C-P7, C-L4): the modal panel over the scrim with the bag's items in round slots, three
## to a row; the quick bar slides away (M-16) and comes back on close. A tap on a slot selects it and names it under
## the slots. ✕, a tap on the scrim or Android Back (the host asks close_modal() first) close it.
func open_bag(focus := "") -> void:
	if _bag != null or farm.is_empty(): return
	_bar.cancel_drag()
	close_phone()
	_bag = UiModalPanel.new("Bag", BAG_HERO)
	_bag.name = "BagPanel"
	_bag.close_requested.connect(close_bag)
	_slots = GridContainer.new()
	_slots.name = "BagSlots"
	_slots.columns = BAG_COLUMNS
	_slots.add_theme_constant_override(&"h_separation", int(UiTokens.SIZE_PANEL_SLOT_GAP))
	_slots.add_theme_constant_override(&"v_separation", int(UiTokens.SIZE_PANEL_ROW_GAP))
	_bag.body.add_child(_slots)
	_picked_name = UiKit.label("", UiTokens.STYLE_TYPE_CAPTION, UiTokens.COLOR_TEXT_SECONDARY)
	_picked_name.name = "PickedName"
	_picked_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bag.body.add_child(_picked_name)
	_ui.add_child(_bag)
	_ui.move_child(_toast, -1)
	bag_selected = ""
	_draw_bag()
	if focus != "": select_bag_item(focus)
	_bag.open()
	UiMotion.bar_shown(_bar, false, _bar.position.y)
	_refresh_tip()

## Closes the bag (M-05, input released at once); the quick bar comes back (M-16).
func close_bag() -> bool:
	if _bag == null: return false
	_bag.close()
	_bag = null
	_slots = null
	_bag_slots = {}
	_picked_name = null
	bag_selected = ""
	_place_bar()
	if not farm.is_empty() and not held:
		var rest := _bar.position.y
		_bar.position.y = rest + UiMotion.BAR_HIDE_Y
		UiMotion.bar_shown(_bar, true, rest)
	_refresh_tip()
	return true

func bag_open() -> bool: return _bag != null

func _item_names() -> Dictionary:
	var content := P0Logic.content()
	var names := {}
	for crop: Dictionary in content.get("crops", []):
		names[str(crop.get("id", ""))] = str(crop.get("name", ""))
		names[str(crop.get("seed", ""))] = str(crop.get("seed_name", ""))
	names.merge(content.get("tools", {}).get("names", {}))
	for id: String in content.get("materials", {}):
		names[id] = str(content.materials[id].get("name", ""))
	var wanted := {}
	var gathered_items := []
	for source: Dictionary in _gather.get("sources", {}).values(): gathered_items.append(source.item)
	for id: String in BAG_ORDER + rules.get("welcome_gift", {}).keys() + gathered_items:
		if names.has(id) and not str(names[id]).is_empty(): wanted[id] = names[id]
	for id: String in ParcelItems.NAMES: wanted[id] = ParcelItems.NAMES[id]
	return wanted

func _build_marker() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * _data.cell_m * 0.94
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker = MeshInstance3D.new()
	_marker.name = "TargetCell"
	_marker.mesh = plane
	_marker.material_override = _marker_material
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)

func _build_ui(canvas: CanvasLayer) -> void:
	# Over the world and the stick, under the scene's header (Back) and the farming UI.
	_cover = ColorRect.new()
	_cover.name = "LoadingCover"
	_cover.theme = UiKit.theme()
	_cover.color = UiTokens.COLOR_SURFACE
	_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(_cover)
	canvas.move_child(_cover, mini(1, canvas.get_child_count() - 1))
	_cover_label = UiKit.label(LOADING, UiTokens.STYLE_BODY_B14)
	_cover_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cover_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cover.add_child(_cover_label)
	# The main farm's world controls (P0Ui._build_bar / _build_fab), on the UI kit theme.
	_ui = Control.new()
	_ui.name = "FarmingUi"
	_ui.theme = UiKit.theme()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_ui)
	_bar = UiQuickBar.new()
	_bar.bag_icon = UiArt.SYS_BAG
	_bar.name = "QuickBar"
	_bar.haptics = OS.has_feature("mobile")
	_bar.visible = false
	_bar.slot_tapped.connect(func(id: String): open_bag(id))
	_bar.ghost_tapped.connect(func(_i: int): open_bag())
	_bar.bag_requested.connect(func(): open_bag())
	_bar.close_requested.connect(close_bag)
	# The bar follows the bag's order and the parcel save keeps no bar layout, so the main farm's long-press drag
	# (swap, Pin, Remove) has nothing to change here: the cells' drag gestures are not passed to the bar (C-74#39).
	# Taps still select, and a swipe up still opens the bag.
	for cell: UiItemCell in _bar.cells():
		for connection: Dictionary in cell.get_signal_connection_list(&"gesture"):
			if (connection.callable as Callable).get_object() == _bar: cell.gesture.disconnect(connection.callable)
		cell.gesture.connect(func(outcome: Dictionary): if outcome.get("kind") == &"swipe_up": open_bag())
	_ui.add_child(_bar)
	_keys = UiActionKey.new()
	_keys.name = "ActionKey"
	_keys.switch_visible = false   # one action here: no switch key, no radial
	_keys.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ui.add_child(_keys)
	_key = _keys.key()
	_key.name = "MainKey"
	_key.pressed_down.connect(_on_key)
	# C-148: the main HUD's Energy chip; the scene puts it in its top bar (it is not under _ui).
	energy_chip = UiEnergyChip.new()
	energy_chip.name = "Energy"
	energy_chip.theme = UiKit.theme()
	energy_chip.visible = false
	energy_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	energy_chip.pressed.connect(open_energy_panel)
	# C-107: the task button (C-H3; the scene puts it in its top bar), its drop-down under the bar (C-T1) and the phone
	# button at the right above the action key (C-L3).
	task_button = UiTaskButton.new()
	task_button.name = "Tasks"
	task_button.visible = false
	task_button.pressed.connect(toggle_tasks)
	drop_down = UiTaskDropDown.new()
	drop_down.name = "TaskDropDown"
	drop_down.more_pressed.connect(func(): open_phone(Phone.TASKS_TAB))
	drop_down.folded.connect(_refresh_tip)
	_ui.add_child(drop_down)
	phone_button = UiGlassButton.new(UiArt.sys("phone"))
	phone_button.name = "PhoneButton"
	phone_button.visible = false
	phone_button.pressed.connect(func(): open_phone())
	_ui.add_child(phone_button)
	_toast = ToastLayer.new()
	_toast.name = "Toast"
	_ui.add_child(_toast)
	_toast.anchor_above(_bar)
	# Centred under the top bar in a container, which lays the wrapping sentence out at the card's width.
	_tip_box = CenterContainer.new()
	_tip_box.name = "TipRow"
	_tip_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_ui.add_child(_tip_box)
	_tip = UiTipCard.new()
	_tip.name = "Tip"
	_tip.visible = false
	_tip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_tip.tapped.connect(func():
		_tip_closed = tip_step
		_refresh_tip())
	_tip_box.add_child(_tip)
	_ui.move_child(_toast, -1)
	_ui.resized.connect(_place_bar)
	_place_bar.call_deferred()

## Bottom controls as the main farm's (BAR-1, P0Ui._place_controls): the bar at x 12, 24 above the safe bottom; the
## action key 16 from the right, 40 above the bar.
func _place_bar() -> void:
	if not is_inside_tree(): return
	var bottom := UiTokens.SIZE_QUICK_BAR_BOTTOM + _safe_bottom()
	_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_bar.offset_left = UiTokens.SIZE_QUICK_BAR_X
	_bar.offset_right = UiTokens.SIZE_QUICK_BAR_X + UiTokens.SIZE_QUICK_BAR_W
	_bar.offset_bottom = -bottom
	_bar.offset_top = -bottom - UiTokens.SIZE_QUICK_BAR_H
	var key_bottom := bottom + UiTokens.SIZE_QUICK_BAR_H + KEY_ABOVE_BAR
	if is_instance_valid(_side_button):
		# Left of the action key on its baseline: clear of the quick bar under it and of the key (C-74#17).
		_side_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_side_button.offset_left = UiTokens.SIZE_QUICK_BAR_X
		_side_button.offset_right = UiTokens.SIZE_QUICK_BAR_X + _side_button.custom_minimum_size.x
		_side_button.offset_bottom = -key_bottom
		_side_button.offset_top = -key_bottom - _side_button.custom_minimum_size.y
	_keys.offset_right = -UiTokens.SPACE_PAGE
	_keys.offset_left = -UiTokens.SPACE_PAGE - UiTokens.SIZE_ACTION_KEY_W
	_keys.offset_bottom = -key_bottom
	_keys.offset_top = -key_bottom - UiTokens.SIZE_ACTION_KEY_H
	# C-107: the phone button right-aligned 12 (its Ø36 glass, in a 44 hit area) above the action key (C-L3).
	var inset := (UiTokens.SIZE_TOUCH_MIN - UiTokens.SIZE_HUD_SIDE_BUTTON) * 0.5
	var phone_bottom := key_bottom + UiTokens.SIZE_ACTION_KEY_H + PHONE_BUTTON_GAP - inset
	phone_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	phone_button.offset_right = -UiTokens.SIZE_SCREEN_EDGE + inset
	phone_button.offset_left = phone_button.offset_right - UiTokens.SIZE_TOUCH_MIN
	phone_button.offset_bottom = -phone_bottom
	phone_button.offset_top = -phone_bottom - UiTokens.SIZE_TOUCH_MIN
	drop_down.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_place_drop_down()
	if phone != null: _place_phone()

## The guide's card (C-35): the current step's sentence while nothing else holds the screen. A tap closes it until
## the next step; finishing the step moves it on.
func _refresh_tip() -> void:
	if _tip == null: return
	var step := "" if unavailable else Guide.step(farm, server_now())
	if step != tip_step:
		tip_step = step
		if step != _tip_closed: _tip_closed = ""
		if not step.is_empty(): _tip.show_tip(Guide.text(step))
	_tip.visible = not tip_step.is_empty() and tip_step != _tip_closed and not held and _bag == null and phone == null \
		and not (drop_down != null and drop_down.showing)
	# Under the top bar (the main farm puts its TipCard under the HUD, clear of the key and the bar).
	if _tip.visible: _tip_box.offset_top = tip_top if tip_top >= 0.0 else TIP_TOP + _safe_top()

# ------------------------------------------------------------------ Tasks and the phone (C-107)

## The drop-down's rows: up to three ending at the current task (the two before it done), so the next step is in view;
## `More…` opens the phone for the rest. {rows: [{title, state}], done: rows done above the window, start}.
func drop_rows() -> Dictionary:
	var rows := Tasks.rows(farm, server_now(), _reached())
	var done := Tasks.done_count(farm, server_now(), _reached())
	var start := clampi(done - (UiTaskDropDown.MAX_ROWS - 1), 0, maxi(0, rows.size() - UiTaskDropDown.MAX_ROWS))
	var shown := []
	for row: Dictionary in rows.slice(start, start + UiTaskDropDown.MAX_ROWS):
		shown.append({"title": row.title, "key": row.key, "state": UiTaskRow.State.DONE if row.state == "done"
			else UiTaskRow.State.CURRENT if row.state == "current" else UiTaskRow.State.TODO})
	return {"rows": shown, "done": done, "start": start, "more": rows.size() > UiTaskDropDown.MAX_ROWS}

## The task button: drops the rows under the top bar (no scrim, the scene plays on), or folds them.
func toggle_tasks() -> void:
	if drop_down.showing:
		drop_down.fold()
		return
	if farm.is_empty() or held: return
	_open_drop_down()
	_mark_seen()

func _open_drop_down() -> void:
	var view := drop_rows()
	_drop_done = view.done
	_place_drop_down()
	drop_down.open(view.rows, view.more)
	_refresh_tip()

## The drop-down's rows from the bar's left edge, 10 under it (C-T1).
func _place_drop_down() -> void:
	drop_down.offset_left = UiTokens.SIZE_SCREEN_EDGE
	var top := bar_bottom if bar_bottom >= 0.0 else TIP_TOP - UiTokens.SPACE_PAGE + _safe_top()
	drop_down.offset_top = top + DROP_DOWN_GAP

## Opens the phone on `tab` (M-08 from its button; the quick bar slides away, M-16): Tasks, Inbox or Collection.
func open_phone(tab := Phone.TASKS_TAB) -> void:
	if phone != null or farm.is_empty() or held: return
	close_bag()
	close_energy()
	drop_down.fold()
	_bar.cancel_drag()
	phone = Phone.new()
	phone.close_requested.connect(close_phone)
	phone.task_pressed.connect(_on_task_pressed)
	_ui.add_child(phone)
	_ui.move_child(_toast, -1)
	phone.refresh(Tasks.rows(farm, server_now(), _reached()), {}, [])
	_place_phone()
	phone.show_tab(tab)
	phone.open()
	_mark_seen()
	UiMotion.bar_shown(_bar, false, _bar.position.y)
	_refresh_tip()

## Closes the phone (M-09, input released at once); the quick bar comes back (M-16). False when it was not open.
func close_phone() -> bool:
	if phone == null: return false
	phone.close()
	phone = null
	_place_bar()
	if not farm.is_empty() and not held and _bag == null:
		var rest := _bar.position.y
		_bar.position.y = rest + UiMotion.BAR_HIDE_Y
		UiMotion.bar_shown(_bar, true, rest)
	_refresh_tip()
	return true

func phone_open() -> bool: return phone != null

## C-L5: right 14, its bottom 8 above the phone button; on a short screen it may cover the top bar (under its scrim),
## never past the safe top.
func _place_phone() -> void:
	var glass_top := phone_button.position.y + (UiTokens.SIZE_TOUCH_MIN - UiTokens.SIZE_HUD_SIDE_BUTTON) * 0.5
	phone.place(Vector2(_ui.size.x - PHONE_RIGHT, glass_top - PHONE_ABOVE_BUTTON), UiTokens.SIZE_SCREEN_SAFE_INSET + _safe_top())

## The current row tapped in the phone: the phone closes and that step's tip shows again (C-85 ⑧-B), nothing more.
func _on_task_pressed(key: String) -> void:
	close_phone()
	if key == Guide.step(farm, server_now()):
		_tip_closed = ""
		tip_step = ""
		_refresh_tip()

## Buttons follow the save: shown once it is read and nothing holds the screen; a task not yet seen marks both. A step
## done while the drop-down is up plays its finishing beat there, and the rows move on a second later.
func _refresh_tasks() -> void:
	if task_button == null: return
	var ready := not farm.is_empty() and not held
	task_button.visible = ready
	phone_button.visible = ready
	if not ready: return
	var done := Tasks.done_count(farm, server_now(), _reached())
	# Follows the count both ways: it holds itself up only on Sell what you gathered, so a lower count is a reset parcel.
	if done != tasks_reached:
		tasks_reached = done
		_keep_local()
	var current := Tasks.current(farm, server_now(), _reached())
	var fresh := not current.is_empty() and current != _seen()
	task_button.badge = fresh
	phone_button.badge = fresh
	if drop_down.showing and _drop_done >= 0 and done > _drop_done:
		# The finished row is the one that was current in the rows still showing.
		var index := _drop_done - _drop_start()
		_drop_done = done
		drop_down.complete(index, _open_drop_down)
		_mark_seen()
	elif done != _drop_done:
		_drop_done = done
	if phone != null:
		var rows := Tasks.rows(farm, server_now(), _reached())
		if rows != phone.tasks: phone.refresh(rows, {}, [])

## Where the drop-down's showing rows start in the task list (its rows were built from the last count).
func _drop_start() -> int:
	return clampi(_drop_done - (UiTaskDropDown.MAX_ROWS - 1), 0, maxi(0, Tasks.TASKS.size() - UiTaskDropDown.MAX_ROWS))

func _seen() -> String:
	_read_local()
	return seen_task

func _reached() -> int:
	_read_local()
	return tasks_reached

func _read_local() -> void:
	if _seen_read: return
	_seen_read = true
	var raw = JSON.parse_string(FileAccess.get_file_as_string(phone_seen_path)) if FileAccess.file_exists(phone_seen_path) else null
	var entry = raw.get(str(_data.get("block_id", ""))) if raw is Dictionary else null
	if entry is Dictionary:
		seen_task = str(entry.get("seen", ""))
		tasks_reached = int(entry.get("reached", 0))
	elif entry is String:
		seen_task = entry

## The current task has been seen (the drop-down or the phone opened on it): the buttons' dots go.
func _mark_seen() -> void:
	var current := Tasks.current(farm, server_now(), _reached())
	if current.is_empty() or current == _seen(): return
	seen_task = current
	_keep_local()
	task_button.badge = false
	phone_button.badge = false

func _keep_local() -> void:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(phone_seen_path)) if FileAccess.file_exists(phone_seen_path) else null
	var all: Dictionary = raw if raw is Dictionary else {}
	all[str(_data.get("block_id", ""))] = {"seen": seen_task, "reached": tasks_reached}
	DirAccess.make_dir_recursive_absolute(phone_seen_path.get_base_dir())
	var file := FileAccess.open(phone_seen_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all))
		file.close()

## Places a scene button (the house's Build Cottage, C-33) at the left on the action key's baseline, so it never
## covers the quick bar or the key; it keeps its own `custom_minimum_size`.
func place_side_button(button: Control) -> void:
	_side_button = button
	_place_bar()

## Top system inset (status bar, notch) in UI units; 0 on desktop (as P0Ui.safe_top).
func _safe_top() -> float:
	if not is_inside_tree() or not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).y

## Bottom system inset (gesture bar) in UI units; 0 on desktop (as P0Ui.safe_bottom).
func _safe_bottom() -> float:
	if not is_inside_tree() or not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).w
