extends "res://modules/mining/monsters/f_brain.gd"
## The king keeps the slime's chase/telegraph/charge/recovery pattern, with its own authored timestamps.

func step(enemy: Dictionary, fight, player: PlayerMover, dt: float, may_path: bool) -> bool:
	var pathed := false
	match str(enemy.phase):
		"idle", "chase":
			if in_reach(enemy, player, float(enemy.spec.attack_range)): lock_attack(enemy, player)
			else:
				enemy.phase = "chase"
				pathed = chase(enemy, player, dt, may_path)
		"windup":
			if enemy.timer <= 0.0: enter(enemy, "dash", "attack")
		"dash":
			charge(enemy, fight, player, dt)
			if enemy.timer <= 0.0: enter(enemy, "recover")
		"recover", "stunned":
			if enemy.timer <= 0.0: enemy.phase = "chase"
	place(enemy)
	return pathed
