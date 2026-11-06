extends "res://modules/mining/monsters/monster_brain.gd"
## Shared F movement and animation-clock helpers; the existing combat owns timer decrement and collision stepping.

func data(enemy: Dictionary) -> Dictionary:
	return enemy.node.meta

func seconds(enemy: Dictionary, action: String) -> float:
	return maxf(0.001, float(data(enemy).get("durations", {}).get(action, 0.0)))

func enter(enemy: Dictionary, phase: String, action := "") -> void:
	enemy.phase = phase
	enemy.timer = seconds(enemy, action if action != "" else phase)
	enemy.did_hit = false
	(enemy.mover as PlayerMover).stop()

func lock_attack(enemy: Dictionary, player: PlayerMover) -> void:
	var direction: Vector3 = player.position - enemy.mover.position
	direction.y = 0
	if direction.length_squared() > 0.00001: enemy.direction = direction.normalized()
	enter(enemy, "windup")

func in_reach(enemy: Dictionary, player: PlayerMover, reach: float) -> bool:
	return enemy.mover.position.distance_to(player.position) <= reach \
		and enemy.mover.grid.segment_walkable(enemy.mover.position, player.position)

func chase(enemy: Dictionary, player: PlayerMover, dt: float, may_path: bool) -> bool:
	var movement: PlayerMover = enemy.mover
	if movement.position.distance_to(player.position) > float(enemy.spec.aggro_range):
		movement.stop()
		return false
	enemy.repath -= dt
	var pathed: bool = enemy.repath <= 0.0 and may_path
	if pathed:
		enemy.repath = REPATH_S
		movement.set_target_position(player.position)
	movement.step(dt)
	return pathed

## One hit opportunity at the authored animation timestamp, not once per frame spent in contact.
func timed_hit(enemy: Dictionary, fight, player: PlayerMover, action: String, at_key: String, reach: float) -> void:
	var elapsed := seconds(enemy, action) - float(enemy.timer)
	if bool(enemy.did_hit) or elapsed < float(data(enemy).get(at_key, 0.0)): return
	enemy.did_hit = true
	if fight.invulnerability <= 0.0 and in_reach(enemy, player, reach): fight.touch(enemy)

func charge(enemy: Dictionary, fight, player: PlayerMover, dt: float) -> void:
	fight.slide(enemy.mover, fight.dash_step(enemy, player, enemy.direction * float(enemy.spec.dash_speed) * dt))
	# Imported body radii must not put the stop boundary outside the touch test.
	var contact: float = maxf(float(enemy.spec.radius) + fight.PLAYER_RADIUS, float(data(enemy).get("contact_range", 0.0)))
	timed_hit(enemy, fight, player, "attack", "hit_at", contact)

func place(enemy: Dictionary) -> void:
	enemy.node.position = enemy.mover.position
