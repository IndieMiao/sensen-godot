extends "res://modules/mining/monsters/f_brain.gd"

func can_be_hit(enemy: Dictionary) -> bool:
	return str(enemy.phase) == "dash"

func step(enemy: Dictionary, fight, player: PlayerMover, dt: float, may_path: bool) -> bool:
	var pathed := false
	match str(enemy.phase):
		"idle", "chase": enter(enemy, "fly_high")
		"fly_high":
			if in_reach(enemy, player, float(enemy.spec.attack_range)):
				(enemy.mover as PlayerMover).stop()
				if enemy.timer <= 0.0: lock_attack(enemy, player)
			else: pathed = chase(enemy, player, dt, may_path)
		"windup":
			if enemy.timer <= 0.0: enter(enemy, "dash", "attack")
		"dash":
			charge(enemy, fight, player, dt)
			if enemy.timer <= 0.0: enter(enemy, "recover")
		"recover", "stunned":
			if enemy.timer <= 0.0: enter(enemy, "fly_high")
	place(enemy)
	return pathed
