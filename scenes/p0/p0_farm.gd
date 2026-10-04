extends Node3D
## P0 milestone 1 — the homestead slice (plan v2 §17.2): energy → farming → stall → energy.
## World is built in code (island, 30 plots, house, bench, Bao's stall); the player walks with the floating joystick,
## the camera follows inside a safe box (§10.1), the main action works on the plot in front (§10.2.2), and facilities
## respond to taps only (Bao greets first, p(4); the bench offers Rest). Rules live on the P0 server (server/src/p0).

const CELL := 1.25
const COLS := 6
const ISLAND := Rect2(-7.6, -7.6, 15.2, 15.2)
const SPAWN := Vector3(-3.0, 0, 0.6)
const SPEED := 3.75
const STALL := Vector3(-0.4, 0, -5.2)
const BAO := Vector3(-0.4, 0, -5.9)
const BENCH := Vector3(-5.6, 0, -2.0)
const HOUSE := Vector3(-5.2, 0, -5.4)
const POND := Vector3(4.6, 0, -5.0)
const POND_R := Vector2(2.3, 1.6)
const STOVE := Vector3(-5.8, 0, 1.2)
const TACKLE := Vector3(-6.2, 0, 4.2)   # Old Kai's tackle stand at the west end of the creek
const KAI := Vector3(-6.2, 0, 4.75)
const CREEK_Z := 6.25          # Willow Creek runs east–west along the south edge (River template)
const CREEK_HALF := 0.55
const PITCH := 43.0
const YAW := 14.5
const CROP_COLORS := {
	"crop_radish": Color("e8607a"), "crop_lettuce": Color("9bd07a"), "crop_herb": Color("6fbf5e"), "crop_carrot": Color("f08a3c"),
	"crop_potato": Color("c9a27a"), "crop_chamomile": Color("f6eecb"), "crop_chili": Color("e0503c"), "crop_tomato": Color("e8604a"),
}

var session: P0Session
var ui: P0Ui
var cam: Camera3D
var player: Node3D
var rig: Node3D
var _anim := ""
var _joy := Vector2.ZERO
var _facing := Vector3(0, 0, 1)
var _focus := Vector3.ZERO
var _idle_s := 0.0
var _plots := {}           # id -> {"base": MeshInstance3D, "crop": Node3D, "pos": Vector3, "state": "", "crop_id": ""}
var _front: Dictionary = {}
var _hi: MeshInstance3D
var _obstacles: Array[Rect2] = []
var _seed := ""
var _mats := {}
var _shot_t := 0.0
var _shot_script: Array = []
var _mode := "farm"
var _fishing: P0Fishing
var _cooking: P0Cooking
var _rod: MeshInstance3D
var _bobber: MeshInstance3D
var _line: MeshInstance3D
var _bob_target := Vector3.ZERO
var _bob_phase := ""
var _water: MeshInstance3D
var _hold_last := {}
var _hold_t := 0.0
var _site := "pond"

func _ready() -> void:
	# The map app runs with a transparent window (native map underlay); the P0 farm is an opaque world.
	get_viewport().transparent_bg = false
	get_window().transparent = false
	RenderingServer.set_default_clear_color(Color("b9dccf"))
	_build_world()
	session = P0Session.new()
	add_child(session)
	ui = P0Ui.new()
	add_child(ui)
	ui.joystick.connect(func(v): _joy = v)
	ui.tapped.connect(_on_tap)
	ui.action_pressed.connect(_on_action)
	ui.command.connect(func(cmd): session.send(cmd))
	ui.seed_selected.connect(func(id): _seed = id)
	ui.dev_skip.connect(func(m): session.dev_skip(m); ui.toast("Clock +%dh (dev)" % (m / 60)))
	ui.zoom.connect(func(f: float): cam.size = clampf(cam.size * f, 6.5, 17.0))
	ui.recenter.connect(func(): _focus = player.position)
	ui.show_spot.connect(_show_spot)
	session.state_changed.connect(_on_state)
	session.refused.connect(_on_refused)
	session.connection_failed.connect(func(msg): ui.toast(msg + " · " + session.base_url, 4.0))
	if OS.get_environment("P0_AUTO") == "1" or FileAccess.file_exists("user://p0_auto"):
		P0Fishing.auto_play = true
		P0Cooking.auto_play = true

# ---------------------------------------------------------------- world
func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var key := color.to_html()
	if _mats.has(key): return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	_mats[key] = m
	return m

func _box(size: Vector3, pos: Vector3, color: Color, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)
	return mi

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("b9dccf")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("fff4e0")
	e.ambient_light_energy = 0.42
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	# backdrop: a huge unlit pastel floor under the island so no transparent pixel can show through on Android
	var floor := _box(Vector3(220, 0.1, 220), Vector3(0, -3.0, 0), Color("b9dccf"))
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("b9dccf")
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor.material_override = fm
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# island: sand slab + grass top + a path to the stall
	_box(Vector3(16, 0.8, 16), Vector3(0, -0.42, 0), Color("d9bb84"))
	_box(Vector3(15.4, 0.04, 15.4), Vector3(0, 0.0, 0), Color("7fb84f"))
	_box(Vector3(1.4, 0.05, 6.0), Vector3(-2.6, 0.01, -2.4), Color("e8d4a8"))
	_box(Vector3(5.0, 0.05, 1.3), Vector3(-4.6, 0.01, -3.4), Color("e8d4a8"))
	# house
	_box(Vector3(3.0, 2.0, 2.6), HOUSE + Vector3(0, 1.0, 0), Color("f3e9d6"))
	var roof := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(3.5, 1.3, 3.0)
	roof.mesh = pm
	roof.position = HOUSE + Vector3(0, 2.65, 0)
	roof.material_override = _mat(Color("d9785b"))
	add_child(roof)
	_box(Vector3(0.7, 1.2, 0.08), HOUSE + Vector3(0.5, 0.6, 1.32), Color("6f9e5a"))
	_obstacles.append(Rect2(HOUSE.x - 1.7, HOUSE.z - 1.5, 3.4, 3.0))
	# bench
	_box(Vector3(1.4, 0.12, 0.5), BENCH + Vector3(0, 0.42, 0), Color("b98a5e"))
	_box(Vector3(1.4, 0.4, 0.1), BENCH + Vector3(0, 0.7, -0.22), Color("a8794f"))
	for x in [-0.6, 0.6]: _box(Vector3(0.1, 0.4, 0.4), BENCH + Vector3(x, 0.2, 0), Color("9a6f47"))
	_obstacles.append(Rect2(BENCH.x - 0.8, BENCH.z - 0.35, 1.6, 0.7))
	# Bao's stall: counter, posts, roof, hay
	_box(Vector3(2.6, 0.9, 0.7), STALL + Vector3(0, 0.45, 0), Color("c49a6c"))
	_box(Vector3(2.7, 0.08, 0.8), STALL + Vector3(0, 0.92, 0), Color("a8794f"))
	for x in [-1.25, 1.25]: _box(Vector3(0.14, 2.3, 0.14), STALL + Vector3(x, 1.15, -0.9), Color("9a6f47"))
	var sroof := MeshInstance3D.new()
	var spm := PrismMesh.new()
	spm.size = Vector3(3.1, 0.7, 2.2)
	sroof.mesh = spm
	sroof.position = STALL + Vector3(0, 2.6, -0.6)
	sroof.material_override = _mat(Color("d9785b"))
	add_child(sroof)
	for i in 3: _box(Vector3(0.55, 0.45, 0.55), STALL + Vector3(-0.8 + i * 0.75, 0.22, -1.45), Color("f0c86a"))
	_obstacles.append(Rect2(STALL.x - 1.4, STALL.z - 1.9, 2.8, 2.3))
	_spawn_bao()
	_build_pond()
	_build_creek()
	_build_stove()
	_build_tackle()
	# plots
	for id in 30:
		var col := id % COLS
		var row := id / COLS
		var pos := Vector3(-1.0 + col * CELL, 0, -1.6 + row * CELL)
		var base := _box(Vector3(1.08, 0.1, 1.08), pos + Vector3(0, 0.05, 0), Color("8dbe5e"))
		var crop := Node3D.new()
		crop.position = pos + Vector3(0, 0.1, 0)
		add_child(crop)
		_plots[id] = {"base": base, "crop": crop, "pos": pos, "state": "", "crop_id": ""}
	_hi = _box(Vector3(1.2, 0.02, 1.2), Vector3(0, 0.13, 0), Color(0.5, 0.78, 0.42, 0.55))
	var hm := _mat(Color(0.5, 0.78, 0.42, 0.5)).duplicate() as StandardMaterial3D
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hi.material_override = hm
	_hi.visible = false
	# player
	player = Node3D.new()
	player.position = SPAWN
	add_child(player)
	rig = Avatar.create_rig()
	rig.assembler = AvatarAssemblerMerged.new()
	rig.rotation.y = PI
	player.add_child(rig)
	rig.config_applied.connect(func(_c): _play("idle"))
	Avatar.follow_saved_outfit(rig)
	# camera
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = 10.5
	cam.near = 0.1
	cam.far = 80.0
	add_child(cam)
	_focus = player.position + Vector3(1.4, 0, 0.8)
	_place_camera()

## Willow Pond (FISH-1): soft-gel water with a sand rim, a willow and reeds. Water blocks walking.
func _build_pond() -> void:
	var rim := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 1.0
	rm.bottom_radius = 1.0
	rm.height = 0.05
	rm.radial_segments = 48
	rim.mesh = rm
	rim.scale = Vector3(POND_R.x + 0.45, 1, POND_R.y + 0.45)
	rim.position = POND + Vector3(0, 0.02, 0)
	rim.material_override = _mat(Color("e8d4a8"))
	add_child(rim)
	_water = MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 1.0
	wm.bottom_radius = 1.0
	wm.height = 0.06
	wm.radial_segments = 48
	_water.mesh = wm
	_water.scale = Vector3(POND_R.x, 1, POND_R.y)
	_water.position = POND + Vector3(0, 0.04, 0)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.45, 0.72, 0.86, 0.88)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.15
	water.metallic_specular = 0.8
	_water.material_override = water
	add_child(_water)
	for i in 3:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.28 + i * 0.22
		tm.outer_radius = 0.31 + i * 0.22
		ring.mesh = tm
		ring.position = POND + Vector3(-0.6, 0.08, 0.2)
		ring.scale = Vector3(1, 0.2, 0.8)
		ring.material_override = _mat(Color(0.86, 0.95, 1.0))
		add_child(ring)
	# willow: trunk + drooping green blobs
	var willow := POND + Vector3(2.2, 0, -1.4)
	_box(Vector3(0.35, 1.8, 0.35), willow + Vector3(0, 0.9, 0), Color("8a6544"))
	for k in 6:
		var a := TAU * k / 6.0
		_sphere(self, willow + Vector3(cos(a) * 0.7, 1.9 - (k % 2) * 0.35, sin(a) * 0.6), 0.62, Color("8cc56e") if k % 2 == 0 else Color("7db35e"))
	_sphere(self, willow + Vector3(0, 2.35, 0), 0.8, Color("95cc76"))
	_obstacles.append(Rect2(willow.x - 0.4, willow.z - 0.4, 0.8, 0.8))
	for k in 5:
		var at := POND + Vector3(-POND_R.x - 0.1 + k * 0.12, 0, 0.9 + k * 0.1)
		_box(Vector3(0.05, 0.6 + (k % 3) * 0.15, 0.05), at + Vector3(0, 0.3, 0), Color("6f9e5a"))

## Willow Creek: a shallow stream across the south edge with sandy banks and stepping stones.
func _build_creek() -> void:
	_box(Vector3(15.4, 0.05, CREEK_HALF * 2 + 0.7), Vector3(0, 0.02, CREEK_Z), Color("e8d4a8"))
	var creek := _box(Vector3(15.6, 0.07, CREEK_HALF * 2), Vector3(0, 0.05, CREEK_Z), Color(0.45, 0.72, 0.86))
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.5, 0.76, 0.88, 0.9)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.roughness = 0.15
	creek.material_override = water
	for k in 7:
		_box(Vector3(0.9, 0.02, 0.06), Vector3(-6.0 + k * 2.0 + (k % 2) * 0.4, 0.1, CREEK_Z - 0.2 + (k % 3) * 0.2), Color(0.88, 0.96, 1.0))
	for k in 4:
		_sphere(self, Vector3(-3.5 + k * 2.6, 0.08, CREEK_Z + 0.75), 0.16, Color("c9c2b0"))
		_box(Vector3(0.05, 0.55, 0.05), Vector3(-2.6 + k * 2.6, 0.27, CREEK_Z - 0.75), Color("6f9e5a"))

## Old Kai's tackle stand: a small counter with a blue awning, rods on a rack; Kai stands behind it.
func _build_tackle() -> void:
	_box(Vector3(1.6, 0.8, 0.6), TACKLE + Vector3(0, 0.4, 0), Color("a8c4d4"))
	_box(Vector3(1.7, 0.07, 0.7), TACKLE + Vector3(0, 0.83, 0), Color("7d9fb4"))
	for x in [-0.75, 0.75]: _box(Vector3(0.1, 1.9, 0.1), TACKLE + Vector3(x, 0.95, 0.45), Color("8a6544"))
	_box(Vector3(1.8, 0.08, 1.0), TACKLE + Vector3(0, 1.92, 0.25), Color("6fa8dc"))
	for i in 3: _box(Vector3(0.04, 1.3, 0.04), TACKLE + Vector3(-0.5 + i * 0.5, 1.35, -0.15), Color("c9a27a"))
	_obstacles.append(Rect2(TACKLE.x - 0.9, TACKLE.z - 0.4, 1.8, 1.4))
	var kai := Avatar.create_rig()
	kai.assembler = AvatarAssemblerMerged.new()
	var holder := Node3D.new()
	holder.position = KAI
	add_child(holder)
	holder.add_child(kai)
	kai.apply_config(Avatar.slot_table.default_config())
	kai.config_applied.connect(func(_c): kai.play_motion("idle"))
	kai.rotation.y = 0.0

## Outdoor kitchen (COOK-1, P0 has one stove): brick stove, pot, chimney and a side counter. Tap to cook.
func _build_stove() -> void:
	_box(Vector3(1.3, 0.8, 0.9), STOVE + Vector3(0, 0.4, 0), Color("c8775a"))
	_box(Vector3(1.36, 0.08, 0.96), STOVE + Vector3(0, 0.84, 0), Color("6e5b52"))
	_box(Vector3(0.3, 1.2, 0.3), STOVE + Vector3(0.45, 1.4, -0.28), Color("b4664c"))
	var pot := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.3
	pm.bottom_radius = 0.24
	pm.height = 0.3
	pot.mesh = pm
	pot.position = STOVE + Vector3(-0.15, 1.03, 0.05)
	pot.material_override = _mat(Color("4a5560"), 0.4)
	add_child(pot)
	_box(Vector3(0.12, 0.12, 0.12), STOVE + Vector3(-0.15, 0.6, 0.46), Color("f0a24a"))
	_box(Vector3(1.0, 0.75, 0.8), STOVE + Vector3(1.25, 0.37, 0), Color("d9c39a"))
	_box(Vector3(1.06, 0.06, 0.86), STOVE + Vector3(1.25, 0.77, 0), Color("b98a5e"))
	_obstacles.append(Rect2(STOVE.x - 0.7, STOVE.z - 0.5, 2.5, 1.0))

func _spawn_bao() -> void:
	var bao := Avatar.create_rig()
	bao.assembler = AvatarAssemblerMerged.new()
	bao.rotation.y = PI
	var holder := Node3D.new()
	holder.position = BAO
	holder.rotation.y = PI
	add_child(holder)
	holder.add_child(bao)
	bao.apply_config(Avatar.slot_table.default_config())
	bao.config_applied.connect(func(_c): bao.play_motion("idle"))
	var hat := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.46
	cyl.height = 0.06
	hat.mesh = cyl
	hat.position = BAO + Vector3(0, 1.86, 0)
	hat.material_override = _mat(Color("e9c97f"))
	add_child(hat)

func _place_camera() -> void:
	var p := deg_to_rad(PITCH)
	var y := deg_to_rad(YAW)
	var d := 24.0
	cam.position = _focus + Vector3(sin(y) * d * cos(p), d * sin(p), cos(y) * d * cos(p))
	cam.look_at(_focus, Vector3.UP)

# ---------------------------------------------------------------- frame
func _process(dt: float) -> void:
	_dev_shot(dt)
	_move(dt)
	_follow(dt)
	var v := session.current()
	if v.is_empty(): return
	ui.set_view(v)
	_sync_plots(v)
	_site = "pond" if _pond_d(player.position, 1.7) < 1.0 else ("river" if player.position.z > CREEK_Z - CREEK_HALF - 1.3 else "")
	_mode = "fish" if _site != "" else "farm"
	var site_name := str(v.get("fishing", {}).get("sites", {}).get(_site, {}).get("name", "Willow Pond")) if _site != "" else ""
	ui.set_mode(_mode, site_name)
	if _mode == "fish":
		_front = {}
		_hi.visible = false
		ui.set_action(P0Logic.fish_action(v, ui.selected_bait, _site))
	else:
		_pick_front(v)
		ui.set_action(P0Logic.main_action(v, _front, _seed))
	_update_tags(v)
	_animate_bobber(dt)
	_hold_repeat(dt)
	_teaching(v)
	ui.player_screen = cam.unproject_position(player.position + Vector3(0, 1.0, 0))

## §14.3 one-line teaching cards, each the first time its moment comes (the card keeps its own memory).
func _teaching(v: Dictionary) -> void:
	if ui.has_modal() or _fishing != null or _cooking != null: return
	var firsts: Array = v.get("firsts", [])
	if _mode == "farm" and not firsts.any(func(f): return str(f).begins_with("harvest:")) and not v.get("plots", []).any(func(p): return str(p.state) in ["sown", "growing", "ready"]):
		ui.teach("sow", "Pick a seed, walk up to a plot and press Sow. Hold to keep sowing.")
	elif _mode == "fish":
		ui.teach("cast", "Casting uses 5 Energy. If the fish gets away, most of it comes back.")
		if P0Logic.bag_count(v, "bait_worm") > 0: ui.teach("bait", "Tap Worm Bait to put it on the hook · faster bites, more Fine fish.")
	elif player.position.distance_to(STOVE) < 4.0 and not firsts.any(func(f): return str(f).begins_with("cook:")) and P0Logic.today_line(v).contains("fish"):
		ui.teach("stove", "Tap the stove to grill your first fish.")

## Hold-to-repeat (§14.2 "Hold to keep sowing"): the same verb on each new plot in front, never a new verb.
func _hold_repeat(dt: float) -> void:
	_hold_t -= dt
	if not ui.fab_held or _mode != "farm" or ui.has_modal():
		_hold_last = {}
		return
	var a: Dictionary = ui.fab_state()
	var cmd: Dictionary = a.get("cmd", {})
	if not a.get("enabled", false) or cmd.is_empty() or str(cmd.get("type", "")) == "energy_card": return
	if ui.fab_verb == "": ui.fab_verb = str(a.get("verb", ""))   # pressed before reaching a plot: the first verb met sticks
	if str(a.get("verb", "")) != ui.fab_verb: return
	if cmd == _hold_last or _hold_t > 0.0 or session.busy: return
	_hold_last = cmd
	_hold_t = 0.18
	_on_action(cmd)

func _move(dt: float) -> void:
	var v := _joy
	if Input.is_key_pressed(KEY_W): v.y -= 1
	if Input.is_key_pressed(KEY_S): v.y += 1
	if Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_D): v.x += 1
	if v == Vector2.ZERO or ui.has_modal() or _fishing != null or _cooking != null:
		_play("idle")
		_idle_s += dt
		return
	_idle_s = 0.0
	var right := cam.global_basis.x
	right.y = 0
	right = right.normalized()
	var fwd := -cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var dir := (right * v.x - fwd * v.y)
	if dir.length() > 1.0: dir = dir.normalized()
	var step := dir * SPEED * dt
	var next := player.position + step
	if not _blocked(next): player.position = next
	elif not _blocked(player.position + Vector3(step.x, 0, 0)): player.position += Vector3(step.x, 0, 0)
	elif not _blocked(player.position + Vector3(0, 0, step.z)): player.position += Vector3(0, 0, step.z)
	if dir.length() > 0.05:
		_facing = dir.normalized()
		player.look_at(player.position + _facing, Vector3.UP)
	_play("run")

func _pond_d(p: Vector3, pad := 0.0) -> float:
	return Vector2((p.x - POND.x) / (POND_R.x + pad), (p.z - POND.z) / (POND_R.y + pad)).length()

func _blocked(p: Vector3) -> bool:
	if not ISLAND.grow(-0.4).has_point(Vector2(p.x, p.z)): return true
	if _pond_d(p, 0.25) < 1.0: return true
	if p.z > CREEK_Z - CREEK_HALF - 0.3: return true
	for r in _obstacles:
		if r.has_point(Vector2(p.x, p.z)): return true
	return false

## Safe-box follow: the camera moves only when the player leaves the middle 40 % × 45 %; after 0.6 s idle it eases back.
func _follow(dt: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	var sp := cam.unproject_position(player.global_position)
	var box := Rect2(vp * Vector2(0.3, 0.275), vp * Vector2(0.4, 0.45))
	var d := sp - sp.clamp(box.position, box.end)
	var ppm := vp.x / cam.size
	var right := cam.global_basis.x
	right.y = 0
	right = right.normalized()
	var fwd := -cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	if d != Vector2.ZERO:
		_focus += right * (d.x / ppm) - fwd * (d.y / ppm / sin(deg_to_rad(PITCH)))
	elif _idle_s > 0.6:
		_focus = _focus.lerp(player.position, clampf(dt * 2.5, 0, 1))
	_place_camera()

func _play(anim: String) -> void:
	if rig == null or anim == _anim: return
	_anim = anim
	rig.play_motion(anim)

# ---------------------------------------------------------------- plots
func _sync_plots(v: Dictionary) -> void:
	for p in v.get("plots", []):
		var id := int(p.get("id", -1))
		if not _plots.has(id): continue
		var node: Dictionary = _plots[id]
		var st := str(p.get("state", ""))
		var cid := str(p.get("crop", "")) if p.get("crop", null) != null else ""
		var stage := st
		if st == "growing":
			var c := P0Logic.crop(v, cid)
			var total := float(c.get("grow_h", 4)) * 3600000.0
			stage = "grow%d" % clampi(int((1.0 - float(p.get("ready_in", total)) / total) * 3.0), 0, 2)
		if node.state == stage and node.crop_id == cid: continue
		node.state = stage
		node.crop_id = cid
		var soil: Color = {"wild": Color("8dbe5e"), "tilled": Color("9a7350"), "sown": Color("8a6544")}.get(st, Color("6e5038"))
		(node.base as MeshInstance3D).material_override = _mat(soil)
		for ch in (node.crop as Node3D).get_children(): ch.queue_free()
		_draw_crop(node.crop, st, stage, cid)

func _draw_crop(parent: Node3D, st: String, stage: String, cid: String) -> void:
	var leaf := Color("6fbf5e")
	match st:
		"wild":
			for i in 3: _sphere(parent, Vector3(-0.3 + i * 0.3, 0.06, -0.2 + (i % 2) * 0.35), 0.09, Color("7fb25e"))
		"tilled":
			for i in 3: _box(Vector3(0.9, 0.03, 0.08), Vector3(0, 0.0, -0.3 + i * 0.3), Color("86603f"), parent)
		"sown":
			for i in 4: _sphere(parent, Vector3(-0.25 + (i % 2) * 0.5, 0.03, -0.25 + (i / 2) * 0.5), 0.05, Color("d9c7a6"))
		"growing":
			var s: float = {"grow0": 0.12, "grow1": 0.2, "grow2": 0.28}.get(stage, 0.15)
			_sphere(parent, Vector3(0, s * 0.8, 0), s, leaf)
		"ready":
			_sphere(parent, Vector3(0, 0.22, 0), 0.24, leaf)
			_sphere(parent, Vector3(0.12, 0.4, 0.1), 0.17, CROP_COLORS.get(cid, Color("e8607a")))

func _sphere(parent: Node3D, pos: Vector3, r: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.position = pos
	mi.material_override = _mat(color)
	parent.add_child(mi)

func _pick_front(v: Dictionary) -> void:
	var probe := player.position + _facing * 0.7
	var best := -1
	var best_d := 0.75
	for id in _plots:
		var pos: Vector3 = _plots[id].pos
		var d := Vector2(probe.x - pos.x, probe.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = id
	_front = {}
	if best >= 0:
		for p in v.get("plots", []):
			if int(p.get("id", -1)) == best: _front = p
	_hi.visible = not _front.is_empty()
	if _hi.visible: _hi.position = (_plots[best].pos as Vector3) + Vector3(0, 0.13, 0)

# ---------------------------------------------------------------- input
func _on_action(cmd: Dictionary) -> void:
	if str(cmd.get("type", "")) == "energy_card":
		var a := P0Logic.fish_action(session.current(), ui.selected_bait, _site) if _mode == "fish" else P0Logic.main_action(session.current(), _front, _seed)
		ui.open_energy_card(int(a.get("need", 0)), "Cast" if _mode == "fish" else str(a.get("verb", "Sow ×1")))
		return
	if cmd.is_empty(): return
	if str(cmd.type) == "cast":
		if _fishing != null: return
		_face_pond()
		session.send(cmd)
		return
	_play(AnimPlaceholders.clip_for(str(cmd.type)) if str(cmd.type) in ["sow", "water", "harvest", "till"] else "idle")
	_hold_last = cmd
	session.send(cmd)

## Facilities respond to taps only (§10.2.2): Bao (greeting first, p(4)), the bench (Rest), the stove (Cook).
func _on_tap(screen: Vector2) -> void:
	if ui.has_modal() or _fishing != null or _cooking != null: return
	if cam.unproject_position(BAO + Vector3(0, 1.0, 0)).distance_to(screen) < 60 or cam.unproject_position(STALL + Vector3(0, 0.8, 0)).distance_to(screen) < 60:
		ui.open_greeting()
	elif cam.unproject_position(BENCH + Vector3(0, 0.5, 0)).distance_to(screen) < 50:
		ui.open_rest_card()
	elif cam.unproject_position(STOVE + Vector3(0, 0.8, 0)).distance_to(screen) < 60:
		_open_stove()
	elif cam.unproject_position(KAI + Vector3(0, 1.0, 0)).distance_to(screen) < 60 or cam.unproject_position(TACKLE + Vector3(0, 0.8, 0)).distance_to(screen) < 60:
		ui.open_kai_greeting()

## The stove: empty → Cookbook / Experiment; cooking → back to the pot; ready → collect (no taps = Plain).
func _open_stove() -> void:
	var st = session.current().get("cooking", {}).get("stove", null)
	if st == null:
		ui.open_kitchen()
	elif float(st.get("ready_in", 0)) <= 0.0:
		session.send({"type": "collect", "taps": []})
	else:
		_watch_pot(st)

func _watch_pot(st: Dictionary) -> void:
	if _cooking != null: return
	var v := session.current()
	var dish = st.get("dish", null)
	var heats: Array = st.get("heats", [])
	var teach := not heats.is_empty() and float(heats[0].get("width", 0)) >= 0.5   # the first fire's wide arc (§7.2.4)
	_cooking = P0Cooking.new(ui, st, P0Logic.item_name(v, str(dish)) if dish != null else "Unknown dish", teach)
	_cooking.finished.connect(func(taps: Array):
		_cooking = null
		session.send({"type": "collect", "taps": taps}))
	_cooking.left.connect(func():
		_cooking = null
		ui.toast("The pot keeps cooking · tap the stove to collect"))
	ui.root.add_child(_cooking)

## Energy Card tiles only guide (§3.7.2): pan the camera to the spot and pulse a ring there; the player stays put.
func _show_spot(where: String) -> void:
	var at: Vector3 = {"stove": STOVE, "bench": BENCH}.get(where, player.position)
	_focus = at
	_idle_s = -2.5   # hold the view on the spot before easing back to the player
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.05
	ring.mesh = tm
	ring.position = at + Vector3(0, 0.08, 0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("e3b341")
	ring.material_override = m
	add_child(ring)
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3(1.25, 1, 1.25), 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ring, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_SINE)
	tw.set_loops(2)
	tw.finished.connect(ring.queue_free)

func _face_pond() -> void:
	if _site == "river":
		_facing = Vector3(0, 0, 1)
		player.look_at(player.position + _facing, Vector3.UP)
		_bob_target = Vector3(player.position.x, 0.12, CREEK_Z)
		return
	var to := POND - player.position
	to.y = 0
	_facing = to.normalized()
	player.look_at(player.position + _facing, Vector3.UP)
	# bobber lands ~1 m inside the water along the facing direction
	var p := player.position
	for i in 80:
		p += _facing * 0.1
		if _pond_d(p, -0.7) < 1.0: break
	_bob_target = Vector3(p.x, 0.12, p.z)

func _start_fishing(ev: Dictionary) -> void:
	_fishing = P0Fishing.new(ui, ev, session.current())
	_fishing.reel.connect(func(outcome: String):
		_fishing = null
		session.send({"type": "reel", "outcome": outcome}))
	_fishing.phase_changed.connect(func(ph: String): _bob_phase = ph)
	ui.root.add_child(_fishing)
	_show_tackle(true)

func _show_tackle(on: bool) -> void:
	if _rod == null:
		_rod = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.015
		cm.bottom_radius = 0.03
		cm.height = 2.0
		_rod.mesh = cm
		_rod.material_override = _mat(Color("8a6544"))
		add_child(_rod)
		_bobber = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		_bobber.mesh = sm
		_bobber.material_override = _mat(Color("e8607a"))
		add_child(_bobber)
		_line = MeshInstance3D.new()
		_line.mesh = ImmediateMesh.new()
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1, 1, 1, 0.9)
		_line.material_override = lm
		add_child(_line)
	_rod.visible = on
	_bobber.visible = on
	_line.visible = on
	if not on: _bob_phase = ""

func _animate_bobber(_dt: float) -> void:
	if _rod == null or not _rod.visible: return
	var hand := player.position + _facing * 0.35 + Vector3(0, 1.0, 0)
	var tip := hand + _facing * 1.3 + Vector3(0, 0.9, 0)
	_rod.position = (hand + tip) * 0.5
	_rod.look_at(tip, Vector3.UP if absf((tip - hand).normalized().dot(Vector3.UP)) < 0.99 else Vector3.FORWARD)
	_rod.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var t := Time.get_ticks_msec() / 1000.0
	var dip := 0.0
	match _bob_phase:
		"wait": dip = sin(t * 3.0) * 0.02
		"bite": dip = -0.08 + sin(t * 18.0) * 0.04
		"reel": dip = sin(t * 9.0) * 0.05
	_bobber.position = _bob_target + Vector3(0, dip, 0)
	var im := _line.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(tip)
	im.surface_add_vertex(_bobber.position)
	im.surface_end()

func _update_tags(v: Dictionary) -> void:
	var busy := _fishing != null or _cooking != null
	var near_bao := player.position.distance_to(STALL) < 4.5 and not busy
	var board_note := ""
	for r in v.get("stall", {}).get("board", {}).get("requests", []):
		if str(r.status) == "open" or (str(r.status) == "accepted" and int(r.have) >= int(r.qty)): board_note = " · !"
	ui.tag("bao", "Bao · Tap to talk" + board_note, cam.unproject_position(BAO + Vector3(0, 2.3, 0)), near_bao or (board_note != "" and not busy), true)
	var r: Dictionary = v.get("rest", {})
	var used := int(r.get("used", 0)) >= int(r.get("limit", 1))
	ui.tag("bench", "Rest · used today" if used else "Rest · +60 Energy · once a day", cam.unproject_position(BENCH + Vector3(0, 1.1, 0)), player.position.distance_to(BENCH) < 3.5 and not busy)
	var st = v.get("cooking", {}).get("stove", null)
	var stove_text := "Stove · Tap to cook"
	if st != null:
		stove_text = "Stove · Ready · Tap to collect" if float(st.get("ready_in", 0)) <= 0.0 else "Stove · Cooking " + P0Logic.duration(float(st.get("ready_in", 0)))
	ui.tag("kai", "Old Kai · Tap to talk", cam.unproject_position(KAI + Vector3(0, 2.3, 0)), player.position.distance_to(TACKLE) < 4.0 and not busy, true)
	ui.tag("stove", stove_text, cam.unproject_position(STOVE + Vector3(0, 2.1, 0)), (player.position.distance_to(STOVE) < 4.0 or st != null) and not busy, st != null)

# ---------------------------------------------------------------- server results
func _on_state(v: Dictionary, events: Array) -> void:
	ui.set_view(v)   # cards built below read the fresh view (Fish-dex, creel, meals)
	var at := cam.unproject_position(player.position + Vector3(0, 2.0, 0))
	if not _front.is_empty() and _plots.has(int(_front.get("id", -1))):
		at = cam.unproject_position((_plots[int(_front.id)].pos as Vector3) + Vector3(0, 0.6, 0))
	var dy := 0.0
	var xp_lines: Array = []
	for i in events.size():
		var ev: Dictionary = events[i]
		match str(ev.get("kind", "")):
			"xp":
				# The server emits a first-time bonus as `first` immediately followed by its `xp`.
				var bonus: bool = i > 0 and str(events[i - 1].get("kind", "")) == "first" and int(events[i - 1].xp) == int(ev.amount)
				if int(ev.amount) > 0 and not bonus:
					xp_lines.append("+%d %s XP" % [int(ev.amount), str(ev.skill).capitalize()] + ("" if int(ev.percent) >= 100 else " · %d%%" % int(ev.percent)))
			"reward":
				if int(ev.energy) > 0: xp_lines.append(P0Logic.reward_line(str(ev.id), int(ev.energy)))
			"first":
				var what := str(ev.what)
				if what.begins_with("catch:"): xp_lines.append("First catch! +%d XP" % int(ev.xp))
				elif what.begins_with("cook:"): xp_lines.append("New recipe! · First cooked · +%d Cooking XP" % int(ev.xp))
				elif what == "landed": xp_lines.append("First fish landed · +%d XP" % int(ev.xp))
	for ev in events:
		match str(ev.get("kind", "")):
			"energy":
				var dlt := int(ev.delta)
				if str(ev.reason) != "cast":
					ui.float_text(("%+d Energy" % dlt), at + Vector2(0, dy), Color("d9772f") if dlt < 0 else Color("4f934b"))
				else:
					ui.float_text("−%d Energy" % -dlt, at + Vector2(0, dy), Color("d9772f"))
			"xp":
				if int(ev.amount) > 0:
					ui.float_text("+%d XP" % int(ev.amount) + ("" if int(ev.percent) >= 100 else " · %d%%" % int(ev.percent)), at + Vector2(0, dy), Color("1e9bb0"))
			"item":
				var iid := str(ev.id)
				if int(ev.delta) > 0 and not iid.begins_with("seed_") and not iid.begins_with("dish_") and not iid.begins_with("fish_"):
					ui.float_text("+%d %s" % [int(ev.delta), P0Logic.item_name(v, iid)], at + Vector2(0, dy), Color("4f934b"))
			"coins":
				ui.float_text("%+d coins" % int(ev.delta), at + Vector2(0, dy), Color("c9962a"))
			"cast":
				_start_fishing(ev)
			"catch":
				_on_catch(ev, xp_lines)
			"pot":
				var st = v.get("cooking", {}).get("stove", null)
				if st is Dictionary: _watch_pot(st)
			"dish":
				var lines := xp_lines.duplicate()
				ui.queue_card(func(): ui.show_dish(ev, lines))
			"request":
				if str(ev.status) == "accepted": ui.toast("Tracking · it shows in Today")
				else: ui.toast("Request complete · +%d coins" % int(ev.coins))
			"meal":
				ui.teach("meal", "Energy comes back over time. A meal brings it back now.")
				if int(ev.gain) <= 0:
					ui.toast("Full belly · Meals reset in " + P0Logic.duration(float(v.get("meals", {}).get("resets_in", 0))) if int(ev.counted) <= 0 and int(ev.nominal) > 0 else "Same dish · no Energy today")
				else:
					ui.toast("+%d Energy · Meals today %d/%d" % [int(ev.gain), int(ev.meals), int(ev.cap)])
			"level":
				var lv: Dictionary = ev
				ui.queue_card(func(): ui.show_level_up(lv))
		dy -= 16.0
	if ui.modal_kind == "stall" and events.size() > 0:
		ui.set_view(session.current())
		ui.open_stall(_stall_bubble(events))
	elif ui.modal_kind == "tackle" and events.size() > 0:
		ui.open_tackle("Strung and ready — it's on your belt. Swap rods in Tools & Gear.")
	elif ui.modal_kind == "gear" and events.size() == 0:
		ui.open_gear()

func _on_catch(ev: Dictionary, xp_lines: Array) -> void:
	_show_tackle(false)
	match str(ev.result):
		"landed":
			var fid := str(ev.fish)
			var r := int(ev.rarity)
			var lines := xp_lines.duplicate()
			ui.queue_card(func(): ui.show_catch(fid, r, lines))
		"broke_free":
			var gone: Dictionary = ev
			ui.queue_card(func(): ui.show_got_away(gone))
		"escaped":
			var tail := ""
			if ev.has("protected_left"): tail = " · protection %d left today" % int(ev.protected_left)
			ui.toast("It got away · %d Energy back%s" % [int(ev.refund), tail], 3.0)
		"cancelled":
			ui.toast("Line in · Energy back")

func _is_stall_open() -> bool:
	return ui.modal_kind == "stall"

func _stall_bubble(events: Array) -> String:
	for ev in events:
		if str(ev.get("kind", "")) == "coins" and int(ev.delta) > 0: return "Thanks! %d coins for those." % int(ev.delta)
		if str(ev.get("kind", "")) == "item" and int(ev.delta) > 0:
			var id := str(ev.id)
			return "%d %s — %s" % [int(ev.delta), P0Logic.item_name(session.view, id), "good luck at the pond." if id.begins_with("bait_") else "happy sowing."]
	return ""

func _on_refused(code: String, detail: Dictionary, cmd: Dictionary) -> void:
	if code == "bag_full" and str(cmd.get("type", "")) == "reel":
		_show_tackle(false)
		session.send({"type": "reel", "outcome": "escaped"})
		ui.toast("Creel full · the fish slipped away")
		return
	match code:
		"need_energy":
			ui.open_energy_card(int(detail.get("need", 0)), "Cast" if str(cmd.get("type", "")) == "cast" else "Sow ×1")
		"locked":
			ui.toast("%s Lv%d · %d XP to go" % [str(detail.get("skill", "farming")).capitalize(), int(detail.get("level", 2)), int(detail.get("xp_to_go", 0))])
		"no_coins":
			ui.toast("Need %d more coins" % int(detail.get("need", 0)))
		"bag_full":
			ui.toast("Bag full · free a slot first")
		"rest_used":
			ui.toast("Rest used today")
		"energy_full":
			ui.toast("Energy full · eat later" if str(cmd.get("type", "")) == "eat" else "Energy full")
		"not_ready":
			ui.toast("Not ready yet")
		"creel_full":
			ui.toast("Creel full · 0 free slots · Sell or cook first")
		"already_casting":
			ui.toast("Your line is already in the water")
		"no_bait":
			ui.toast("No bait left")
		"too_early", "no_cast":
			_show_tackle(false)
		"stove_busy":
			ui.toast("The stove is busy · %s left" % P0Logic.duration(float(detail.get("ready_in", 0))))
		"needs_main":
			ui.toast("Needs a main ingredient")
		"not_for_cooking":
			ui.toast("Not for cooking")
		"missing_ingredients", "not_enough":
			ui.toast("Missing ingredients")
		"sold_out":
			ui.toast("Sold out today · %d left" % int(detail.get("left", 0)))
		_:
			ui.toast("Can't do that (%s)" % code)

# ---------------------------------------------------------------- dev: scripted desktop screenshots
## P0_SHOT=/abs/path.png [P0_SHOT_STEPS="walk:1.2,sow,..."] — run a few scripted inputs, save one frame, quit.
func _dev_shot(dt: float) -> void:
	var path := OS.get_environment("P0_SHOT")
	if path == "": return
	if _shot_t == 0.0: _shot_script = OS.get_environment("P0_SHOT_STEPS").split(",", false)
	_shot_t += dt
	if Time.get_ticks_msec() > int(OS.get_environment("P0_SHOT_LIMIT_MS") if OS.get_environment("P0_SHOT_LIMIT_MS") != "" else "25000"): get_tree().quit(2)
	if not _shot_script.is_empty() and _shot_t > 2.0:
		var step := str(_shot_script[0]).split(":")
		match step[0]:
			"walk":
				_joy = Vector2(float(step[1]), float(step[2])) if step.size() > 2 else Vector2(0.6, 0.2)
				if _shot_t > 2.0 + float(step[3] if step.size() > 3 else "1.0"):
					_joy = Vector2.ZERO
					_shot_script.pop_front()
					_shot_t = 2.0
				return
			"act":
				ui._fab_pressed()
			"hold":
				ui.fab_held = true
				ui._fab_pressed()
			"release":
				ui.fab_held = false
			"greet":
				ui.open_greeting()
			"stall":
				ui.open_stall("", step[1] if step.size() > 1 else "")
			"bag":
				ui.open_bag(step[1] if step.size() > 1 else "")
			"energy":
				ui.open_energy_card(3, "Sow ×1")
			"spot":
				_show_spot(step[1])
			"close":
				ui.close_modal()
			"goto":
				player.position = Vector3(float(step[1]), 0, float(step[2]))
				_focus = player.position
			"auto":
				P0Fishing.auto_play = true
				P0Cooking.auto_play = true
			"manual":
				P0Cooking.auto_play = false
			"dex":
				ui.open_fishdex()
			"kai":
				ui.open_kai_greeting()
			"tackle":
				ui.open_tackle()
			"gear":
				ui.open_gear()
			"skills":
				ui.open_skills()
			"radial":
				ui.open_radial()
			"kitchen":
				ui.open_kitchen(step[1] if step.size() > 1 else "cookbook")
			"stove":
				_open_stove()
			"put":
				ui._exp_slots.append(step[1])
				ui.open_kitchen("experiment")
			"cook":
				session.send({"type": "cook", "recipe": step[1]})
			"send":
				# send:type=reel|outcome=landed (commas separate steps, so no JSON here)
				var cmd := {}
				for pair in ":".join(step.slice(1)).split("|"):
					var kv := pair.split("=")
					cmd[kv[0]] = int(kv[1]) if kv[1].is_valid_int() else kv[1]
				session.send(cmd)
			"wait":
				if _shot_t < 2.0 + float(step[1]): return
			"until":
				# wait for a state: fishing / cooking / modal / idle
				var ready := false
				match step[1]:
					"bite": ready = _fishing != null and _fishing.phase == "bite"
					"reel": ready = _fishing != null and _fishing.phase == "reel"
					"cooking": ready = _cooking != null
					"modal": ready = ui.has_modal()
					"idle": ready = _fishing == null and _cooking == null
				if not ready and _shot_t < 40.0: return
			"skip":
				session.dev_skip(int(step[1]))
		_shot_script.pop_front()
		_shot_t = 1.2
		return
	if _shot_script.is_empty() and _shot_t > 1.55:
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		print("P0_SHOT saved ", path)
		get_tree().quit()
