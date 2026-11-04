extends "res://modules/mining/monsters/f_brain.gd"

func can_be_hit(enemy: Dictionary) -> bool:
	return str(enemy.phase) != "hide"

func on_hit(enemy: Dictionary, _stun_s: float) -> void:
	if can_be_hit(enemy): enter(enemy, "hide")

func step(enemy: Dictionary, fight, player: PlayerMover, dt: float, may_path: bool) -> bool:
	var interval := float(data(enemy).get("spore_interval", 1.0))
	enemy["spore_wait"] = maxf(0.0, float(enemy.get("spore_wait", interval)) - dt)
	var pathed := false
	match str(enemy.phase):
		"idle", "chase":
			if in_reach(enemy, player, float(enemy.spec.attack_range)):
				enemy.phase = "idle"
				(enemy.mover as PlayerMover).stop()
				if enemy.spore_wait <= 0.0: lock_attack(enemy, player)
			else:
				enemy.phase = "chase"
				pathed = chase(enemy, player, dt, may_path)
		"windup":
			if enemy.timer <= 0.0:
				enter(enemy, "spore")
				enemy.spore_wait = interval
		"spore":
			timed_hit(enemy, fight, player, "spore", "spore_at", float(data(enemy).get("spore_range", enemy.spec.attack_range)))
			if enemy.timer <= 0.0: enter(enemy, "recover")
		"hide", "recover":
			if enemy.timer <= 0.0: enemy.phase = "idle"
	place(enemy)
	return pathed
