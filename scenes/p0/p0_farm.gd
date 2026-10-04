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
	session.state_changed.connect(_on_state)
	session.refused.connect(_on_refused)
	session.connection_failed.connect(func(msg): ui.toast(msg + " · " + session.base_url, 4.0))

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
	_pick_front(v)
	ui.set_action(P0Logic.main_action(v, _front, _seed))
	_update_tags(v)

func _move(dt: float) -> void:
	var v := _joy
	if Input.is_key_pressed(KEY_W): v.y -= 1
	if Input.is_key_pressed(KEY_S): v.y += 1
	if Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_D): v.x += 1
	if v == Vector2.ZERO or ui.has_modal():
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

func _blocked(p: Vector3) -> bool:
	if not ISLAND.grow(-0.4).has_point(Vector2(p.x, p.z)): return true
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
		var a := P0Logic.main_action(session.current(), _front, _seed)
		ui.open_energy_card(int(a.get("need", 0)), str(a.get("verb", "Sow ×1")))
		return
	if cmd.is_empty(): return
	_play(AnimPlaceholders.clip_for(str(cmd.type)) if str(cmd.type) in ["sow", "water", "harvest", "till"] else "idle")
	session.send(cmd)

## Facilities respond to taps only (§10.2.2): Bao (greeting first, p(4)) and the bench (Rest).
func _on_tap(screen: Vector2) -> void:
	if ui.has_modal(): return
	if cam.unproject_position(BAO + Vector3(0, 1.0, 0)).distance_to(screen) < 60 or cam.unproject_position(STALL + Vector3(0, 0.8, 0)).distance_to(screen) < 60:
		ui.open_greeting()
	elif cam.unproject_position(BENCH + Vector3(0, 0.5, 0)).distance_to(screen) < 50:
		ui.open_rest_card()

func _update_tags(v: Dictionary) -> void:
	var near_bao := player.position.distance_to(STALL) < 4.5
	ui.tag("bao", "Bao · Tap to talk", cam.unproject_position(BAO + Vector3(0, 2.3, 0)), near_bao, true)
	var r: Dictionary = v.get("rest", {})
	var used := int(r.get("used", 0)) >= int(r.get("limit", 1))
	ui.tag("bench", "Rest · used today" if used else "Rest · +60 Energy · once a day", cam.unproject_position(BENCH + Vector3(0, 1.1, 0)), player.position.distance_to(BENCH) < 3.5)

# ---------------------------------------------------------------- server results
func _on_state(v: Dictionary, events: Array) -> void:
	var at := cam.unproject_position(player.position + Vector3(0, 2.0, 0))
	if not _front.is_empty() and _plots.has(int(_front.get("id", -1))):
		at = cam.unproject_position((_plots[int(_front.id)].pos as Vector3) + Vector3(0, 0.6, 0))
	var dy := 0.0
	for ev in events:
		match str(ev.get("kind", "")):
			"energy":
				var dlt := int(ev.delta)
				ui.float_text(("%+d Energy" % dlt), at + Vector2(0, dy), Color("d9772f") if dlt < 0 else Color("4f934b"))
			"xp":
				if int(ev.amount) > 0:
					ui.float_text("+%d XP" % int(ev.amount) + ("" if int(ev.percent) >= 100 else " · %d%%" % int(ev.percent)), at + Vector2(0, dy), Color("1e9bb0"))
			"item":
				if int(ev.delta) > 0 and not str(ev.id).begins_with("seed_"):
					ui.float_text("+%d %s" % [int(ev.delta), P0Logic.item_name(v, str(ev.id))], at + Vector2(0, dy), Color("4f934b"))
			"coins":
				ui.float_text("%+d coins" % int(ev.delta), at + Vector2(0, dy), Color("c9962a"))
			"level":
				ui.show_level_up(ev)
		dy -= 16.0
	if ui.has_modal() and events.size() > 0 and _is_stall_open():
		ui.set_view(session.current())
		ui.open_stall(_stall_bubble(events))

func _is_stall_open() -> bool:
	return ui._modal != null and ui._modal.get_child_count() > 1 and ui._modal.get_child(1) is PanelContainer and (ui._modal.get_child(1) as PanelContainer).offset_top <= -500

func _stall_bubble(events: Array) -> String:
	for ev in events:
		if str(ev.get("kind", "")) == "coins" and int(ev.delta) > 0: return "Thanks! %d coins for those." % int(ev.delta)
		if str(ev.get("kind", "")) == "item" and int(ev.delta) > 0: return "%d %s — happy sowing." % [int(ev.delta), P0Logic.item_name(session.view, str(ev.id))]
	return ""

func _on_refused(code: String, detail: Dictionary, cmd: Dictionary) -> void:
	match code:
		"need_energy":
			ui.open_energy_card(int(detail.get("need", 0)), "Sow ×1")
		"locked":
			ui.toast("Farming Lv%d · %d XP to go" % [int(detail.get("level", 2)), int(detail.get("xp_to_go", 0))])
		"no_coins":
			ui.toast("Need %d more coins" % int(detail.get("need", 0)))
		"bag_full":
			ui.toast("Bag full · free a slot first")
		"rest_used":
			ui.toast("Rest used today")
		"energy_full":
			ui.toast("Energy full")
		"not_ready":
			ui.toast("Not ready yet")
		_:
			ui.toast("Can't do that (%s)" % code)

# ---------------------------------------------------------------- dev: scripted desktop screenshots
## P0_SHOT=/abs/path.png [P0_SHOT_STEPS="walk:1.2,sow,..."] — run a few scripted inputs, save one frame, quit.
func _dev_shot(dt: float) -> void:
	var path := OS.get_environment("P0_SHOT")
	if path == "": return
	if _shot_t == 0.0: _shot_script = OS.get_environment("P0_SHOT_STEPS").split(",", false)
	_shot_t += dt
	if Time.get_ticks_msec() > 25000: get_tree().quit(2)
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
			"greet":
				ui.open_greeting()
			"stall":
				ui.open_stall()
			"bag":
				ui.open_bag()
			"energy":
				ui.open_energy_card(3, "Sow ×1")
			"close":
				ui.close_modal()
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
