class_name JourneyWorkshop
extends RefCounted

static func planned(state: Dictionary) -> Dictionary:
	var plan: Dictionary = state.get("journey", {}).get("workshop", {}).get("planned", {})
	if plan.is_empty() or not JourneyProgress.data().workshop.recipes.has(plan.get("item", "")): return {}
	if not JourneyProgress.data().projects.has(plan.get("project", "")): return {}
	if not JourneyProgress.project_complete(state, str(plan.get("project", ""))): return {}
	var slot := int(plan.get("slot", -1))
	if slot < 0 or slot >= int(JourneyProgress.data().workshop.display_slots): return {}
	if not str(JourneyProgress.display_items(state, str(plan.project))[slot]).is_empty(): return {}
	return plan

static func preview_item(state: Dictionary, project: String, slot: int) -> String:
	var plan := planned(state)
	return str(plan.item) if plan.get("project") == project and int(plan.get("slot", -1)) == slot else ""

static func goal(state: Dictionary) -> Dictionary:
	var plan := planned(state)
	if plan.is_empty(): return {}
	var recipe: Dictionary = JourneyProgress.data().workshop.recipes[plan.item]
	var next := {}
	if JourneyProgress.stock(state, str(plan.item)) > 0:
		next = {"place": JourneyProgress.data().projects[plan.project].place, "target": "display:%s:%d" % [plan.project, plan.slot],
			"icon": "plus", "hint": "Ready to place"}
	else:
		for project in JourneyProgress.data().projects:
			var display := JourneyProgress.display_items(state, str(project))
			if display.has(plan.item):
				next = {"place": JourneyProgress.data().projects[project].place, "target": "display:%s:%d" % [project, display.find(plan.item)],
					"icon": "backpack", "hint": "Collect your piece"}
				break
		if next.is_empty():
			for item in recipe.materials:
				var have := JourneyProgress.material(state, str(item))
				if have >= int(recipe.materials[item]): continue
				next = JourneyProgress._material_goal(state, str(item))
				next.hint = "%s %d/%d" % ["Reeds" if item == "fiber" else str(item).capitalize(), have, int(recipe.materials[item])]
				break
		if next.is_empty(): next = {"place": "nursery", "target": "workbench", "icon": "hammer", "hint": "Ready to make"}
	next.label = "%s: %s" % [recipe.name, next.hint]
	return next
