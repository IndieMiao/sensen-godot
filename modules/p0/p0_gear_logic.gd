extends RefCounted
## SGODOT-355 G: display facts from content and authoritative view; no local rewards or HP settlement.

## Independent integration switches (392). No player preference/save field: enable each in a reviewed build.
static var weapon_actions_enabled := true
static var potion_actions_enabled := true

static func command_allowed(cmd: Dictionary) -> bool:
	var type := str(cmd.get("type", ""))
	var id := str(cmd.get("item", ""))
	if id.begins_with("potion_") and type in ["store", "take_out"]: return false
	if not potion_actions_enabled and (type == "mine_drink" or (type == "buy" and id.begins_with("potion_"))): return false
	if not weapon_actions_enabled:
		if type == "equip" and id.begins_with("weapon_"): return false
		if type == "craft":
			for recipe in P0Logic.content().get("workbench", {}).get("recipes", []):
				if str(recipe.get("id", "")) == str(cmd.get("recipe", "")) and str(recipe.get("to", "")) == "weapon": return false
	return true

static func weapon(id: String) -> Dictionary:
	return P0Logic.content().get("mine", {}).get("combat", {}).get("weapons", {}).get(id, {})

static func potion(id: String) -> Dictionary:
	return P0Logic.content().get("mine", {}).get("potions", {}).get(id, {})

static func weapon_rows(view: Dictionary) -> Array:
	var out := []
	var gear: Dictionary = view.get("gear", {})
	for id in P0Logic.content().get("mine", {}).get("combat", {}).get("weapons", {}):
		if not str(id).begins_with("weapon_"): continue
		var d := weapon(id).duplicate()
		d.merge({id = id, owned = (gear.get("weapons", []) as Array).has(id), equipped = str(gear.get("weapon", "")) == id})
		out.append(d)
	return out

static func weapon_recipe(id: String) -> Dictionary:
	for r in P0Logic.content().get("workbench", {}).get("recipes", []):
		if str(r.get("to", "")) == "weapon" and str(r.get("out", "")) == id: return r
	return {}

static func weapon_gate(view: Dictionary, id: String) -> String:
	var recipe := weapon_recipe(id)
	if recipe.is_empty(): return ""
	var lv := int(recipe.get("homestead", 0))
	return "Homestead Lv%d" % lv if int(view.get("homestead", {}).get("level", 1)) < lv else "Craft at Workbench"

static func weapon_source(view: Dictionary, id: String) -> String:
	if (view.get("gear", {}).get("weapons", []) as Array).has(id): return ""
	if not weapon_recipe(id).is_empty(): return "Workbench"
	if str(P0Logic.content().get("mine", {}).get("first_dig", {}).get("reward", {}).get("weapon", "")) == id: return "Pip's First Dig"
	return ""

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
	if not potion_actions_enabled: return k
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

## v4q(9), #697: the server offers/consumes this line. Keep only this conversation's copy in the UI.
static func pip_line(view: Dictionary, resident: String) -> String:
	if resident != "res_pip" or P0Guide.guide_on(view): return ""
	var first = view.get("first_dig", null)
	if not first is Dictionary or not bool(first.get("done", false)): return ""
	var line = view.get("pip_line", null)
	if not line is Dictionary or str(line.get("key", "")) != "pip_vein": return ""
	var name := str(line.get("name", "")).strip_edges()
	if name == "" or str(line.get("vein", "")) == "": return ""
	var template := str(P0Logic.content().get("mine", {}).get("first_dig", {}).get("lines", {}).get("pip_vein", ""))
	return template.replace("%s", name) if template.contains("%s") else ""

static func first_dig_row(view: Dictionary) -> Dictionary:
	var d := first_dig(view)
	if d.is_empty(): return {}
	return {line = "Pip's First Dig · Floor %d/%d" % [int(d.get("have", 0)), int(d.floor)],
		icon = "ladder", go = "", dot = "", first_dig = true}

static func first_dig_card(view: Dictionary) -> Dictionary:
	var d := first_dig(view)
	if d.is_empty(): return {}
	var def: Dictionary = P0Logic.content().get("mine", {}).get("first_dig", {})
	var reward: Dictionary = def.get("reward", {})
	var parts := PackedStringArray()
	if int(reward.get("affinity", 0)) > 0: parts.append("+%d Friendship" % int(reward.affinity))
	var id := str(reward.get("weapon", ""))
	if id != "": parts.append(P0Logic.item_name(view, id))
	var giver: Dictionary = P0Logic.content().get("residents", {}).get(str(d.get("giver", "res_pip")), {})
	var who := "%s · %s · personal request" % [str(giver.get("name", "Pip")), str(giver.get("role", "Courier Kid"))]
	return {title = "Pip's First Dig", who = who, needs_label = "", close_only = true,
		line = "Ever been down a mine? Reach Floor %d and tell me what's down there!" % int(d.floor),
		needs = [{name = "Reach Floor %d · any mine" % int(d.floor), have = int(d.get("have", 0)), need = int(d.floor), icon = P0Logic.icon("ladder"), counting = true}],
		reward = " · ".join(parts)}

static func first_dig_reward(view: Dictionary, events: Array) -> String:
	if not events.any(func(e): return str(e.get("kind", "")) == "first_dig" and bool(e.get("done", false))): return ""
	var id := str(P0Logic.content().get("mine", {}).get("first_dig", {}).get("reward", {}).get("weapon", ""))
	if id == "": return ""
	return P0Logic.item_name(view, id) + (" · equipped" if str(view.get("gear", {}).get("weapon", "")) == id else "")
