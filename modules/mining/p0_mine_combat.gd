extends "res://modules/mining/mine_combat.gd"
## P0 mine floors' monsters (SGODOT-288; §13.3.4, §13.3.8; 355 b1): the old mine's slimes as they were — their art,
## their chase, wind-up, leap and recovery, the swing arc and its flash — on P0's floor data. What a floor holds and how
## much HP each monster has left come from the server view (view.mine.at.floor_state.mobs); how each kind looks and moves comes
## from modules/mining/monsters/ (355 b1, contract-efg §10: its json, a MonsterView and a MonsterBrain by kind,
## Monsters), as the client owns movement and the server settles hits, HP and loot (server/src/p0/mine.ts). A monster at
## 0 stays hidden until the floor is left, so a refused swing can't revive it.

const Monsters := preload("res://modules/mining/monsters/monsters.gd")
const SlimeView := preload("res://modules/mining/monsters/slime_view.gd")
## The old mining table's names for the two slimes (band_of's callers, the 288 report) → the kinds.
const LEGACY := {"slime": "mob_slime", "elite_slime": "mob_elite_slime"}
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

## The wind-up's band, squash, shake and rebound are the slime's look now (SlimeView); its squash, for the tests.
const SQUASH := SlimeView.SQUASH
## A short buzz when a monster starts a wind-up (phones only).
const HAPTIC_MS := 20

var _weapon := {"damage": 3, "speed": 2.0, "range": REACH, "knockback": KNOCKBACK}
## Where each monster of this floor fell (index → position): a drop the bag had no room for lies there (v4q(5) ⑫).
var fallen := {}
## Monsters down and still showing their `die` (id → {enemy, left}): out of the fight, their look played on until the
## json's die time runs out (contract-efg §10; 刘邦 on #627).
var dying := {}

## The weapon from the view (mine.weapon {attack, speed}); damage feeds the floating number only.
func weapon(_state: Dictionary) -> Dictionary:
	return _weapon

## Build or refresh this floor's monsters from the view. `key` changes with the mine, the floor and the day (a new day
## draws the floor again, contract-efg §5 ⑩): a new key clears the old monsters and spawns these at the old mine's spots.
func sync_p0(view: Dictionary, n: int, player_mover: PlayerMover) -> void:
	var mine: Dictionary = view.get("mine", {})
	var w: Dictionary = mine.get("weapon", {})
	var speed := 1.0 / (1.0 / maxf(0.1, float(w.get("speed", 2.0))) + TEMPO_MARGIN_S)
	_weapon = {"damage": int(w.get("attack", 3)), "speed": speed, "range": REACH, "knockback": KNOCKBACK}
	var at = mine.get("at", null)
	var floor: Dictionary = at.get("floor_state", {}) if at is Dictionary and int(at.get("floor", 0)) == n else {}
	var mobs: Array = floor.get("mobs", [])
	var key := "%s:%d:%s" % [str(at.get("mine", "")), n, str(at.get("day", ""))] if at is Dictionary else ":%d:" % n
	if key != _key:
		_key = key
		for enemy in _actors.values(): enemy.node.queue_free()
		enemies.clear()
		_actors.clear()
		dying.clear()
		fallen.clear()
		_fx.clear()   # a strike from the last floor never lands on this one
		grace = LANDING_GRACE_S
		for i in mobs.size():
			var kind := str(mobs[i].get("kind", ""))
			var spec := Monsters.spec(kind)   # from the kind's json; each monster its own copy
			spec.hp = int(mobs[i].get("max", mobs[i].get("hp", 1)))
			var hp := int(mobs[i].get("hp", spec.hp))
			if hp <= 0: continue
			var point := _spawn_point(player_mover, SPAWNS[i % SPAWNS.size()])
			var movement := PlayerMover.new(player_mover.bp, player_mover.grid)
			movement.position = point
			movement.speed = float(spec.move_speed)
			var node := Monsters.view(kind, spec)
			add_child(node)
			node.position = point
			(node.get_node("Health") as Label3D).visible = false   # the bar only (EnemyHP Kind=Mob, COMBAT-1)
			for bar in ["HealthFill", "HealthTrack"]: (node.get_node(bar) as Node3D).visible = false   # after the first hit
			var id := mob_id(i)
			enemies[id] = {"id": id, "kind": kind, "node": node, "spec": spec, "brain": Monsters.brain(kind), "mover": movement,
				"index": i, "hp": hp, "phase": "idle", "timer": 0.0, "repath": 0.0, "direction": Vector3.FORWARD, "flash": 0.0,
				"did_hit": false, "elite": bool(mobs[i].get("elite", Monsters.is_elite(kind))), "guard": bool(mobs[i].get("guard", false))}
			_actors[id] = enemies[id]
	for id in _actors:
		var enemy: Dictionary = _actors[id]
		var i := int(enemy.index)
		var hp := int(mobs[i].get("hp", 0)) if i < mobs.size() else 0
		if hp < int(enemy.hp):
			_number(enemy.node.position + Vector3(0, 1, 0), str(int(enemy.hp) - hp), Color("fff3bd"))
			enemy.flash = 0.18
			if not bool(enemy.get("guard", false)):   # the Mob bar shows from the first hit on; a guard's is the HUD card (E5)
				for bar in ["HealthFill", "HealthTrack"]: (enemy.node.get_node(bar) as Node3D).visible = true
		enemy.hp = hp
		if hp <= 0:
			if enemies.has(id):   # just now: once, however many syncs say it again
				fallen[i] = enemy.node.position
				_die(id, enemy)
			continue
		if str(enemy.phase) == "dead":   # back up (a reply's view rolled back), falling or fallen: standing again
			dying.erase(id)
			enemy.phase = "idle"
			enemy.node.call("play", "idle")
		enemy.node.visible = true
		enemies[id] = enemy
		enemy.mover.bp = player_mover.bp
		enemy.mover.grid = player_mover.grid
		enemy.node.get_node("HealthFill").scale.x = maxf(0.01, float(hp) / float(enemy.spec.hp))

## A monster the server reports down (`mob_down`), shown down now as a sync to 0 HP would: its last damage number, then
## gone (李元芳 B6, 283 86d07bd5: a reply whose view moved on must not leave it standing).
func down(i: int) -> void:
	var id := mob_id(i)
	var enemy = _actors.get(id, null)
	if enemy == null or int(enemy.hp) <= 0: return
	_number(enemy.node.position + Vector3(0, 1, 0), str(int(enemy.hp)), Color("fff3bd"))
	fallen[i] = enemy.node.position
	enemy.hp = 0
	_die(id, enemy)

## Down: out of the fight at once (no hit, no touch, not alive for the ladder), its look playing `die` for its json's
## time (a model folds and fades, 上官婉儿; 刘邦's views fade in update) and then gone; a kind that times no die (the
## slime's placeholder) is gone now, as it always was.
func _die(id: String, enemy: Dictionary) -> void:
	enemies.erase(id)
	enemy.phase = "dead"   # no brain runs it; back above 0 HP it stands again (亚瑟 on #685)
	var node = enemy.node
	var left := float(node.call("duration", "die")) if node.has_method("duration") else 0.0
	if left <= 0.0:
		node.visible = false
		return
	node.visible = true
	node.call("play", "die")
	dying[id] = {"enemy": enemy, "left": left}

## The id a monster index goes by in the old combat ("slime_1" …) and back.
static func mob_id(i: int) -> String: return "slime_%d" % (i + 1)
static func mob_index(id: String) -> int: return id.trim_prefix("slime_").to_int() - 1

## Where monster i fell, or its spawn spot when it fell before this scene saw it.
func fallen_at(i: int) -> Vector3:
	return fallen.get(i, SPAWNS[i % SPAWNS.size()])

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

## A brain's moves (contract-efg §10; 亚瑟 on #627: not the fight's private helpers): `slide` a short move that never goes
## through a wall, `dash_step` a dash's step cut where the body would reach the player's edge.
func slide(mover: PlayerMover, offset: Vector3) -> void: _slide(mover, offset)
func dash_step(enemy: Dictionary, player: PlayerMover, offset: Vector3) -> Vector3: return _dash_step(enemy, player, offset)

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
	var fx := {"left": fx_delay, "origin": mover.position, "facing": mover.facing, "reach": float(spec.range), "hits": []}
	last_stunned = []
	for id in enemies:
		var enemy: Dictionary = enemies[id]
		if not enemy.brain.can_be_hit(enemy): continue   # a Shroomling hiding
		var reach := float(spec.range) + HIT_SLACK + float(enemy.spec.get("radius", 0.0))   # to the body's edge
		if not within_swing(mover.position, mover.facing, enemy.node.position, reach, float(_config.attack_arc_degrees)): continue
		if not mover.grid.segment_walkable(mover.position, enemy.node.position): continue
		hit.append(id)
		if enemy.brain.stunned(enemy): last_stunned.append(id)   # struck while stunned (a Rock Beetle): × its stun_mult
		enemy.brain.on_hit(enemy, float(_config.hit_stun_seconds))
		fx.hits.append(id)
	if fx_delay > 0.0: _fx.append(fx)
	else: _strike(fx, mover)
	return hit

## The monsters the last swing struck while they were stunned (contract-efg §8: mine_attack's `stunned`).
var last_stunned: Array[String] = []

## Seconds from a swing's press to its visible strike (the slash clip's wrist peak; P0Mine sets it per swing, SGODOT-291):
## the arc, the struck slimes' flash and their knockback wait that long. Who was hit, their stun and the command to the
## server do not — they stay at the press, so the server's tempo and the fight's timing are as before.
var fx_delay := 0.0
var _fx: Array = []   # strikes waiting for their peak: {left, origin, facing, reach, hits}

## The visible strike: the arc where the swing was aimed, and each struck slime still up flashing and knocked back from
## where the player stands now.
func _strike(fx: Dictionary, mover: PlayerMover) -> void:
	_show_swing(fx.origin, fx.facing, float(fx.reach))
	for id in fx.hits:
		if not enemies.has(id): continue   # gone meanwhile (the swing's reply took it down)
		var enemy: Dictionary = enemies[id]
		enemy.flash = 0.18
		var direction: Vector3 = (enemy.node.position - mover.position).normalized()
		_slide(enemy.mover, direction * float(_weapon.knockback) * (1.0 - float(enemy.spec.knockback_resistance)))
		enemy.node.position = enemy.mover.position


## A frame: the strikes waiting for their peak, the old mine's clocks and each monster's move from its brain (none while
## the fight holds still or in the landing grace), then each monster's look — which goes on while it holds still, so a
## band still fades — and a short buzz when one starts a wind-up.
func step(delta: float, mover: PlayerMover, paused: bool) -> void:
	if not paused:
		for fx in _fx.duplicate():
			fx.left = float(fx.left) - clampf(delta, 0, 0.1)
			if fx.left <= 0.0:
				_fx.erase(fx)
				_strike(fx, mover)
	var before := {}
	for id in enemies: before[id] = str(enemies[id].phase)
	var stepped := _advance(delta, mover, paused)
	for id in enemies:
		var e: Dictionary = enemies[id]
		var was := str(before.get(id, ""))
		if str(e.phase) == "windup" and was != "windup" and HAPTIC_MS > 0 and OS.has_feature("mobile"): Input.vibrate_handheld(HAPTIC_MS)
		e.node.update(e, was, delta, stepped, _elapsed)
	# the fallen play their die out, paused or not (a reply's sync can down one while the fight holds still)
	for id in dying.keys():
		var d: Dictionary = dying[id]
		var e: Dictionary = d.enemy
		e.node.update(e, "dead", delta, stepped, _elapsed)
		d.left = float(d.left) - delta
		if float(d.left) <= 0.0:
			e.node.visible = false
			dying.erase(id)

## The old mine's frame (mine_combat.step) with the moves from each monster's brain: the clocks, the landing grace, then
## each monster, at most one finding its path a frame (perf Q6). Whether the monsters moved this frame.
func _advance(delta: float, mover: PlayerMover, paused: bool) -> bool:
	if paused: return false
	var dt := clampf(delta, 0, 0.1)
	_elapsed += dt
	cooldown = maxf(0, cooldown - dt)
	invulnerability = maxf(0, invulnerability - dt)
	grace = maxf(0, grace - dt)
	fade(dt)
	if grace > 0: return false
	var pathed := false
	for id in enemies:
		var enemy: Dictionary = enemies[id]
		enemy.timer = maxf(0, float(enemy.timer) - dt)
		enemy.flash = maxf(0, float(enemy.flash) - dt)
		if enemy.brain.step(enemy, self, mover, dt, not pathed): pathed = true
	return true

## A monster's hit reached the player (its brain says when): the player's invulnerability starts and `contact` goes up,
## which the mine sends to the server (mine_attack hurt_by).
func touch(enemy: Dictionary) -> void:
	invulnerability = float(_config.invulnerability_ms) / 1000.0
	contact.emit(str(enemy.id))

## The band's reach and width for a kind (its mining-table name or the kind; tests, the 288 report).
func band_of(kind: String) -> Dictionary:
	return SlimeView.band_size(Monsters.spec(str(LEGACY.get(kind, kind))))
