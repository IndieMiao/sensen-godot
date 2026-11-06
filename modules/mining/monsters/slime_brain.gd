extends "res://modules/mining/monsters/monster_brain.gd"
## The Slime's fight, as the old mine had it (moved unchanged from mine_combat.gd step): idle until the player is within
## aggro, chase, wind up once within reach in the open, leap along the direction the wind-up locked, recover; a swing's
## short stun holds it. The Elite Slime's too, with its own numbers, and any kind the client does not know yet
## (Monsters).

func step(enemy: Dictionary, fight, player: PlayerMover, dt: float, may_path: bool) -> bool:
	var spec: Dictionary = enemy.spec
	var movement: PlayerMover = enemy.mover
	var distance := movement.position.distance_to(player.position)
	var pathed := false
	match str(enemy.phase):
		"idle", "chase":
			if distance <= float(spec.attack_range) and movement.grid.segment_walkable(movement.position, player.position):
				enemy.phase = "windup"
				enemy.timer = float(spec.windup_seconds)
				enemy.direction = (player.position - movement.position).normalized()
				enemy.did_hit = false
				movement.stop()
			elif distance <= float(spec.aggro_range):
				enemy.phase = "chase"
				enemy.repath -= dt
				if enemy.repath <= 0 and may_path:
					pathed = true
					enemy.repath = REPATH_S
					movement.set_target_position(player.position)
				movement.step(dt)
			else:
				enemy.phase = "idle"
				movement.stop()
		"windup":
			if enemy.timer <= 0:
				enemy.phase = "dash"
				enemy.timer = float(spec.dash_seconds)
		"dash":
			fight.slide(movement, fight.dash_step(enemy, player, enemy.direction * float(spec.dash_speed) * dt))
			if not enemy.did_hit and fight.invulnerability <= 0 and movement.position.distance_to(player.position) <= float(spec.radius) + 0.35 and movement.grid.segment_walkable(movement.position, player.position):
				enemy.did_hit = true
				fight.touch(enemy)
			if enemy.timer <= 0:
				enemy.phase = "recover"
				enemy.timer = float(spec.recovery_seconds)
		"recover", "stunned":
			if enemy.timer <= 0: enemy.phase = "chase"
	enemy.node.position = movement.position
	return pathed
