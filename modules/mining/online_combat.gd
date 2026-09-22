extends "res://modules/mining/mine_combat.gd"
## Rendering and local swing feedback only. AI, collision and damage belong to the room server.

var _network_targets: Dictionary = {}

func apply_monsters(monsters: Array) -> void:
	_network_targets.clear()
	for monster in monsters:
		_network_targets[str(monster.id)] = monster
		if not enemies.has(str(monster.id)): continue
		var enemy: Dictionary = enemies[str(monster.id)]
		enemy.phase = str(monster.phase)
		enemy.hp = int(monster.hp)
		var label := enemy.node.get_node("Health") as Label3D
		label.text = "%d / %d" % [int(monster.hp), int(enemy.spec.hp)]
		enemy.node.get_node("HealthFill").scale.x = maxf(.01, float(monster.hp) / float(enemy.spec.hp))
		enemy.node.visible = int(monster.hp) > 0

func step(delta: float, _mover: PlayerMover, _paused: bool) -> void:
	var dt := clampf(delta, 0, .1)
	_elapsed += dt
	cooldown = maxf(0, cooldown - dt)
	invulnerability = maxf(0, invulnerability - dt)
	_swing_left = maxf(0, _swing_left - dt)
	if is_instance_valid(_swing): _swing.visible = _swing_left > 0
	for number in _numbers.duplicate():
		number.left -= dt
		number.label.position.y += dt * .5
		if number.left <= 0:
			number.label.queue_free()
			_numbers.erase(number)
	for id in enemies:
		if not _network_targets.has(id): continue
		var enemy: Dictionary = enemies[id]
		var target: Dictionary = _network_targets[id]
		var point := Vector3(float(target.x), 0, float(target.z))
		enemy.mover.position = (enemy.mover.position as Vector3).lerp(point, minf(1, dt * 12))
		enemy.node.position = enemy.mover.position
		var winding := str(target.phase) == "windup"
		var body := enemy.node.get_node("Body") as MeshInstance3D
		(body.material_override as StandardMaterial3D).albedo_color = Color("f38870") if winding else enemy.node.get_meta("color")
		body.scale = Vector3(1.12, .7, 1.12) if winding else Vector3(1, 1 + sin(_elapsed * 7) * .04, 1)
		enemy.node.get_node("Warning").visible = winding

func swing(state: Dictionary, mover: PlayerMover, target_id := "") -> Array[String]:
	var spec := weapon(state)
	if cooldown > 0 or spec.is_empty(): return []
	var target: Dictionary = enemies.get(target_id, {})
	if target.is_empty():
		var nearest := float(spec.range) + .35
		for enemy in enemies.values():
			var distance := mover.position.distance_to(enemy.node.position)
			if distance < nearest:
				nearest = distance
				target = enemy
	if not target.is_empty(): mover.facing = (target.node.position - mover.position).normalized()
	cooldown = 1.0 / float(spec.speed)
	_show_swing(mover.position, mover.facing, float(spec.range))
	return []
