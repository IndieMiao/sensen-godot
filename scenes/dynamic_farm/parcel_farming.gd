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
## Outer gathering (C-60, ParcelGather): near a tree, flower or rock of the extension the key gathers it until it grows
## back. Gathering never touches the walk, the layout or collision. C-236 (SEN-C-234 D-558, owner SEN-Q-345; numbers
## SEN-Q-342): the key reads `Chop` / `Break` / `Pick` with the object's whole price; a tree takes 3 chops, a rock 2
## hits, a herb one pull (GatherStage plays them with C-235's art); the last one sends the one `gather`, and its drops,
## floats and flights wait for the reply. A felled tree leaves its stump, a broken rock its scree, a pulled herb nothing
## (C-234#50) until they grow back. The yard's obstacles (Q4) are chopped, broken and pulled the same way, then gone.
## With a body (the scene, C-73) a press first walks the player beside the cell and plays the
## main farm's labour clip; the command goes out with the clip and its result lands as it ends.
## Livestock (C-154, ParcelLivestock): near a coop's feeder the key reads `Feed` (`1 Energy`); a carrot goes in, and
## the hen lays an egg on the ground `produce_seconds` later. Walking within reach of a laid egg picks it up by
## itself: it flies into the player and on into the Bag (`+1 Egg`), the server checking each egg is taken once.
## The coop's own floor is walked, never farmed: its cells show no key of their own; since C-175 a tap on it offers the
## nearest feeder's Feed, and the press walks there first. The barn (C-181) works the same way: two carrots a feeding
## (`Need 2 more Carrot` when short), a cow gives milk on the ground 15 minutes later.
## The in-game phone (C-107, design C-85 ⑧): the top bar's task button drops the guide's steps under the bar (C-T1–T3)
## and the phone button at the right opens the phone (Tasks / Inbox / Collection, ParcelPhone); both read the save.
signal state_changed(farm: Dictionary)

const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Space = preload("res://modules/dynamic_farm/parcel_space.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
const Gather = preload("res://modules/dynamic_farm/parcel_gather.gd")
const Guide = preload("res://modules/dynamic_farm/parcel_guide.gd")
const GatherFx = preload("res://modules/dynamic_farm/gather_fx.gd")
const GatherStage = preload("res://scenes/dynamic_farm/gather_stage.gd")
const Palette = preload("res://modules/dynamic_farm/farm_palette.gd")
const CropArt = preload("res://modules/dynamic_farm/parcel_crop_art.gd")
const Livestock = preload("res://scenes/dynamic_farm/parcel_livestock.gd")
const LivestockArt = preload("res://modules/dynamic_farm/farm_livestock.gd")
## How near a feeder (m, its centre on the ground) the key offers Feed (C-154): the bowl is solid, so the player
## stands at least ~0.5 m from its centre.
const FEED_REACH_M := 1.1
## C-175: a tap on a coop's floor offers its nearest feeder within this distance (m; a coop is 7×5 cells), and the
## press walks the player up to it first, as Fill walks up to the well.
const FEED_TAP_M := 8.0
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
## C-141 crop sway (C-140's owner-confirmed design, attachment-1069 §3, SEN-Q-321): a walking player shakes the
## carrots they brush past; ripe carrots sway (ParcelCropArt). On unless this setting turns it off.
const SWAY_SETTING := "sensen/dynamic_farm/crop_sway"
## Player centre to plant centre on the ground (m): body radius 0.3 + crown radius about 0.25.
const SWAY_TRIGGER_M := 0.55
## Slower than this (m/s) brushes nothing: turning on the spot, pushing against a wall.
const SWAY_MIN_SPEED := 0.5
## One plant shakes again only after this long (s).
const SWAY_COOLDOWN_S := 0.6
## Shake amplitude by carrot stage 0..6 (tilled .. maturity). The design's four growth steps 0.45 / 0.65 / 0.85 / 1.0
## spread over C-139's six plant stages: seedlings move less, the mature plant the full 13.5°.
const SWAY_STAGE_AMP := [0.0, 0.45, 0.56, 0.67, 0.78, 0.89, 1.0]
## The tools first (C-151: the pail beside the hoe), then seeds and crops.
const BAG_ORDER := ["hoe_starter", "pail", "seed_carrot", "crop_carrot"]
## Parcel items the main farm's content table does not name (C-74#33, copy per C-45). The icon is a placeholder from
## the existing set (the HUD's home), no new art.
## C-151: `Water` is P0's key (P0Logic, the plot's Water); `Fill` draws the pail at the well (打水, SEN-C-151).
const VERBS := {"clear": "Clear", "till": "Till", "sow": "Sow", "harvest": "Harvest", "rest": "Rest", "gather": "Gather",
	"feed": "Feed", "fill": "Fill", "water": "Water"}
## C-236: kinds whose one hit is a pull (the herb, the yard's weed): the plant comes up into the hand.
const PULLED := ["flower", "weed"]
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
var _marker_shown := false
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
## Crop sway (C-141): on or off, its clock, the player's last position, the plants within reach last frame and
## when each plant last shook; `sway_triggers` counts the plants shaken since the last switch (QA).
var sway := true
var _sway_clock := 0.0
var _sway_from = null
var _sway_inside := {}
var _sway_last := {}
var sway_triggers := 0
## Layout indices drawn as gathered: index -> true.
var _spent := {}
## Layout index → [the batch drawing it, its instance] for the objects drawn as they grow (Scenery.build's `drawn`).
var _outer_drawn := {}
## C-236: the core layout's drawn instances (index -> [batch, instance]), kept up to date as obstacles are cleared.
var _core_drawn := {}
## C-236: the gathering in 3D (GatherStage), the hits landed so far (GatherFx.Damage, this visit only), the key held
## down (hits go on until the object is done), a press during a hit (one more after it), the stick this frame, a hit
## playing, and outer objects whose last hit is still playing (layout index -> true: drawn by GatherStage, not the batch).
var gather_stage: Node3D
var damage: RefCounted
var _key_held := false
var _queued := false
var _steering_now := false
var swinging := false
var _presenting := {}
var _redraw_gathered := false
## C-236: when the last hit landed (ticks ms); the next one lands no sooner than `common.min_hit_interval_ms` after it.
var _last_contact_ms := -1_000_000
## Every hit's contact time this visit (ticks ms; QA reads it).
var contacts := []
## C-236: what the bar and the Energy chip keep showing until the gathered drop appears ({} / -1: the save's).
var _held_bag = null
var _held_energy := -1

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
## scene (C-73), `outer` the drawn outer layer, {layout, root, recipe, drawn?} (its walk profiles are
## already bound; `drawn`: Scenery.build's batch and instance per layout item).
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
	var core_drawn: Array = core.get("drawn", [])
	for i in mini(core_drawn.size(), _core_plan.layout.size()): _core_drawn[i] = core_drawn[i]
	_path = Space.protected_path(data)
	_gather = Gather.rules()
	if outer.get("root") is Node3D and outer.get("layout") is Array:
		_outer_layout = outer.layout
		_outer_root = outer.root
		var drawn: Array = outer.get("drawn", [])
		for i in mini(drawn.size(), _outer_layout.size()): _outer_drawn[i] = drawn[i]
		var recipe = outer.get("recipe")
		var version := str(recipe.get("outer_groves", {}).get("version", "")) if recipe is Dictionary else ""
		gatherables = Gather.objects(_outer_layout, walk, data.block_id, _gather, version)
	_names = _item_names()
	_crop_art = CropArt.new(walk.point, data.cell_m)
	_crop_art.name = "ParcelCrops"
	add_child(_crop_art)
	sway = bool(ProjectSettings.get_setting(SWAY_SETTING, true))
	_crop_art.set_sway(sway)
	livestock = Livestock.new()
	livestock.setup(walk)
	add_child(livestock)
	damage = GatherFx.damage()
	gather_stage = GatherStage.new()
	gather_stage.name = "GatherStage"
	if body != null and body.has_method("shake_camera"):
		gather_stage.shake_camera = func(m: float, ms: float): if not UiMotion.reduced: body.shake_camera(m, ms)
	add_child(gather_stage)
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
	_steering_now = steering
	if steering:
		picked = null
		picked_object = -1
	# C-236: hits not followed up within the memory run out; the scar on the object standing in closes.
	if damage != null and not swinging:
		var gone: Array = damage.expire(Time.get_ticks_msec())
		if gather_stage != null and gather_stage.key() in gone: gather_stage.release()
	target = job if job != null else (picked if picked != null else facing_cell)
	_placed = player is Vector3
	if _placed:
		_player = player
		_facing = facing
	if sway: _update_sway(delta)
	# C-154: animals move; a laid drop in reach is picked up by itself (not while another command is out or a mode holds).
	if livestock != null and not farm.is_empty():
		var reached: Array = livestock.update(delta, _player, server_now(), busy or swinging or held or not _placed or not _picking.is_empty())
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

## The key for gathering object `index`: {verb, kind, refusal, command, object, ready_in_ms?}; `kind` (C-236) is how it
## is gathered (tree: Chop, rock: Break, flower: Pick).
func _gather_action(index: int) -> Dictionary:
	var object: Dictionary = gatherables[index]
	var kind := str(GatherFx.OUTER.get(object.kind, object.kind))
	var now := server_now()
	var ready := Gather.ready_at(_gather, farm, object.id, now)
	if ready > 0:
		return {"verb": "gather", "kind": kind, "refusal": REGROWING, "command": {}, "object": index, "ready_in_ms": ready - now}
	if gap(index) > GATHER_REACH_M:
		return {"verb": "gather", "kind": kind, "refusal": TOO_FAR, "command": {}, "object": index}
	return {"verb": "gather", "kind": kind, "refusal": "", "command": {"type": "gather", "object": object.id}, "object": index}

## C-236 (SEN-Q-345 Q4): how the yard obstacle on `cell` is cleared (tree, bush, rock, weed), "" when it is none.
func core_kind(cell: Vector2i) -> String:
	var anchor = _obstacles.get(cell)
	if anchor == null or not _anchors.has(anchor): return ""
	return str(GatherFx.core(str(_core_plan.layout[_anchors[anchor]].get("role", ""))).get("kind", ""))

## The key's verb word: Chop / Break / Pick / Pull for gathering and clearing (C-236, SEN-Q-345 Q1), else VERBS.
func verb_label(action: Dictionary) -> String:
	var kind := str(action.get("kind", ""))
	if not kind.is_empty() and action.get("verb") in ["gather", "clear"]: return GatherFx.verb(kind)
	return str(VERBS.get(action.get("verb", ""), ""))

func _refresh_key() -> void:
	if held:
		_marker.visible = false
		_keys.set_shown(false)
		_keys.visible = false
		_bar.visible = false
		return
	current = {} if farm.is_empty() else Space.action(rules, _data, _path, _obstacles, farm, target, server_now())
	# C-154: a coop's floor is never farmed (no key there); at its feeder the key feeds.
	# C-171: a tapped cell with a step to do (Fill at a well, Till) wins over the feeder, as a tapped object does.
	if not farm.is_empty() and livestock != null:
		var on_coop := livestock.covers(target)
		if on_coop: current = {}
		var feeder := livestock.feeder_near(_player, FEED_REACH_M) if _placed else {}
		# C-175: a tapped coop floor cell offers the feeder nearest to it, walked up to on the press.
		if feeder.is_empty() and on_coop and picked != null and _placed:
			feeder = livestock.feeder_near(_walk.point(target), FEED_TAP_M)
			if not feeder.is_empty(): feeder.approach = true
		if not feeder.is_empty() and (picked == null or current.is_empty() or not str(current.refusal).is_empty()):
			current = _feed_action(feeder)
	# A tapped object wins; a nearby one only when no cell was tapped and the cell in front has no step to do.
	var object := -1 if farm.is_empty() else gather_target()
	if object >= 0 and (picked_object >= 0 or (picked == null and (current.is_empty() or not str(current.refusal).is_empty()))):
		current = _gather_action(object)
	if current.get("verb") == "clear":
		var kind := core_kind(target)
		if not kind.is_empty(): current.kind = kind
	_marker.visible = not current.is_empty()
	_keys.set_shown(_marker.visible or farm.is_empty())   # MS-23
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
	var refused := not str(current.refusal).is_empty()
	_place_marker(spot + Vector3(0, 0.045, 0), refused)
	# C-148: the price of what the key does (P0's key: `Sow` over `3 Energy`; free actions carry no price, LOCK-02).
	if not refused: key_cost = ParcelFarm.energy_cost(rules, current.command)
	key_short = key_cost > 0 and energy_value() < key_cost
	if current.refusal == Space.NOT_RIPE:
		_key.verb = "Growing"
		_key.cost = P0Logic.key_ready(float(current.ripe_in_ms))
	elif current.verb == "gather":
		_key.verb = "Regrowing" if current.refusal == REGROWING else verb_label(current)
		_key.cost = P0Logic.key_ready(float(current.ready_in_ms)) if current.refusal == REGROWING \
			else "Move closer" if current.refusal == TOO_FAR else _price()
	elif current.verb == "rest":
		_key.verb = VERBS.rest
		_key.cost = REFUSALS.get(current.refusal, "+%d Energy" % int(current.get("gain", 0)))
	elif current.verb == "feed":
		_key.verb = VERBS.feed
		_key.cost = str(current.key_text) if refused else _price()
	else:
		_key.verb = verb_label(current)
		_key.cost = REFUSALS.get(current.refusal, _price())
	# The key's badge is the tool or item the press uses: the hoe for farming, the feed (a carrot) at a feeder; C-236: the
	# axe at a tree or bush, the pick at a rock, the hand at a herb or weed (LOCK-02's tool badge).
	var badge: Texture2D = item_icon(str(current.feed_item)) if current.get("verb") == "feed" \
		else GatherFx.tool_icon(str(current.kind)) if current.has("kind") else _tool_badge()
	if _keys.tool_icon != badge: _keys.tool_icon = badge
	_key.state = UiSceneAction.State.UNAVAILABLE if refused else UiSceneAction.State.INSUFFICIENT if key_short \
		else UiSceneAction.State.DEFAULT

## The key's second line for a priced action: `3 Energy`, short of it `Need 3 Energy` (LOCK-10); free: none.
func _price() -> String:
	if key_cost <= 0: return ""
	return ("Need %d Energy" if key_short else "%d Energy") % key_cost

func _on_key() -> void:
	if held: return
	_key_held = true
	# C-236: a press during a hit asks for one more after it (the key held down keeps going on its own).
	if swinging:
		_queued = true
		return
	if unavailable and not busy:
		await enter()
		return
	if busy or current.is_empty(): return
	if key_short:
		# Short of Energy: the press opens the Energy card and sends nothing (LOCK-09 / LOCK-10). C-236: before the first hit,
		# for the object's whole price.
		open_energy_card(key_cost, verb_label(current))
		return
	if not str(current.refusal).is_empty():
		# The whole sentence where the key shows a shorter one (the feeder's `Need 2 more Carrot`, C-192).
		var refusal := "Not ripe yet" if current.refusal == Space.NOT_RIPE else "Not ready yet" if current.refusal == REGROWING \
			else str(current.get("refusal_text", _key.cost))
		_toast.show_toast(refusal, ToastLayer.Severity.REFUSED)
		return
	if current.verb == "gather": await gather(current)
	elif current.verb == "feed": await feed(current)
	else: await work(target, current)

## One gather press (C-60): the object is already in reach, so the player only faces it (no walk). C-236: each press is
## one hit (`strike_down`), the last one sends the `gather`; it replaces MS-08's two rocks and the grey (SEN-Q-345 Q6).
func gather(action: Dictionary) -> Dictionary:
	var object: Dictionary = gatherables[action.object]
	var index := int(object.index)
	var item: Dictionary = _outer_layout[index] if index < _outer_layout.size() else {}
	return await strike_down({"key": object.id, "model": object.asset, "kind": str(action.get("kind", "tree")),
		"hits": int(object.get("hits", 1)), "rest": item.get("transform", Transform3D(Basis(), object.origin)),
		"drawn": _outer_instance(index), "cells": [_walk.cell_at(object.origin)], "outer": index, "item": object.item},
		action.command)

## C-236: the hits on one object (`t`: key, model, kind, hits, rest, drawn, cells, outer (layout index, -1 in the yard),
## item) until it is done, the stick moves, or the key is let go. A hit plays its clip; the stick before its contact
## takes it back (nothing counted), after it only skips the follow-through. Hits are remembered for 30 s (`damage`); the
## one that finishes the object sends `command` and plays the fall, the breaking or the pull while the reply comes.
## Without the 3D scene (headless stores) one press settles at once, as before.
func strike_down(t: Dictionary, command: Dictionary) -> Dictionary:
	if gather_stage == null or _body == null or not _body.has_method("gesture"): return await send(command)
	if gather_stage.key() != t.key:
		if not gather_stage.key().is_empty(): damage.forget(gather_stage.key())
		var drawn: Array = t.get("drawn", [])
		gather_stage.focus(t.key, t.model, t.kind, t.rest, drawn, _player, _instance_tint(drawn), _instance_mesh(drawn, t.kind),
			_bloom(str(t.model), (t.rest as Transform3D).origin))
	swinging = true
	var result := {"ok": false, "code": "CANCELLED"}
	var hits := maxi(1, int(t.hits))
	while is_inside_tree():
		_queued = false
		var done: int = damage.done(t.key, Time.get_ticks_msec())
		var last := done + 1 >= hits
		if last and t.kind in PULLED: gather_stage.begin_pull()
		# SEN-Q-342 §5 / C-236#14: two hits land at least 0.9 s apart; a quicker press or the held key waits a beat first.
		var gap_ms := int(GatherFx.common().get("min_hit_interval_ms", 900))
		var wait := (_last_contact_ms + gap_ms - Time.get_ticks_msec()) / 1000.0 - GatherFx.contact_s(t.kind)
		if wait > 0.0 and not await _hold(wait): break
		var length: float = _body.gesture(t.kind, t.cells)
		var contact := minf(GatherFx.contact_s(t.kind), length)
		if not await _hold(contact):
			# Wound up and let go: this hit never landed (a pulled herb drops back where it was).
			_body.cut_labour()
			if last and t.kind in PULLED: gather_stage.refuse()
			break
		_last_contact_ms = Time.get_ticks_msec()
		contacts.append(_last_contact_ms)
		done = damage.hit(t.key, Time.get_ticks_msec())
		if done >= hits:
			result = await _settle(t, command)
			break
		gather_stage.strike(done, hits)
		_hitstop()
		if not await _hold(length - contact): _body.cut_labour()
		if not is_inside_tree(): break
		result = {"ok": true, "code": "HIT", "done": done, "hits": hits}
		if not (_key_held or _queued) or _steering_now: break
		# The key held down: the next hit, as long as the object is still the key's and nothing else holds the screen.
		if held or current.is_empty() or str(current.get("refusal", "")) != "" or key_short: break
	swinging = false
	return result

## Waits `seconds` of the hit; false when the stick moved meanwhile (the caller cuts the hit short).
func _hold(seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		if not is_inside_tree(): return false
		if _steering_now: return false
	return true

## The approved 40 ms hit-stop on contact (not under reduced motion): the gatherer's clip holds for a beat.
func _hitstop() -> void:
	var ms := int(GatherFx.common().get("hitstop_ms", 40))
	if UiMotion.reduced or ms <= 0 or not _body.has_method("hitstop"): return
	_body.hitstop(ms)

## The finishing hit: the object goes (fall / pieces / pull) while `command` goes out; what it gave shows no sooner
## than the picture says and never before the reply (`common.reward_gate`): a log or a stone pops out where the tree
## fell or the rock broke, its `+2 Timber` and `−3 Energy` rise from it, it flies into the player and on into the bar;
## a herb's icon pops from the player's head (`max(700 ms, reply)`). Refused, the object comes back and nothing is given.
func _settle(t: Dictionary, command: Dictionary) -> Dictionary:
	var kind := str(t.kind)
	var outer := int(t.get("outer", -1))
	if kind in PULLED: _body.hold_plant(t.model, true, _instance_mesh(t.get("drawn", []), kind))
	var picture_s: float = gather_stage.finish(UiMotion.reduced)
	var shown_at := Time.get_ticks_msec() + int(picture_s * 1000.0)
	if outer >= 0: _presenting[outer] = true
	var energy_before := energy_value()
	_held_bag = farm.get("bag", {}).duplicate()
	_held_energy = energy_before
	var result := await send(command, 0.0, false)
	if not is_inside_tree(): return result
	if Time.get_ticks_msec() < shown_at:
		await get_tree().create_timer((shown_at - Time.get_ticks_msec()) / 1000.0).timeout
		if not is_inside_tree(): return result
	damage.forget(t.key)
	_held_bag = null
	_held_energy = -1
	_draw_bag()
	if not result.get("ok", false):
		gather_stage.refuse()
		if kind in PULLED: _body.hold_plant(t.model, false, null, true)
		await get_tree().create_timer(UiMotion.secs(float(GatherFx.common().get("refuse_rewind_ms", 300)))).timeout
		if outer >= 0: _presenting.erase(outer)
		if is_inside_tree(): gather_stage.release()
		return result
	var gains: Dictionary = result.get("gains", {})
	var spent := energy_before - energy_value()
	var pickup: Dictionary = GatherFx.config().get("pickup", {})
	if kind in PULLED:
		# A herb: the icon pops from over the player's head and flies on into the bar with the floats.
		var head := _player_screen()
		announce_gains(gains, head)
		announce_energy(-spent, head)
		gather_stage.picked_up()
		_body.hold_plant(t.model, false)
	else:
		var drop: Node3D = gather_stage.reward(str(t.get("item", ""))) if not gains.is_empty() else null
		var from: Vector2 = _body.screen_point(drop.global_position, 0.3) if drop != null else _gain_screen(command)
		announce_gains(gains, from, false, false)
		announce_energy(-spent, from)
		if drop != null:
			var drop_rule: Dictionary = GatherFx.kind(kind).get("drop", {})
			await get_tree().create_timer(UiMotion.secs(float(drop_rule.get("pop_ms", 360)) + float(drop_rule.get("hold_ms", 200)))).timeout
			if not is_inside_tree(): return result
			gather_stage.pull_drop(func() -> Vector3: return _body.player_position() + Vector3(0, 0.9, 0))
			await get_tree().create_timer(UiMotion.secs(float(pickup.get("magnet_ms", 320)))).timeout
			if not is_inside_tree(): return result
		fly_gains(_player_screen())
	# The outer object stays the stage's until its last clip has played (the crown sinks and fades), then its stump or
	# scree joins the spent batch; a yard obstacle fades out whole (nothing is left where it was cleared).
	if outer >= 0:
		await get_tree().create_timer(_clip_left()).timeout
		if not is_inside_tree(): return result
		_presenting.erase(outer)
		_redraw_gathered = true
		_draw_gathered()
		gather_stage.release(true)
	else:
		await get_tree().create_timer(_clip_left()).timeout
		if is_inside_tree(): gather_stage.vanish()
	return result

## How long the object's last clip still plays (s).
func _clip_left() -> float:
	var target: Node = gather_stage.get_node_or_null("GatherTarget")
	var anim := target.get_node_or_null("AnimationPlayer") as AnimationPlayer if target != null else null
	if anim == null or not anim.is_playing(): return 0.0
	return maxf(0.0, anim.current_animation_length - anim.current_animation_position) / maxf(anim.speed_scale, 0.01)

## The batch colour of a drawn instance (the autumn trees' tint), white without one.
func _instance_tint(drawn: Array) -> Color:
	if drawn.size() < 2 or not is_instance_valid(drawn[0]): return Color.WHITE
	var mm: MultiMesh = (drawn[0] as MultiMeshInstance3D).multimesh
	return mm.get_instance_color(drawn[1]) if mm.use_colors and int(drawn[1]) < mm.instance_count else Color.WHITE

## A plant's recoloured batch mesh (C-235: the same on the ground and in the hand), null for trees and rocks.
func _instance_mesh(drawn: Array, kind: String) -> Mesh:
	if not kind in PULLED or drawn.size() < 2 or not is_instance_valid(drawn[0]): return null
	return (drawn[0] as MultiMeshInstance3D).multimesh.mesh

## V-723: a herb's petal colour, the brightest colour its palette variant paints (the lilac-white, the white).
func _bloom(asset: String, origin: Vector3) -> Color:
	var palette: Dictionary = _recipe.get("prop_palette", {}) if _recipe is Dictionary else {}
	var variants = palette.get("assets", {}).get(asset)
	var pick := Palette.pick(palette, asset, origin) if variants is Array else -1
	if pick < 0 or pick >= variants.size(): return GatherStage.PETAL_PINK
	var best := GatherStage.PETAL_PINK
	var lightest := -1.0
	for value in variants[pick].get("map", {}).values():
		var c := Color("#" + str(value))
		if c.get_luminance() > lightest:
			lightest = c.get_luminance()
			best = c
	return best

## The batch drawing outer object `index` and its instance there: [MultiMeshInstance3D, i], or [] (not drawn, gone).
func _outer_instance(index: int) -> Array:
	var at: Array = _outer_drawn.get(index, [])
	if at.is_empty() or not is_instance_valid(at[0]) or (at[0] as Node).is_queued_for_deletion(): return []
	return at

## The key at a livestock building's feeder (C-154): Feed, or why not (`Need 1 Carrot`, the art's `Hens are fed` /
## `Pick up eggs first`); {verb, refusal, refusal_text, key_text, command, feeder}. `refusal_text` is the whole
## sentence (the tap's toast); `key_text` is what the key's second line shows: the same where it fits, else its shorter
## form (C-192, P0's keys: `Need 2 more Carrot` → `Need 2 more`; the art's `full_short` / `fed_short`).
func _feed_action(near: Dictionary) -> Dictionary:
	var b: Dictionary = near.building
	var refusal := ParcelFarm.feed_refusal(rules, farm, b, server_now())
	var rule := ParcelFarm.livestock_of(rules, b)
	var copy: Dictionary = LivestockArt.building_art(str(b.type)).get("copy", {})
	var text := ""
	var short := ""
	match refusal:
		"NO_FEED":
			var have := int(farm.get("bag", {}).get(str(rule.get("feed", "")), 0))
			text = feed_gap(rule, have)
			short = feed_gap(rule, have, true)
		"ANIMALS_FED":
			text = str(copy.get("fed", "Hens are fed"))
			short = str(copy.get("fed_short", ""))
		"GROUND_FULL":
			# C-192: with as many on the ground as animals (the barn's 2, SEN-Q-282) the ground fills before every animal
			# is waiting, so while none of them is given yet there is nothing to pick up: the key says they are fed.
			var now := server_now()
			if ParcelFarm.drops_in(farm, int(b.id)).any(func(d: Dictionary): return int(d.ready_at) <= now):
				text = str(copy.get("full", "Pick up eggs first"))
				short = str(copy.get("full_short", ""))
			else:
				text = str(copy.get("fed", "Hens are fed"))
				short = str(copy.get("fed_short", ""))
		"NOT_LIVESTOCK": text = "That didn't work."
	return {"verb": "feed", "refusal": refusal, "refusal_text": text, "key_text": key_copy(text, short),
		"feed_item": str(rule.get("feed", "")),
		"command": {"type": "feed", "building": int(b.id)} if refusal.is_empty() else {}, "feeder": near.point,
		"stand": near.get("stand"), "approach": bool(near.get("approach", false))}

## The main key's second line for `text`: itself when it shows whole on the key, else `short` (when there is one).
static func key_copy(text: String, short: String) -> String:
	return text if short.is_empty() or UiSceneAction.cost_fits(text) else short

## The key's reason when the bag has `have` of the feed and a feeding takes the rule's `feed_amount` (C-181): `Need 1
## Carrot` with none for one (the coop, as before), else P0's `Need N more <item>` (the barn: `Need 2 more Carrot`).
## `short`: without the item (`Need 2 more`), what the key shows where the whole one does not fit (C-192).
func feed_gap(rule: Dictionary, have: int, short := false) -> String:
	var feed := str(rule.get("feed", ""))
	var name_ := str(_names.get(feed, ParcelItems.name_of(feed)))
	var need := int(rule.get("feed_amount", 1))
	if need == 1 and have <= 0: return "Need 1" if short else "Need 1 %s" % name_
	return "Need %d more" % (need - have) if short else "Need %d more %s" % [need - have, name_]

## One feed press (C-154): the feeder is already in reach, so the player faces it and plays the labour clip while
## the command goes out; the fed hen then comes to peck (ParcelLivestock). C-175: offered for a tapped coop floor cell,
## the player first walks up beside the feeder (as `work` does); C-202: to where the feeder is filled from, when its art
## says (`stand`, the barn trough's right end).
func feed(action: Dictionary) -> Dictionary:
	if _body == null: return await send(action.command)
	var cells: Array[Vector2i] = [_walk.cell_at(action.feeder)]
	if action.get("approach", false):
		busy = true
		var stand = action.get("stand")
		var reached: String = await _body.approach(cells, {_walk.cell_at(stand): 0.0} if stand is Vector3 else {})
		if not is_inside_tree(): return {"ok": false, "code": "LEFT"}
		if reached != "ok":
			busy = false
			if reached == "unreachable": _toast.show_toast(UNREACHABLE, ToastLayer.Severity.REFUSED)
			return {"ok": false, "code": reached.to_upper()}
	_body.labour("harvest", cells, LABOUR_S)
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
		announce_gains(gains, _player_screen(), true)

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
	# C-236 (SEN-Q-345 Q4): a yard obstacle is chopped, broken or pulled like the outer ones; its last hit sends the clear.
	if action.get("verb") == "clear" and not str(action.get("kind", "")).is_empty() and _body.has_method("gesture"):
		busy = false
		var anchor = _obstacles.get(cell)
		var index: int = _anchors.get(anchor, -1) if anchor != null else -1
		if index >= 0:
			var item: Dictionary = _core_plan.layout[index]
			var hits := int(GatherFx.core(str(item.get("role", ""))).get("hits", 1))
			var outcome := await strike_down({"key": "core:%s" % ParcelFarm.key(anchor), "model": item.asset, "kind": action.kind,
				"hits": hits, "rest": item.transform, "drawn": _core_drawn.get(index, []), "cells": cells, "outer": -1, "item": ""}, action.command)
			job = null
			return outcome
	# C-151: Fill and Water play C-153's pail actions, as long as they last (the scene's labour_seconds).
	var seconds: float = _body.labour_seconds(action.verb, LABOUR_S) if _body.has_method("labour_seconds") else LABOUR_S
	_body.labour(action.verb, cells, seconds)
	var result := await send(action.command, seconds)
	job = null
	# MS-07 (C-185 §3.2): the reply's new soil springs up with a puff of dust, a sown seedling grows from its root, a
	# watered cell's soil darkens to wet as drops splash off it (C-211).
	if bool(result.get("ok", false)) and _crop_art != null:
		if action.verb == "till":
			_crop_art.pop(cell, &"soil")
			_crop_art.dust(cell)
		elif action.verb == "sow": _crop_art.pop(cell, &"plant")
		elif action.verb == "water": _crop_art.wet_in(cell)
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
## shown no sooner than this after sending (the labour clip's length). `announce` false (C-236): the caller shows the
## gains itself, later (they are in the result's `gains`); refusals are shown here either way.
func send(command: Dictionary, hold_s := 0.0, announce := true) -> Dictionary:
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
		var gains := {}
		for id: String in farm.bag:
			var gained := int(farm.bag.get(id, 0)) - int(before.get(id, 0))
			if gained > 0: gains[id] = gained
		result["gains"] = gains
		if not announce: return result
		if command.type in ["harvest", "gather"]: announce_gains(gains, _gain_screen(command))
		var cost := ParcelFarm.energy_cost(rules, command)
		announce_energy(-cost if cost > 0 else energy_value() - energy_before if command.type == "rest" else 0, _gain_screen(command))
	elif result.get("code") == "NO_ENERGY":
		# The server's clock disagreed with the key's: the same card as a short key (LOCK-09).
		var detail: Dictionary = result.get("detail", {})
		var label := verb_label(current) if current.get("command") == command else str(VERBS.get(_verb_of(command), ""))
		open_energy_card(int(detail.get("need", ParcelFarm.energy_cost(rules, command))), label)
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
	energy_chip.show_energy(_held_energy if _held_energy >= 0 else int(e.value), int(e.max), regen, key_cost if key_short else 0)

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
	_open_energy_layer(center, UiTokens.COLOR_SCRIM_MODAL)
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
	_open_energy_layer(panel, Color(UiTokens.COLOR_SCRIM_MODAL, 0.0))
	energy_modal = "panel"

func _open_energy_layer(content: Control, scrim: Color) -> void:
	_bar.cancel_drag()
	# G-02: the bag and the phone close, the drop-down folds; the quick bar slides away (M-16), the guide hides.
	close_bag()
	close_phone()
	if drop_down != null: drop_down.fold()
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
	# MS-11 / M-04: the scrim fades in, the card or panel grows 0.88 → 1 (the card from its centre, the panel from its
	# pointer at the chip).
	UiMotion.panel_in(content, veil, Vector2(0.5, 0.5) if content is CenterContainer else Vector2(0.15, 0.0))
	if _bar.visible: UiMotion.bar_shown(_bar, false, _bar.position.y)
	_refresh_tip()

## Closes the Energy card or panel (M-05; touches go through at once); false when neither was open.
func close_energy() -> bool:
	if _energy_layer == null: return false
	var layer := _energy_layer
	_energy_layer = null
	energy_modal = ""
	var veil := layer.get_node_or_null("Scrim") as Control
	if veil != null: veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content := layer.get_child(layer.get_child_count() - 1) as Control
	content.propagate_call(&"set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
	if layer.is_inside_tree() and content != veil: UiMotion.panel_out(content, veil, layer.queue_free)
	else: layer.queue_free()
	if not farm.is_empty() and not held and _bag == null and phone == null:
		_place_bar()   # back at its rest (M-16 left it 24 lower), as close_bag does
		var rest := _bar.position.y
		_bar.position.y = rest + UiMotion.BAR_HIDE_Y
		UiMotion.bar_shown(_bar, true, rest)
	_refresh_tip()
	return true

## The Energy a reply spent or gave as one float over what it was spent on: `−3 Energy` / `+60 Energy` (P0's tones).
## C-185 MS-06: it joins the same stack as the reply's item lines, last (not apart, 80 up).
func announce_energy(delta: int, from: Vector2) -> void:
	if delta == 0: return
	var line := UiGainFloat.new(("+%d Energy" if delta > 0 else "−%d Energy") % absi(delta),
		UiGainFloat.Tone.ENERGY_GAIN if delta > 0 else UiGainFloat.Tone.ENERGY_COST)
	line.name = "EnergyFloat"
	line.theme = UiKit.theme()
	_ui.add_child(line)
	var index := 0
	if not _float_batch.is_empty() and Time.get_ticks_msec() - int(_float_batch.ms) <= ENERGY_JOINS_MS:
		index = mini(int(_float_batch.lines), UiTokens.MOTION_LIMIT_FLOAT_LINES - 1)
	_float_batch = {}
	line.play(from - Vector2(0, FLOAT_ABOVE), index)

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
	# C-236: where each remaining obstacle is drawn now (a yard target hides its own instance in the new batches).
	_core_drawn = {}
	var kept := 0
	for i in _core_plan.layout.size():
		var item: Dictionary = _core_plan.layout[i]
		if _removed.has(item.cell) or gone.has(item.cell): continue
		if kept < art.drawn.size(): _core_drawn[i] = art.drawn[kept]
		kept += 1
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

## Redraws the outer layer when the set of gathered objects changes. C-236: a felled tree leaves its stump, a broken rock
## its scree (C-235's pieces, one batch per model, in the tree's tint), a pulled herb nothing at all (C-234#50: no root,
## no leaves); all come back once grown. An object whose last hit is still playing is GatherStage's and drawn by none
## of these. Art only: the walk keeps every profile bound at load, so reach and collision never change.
func _draw_gathered() -> void:
	if _outer_root == null or farm.is_empty(): return
	var now := server_now()
	var spent := {}
	for object: Dictionary in gatherables:
		if Gather.ready_at(_gather, farm, object.id, now) > 0: spent[object.index] = true
	if spent == _spent and not _redraw_gathered: return
	var fresh := []
	var fresh_at := []
	var pieces := {}   # model -> [transforms, tints]
	for i in _outer_layout.size():
		var item: Dictionary = _outer_layout[i]
		if not spent.has(i) and not _presenting.has(i):
			fresh.append(item)
			fresh_at.append(i)
		elif spent.has(i) and not _presenting.has(i) and item.solid:
			if not pieces.has(item.asset): pieces[item.asset] = [[], []]
			pieces[item.asset][0].append(item.transform)
			pieces[item.asset][1].append(_spent_tint(i))
	var art := Scenery.build({"layout": fresh}, _walk, _recipe, false)
	if not art.ok: return
	_spent = spent
	_redraw_gathered = false
	var tints := {}
	for i: int in _outer_drawn: tints[i] = _instance_tint(_outer_drawn[i])
	_spent_tints.merge(tints, true)
	_outer_drawn = {}
	for k in fresh_at.size(): _outer_drawn[fresh_at[k]] = art.drawn[k]
	for child in _outer_root.get_children():
		_outer_root.remove_child(child)
		child.queue_free()
	for child in art.root.get_children():
		art.root.remove_child(child)
		_outer_root.add_child(child)
	art.root.free()
	for model: String in pieces:
		var piece: Dictionary = GatherStage.spent_piece(model)
		if piece.is_empty(): continue
		var batch := MultiMeshInstance3D.new()
		batch.name = "Spent_" + model
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.use_colors = true
		batch.multimesh.mesh = piece.mesh
		batch.multimesh.instance_count = pieces[model][0].size()
		for j in pieces[model][0].size():
			batch.multimesh.set_instance_transform(j, pieces[model][0][j])
			batch.multimesh.set_instance_color(j, pieces[model][1][j])
		batch.material_override = piece.material
		batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_outer_root.add_child(batch)

## The colour an outer object was drawn in while it grew (the autumn trees), for its stump.
var _spent_tints := {}
func _spent_tint(index: int) -> Color:
	if _outer_drawn.has(index): return _instance_tint(_outer_drawn[index])
	return _spent_tints.get(index, Color.WHITE)

## Crop sway on or off (C-141; QA compares the two). Off draws the carrots still, as before.
func set_sway(on: bool) -> void:
	sway = on
	_sway_from = null
	_sway_inside.clear()
	_sway_last.clear()
	sway_triggers = 0
	_crop_art.set_sway(on)

## Design §3.1: a plant shakes when the walking player comes within SWAY_TRIGGER_M of it, once per entry and not
## again within SWAY_COOLDOWN_S, away from the player plus half the walking direction. Only the 3×3 cells round the
## player are looked at. Tapped routes and the stick both move the player, so both shake by the same rule.
func _update_sway(delta: float) -> void:
	_sway_clock += delta
	_crop_art.set_clock(_sway_clock)
	if not _placed or farm.is_empty():
		_sway_from = null
		return
	var move := Vector2.ZERO
	if _sway_from is Vector3: move = Vector2(_player.x - _sway_from.x, _player.z - _sway_from.z)
	_sway_from = _player
	var walking := delta > 0.0 and move.length() / delta > SWAY_MIN_SPEED
	var here: Vector2i = _walk.cell_at(_player)
	var inside := {}
	var now := server_now()
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := here + Vector2i(dx, dy)
			var crop = farm.crops.get(ParcelFarm.key(cell))
			if not crop is Dictionary or crop.get("crop") != CropArt.CARROT: continue
			var at: Vector3 = _walk.point(cell)
			var away := Vector2(at.x - _player.x, at.z - _player.z)
			if away.length() >= SWAY_TRIGGER_M: continue
			inside[cell] = true
			if _sway_inside.has(cell) or not walking or _sway_clock - float(_sway_last.get(cell, -100.0)) <= SWAY_COOLDOWN_S:
				continue
			var push := away.normalized() if away.length() > 0.05 else move.normalized()
			push = (push + move.normalized() * 0.5).normalized()
			_crop_art.shake(cell, push * float(SWAY_STAGE_AMP[CropArt.stage_of(crop, now)]))
			_sway_last[cell] = _sway_clock
			sway_triggers += 1
	_sway_inside = inside

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
	var bag := shown_bag()
	var ids: Array = BAG_ORDER.filter(func(id): return int(bag.get(id, 0)) > 0)
	for id: String in bag:
		if id not in ids and _names.has(id) and int(bag[id]) > 0: ids.append(id)
	return ids

## The bag as the bar and the drawer show it: the save's, except while a gathering's reply waits for its drop to show
## (C-236 `common.reward_gate`: the counts roll only as the gain appears), when it is the bag from before.
func shown_bag() -> Dictionary:
	return _held_bag if _held_bag is Dictionary else farm.get("bag", {})

## Quick bar and bag drawer follow the save: counts change as each reply lands.
func _draw_bag() -> void:
	var ids := bag_ids()
	var slots := []
	# C-186 (C-185 §3.1 D, C-185#79): the seed the key sows sits on the Seeds end, not in a middle slot.
	var seed := seed_shown(ids)
	# C-228 (SEN-C-227 D4, owner SEN-Q-344): blueprints stay in the bag and the blueprint book, not on the quick bar.
	var blueprints := blueprint_items()
	for id: String in ids:
		if slots.size() >= _bar.slot_count: break
		if id == seed or blueprints.has(id): continue
		slots.append({"id": id, "icon": item_icon(id), "title": _names.get(id, id), "quantity": int(shown_bag()[id])})
	_bar.slots = slots
	_bar.seeds_item = {} if seed.is_empty() else {"id": seed, "icon": item_icon(seed)}
	if _bag == null and phone == null and _energy_layer == null: _bar.visible = not farm.is_empty() and not held
	_keys.tool_icon = _tool_badge()
	if _bag != null: _draw_bag_slots(ids)

## The rules' building blueprints (item id -> true): kept off the quick bar (C-228).
func blueprint_items() -> Dictionary:
	var out := {}
	for rule in rules.get("buildings", {}).values():
		if rule is Dictionary and rule.get("blueprint") is String: out[rule.blueprint] = true
	return out

## The seed the Seeds end shows: the rules' sowing seed while the bag holds it, else the bag's first seed, else "".
func seed_shown(ids: Array) -> String:
	for crop: Dictionary in rules.get("crops", {}).values():
		if str(crop.get("seed", "")) in ids: return str(crop.seed)
	for id: String in ids:
		if id.begins_with("seed_"): return id
	return ""

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
			slot.item = {"id": id, "icon": item_icon(id), "qty": int(shown_bag()[id])}
			slot.is_new = bag_fresh.has(id)
			_bag_slots[id] = slot
		else:
			slot.name = "Slot_%d" % i
			slot.item = {}
			slot.is_new = false
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

## An item's name as the bag shows it (C-181: the Build key's `Need N more Timber`).
func item_name(id: String) -> String:
	return str(_names.get(id, ParcelItems.name_of(id)))

## A short notice over the scene (C-181: a tap on the Build key while materials are short says why).
func show_notice(text: String) -> void:
	if _toast != null: _toast.show_toast(text, ToastLayer.Severity.INFO)

## A gain (the welcome gift, a harvest, a gather, a pickup; C-185 MS-04 / MS-06, C-186): one float per item rising from
## `from` (screen point of what gave it) and the item's icon flying (UiRewardFly) to where it lands on the quick bar
## (`landing_for`: the slot holding it, else the Bag end), which bumps as it lands. One icon per kind, 60 apart, at
## most five; a float for the same item still up adds to it (`+3 Carrot`); past four lines a kind joins the newest
## line. With the bag or the phone open, or the bar away, nothing flies: the float only, and the Bag end bumps once
## when the bar comes back (land_pending). `pickup`: the egg / milk path, the icon flies at once (MS-05).
## Items without a name or icon in the content table are skipped. `fly` false (C-236): the floats only; `fly_gains` sends
## the icons later, from where the gathered drop reached the player.
func announce_gains(gains: Dictionary, from: Vector2, pickup := false, fly := true) -> void:
	last_gains = {}
	var lines := 0
	var flights := 0
	var newest: UiGainFloat = null
	var on_screen := _bag == null and phone == null and _bar.is_visible_in_tree()
	for id: String in gains:
		var count := int(gains[id])
		if count <= 0 or not _names.has(id): continue
		last_gains[id] = count
	if last_gains.is_empty(): return
	_draw_bag()   # the bar holds the new counts (and a new item's slot) before anything lands on it
	for id: String in last_gains:
		var count: int = last_gains[id]
		var icon := item_icon(id)
		var live: Dictionary = _gain_lines.get(id, {})
		if not live.is_empty() and is_instance_valid(live.line) and (live.line as UiGainFloat).showing():
			live.count = int(live.count) + count
			(live.line as UiGainFloat).text = "+%d %s" % [live.count, _names[id]]
		elif lines >= UiTokens.MOTION_LIMIT_FLOAT_LINES and newest != null:
			newest.text += " · +%d %s" % [count, _names[id]]
		else:
			var line := UiGainFloat.new("+%d %s" % [count, _names[id]], UiGainFloat.Tone.ITEM, icon)
			line.name = "Gain_" + id
			line.theme = UiKit.theme()
			_ui.add_child(line)
			line.play(from - Vector2(0, FLOAT_ABOVE), lines)
			_gain_lines[id] = {"line": line, "count": count}
			newest = line
			lines += 1
		if not fly: continue
		if not on_screen:
			_land_waiting = true
		elif flights < UiTokens.MOTION_LIMIT_REWARD_ICONS:
			var to := landing_for(id)
			if UiRewardFly.launch(_ui, from, to, icon, UiRewardFly.stagger_s(flights), func(): UiMotion.land(to), pickup) != null:
				flights += 1
	_float_batch = {"ms": Time.get_ticks_msec(), "lines": lines}

## C-236: the last gain's icons (`last_gains`) fly from `from` into the quick bar now (MS-05's path, as a pickup).
func fly_gains(from: Vector2) -> void:
	var on_screen := _bag == null and phone == null and _bar.is_visible_in_tree()
	var flights := 0
	for id: String in last_gains:
		if not on_screen:
			_land_waiting = true
			continue
		if flights >= UiTokens.MOTION_LIMIT_REWARD_ICONS: break
		var to := landing_for(id)
		if UiRewardFly.launch(_ui, from, to, item_icon(id), UiRewardFly.stagger_s(flights), func(): UiMotion.land(to), true) != null:
			flights += 1

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
	# G-02 (C-185 §3.5): one overlay at a time; the task drop-down folds first.
	close_phone()
	close_energy()
	if drop_down != null: drop_down.fold()
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
	bag_fresh = _take_bag_fresh()   # C-185 P-01: the items new since the bag was last opened carry a dot this time
	_draw_bag()
	if focus != "": select_bag_item(focus)
	_bag.open()
	_bag.stagger(_slots.get_children())   # M-06
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
	land_pending()
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

## MS-09 (C-185 §3.2, C-W4): the target cell is a white dashed outline (0.92, its inside white 0.10), the danger red
## when the key refuses; a new target's frame fades in over 120 while the old one fades out.
func _place_marker(at: Vector3, refused: bool) -> void:
	var tint := UiTokens.COLOR_ACTION_DANGER if refused else Color.WHITE
	var moved := not _marker.position.is_equal_approx(at)
	if moved and _marker.visible and _marker_shown and not UiMotion.reduced and is_inside_tree():
		var old := _marker.duplicate() as MeshInstance3D
		old.name = "TargetCellOld"
		var old_material := _marker_material.duplicate() as StandardMaterial3D
		old.material_override = old_material
		add_child(old)
		var out := create_tween()
		out.tween_property(old_material, "albedo_color:a", 0.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		out.tween_callback(old.queue_free)
		_marker_material.albedo_color = Color(tint, 0.0)
		var fade := create_tween()
		fade.tween_property(_marker_material, "albedo_color:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	elif not (_marker_material.albedo_color.a < 1.0 and not moved):
		_marker_material.albedo_color = tint
	else:
		_marker_material.albedo_color = Color(tint, _marker_material.albedo_color.a)
	_marker.position = at
	_marker_shown = true

## The dashed frame's texture: dashes 8 on 5 off round the edge (2.5 of a 64 px cell is ~4), the inside white 10%.
static func _dash_texture() -> ImageTexture:
	var n := 64
	var w := 4
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0.10))
	var period := 13
	for i in n:
		var on := (i % period) < 8
		if not on: continue
		for k in w:
			for p: Vector2i in [Vector2i(i, k), Vector2i(i, n - 1 - k), Vector2i(k, i), Vector2i(n - 1 - k, i)]:
				img.set_pixelv(p, Color(1, 1, 1, 0.92))
	return ImageTexture.create_from_image(img)

func _build_marker() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * _data.cell_m * 0.94
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_material.albedo_texture = _dash_texture()
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
	_bar = UiQuickBar.new(true)   # C-186: Seeds end + 4 frosted slots + Bag end (C-185 §3.1 D)
	_bar.bag_icon = UiArt.bag_end()   # C-211: the coloured bag (C-185 §3.1 D)
	_bar.name = "QuickBar"
	_bar.haptics = OS.has_feature("mobile")
	_bar.visible = false
	_bar.slot_tapped.connect(func(id: String): open_bag(id))
	_bar.ghost_tapped.connect(func(_i: int): open_bag())
	_bar.bag_requested.connect(func(): open_bag())
	_bar.close_requested.connect(close_bag)
	_bar.seeds_pressed.connect(func(): open_bag(str(_bar.seeds_item.get("id", ""))))
	# The bar follows the bag's order and the parcel save keeps no bar layout, so the main farm's long-press drag
	# (swap, Pin, Remove) has nothing to change here: the cells' drag gestures are not passed to the bar (C-74#39).
	# Taps still select, and a swipe up still opens the bag.
	for cell: UiItemCell in _bar.cells():
		for connection: Dictionary in cell.get_signal_connection_list(&"gesture"):
			if (connection.callable as Callable).get_object() == _bar: cell.gesture.disconnect(connection.callable)
		cell.gesture.connect(func(outcome: Dictionary): if outcome.get("kind") == &"swipe_up": open_bag())
	_ui.add_child(_bar)
	_keys = UiActionKey.new(true)   # C-186: the clay key (owner Q-285, C-185 §3.7)
	_keys.name = "ActionKey"
	_keys.switch_visible = false   # one action here: no switch key, no radial
	_keys.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ui.add_child(_keys)
	_key = _keys.key()
	_key.name = "MainKey"
	_key.pressed_down.connect(_on_key)
	_key.released.connect(func(): _key_held = false)   # C-236: hits go on while the key is held
	# C-148: the main HUD's Energy chip; the scene puts it in its top bar (it is not under _ui).
	energy_chip = UiEnergyChip.new(true)   # C-186: the clay capsule (C-185 §3.1 A)
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
	_tip.set_glass()   # C-186: the dark glass guide bar (C-185 §3.1 C)
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
	# C-186: the clay key's bottom 10 above the bar, 8 from the right (C-185 §3.7, the owner's attachment-1820).
	var key_bottom := bottom + UiTokens.SIZE_QUICK_BAR_H + UiTokens.SIZE_CLAY_KEY_ABOVE_BAR
	var group := _keys.get_combined_minimum_size()
	if is_instance_valid(_side_button):
		# Left of the action key on its baseline: clear of the quick bar under it and of the key (C-74#17).
		_side_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_side_button.offset_left = UiTokens.SIZE_QUICK_BAR_X
		_side_button.offset_right = UiTokens.SIZE_QUICK_BAR_X + _side_button.custom_minimum_size.x
		_side_button.offset_bottom = -key_bottom
		_side_button.offset_top = -key_bottom - _side_button.custom_minimum_size.y
	_keys.offset_right = -UiTokens.SIZE_CLAY_KEY_RIGHT
	_keys.offset_left = -UiTokens.SIZE_CLAY_KEY_RIGHT - group.x
	_keys.offset_bottom = -key_bottom
	_keys.offset_top = -key_bottom - group.y
	# C-107: the phone button right-aligned 12 (its Ø36 glass, in a 44 hit area) above the action key (C-L3).
	var inset := (UiTokens.SIZE_TOUCH_MIN - UiTokens.SIZE_HUD_SIDE_BUTTON) * 0.5
	var phone_bottom := key_bottom + group.y + PHONE_BUTTON_GAP - inset
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
	var was_visible := _tip.visible
	var changed := step != tip_step
	if changed:
		tip_step = step
		if step != _tip_closed: _tip_closed = ""
		if not step.is_empty(): _tip.show_tip(Guide.text(step))
	_tip.visible = not tip_step.is_empty() and tip_step != _tip_closed and not held and _bag == null and phone == null \
		and not (drop_down != null and drop_down.showing) and _energy_layer == null
	# Under the top bar (the main farm puts its TipCard under the HUD, clear of the key and the bar).
	if _tip.visible: _tip_box.offset_top = tip_top if tip_top >= 0.0 else TIP_TOP + _safe_top()
	# MS-19: a new step slides in from 8 above (160); the bar fades back in (120) when an overlay closes.
	if _tip.visible and (changed or not was_visible): _tip_in(changed and was_visible)

## MS-19: the guide bar comes in — a new step from y −8 (160, after the old one's 120 fade), or a 120 fade back.
func _tip_in(new_step: bool) -> void:
	if UiMotion.reduced or not _tip.is_inside_tree():
		_tip.modulate.a = 1.0
		return
	if _tip.has_meta(&"_tip_tw"):
		var old = _tip.get_meta(&"_tip_tw")
		if old is Tween and (old as Tween).is_valid(): (old as Tween).kill()
	var tw := UiMotion.tween(_tip, UiTokens.MOTION_EASING_STANDARD)
	_tip.modulate.a = 0.0
	if new_step:
		tw.tween_interval(UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
		var rest := _tip_box.offset_top
		tw.tween_callback(func(): _tip_box.offset_top = rest - UiTokens.MOTION_OFFSET_GUIDE_ENTER)
		tw.tween_property(_tip_box, "offset_top", rest, UiMotion.secs(UiTokens.MOTION_DURATION_QUICK_MS))
		tw.parallel().tween_property(_tip, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_QUICK_MS))
	else:
		tw.tween_property(_tip, "modulate:a", 1.0, UiMotion.secs(UiTokens.MOTION_DURATION_FAST_MS))
	_tip.set_meta(&"_tip_tw", tw)

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
	land_pending()
	return true

func phone_open() -> bool: return phone != null

## C-L5: right 14, its bottom 8 above the phone button; on a short screen it may cover the top bar (under its scrim),
## never past the safe top.
func _place_phone() -> void:
	var glass_top := phone_button.position.y + (UiTokens.SIZE_TOUCH_MIN - UiTokens.SIZE_HUD_SIDE_BUTTON) * 0.5
	phone.place(Vector2(_ui.size.x - PHONE_RIGHT, glass_top - PHONE_ABOVE_BUTTON), UiTokens.SIZE_SCREEN_SAFE_INSET + _safe_top())

## The current row tapped in the phone: the phone closes and the guide's tip for it shows again (C-85 ⑧-B), nothing
## more. C-175: a row is a milestone and the tip its next step (Feed a hen may first ask to sow a carrot), so the row
## is matched against the current row, not the tip.
func _on_task_pressed(key: String) -> void:
	close_phone()
	if key == Tasks.current(farm, server_now(), _reached()):
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
	# Follows the count both ways: it holds itself up only on Sell an egg (C-175), so a lower count is a reset parcel.
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

# ------------------------------------------------------------------ Reward feedback and the bag's new dot (C-186)

## The Energy float joins the item lines of a reply announced this recently (send() announces both at once).
const ENERGY_JOINS_MS := 50
## Which items the bag held when it was last opened, per parcel on this device: an item whose count grew since shows
## C-185 P-01's `badge/unread` dot until the bag is opened again. Local only, never in the save (as PHONE_SEEN_PATH).
const BAG_SEEN_PATH := "user://dynamic_farm_local/bag_seen.json"
var bag_seen_path := BAG_SEEN_PATH
## Items marked new in the bag open now (id -> true).
var bag_fresh := {}
## Item float lines still up (id -> {line, count}): another gain of the item adds to it (MS-06).
var _gain_lines := {}
## The last reply's item lines (for the Energy line to queue after them).
var _float_batch := {}
## A gain came while nothing could fly (the bag or the phone open): the Bag end bumps when the bar is back.
var _land_waiting := false

## Where an item's flight lands (MS-04): the quick bar's `landing_for` (the slot holding it, the Seeds end for seeds,
## else the Bag end); before the bar has it, the slot holding it, else the Bag end.
func landing_for(id: String) -> Control:
	if _bar.has_method(&"landing_for"):
		var at = _bar.call(&"landing_for", id)
		if at is Control: return at
	var cell := _bar.cell_for(id)
	return cell if cell != null else _bar.bag_end()

## Call when the quick bar comes back (the bag or the phone closed): a gain that could not fly while they were open
## bumps the Bag end once, after the bar's slide back (M-16, 260).
func land_pending() -> void:
	if not _land_waiting or not is_inside_tree(): return
	_land_waiting = false
	var bag := _bar.bag_end()
	get_tree().create_timer(UiMotion.secs(UiTokens.MOTION_DURATION_MODERATE_MS)).timeout.connect(func():
		if is_instance_valid(bag) and bag.is_visible_in_tree(): UiMotion.land(bag))

## The items whose count grew since the bag was last opened here (none recorded: every item, once per device), and
## records the counts now; the dots stay for this opening.
func _take_bag_fresh() -> Dictionary:
	var raw = JSON.parse_string(FileAccess.get_file_as_string(bag_seen_path)) if FileAccess.file_exists(bag_seen_path) else null
	var all: Dictionary = raw if raw is Dictionary else {}
	var key := str(_data.get("block_id", ""))
	var seen = all.get(key)
	var counts := {}
	var fresh := {}
	for id: String in farm.get("bag", {}):
		var n := int(farm.bag[id])
		if n <= 0: continue
		counts[id] = n
		if n > int(seen.get(id, 0) if seen is Dictionary else 0): fresh[id] = true
	all[key] = counts
	DirAccess.make_dir_recursive_absolute(bag_seen_path.get_base_dir())
	var file := FileAccess.open(bag_seen_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all))
		file.close()
	return fresh
