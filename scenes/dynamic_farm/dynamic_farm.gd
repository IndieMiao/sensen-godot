extends Node3D
## Art scene; with `own_parcel` it also farms the owner's parcel (ParcelFarming, C-34).
## The host owns selection, network, identity, claims and return routing.
signal preview_ready(summary: Dictionary)
signal preview_error(message: String)
signal back_requested
## An approach (C-73) ended: "ok", "unreachable" or "cancelled".
signal approach_finished(result: String)

const Data = preload("res://modules/dynamic_farm/farm_data.gd")
const Walk = preload("res://modules/dynamic_farm/farm_walk.gd")
const Fieldkit = preload("res://modules/dynamic_farm/parcel_fieldkit.gd")
const GroundPaint = preload("res://modules/dynamic_farm/parcel_ground_paint.gd")
const Ground = preload("res://modules/dynamic_farm/farm_mesh.gd")
const Scenery = preload("res://modules/dynamic_farm/farm_scenery.gd")
const Shade = preload("res://modules/dynamic_farm/farm_shade.gd")
const EdgeDecor = preload("res://modules/dynamic_farm/farm_edge_decor.gd")
const CameraRules = preload("res://modules/farm/farm_camera.gd")
const Cliff = preload("res://modules/dynamic_farm/island_cliff.gd")
const SKY_SHADER = preload("res://modules/dynamic_farm/island_sky.gdshader")
const Controls = preload("res://scenes/dynamic_farm/dynamic_controls.gd")
const MergedAssembler = preload("res://modules/avatar/assembly/assembler_merged.gd")
const Building = preload("res://modules/dynamic_farm/farm_building.gd")
const ParcelFarm = preload("res://modules/dynamic_farm/parcel_farm.gd")
const Art = preload("res://modules/farm/farm_art.gd")
const Placement = preload("res://scenes/dynamic_farm/building_placement.gd")
## The main farm's pop and dust (a Homestead look swapped in), reused for a building just built (C-114).
const Fence = preload("res://scenes/p0/p0_fence.gd")
const HOUSE_DUST_SCALE := 4.0
const Farming = preload("res://scenes/dynamic_farm/parcel_farming.gd")
const FarmPath = preload("res://modules/dynamic_farm/farm_path.gd")
const LocalFarmStore = preload("res://modules/dynamic_farm/parcel_farm_local_store.gd")
const RemoteFarmStore = preload("res://modules/dynamic_farm/parcel_farm_remote_store.gd")
const ParcelItems = preload("res://modules/dynamic_farm/parcel_items.gd")
const PROFILE := "res://scenes/dynamic_farm/parcel_profile.gd"
## Over the parcel's own HUD (20) and under the host's loading panel (30, hidden once the parcel is up).
const PROFILE_LAYER := 25
## Development only: keep the own-parcel farm on the device instead of the C-31 server.
const LOCAL_SAVE_SETTING := "sensen/dynamic_farm/local_farm_save"
const SPEED := 3.75
## Background cloud drift in screen widths per second; negative drifts left. A group
## crosses a 1080-pixel-wide screen in about 100 s.
const CLOUD_DRIFT := 0.01
## A route is given up when the player gains less than this share of the walking speed for
## ROUTE_STUCK_S (something the route did not expect is in the way).
const ROUTE_STUCK_RATIO := 0.2
const ROUTE_STUCK_S := 0.5
## Standing this close to a cell (centre to centre, in cells) is close enough to work it.
const REACH_CELLS := 1.5
## The pail (C-153's art; C-151 wires it in): the pail in the right hand (BucketGesture, a child of the rig beside its
## Skeleton3D) and its actions, added to the rig's AnimationPlayer as the `pail` library. Fill draws at the well,
## Water pours on one cell; the pail shows only while one of them plays.
const PAIL_GESTURE = preload("res://assets/dynamic_farm/watering/bucket_gesture.tscn")
const PAIL_ACTIONS = preload("res://assets/dynamic_farm/watering/bucket_actions.tres")
const PAIL_LIBRARY := &"pail"
## Labour verbs played with the pail -> their action in PAIL_ACTIONS.
const PAIL_MOTIONS := {"fill": "draw", "water": "pour"}
## The scene gives up loading (its shade masks and the player's look) after this much time in drawn frames (C-168).
## Time with no frames does not count: building the scene in _ready (about 19 s under an emulator's software renderer),
## a lost Android render surface, the app in the background. Counted wall time from _ready, a slow build alone spent it,
## and Retry, building again, failed at its first frame.
const LOAD_LIMIT_S := 15.0
## One frame adds at most this much to the loading time: the first frame after a stall is not seconds of loading.
const LOAD_FRAME_CAP_S := 0.25
## The top bar's second row, the one-line place bar (C-186, C-185 §3.1 B): its drawn height.
const PLACE_ROW_H := float(UiTokens.SIZE_HUD_PLACE_H)
## C-186: ‹ and the task button take 40 wide in the clay row (Ø36 discs, 44 high), so the row keeps in 360.
const HUD_BUTTON_W := 40.0
const PIN_ICON := preload("res://assets/ui/icons/lucide/map-pin.svg")

var _args := {}
var _data := {}
var _walk: RefCounted
var _ground_paint: GroundPaint
var _placement_grid: Array[Node] = []
var _ground: Node3D
var _props: Node3D
var _plan := {}
var _edge_plan := {}
var _shade: Node
var _actor: Node3D
var _rig: Node3D
var _camera: Camera3D
var _environment: WorldEnvironment
var _clouds: ShaderMaterial
var _cloud_drift := 0.0
var _saved_environment: Environment
var _canvas: CanvasLayer
var _controls: Control
var _header: HBoxContainer
var _title: Label
var _status: Label
var _coins_capsule: PanelContainer
## The top bar's second row: the parcel's name over its status (C-108).
var _place_chip: PanelContainer
## The HUD avatar (C-H1): the profile (C-108).
var _avatar: UiHudAvatar
## The profile and the pages opened from it, over the parcel (parcel_profile.gd), else null.
var _profile: Control
var _profile_layer: CanvasLayer
var _coins: Label
var _coins_icon: TextureRect
var _movement := Vector2.ZERO
var _focus := Vector3.ZERO
var _zoom := 1.0
var _normal_size := 7.2
var _avatar_loaded := false
var _ready_sent := false
var _failed := false
var _back_sent := false
var _suspended := false
var _focused := true
var _overview := false
var _started_ms := 0
## Loading time so far in drawn frames (LOAD_LIMIT_S).
var _loading_s := 0.0
var _clip := ""
var _summary := {}
var _hint: Label
var _farming: Node3D
var _facing := Vector3.BACK
# The buildings (C-33 the first house, C-150 any type) on the owner's parcel, through ParcelFarming's save, by
# building id: {node, proxy, wire}; none in the art preview.
var _buildings := {}
var _build: UiCommandButton
## The type the Build key places (build_choice()), "" when it is hidden.
var _build_type := ""
var _placement: Placement
var _sending := false
var _paths: RefCounted
## Waypoints of the current approach; the stick cancels it.
var _route: Array[Vector3] = []
var _route_stuck_s := 0.0
## A labour clip is playing; the player holds still until it ends.
var _labour_left := 0.0
## The Energy card's `Show home` (C-148) holds the camera on the cottage until the player moves.
var _showing_house := false
## The pail in the hand (PAIL_GESTURE), made the first time Fill or Water plays; hidden between them.
var _pail: Node3D

func setup(args: Dictionary) -> void:
	_args = args.duplicate(true)

func _ready() -> void:
	_started_ms = Time.get_ticks_msec()
	_build_ui()
	get_viewport().size_changed.connect(_on_viewport_resized)
	if (_args.get("preview_only") != true and _args.get("own_parcel") != true) or not _args.get("farm") is Dictionary:
		_fail("This farm preview could not be opened.")
		return
	_data = Data.decode(_args.farm)
	if not _data.ok:
		_fail(_data.error)
		return
	if _args.get("dataset") != _data.dataset_version or _args.get("block_id") != _data.block_id:
		_fail("The selected farm has changed. Please select it again.")
		return
	_walk = Walk.new(_data)
	if not _walk.clear_position(_walk.position):
		_fail("This farm has no safe arrival point.")
		return
	_plan = Scenery.plan(_data,_walk)
	if not _plan.ok:
		_fail(_plan.error)
		return
	Shade.enforce_budget(_plan,_data,_walk)
	_ground = Ground.build(_data,_walk,_plan.recipe,true,Shade.can_widen(_plan,_data,_walk),
		1.0 if bool(_args.get("original_slope_material",false)) else 0.65)
	add_child(_ground)
	_ground_paint = GroundPaint.new(_data)
	for chunk: Dictionary in _ground.get_meta("shade_chunks"):
		for part: MeshInstance3D in chunk.meshes:
			part.material_override.set_shader_parameter("field_mask", _ground_paint.texture)
	_placement_grid = _ground.find_children("CoreGrid_*", "MeshInstance3D", false, false)
	add_child(Fieldkit.meadow(_data, _walk))
	var art := Scenery.build(_plan,_walk,_plan.recipe)
	if not art.ok:
		_fail(art.error)
		return
	_props = art.root
	add_child(_props)
	# Separate batches outside extension occupancy and shadow budgets; stones, bushes
	# and trees still block through the shared model-fitted profiles (Q-16).
	var core_art := Scenery.build(_plan.core_obstacles, _walk, _plan.recipe)
	if not core_art.ok:
		_fail(core_art.error)
		return
	core_art.root.name = "CoreObstacles"
	add_child(core_art.root)
	if _args.get("own_parcel") == true:
		_farming = Farming.new()
		_farming.name = "ParcelFarming"
		add_child(_farming)
	_setup_world()
	_shade = Shade.new()
	add_child(_shade)
	_shade.setup(_ground,_props,_plan,_data,_walk)
	if bool(_args.get("edge_decor_preview",false)):
		_edge_plan=EdgeDecor.plan(_data,_walk,_plan)
		var edge_art:=Scenery.build(_edge_plan,_walk,_plan.recipe)
		if not edge_art.ok:
			_fail(edge_art.error)
			return
		edge_art.root.name="EdgeDecorPreview"
		add_child(edge_art.root)
	_actor = Node3D.new()
	_actor.name = "PreviewPlayer"
	_actor.position = _walk.position
	add_child(_actor)
	var avatar := get_tree().root.get_node_or_null("Avatar")
	if avatar == null or avatar.get("loader") == null:
		_fail("The player appearance service is unavailable.")
		return
	_rig = avatar.create_rig()
	_rig.assembler = MergedAssembler.new()
	_rig.rotation.y = PI
	_rig.config_applied.connect(_on_avatar_ready,CONNECT_ONE_SHOT)
	_rig.part_load_failed.connect(func(_slot,_part,_error): _fail("The player appearance could not be loaded."))
	_actor.add_child(_rig)
	for child in _rig.get_children():
		if child.get_script() == preload("res://modules/avatar/assembly/rig_activity.gd"):
			child.reduced_distance = 50
			child.sleep_distance = 80
	avatar.follow_saved_outfit(_rig)
	_focus = _actor.position
	_place_camera()
	_facing = Vector3(_camera.global_basis.z.x, 0, _camera.global_basis.z.z).normalized()
	if _farming != null:
		var store = _args.get("farm_store")
		if not store is RefCounted or not store.has_method("enter") or not store.has_method("send"):
			var net := get_tree().root.get_node_or_null("Net")
			if bool(ProjectSettings.get_setting(LOCAL_SAVE_SETTING, false)): store = LocalFarmStore.new(_data.block_id)
			else: store = RemoteFarmStore.new(net.client if net != null else null, _data.block_id, _data.dataset_version)
		_paths = FarmPath.new(_walk)
		_farming.setup(_data, _walk, {"plan": _plan.core_obstacles, "root": core_art.root, "proxies": core_art.proxies, "recipe": _plan.recipe}, store, _canvas,
			self, {"layout": _plan.layout, "root": _props, "recipe": _plan.recipe})
		_hint.hide()
		_farming.state_changed.connect(_on_farm_changed)
		_farming.place_side_button(_build)
		# C-148: the parcel's Energy in the top bar, P0's chip just before the coins.
		# C-186 (C-185 §3.1 A, attachment-1820): the clay Energy capsule hangs on the avatar's right.
		_header.add_child(_farming.energy_chip)
		_header.move_child(_farming.energy_chip, _avatar.get_index() + 1)
		# C-107: the task button (C-H3), a clay disc since C-186, just before the coins.
		_header.add_child(_farming.task_button)
		_header.move_child(_farming.task_button, _coins_capsule.get_index())
		UiClay.round_button(_farming.task_button, HUD_BUTTON_W)
		_farming.tip_top = top_bar_bottom() + UiTokens.SPACE_S5
		_farming.bar_bottom = top_bar_bottom()
	# C-186 (C-185 §3.1 B, 6 item 1 by the owner's attachment-1820): the address alone; the cell counts were for us.
	_title.text = _data.address if not _data.address.is_empty() else _data.name
	_fit_place_chip()
	_summary = {"schema":4,"dataset":_data.dataset_version,"block_id":_data.block_id,
		"core_cells":_data.counts.core,"extension_cells":_data.counts.extension,
		"protected_cells":_data.protected.size(),"reserved_placement_cells":_walk.reserved.size(),
		"art_version":_plan.art_version,"layout_sha256":_plan.layout_sha256,
		"roles":_plan.roles,"instances":art.instances,"batches":art.batches,
		"placed_triangles":art.placed_triangles,"unique_triangles":art.unique_triangles,
		"shadow_budget_rejected":_plan.shadow_budget_rejected,"island_backdrop":true,
		"seed_hex":_data.seed_hex,"generator_version":_data.generator_version,
		"camera":{"pitch":43.0,"yaw":14.5,"keep_width":true},
		"source_origin":[_data.origin.x,_data.origin.y]}
	_summary.core_obstacles = {"roles":_plan.core_obstacles.roles, "instances":core_art.instances,
		"batches":core_art.batches, "placed_triangles":core_art.placed_triangles,
		"layout_sha256":_plan.core_obstacles.layout_sha256}
	_summary.outer = _plan.outer.duplicate()
	_summary.outer.reserved_cells = _walk.reserved.size()
	_summary.bank = _ground.get_meta("bank_metrics",{})
	_summary.slope_material={"clearing_linear_gain":_ground.get_meta("slope_material_linear_gain"),
		"batches":_ground.get_meta("slope_batches")}
	_summary.edge_decor={"enabled":not _edge_plan.is_empty(),"instances":_edge_plan.get("layout",[]).size(),
		"triangles":_edge_plan.get("triangles",0),"batches":_edge_plan.get("batches",0),
		"layout_sha256":_edge_plan.get("layout_sha256",""),"covered_cells":_edge_plan.get("covered_cells",0),
		"perimeter_cells":_edge_plan.get("perimeter_cells",0),"clusters":_edge_plan.get("clusters",[]).size()}

## Every save reply (ParcelFarming): the buildings as they stand, the Build key while a blueprint waits.
func _on_farm_changed(farm: Dictionary) -> void:
	if _failed: return
	var coins := int(farm.get("coins", 0))
	# MS-03: the number rolls to the new value (rising pops the coin, falling flashes) once the capsule has shown one.
	if _coins_capsule.visible and _coins.text.is_valid_int() and int(_coins.text) != coins:
		if not (UiMotion.rolling(_coins) and int(_coins.get_meta(&"_roll_to", coins)) == coins):
			_coins.set_meta(&"_roll_to", coins)
			UiMotion.roll(_coins, int(_coins.text), coins, "%d", _coins_icon)
	elif not UiMotion.rolling(_coins): _coins.text = str(coins)
	_coins_capsule.visible = true
	_sync_buildings(farm)
	_ground_paint.update(farm)
	_refresh_build()

## The saved buildings (ParcelFarm.buildings_of), or [] without the owner's farm.
func buildings_state() -> Array:
	return ParcelFarm.buildings_of(_farming.farm) if _farming != null else []

## The first type of the rules' `buildings` whose blueprint is in the bag, still under its limit at the farm's level
## (C-152: wells 2 from Lv3, 3 from Lv5) and with art here; "" when there is none.
func build_choice() -> String:
	if _farming == null: return ""
	var bag: Dictionary = _farming.farm.get("bag", {})
	var rules := ParcelFarm.rules()
	var types: Dictionary = rules.get("buildings", {})
	var built := buildings_state()
	var level := ParcelFarm.farm_level(_farming.farm)
	for type: String in types:
		if int(bag.get(types[type].blueprint, 0)) <= 0 or Building.kind(type).is_empty(): continue
		if built.filter(func(b): return b.type == type).size() < ParcelFarm.building_max(rules, type, level): return type
	return ""

func _refresh_build() -> void:
	_build_type = build_choice() if _placement == null else ""
	_build.visible = _build_type != ""
	if _build.visible: _build.label = "Build %s" % Building.kind(_build_type).name
	_build.reason = build_gap(_build_type) if _build.visible else ""

## C-181: the first material the type's `materials` (the barn's 20 Timber, 10 Stone) still lacks, as P0's `Need N more
## Timber`; "" when the bag has them all (the key places, and the server takes them with the blueprint).
func build_gap(type: String) -> String:
	if _farming == null or type.is_empty(): return ""
	var bag: Dictionary = _farming.farm.get("bag", {})
	var needs: Dictionary = ParcelFarm.rules().buildings[type].get("materials", {})
	for item: String in needs:
		var short := int(needs[item]) - int(bag.get(item, 0))
		if short > 0: return "Need %d more %s" % [short, _farming.item_name(item)]
	return ""

func _show_placement_grid(shown: bool) -> void:
	for part: MeshInstance3D in _placement_grid: part.visible = shown

func begin_placement() -> void:
	if not _build.visible: return
	var type := _build_type
	var base := Building.base_of(ParcelFarm.rules().buildings[type])
	# A press still walking to its cell is given up; one already working finishes under the preview.
	if not _route.is_empty(): _end_route("cancelled")
	_movement = Vector2.ZERO
	_controls.reset()
	_controls.process_mode = Node.PROCESS_MODE_DISABLED
	_farming.held = true
	var obstacles: Dictionary = _farming.obstacle_cells()
	var taken := Building.blocked(obstacles, _farming.farm)
	var walk_blocked := _walk_blocked(obstacles)
	var path: Dictionary = _farming.protected_path()
	var cleared := _cleared()
	var start = Building.start_spot(_data, _walk.cell_at(_actor.position), base, taken, path, walk_blocked, type, obstacles,
		cleared.taken, cleared.walk_blocked)
	_placement = Placement.new()
	_show_placement_grid(true)
	add_child(_placement)
	_placement.setup(type, base, _data, _walk, _camera, _canvas, taken, path, walk_blocked,
		start.at if start != null else _walk.cell_at(_actor.position) - Building.middle(base), cleared,
		start.rotation if start != null else 0)
	_placement.confirmed.connect(_on_place_confirmed)
	_placement.cancelled.connect(end_placement)
	_refresh_build()
	_play("idle")
	_focus = Building.center(_walk, _placement.at, base, _placement.rotation_steps)
	_overview = false
	_place_camera()

## Cells walking cannot use besides a new footprint: solid core obstacles, the buildings standing and reserved cells.
func _walk_blocked(obstacles: Dictionary) -> Dictionary:
	return Building.solid(_plan.core_obstacles.layout, obstacles).merged(_walk.reserved).merged(ParcelFarm.building_cells(_farming.farm))

## Building.reason's `taken` and `walk_blocked` with every core obstacle cleared (C-175: what clearing would allow).
func _cleared() -> Dictionary:
	return {"taken": Building.blocked({}, _farming.farm), "walk_blocked": _walk_blocked({})}

func end_placement() -> void:
	if _placement == null: return
	_placement.queue_free()
	_placement = null
	_show_placement_grid(false)
	_sending = false
	_farming.held = false
	_controls.process_mode = Node.PROCESS_MODE_INHERIT
	_controls.reset()
	_refresh_build()

## Build: the place_building command through ParcelFarming's save (Q-44); the reply builds it (state_changed).
func _on_place_confirmed(at: Vector2i, rotation_steps: int) -> void:
	if _sending or _farming.busy: return
	_sending = true
	var type := _placement.type
	var before := _buildings.keys()
	var reply: Dictionary = await _farming.send({"type":"place_building", "building":type, "x":at.x, "y":at.y,
		"rotation":rotation_steps})
	_sending = false
	if reply.get("ok", false) and is_inside_tree():
		for b: Dictionary in buildings_state():
			if not before.has(int(b.id)): _pop(b)
	if not is_inside_tree() or _placement == null: return
	# A refused spot keeps the preview, judged again on the farm the reply brought; anything else ends it.
	if reply.get("ok", false) or str(reply.get("code", "")) not in ["CELL_OCCUPIED", "BUILDING_OVERLAP"]:
		end_placement()
	else:
		var obstacles: Dictionary = _farming.obstacle_cells()
		_placement.retake(Building.blocked(obstacles, _farming.farm), _walk_blocked(obstacles), _cleared())

## Build succeeded (C-114): the building the reply just built grows in with the main farm's overshoot and puffs
## dust round its footprint. One that comes with the save (reopening, a refused Build) only stands there.
## The main farm's puffs are sized for a fence post; round the 2.4 m cottage each one is HOUSE_DUST_SCALE times
## larger, so they read as the clouds of the owner's reference (C-103 screenshot 704).
func _pop(building: Dictionary) -> void:
	var node = _buildings.get(int(building.id), {}).get("node")
	if not node is Node3D: return
	var before := get_child_count()
	Fence.pop_in(self, [node])
	for point in Building.rim(_walk, Building.at_of(building), Building.base_of(building), int(building.rotation)):
		Fence.dust(self, point)
	for i in range(before, get_child_count()):
		var puff := get_child(i) as CPUParticles3D
		if puff == null: continue
		puff.scale_amount_min *= HOUSE_DUST_SCALE
		puff.scale_amount_max *= HOUSE_DUST_SCALE

## The scene follows the save's buildings: new ones stand (no pop; Build pops its own), gone ones leave with their
## walls. A building is matched by id and its spot, so one the save moved or turned is built again.
func _sync_buildings(farm: Dictionary) -> void:
	var wanted := {}
	for b: Dictionary in ParcelFarm.buildings_of(farm): wanted[int(b.id)] = b
	for id: int in _buildings.keys():
		if wanted.has(id) and _spot(wanted[id]) == _spot(_buildings[id].state): continue
		var built: Dictionary = _buildings[id]
		for proxy in built.proxies: _walk.remove_prop(proxy)
		for node in [built.node] + built.wires:
			if is_instance_valid(node): node.queue_free()
		_buildings.erase(id)
	for id: int in wanted:
		if not _buildings.has(id): _build_building(wanted[id])

static func _spot(b: Dictionary) -> String:
	return "%s %d %d %d %d %d" % [b.type, int(b.x), int(b.y), int(b.width), int(b.depth), int(b.rotation)]

## A saved building, its model (if this client has art for its type) and wall profiles (C-19's model-fitted walking;
## a livestock building's fence runs and parts, its entry open, C-154); a player standing on the new walls steps out.
## A type without art here still keeps its cells from farming (ParcelFarm.building_cells) but has nothing to show or
## bump into.
func _build_building(building: Dictionary) -> void:
	var type := str(building.type)
	var at := Building.at_of(building)
	var base := Building.base_of(building)
	var turns := int(building.rotation)
	var node := Node3D.new()
	node.name = "Building%d" % int(building.id)
	node.transform = Building.transform(_walk, at, base, turns)
	var model := Building.model(type, base, _walk.cell_m)
	if model != null: node.add_child(model)
	add_child(node)
	var proxies := Building.proxies(_walk, type, at, base, turns)
	var wires := []
	for proxy in proxies:
		_walk.add_prop(proxy)
		if not get_tree().debug_collisions_hint: continue
		var wire := MeshInstance3D.new()
		wire.mesh = proxy.debug_wire()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.albedo_color = Color("00e5ff")
		wire.material_override = material
		wire.transform = proxy.pose
		add_child(wire)
		wires.append(wire)
	_buildings[int(building.id)] = {"state": building.duplicate(), "node": node, "proxies": proxies, "wires": wires}
	if _actor != null and not _walk.clear_position(_walk.position):
		_walk.position = _step_out(_walk.position)
		_actor.position = _walk.position
		_focus = _actor.position
		_place_camera()

## The nearest clear point to `from`, searched in rings of 0.1 m.
func _step_out(from: Vector3) -> Vector3:
	for ring in range(1, 40):
		for k in 32:
			var p := from + Vector3.FORWARD.rotated(Vector3.UP, TAU * k / 32.0) * ring * 0.1
			if _walk.clear_position(p): return p
	return _walk.point(_data.spawn)

# For the parcel's opaque silhouettes use two coverage samples instead of four;
# never raise a player's lower setting. This is viewport-local, not a project
# default. Multiple previews in one viewport release the original setting last.
const PARCEL_AA_LEASE := &"sensen_dynamic_farm_aa_lease"
var _aa_view: Viewport

func _take_parcel_aa() -> void:
	if is_instance_valid(_aa_view): return
	var view := get_viewport()
	if view.has_meta(PARCEL_AA_LEASE):
		view.get_meta(PARCEL_AA_LEASE).users += 1
	elif view.msaa_3d > Viewport.MSAA_2X:
		view.set_meta(PARCEL_AA_LEASE, {"original": view.msaa_3d, "users": 1})
		view.msaa_3d = Viewport.MSAA_2X
	else:
		return
	_aa_view = view

func _exit_tree() -> void:
	_release_parcel_aa()

func _release_parcel_aa() -> void:
	if not is_instance_valid(_aa_view) or not _aa_view.has_meta(PARCEL_AA_LEASE): return
	var lease: Dictionary = _aa_view.get_meta(PARCEL_AA_LEASE)
	lease.users -= 1
	if lease.users == 0:
		if _aa_view.msaa_3d == Viewport.MSAA_2X:
			_aa_view.msaa_3d = lease.original
		_aa_view.remove_meta(PARCEL_AA_LEASE)
	_aa_view = null

func _setup_world() -> void:
	_take_parcel_aa()
	var env := Environment.new()
	_clouds = ShaderMaterial.new()
	_clouds.shader = SKY_SHADER
	env.sky = Sky.new()
	env.sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky.sky_material = _clouds
	env.background_mode = Environment.BG_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.90,0.88,0.84)
	env.ambient_light_energy = 0.42
	_environment = WorldEnvironment.new()
	_environment.environment = env
	add_child(_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Shade.SUN_DEGREES
	sun.light_color = Color(1.0,0.905,0.755)
	sun.light_energy = 1.16
	sun.shadow_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	sun.shadow_opacity = 0.64
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.4
	sun.directional_shadow_max_distance = 30.0
	sun.directional_shadow_fade_start = 1.0
	sun.directional_shadow_pancake_size = 4.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(_camera)
	_camera.make_current()
	_normal_size = CameraRules.close_view_size(get_viewport().get_visible_rect().size) * CameraRules.P0_VIEW_K

func _on_avatar_ready(_config) -> void:
	var merged := _rig.find_children("merged_mesh","MeshInstance3D",true,false)
	if merged.is_empty() or (merged[0] as MeshInstance3D).mesh == null or (merged[0] as MeshInstance3D).mesh.get_surface_count() == 0:
		_fail("The player appearance is incomplete.")
		return
	_avatar_loaded = true
	_play("idle")

func _process(delta: float) -> void:
	if _failed or _suspended or _walk == null: return
	if _clouds != null:
		_cloud_drift += CLOUD_DRIFT * delta
		_clouds.set_shader_parameter("drift", _cloud_drift)
	if not _ready_sent:
		if _avatar_loaded and _shade.complete:
			_ready_sent = true
			_summary.shadows = _shade.metrics.duplicate(true)
			_summary.ready_ms = Time.get_ticks_msec() - _started_ms
			preview_ready.emit(_summary.duplicate(true))
			# Only once the scene is up: building it stalls the main thread for seconds, and an
			# HTTP request started during that stall times out (V-123).
			if _farming != null: _farming.enter()
		elif loading_timed_out(delta):
			_fail("The farm preview could not finish loading.")
		return
	if not _focused or _placement != null: return
	var dt := clampf(delta,0,0.1)
	var input := _movement
	input = input.limit_length(1.0)
	# Until the save is applied the parcel is covered; the player waits at the arrival point.
	if _farming != null and not _farming.loaded(): input = Vector2.ZERO
	var steering := not input.is_zero_approx()
	var moving := false
	if _labour_left > 0.0:
		# The labour clip holds the player still, stick or not (the main farm's labour beat).
		_labour_left -= dt
		if _labour_left <= 0.0:
			_play("idle")
			_put_pail_away()
	else:
		if steering and not _route.is_empty(): _end_route("cancelled")
		if not _route.is_empty():
			moving = _follow_route(dt)
		else:
			var right := _camera.global_basis.x
			right.y = 0
			var forward := -_camera.global_basis.z
			forward.y = 0
			var direction := right.normalized()*input.x-forward.normalized()*input.y
			var previous: Vector3 = _walk.position
			_walk.move(direction*SPEED*dt)
			_actor.position = _walk.position
			moving = _actor.position.distance_to(previous) > 0.0001
			# Turn toward the stick even when blocked, so the key can target what the player pushes against.
			if not direction.is_zero_approx(): _facing = direction.normalized()
			if moving:
				_actor.look_at(_actor.position+direction,Vector3.UP)
				_play("run")
			else:
				_play("idle")
	if _farming != null:
		_farming.update(dt, _walk.cell_at(_actor.position + _facing * _walk.cell_m * 0.8), steering,
			_actor.position, _facing)
	if steering: _showing_house = false
	if not _overview and not _showing_house:
		var size := get_viewport().get_visible_rect().size
		var safe := Rect2(size*Vector2(0.23,0.26),size*Vector2(0.54,0.48))
		_focus += CameraRules.follow_shift(_camera,_actor.position,safe)
		if input.is_zero_approx() and _route.is_empty(): _focus = _focus.lerp(_actor.position,minf(dt*2.8,1.0))
		_place_camera()

## Adds one drawn frame (at most LOAD_FRAME_CAP_S of it) to the loading time; true once it passes LOAD_LIMIT_S.
func loading_timed_out(delta: float) -> bool:
	_loading_s += clampf(delta, 0.0, LOAD_FRAME_CAP_S)
	return _loading_s > LOAD_LIMIT_S

## The Energy card's Rest tile (`Show home`, C-148): the camera turns to the cottage and stays there until the
## player moves; it never walks the player there or rests for them (LOCK-09: tiles only guide).
func show_house() -> void:
	var home := ParcelFarm.home_building(_farming.farm) if _farming != null else {}
	var node = _buildings.get(int(home.get("id", -1)), {}).get("node")
	if not node is Node3D: return
	_focus = node.position
	_overview = false
	_showing_house = true
	_place_camera()

## Walks the player beside `cells` (8 neighbours, sides preferred) and turns them to face the
## cells, along a route around everything the walker collides with (C-73). Returns "ok" there,
## "unreachable" when no route exists or the walk stalls, "cancelled" when the stick or a pause
## ends it first. Already within reach, it only turns.
func approach(cells: Array) -> String:
	if _walk == null or cells.is_empty(): return "unreachable"
	if not _route.is_empty(): _end_route("cancelled")
	_paths.forget()
	var goals: Dictionary = _paths.stand_cells(cells)
	if goals.has(_walk.cell_at(_walk.position)) or _within_reach(cells):
		_face_cells(cells)
		return "ok"
	var route: Array[Vector3] = _paths.route(_walk.position, goals)
	if route.is_empty(): return "unreachable"
	_route = route
	_route_stuck_s = 0.0
	var result: String = await approach_finished
	if result == "ok": _face_cells(cells)
	return result

## Plays the main farm's labour clip for `verb` (AnimPlaceholders.clip_for) facing `cells`,
## holding the player still for `seconds`. Presentation only: commands are the caller's.
## C-151: Fill and Water play the pail's own actions with the pail in hand (PAIL_MOTIONS).
func labour(verb: String, cells: Array, seconds: float) -> void:
	_face_cells(cells)
	_labour_left = seconds
	if PAIL_MOTIONS.has(verb) and _take_pail():
		_clip = ""   # the same action twice in a row (watering cell after cell) starts again
		_play("%s/%s" % [PAIL_LIBRARY, PAIL_MOTIONS[verb]])
		return
	_put_pail_away()
	_play(AnimPlaceholders.clip_for(verb))
	if AnimPlaceholders.is_placeholder(verb) and _rig != null: AnimPlaceholders.play_fallback(_rig, seconds)

## How long `verb`'s labour plays: a pail action its own length (Fill 2.22 s, Water 2.28 s), else `default`.
func labour_seconds(verb: String, default: float) -> float:
	var motion = PAIL_MOTIONS.get(verb)
	return PAIL_ACTIONS.get_animation(motion).length if motion != null and PAIL_ACTIONS.has_animation(motion) else default

## The pail in the right hand with its actions on the rig's player; false without a rig (nothing to hold it).
func _take_pail() -> bool:
	var player := _rig.get_node_or_null("AnimationPlayer") as AnimationPlayer if _rig != null else null
	if player == null or _rig.get_node_or_null("Skeleton3D") == null: return false
	if not player.has_animation_library(PAIL_LIBRARY): player.add_animation_library(PAIL_LIBRARY, PAIL_ACTIONS)
	if _pail == null:
		_pail = PAIL_GESTURE.instantiate() as Node3D
		_pail.name = "BucketGesture"   # the actions' tracks name it
		_rig.add_child(_pail)
	_pail.visible = true
	return true

func _put_pail_away() -> void:
	if _pail != null: _pail.visible = false

## Standing on a cell beside `cells`, not on one of them, near enough to reach.
func _within_reach(cells: Array) -> bool:
	var here: Vector2i = _walk.cell_at(_walk.position)
	if here in cells: return false
	for cell: Vector2i in cells:
		var d: Vector2i = cell - here
		if absi(d.x) <= 1 and absi(d.y) <= 1 and _walk.position.distance_to(_walk.point(cell)) <= REACH_CELLS * _walk.cell_m:
			return true
	return false

func _face_cells(cells: Array) -> void:
	var centre := Vector3.ZERO
	for cell: Vector2i in cells: centre += _walk.point(cell)
	var to: Vector3 = centre / cells.size() - _walk.position
	to.y = 0
	if to.length() < 0.01: return
	_facing = to.normalized()
	_actor.look_at(_actor.position + _facing, Vector3.UP)

## One frame along the route at walking speed; true when the player moved.
func _follow_route(dt: float) -> bool:
	var previous: Vector3 = _walk.position
	var budget := SPEED * dt
	while budget > 0.00001 and not _route.is_empty():
		var to: Vector3 = _route[0] - _walk.position
		to.y = 0
		var length := to.length()
		if length <= budget:
			_walk.move(to)
			budget -= length
			if _walk.position.distance_to(_route[0]) > 0.02: break
			_route.pop_front()
		else:
			_walk.move(to / length * budget)
			budget = 0.0
	_actor.position = _walk.position
	var step: Vector3 = _walk.position - previous
	step.y = 0
	if step.length() > 0.0001:
		_facing = step.normalized()
		_actor.look_at(_actor.position + _facing, Vector3.UP)
		_play("run")
	if _route.is_empty():
		_play("idle")
		_end_route("ok")
	elif step.length() < SPEED * dt * ROUTE_STUCK_RATIO:
		_route_stuck_s += dt
		if _route_stuck_s >= ROUTE_STUCK_S:
			_play("idle")
			_end_route("unreachable")
	else:
		_route_stuck_s = 0.0
	return step.length() > 0.0001

func _end_route(result: String) -> void:
	_route.clear()
	_route_stuck_s = 0.0
	approach_finished.emit(result)

func _place_camera() -> void:
	if _camera == null: return
	_camera.size = _normal_size * _zoom
	CameraRules.place(_camera,_focus)
	CameraRules.fit_ground_depth(_camera, Cliff.LOWEST_Y, 5.0)

func set_review_overview(enabled: bool) -> void:
	# Review-only capture hook. Normal interaction retains the existing player-scale camera.
	if not _ready_sent: return
	_overview = enabled
	_controls.reset()
	if enabled:
		_focus = Vector3.ZERO
		_place_camera()
		var extent: Vector2 = Vector2(_data.grid_size)*_data.cell_m
		var box := AABB(Vector3(-extent.x*0.5,Cliff.LOWEST_Y,-extent.y*0.5),Vector3(extent.x,5.0-Cliff.LOWEST_Y,extent.y))
		var size := get_viewport().get_visible_rect().size
		CameraRules.fit(_camera,box,Rect2(Vector2(20,112),size-Vector2(40,172)))
		CameraRules.fit_ground_depth(_camera,Cliff.LOWEST_Y,5.0)
	else:
		_focus = _actor.position
		_place_camera()

func _play(clip: String) -> void:
	if _rig == null or clip == _clip: return
	_clip = clip
	_rig.play_motion(clip)

func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 20
	add_child(_canvas)
	_controls = Controls.new()
	_canvas.add_child(_controls)
	_controls.movement_changed.connect(func(value: Vector2): _movement = value)
	_controls.zoom_changed.connect(func(factor: float):
		_zoom = clampf(_zoom*factor,0.8,1.4)
		_overview = false
		_place_camera())
	_controls.tapped.connect(_on_tapped)
	_controls.recenter_requested.connect(func():
		if _actor != null:
			_focus = _actor.position
			_overview = false
			_place_camera())
	# Top bar (C-74; UI v3 since C-105, docs/design/ui-v3-2026-11-24 §4.1 / C-L2): over the scene, in glass (S-2), two
	# rows as the main HUD's (LOCK-06: the HUD row, the location chip under it). Row 1: a Ø36 glass Back in its 44 hit
	# area, the HUD avatar (C-H1, C-108: it opens the profile), and on one's own parcel its Energy (C-148) and coins
	# (C-59) in the C-H4 glass capsule at the right. Row 2: the parcel's name over its status in a glass capsule, as wide
	# as its lines. 12 from the screen's sides, safe top + 8.
	_header = HBoxContainer.new()
	_header.name = "TopBar"
	_header.theme = UiKit.theme()
	# C-186: the clay row (‹, avatar, Energy, tasks, coins) is 4 apart (S2) so it keeps inside a 360 screen (C-185 fig-03).
	_header.add_theme_constant_override(&"separation", UiTokens.SPACE_S2)
	_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_header.offset_left = UiTokens.SIZE_SCREEN_EDGE - (HUD_BUTTON_W - UiTokens.SIZE_HUD_CLAY_BUTTON) * 0.5
	_header.offset_right = -UiTokens.SPACE_S4   # C-186: the coins capsule's clay edge 8 from the side
	_header.offset_top = UiTokens.SIZE_SCREEN_SAFE_INSET + _safe_top()
	_header.offset_bottom = _header.offset_top + UiTokens.SIZE_HUD_AVATAR_V3
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_header)
	var back := UiGlassButton.new(null, UiGlassButton.Glyph.BACK)
	back.name = "Back"
	back.tooltip_text = "Back"
	back.pressed.connect(_request_back)
	UiClay.round_button(back, HUD_BUTTON_W)   # C-186: a cream clay disc (C-185 §3.1 B)
	_header.add_child(back)
	_avatar = UiHudAvatar.new()
	_avatar.clay = true   # C-186: the cream clay rounded square, no empty ring (F-02)
	_avatar.pressed.connect(open_profile)
	_header.add_child(_avatar)
	var spacer := Control.new()
	spacer.name = "Spacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(spacer)
	# One's own parcel: its coins (C-59, apart from the main farm's), since C-186 a cream clay capsule with the big coin
	# pressed on its left end (C-185 §3.1 A, attachment-1820), at the right.
	_coins_capsule = PanelContainer.new()
	_coins_capsule.name = "Coins"
	_coins_capsule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coins_capsule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var coin_box := UiClay.face(UiTokens.SIZE_HUD_CLAY_RADIUS)
	coin_box.content_margin_left = 2.0
	coin_box.content_margin_right = 10.0
	coin_box.content_margin_top = 2.0
	coin_box.content_margin_bottom = 2.0
	_coins_capsule.add_theme_stylebox_override(&"panel", coin_box)
	_coins_capsule.custom_minimum_size = Vector2(56, 32)
	_coins_capsule.visible = false
	var coin_row := HBoxContainer.new()
	coin_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_row.add_theme_constant_override(&"separation", UiTokens.SPACE_S2)
	_coins_capsule.add_child(coin_row)
	_coins_icon = UiKit.icon(UiArt.COIN, 26.0)
	_coins_icon.name = "Coin"
	_coins_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_row.add_child(_coins_icon)
	_coins = UiKit.label("0", UiTokens.STYLE_C14_XB, UiTokens.COLOR_HUD_CLAY_INK)
	_coins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coins.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coin_row.add_child(_coins)
	_header.add_child(_coins_capsule)
	# Row 2 (C-186, C-185 §3.1 B): the address on one line in dark glass with the red pin, under the coins at the right;
	# no › (tapping it does nothing).
	_place_chip = PanelContainer.new()
	_place_chip.name = "Place"
	_place_chip.theme = UiKit.theme()
	_place_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_chip.add_theme_stylebox_override(&"panel",
		UiClay.padded(UiClay.glass_dark(UiTokens.SIZE_HUD_PLACE_H * 0.5), UiTokens.SPACE_S4, 0.0))
	_place_chip.custom_minimum_size.y = UiTokens.SIZE_HUD_PLACE_H
	_place_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_place_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_place_chip.offset_top = _header.offset_bottom + UiTokens.SPACE_S2
	_place_chip.offset_bottom = _place_chip.offset_top + UiTokens.SIZE_HUD_PLACE_H
	_place_chip.offset_right = -UiTokens.SIZE_SCREEN_EDGE
	_canvas.add_child(_place_chip)
	var place_row := HBoxContainer.new()
	place_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place_row.add_theme_constant_override(&"separation", UiTokens.SPACE_S2)
	_place_chip.add_child(place_row)
	var pin := UiKit.icon(PIN_ICON, UiTokens.SIZE_HUD_PLACE_PIN)
	pin.name = "Pin"
	pin.modulate = UiTokens.COLOR_HUD_PIN
	pin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	place_row.add_child(pin)
	_title = UiKit.label("Dynamic farm", UiTokens.STYLE_TYPE_LABEL_ON_DARK)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_override(&"font", UiKit.font(&"extrabold"))
	_title.add_theme_font_size_override(&"font_size", UiTokens.SIZE_HUD_PLACE_FONT)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.custom_minimum_size.x = 0
	place_row.add_child(_title)
	_status = _title   # one line since C-186 (no separate status line)
	_fit_place_chip()
	_controls.top_exclusion_y = top_bar_bottom()
	_hint = UiKit.label("Art preview · Walk and explore", UiTokens.STYLE_CAPTION_B12, UiTokens.COLOR_SECONDARY)
	_hint.theme = UiKit.theme()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_bottom = -12
	_hint.offset_top = -34
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_hint)
	_build = UiCommandButton.new("Build Cottage", UiCommandButton.Kind.PRIMARY)
	_build.name = "Build"
	_build.theme = UiKit.theme()
	# 180 × 48; ParcelFarming places it beside the action key (place_side_button), clear of the key and quick bar.
	_build.custom_minimum_size = Vector2(180, 48)
	_build.clay = true   # C-186: the clay side key beside the clay action key (C-185 §3.1 E)
	_build.visible = false
	_build.activated.connect(begin_placement)
	_build.unavailable_pressed.connect(func(reason: String): if _farming != null: _farming.show_notice(reason))
	_canvas.add_child(_build)

## The place capsule as wide as its longer line (name or status), at most the screen less its 12 sides; past that
## the lines cut with … (a Label that may cut asks for no width of its own, so the width is measured here).
func _fit_place_chip() -> void:
	if _place_chip == null or not is_inside_tree(): return
	var widest := 0.0
	if not _title.text.is_empty():
		var font := _title.get_theme_font(&"font")
		widest = font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _title.get_theme_font_size(&"font_size")).x
	var box := _place_chip.get_theme_stylebox(&"panel")
	var sides := box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) if box != null else 0.0
	sides += UiTokens.SIZE_HUD_PLACE_PIN + UiTokens.SPACE_S2
	var room := get_viewport().get_visible_rect().size.x - UiTokens.SIZE_SCREEN_EDGE * 2.0 - sides
	_title.custom_minimum_size.x = ceilf(minf(widest, maxf(0.0, room)))
	_place_chip.offset_left = _place_chip.offset_right - _place_chip.get_combined_minimum_size().x

## Where the top bar ends (its second row's bottom, a 34 two-line capsule), in canvas units: the world's touches start
## under it and the farming tip sits under it.
func top_bar_bottom() -> float:
	return UiTokens.SIZE_SCREEN_SAFE_INSET + _safe_top() + UiTokens.SIZE_HUD_AVATAR_V3 + UiTokens.SPACE_S2 + PLACE_ROW_H \
		+ UiTokens.SPACE_S2

## Top system inset (status bar, notch) in UI units; 0 on desktop (as P0Ui.safe_top).
func _safe_top() -> float:
	if not is_inside_tree() or not (OS.has_feature("android") or OS.has_feature("ios")): return 0.0
	return UIMetrics.safe_margins(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(),
		get_viewport().get_visible_rect().size, 0.0).y

## Screen point (canvas units) of `world` raised by `lift` metres: where a float or an item flight starts.
func screen_point(world: Vector3, lift := 0.0) -> Vector2:
	if _camera == null: return get_viewport().get_visible_rect().size * Vector2(0.5, 0.42)
	return _camera.unproject_position(world + Vector3(0, lift, 0))

func player_position() -> Vector3:
	return _actor.position if _actor != null else Vector3.ZERO

## A tap picks an outer object under it (C-60), else the ground cell, for the main key.
func _on_tapped(at: Vector2) -> void:
	if _farming == null or not _ready_sent or _camera == null or not _farming.loaded(): return
	var from := _camera.project_ray_origin(at)
	var dir := _camera.project_ray_normal(at)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	_farming.pick(_walk.cell_at(hit) if hit is Vector3 else Vector2i(-1, -1), from, dir)

func _request_back() -> void:
	if _back_sent: return
	_back_sent = true
	end_placement()
	_movement = Vector2.ZERO
	_controls.reset()
	back_requested.emit()

func is_back_navigation_locked() -> bool:
	if close_modal(): return true
	_request_back()
	return true

## Closes the page on top of the profile (the profile last), else the farming UI's open drawer (the bag), Energy
## card / panel or phone (C-107); false when none was open.
func close_modal() -> bool:
	if is_instance_valid(_profile):
		_profile.back()
		return true
	return _farming != null and (_farming.close_energy() or _farming.close_bag() or _farming.close_phone())

## The profile over the parcel (C-108; C-85 ①: the HUD avatar opens it): the parcel's HUD hides and its touches stop
## until it closes; Settings and the dressing room open from it (parcel_profile.gd). The player stops where they are.
func open_profile() -> Control:
	if is_instance_valid(_profile) or _suspended or _back_sent: return null
	end_placement()
	if not _route.is_empty(): _end_route("cancelled")
	_movement = Vector2.ZERO
	_controls.reset()
	if _farming != null:
		_farming.close_energy()
		_farming.close_bag()
		_farming.close_phone()
		if _farming.drop_down != null: _farming.drop_down.fold()
	_profile_layer = CanvasLayer.new()
	_profile_layer.name = "ProfileLayer"
	_profile_layer.layer = PROFILE_LAYER
	add_child(_profile_layer)
	_profile = load(PROFILE).open(_profile_layer, Vector3.ZERO, profile_home())
	_profile.closed.connect(_profile_closed)
	_canvas.visible = false
	_controls.process_mode = Node.PROCESS_MODE_DISABLED
	return _profile

func profile_open() -> bool: return is_instance_valid(_profile) and not _profile.is_queued_for_deletion()

func _profile_closed() -> void:
	_profile = null
	if is_instance_valid(_profile_layer): _profile_layer.queue_free()
	_profile_layer = null
	_controls.process_mode = Node.PROCESS_MODE_INHERIT
	_controls.reset()
	if not _suspended: _canvas.visible = true

## `My farm` on the profile: one's own parcel, its name and what grows there (the main farm's line: `Carrots ready to
## harvest`, `Carrots ready in 3h 32m`); the card closes the profile, back on the parcel. None on a preview.
func profile_home() -> Dictionary:
	if _args.get("own_parcel") != true or _data.is_empty(): return {}
	var status := home_status(_farming.farm if _farming != null else {}, _farming.server_now() if _farming != null else 0)
	return {"name": _data.address if not str(_data.get("address", "")).is_empty() else str(_data.get("name", "")),
		"status": status.text, "ready": status.ready, "pressed": Callable()}

## The earliest crop on the parcel, as the main farm's profile words it (P0ProfilePage._farm_status); "" with none.
static func home_status(farm: Dictionary, now_ms: int) -> Dictionary:
	var ready := ""
	var best := INF
	var growing := ""
	for cell in farm.get("crops", {}):
		var c: Dictionary = farm.crops[cell]
		# A dry crop (C-151) is not growing: its ripe_at is NEVER, and the main farm leaves an unwatered plot out too.
		if ParcelFarm.is_dry(c): continue
		var left := float(int(c.get("ripe_at", 0)) - now_ms)
		if left <= 0.0:
			if ready == "": ready = str(c.get("crop", ""))
		elif left < best:
			best = left
			growing = str(c.get("crop", ""))
	if ready != "": return {"text": "%s ready to harvest" % P0Logic.plural(_crop_name(ready)), "ready": true}
	if growing != "": return {"text": "%s ready in %s" % [P0Logic.plural(_crop_name(growing)), P0Logic.span(best)], "ready": false}
	return {"text": "", "ready": false}

static func _crop_name(id: String) -> String:
	var n := ParcelItems.name_of(id)
	return n if n != "" else id.trim_prefix("crop_").capitalize()

func suspend() -> void:
	if _suspended: return
	_release_parcel_aa()
	_suspended = true
	end_placement()
	if not _route.is_empty(): _end_route("cancelled")
	_labour_left = 0.0
	_put_pail_away()
	_movement = Vector2.ZERO
	_controls.reset()
	_canvas.visible = false
	if is_instance_valid(_profile_layer): _profile_layer.visible = false
	visible = false
	if _environment != null:
		_saved_environment = _environment.environment
		_environment.environment = null
	process_mode = Node.PROCESS_MODE_DISABLED

func resume() -> void:
	if not _suspended: return
	if _environment != null: _take_parcel_aa()
	process_mode = Node.PROCESS_MODE_INHERIT
	_suspended = false
	_back_sent = false
	visible = true
	# Back from the dressing room: the profile is still over the parcel, its HUD stays hidden under it.
	_canvas.visible = not profile_open()
	if is_instance_valid(_profile_layer): _profile_layer.visible = true
	if _environment != null: _environment.environment = _saved_environment
	if _camera != null: _camera.make_current()
	_movement = Vector2.ZERO
	_controls.reset()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_movement = Vector2.ZERO
		if _controls != null: _controls.reset()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true

func _fail(message: String) -> void:
	if _failed: return
	_failed = true
	_movement = Vector2.ZERO
	_status.text = message
	_fit_place_chip()
	preview_error.emit(message)

func _on_viewport_resized() -> void:
	_fit_place_chip()
	_normal_size = CameraRules.close_view_size(get_viewport().get_visible_rect().size) * CameraRules.P0_VIEW_K
	if _overview and _ready_sent:
		set_review_overview(true)
	else:
		_place_camera()
