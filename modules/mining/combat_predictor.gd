extends RefCounted
## Pending health is visual only. Inventory and floor clearance always come from the server.

const Layout = preload("res://modules/mining/mine_layout.gd")
var pending: Array[Dictionary] = []

func view(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	var mine: Dictionary = result.get("mine", {})
	var floor_number := int(mine.get("floor", 0))
	if floor_number <= 0: return result
	var config: Dictionary = Layout.data().combat
	var kinds: Array = config.floors.get(str(floor_number), [])
	var health: Array = mine.get("combat", {}).get("monsters", {}).get(str(floor_number), []).duplicate()
	if health.size() != kinds.size():
		var cleared: bool = mine.get("cleared_floors", []).any(func(value): return int(value) == floor_number)
		health = kinds.map(func(kind): return 0 if cleared else int(config.monsters[kind].hp))
	if not mine.has("combat"): mine.combat = {"sequence": 0, "monsters": {}}
	mine.combat.monsters[str(floor_number)] = health
	var damage := int(CharacterModel.main_hand_stats(state).damage)
	var hp := CharacterModel.hp(state)
	for event in pending:
		if int(event.run) != int(mine.get("run", 0)) or int(event.floor) != floor_number: continue
		if hp <= 0: break
		for id in event.targets:
			var index := str(id).trim_prefix("slime_").to_int() - 1
			if index < 0 or index >= health.size() or damage <= 0: continue
			health[index] = maxi(0, int(health[index]) - maxi(1, damage - int(config.monsters[kinds[index]].defense)))
		var source := str(event.get("hurt_by", "")).trim_prefix("slime_").to_int() - 1
		if source >= 0 and source < health.size() and int(health[source]) > 0:
			hp = maxi(0, hp - maxi(1, int(config.monsters[kinds[source]].damage) - int(CharacterModel.current(state, "defense"))))
	if not result.has("character"): result.character = {"version": 1, "buffs": []}
	result.character.hp = hp
	return result

func payload(state: Dictionary) -> Dictionary:
	if pending.is_empty(): return {}
	var event := pending[0].duplicate(true)
	var mine: Dictionary = state.get("mine", {})
	if int(event.run) != int(mine.get("run", -1)) or int(event.floor) != int(mine.get("floor", 0)): return {}
	var health: Array = mine.get("combat", {}).get("monsters", {}).get(str(int(event.floor)), [])
	if not mine.has("combat"):
		var config: Dictionary = Layout.data().combat
		var cleared: bool = mine.get("cleared_floors", []).any(func(value): return int(value) == int(event.floor))
		health = config.floors.get(str(int(event.floor)), []).map(func(kind): return 0 if cleared else int(config.monsters[kind].hp))
	var alive := func(id):
		var index := str(id).trim_prefix("slime_").to_int() - 1
		return index >= 0 and index < health.size() and int(health[index]) > 0
	event.targets = event.targets.filter(alive)
	if event.has("hurt_by") and not alive.call(event.hurt_by): event.erase("hurt_by")
	if event.targets.is_empty() and not event.has("hurt_by"): return {}
	event.sequence = int(mine.get("combat", {}).get("sequence", 0))
	event.erase("created_ms")
	return event
