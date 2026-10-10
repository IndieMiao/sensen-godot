extends Node3D
## P0 mine floors 1–2 (SGODOT-231; plan §13.3, LOCK-21, LOCK-24): the old polished mine chambers (MineArt B1 / B2,
## approved 2026-09-24) with the P0 actor, safe-box camera and main action key. The server owns the run (view.mine);
## this world draws it, picks the rock the player faces and sends mine_* commands. P0MaterialLogic writes every key,
## row and float. Rocks respond only to the main key (LOCK-02), which is Mining's alone; the ladders and the elevator
## are facilities (SGODOT-266, user on 263 ③): an icon button and strip each (P0WorldPrompts.mine_facility), a tap
## walks the player up, then a free move goes at once and a new floor's fee waits on the EntryCard's button.

const P0City := preload("res://modules/p0/p0_city.gd")   # the P0 home city (SGODOT-270)
const Art = preload("res://modules/mining/mine_art.gd")
const Layout = preload("res://modules/mining/mine_layout.gd")
const ElasticZoom = preload("res://modules/p0/p0_elastic_zoom.gd")
const Combat = preload("res://modules/mining/p0_mine_combat.gd")
const FarmCamera = preload("res://modules/farm/farm_camera.gd")
var PLACE := P0City.chip("Mine · Floor %d")
const REACH := 1.7          # m: a rock in front of the player within this distance; a facility used from this close
const CARD_REACH := 2.4     # m: a facility's strip opens, its EntryCard stays (the farm's mouth reach)
const BREAK_S := 0.45       # rock break: shake, shrink, chips
const STATUS_INTRO_MS := 3000   # "Run 1/2 today" first, then "Rocks 2/6" (MINE-1 / P0-2)
const FLOORS := 5               # §13.3.2 (SGODOT-288): floors 3–4 add slimes, floor 5 is the elite's alone

var rt: P0Runtime
var floor_n := 1
var cam: Camera3D
var environment: Environment
var world_env: WorldEnvironment
var actor: P0Actor
var bp: FarmBlueprint
var grid: BlueprintGrid
var scenery: Node3D
var objects: Node3D
var backdrop: Node3D   # the underground backdrop (SGODOT-257), outside scenery / objects
var combat: Node3D     # Combat (p0_mine_combat.gd): this floor's slimes, their moves and the swing (SGODOT-288)
var _hurt_pending := false   # a hit sent, its reply not yet in: the next hit waits (the server's 1 s window)
var _hurt_sent_ms := 0
## The slime-hit command's key: its settle (ok with or without a hurt event, refused, or a failed request) frees the next
## hit, so one quiet reply can never leave the player unhittable for the rest of the visit (苏烈 on #223).
const HURT_KEY := "mine_hurt"
const HURT_STALE_MS := 4000   # and a reply that never comes at all frees it after this
## Swings sent and not yet answered (each its own key): a fall that comes in while one of them may still beat the elite
## waits for it, and is dropped if that swing ends the run (q(116) ③: the elite down and the player down in the same
## exchange is a win — Run complete only).
const SWING_KEY := "mine_swing_%d"
var _swings := 0
var _swings_out := {}
## The slash (SGODOT-291; 不知火舞 on 291 72917be2): attack_slash, a raised slanted chop, and attack_slash_b, a sweep,
## alternate while Attack is pressed on; a pause over SLASH_RESET_S starts again with the chop. [clip, its length, the
## right wrist's speed peak from its start (上官婉儿's measure on the bones)]: the arc, the struck slime's flash and
## knockback come ARC_LEAD_S before the peak (P0MineCombat.fx_delay); who was hit is judged and sent at the press, as
## before. The body holds still until the peak — on the move too — and past it the stick cancels the follow-through
## (P0Actor.attack; 不知火舞 on 291: 0.22 s for the chop, 0.30 s for the sweep).
const SLASHES := [["attack_slash", 0.52, 0.22], ["attack_slash_b", 0.60, 0.30]]
const SLASH_RESET_S := 0.8
const ARC_LEAD_S := 0.03
var _slash := -1          # the last slash's place in SLASHES
var _slash_t := INF       # seconds since it began
## The Combat slot's sword in the right hand for the whole slash (不知火舞 on 291: B, in hand from the wind-up): each frame its grip on the hand bone as
## the clip poses it — the blade across the knuckles to the thumb side (the bone's +Y), its edge along the fingers (+X).
const CombatArt := preload("res://modules/mining/combat_art.gd")
const HAND_BONE := "Wrist_R"
const GRIP_ALONG := 0.085   # the grip's centre from the wrist toward the fingers (m)
const GRIP_PALM := -0.02    # … and toward the palm (the bone's −Z)
const SWORD_GRIP_Y := 0.17  # the sword model's grip centre over its origin (combat_art: handle 0.045–0.295)
const SWORD_SCALE := 0.65
var _sword: MeshInstance3D
var _sword_id := ""
var _ko_waiting := false
var _ko := false   # knocked out: the moment before leaving — the fight frozen, the bar at 0 %
var _completing := false     # Run complete: the banner, then out to the mouth
var _rocks := {}            # rock index → Node3D (gone once broken)
var _previews := {}         # rock index → Sprite3D torch preview
var _breaking := {}         # rock index → true while its break plays (the view may already say broken)
var _focus := Vector3.ZERO
var _cam_follow := P0Follow.new()
# Camera unification (用户 via 奕星, 2026-10-09; target 哪吒, 65.8 px at 360 × 800): the farm's size and pinch — zoom 1 is
# FarmCamera.player_scale_size at the farm's 43° pitch, rubber-banded 0.8–1.4 about the pinch centre (ElasticZoom).
var _zoom := 1.0
var _room := AABB()          # this floor's walls (the camera's vertical framing, _frame_chamber); empty until built
var _art_points := PackedVector3Array()   # this floor's art vertices incl. the ladders and the elevator (side stops)
var _art_sides := PackedVector3Array()    # of those, the leftmost and rightmost for the camera's right (_side_points)
var _art_right := Vector3.ZERO            # the camera right _art_sides were found for
var _band := Rect2()         # the last camera band seen with no panel up (_camera_band)
var _pinch = ElasticZoom.new(0.8, 1.4)
var _zoom_at := Vector2.INF
var _after_pinch := false    # the fingers lifted: once the zoom settles, ease back if the player left the safe box
var _target := {}           # {kind, rock, at}
var _entered_ms := 0
var _hold_until := 0
var _leaving := false
var _grey := false
var _elevator_to := -1      # the floor an elevator ride asked for: it lands beside the elevator, not at the stairs
var _facilities := {}       # id ("mine_up", "mine_down", "mine_elevator") → {kind, at, node, box} on this floor
var _walk := {}             # a tapped facility being walked to: {id, point}
var _card_for := ""         # the facility whose EntryCard shows (a new floor's fee), "" none
var _strip_open := ""        # the facility holding the open strip (P0Garden.pick_card)
var _strip_side := UiWorldNameBar.Dir.RIGHT
var _entry: UiEntryCard     # the fee card over a ladder (built on first use, on the P0 UI's root)
var _entry_data := {}       # P0MaterialLogic.mine_facility for _card_for

func setup(args: Dictionary) -> void:
	floor_n = clampi(int(args.get("floor", 1)), 1, FLOORS)

func _ready() -> void:
	P0Runtime.mark("%s _ready start" % name)
	get_viewport().transparent_bg = false
	add_child((load("res://modules/ui/opaque_scene_layer.tscn") as PackedScene).instantiate())
	_build_light()
	actor = P0Actor.new()
	add_child(actor)
	_build_floor(floor_n)
	actor.setup(bp, grid, cam, Layout.SPAWN)
	combat = Combat.new()
	add_child(combat)
	combat.contact.connect(_on_contact)
	_focus = actor.position
	_update_camera()
	_entered_ms = Time.get_ticks_msec()
	rt = P0Runtime.ensure()
	rt.attach(self)
	rt.ui.set_mode(P0MaterialLogic.landing_mode(rt.session.current(), floor_n))
	rt.ui.actions_here = P0MaterialLogic.mine_actions(floor_n)
	rt.ui.set_place(PLACE % floor_n)
	rt.session.state_changed.connect(_on_state)
	rt.session.command_settled.connect(_on_settled)

func _exit_tree() -> void:
	if is_instance_valid(_entry): _entry.queue_free()
	if rt:
		rt.ui.actions_here = []
		rt.ui.set_hp(-1, 0)
		if rt.session.state_changed.is_connected(_on_state): rt.session.state_changed.disconnect(_on_state)
		if rt.session.command_settled.is_connected(_on_settled): rt.session.command_settled.disconnect(_on_settled)
		rt.detach(self)

func p0_surface() -> String: return "mine"
func p0_space() -> String: return "mine"
func p0_energy_verb() -> String: return str(rt.ui.fab_state().get("verb", "Mine"))

# ---------------------------------------------------------------- world
## The old mine's light (scenes/mine/mine.gd 135–155): dark backdrop, warm key light, lantern pools in the chamber.
func _build_light() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = MineBackdrop.VOID   # the backdrop's outer edge fades into this (SGODOT-257)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e8dfea")
	environment.ambient_light_energy = 0.48
	world_env = WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-51, -38, 0)
	sun.light_color = Color("ffe8ce")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.58
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 0.45
	sun.shadow_blur = 1.6
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(cam)
	cam.make_current()

## One chamber: B1–B5 art (MineArt), the fixed rock positions on floors 1–4 (the server's rock index; floor 5 has none),
## the up ladder (Exit mine on floor 1, the floor above below it), the down ladder on floors 1–4 and an elevator on every
## floor (q(44)); the floors' monsters come with MineCombat (SGODOT-288).
func _build_floor(n: int) -> void:
	floor_n = n
	for node in [scenery, objects, backdrop]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	_rocks.clear()
	_previews.clear()
	_breaking.clear()
	scenery = Art.floor_scenery(n, true)   # adds the up ladder, and the elevator on floor 1
	add_child(scenery)
	_room = _walls_box(scenery)
	objects = Node3D.new()
	objects.name = "MineObjects"
	add_child(objects)
	if n not in [1, FLOORS]: objects.add_child(Art.elevator(true))   # MineArt puts one in floors 1 and 5 itself
	if n < FLOORS: objects.add_child(Art.ladder(Layout.DOWN, false))
	var broken := _broken(_view(), n)
	for i in rock_count(n):
		if broken[i]: continue
		var rock := Art.rock(Layout.FALLBACK_POSITIONS[i], i, n)
		rock.name = "Rock%d" % i
		objects.add_child(rock)
		_rocks[i] = rock
	_art_points = _art_vertices(scenery)
	for node in objects.get_children():   # the elevator and the down ladder stand against the walls; rocks are inside
		if not str(node.name).begins_with("Rock"): _art_points.append_array(_art_vertices(node))
	_art_right = Vector3.ZERO
	_find_facilities(n)
	# The underground backdrop (SGODOT-257) hangs off the world itself, outside scenery / objects: the camera's walls box
	# and art edges above never see it, so it frames nothing. Its outer edge fades into the Environment's background.
	backdrop = MineBackdrop.build(n)
	add_child(backdrop)
	_rebuild_nav(broken)

## Rocks on a floor (§13.3.2): the six fixed positions on floors 1–4, none on Floor 5.
static func rock_count(n: int) -> int:
	return 0 if n >= FLOORS else Layout.FALLBACK_POSITIONS.size()

func _rebuild_nav(broken: Array) -> void:
	var nodes: Array = []
	var gone: Array = []
	for i in Layout.FALLBACK_POSITIONS.size():
		nodes.append({"id": str(i), "position": Layout.FALLBACK_POSITIONS[i]})
		if broken[i] or i >= rock_count(floor_n): gone.append(str(i))   # Floor 5: an open chamber for the elite fight
	bp = Layout._navigation(nodes, gone)
	grid = BlueprintGrid.new(bp)
	if actor and actor.mover:
		var at := actor.mover.position
		actor.mover = PlayerMover.new(bp, grid)
		actor.mover.position = at if bp.is_walkable(bp.world_to_cell(at)) else Layout.SPAWN

func _view() -> Dictionary:
	return rt.session.current() if rt else (P0Runtime.ensure().session.current())

func _broken(v: Dictionary, n: int) -> Array:
	var out: Array = []
	out.resize(Layout.FALLBACK_POSITIONS.size())
	out.fill(false)
	var run = v.get("mine", {}).get("run", null)
	if run == null: return out
	for f in run.get("floors", []):
		if int(f.get("floor", 0)) == n:
			var b: Array = f.get("broken", [])
			for i in mini(b.size(), out.size()): out[i] = bool(b[i])
	return out

## This floor's facilities and their art (the tap box and where the prompt sits): the up ladder (Exit on floor 1), the
## down ladder above floor 2 and the elevator. Their art stands still, so its world box is found once here (亚瑟 on #190)
## rather than walked through every frame.
func _find_facilities(n: int) -> void:
	if rt != null:   # a new floor: the old floor's prompts fold (the ladder down is not on floor 2)
		for id in _facilities: rt.ui.world_icon(id, null, Vector2.ZERO, false)
	_facilities.clear()
	_walk = {}
	close_card()
	var up := scenery.find_child("UpLadder", true, false) as Node3D
	_facilities["mine_up"] = {"kind": "exit" if n == 1 else "up", "at": Layout.UP, "node": up}
	if n < FLOORS: _facilities["mine_down"] = {"kind": "stairs", "at": Layout.DOWN, "node": objects.find_child("DownLadder", true, false)}
	var lift := scenery.find_child("MineElevator", true, false) as Node3D
	if lift == null: lift = objects.find_child("MineElevator", true, false) as Node3D
	_facilities["mine_elevator"] = {"kind": "elevator", "at": Layout.ELEVATOR, "node": lift}
	for id in _facilities: _facilities[id]["box"] = _art_box(_facilities[id].node)

## Stairs, the elevator or a new floor: rebuild the chamber and land at the spawn (the elevator lands beside it).
func _go_floor(n: int, by_elevator := false) -> void:
	_build_floor(n)
	actor.teleport(Layout.ELEVATOR + Vector3(1.1, 0, 0.6) if by_elevator else Layout.SPAWN)
	_focus = actor.position
	_cam_follow.hold()
	rt.ui.set_place(PLACE % n)
	rt.ui.actions_here = P0MaterialLogic.mine_actions(n)
	# Land ready to fight where a monster is up (李元芳 R5: Express to Floor 5 met the elite on `Mine · No rocks here`);
	# no Combat on floors 1–2 (§13.3.8)
	rt.ui.set_mode(P0MaterialLogic.landing_mode(rt.session.current(), n))
	_entered_ms = Time.get_ticks_msec()

# ---------------------------------------------------------------- frame
func p0_joystick(v: Vector2) -> void:
	if actor and not _leaving: actor.set_input(v)
	if v != Vector2.ZERO: _walk = {}   # pushing the stick on the way cancels the walk (SGODOT-266)

## A tap on a ladder or the elevator — its icon button, strip or the model itself — walks the player up to it, then
## uses it (SGODOT-266). On the open fee card: its button's. Rocks never respond to taps (LOCK-02), and any other tap
## folds the card.
func p0_tap(screen: Vector2) -> void:
	if _leaving or rt.ui.has_modal(): return
	var id := str(rt.ui.tapped_card)
	if id == "" and is_instance_valid(_entry) and _entry.visible and _entry.tap_at(screen + rt.ui.root.global_position) != "": return
	close_card()
	if not _facilities.has(id): id = facility_at(screen)
	if id != "": walk_to(id)

## The facility whose model holds a screen point (the smallest box when two overlap), "" none.
func facility_at(screen: Vector2) -> String:
	var best := ""
	var best_area := INF
	for id in _facilities:
		var box := _screen_rect(_facilities[id].box)
		if box.has_point(screen) and box.get_area() < best_area:
			best = id
			best_area = box.get_area()
	return best

## Walk up to a facility (the nearest walkable point by it, Layout.approach), then use it; from close by, use it now.
func walk_to(id: String) -> void:
	var f: Dictionary = _facilities.get(id, {})
	if f.is_empty(): return
	if P0FarmMaterials.flat(actor.position, f.at) <= REACH:
		_arrive(id)
		return
	var point := Layout.approach(actor.mover, f.at)
	if P0FarmMaterials.flat(point, f.at) > REACH or not actor.mover.set_target_position(point):
		return   # nowhere to stand by it (not on the shipped floors)
	_walk = {"id": id, "point": point}

## Arrived (or already there): face it, then a free move goes now; a new floor's fee opens the card (SGODOT-266).
func _arrive(id: String) -> void:
	_walk = {}
	var f: Dictionary = _facilities.get(id, {})
	if f.is_empty(): return
	actor.face(f.at)
	var use := P0MaterialLogic.mine_facility(_view(), floor_n, str(f.kind))
	if bool(use.get("card", false)):
		_card_for = id
		return
	var cmd: Dictionary = use.get("cmd", {})
	if not cmd.is_empty(): p0_action(cmd)

func close_card() -> void:
	_card_for = ""
	if is_instance_valid(_entry): _entry.visible = false

func p0_frame(v: Dictionary, dt: float) -> void:
	if _leaving: return
	if v.get("mine", {}).get("run", null) == null:
		_kick_out()
		if _completing: _follow(dt)   # the banner holds the floor in view; nothing else moves
		return
	actor.step(dt)
	if not _walk.is_empty() and not actor.mover.is_moving():
		var id := str(_walk.id)
		_walk = {}
		if _facilities.has(id) and P0FarmMaterials.flat(actor.position, _facilities[id].at) <= REACH: _arrive(id)
		if _leaving or not is_inside_tree(): return   # the way out popped the mine mid-frame (as P0Room's door)
	_follow(dt)
	_sync_rocks(v)
	_fight(v, dt)
	_pick_target()
	var ctx := {"floor": floor_n, "target": str(_target.get("kind", "")), "rock": int(_target.get("rock", -1)),
		"item": _selected_item()}
	var combat_on := rt.ui.bar_mode == "combat"
	rt.ui.set_action(P0MaterialLogic.combat_action(v, ctx) if combat_on else P0MaterialLogic.mine_action(v, ctx))
	_hold_repeat()
	_marks(v)
	_prompts(v)

## Floors 3–5 (SGODOT-288): the slimes from the view, their moves (paused while a panel is up or the player is busy
## elsewhere), the player's HP and the elite's card. The HP shown is the server's (view.mine.run.hp).
func _fight(v: Dictionary, dt: float) -> void:
	if combat == null: return
	combat.sync_p0(v, floor_n, actor.mover)
	# Knocked out: the fight holds still until the player is out (the server has already refilled HP for the run, so
	# the bar keeps 0 % for the moment instead of jumping to 100 % — 不知火舞 on 288 78d0f863)
	combat.step(dt, actor.mover, rt.ui.has_modal() or _completing or _ko)
	_slash_t += dt
	_hold_sword(str(v.get("mine", {}).get("weapon", {}).get("id", "")))
	var run: Dictionary = v.get("mine", {}).get("run", {})
	var fighting := floor_n >= 3 and run is Dictionary and not run.is_empty()
	rt.ui.set_hp((0 if _ko else int(run.get("hp", -1))) if fighting else -1, int(v.get("mine", {}).get("hp_max", 100)),
		combat.elite_hp().merged({"name": "Elite Slime"}) if fighting and not combat.elite_hp().is_empty() else {})

## The Combat slot's sword (its model from the view's mine.weapon.id), in the right hand from the slash's peak to its end.
func _hold_sword(id: String) -> void:
	if id != _sword_id:
		_sword_id = id
		if is_instance_valid(_sword): _sword.queue_free()
		_sword = null
		if id != "":
			_sword = CombatArt.model(id)
			_sword.name = "HeldSword"
			_sword.scale = Vector3.ONE * SWORD_SCALE
			actor.add_child(_sword)
	if not is_instance_valid(_sword): return
	_sword.visible = sword_due() and not _ko
	if _sword.visible: _grip_sword()

## Whether a slash clip plays (the sword's time in hand).
func sword_due() -> bool:
	return _slash >= 0 and actor.attacking()

## Seconds from a slash's press to its strike: its wrist peak, ARC_LEAD_S early.
func strike_at(i: int) -> float: return maxf(0.0, float(SLASHES[i][2]) - ARC_LEAD_S)

## The sword's grip on the right hand as the clip poses it now.
func _grip_sword() -> void:
	var sk: Skeleton3D = actor.rig.skeleton if actor.rig else null
	var bone := sk.find_bone(HAND_BONE) if sk else -1
	if bone < 0: return
	var hand := sk.global_transform * sk.get_bone_global_pose(bone)
	var b := hand.basis.orthonormalized()
	var grip := hand.origin + b.x * GRIP_ALONG + b.z * GRIP_PALM
	_sword.global_transform = Transform3D(b.scaled(Vector3.ONE * SWORD_SCALE), grip - b.y * SWORD_GRIP_Y * SWORD_SCALE)

## Whether the sword is in hand now (tests and shots).
func sword_shown() -> bool: return is_instance_valid(_sword) and _sword.visible

## A slime's leap reached the player (MineCombat.contact): the server settles the hit (the 1 s window there too).
func _on_contact(id: String) -> void:
	if _hurt_pending and Time.get_ticks_msec() - _hurt_sent_ms > HURT_STALE_MS: _hurt_pending = false
	if _hurt_pending or _completing or _ko or rt.session.busy: return
	if not rt.session.send({"type": "mine_attack", "floor": floor_n, "hurt_by": Combat.mob_index(id)}, HURT_KEY): return
	_hurt_pending = true
	_hurt_sent_ms = Time.get_ticks_msec()

## Any end of the hit command frees the next one (see HURT_KEY).
func _on_settled(key: String, _ok: bool, _code: String) -> void:
	if key == HURT_KEY: _hurt_pending = false
	if _swings_out.erase(key) and _swings_out.is_empty() and _ko_waiting:
		_ko_waiting = false
		if not _completing: _knocked_out()   # the swings in flight did not end the run: the fall stands

## Attack (Combat's key): one swing — the arc, the stun and the knockback here; the server settles who was hit.
func _swing() -> void:
	if combat == null or _ko_waiting or _ko: return   # a fall waits on the swings out / the knock-out moment: no new swing (苏烈 on #253, #255)
	if combat.cooldown > 0.0: return   # within the weapon's tempo: no swing, no clip
	_slash = 0 if _slash < 0 or _slash_t > SLASH_RESET_S else 1 - _slash
	_slash_t = 0.0
	var slash: Array = SLASHES[_slash]
	combat.fx_delay = strike_at(_slash)
	var hit: Array = combat.swing({}, actor.mover)
	actor.face(actor.position + actor.mover.facing)   # turned to the slime it swung at
	actor.attack(str(slash[0]), float(slash[1]), float(slash[2]))   # held still to the wrist's peak
	_hold_sword(_sword_id)
	if hit.is_empty(): return
	var cmd := {"type": "mine_attack", "floor": floor_n, "targets": hit.map(func(id): return Combat.mob_index(str(id)))}
	if rt.session.send(cmd, SWING_KEY % _swings): _swings_out[SWING_KEY % _swings] = true
	_swings += 1

## Rocks the server says are broken (another device, a reconnect) leave without the break animation.
func _sync_rocks(v: Dictionary) -> void:
	var broken := _broken(v, floor_n)
	var changed := false
	for i in broken.size():
		if broken[i] and _rocks.has(i) and not _breaking.has(i):
			_rocks[i].queue_free()
			_rocks.erase(i)
			changed = true
	if changed: _rebuild_nav(broken)

## The rock in front: nearest within reach, favouring what the player faces. Ladders and the elevator are tapped, never
## the key's (SGODOT-266).
func _pick_target() -> void:
	var best := {}
	var best_score := INF
	var f := actor.facing()
	var candidates: Array = []
	for i in _rocks: candidates.append({"kind": "rock", "rock": int(i), "at": Layout.FALLBACK_POSITIONS[i]})
	for c in candidates:
		var to: Vector3 = c.at - actor.position
		to.y = 0
		var d := to.length()
		if d > REACH: continue
		var score := d - 0.6 * (f.dot(to.normalized()) if d > 0.01 else 1.0)
		if score < best_score:
			best_score = score
			best = c
	_target = best

## The quick-bar selection in Mining (the torch): like seeds, the non-fishing bar selects into selected_seed.
func _selected_item() -> String:
	return rt.ui.selected_seed if rt.ui.bar_mode == "mine" else ""

## Hold the key to keep mining (the farm's hold-to-repeat): the same verb, one labour beat apart.
func _hold_repeat() -> void:
	if not rt.ui.fab_held or rt.ui.has_modal() or actor.busy() or rt.session.busy: return
	if Time.get_ticks_msec() < _hold_until: return
	var a: Dictionary = rt.ui.fab_state()
	var cmd: Dictionary = a.get("cmd", {})
	if not a.get("enabled", false) or str(cmd.get("type", "")) != "mine_rock": return
	if rt.ui.fab_verb == "": rt.ui.fab_verb = str(a.get("verb", ""))
	if str(a.get("verb", "")) != rt.ui.fab_verb: return
	p0_action(cmd)

## Floor-wide grey on a full bag (q(44)), torch previews over lit rocks, the status line.
func _marks(v: Dictionary) -> void:
	var marks := P0MaterialLogic.rock_marks(v, floor_n)
	var grey := not marks.is_empty() and bool(marks[0].grey)
	if grey != _grey:
		_grey = grey
		for i in _rocks:
			var mesh := (_rocks[i] as Node3D).get_node_or_null("Rock") as MeshInstance3D
			if mesh: mesh.transparency = 0.45 if grey else 0.0
	for i in marks.size():
		var drop = marks[i].preview
		var show: bool = drop != null and str(drop) != "" and _rocks.has(i)
		if show and not _previews.has(i):
			var s := Sprite3D.new()
			s.texture = P0Logic.icon(str(drop))
			s.pixel_size = 0.0045
			s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			s.no_depth_test = true
			s.position = Layout.FALLBACK_POSITIONS[i] + Vector3(0, 1.05, 0)
			objects.add_child(s)
			_previews[i] = s
		elif not show and _previews.has(i):
			_previews[i].queue_free()
			_previews.erase(i)
	var intro := Time.get_ticks_msec() - _entered_ms < STATUS_INTRO_MS
	rt.ui.set_status_line(P0MaterialLogic.mine_status(v, floor_n, intro))

## The facilities' world prompts (LOCK-07 v2, as on the farm): each one's icon button within P0WorldPrompts.RANGE, the
## nearest within CARD_REACH opens its strip; the one with its fee card up shows the card instead. The card folds when
## the player walks off.
func _prompts(v: Dictionary) -> void:
	if _card_for != "" and (not _facilities.has(_card_for) or P0FarmMaterials.flat(actor.position, _facilities[_card_for].at) > CARD_REACH):
		close_card()
	var cands: Array = []
	for id in _facilities: cands.append([id, _facilities[id].at, CARD_REACH])
	_strip_open = P0Garden.pick_card(cands, actor.position, _strip_open)
	_strip_side = _facing_side()
	for id in _facilities:
		var f: Dictionary = _facilities[id]
		var box: AABB = f.box
		var at: Vector3 = f.at
		var mark: Vector3 = Vector3(box.get_center().x, box.end.y + 0.15, box.get_center().z) if box.size != Vector3.ZERO else at + Vector3(0, 1.9, 0)
		var hit: Vector3 = box.get_center() if box.size != Vector3.ZERO else at + Vector3(0, 0.8, 0)
		var prompt := P0WorldPrompts.mine_facility(v, floor_n, str(f.kind))
		var screen := cam.unproject_position(mark)
		var tap := cam.unproject_position(hit)
		var show := P0WorldPrompts.show(id, _strip_open, P0FarmMaterials.flat(actor.position, f.at), prompt) \
			if id != _card_for and not rt.ui.has_modal() else P0WorldPrompts.Show.NONE
		if show == P0WorldPrompts.Show.BAR:
			rt.ui.name_bar(id, prompt.icon, str(prompt.text), str(prompt.fact), screen, true, _strip_side, bool(prompt.dimmed),
				int(prompt.status), tap)
		else:
			rt.ui.world_icon(id, prompt.icon, screen, show == P0WorldPrompts.Show.ICON, false, int(prompt.status), tap,
				str(prompt.get("count", "")))
	_show_card(v)

## A facility's art on screen: its world box's corners projected, grown to the 44 touch size (the floor hatch of the
## ladder down is flat); empty without art.
func _screen_rect(box: AABB) -> Rect2:
	if box.size == Vector3.ZERO: return Rect2()
	var r := Rect2(cam.unproject_position(box.get_endpoint(0)), Vector2.ZERO)
	for i in range(1, 8): r = r.expand(cam.unproject_position(box.get_endpoint(i)))
	var grow := maxf(0.0, UiTokens.SIZE_TOUCH - minf(r.size.x, r.size.y)) * 0.5
	return r.grow(grow)

## A facility's art in world space (all its meshes, the node's own included), an empty AABB without one.
static func _art_box(node: Node3D) -> AABB:
	if not is_instance_valid(node): return AABB()
	var box := AABB()
	var first := true
	for vi in node.find_children("*", "GeometryInstance3D", true, false):
		var b: AABB = (vi as GeometryInstance3D).global_transform * (vi as GeometryInstance3D).get_aabb()
		if b.size == Vector3.ZERO: continue
		box = b if first else box.merge(b)
		first = false
	if node is GeometryInstance3D and (node as GeometryInstance3D).get_aabb().size != Vector3.ZERO:
		var own: AABB = node.global_transform * (node as GeometryInstance3D).get_aabb()
		box = own if first else box.merge(own)
	return box

## The side a strip opens to: the character's facing on screen; facing the camera or away keeps the last side.
func _facing_side() -> UiWorldNameBar.Dir:
	var from := cam.unproject_position(actor.position)
	var dx := cam.unproject_position(actor.position + actor.facing()).x - from.x
	if absf(dx) < 6.0: return _strip_side
	return UiWorldNameBar.Dir.LEFT if dx < 0.0 else UiWorldNameBar.Dir.RIGHT

## The fee card over a ladder (UiEntryCard without a title: the destination is on its one button, 不知火舞 9ce583a8).
func _show_card(v: Dictionary) -> void:
	var on := _card_for != "" and not rt.ui.has_modal()
	if not on:
		if is_instance_valid(_entry): _entry.visible = false
		return
	if not is_instance_valid(_entry):
		if rt.ui.root == null: return
		_entry = UiEntryCard.new()
		_entry.theme = UiKit.theme()
		_entry.passive = true   # a drag starting on it is the joystick; p0_tap resolves the real tap (as on the farm)
		_entry.pressed.connect(_on_card_pressed)
		rt.ui.root.add_child(_entry)
	var f: Dictionary = _facilities[_card_for]
	_entry_data = P0MaterialLogic.mine_facility(v, floor_n, str(f.kind))
	if not bool(_entry_data.get("card", false)):   # paid meanwhile (the elevator, another device): a free move now
		var id := _card_for
		close_card()
		_arrive(id)
		return
	_entry.visible = true
	_entry.action = str(_entry_data.label)
	_entry.state = UiEntryCard.State.AVAILABLE if bool(_entry_data.enabled) else UiEntryCard.State.UNAVAILABLE
	_entry.amber = bool(_entry_data.amber)
	var box: AABB = f.box
	var at: Vector3 = f.at
	var top := cam.unproject_position(Vector3(box.get_center().x, box.end.y + 0.15, box.get_center().z) if box.size != Vector3.ZERO else at + Vector3(0, 1.9, 0))
	var size := _entry.get_combined_minimum_size()
	var r := WorldAnchor.place(size, top - Vector2(0, UiTokens.SPACE_WITHIN), Rect2(Vector2.ZERO, rt.ui.root.size), UiTokens.SPACE_WITHIN, true)
	# Never over the player: lifted clear of the body by 4, no higher than under the HUD (不知火舞 on #190).
	r = WorldAnchor.lift_clear(r, actor.screen_box(cam), P0FarmMaterials.BODY_GAP, rt.ui.card_top())
	_entry.size = size
	_entry.position = r.position
	_entry.point_at(top.x - r.position.x)

## The fee button: grey says why (LOCK-10), amber opens the Energy card for this floor, else the floor (2 Energy).
func _on_card_pressed() -> void:
	var d := _entry_data
	if not bool(d.get("enabled", false)):
		rt.ui.toast(str(d.get("toast", d.get("label", ""))))
		return
	var cmd: Dictionary = d.get("cmd", {})
	if str(cmd.get("type", "")) == "energy_card":
		rt.energy_card(int(d.get("need", 0)), str(d.get("verb", "")))
		return
	close_card()
	p0_action(cmd)

func card_shown() -> bool: return is_instance_valid(_entry) and _entry.visible
func card_entry() -> UiEntryCard: return _entry if card_shown() else null

# ---------------------------------------------------------------- actions
func p0_action(cmd: Dictionary) -> void:
	match str(cmd.get("type", "")):
		"mine_rock":
			var i := int(cmd.get("rock", -1))
			if _rocks.has(i): actor.labour("till", Layout.FALLBACK_POSITIONS[i])   # the old mine's dig beat (user, 2026-10-08)
			_hold_until = Time.get_ticks_msec() + int(maxf(P0Actor.LABOUR_S, 0.95) * 1000.0)   # server tempo 0.9 s
			rt.session.send(cmd)
		"mine_floor", "mine_torch", "mine_express":
			rt.session.send(cmd)
		"mine_swing":
			_swing()
		"elevator":
			P0MaterialCards.open_elevator(rt.ui, _view(), floor_n, _on_elevator_row)
		"mine_exit", "mine_leave":
			_leave()
		"toast":
			rt.ui.toast(str(cmd.get("text", "")))
		_:
			if not cmd.is_empty(): rt.session.send(cmd)

func _on_elevator_row(cmd: Dictionary) -> void:
	rt.ui.close_modal()
	match str(cmd.get("type", "")):
		"mine_leave": _leave()
		"mine_floor":
			if int(cmd.get("floor", 0)) == floor_n: return
			_elevator_to = int(cmd.get("floor", 0))
			rt.session.send(cmd)
		"mine_express":   # inside a run: a free ride to Floor 5 (§13.3.9)
			_elevator_to = FLOORS
			rt.session.send(cmd.merged({"space": "mine"}))
		"energy_card": rt.energy_card(int(cmd.get("need", 0)), str(cmd.get("verb", "")))

## Server results for this world: a rock breaks, a floor is reached or cleared, a torch lights the floor.
func _on_state(v: Dictionary, events: Array) -> void:
	if rt.world != self: return
	if events.any(func(e): return str(e.get("kind", "")) == "mine" and str(e.get("action", "")) in ["hurt", "knocked_out"]):
		_hurt_pending = false
	for line in P0MaterialLogic.mine_event_lines(events):
		var text := str(line.text)
		match str(line.action):
			"cleared", "express_unlocked": rt.ui.toast_success(text)   # MINE-P0-3 / MINE-4, §4.8.6 Toast Success
			"knocked_out": pass   # the moment below says it
			_:   # the floor fee `Floor 2 · −2 Energy` (q(46)): the Energy line of the reply's three (q(49) ①)
				rt.ui.queue_floats([{kind = "energy", key = text, text = text, tone = UiFloatText.Tone.ENERGY_COST}], rt.anchor())
	for e in events:
		if str(e.get("kind", "")) != "mine": continue
		match str(e.get("action", "")):
			"rock": _break_rock(int(e.get("rock", -1)), v)
			"floor", "express":
				var n := int(e.get("floor", floor_n))
				if n != floor_n: _go_floor(n, n == _elevator_to)
				_elevator_to = -1
			"hurt": combat.hurt(actor.mover, Combat.mob_id(int(e.get("mob", 0))), int(e.get("damage", 0)))
			"defeat":
				# the last one down on a floor with rocks left: back to Mining (Floor 3–4); Floor 5 completes the run
				if rt.ui.bar_mode == "combat" and P0MaterialLogic.mobs_up(v, floor_n) == 0 and rock_count(floor_n) > 0:
					rt.ui.set_mode("mine")
				if bool(e.get("quartz_spent", false)):
					rt.ui.queue_floats([{kind = "item", key = P0MaterialLogic.QUARTZ_ONCE, text = P0MaterialLogic.QUARTZ_ONCE,
						tone = UiFloatText.Tone.ITEM}], rt.anchor())
			"knocked_out":   # the elite's last blow and the player's fall count as a win (q(116) ③): see _knocked_out
				if not events.any(func(x): return str(x.get("kind", "")) == "mine" and str(x.get("action", "")) == "complete"): _knocked_out()
			"complete": _run_complete(v, events)
	if v.get("mine", {}).get("run", null) == null and not _completing: _hurt_pending = false

## The break the old mine never had: a short shake, shrink and stone chips, then only this rock goes (no floor rebuild).
func _break_rock(i: int, v: Dictionary) -> void:
	if not _rocks.has(i): return
	var rock: Node3D = _rocks[i]
	_breaking[i] = true
	_chips(rock.position)
	var tw := create_tween()
	tw.tween_property(rock, "rotation:z", 0.12, BREAK_S * 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(rock, "rotation:z", -0.1, BREAK_S * 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_property(rock, "scale", Vector3(0.2, 0.05, 0.2), BREAK_S * 0.64).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.finished.connect(func():
		if is_instance_valid(rock): rock.queue_free()
		_rocks.erase(i)
		_breaking.erase(i)
		if _previews.has(i):
			_previews[i].queue_free()
			_previews.erase(i)
		_rebuild_nav(_broken(rt.session.current(), floor_n)))

func _chips(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 14
	p.lifetime = 0.6
	p.explosiveness = 0.95
	p.position = at + Vector3(0, 0.35, 0)
	p.direction = Vector3.UP
	p.spread = 70
	p.initial_velocity_min = 1.6
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.11
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("687376")
	mat.roughness = 0.95
	mesh.material = mat
	p.mesh = mesh
	objects.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

## Out of the mine: back to the farm (this world sits above it), 0 Energy (q(44)). The run stays until 04:00. One
## layer down, like a room's door: leave_world goes all the way to the map (the place chip's path), which took the
## exit ladder and the elevator's Ground to the map (user int11 ①, 不知火舞 on 231).
func _leave() -> void:
	if _leaving: return
	_leaving = true
	close_card()
	actor.set_input(Vector2.ZERO)
	rt.leave_room()

## 04:00 while inside: back outside the mouth, where the farm floats "Run ended at daily reset" once (q(44)).
func _kick_out() -> void:
	if _completing: return   # Run complete leaves by itself after its banner
	_leave()

## MINE-KO-MOMENT: HP 0 — input stops, `Knocked out` · `back at the entrance` over a scrim for 1.5 s, then out to the
## mine mouth; the run is kept (Continue run · Free) and HP is full again outside (§13.3.1).
const KO_S := 1.5
func _knocked_out() -> void:
	if _leaving or _completing: return   # the elite went down first (q(116) ③): Run complete only
	if not _swings_out.is_empty():   # a swing still on its way may beat the elite: wait for it
		_ko_waiting = true
		return
	_ko = true
	actor.set_input(Vector2.ZERO)
	actor.lock(true)
	rt.ui.toast(P0MaterialLogic.mine_event_text({"kind": "mine", "action": "knocked_out"}), KO_S)
	get_tree().create_timer(KO_S).timeout.connect(func():
		if is_inside_tree(): _leave())

## MINE-5: the elite beaten ends the run — the Run complete banner, then out to the mine mouth.
const COMPLETE_S := 2.5
func _run_complete(v: Dictionary, events: Array) -> void:
	_completing = true
	var loot = null
	for e in events:
		if str(e.get("kind", "")) == "mine" and str(e.get("action", "")) == "defeat" and str(e.get("mob_kind", "")) == "mob_elite_slime":
			loot = e.get("loot", null)
	var spec := P0MaterialLogic.run_complete(v, loot)
	spec.rewards = (spec.rewards as Array).map(func(r): return {"text": r.text, "tone": UiFloatText.Tone.ITEM, "icon": P0Logic.icon(str(r.item))})
	rt.ui.show_banner(spec)
	get_tree().create_timer(COMPLETE_S).timeout.connect(func():
		if is_inside_tree(): _leave())

# ---------------------------------------------------------------- camera (old mine framing + safe box)
func _follow(dt: float) -> void:
	_focus = _cam_follow.step(cam, _focus, actor.position, actor.mover.is_moving(), dt)
	if _pinch.step(dt): _set_zoom(_pinch.value)   # springing back from past a limit, about the same point
	else:
		_update_camera()
		if _after_pinch: _ease_back_after_pinch()

## A pinch zooms about the fingers, which can leave the player outside the safe box — half off the screen at a room's
## end (李元芳 int12, 奕星). Once the fingers have lifted and the zoom has settled, the camera eases back to them as
## after a step (P0Follow, 0.6 s); with the player still inside the box the pinched framing stays until they walk.
func _ease_back_after_pinch() -> void:
	_after_pinch = false
	if not P0Follow.box(get_viewport().get_visible_rect().size).has_point(cam.unproject_position(actor.position)):
		_cam_follow.held = false

func _update_camera() -> void:
	cam.size = FarmCamera.player_scale_size(get_viewport().get_visible_rect().size, FarmCamera.PITCH_DEG) / _zoom
	FarmCamera.place(cam, _focus + Vector3.UP * 0.7)
	_frame_chamber()
	FarmCamera.fit_ground_depth(cam)

## Framing (不知火舞 on 231, the rooms' rule of #127). Down: the four corners of the band between the HUD and the quick
## bar / main key (_camera_band) land in the room — the top corners at the wall tops within the back wall, the bottom
## corners on the floor within the front edge; the room is wider than that band, so the focus stays at the middle of
## the range this gives (fixed). Across: the room is wider than the screen, so the safe box follows, but stops where the
## art's outer edge — the walls, the ladders and the elevator on them — comes P0Room.SIDE_MARGIN (18 px) from the
## screen's side, the mine's dark backdrop showing past it. Moves `_focus` itself, so the follow and the pinch carry on.
func _frame_chamber() -> void:
	if _room.size == Vector3.ZERO: return
	var vp := get_viewport().get_visible_rect().size
	var band := _camera_band(rt.ui if rt != null else null, vp)
	if band.size.x <= 0.0 or band.size.y <= 0.0: return
	var lo := -INF
	var hi := INF
	for c in [band.position, Vector2(band.end.x, band.position.y), Vector2(band.position.x, band.end.y), band.end]:
		var far: bool = c.y == band.position.y
		var off := _ray_at(c, _room.end.y if far else _room.position.y) - _focus
		if far: lo = maxf(lo, _room.position.z - off.z)
		else: hi = minf(hi, _room.end.z - off.z)
	var z := clamp_or_centre(_focus.z, lo, hi)
	if not is_equal_approx(z, _focus.z):
		_focus.z = z
		FarmCamera.place(cam, _focus + Vector3.UP * 0.7)
	# Across, on screen: the art's outermost points against the side margins. Moving the focus along the ground's x
	# moves the picture across by cos(yaw) of it (orthographic: the same everywhere), so one step lands it.
	var sides := _side_points()
	if sides.is_empty(): return
	var dx := side_shift(cam.unproject_position(sides[0]).x, cam.unproject_position(sides[1]).x, vp.x, P0Room.SIDE_MARGIN)
	if is_zero_approx(dx): return
	var px_per_x := cam.global_basis.x.x * vp.x / cam.size   # screen px per metre of ground x
	if absf(px_per_x) < 0.0001: return
	_focus.x -= dx / px_per_x
	FarmCamera.place(cam, _focus + Vector3.UP * 0.7)

## How far (px) the art spanning left..right must move across a screen `width` wide: into the middle when it fits
## inside the margins, else only so far that neither side shows more than `margin` of backdrop.
static func side_shift(left: float, right: float, width: float, margin: float) -> float:
	if right - left <= width - 2.0 * margin: return (width - left - right) * 0.5
	if left > margin: return margin - left
	if right < width - margin: return width - margin - right
	return 0.0

## The band to frame into: P0Ui.camera_band while no panel is up, else the last one seen then (苏烈 on #129). A panel
## that hides the quick bar and the key (the inbox, the profile, the skills) would stretch the band to the screen's
## foot and the fixed middle would move — the room jumping behind the panel and back. The whole viewport until a band
## has been seen.
func _camera_band(ui: P0Ui, viewport: Vector2) -> Rect2:
	if ui != null and ui.is_node_ready() and not ui.has_modal(): _band = ui.camera_band()
	return _band if _band.has_area() else Rect2(Vector2.ZERO, viewport)

## Where the camera ray through a screen point (this UI's coordinates) crosses the plane at height y.
func _ray_at(screen: Vector2, y: float) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var n := cam.project_ray_normal(screen)
	return o + n * ((y - o.y) / n.y) if absf(n.y) > 0.0001 else o

## The allowed range's middle when it is empty (the band is wider than the room: that axis stays fixed), else v clamped.
static func clamp_or_centre(v: float, lo: float, hi: float) -> float:
	return (lo + hi) * 0.5 if lo > hi else clampf(v, lo, hi)

## The floor's walls: of the art's meshes, the one standing taller than half a metre with the widest footprint — the
## carved walls; Art.VIEW_BOUNDS if none is found.
static func _walls_box(root: Node3D) -> AABB:
	var best := AABB()
	for b in _art_boxes(root):
		if b.size.y > 0.5 and b.size.x * b.size.z > best.size.x * best.size.z: best = b
	return best if best.size != Vector3.ZERO else Art.VIEW_BOUNDS

## The art's leftmost and rightmost vertex on screen. The camera only turns with the yaw, which is fixed, so they are
## found once per floor (and again only if the camera's right changes) and projected each frame — the real outer edge,
## not a box corner standing out past a rounded wall end.
func _side_points() -> PackedVector3Array:
	var r := cam.global_basis.x
	if _art_points.is_empty(): return PackedVector3Array()
	if r.is_equal_approx(_art_right) and _art_sides.size() == 2: return _art_sides
	var lo := _art_points[0]
	var hi := _art_points[0]
	for p in _art_points:
		if p.dot(r) < lo.dot(r): lo = p
		if p.dot(r) > hi.dot(r): hi = p
	_art_right = r
	_art_sides = PackedVector3Array([lo, hi])
	return _art_sides

## Every mesh vertex under `root` in world space (MeshInstance3D and MultiMeshInstance3D); lights and decals have none
## that matter here, the wall contact shade lies flat inside the walls' reach.
static func _art_vertices(root: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	if root == null: return out
	var nodes: Array = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D: nodes.append(root)
	for g in nodes:
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var xf: Transform3D = (g as Node3D).global_transform
			if (g as MeshInstance3D).get_aabb().size.y <= 0.01: continue   # flat decals
			for v in (g as MeshInstance3D).mesh.get_faces(): out.append(xf * v)
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm.mesh == null: continue
			var faces := mm.mesh.get_faces()
			var base: Transform3D = (g as Node3D).global_transform
			for i in mm.instance_count:
				var xf := base * mm.get_instance_transform(i)
				for v in faces: out.append(xf * v)
	return out

## One world box per mesh under `root` — lights and flat decals left out (the wall contact shade reaches past the
## walls); not merged, so a tall piece inside (the elevator) does not raise the walls' corners.
static func _art_boxes(root: Node3D) -> Array[AABB]:
	var out: Array[AABB] = []
	if root == null: return out
	for vi in root.find_children("*", "VisualInstance3D", true, false):
		if vi is Light3D: continue
		var b: AABB = (vi as VisualInstance3D).global_transform * (vi as VisualInstance3D).get_aabb()
		if b.size.y > 0.01: out.append(b)
	return out

## Zoom about the last pinch centre: the ground point under the fingers stays put (the farm's _set_zoom).
func _set_zoom(value: float) -> void:
	_zoom = value
	if cam == null or not is_inside_tree(): return
	var before = ElasticZoom.ground_at(cam, _zoom_at, _focus.y)
	_update_camera()
	var d := ElasticZoom.shift(before, ElasticZoom.ground_at(cam, _zoom_at, _focus.y))
	if d != Vector3.ZERO:
		_focus += d
		_update_camera()

func p0_zoom(f: float, at := Vector2.INF) -> void:
	_after_pinch = false
	_zoom_at = at
	_pinch.pinch(f)
	_cam_follow.hold()   # the pinched framing stays until the player walks (the safe box takes over then)
	_set_zoom(_pinch.value)
func p0_zoom_end() -> void:
	_pinch.release()
	_after_pinch = true
func p0_recenter() -> void:
	_focus = actor.position
	_cam_follow.held = false

func p0_anchor() -> Vector2:
	var at: Vector3 = _target.get("at", actor.position) if not _target.is_empty() else actor.position
	return cam.unproject_position(at + Vector3(0, 1.0, 0))

func is_back_navigation_locked() -> bool: return false

func suspend() -> void:
	close_card()
	process_mode = Node.PROCESS_MODE_DISABLED
	hide()
	cam.current = false
	world_env.environment = null

func resume() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	show()
	get_viewport().transparent_bg = false
	world_env.environment = environment
	cam.make_current()
	if rt: rt.attach(self)

# ---------------------------------------------------------------- dev steps for P0_SHOT
func p0_dev(step: PackedStringArray) -> bool:
	match step[0]:
		"goto":
			actor.teleport(Vector3(float(step[1]), 0, float(step[2])))
			_focus = actor.position
		"rock":
			var i := int(step[1])
			actor.teleport(Layout.approach(actor.mover, Layout.FALLBACK_POSITIONS[i]))
			actor.face(Layout.FALLBACK_POSITIONS[i])
			_focus = actor.position
		"floor": _go_floor(int(step[1]))
		"combat": rt.ui.set_mode("combat" if step.size() < 2 or step[1] != "0" else "mine")   # combat[:0] — the radial's pick
		"attack": _swing()   # one Attack (Combat's key)
		"attacks":   # attacks:n:ms[:delay ms] — n presses of Attack ms apart in game time (shots of the slash, SGODOT-291)
			var after := float(step[3]) / 1000.0 if step.size() > 3 else 0.0
			for i in int(step[1]): get_tree().create_timer(after + float(step[2]) / 1000.0 * i, false).timeout.connect(_swing)
		"near":   # near:i — stand next to monster i (the screenshots' fight)
			var e: Dictionary = combat.enemies.get(Combat.mob_id(int(step[1])), {}) if combat else {}
			if not e.is_empty():
				actor.teleport((e.node as Node3D).position + Vector3(1.0, 0, 0.4))
				actor.face((e.node as Node3D).position)
				_focus = actor.position
				_cam_follow.hold()
		"elevator": p0_action({"type": "elevator"})
		"tapfac":   # tapfac:mine_down — a tap on that facility's model (walk up, then use it; SGODOT-266)
			p0_tap(cam.unproject_position((_facilities[step[1]].box as AABB).get_center()) if _facilities.has(step[1]) else Vector2(-1, -1))
		"cardtap":   # cardtap — a real tap on the open fee card's button
			if card_shown(): p0_tap(_entry.main_rect().get_center() - rt.ui.root.global_position)
		"elevrow":   # elevrow:0 — press that row of the open elevator panel (row 0 is Ground)
			for n in rt.ui.find_children("*", "", true, false):
				if n is UiElevatorPanel and (n as UiElevatorPanel).row(int(step[1])) != null:
					(n as UiElevatorPanel).row(int(step[1])).pressed.emit()
					break
		"exit": _leave()
		"backdrop":   # backdrop:0|1 — the on/off check (SGODOT-257)
			if is_instance_valid(backdrop): backdrop.visible = step[1] != "0"
		"zoom":   # zoom:0.8 — a pinch to that zoom, fingers lifted
			p0_zoom(_pinch.value / float(step[1]))
			p0_zoom_end()
		"pinch":   # pinch:1.4:4:400 — a pinch to that zoom about that screen point, fingers lifted (int12)
			p0_zoom(_pinch.value / float(step[1]), Vector2(float(step[2]), float(step[3])))
			p0_zoom_end()
		_: return false
	return true

func p0_until(name: String) -> bool:
	match name:
		"floor2": return floor_n == 2
		"floor1": return floor_n == 1
		"idle": return not actor.busy()
		"arrived": return _walk.is_empty() and not actor.mover.is_moving()
		"card": return card_shown()
	return false
