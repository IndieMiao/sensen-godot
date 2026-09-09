class_name JourneyRequests
extends RefCounted

static func tracked(state: Dictionary) -> Dictionary:
	var pin: Dictionary = state.get("journey", {}).get("tracked_opportunity", {})
	var slot := str(pin.get("slot", ""))
	var progress: Dictionary = state.get("journey", {}).get("opportunities", {}).get(slot, {})
	if pin.is_empty() or not progress.has("sequence") or pin.get("sequence") != progress.sequence: return {}
	return pin if available(state, slot) else {}

static func available(state: Dictionary, slot: String) -> bool:
	var spec := JourneyProgress.offer(state, slot)
	return not spec.is_empty() and (not spec.has("requires") or JourneyProgress.unlocked(state, str(spec.requires))) \
		and (slot != "bistro" or JourneyProgress.fact(state, "shared_meal"))

static func crop_needs(state: Dictionary, slot := "") -> Dictionary:
	if slot.is_empty(): slot = str(tracked(state).get("slot", ""))
	if not available(state, slot): return {}
	var spec := JourneyProgress.offer(state, slot)
	var needs: Dictionary = spec.produce.duplicate()
	for dish in spec.dishes:
		var missing := maxi(0, int(spec.dishes[dish]) - int(state.get("inventory", {}).get("dishes", {}).get(dish, 0)))
		for crop in JourneyProgress.recipes()[dish].inputs:
			needs[crop] = int(needs.get(crop, 0)) + missing * int(JourneyProgress.recipes()[dish].inputs[crop])
	return needs

static func dish_needs(state: Dictionary) -> Dictionary:
	var pin := tracked(state)
	return JourneyProgress.offer(state, str(pin.slot)).dishes.duplicate() if not pin.is_empty() else {}

static func goal(state: Dictionary, now_ms := -1, slot := "") -> Dictionary:
	if slot.is_empty(): slot = str(tracked(state).get("slot", ""))
	if not available(state, slot): return {}
	var spec := JourneyProgress.offer(state, slot)
	var next := {}
	if JourneyProgress.material(state, "wood") < int(spec.wood):
		next = JourneyProgress._material_goal(state, "wood")
		next.hint = "Wood %d/%d" % [JourneyProgress.material(state, "wood"), int(spec.wood)]
	if next.is_empty():
		var candidates := []
		var needs := crop_needs(state, slot)
		for crop in needs:
			if JourneyProgress.available(state, str(crop)) < int(needs[crop]):
				candidates.append(JourneyProgress._crop_goal(state, str(crop), int(needs[crop]), now_ms))
		var order := {"harvest": 0, "care": 1, "gather": 2, "sow": 3, "stall": 4, "wait": 5}
		candidates.sort_custom(func(a, b): return order[a.action] < order[b.action])
		if not candidates.is_empty(): next = candidates[0]
	if next.is_empty():
		for dish in spec.dishes:
			if int(state.get("inventory", {}).get("dishes", {}).get(dish, 0)) < int(spec.dishes[dish]):
				next = {"place": "bistro", "target": "counter", "hint": "Prepare " + str(dish).capitalize(), "icon": "utensils"}
				break
	if next.is_empty():
		next = {"place": "bistro", "target": "table", "icon": "utensils"} if slot == "bistro" else \
			JourneyProgress._resident_goal(str(StreetCommons.RESIDENTS[slot]), "", "package-check")
		next.hint = "Ready to deliver"
	next.label = "%s: %s" % [spec.name, next.hint]
	return next
