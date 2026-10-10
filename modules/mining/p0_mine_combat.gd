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
## radius) and as wide as the hit; it sweeps from the feet to its far end over the wind-up and the slime leaps when
## it is full. Orange-red #E8603C, fill 30 % / edge 70 %; the elite's in full, a slime's paler. The direction is the
## one the wind-up locked (mine_combat sets enemy.direction once): the lunge follows the band, never re-aims.
const BAND_COLOR := Color("e8603c")
const BAND_FILL := 0.30
const BAND_EDGE := 0.70
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
	var best_d := REACH + 0.35
	for id in enemies:
		var d: float = at.distance_to(enemies[id].node.position)
		if d < best_d:
			best_d = d
			best = id
	return best


## One wind-up's band: a flat strip on the ground under the slime's root, out of Body's squash, hidden until a wind-up.
func _band(spec: Dictionary, elite: bool) -> Node3D:
	var band := Node3D.new()
	band.name = "Band"
	band.visible = false
	var reach := float(spec.dash_speed) * float(spec.dash_seconds) + float(spec.radius) + 0.35
	var width := (float(spec.radius) + 0.35) * 2.0
	var alpha := 1.0 if elite else BAND_PALE
	for part in [["Fill", BAND_FILL, width, 0.0], ["Edge", BAND_EDGE, width + 0.08, -0.004]]:
		var quad := PlaneMesh.new()
		quad.size = Vector2(part[2], 1.0)
		var mesh := MeshInstance3D.new()
		mesh.name = str(part[0])
		mesh.mesh = quad
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(BAND_COLOR, float(part[1]) * alpha)
		m.no_depth_test = false
		mesh.material_override = m
		mesh.position.y = BAND_Y + float(part[3])
		band.add_child(mesh)
	band.set_meta("reach", reach)
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
			band.visible = phase == "windup"
			if band.visible: _lay_band(band, e)
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

## The band from the slime's feet along the locked direction, swept out over the wind-up (full when it leaps).
func _lay_band(band: Node3D, e: Dictionary) -> void:
	var dir: Vector3 = e.get("band_dir", e.direction)
	if dir.length() < 0.01: dir = Vector3.FORWARD
	var total := float(e.spec.windup_seconds)
	var done := clampf(1.0 - float(e.timer) / maxf(0.01, total), 0.0, 1.0)
	var reach := float(band.get_meta("reach", 2.0))
	var length := maxf(0.05, reach * done)
	band.rotation = Vector3(0, atan2(dir.x, dir.z), 0)
	for part in band.get_children():
		var mesh := part as MeshInstance3D
		mesh.scale = Vector3(1, 1, length)
		mesh.position.z = length * 0.5

## The band's reach and width for a kind (tests, the 288 report).
func band_of(kind: String) -> Dictionary:
	var spec: Dictionary = _config.monsters[kind]
	return {"reach": float(spec.dash_speed) * float(spec.dash_seconds) + float(spec.radius) + 0.35,
		"width": (float(spec.radius) + 0.35) * 2.0, "windup": float(spec.windup_seconds)}
