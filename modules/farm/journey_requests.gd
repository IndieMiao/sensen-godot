class_name JourneyRequests
extends RefCounted

const SLOTS := ["nursery", "bistro", "restorer"]

static func progress(state: Dictionary, slot: String) -> Dictionary:
	return state.get("journey", {}).get("opportunities", {}).get(slot, {})

static func accepted(state: Dictionary, slot: String) -> bool:
	var current := progress(state, slot)
	if current.has("accepted"): return bool(current.accepted)
	var pin: Dictionary = state.get("journey", {}).get("tracked_opportunity", {})
	return pin.get("slot") == slot and pin.get("sequence") == current.get("sequence", -1)

static func tracked(state: Dictionary) -> Dictionary:
	var pin: Dictionary = state.get("journey", {}).get("tracked_opportunity", {})
	var slot := str(pin.get("slot", ""))
	var progress: Dictionary = state.get("journey", {}).get("opportunities", {}).get(slot, {})
	if pin.is_empty() or not progress.has("sequence") or pin.get("sequence") != progress.sequence: return {}
	return pin if available(state, slot) and accepted(state, slot) else {}

static func available(state: Dictionary, slot: String) -> bool:
	var spec := JourneyProgress.offer(state, slot)
	return not spec.is_empty() and (not spec.has("requires") or JourneyProgress.unlocked(state, str(spec.requires))) \
		and (slot != "bistro" or JourneyProgress.fact(state, "shared_meal"))

static func requirements(state: Dictionary, slot: String) -> Dictionary:
	var spec := JourneyProgress.offer(state, slot)
	var result: Dictionary = spec.get("materials", {}).duplicate(true)
	if int(spec.get("wood", 0)) > 0: result.wood = int(result.get("wood", 0)) + int(spec.wood)
	for group in ["produce", "dishes", "props"]:
		for id in spec.get(group, {}): result[id] = int(result.get(id, 0)) + int(spec[group][id])
	return result

static func quantity(state: Dictionary, id: String) -> int:
	var spec := ItemCatalog.definition(id)
	var source: Dictionary = spec.get("source", {})
	match str(source.get("kind", "")):
		"produce": return JourneyProgress.available(state, str(source.id))
		"dish": return int(state.get("inventory", {}).get("dishes", {}).get(source.id, 0))
		"material": return JourneyProgress.material(state, str(source.id))
		"prop": return JourneyProgress.stock(state, str(source.id))
	return 0

static func supplies_ready(state: Dictionary, slot: String) -> bool:
	if not available(state, slot): return false
	var needs := requirements(state, slot)
	return needs.keys().all(func(id): return quantity(state, str(id)) >= int(needs[id]))

static func last_completed(state: Dictionary, slot: String) -> Dictionary:
	return progress(state, slot).get("last_completed", {})

static func completed_offer(state: Dictionary, slot: String) -> Dictionary:
	var record := last_completed(state, slot)
	for spec in JourneyProgress.data().opportunities.get(slot, []):
		if spec.get("id") == record.get("offer_id", ""): return spec
	return {}

static func last_reply(state: Dictionary, slot: String) -> String:
	return L10n.text(str(completed_offer(state, slot).get("reply", "")))

static func status(state: Dictionary, slot: String) -> String:
	if not available(state, slot): return L10n.text("Request not available yet")
	if not accepted(state, slot): return L10n.text("Available request")
	if supplies_ready(state, slot):
		return L10n.text("Ready to deliver") + (" / " + L10n.text("Tracked request") if tracked(state).get("slot") == slot else "")
	return L10n.text("Tracked request" if tracked(state).get("slot") == slot else "Accepted request")

static func delivery_goal(slot: String) -> Dictionary:
	var goal := {"place": "bistro", "target": "table", "icon": "utensils"} if slot == "bistro" else \
		JourneyProgress._resident_goal(str(StreetCommons.RESIDENTS[slot]), "", "package-check")
	goal.hint = L10n.text("Ready to deliver")
	return goal

static func material_needs(state: Dictionary, slot: String) -> Dictionary:
	var spec := JourneyProgress.offer(state, slot)
	var needs: Dictionary = spec.get("materials", {}).duplicate(true)
	needs.wood = int(needs.get("wood", 0)) + int(spec.get("wood", 0))
	for dish in spec.get("dishes", {}):
		var missing := maxi(0, int(spec.dishes[dish]) - quantity(state, str(dish)))
		for item in JourneyProgress.recipes()[dish].get("materials", {}):
			needs[item] = int(needs.get(item, 0)) + missing * int(JourneyProgress.recipes()[dish].materials[item])
	for prop in spec.get("props", {}):
		var missing := maxi(0, int(spec.props[prop]) - quantity(state, str(prop)))
		var recipe := CharacterModel.craft_recipe(state, JourneyProgress.data().workshop.recipes.get(prop, {}))
		for item in recipe.get("materials", {}): needs[item] = int(needs.get(item, 0)) + missing * int(recipe.materials[item])
	return needs

static func crop_needs(state: Dictionary, slot := "") -> Dictionary:
	if slot.is_empty(): slot = str(tracked(state).get("slot", ""))
	if not available(state, slot): return {}
	var spec := JourneyProgress.offer(state, slot)
	var needs: Dictionary = spec.produce.duplicate()
	for dish in spec.dishes:
		var missing := maxi(0, int(spec.dishes[dish]) - int(state.get("inventory", {}).get("dishes", {}).get(dish, 0)))
		for crop in JourneyProgress.recipes()[dish].inputs:
			needs[crop] = int(needs.get(crop, 0)) + missing * int(JourneyProgress.recipes()[dish].inputs[crop])
	for prop in spec.get("props", {}):
		var missing := maxi(0, int(spec.props[prop]) - quantity(state, str(prop)))
		for crop in JourneyProgress.data().workshop.recipes.get(prop, {}).get("produce", {}):
			needs[crop] = int(needs.get(crop, 0)) + missing * int(JourneyProgress.data().workshop.recipes[prop].produce[crop])
	return needs

static func dish_needs(state: Dictionary) -> Dictionary:
	var pin := tracked(state)
	return JourneyProgress.offer(state, str(pin.slot)).dishes.duplicate() if not pin.is_empty() else {}

static func goal(state: Dictionary, now_ms := -1, slot := "") -> Dictionary:
	if slot.is_empty(): slot = str(tracked(state).get("slot", ""))
	if not available(state, slot): return {}
	var spec := JourneyProgress.offer(state, slot)
	var next := {}
	for prop in spec.get("props", {}):
		if quantity(state, str(prop)) >= int(spec.props[prop]): continue
		for project in JourneyProgress.data().projects:
			var pieces := JourneyProgress.display_items(state, str(project))
			if pieces.has(prop):
				next = {"place": JourneyProgress.data().projects[project].place, "target": "display:%s:%d" % [project, pieces.find(prop)], "icon": "package-check", "hint": L10n.text("Collect your piece")}
				break
		if not next.is_empty(): break
	var materials := material_needs(state, slot)
	for item in materials:
		if not next.is_empty(): break
		var have := JourneyProgress.material(state, str(item))
		if have >= int(materials[item]): continue
		next = JourneyProgress._material_goal(state, str(item))
		next.hint = L10n.format_text("%s %d/%d", [L10n.material_name(str(item)), have, int(materials[item])])
		break
	if next.is_empty():
		var candidates := []
		var needs := crop_needs(state, slot)
		for crop in needs:
			if JourneyProgress.available(state, str(crop)) < int(needs[crop]):
				candidates.append(JourneyProgress._crop_goal(state, str(crop), int(needs[crop]), now_ms))
		var order := {"harvest": 0, "water": 1, "gather": 2, "sow": 3, "stall": 4, "wait": 5}
		candidates.sort_custom(func(a, b): return order[a.action] < order[b.action])
		if not candidates.is_empty(): next = candidates[0]
	if next.is_empty():
		for prop in spec.get("props", {}):
			if quantity(state, str(prop)) < int(spec.props[prop]):
				next = {"place": "nursery", "target": "workbench", "hint": L10n.text("Make ") + ItemCatalog.name_of(str(prop)), "icon": "hammer"}
				break
	if next.is_empty():
		for dish in spec.dishes:
			if int(state.get("inventory", {}).get("dishes", {}).get(dish, 0)) < int(spec.dishes[dish]):
				next = {"place": "bistro", "target": "counter", "hint": L10n.format_text("Prepare %s", str(dish).capitalize()), "icon": "utensils"}
				break
	if next.is_empty():
		next = delivery_goal(slot)
	next.label = L10n.format_text("%s: %s", [spec.name, next.hint])
	return next
