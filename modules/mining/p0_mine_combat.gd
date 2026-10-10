extends "res://modules/mining/mine_combat.gd"
## P0 mine floors 3–5 (SGODOT-288; §13.3.4, §13.3.8): the old mine's slimes as they were — their art, their chase,
## wind-up, leap and recovery, the swing arc and its flash — on P0's floor data. What a floor holds and how much HP
## each monster has left come from the server view (view.mine.run.floors[n].mobs); how they move comes from the old
## mining table (assets/farm/data/mining.json), as the client owns movement and the server settles hits, HP and loot
## (server/src/p0/mine.ts). A monster at 0 stays hidden until the floor is left, so a refused swing can't revive it.

## P0 monster kind → the old mining table's movement and look (slime / elite_slime).
const KINDS := {"mob_slime": "slime", "mob_elite_slime": "elite_slime"}
## The Combat slot's swing feel: P0 content gives attack and speed (the server's numbers); reach and knockback are the
## old shortsword's, as the mine has always felt (assets/farm/data/items.json rusty_sword).
const REACH := 1.65
const KNOCKBACK := 0.7
## The swing waits this much longer than the server's tempo (1 / speed), as the rock beat does (0.95 s for 0.9 s), so a
## little network jitter never has the server refuse a swing the client already showed (苏烈 on #223).
const TEMPO_MARGIN_S := 0.05
## On arriving at a floor the monsters hold still this long: the old mine's 1.5 s entry grace, a little longer since
## Express lands right by the elite (李元芳 R5 on SGODOT-288). With the key already on Attack, that is time to swing.
const LANDING_GRACE_S := 2.0

## The lunge band (不知火舞 288 785a6a5b, 上官婉儿 c8a7507a, 李白 on 288): from the wind-up's first frame a strip on the
## ground from the slime's feet along the locked lunge, as long as the lunge reaches (dash speed × time + the hit
## radius) and as wide as the hit, its far end round; it sweeps from the feet to its far end over the wind-up, the
## slime leaps when it is full, the band stays through the lunge and fades over 0.15 s after it (不知火舞 7d4f0231).
## Orange-red #E8603C at 30 %; the elite's in full, a slime's paler (the 70 % edge did not read on the ground and is
## gone). The direction is the one the wind-up locked (mine_combat sets enemy.direction once): the lunge follows the
## band, never re-aims.
const BAND_COLOR := Color("e8603c")
const BAND_FILL := 0.30
const BAND_FADE_S := 0.15
const BAND_PALE := 0.6       # a common slime's band, against the elite's
const BAND_Y := 0.03
## The wind-up squash on Body only (pivot at its feet, so they stay on the ground), a small shake of its position over
## the last 0.2 s, and a 0.08 s rebound as it leaps (上官婉儿 c8a7507a).
const SQUASH := Vector3(1.18, 0.78, 1.18)
const SHAKE_S := 0.2
const SHAKE_M := 0.03
const REBOUND_S := 0.08
const HAPTIC_MS := 20

var _weapon := {"damage": 3, "speed": 2.0, "range": REACH, "knockback": KNOCKBACK}

## The weapon from the view (mine.weapon {attack, speed}); damage feeds the floating number only.
func weapon(_state: Dictionary) -> Dictionary:
	return _weapon

## Build or refresh this floor's monsters from the view. `key` changes with the run and floor: a new floor clears the
## old monsters and spawns these at the old mine's spots.
func sync_p0(view: Dictionary, n: int, player_mover: PlayerMover) -> void:
	var mine: Dictionary = view.get("mine", {})
	var w: Dictionary = mine.get("weapon", {})
	var speed := 1.0 / (1.0 / maxf(0.1, float(w.get("speed", 2.0))) + TEMPO_MARGIN_S)
	_weapon = {"damage": int(w.get("attack", 3)), "speed": speed, "range": REACH, "knockback": KNOCKBACK}
	var run = mine.get("run", null)
	var floor := {}
	if run is Dictionary:
		for f in run.get("floors", []):
			if int(f.get("floor", 0)) == n: floor = f
	var mobs: Array = floor.get("mobs", [])
	var key := "%s:%d" % [str(run.get("id", "")) if run is Dictionary else "", n]
	if key != _key:
		_key = key
		for enemy in _actors.values(): enemy.node.queue_free()
		enemies.clear()
		_actors.clear()
		grace = LANDING_GRACE_S
		for i in mobs.size():
			var kind := str(KINDS.get(str(mobs[i].get("kind", "")), "slime"))
			var spec: Dictionary = _config.monsters[kind].duplicate()
			spec.hp = int(mobs[i].get("max", spec.hp))
			var hp := int(mobs[i].get("hp", spec.hp))
			if hp <= 0: continue
			var point := _spawn_point(player_mover, SPAWNS[i % SPAWNS.size()])
			var movement := PlayerMover.new(player_mover.bp, player_mover.grid)
			movement.position = point
			movement.speed = float(spec.move_speed)
			var node := _slime(spec, kind == "elite_slime")
			node.add_child(_band(spec, kind == "elite_slime"))
			add_child(node)
			node.position = point
			(node.get_node("Health") as Label3D).visible = false   # the bar only (EnemyHP Kind=Mob, COMBAT-1)
			for bar in ["HealthFill", "HealthTrack"]: (node.get_node(bar) as Node3D).visible = false   # after the first hit
			var id := mob_id(i)
			enemies[id] = {"node": node, "spec": spec, "mover": movement, "index": i, "hp": hp, "phase": "idle",
				"timer": 0.0, "repath": 0.0, "direction": Vector3.FORWARD, "flash": 0.0, "did_hit": false, "elite": kind == "elite_slime"}
			_actors[id] = enemies[id]
	for id in _actors:
		var enemy: Dictionary = _actors[id]
		var i := int(enemy.index)
		var hp := int(mobs[i].get("hp", 0)) if i < mobs.size() else 0
		if hp < int(enemy.hp):
			_number(enemy.node.position + Vector3(0, 1, 0), str(int(enemy.hp) - hp), Color("fff3bd"))
			enemy.flash = 0.18
			if not bool(enemy.elite):   # the Mob bar shows from the first hit on; the elite's is the HUD card
				for bar in ["HealthFill", "HealthTrack"]: (enemy.node.get_node(bar) as Node3D).visible = true
		enemy.hp = hp
		if hp <= 0:
			enemy.node.visible = false
			enemies.erase(id)
			continue
		enemy.node.visible = true
		enemies[id] = enemy
		enemy.mover.bp = player_mover.bp
		enemy.mover.grid = player_mover.grid
		enemy.node.get_node("HealthFill").scale.x = maxf(0.01, float(hp) / float(enemy.spec.hp))

## The id a monster index goes by in the old combat ("slime_1" …) and back.
static func mob_id(i: int) -> String: return "slime_%d" % (i + 1)
static func mob_index(id: String) -> int: return id.trim_prefix("slime_").to_int() - 1

## The elite still standing on this floor: {hp, max} for the HUD card (COMBAT-ELITE), {} when none.
func elite_hp() -> Dictionary:
	for e in enemies.values():
		if bool(e.get("elite", false)) and int(e.hp) > 0: return {"hp": int(e.hp), "max": int(e.spec.hp)}
	return {}

func any_alive() -> bool: return not enemies.is_empty()

## The nearest live monster within the swing's reach, for the key's state; "" when none.
func in_reach(at: Vector3) -> String:
	var best := ""
	var best_d := REACH + TURN_MARGIN
	for id in enemies:
		var d := edge_distance(at, enemies[id])
		if d < best_d:
			best_d = d
			best = id
	return best

## The swing measures to a monster's body, not its centre (不知火舞 on 288, 10-10: on Floor 5 the elite, 0.65 m round,
## waited 2.4–2.6 m centre to centre behind the player — its lunge's range — and looked pressed against them, yet the
## old centre test neither turned the player to it nor reached it; 7.7 s of Attack landed once, mid-lunge). The player
## turns to the nearest monster whose edge is within REACH + TURN_MARGIN and hits those whose edge is within REACH in the
## arc. A slime (0.4 m) gains as much as its size; the legacy mine's MineCombat keeps the centre test.
const TURN_MARGIN := 0.35   # the old mine's turn margin (mine_combat.swing), now from the body's edge
## A hit is where the drawn arc sweeps (不知火舞 on #275, B): the arc band is 0.12 m wide at REACH and a slime's dome
## stands over its ground circle, so a body whose edge is within REACH + HIT_SLACK is hit — the elite at its wind-up
## spot (edge 1.67–1.74 m) is, at its recovery spot (1.85 m) a step in is still needed.
const HIT_SLACK := 0.15

## A lunge stops where its body meets the player's (不知火舞 288 ce070cd7: the elite ran on through the player, who sank into
## it to the head): never closer than its radius + PLAYER_RADIUS centre to centre, a hair inside the dash's hit test
## (mine_combat: radius + 0.35) so the touch still lands. Already touching, it may move away but never further in; a lunge
## that passes the player by runs its length (the band shows that whole reach).
const PLAYER_RADIUS := 0.35
const CONTACT_INSIDE := 0.02

func _dash_step(enemy: Dictionary, player: PlayerMover, offset: Vector3) -> Vector3:
	var contact := float(enemy.spec.get("radius", 0.0)) + PLAYER_RADIUS - CONTACT_INSIDE
	var from: Vector3 = (enemy.mover as PlayerMover).position - player.position
	from.y = 0
	var flat := Vector3(offset.x, 0, offset.z)
	var a := flat.length_squared()
	if a < 1e-9: return offset
	var b := 2.0 * from.dot(flat)
	var c := from.length_squared() - contact * contact
	if c <= 0.0: return offset if b >= 0.0 else Vector3.ZERO
	var disc := b * b - 4.0 * a * c
	if disc < 0.0: return offset
	var t := (-b - sqrt(disc)) / (2.0 * a)   # where |from + t·flat| first reaches contact
	return offset * t if t >= 0.0 and t <= 1.0 else offset

## Flat distance from `at` to a monster's body edge (its spec radius), 0 inside it.
static func edge_distance(at: Vector3, enemy: Dictionary) -> float:
	var off: Vector3 = enemy.node.position - at
	off.y = 0
	return maxf(0.0, off.length() - float(enemy.spec.get("radius", 0.0)))

func swing(state: Dictionary, mover: PlayerMover, target_id := "") -> Array[String]:
	var hit: Array[String] = []
	var spec := weapon(state)
	if cooldown > 0 or spec.is_empty(): return hit
	var target: Dictionary = enemies.get(target_id, {})
	if target.is_empty():
		var nearest := float(spec.range) + TURN_MARGIN
		for enemy in enemies.values():
			var d := edge_distance(mover.position, enemy)
			if d < nearest:
				nearest = d
				target = enemy
	if not target.is_empty():
		var to: Vector3 = target.node.position - mover.position
		to.y = 0
		if to.length() > 0.01: mover.facing = to.normalized()
	cooldown = 1.0 / float(spec.speed)
	_show_swing(mover.position, mover.facing, float(spec.range))
	for id in enemies:
		var enemy: Dictionary = enemies[id]
		var reach := float(spec.range) + HIT_SLACK + float(enemy.spec.get("radius", 0.0))   # to the body's edge
		if not within_swing(mover.position, mover.facing, enemy.node.position, reach, float(_config.attack_arc_degrees)): continue
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


## One wind-up's band: a flat strip on the ground under the slime's root, out of Body's squash, hidden until a wind-up.
func _band(spec: Dictionary, elite: bool) -> Node3D:
	var band := Node3D.new()
	band.name = "Band"
	band.visible = false
	var reach := float(spec.dash_speed) * float(spec.dash_seconds) + float(spec.radius) + 0.35
	var width := (float(spec.radius) + 0.35) * 2.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(BAND_COLOR, BAND_FILL * (1.0 if elite else BAND_PALE))
	# The strip (unit length, scaled along z as it sweeps) and its round far end (a disc the strip's width, moved to
	# the tip), one material so the overlap reads as one shape
	var strip := MeshInstance3D.new()
	strip.name = "Strip"
	var quad := PlaneMesh.new()
	quad.size = Vector2(width, 1.0)
	strip.mesh = quad
	strip.material_override = m
	strip.position.y = BAND_Y
	band.add_child(strip)
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var disc := CylinderMesh.new()
	disc.top_radius = width * 0.5
	disc.bottom_radius = width * 0.5
	disc.height = 0.001
	disc.radial_segments = 24
	disc.rings = 1
	cap.mesh = disc
	cap.material_override = m
	cap.position.y = BAND_Y
	band.add_child(cap)
	band.set_meta("reach", reach)
	band.set_meta("width", width)
	band.set_meta("alpha", m.albedo_color.a)
	return band

## The base step, then the wind-up's look: the band sweeping out along the locked direction, Body squashed with a
## shake at the end, the rebound on the leap, and a short buzz when a wind-up starts.
func step(delta: float, mover: PlayerMover, paused: bool) -> void:
	var before := {}
	for id in enemies: before[id] = str(enemies[id].phase)
	super.step(delta, mover, paused)
	for id in enemies:
		var e: Dictionary = enemies[id]
		var node: Node3D = e.node
		var band := node.get_node_or_null("Band") as Node3D
		var body := node.get_node("Body") as Node3D
		var phase := str(e.phase)
		if phase == "windup" and before.get(id, "") != "windup":
			e["band_dir"] = Vector3(e.direction)
			if HAPTIC_MS > 0 and OS.has_feature("mobile"): Input.vibrate_handheld(HAPTIC_MS)
		if phase == "dash" and before.get(id, "") == "windup": e["rebound"] = REBOUND_S
		if band:
			# shown through the wind-up and the lunge, then fading out (不知火舞 7d4f0231)
			if phase in ["windup", "dash"]: e["band_fade"] = BAND_FADE_S
			else: e["band_fade"] = maxf(0.0, float(e.get("band_fade", 0.0)) - clampf(delta, 0, 0.1))
			var fade := 1.0 if phase in ["windup", "dash"] else float(e.band_fade) / BAND_FADE_S
			band.visible = fade > 0.0
			if band.visible: _lay_band(band, e, fade)
		node.get_node("Warning").visible = false   # the band says it now
		if phase == "windup":
			body.scale = SQUASH
			var left := float(e.timer)
			body.position = Vector3(sin(_elapsed * 70.0), 0, cos(_elapsed * 55.0)) * SHAKE_M if left <= SHAKE_S else Vector3.ZERO
		else:
			body.position = Vector3.ZERO
			var r := float(e.get("rebound", 0.0))
			if r > 0:
				e["rebound"] = maxf(0.0, r - clampf(delta, 0, 0.1))
				var k := r / REBOUND_S
				body.scale = Vector3(1.0 - 0.08 * k, 1.0 + 0.14 * k, 1.0 - 0.08 * k)

## The band from the slime's feet along the locked direction, swept out over the wind-up (full from the leap on), its
## round end at the tip, at `fade` of its opacity.
func _lay_band(band: Node3D, e: Dictionary, fade := 1.0) -> void:
	var dir: Vector3 = e.get("band_dir", e.direction)
	if dir.length() < 0.01: dir = Vector3.FORWARD
	var done := 1.0
	if str(e.phase) == "windup":
		done = clampf(1.0 - float(e.timer) / maxf(0.01, float(e.spec.windup_seconds)), 0.0, 1.0)
	var reach := float(band.get_meta("reach", 2.0))
	var half := float(band.get_meta("width", 1.0)) * 0.5
	var tip := maxf(0.05, reach * done)
	# the strip runs to where the round end's centre sits, so the disc rounds the tip exactly at the reach
	var strip_len := maxf(0.01, tip - half)
	band.rotation = Vector3(0, atan2(dir.x, dir.z), 0)
	# the band stays where the wind-up laid it while the slime lunges along it
	band.global_position = e.get("band_from", band.global_position) if str(e.phase) != "windup" else (band.get_parent() as Node3D).global_position
	if str(e.phase) == "windup": e["band_from"] = band.global_position
	var strip := band.get_node("Strip") as MeshInstance3D
	strip.scale = Vector3(1, 1, strip_len)
	strip.position.z = strip_len * 0.5
	strip.visible = tip > half
	var cap := band.get_node("Cap") as MeshInstance3D
	cap.position.z = maxf(0.0, tip - half)
	var cap_scale := minf(1.0, tip / maxf(0.01, half * 2.0)) if tip < half * 2.0 else 1.0
	cap.scale = Vector3(cap_scale, 1, cap_scale)
	var m := strip.material_override as StandardMaterial3D
	m.albedo_color.a = float(band.get_meta("alpha", BAND_FILL)) * fade

## The band's reach and width for a kind (tests, the 288 report).
func band_of(kind: String) -> Dictionary:
	var spec: Dictionary = _config.monsters[kind]
	return {"reach": float(spec.dash_speed) * float(spec.dash_seconds) + float(spec.radius) + 0.35,
		"width": (float(spec.radius) + 0.35) * 2.0, "windup": float(spec.windup_seconds)}
