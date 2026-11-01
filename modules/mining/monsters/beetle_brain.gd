extends "res://modules/mining/monsters/f_brain.gd"

func stunned(enemy: Dictionary) -> bool:
	return str(enemy.phase) == "stunned" and float(enemy.timer) > 0.0

func on_hit(_enemy: Dictionary, _stun_s: float) -> void:
	pass   # Hits never cancel a charge or restart its authored post-charge vulnerability window.

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
			if enemy.timer <= 0.0: enter(enemy, "stunned")
		"stunned":
			if enemy.timer <= 0.0: enemy.phase = "chase"
	place(enemy)
	return pathed
