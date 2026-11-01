extends RefCounted
## SGODOT-355 G: display facts from content and authoritative view; no local rewards or HP settlement.

static func weapon(id: String) -> Dictionary:
	return P0Logic.content().get("mine", {}).get("combat", {}).get("weapons", {}).get(id, {})

static func potion(id: String) -> Dictionary:
	return P0Logic.content().get("mine", {}).get("potions", {}).get(id, {})

static func weapon_rows(view: Dictionary) -> Array:
	var out := []
	var gear: Dictionary = view.get("gear", {})
	for id in gear.get("weapons", []):
		if not id is String or weapon(id).is_empty(): continue
		var d := weapon(id).duplicate()
		d.merge({id = id, owned = true, equipped = str(gear.get("weapon", "")) == id})
		out.append(d)
	return out

static func weapon_effect(id: String) -> String:
	var d := weapon(id)
	return "Attack %d" % int(d.attack) if d.has("attack") else ""

static func potion_effect(id: String) -> String:
	var heal = potion(id).get("heal", null)
	if heal is String and heal == "full": return "Restores full HP"
	return "+%d HP" % int(heal) if heal is float or heal is int else ""

## E supplies authoritative remaining cooldown. Unknown (-1) must not enable a drink.
static func drink_action(view: Dictionary, id: String, cooldown_ms: float) -> Dictionary:
	var k := {icon = "heart", tool = id, verb = "Drink", sub = "", enabled = false, amber = false, cmd = {}, need = 0, once = true}
	var d := potion(id)
	var mine: Dictionary = view.get("mine", {})
	var at = mine.get("at", null)
	if d.is_empty() or not at is Dictionary:
		k.sub = "In the mine only"
		return k
	if P0Logic.bag_count(view, id) <= 0:
		k.sub = "Buy at Homestead Stall"
		return k
	var hp := int(at.get("hp", 0))
	var cap := int(mine.get("hp_max", 0))
	if cap <= 0 or hp <= 0: return k
	if hp >= cap:
		k.sub = "HP full"
		return k
	if cooldown_ms < 0:
		k.sub = "Loading"
		return k
	if cooldown_ms > 0:
		k.sub = P0Logic.duration(cooldown_ms)
		return k
	var floors = d.get("floors", "any")
	if floors is Array and not floors.has(int(at.get("floor", 0))): return k
	if str(at.get("day", "")) == "" or str(at.get("mine", "")) == "": return k
	if potion_effect(id) == "": return k
	k.enabled = true
	k.cmd = {type = "mine_drink", item = id, day = str(at.day), place = str(at.mine)}
	return k

static func first_dig(view: Dictionary) -> Dictionary:
	var d = view.get("first_dig", null)
	return d if d is Dictionary and not bool(d.get("done", false)) and int(d.get("floor", 0)) > 0 else {}

static func first_dig_row(view: Dictionary) -> Dictionary:
	var d := first_dig(view)
	if d.is_empty(): return {}
	return {line = "Pip's First Dig · Floor %d/%d" % [int(d.get("have", 0)), int(d.floor)],
		icon = "pickaxe", go = "", dot = "", first_dig = true}

static func first_dig_card(view: Dictionary) -> Dictionary:
	var d := first_dig(view)
	if d.is_empty(): return {}
	var def: Dictionary = P0Logic.content().get("mine", {}).get("first_dig", {})
	var reward: Dictionary = def.get("reward", {})
	var parts := PackedStringArray()
	if int(reward.get("affinity", 0)) > 0: parts.append("+%d Friendship" % int(reward.affinity))
	var id := str(reward.get("weapon", ""))
	if id != "": parts.append(P0Logic.item_name(view, id))
	return {title = "Pip's First Dig", who = "Pip", needs_label = "", close_only = true,
		line = "Ever been down a mine? Reach Floor %d and tell me what's down there!" % int(d.floor),
		needs = [{name = "Reach Floor %d · any mine" % int(d.floor), have = int(d.get("have", 0)), need = int(d.floor), icon = P0Logic.icon("pickaxe")}],
		reward = " · ".join(parts)}

static func first_dig_reward(view: Dictionary, events: Array) -> String:
	if not events.any(func(e): return str(e.get("kind", "")) == "first_dig" and bool(e.get("done", false))): return ""
	var id := str(P0Logic.content().get("mine", {}).get("first_dig", {}).get("reward", {}).get("weapon", ""))
	if id == "": return ""
	return P0Logic.item_name(view, id) + (" · equipped" if str(view.get("gear", {}).get("weapon", "")) == id else "")
