extends Node3D
## SGODOT-341 / q(222): the existing Pip look beside the first bed, driven only by the resolved server view.
## No new collider, automatic dialogue, task state or inventory mutation. Loaded explicitly (no editor import).

const NPCS := "res://assets/p0/outpost_npcs.json"
const PIP := "res_pip"
const TAG := "farm:guide_pip"
const WATER_TAG := "farm:guide_water:"
const GROWTH_TAG := "farm:guide_growth:"
## Pip by the starting beds (SGODOT-355 b1: the 2 × 4 at x 8–14, y 9–11): the walkway on the block's left, between its
## two rows. LAND: where a guided player lands on the farm, the walkway in front of the block (q(215) 「落地在首畦旁」).
const STAND := Vector2i(7, 10)
const LAND := Vector2i(9, 8)
## He wanders by the starting beds while the guide has him here (SGODOT-411; the user, 11-04: "给pip添加在农场内的闲逛,而不是
## 呆呆地站着,当用户点击(对话框出现的时候)再停下来朝向用户"; 不知火舞's spec 2026-11-04): on walkable cells that are in no
## one's way — no bed, no path the yard keeps clear, nothing within a cell of the sign, the door or the stall — within
## TETHER cells of STAND (TETHER_BANG while his `!` wants the player), stopping a while at each. Talking, a panel up, or
## the player near: he stands and turns to the player.
const TETHER := 4.0
const TETHER_BANG := 2.0
const WALK_SPEED := 1.0           # m/s, under the player's walk; the walk clip's own stride at his 0.88 (上官婉儿 checks it)
const TURN_S := 0.25              # a half turn
const STOP_S := Vector2(3.0, 6.0)
const HOP_M := Vector2(1.5, 4.0)  # the next stop this far from where he is
const NEAR_M := 2.6               # the name tag's near: he stops and turns to the player…
const AWAY_M := 3.5               # …and walks on once the player is this far
const CLEAR_M := 1.5              # no stop this close to the player
const RESUME_S := 1.5             # after a talk or a panel closes
const WAVE_M := 6.0               # about one stop in four, the player this near, he turns to them and waves
const WAVE_CHANCE := 0.25

var farm: Node3D
var pip_root: Node3D
var rig: AvatarRig
var _waved := false
var _wave_left := 0.0
var _highlights := {}
var _water_badges := {}
var _growth_badges := {}
var rng := RandomNumberGenerator.new()   # where and how long he stops (a test seeds it)
var _route: Array[Vector3] = []          # the cells still to walk to the stop, world points
var _stop_left := 0.0                    # standing at a stop
var _resume_left := 0.0                  # standing on after a talk or a panel closed
var _near := false                       # the player came within NEAR_M and is not past AWAY_M yet
var _was_held := false
var _last_stop := Vector2i(-1, -1)
var _facing = null                       # a world point to turn to while standing, or null

func setup(host: Node3D) -> Node3D:
	farm = host
	return self

func frame(view: Dictionary, dt: float) -> void:
	var info := P0Guide.pip(view)
	var here := bool(info.get("here", false))
	if here and pip_root == null: _spawn()
	if pip_root != null:
		# If the guide ends while the player stands here, keep the model until leave(); all guidance stops now.
		var head: Vector2 = farm.cam.unproject_position(pip_root.to_global(Vector3(0, 2.0, 0)))
		var visible_head: bool = not farm.cam.is_position_behind(pip_root.global_position) and farm.get_viewport().get_visible_rect().has_point(head)
		var talking: bool = farm.rt.ui.speaker() == PIP
		var near: bool = P0FarmMaterials.flat(farm.actor.position, pip_root.position) < 2.6
		farm.rt.ui.npc_tag(TAG, "Pip", head, visible_head, near, talking,
			UiStatusBadge.State.REQUEST if here and bool(info.get("bang", false)) else -1)
		if _wave_left > 0.0:
			_wave_left -= dt
			if _wave_left <= 0.0: rig.play_motion("idle")
		if here and visible_head and not farm.rt.ui.has_modal() and not _waved and not rig.is_busy():
			_waved = true
			_wave()
		_wander(info, dt)
	_highlight(view)
	_water_marks(view)
	_growth_marks(view)

func _spawn() -> void:
	var def: Dictionary = P0RoomAnchors.read_json(NPCS).get("npcs", {}).get(PIP, {})
	if def.is_empty(): return
	pip_root = Node3D.new()
	pip_root.name = "GuidePip"
	pip_root.position = farm.bp.cell_to_world(STAND)
	pip_root.scale = Vector3.ONE * float(def.get("scale", 0.88))
	add_child(pip_root)
	pip_root.look_at(Vector3(farm.actor.global_position.x, pip_root.global_position.y, farm.actor.global_position.z), Vector3.UP)
	rig = Avatar.create_rig()
	rig.assembler = AvatarAssemblerMerged.new()
	rig.rotation.y = PI   # the reused rig faces +Z, while look_at points -Z at the player
	for child in rig.get_children():
		if child is RigActivity:
			child.reduced_distance = 50
			child.sleep_distance = 80
	pip_root.add_child(rig)
	rig.config_applied.connect(func(_c): rig.play_motion("idle"))
	rig.apply_config(OnlineAppearance.config({"version": 1, "slots": def.get("slots", {})}, true))
	_route.clear()
	_stop_left = rng.randf_range(STOP_S.x, STOP_S.y)   # he stands first: the landing, its wave and opening line
	_resume_left = 0.0
	_near = false
	_last_stop = STAND
	_facing = null

func _wave() -> void:
	if rig == null: return
	var player := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null and player.has_animation("emote_wave"):
		rig.play_motion("emote_wave")
		_wave_left = player.get_animation("emote_wave").length

## One frame of his stroll. Held — talking to the player, a panel up, or the player within NEAR_M (until past AWAY_M) —
## he stands where he is and turns to the player, the route dropped; RESUME_S after a talk or a panel he picks a new stop
## from where he is. Else he walks his route, or stands out his stop, or picks the next one.
func _wander(info: Dictionary, dt: float) -> void:
	var ui = farm.rt.ui
	var player: Vector3 = farm.actor.position
	var d := P0FarmMaterials.flat(player, pip_root.position)
	_near = d < NEAR_M or (_near and d < AWAY_M)
	var held: bool = ui.speaker() == PIP or ui.has_modal()
	if held or _near:
		if held: _was_held = true
		_route.clear()
		_stand()
		_turn_to(player, dt)
		return
	if _was_held:   # a talk or a panel just closed: stand on a moment
		_was_held = false
		_resume_left = RESUME_S
		_stop_left = 0.0
	if _resume_left > 0.0:
		_resume_left -= dt
		_stand()
		if _facing != null: _turn_to(_facing, dt)
		return
	if not _route.is_empty():
		_walk(dt)
		return
	if _stop_left > 0.0:
		_stop_left -= dt
		_stand()
		if _facing != null: _turn_to(_facing, dt)
		return
	_pick_stop(info, player)

func _stand() -> void:
	if _wave_left <= 0.0 and rig != null: rig.play_motion("idle")

## Toward the route's next point at WALK_SPEED, turning as he goes; at the stop, a while standing there facing the
## first bed or a way of his own — or, now and then with the player near, them, with a wave.
func _walk(dt: float) -> void:
	var to: Vector3 = _route[0]
	var off := to - pip_root.position
	off.y = 0.0
	var step := WALK_SPEED * dt
	if off.length() <= step:
		pip_root.position = Vector3(to.x, pip_root.position.y, to.z)
		_route.remove_at(0)
	else:
		pip_root.position += off.normalized() * step
	if off.length() > 0.01: _turn_to(pip_root.position + off, dt)
	if rig != null and _wave_left <= 0.0: rig.play_motion("walk")
	if not _route.is_empty(): return
	_stop_left = rng.randf_range(STOP_S.x, STOP_S.y)
	var player: Vector3 = farm.actor.position
	if P0FarmMaterials.flat(player, pip_root.position) < WAVE_M and rng.randf() < WAVE_CHANCE:
		_facing = player
		_wave()
	elif rng.randf() < 0.5:
		_facing = farm.bp.cell_to_world(P0Garden.cell_of(0))   # the first bed
	else:
		var a := rng.randf_range(-PI, PI)
		_facing = pip_root.position + Vector3(-sin(a), 0, -cos(a))
	if rig != null and _wave_left <= 0.0: rig.play_motion("idle")

## Turn toward `at` by at most a half turn per TURN_S (his -Z looks at it; the rig inside faces +Z, rotated by PI).
func _turn_to(at: Vector3, dt: float) -> void:
	var off := at - pip_root.position
	if Vector2(off.x, off.z).length() < 0.01: return
	var want := atan2(-off.x, -off.z)
	pip_root.rotation.y = rotate_toward(pip_root.rotation.y, want, PI / TURN_S * dt)

## The cells he may stop on now: walkable on the farm's grid (no wall, house, tree, piece), no bed, none of the yard's
## kept paths, not within a cell of its objects (the sign, the door, the stall…), within `tether` cells of STAND.
func stops(tether: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var beds := {}
	for id in P0Garden.max_plots(): beds[P0Garden.cell_of(id)] = true
	var yard: Dictionary = P0Decor.yard()
	var kept: Array[Rect2i] = []
	for r in yard.get("paths", []): kept.append(P0Decor._rect(r))
	for r in yard.get("objects", []): kept.append(P0Decor._rect(r).grow(1))
	var reach := int(ceil(tether))
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c := STAND + Vector2i(dx, dy)
			if Vector2(dx, dy).length() > tether or not farm.bp.in_bounds(c) or farm.grid.astar.is_point_solid(c): continue
			if beds.has(c) or kept.any(func(r: Rect2i): return r.has_point(c)): continue
			out.append(c)
	return out

## The next stop, HOP_M from where he is, CLEAR_M off the player, not the last one, and a way to it over stop cells only
## (never across a bed); none: he stands another while.
func _pick_stop(info: Dictionary, player: Vector3) -> void:
	var cells := stops(TETHER_BANG if bool(info.get("bang", false)) else TETHER)
	var here: Vector2i = farm.bp.world_to_cell(pip_root.position)
	var options: Array[Vector2i] = []
	for c in cells:
		var at: Vector3 = farm.bp.cell_to_world(c)
		var hop := P0FarmMaterials.flat(at, pip_root.position)
		if c == _last_stop or c == here or hop < HOP_M.x or hop > HOP_M.y: continue
		if P0FarmMaterials.flat(at, player) < CLEAR_M: continue
		options.append(c)
	_stop_left = rng.randf_range(STOP_S.x, STOP_S.y)
	_facing = null
	if options.is_empty(): return
	var to := options[rng.randi_range(0, options.size() - 1)]
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(STAND - Vector2i(6, 6), Vector2i(13, 13))
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	astar.fill_solid_region(astar.region, true)
	for c in cells: astar.set_point_solid(c, false)
	if astar.is_in_boundsv(here): astar.set_point_solid(here, false)   # he may stand off the stop cells (STAND, a held spot)
	if not astar.is_in_boundsv(here): return
	var path := astar.get_id_path(here, to)
	if path.size() < 2: return
	_route.clear()
	for i in range(1, path.size()): _route.append(farm.bp.cell_to_world(path[i]))
	_last_stop = to
	_stop_left = 0.0

func _highlight(view: Dictionary) -> void:
	var ids := P0Guide.teaching_plots(view)
	for id in ids:
		if not _highlights.has(id):
			var outline: MeshInstance3D = farm._bed_highlight()
			outline.position = farm.bp.cell_to_world(P0Garden.cell_of(id)) + Vector3(0, P0Garden.BED_H + 0.013, 0)
			add_child(outline)
			_highlights[id] = outline
	for id in _highlights:
		var highlighted: bool = view.get("plots", []).any(func(p): return int(p.get("id", -1)) == int(id) and str(p.get("state", "")) in ["tilled", "ready"])
		_highlights[id].visible = ids.has(id) and highlighted and not farm.rt.ui.has_modal() and not farm.rt.ui.placing()
	# The ordinary near-bed outline must not introduce a third teaching highlight; actions stay enabled everywhere.
	if not ids.is_empty() and str(view.get("guide", {}).get("step", "")) == "t_sow_quick": farm._hi.visible = false

## Sown teaching beds need water, not another sow outline (340 S3). Read the actual plot state and server targets;
## never infer a target from the step name or keep a drop after a confirmed watering. Display-only kit badges.
func _water_marks(view: Dictionary) -> void:
	var wanted := {}
	if not farm.rt.ui.has_modal() and not farm.rt.ui.placing():
		var ids := P0Guide.teaching_plots(view)
		for plot in view.get("plots", []):
			var id := int(plot.get("id", -1))
			if not ids.has(id) or str(plot.get("state", "")) != "sown": continue
			var at: Vector3 = farm.bp.cell_to_world(P0Garden.cell_of(id)) + Vector3(0, P0Garden.BED_H + 0.6, 0)
			if farm.cam.is_position_behind(at): continue
			wanted[id] = true
			_water_badges[id] = true
			farm.rt.ui.badge(WATER_TAG + str(id), UiStatusBadge.State.AVAILABLE,
				farm.cam.unproject_position(at), true, "", P0Logic.icon("water"), true)
			_water_clear_of_pip(id)
	for id in _water_badges:
		if not wanted.has(id): farm.rt.ui.badge(WATER_TAG + str(id), UiStatusBadge.State.AVAILABLE, Vector2.ZERO, false)

## S4 no longer marks the teaching plots: their growth is a crop fact, not an instruction to act. Rebuild from
## the server's teaching-crop metadata on every visit. `view` already uses the ordinary session time projection.
func _growth_marks(view: Dictionary) -> void:
	var wanted := {}
	if P0Guide.guide_on(view) and not farm.rt.ui.has_modal() and not farm.rt.ui.placing():
		for plot in view.get("plots", []):
			var id := int(plot.get("id", -1))
			if id < 0 or id >= P0Garden.plot_count(view): continue
			if P0Logic.quick_seed(view, str(plot.get("crop", ""))).is_empty(): continue
			var state := str(plot.get("state", ""))
			if state != "ready" and (state != "growing" or plot.get("ready_in") == null): continue
			var at: Vector3 = farm.bp.cell_to_world(P0Garden.cell_of(id)) + Vector3(0, P0Garden.BED_H + 0.6, 0)
			if farm.cam.is_position_behind(at): continue
			wanted[id] = true
			_growth_badges[id] = true
			farm.rt.ui.badge(GROWTH_TAG + str(id), UiStatusBadge.State.READY if state == "ready" else UiStatusBadge.State.COUNTDOWN,
				farm.cam.unproject_position(at), true, "" if state == "ready" else P0Logic.duration(float(plot.ready_in)), null, true)
			_water_clear_of_pip(id, GROWTH_TAG)
	for id in _growth_badges:
		if not wanted.has(id): farm.rt.ui.badge(GROWTH_TAG + str(id), UiStatusBadge.State.COUNTDOWN, Vector2.ZERO, false)

## Pip wanders by the first teaching beds: his name tag is where he is this frame (npc_tag above, before the badges).
## Keep its status and caption readable without moving his name tag;
## prefer just above the tag, or below it at the top edge of the world band. Neither mark takes the other's input.
func _water_clear_of_pip(id: int, prefix := WATER_TAG) -> void:
	var badge: UiStatusBadge = farm.rt.ui._badges.get(prefix + str(id))
	var tag: Control = farm.rt.ui._npc_tags.get(TAG)
	if badge == null or not badge.visible or tag == null or not tag.visible: return
	var rect := badge.get_global_rect()
	var name_rect := tag.get_global_rect()
	if not rect.intersects(name_rect): return
	var area: Rect2 = farm.rt.ui._marker_area()
	var above := name_rect.position.y - rect.size.y - UiTokens.SPACE_WITHIN
	var below := name_rect.end.y + UiTokens.SPACE_WITHIN
	if above >= area.position.y:
		badge.global_position.y = above
	elif below + rect.size.y <= area.end.y:
		badge.global_position.y = below
	else:
		badge.hide()   # no clear world space, as for an anchor outside the viewport

func tap(screen: Vector2, card: String) -> bool:
	if pip_root == null or farm.rt.ui.has_modal(): return false
	if farm.cam.is_position_behind(pip_root.global_position): return false
	var at: Vector2 = farm.cam.unproject_position(pip_root.to_global(Vector3(0, 0.8, 0)))
	if card != TAG and at.distance_to(screen) > UiTokens.SIZE_TOUCH * 0.5: return false
	farm.actor.face(pip_root.position)
	farm.rt.ui.open_resident(PIP)
	return true

func hide_marks() -> void:
	farm.rt.ui.npc_tag(TAG, "", Vector2.ZERO, false)
	for outline in _highlights.values(): outline.visible = false
	for id in _water_badges: farm.rt.ui.badge(WATER_TAG + str(id), UiStatusBadge.State.AVAILABLE, Vector2.ZERO, false)
	for id in _growth_badges: farm.rt.ui.badge(GROWTH_TAG + str(id), UiStatusBadge.State.COUNTDOWN, Vector2.ZERO, false)

## Farm suspension counts as leaving (including going inside): never disappear in front of the player.
func leave() -> void:
	if pip_root != null:
		pip_root.queue_free()
		pip_root = null
		rig = null
		_wave_left = 0.0
	hide_marks()

func near_resident() -> String:
	return PIP if pip_root != null and P0FarmMaterials.flat(farm.actor.position, pip_root.position) < 2.6 else ""
