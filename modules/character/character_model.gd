class_name CharacterModel
extends RefCounted

const PATH := "res://assets/farm/data/character.json"
const STATS := ["max_hp", "move_speed", "defense", "tool_scope", "gather_bonus", "mining_bonus", "craft_savings"]
const SLOTS := ["main_hand", "fishing_rod", "ring_1", "ring_2", "necklace", "gloves"]
const HAND_STATS := ["damage", "speed", "range", "knockback", "crop_power", "ore_power", "wood_power"]
const BASIC_MATERIALS := ["wood", "stone", "fiber"]
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(PATH): _data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func canonical(state: Dictionary) -> bool:
	return BagModel.canonical(state) and int(state.get("character", {}).get("version", 0)) == 1

static func stat_name(id: String) -> String:
	if id in ["max_hp", "move_speed", "defense"]:
		return L10n.text({"max_hp": "Max HP", "move_speed": "Move speed", "defense": "Defense"}[id])
	return L10n.text({"tool_scope": "Plots per gesture", "gather_bonus": "Gathering bonus", "mining_bonus": "Mining stone bonus", "craft_savings": "Crafting savings"}.get(id, id))

static func stat_description(id: String) -> String:
	if id in ["max_hp", "move_speed", "defense"]:
		return L10n.text({"max_hp": "Maximum health.", "move_speed": "Movement in metres per second.", "defense": "Damage blocked from each monster hit."}[id])
	return L10n.text({"tool_scope": "Plots worked together with the equipped tool.", "gather_bonus": "Extra primary material from a regular supply pile.", "mining_bonus": "Extra stone per mined rock.", "craft_savings": "Fewer timber, stone or reeds spent at the workbench; at least one of each remains."}.get(id, ""))

static func slot_name(id: String) -> String:
	return L10n.text({"main_hand": "Main hand", "fishing_rod": "Fishing rod slot", "ring_1": "Ring 1", "ring_2": "Ring 2", "necklace": "Necklace", "gloves": "Gloves slot"}.get(id, id))

static func equipment_slots(id: String) -> Array:
	var slot := str(equipment(id).get("slot", ""))
	return ["ring_1", "ring_2"] if slot in ["ring_1", "ring_2"] else ([slot] if not slot.is_empty() else [])

static func main_hand_stats(state: Dictionary) -> Dictionary:
	var result: Dictionary = data().main_hand_base.duplicate()
	var properties: Dictionary = ItemCatalog.definition(str(equipped(state, "main_hand").get("item_id", ""))).get("properties", {})
	for stat in HAND_STATS:
		if properties.has(stat): result[stat] = properties[stat]
	return result

static func resource_kind(materials: Dictionary) -> String:
	if int(materials.get("wood", 0)) > 0: return "wood"
	for id in ["stone", "copper_ore", "rock_salt"]:
		if int(materials.get(id, 0)) > 0: return "ore"
	return "crop"

static func gather_seconds(state: Dictionary, kind: String, work := 0.9) -> float:
	return work / maxf(0.01, float(main_hand_stats(state).get(kind + "_power", 1)))

static func has_fishing_rod(state: Dictionary) -> bool:
	return equipment(str(equipped(state, "fishing_rod").get("item_id", ""))).get("slot") == "fishing_rod"

static func equipment(id: String) -> Dictionary:
	var spec: Dictionary = data().get("equipment", {}).get(id, {}).duplicate(true)
	if id in ["hand_tools", "row_tool"] and spec.is_empty():
		spec = {"slot": "main_hand", "modifiers": {"tool_scope": int(ItemCatalog.definition(id).get("properties", {}).get("tool_scope", 1)) - 1}}
	return spec

static func consumable(id: String) -> Dictionary:
	return data().get("consumables", {}).get(id, {})

static func buffs(state: Dictionary) -> Array:
	return state.get("character", {}).get("buffs", []).filter(func(buff): return int(buff.get("remaining_uses", 0)) > 0 and not consumable(str(buff.get("source_item_id", ""))).is_empty())

static func active_buff(state: Dictionary, id: String) -> Dictionary:
	var spec := consumable(id)
	for buff in buffs(state):
		if buff.get("id") == spec.get("buff_id"): return buff
	return {}

static func equipped(state: Dictionary, slot: String) -> Dictionary:
	var entry = BagModel.snapshot(state).get("equipped", {}).get(slot)
	return entry if entry is Dictionary else {}

static func equipped_slot(state: Dictionary, stack_id: String) -> String:
	for slot in SLOTS:
		if equipped(state, slot).get("id", "") == stack_id: return slot
	return ""

static func breakdown(state: Dictionary, stat: String) -> Dictionary:
	var base := float(data().get("base", {}).get(stat, 1 if stat == "tool_scope" else 0))
	var gear := 0.0
	for slot in SLOTS:
		var entry := equipped(state, slot)
		if not entry.is_empty(): gear += float(equipment(str(entry.item_id)).get("modifiers", {}).get(stat, 0))
	if stat == "tool_scope" and not BagModel.canonical(state): gear = 2 if bool(state.get("tools", {}).get("row_tool", false)) else 0
	var meals := 0
	for buff in buffs(state):
		var spec := consumable(str(buff.source_item_id))
		if spec.get("stat") == stat: meals += int(spec.get("amount", 0))
	if stat == "move_speed": return {"base": base, "equipment": gear, "meals": meals, "current": base + gear + meals}
	return {"base": int(base), "equipment": int(gear), "meals": meals, "current": int(base + gear + meals)}

static func current(state: Dictionary, stat: String) -> float:
	return float(breakdown(state, stat).current)

static func hp(state: Dictionary) -> int:
	return mini(int(current(state, "max_hp")), int(state.get("character", {}).get("hp", current(state, "max_hp"))))

static func can_eat(state: Dictionary, id: String) -> bool:
	return not consumable(id).is_empty() and (active_buff(state, id).is_empty() or (hp(state) < current(state, "max_hp") and int(consumable(id).get("heal", 0)) > 0))

static func compare(state: Dictionary, id: String, stat: String, target_slot := "") -> float:
	var candidate := equipment(id)
	if candidate.is_empty(): return current(state, stat)
	var old := equipped(state, target_slot if target_slot in equipment_slots(id) else str(candidate.slot))
	return current(state, stat) - float(equipment(str(old.get("item_id", ""))).get("modifiers", {}).get(stat, 0)) + float(candidate.get("modifiers", {}).get(stat, 0))

static func owns(state: Dictionary, id: String) -> bool:
	var bag := BagModel.snapshot(state)
	for entry in bag.get("slots", []) + bag.get("overflow", []):
		if entry.get("item_id") == id: return true
	for slot in SLOTS:
		if equipped(state, slot).get("item_id") == id: return true
	return false

static func effect_label(id: String) -> String:
	var spec := consumable(id)
	if spec.is_empty(): return ""
	return L10n.format_text("%s +%d for %d successful actions", [stat_name(str(spec.stat)), int(spec.amount), int(spec.uses)])

static func modifier_label(id: String) -> String:
	var parts: Array[String] = []
	if equipment(id).get("slot") == "main_hand":
		var properties: Dictionary = ItemCatalog.definition(id).get("properties", {})
		return L10n.format_text("Damage %d / Attacks per second %s", [int(properties.get("damage", 0)), str(properties.get("speed", 0))])
	for stat in equipment(id).get("modifiers", {}):
		var amount := float(equipment(id).modifiers[stat])
		if amount != 0: parts.append(stat_name(str(stat)) + " +" + ItemCatalog.property_value(amount))
	return " / ".join(parts)

static func action_status(state: Dictionary, stat: String) -> String:
	var amount := int(current(state, stat))
	if amount <= 0: return ""
	var text := stat_name(stat) + " +" + str(amount)
	for buff in buffs(state):
		if consumable(str(buff.source_item_id)).get("stat") == stat:
			text += " / " + L10n.format_text("Meal: %d uses left", int(buff.remaining_uses))
	return text

static func gathered_materials(state: Dictionary, materials: Dictionary) -> Dictionary:
	var result := materials.duplicate(true)
	var bonus := int(current(state, "gather_bonus"))
	if bonus <= 0: return result
	var primary := ""
	var largest := 0
	for item in BASIC_MATERIALS:
		if int(materials.get(item, 0)) > largest:
			primary = item
			largest = int(materials[item])
	if not primary.is_empty(): result[primary] = largest + bonus
	return result

static func craft_materials(state: Dictionary, materials: Dictionary) -> Dictionary:
	var result := materials.duplicate(true)
	var budget := int(current(state, "craft_savings"))
	for item in BASIC_MATERIALS:
		if budget <= 0: break
		var saved := mini(budget, maxi(0, int(result.get(item, 0)) - 1))
		if saved > 0:
			result[item] = int(result[item]) - saved
			budget -= saved
	return result

static func craft_recipe(state: Dictionary, recipe: Dictionary) -> Dictionary:
	var result := recipe.duplicate(true)
	result.materials = craft_materials(state, recipe.get("materials", {}))
	return result
