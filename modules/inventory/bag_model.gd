class_name BagModel
extends RefCounted

static func canonical(state: Dictionary) -> bool:
	return state.get("bag") is Dictionary and int(state.bag.get("version", 0)) == 2

static func snapshot(state: Dictionary) -> Dictionary:
	if state.get("bag") is Dictionary: return state.bag
	# Older previews remain readable; only a server snapshot can create managed stacks.
	var slots: Array = []
	for id in ItemCatalog.data().items:
		var source: Dictionary = ItemCatalog.definition(str(id)).source
		var amount := 0
		match str(source.kind):
			"seed":
				for lot in ["bound", "bought"]:
					var count := int(state.get("inventory", {}).get("seeds", {}).get(source.id, {}).get(lot, 0))
					if count > 0: slots.append({"id": "legacy_" + str(id) + "_" + lot, "item_id": id, "quantity": count, "quality": "normal", "seed_lot": lot})
				continue
			"produce": amount = int(state.get("inventory", {}).get("produce", {}).get(source.id, 0))
			"dish": amount = int(state.get("inventory", {}).get("dishes", {}).get(source.id, 0))
			"material": amount = JourneyProgress.material(state, str(source.id))
			"prop": amount = JourneyProgress.stock(state, str(source.id))
			"tool": amount = 1 if source.id == "hand_tools" or bool(state.get("tools", {}).get("row_tool", false)) else 0
		if amount > 0: slots.append({"id": "legacy_" + str(id), "item_id": id, "quantity": amount, "quality": "normal"})
	return {"version": 0, "sequence": 0, "capacity": maxi(int(ItemCatalog.data().capacity), slots.size()), "slots": slots, "overflow": [], "equipped": {}}

static func stack(state: Dictionary, id: String) -> Dictionary:
	var bag := snapshot(state)
	for entry in bag.get("slots", []) + bag.get("overflow", []):
		if str(entry.id) == id: return entry
	for entry in bag.get("equipped", {}).values():
		if entry is Dictionary and str(entry.get("id", "")) == id: return entry
	return {}

static func compatible(first: Dictionary, second: Dictionary) -> bool:
	return first.get("id") != second.get("id") and first.get("item_id") == second.get("item_id") \
		and first.get("quality", "normal") == second.get("quality", "normal") \
		and first.get("seed_lot", "") == second.get("seed_lot", "") \
		and first.get("attributes", {}) == second.get("attributes", {}) \
		and not first.has("instance_id") and not second.has("instance_id")

static func merge_targets(state: Dictionary, source: Dictionary) -> Array:
	return snapshot(state).get("slots", []).filter(func(entry):
		return compatible(source, entry) and int(entry.quantity) < int(ItemCatalog.definition(str(entry.item_id)).get("max_stack", 1)))

static func reserved(state: Dictionary, entry: Dictionary) -> int:
	var source: Dictionary = ItemCatalog.definition(str(entry.get("item_id", ""))).get("source", {})
	return int(state.get("engineering", {}).get("reserved", {}).get(source.get("id", ""), 0)) if source.get("kind") == "produce" else 0

static func discardable_quantity(state: Dictionary, entry: Dictionary) -> int:
	if not bool(ItemCatalog.definition(str(entry.get("item_id", ""))).get("discardable", false)): return 0
	var available := int(entry.get("quantity", 0))
	var source: Dictionary = ItemCatalog.definition(str(entry.get("item_id", ""))).get("source", {})
	if source.get("kind") == "produce":
		available = mini(available, maxi(0, int(state.get("inventory", {}).get("produce", {}).get(source.id, 0)) - reserved(state, entry)))
	return available

static func tool_scope(state: Dictionary) -> int:
	return CharacterModel.current(state, "tool_scope")

static func routes(state: Dictionary, id: String) -> Array:
	var spec := ItemCatalog.definition(id)
	var source: Dictionary = spec.get("source", {})
	var kind := str(source.get("kind", ""))
	var result: Array = []
	for slot in JourneyRequests.SLOTS:
		if JourneyRequests.available(state, slot) and JourneyRequests.requirements(state, slot).has(id):
			var goal := JourneyRequests.delivery_goal(slot)
			result.append(goal.merged({"icon": "list-checks", "label": L10n.text(str(JourneyProgress.offer(state, slot).name))}, true))
	if kind == "seed": result.append(_route("sprout", "Plant", "farm", "", {"plant_crop": source.id}))
	if kind in ["material", "produce"]:
		for recipe_id in JourneyProgress.recipes():
			var recipe: Dictionary = JourneyProgress.recipes()[recipe_id]
			var inputs: Dictionary = recipe.get("materials", {}) if kind == "material" else recipe.get("inputs", {})
			if inputs.has(source.id): result.append(_route("utensils", L10n.dish_name(str(recipe_id)), "bistro", "counter"))
	if kind == "material":
		for equipment_id in CharacterModel.data().get("equipment", {}):
			if CharacterModel.equipment(str(equipment_id)).get("materials", {}).has(source.id):
				result.append(_route("hammer", ItemCatalog.name_of(str(equipment_id)), "nursery", "workbench"))
		for recipe_id in JourneyProgress.data().workshop.recipes:
			var recipe: Dictionary = JourneyProgress.data().workshop.recipes[recipe_id]
			if recipe.get("materials", {}).has(source.id): result.append(_route("hammer", L10n.text(str(recipe.name)), "nursery", "workbench"))
		for project_id in JourneyProgress.data().projects:
			var project: Dictionary = JourneyProgress.data().projects[project_id]
			if project.stages.any(func(stage): return stage.get("materials", {}).has(source.id)):
				result.append(_route("hammer", L10n.text(str(project.name)), str(project.place), "project_" + str(project_id)))
	if kind in ["produce", "dish"]: result.append(_route("store", "Sell", "farm", "stall"))
	if kind == "produce": result.append(_route("heart", "Neighbour requests", "nursery", "resident"))
	if id == "salad": result.append(_route("utensils", "Share a salad", "bistro", "table"))
	if id == "tea" and JourneyProgress.project_complete(state, "terrace"):
		result.append(_route("utensils", "Tea terrace", "bistro", "project_terrace"))
	if kind == "prop":
		result.append(_route("house", "Arrange courtyard", "courtyard", "decorations", {"selected_prop": id}))
		if JourneyProgress.data().workshop.recipes.has(id): result.append(_route("package-check", "Deliver", "nursery", "workbench"))
		for project_id in JourneyProgress.data().projects:
			if not JourneyProgress.data().workshop.recipes.has(id): break
			if not JourneyProgress.project_complete(state, str(project_id)): continue
			var displays := JourneyProgress.display_items(state, str(project_id))
			for slot in displays.size():
				if str(displays[slot]).is_empty():
					result.append(_route("move", "Display", str(JourneyProgress.data().projects[project_id].place), "display:" + str(project_id) + ":" + str(slot)))
					break
			if result.any(func(goal): return str(goal.target).begins_with("display:")): break
		for discovery_id in JourneyProgress.data().discoveries:
			var discovery: Dictionary = JourneyProgress.data().discoveries[discovery_id]
			if discovery.item == id and not JourneyProgress.fact(state, "discovery_" + str(discovery_id)):
				result.append(_route("hammer", L10n.text(str(discovery.name)), str(discovery.place), "discovery_" + str(discovery_id)))
	if id in ["copper_ore", "rock_salt", "stone"]: result.append(_route("pickaxe", "Enter mine", "farm", "mine"))
	return result

static func _route(icon: String, label: String, place: String, target: String, extra: Dictionary = {}) -> Dictionary:
	return {"icon": icon, "label": L10n.text(label), "place": place, "target": target}.merged(extra)
