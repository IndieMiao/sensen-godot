extends Node3D

signal contact(monster_id: String)

const Layout = preload("res://modules/mining/mine_layout.gd")
const Meshes = preload("res://modules/mining/mine_mesh.gd")
## Where a floor's monsters stand on arrival, one spot each (snapped to a free cell, _spawn_point), as many as a floor
## has monsters (5 at most, a vein's F21–39). Each within 4.6 m of Layout.SPAWN, under the slime's and the shroomling's
## 5 m aggro, 1.2 m or more apart and off the rocks: the third stood at (7.5, −5.5), 5.49 m off, and never came — the
## floor sat on `1 monster left` with the stairs shut while it waited at the screen's right edge (李元芳's preview A, P12);
## the second was 4.65 m; a fourth and fifth took the first two's spots, pushed further off (李白 on 399: data fixes, no
## q row).
const SPAWNS := [Vector3(4.75, 0, -5.0), Vector3(3.4, 0, -4.3), Vector3(6.3, 0, -4.9), Vector3(1.6, 0, -3.2), Vector3(7.8, 0, -3.3)]
## A chasing slime finds its path to the player again this often, and at most one slime a frame does it (perf Q6,
## SGODOT-260): an A* and its smoothing over the floor's blocked cells each, so slimes due together wait a frame or two
## instead of all landing in one frame (fights at floor 4 jerked about 4 times a second).
const REPATH_S := 0.25
## A slime's eyes, glints and cheeks (perf Q6, SGODOT-260): one mesh of 16 × 8 spheres in one vertex-colour material,
## instead of six default 64 × 32 spheres (about 24k triangles a slime) with a material each.
const FACE_SEGMENTS := Vector2i(16, 8)
static var _face_material: StandardMaterial3D
var enemies: Dictionary = {}
var _actors: Dictionary = {}
var cooldown := 0.0
var invulnerability := 0.0
var grace := 0.0
var _key := ""
var _elapsed := 0.0
var _swing: MeshInstance3D
var _swing_left := 0.0
var _numbers: Array = []
var _config: Dictionary = Layout.data().combat

func weapon(state: Dictionary) -> Dictionary:
	return CharacterModel.main_hand_stats(state)

func sync(state: Dictionary, player_mover: PlayerMover, farm_id: String) -> void:
	var mine: Dictionary = state.get("mine", {})
	var floor_number := int(mine.get("floor", 0))
	var key := "%s:%d:%d" % [farm_id, int(mine.get("run", 0)), floor_number]
	if key != _key:
		_key = key
		for enemy in _actors.values(): enemy.node.queue_free()
		enemies.clear()
		_actors.clear()
		grace = float(_config.entry_grace_seconds)
		# Keep local cooldowns on stairs; server timestamps also survive re-entry.
		var kinds: Array = _config.floors.get(str(floor_number), [])
		for index in kinds.size():
			var spec: Dictionary = _config.monsters[kinds[index]]
			var health := _health(mine, floor_number, index, int(spec.hp))
			if health <= 0: continue
			var point := _spawn_point(player_mover, SPAWNS[index])
			var movement := PlayerMover.new(player_mover.bp, player_mover.grid)
			movement.position = point
			movement.speed = float(spec.move_speed)
			var node := _slime(spec, kinds[index] == "elite_slime")
			add_child(node)
			node.position = point
			enemies["slime_%d" % (index + 1)] = {"node": node, "spec": spec, "mover": movement,
				"index": index, "hp": health, "phase": "idle", "timer": 0.0, "repath": 0.0,
				"direction": Vector3.FORWARD, "flash": 0.0, "did_hit": false}
			_actors["slime_%d" % (index + 1)] = enemies["slime_%d" % (index + 1)]
	for id in _actors:
		var enemy: Dictionary = _actors[id]
		var hp := _health(mine, floor_number, int(enemy.index), int(enemy.spec.hp))
		if hp < int(enemy.hp):
			_number(enemy.node.position + Vector3(0, 1, 0), str(int(enemy.hp) - hp), Color("fff3bd"))
			enemy.flash = 0.18
		if hp <= 0:
			# Retain the actor until leaving the floor so a rejected prediction can restore it.
			enemy.node.visible = false
			enemy.hp = 0
			enemies.erase(id)
			continue
		enemy.node.visible = true
		enemies[id] = enemy
		enemy.hp = hp
		enemy.mover.bp = player_mover.bp
		enemy.mover.grid = player_mover.grid
		var label := enemy.node.get_node("Health") as Label3D
		label.text = "%d / %d" % [hp, int(enemy.spec.hp)]
		enemy.node.get_node("HealthFill").scale.x = maxf(0.01, float(hp) / float(enemy.spec.hp))

func _health(mine: Dictionary, floor_number: int, index: int, maximum: int) -> int:
	var saved: Array = mine.get("combat", {}).get("monsters", {}).get(str(floor_number), [])
	if index < saved.size(): return int(saved[index])
	if mine.get("cleared_floors", []).any(func(value): return int(value) == floor_number): return 0
	return maximum

func _spawn_point(mover: PlayerMover, desired: Vector3) -> Vector3:
	var best := Layout.SPAWN
	var score := INF
	for y in mover.bp.grid.y:
		for x in mover.bp.grid.x:
			var cell := Vector2i(x, y)
			if not mover.bp.is_walkable(cell): continue
			var point := mover.bp.cell_to_world(cell)
			if point.distance_to(Layout.SPAWN) < 3.0: continue
			if enemies.values().any(func(enemy): return enemy.node.position.distance_to(point) < 1.2): continue
			if mover.grid.point_path(Layout.SPAWN, point).is_empty(): continue
			var distance := point.distance_squared_to(desired)
			if distance < score:
				score = distance
				best = point
	return best

static func within_swing(origin: Vector3, facing: Vector3, target: Vector3, reach: float, arc: float) -> bool:
	var offset := target - origin
	offset.y = 0
	return offset.length() <= reach and (offset.length() < 0.05 or facing.normalized().dot(offset.normalized()) >= cos(deg_to_rad(arc * 0.5)))

## The P0 mine overrides this (p0_mine_combat.gd swing: reach to the body's edge, SGODOT-288): keep the two in step.
func swing(state: Dictionary, mover: PlayerMover, target_id := "") -> Array[String]:
	var hit: Array[String] = []
	var spec := weapon(state)
	if cooldown > 0 or spec.is_empty(): return hit
	var target: Dictionary = enemies.get(target_id, {})
	if target.is_empty():
		var nearest := float(spec.range) + 0.35
		for enemy in enemies.values():
			var distance := mover.position.distance_to(enemy.node.position)
			if distance < nearest:
				nearest = distance
				target = enemy
	if not target.is_empty(): mover.facing = (target.node.position - mover.position).normalized()
	cooldown = 1.0 / float(spec.speed)
	_show_swing(mover.position, mover.facing, float(spec.range))
	for id in enemies:
		var enemy: Dictionary = enemies[id]
		if not within_swing(mover.position, mover.facing, enemy.node.position, float(spec.range), float(_config.attack_arc_degrees)): continue
		if not mover.grid.segment_walkable(mover.position, enemy.node.position): continue
		hit.append(id)
		if not enemy.spec.stun_resistant:
			enemy.phase = "stunned"
			enemy.timer = float(_config.hit_stun_seconds)
			enemy.mover.stop()
		enemy.flash = 0.18
		var direction: Vector3 = (enemy.node.position - mover.position).normalized()
		_slide(enemy.mover, direction * float(spec.knockback) * (1.0 - float(enemy.spec.knockback_resistance)))
		enemy.node.position = enemy.mover.position
	return hit

func step(delta: float, mover: PlayerMover, paused: bool) -> void:
	if paused: return
	var dt := clampf(delta, 0, 0.1)
	_elapsed += dt
	cooldown = maxf(0, cooldown - dt)
	invulnerability = maxf(0, invulnerability - dt)
	grace = maxf(0, grace - dt)
	fade(dt)
	if grace > 0: return
	var pathed := false   # a slime has found its path this frame
	for id in enemies:
		var enemy: Dictionary = enemies[id]
		var spec: Dictionary = enemy.spec
		var movement: PlayerMover = enemy.mover
		var distance := movement.position.distance_to(mover.position)
		enemy.timer = maxf(0, float(enemy.timer) - dt)
		enemy.flash = maxf(0, float(enemy.flash) - dt)
		match str(enemy.phase):
			"idle", "chase":
				if distance <= float(spec.attack_range) and movement.grid.segment_walkable(movement.position, mover.position):
					enemy.phase = "windup"
					enemy.timer = float(spec.windup_seconds)
					enemy.direction = (mover.position - movement.position).normalized()
					enemy.did_hit = false
					movement.stop()
				elif distance <= float(spec.aggro_range):
					enemy.phase = "chase"
					enemy.repath -= dt
					if enemy.repath <= 0 and not pathed:
						pathed = true
						enemy.repath = REPATH_S
						movement.set_target_position(mover.position)
					movement.step(dt)
				else:
					enemy.phase = "idle"
					movement.stop()
			"windup":
				if enemy.timer <= 0:
					enemy.phase = "dash"
					enemy.timer = float(spec.dash_seconds)
			"dash":
				_slide(movement, _dash_step(enemy, mover, enemy.direction * float(spec.dash_speed) * dt))
				if not enemy.did_hit and invulnerability <= 0 and movement.position.distance_to(mover.position) <= float(spec.radius) + 0.35 and movement.grid.segment_walkable(movement.position, mover.position):
					enemy.did_hit = true
					invulnerability = float(_config.invulnerability_ms) / 1000.0
					contact.emit(id)
				if enemy.timer <= 0:
					enemy.phase = "recover"
					enemy.timer = float(spec.recovery_seconds)
			"recover", "stunned":
				if enemy.timer <= 0: enemy.phase = "chase"
		enemy.node.position = movement.position
		var body := enemy.node.get_node("Body") as MeshInstance3D
		var material := body.material_override as StandardMaterial3D
		material.albedo_color = Color("fff3bd") if enemy.flash > 0 else (Color("f38870") if enemy.phase == "windup" else enemy.node.get_meta("color"))
		body.scale = Vector3(1.12, 0.7, 1.12) if enemy.phase == "windup" else Vector3(1, 1 + sin(_elapsed * 7) * 0.04, 1)
		enemy.node.get_node("Warning").visible = enemy.phase == "windup"

## One frame of a lunge along its locked direction; the legacy mine lets it run its whole length (P0MineCombat stops it
## at the player's body).
func _dash_step(_enemy: Dictionary, _player: PlayerMover, offset: Vector3) -> Vector3:
	return offset

func _slide(mover: PlayerMover, offset: Vector3) -> void:
	# Small collision steps keep knockback and lunges from crossing narrow rocks.
	var count := maxi(1, ceili(offset.length() / 0.1))
	for index in count:
		var next := mover.position + offset / count
		if not mover.grid.segment_walkable(mover.position, next): break
		mover.position = next

func hurt(mover: PlayerMover, monster_id: String, damage: int) -> void:
	_number(mover.position + Vector3(0, 1.5, 0), "-" + str(damage), Color("ff9584"))
	invulnerability = float(_config.invulnerability_ms) / 1000.0
	if enemies.has(monster_id):
		mover.stop()
		_slide(mover, (mover.position - enemies[monster_id].node.position).normalized() * 0.5)

## The swing's flash and the floating numbers run out, nothing else: what a held fight still shows (a run that has just
## completed keeps its last numbers rising while the banner is up, P0 mine).
func fade(delta: float) -> void:
	var dt := clampf(delta, 0, 0.1)
	_swing_left = maxf(0, _swing_left - dt)
	if is_instance_valid(_swing): _swing.visible = _swing_left > 0
	for number in _numbers.duplicate():
		number.left -= dt
		number.label.position.y += dt * 0.5
		if number.left <= 0:
			number.label.queue_free()
			_numbers.erase(number)

func _number(point: Vector3, text: String, color: Color) -> void:
	var label := _label(text, 42)
	label.modulate = color
	label.position = point
	add_child(label)
	_numbers.append({"label": label, "left": 0.7})

func _label(text: String, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = GameUi.theme().default_font
	label.font_size = font_size
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 8
	label.modulate = Color("f3fff4")
	return label

func _mesh(shape: Mesh, color: Color, point: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = shape
	mesh.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.3
	mesh.material_override = material
	return mesh

func _slime(spec: Dictionary, elite: bool) -> Node3D:
	var root := Node3D.new()
	var color := Color("79cdb6") if not elite else Color("ad7cda")
	root.set_meta("color", color)
	var radius := float(spec.radius)
	var body := _mesh(_slime_body(radius), color, Vector3.ZERO)
	body.name = "Body"
	var jelly := body.material_override as StandardMaterial3D
	jelly.roughness = 0.29
	jelly.rim_enabled = true
	jelly.rim = 0.28
	jelly.rim_tint = 0.65
	root.add_child(body)
	BlobShadow.attach(root,radius*1.15)
	var face := Meshes.surface()
	for side in [-1, 1]:
		_face_sphere(face, radius * 0.09, radius * 0.27, Color("333345"), Vector3(side * radius * 0.30, radius * 0.69, radius * 0.92))   # eye
		_face_sphere(face, radius * 0.026, radius * 0.058, Color("fff9e7"), Vector3(side * radius * 0.30 - radius * 0.02, radius * 0.76, radius * 1.002))   # glint
		_face_sphere(face, radius * 0.10, radius * 0.10, Color("e5a7ca") if elite else Color("b8e1cb"),
			Vector3(side * radius * 0.51, radius * 0.53, radius * 0.89), Vector3(1, 1, 0.36))   # cheek, flattened as before
	face.index()
	var face_mesh := MeshInstance3D.new()
	face_mesh.name = "Face"
	face_mesh.mesh = face.commit()
	face_mesh.material_override = _face_jelly()
	body.add_child(face_mesh)
	var smile := Meshes.surface()
	Meshes.ribbon(smile,[Vector3(-0.09,0.61,0.986)*radius,Vector3(0,0.57,1.015)*radius,Vector3(0.09,0.61,0.986)*radius],radius*0.033,Color("494056"),Vector3.FORWARD)
	body.add_child(Meshes.finish(smile,"Smile"))
	if elite:
		var crown := Meshes.surface()
		var base := Vector3(0,radius*1.42,0)
		Meshes.ring(crown,base,radius*0.24,radius*0.035,Color("e9b34e"))
		for i in 5:
			var a := TAU*i/5
			var b := TAU*(i+1)/5
			var p := Vector3(cos(a)*radius*0.24,0,sin(a)*radius*0.24)
			var q := Vector3(cos(b)*radius*0.24,0,sin(b)*radius*0.24)
			var tip := p + Vector3.UP*radius*0.23
			Meshes.tri(crown,base+p,base+q,base+tip,Color("f1c05b"))
			Meshes.tri(crown,base+p,base+tip,base+q,Color("c9913d"))
			Meshes.oval(crown,base+tip,Vector3.ONE*radius*0.09,Color("ffe09a"))
		body.add_child(Meshes.finish(crown,"Crown","metal"))
	var warning := TorusMesh.new()
	warning.inner_radius = radius + 0.04
	warning.outer_radius = radius + 0.16
	var ring := _mesh(warning, Color("f66458"), Vector3(0, 0.035, 0))
	ring.scale.y = 0.15
	ring.name = "Warning"
	ring.visible = false
	root.add_child(ring)
	var label := _label("", 36)
	label.pixel_size = 0.012
	label.position.y = radius * 2.2 + 0.35
	label.name = "Health"
	root.add_child(label)
	for is_fill in [false, true]:
		var bar := BoxMesh.new()
		bar.size = Vector3(0.94, 0.06, 0.045)
		var health := _mesh(bar, Color("dd7384") if is_fill else Color("334e4a"), Vector3(0, radius * 2.2 + 0.06, 0.05 if is_fill else 0))
		health.name = "HealthFill" if is_fill else "HealthTrack"
		root.add_child(health)
	_no_cast(root)
	return root

## One sphere of the face as the SphereMesh it was (that radius and height), at 16 × 8 segments, scaled, in its colour.
func _face_sphere(s: SurfaceTool, sphere_radius: float, height: float, color: Color, point: Vector3, scale := Vector3.ONE) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = sphere_radius
	sphere.height = height
	sphere.radial_segments = FACE_SEGMENTS.x
	sphere.rings = FACE_SEGMENTS.y
	PlaceScenery._append(s, sphere, Transform3D(Basis.from_scale(scale), point), color)

## The face's material, shared by every slime: the parts' own look (roughness 0.3), its colour from the vertices.
static func _face_jelly() -> StandardMaterial3D:
	if _face_material == null:
		_face_material = StandardMaterial3D.new()
		_face_material.vertex_color_use_as_albedo = true
		_face_material.vertex_color_is_srgb = true
		_face_material.roughness = 0.3
	return _face_material

## A slime casts no real shadow (perf Q6): its blob shadow is the one on the ground, so the shadow pass skips it.
static func _no_cast(root: Node) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _slime_body(radius: float) -> ArrayMesh:
	var surface := Meshes.surface()
	var profile := [Vector2(0.78,0.025),Vector2(0.98,0.10),Vector2(1.0,0.32),Vector2(0.94,0.60),
		Vector2(0.83,0.88),Vector2(0.65,1.12),Vector2(0.40,1.33),Vector2(0.04,1.43)]
	for tier in range(profile.size()-1):
		for i in 32:
			var a := TAU*i/32
			var b := TAU*(i+1)/32
			var p: Vector2 = profile[tier]*radius
			var q: Vector2 = profile[tier+1]*radius
			Meshes.quad(surface,Vector3(cos(a)*p.x,p.y,sin(a)*p.x),Vector3(cos(b)*p.x,p.y,sin(b)*p.x),
				Vector3(cos(b)*q.x,q.y,sin(b)*q.x),Vector3(cos(a)*q.x,q.y,sin(a)*q.x),Color.WHITE)
	surface.generate_normals()
	surface.index()
	return surface.commit()

func _show_swing(origin: Vector3, facing: Vector3, reach: float) -> void:
	if is_instance_valid(_swing): _swing.queue_free()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center_angle := atan2(facing.x, facing.z)
	var half_arc := deg_to_rad(float(_config.attack_arc_degrees) * 0.5)
	for segment in 20:
		var a := center_angle - half_arc + 2 * half_arc * segment / 20
		var b := center_angle - half_arc + 2 * half_arc * (segment + 1) / 20
		var points := [Vector3(sin(a), 0, cos(a)), Vector3(sin(b), 0, cos(b))]
		for point in [points[0] * (reach - 0.12), points[0] * reach, points[1] * reach, points[0] * (reach - 0.12), points[1] * reach, points[1] * (reach - 0.12)]:
			surface.add_vertex(point)
	surface.generate_normals()
	_swing = _mesh(surface.commit(), Color("fff2b6"), origin + Vector3(0, 0.2, 0))
	(_swing.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	add_child(_swing)
	_swing_left = 0.16
