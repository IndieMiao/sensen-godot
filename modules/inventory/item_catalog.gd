class_name ItemCatalog
extends RefCounted

const PATH := "res://assets/farm/data/items.json"
const CATEGORIES := ["all", "seeds", "crops", "mineral", "material", "dish", "equipment", "prop", "fish"]
const CATEGORY_NAMES := {"all": "All items", "seeds": "Seeds", "crops": "Harvest", "mineral": "Minerals", "material": "Materials", "dish": "Meals", "equipment": "Equipment", "prop": "Handmade pieces", "fish": "Fish"}
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func definition(id: String) -> Dictionary:
	return data().get("items", {}).get(id, {})

static func name_of(id: String) -> String:
	return L10n.text(str(definition(id).get("name", id)))

static func category_name(id: String) -> String:
	return L10n.text(str(CATEGORY_NAMES.get(id, "Other")))

static func texture(id: String) -> Texture2D:
	var spec := definition(id)
	var path := str(spec.get("icon", ""))
	if not path.is_empty() and ResourceLoader.exists(path): return load(path) as Texture2D
	return GameUi.icon({"equipment": "shovel", "mineral": "pickaxe", "material": "package-check", "prop": "hammer"}.get(str(spec.get("category", "")), "backpack"))

static func matches(id: String, category: String, query: String) -> bool:
	var spec := definition(id)
	if category != "all" and spec.get("category") != category: return false
	var needle := query.strip_edges().to_lower()
	if needle.is_empty(): return true
	var terms := [name_of(id), category_name(str(spec.get("category", ""))), L10n.text(str(spec.get("description", "")))]
	for use in spec.get("uses", []): terms.append(L10n.text(str(use)))
	return " ".join(terms).to_lower().contains(needle)

static func property_name(id: String) -> String:
	if id in ["crop_power", "ore_power", "wood_power"]:
		return L10n.text({"crop_power": "Crop gathering efficiency", "ore_power": "Ore gathering efficiency", "wood_power": "Wood gathering efficiency"}[id])
	if id in ["damage", "speed", "range", "knockback"]:
		return L10n.text({"damage": "Main-hand damage", "speed": "Attacks per second", "range": "Attack range", "knockback": "Knockback"}[id])
	return CharacterModel.stat_name(id) if id in CharacterModel.STATS else L10n.text(id.capitalize())

static func property_value(value: Variant) -> String:
	if value is float and is_equal_approx(value, roundf(value)): return str(int(value))
	if value is bool: return L10n.text("Yes" if value else "No")
	return L10n.text(str(value))

static func quality_name(id: String) -> String:
	return L10n.text({"normal": "Normal quality", "silver": "Silver quality", "gold": "Gold quality", "iridium": "Iridium quality"}.get(id, "Unknown quality"))

static func gameplay_properties(state: Dictionary, id: String) -> Array:
	var source: Dictionary = definition(id).get("source", {})
	var result: Array = []
	match str(source.get("kind", "")):
		"fish":
			result.append(L10n.format_text("Stall price: %d coins", int(FishingModel.fish(id).price)))
		"seed":
			result.append(L10n.format_text("Growth after care: %s", FarmHud.format_countdown(CropInfo.duration_ms(str(source.id), state))))
			result.append(L10n.format_text("Seed price: %d coins", CropInfo.seed_price(str(source.id))))
		"produce":
			result.append(L10n.format_text("Stall price: %d coins", CropInfo.unit_price(str(source.id), state)))
		"dish":
			var recipe: Dictionary = JourneyProgress.recipes().get(source.id, {})
			var price := int(JourneyProgress.data().dish_prices.get(source.id, 0)) if JourneyProgress.active(state) else int(recipe.get("stall_price", 0))
			result.append(L10n.format_text("Stall price: %d coins", price))
			result.append(_ingredients(recipe.get("inputs", {}), recipe.get("materials", {})))
		"prop":
			var recipe: Dictionary = JourneyProgress.data().workshop.recipes.get(source.id, {})
			if not recipe.is_empty():
				result.append(L10n.format_text("Delivery reward: %d coins", int(recipe.coins)))
				result.append(_ingredients(recipe.get("produce", {}), CharacterModel.craft_materials(state, recipe.get("materials", {}))))
		"equipment":
			result.append(CharacterModel.modifier_label(id))
			if not CharacterModel.equipment(id).get("materials", {}).is_empty():
				result.append(_ingredients({}, CharacterModel.craft_materials(state, CharacterModel.equipment(id).get("materials", {}))))
		"material":
			if id in ["stone", "copper_ore", "rock_salt"]:
				var mining: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/mining.json"))
				if id == "stone": result.append(L10n.format_text("Per mined rock: %d", int(mining.stone_per_rock)))
				else:
					var total := 0
					for drop in mining.bonus_drops: total += int(drop.weight)
					for drop in mining.bonus_drops:
						if drop.material == id and total > 0: result.append(L10n.format_text("Mining bonus chance: %d%%", roundi(float(drop.weight) / total * 100)))
	return result

static func _ingredients(produce: Dictionary, materials: Dictionary) -> String:
	var entries: Array[String] = []
	for crop in produce: entries.append(CropInfo.name_of(str(crop)) + " x" + str(int(produce[crop])))
	for item in materials: entries.append(L10n.material_name(str(item)) + " x" + str(int(materials[item])))
	return L10n.text("Ingredients") + ": " + " / ".join(entries)
