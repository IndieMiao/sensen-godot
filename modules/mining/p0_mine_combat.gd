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

var _weapon := {"damage": 3, "speed": 2.0, "range": REACH, "knockback": KNOCKBACK}

## The weapon from the view (mine.weapon {attack, speed}); damage feeds the floating number only.
func weapon(_state: Dictionary) -> Dictionary:
	return _weapon

## Build or refresh this floor's monsters from the view. `key` changes with the run and floor: a new floor clears the
## old monsters and spawns these at the old mine's spots.
func sync_p0(view: Dictionary, n: int, player_mover: PlayerMover) -> void:
	var mine: Dictionary = view.get("mine", {})
	var w: Dictionary = mine.get("weapon", {})
	_weapon = {"damage": int(w.get("attack", 3)), "speed": float(w.get("speed", 2.0)), "range": REACH, "knockback": KNOCKBACK}
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
		grace = float(_config.entry_grace_seconds)
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
