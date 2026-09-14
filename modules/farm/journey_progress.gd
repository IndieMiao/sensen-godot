class_name JourneyProgress
extends RefCounted

static var _data: Dictionary = {}
static var _recipes: Dictionary = {}
static var _bed_cells: Dictionary = {}

static func goal_state(session: FarmSession) -> Dictionary:
	if session == null: return {}
	var state := session.state
	var path := FarmBlueprint.asset_path(session.layout_patch_id, session.blueprint_revision)
	if not _bed_cells.has(path):
		if not FileAccess.file_exists(path): return state
		var blueprint := FarmBlueprint.load_file(path)
		if blueprint == null: return state
		var ids := {}
		for bed in blueprint.beds():
			for cell in bed.cells: ids["%d,%d" % [cell.x, cell.y]] = false
		for cell in blueprint.reserved_bed().cells: ids["%d,%d" % [cell.x, cell.y]] = true
		_bed_cells[path] = ids
	var cells := {}
	for id in _bed_cells[path]:
		if _bed_cells[path][id] and int(state.get("beds_unlocked", 3)) < 4: continue
		if not FieldGrowth.allows(state, str(id)): continue
		if state.get("cells", {}).has(id): cells[id] = state.cells[id]
	# Guidance reads a filtered view; the server snapshot and its reserved beds stay intact.
	return state.merged({"cells": cells}, true)

static func data() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/journey.json"))
	return _data

static func recipes() -> Dictionary:
	if _recipes.is_empty(): _recipes = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/recipes.json")).recipes
	return _recipes

static func active(state: Dictionary) -> bool:
	return int(state.get("journey", {}).get("version", 0)) == 1

static func fact(state: Dictionary, id: String) -> bool:
	return state.get("journey", {}).get("facts", []).has(id)

static func unlocked(state: Dictionary, id: String) -> bool:
	return state.get("journey", {}).get("unlocks", []).has(id)

static func crops(state: Dictionary) -> Array:
	return CropInfo.ORDER.filter(func(id): return id in ["R", "L"] or unlocked(state, "crop_" + str(id)))

static func nodes(state: Dictionary, place := "") -> Array:
	return data().nodes.filter(func(n): return (place.is_empty() or n.place == place) \
		and (n.place != "bistro" or unlocked(state, "bistro")) \
		and (not n.has("requires") or fact(state, str(n.requires))))

static func remaining_nodes(state: Dictionary, place := "") -> Array:
	var collected: Array = state.get("journey", {}).get("exploration", {}).get("collected", [])
	return nodes(state, place).filter(func(n): return not collected.has(n.id))

static func route_for(state: Dictionary, place: String) -> Dictionary:
	var exploration: Dictionary = state.get("journey", {}).get("exploration", {})
	var id := str(exploration.get("routes_by_place", {}).get(place, "neighbourhood")) if exploration.has("routes_by_place") else str(exploration.get("route", "neighbourhood"))
	var route: Dictionary = data().routes.get(id, {})
	return route if route.get("place") == place else {}

static func street_supplies(state: Dictionary, place: String) -> bool:
	return route_for(state, place).get("surface") == "street"

static func resource_goal(state: Dictionary, node: Dictionary, target: String, label := "Gather supplies") -> Dictionary:
	var goal := _goal(str(node.place), label, "compass").merged({"target": target})
	if street_supplies(state, str(node.place)): goal.surface = "street"
	return goal

static func route_ready(state: Dictionary, id: String) -> bool:
	var route: Dictionary = data().routes.get(id, {})
	if route.is_empty() or (route.has("requires") and not unlocked(state, str(route.requires))): return false
	var place := "" if id == "neighbourhood" else str(route.place)
	return not nodes(state, place).is_empty() and remaining_nodes(state, place).is_empty()

static func requirements_met(state: Dictionary, spec: Dictionary) -> bool:
	return spec.get("requires", []).all(func(id): return fact(state, str(id)))

static func cost_ready(state: Dictionary, spec: Dictionary) -> bool:
	for item in spec.get("materials", {}):
		if material(state, str(item)) < int(spec.materials[item]): return false
	for crop in spec.get("produce", {}):
		if available(state, str(crop)) < int(spec.produce[crop]): return false
	for dish in spec.get("dishes", {}):
		if int(state.get("inventory", {}).get("dishes", {}).get(dish, 0)) < int(spec.dishes[dish]): return false
	return true

static func next_story(state: Dictionary, resident: String) -> Dictionary:
	for story in data().stories.get(resident, []):
		if not fact(state, "story_" + str(story.id)): return story
	return {}

static func gift_ready(state: Dictionary, resident: String) -> bool:
	var journey: Dictionary = state.get("journey", {})
	return int(journey.get("gift_rounds", {}).get(resident, -1)) != int(journey.get("exploration", {}).get("round", 0))

static func stock(state: Dictionary, id: String) -> int:
	return int(state.get("journey", {}).get("workshop", {}).get("stock", {}).get(id, 0))

static func discovery_available(state: Dictionary, id: String) -> bool:
	var spec: Dictionary = data().discoveries.get(id, {})
	return not spec.is_empty() and requirements_met(state, spec) and (spec.place != "bistro" or unlocked(state, "bistro"))

static func discovery_ready(state: Dictionary, id: String) -> bool:
	return discovery_available(state, id) and not fact(state, "discovery_" + id) and stock(state, str(data().discoveries[id].item)) > 0

static func discovery_harvest_ready(state: Dictionary, id: String) -> bool:
	return discovery_available(state, id) and fact(state, "discovery_" + id) \
		and not state.get("journey", {}).get("exploration", {}).get("collected", []).has("discovery_" + id)

static func discovery_reward_label(choice: Dictionary) -> String:
	var parts: Array[String] = []
	var materials := material_label(choice.get("materials", {}))
	if not materials.is_empty(): parts.append(materials)
	for crop in choice.get("produce", {}): parts.append(L10n.format_text("%d %s", [int(choice.produce[crop]), CropInfo.name_of(str(crop))]))
	for crop in choice.get("seeds", {}): parts.append(L10n.format_text("%d %s seeds", [int(choice.seeds[crop]), CropInfo.name_of(str(crop))]))
	return " + ".join(parts)

static func tracked_goal(state: Dictionary, now_ms := -1) -> Dictionary:
	var request := JourneyRequests.goal(state, now_ms)
	if not request.is_empty(): return request
	var handmade := JourneyWorkshop.goal(state)
	if not handmade.is_empty(): return handmade
	var gathering := JourneyGatherings.goal(state, now_ms)
	if not gathering.is_empty(): return gathering
	var project_id := str(state.get("journey", {}).get("tracked_project", ""))
	if not project_id.is_empty(): return project_goal(state, project_id, now_ms)
	var id := str(state.get("journey", {}).get("tracked_discovery", ""))
	if not discovery_available(state, id) or fact(state, "discovery_" + id): return {}
	var spec: Dictionary = data().discoveries[id]
	if stock(state, str(spec.item)) > 0:
		return _goal(str(spec.place), L10n.text("Restore ") + L10n.text(str(spec.name)), "hammer").merged({"hint": L10n.text("Ready to restore"), "target": "discovery_" + id})
	var recipe: Dictionary = data().workshop.recipes[spec.item]
	# A displayed piece is still owned; retrieval must not suggest crafting another one.
	for project in data().projects:
		if display_items(state, str(project)).has(spec.item):
			return _goal(str(data().projects[project].place), L10n.format_text("Collect your %s for %s", [recipe.name, spec.name]), "package-check").merged({"hint": L10n.text("Collect your piece"), "target": "display:%s:%d" % [project, display_items(state, str(project)).find(spec.item)]})
	for material_id in recipe.materials:
		var need := int(recipe.materials[material_id])
		var have := material(state, str(material_id))
		if have < need:
			var destination := _material_goal(state, str(material_id))
			var label := L10n.text("Reeds") if material_id == "fiber" else str(material_id).capitalize()
			destination.label = L10n.format_text("%s: %s %d/%d", [spec.name, label, have, need])
			destination.hint = L10n.format_text("%s %d/%d", [label, have, need])
			return destination
	return _goal("nursery", L10n.format_text("Make %s for %s", [recipe.name, spec.name]), "hammer").merged({"hint": L10n.text("Ready to make"), "target": "workbench"})

static func project_available(state: Dictionary, id: String) -> bool:
	var spec: Dictionary = data().projects.get(id, {})
	return not spec.is_empty() and fact(state, str(spec.requires)) \
		and (spec.place != "bistro" or unlocked(state, "bistro"))

static func project_crop_needs(state: Dictionary, id: String) -> Dictionary:
	if not project_available(state, id) or project_complete(state, id): return {}
	var stage: Dictionary = data().projects[id].stages[project_stage(state, id)]
	var needs: Dictionary = stage.produce.duplicate(true)
	var recipes := recipes()
	for dish in stage.dishes:
		var missing := maxi(0, int(stage.dishes[dish]) - int(state.get("inventory", {}).get("dishes", {}).get(dish, 0)))
		for crop in recipes[dish].inputs:
			needs[crop] = int(needs.get(crop, 0)) + missing * int(recipes[dish].inputs[crop])
	return needs

static func project_goal(state: Dictionary, id: String, now_ms := -1) -> Dictionary:
	if not project_available(state, id) or project_complete(state, id): return {}
	var spec: Dictionary = data().projects[id]
	var stage: Dictionary = spec.stages[project_stage(state, id)]
	var goal := {}
	for item in stage.materials:
		var have := material(state, str(item))
		var need := int(stage.materials[item])
		if have >= need: continue
		goal = _material_goal(state, str(item))
		goal.hint = L10n.format_text("%s %d/%d", [L10n.text("Reeds") if item == "fiber" else str(item).capitalize(), have, need])
		break
	if goal.is_empty():
		var recipes := recipes()
		for dish in stage.dishes:
			if int(state.get("inventory", {}).get("dishes", {}).get(dish, 0)) >= int(stage.dishes[dish]): continue
			if recipes[dish].inputs.keys().all(func(crop): return available(state, str(crop)) >= int(recipes[dish].inputs[crop])):
				goal = _goal("bistro", L10n.format_text("Prepare %s", dish), "utensils").merged({"target": "counter", "hint": L10n.format_text("Prepare %s", str(dish).capitalize())})
				break
	if goal.is_empty():
		var candidates := []
		var needs := project_crop_needs(state, id)
		for crop in needs:
			if available(state, str(crop)) < int(needs[crop]):
				candidates.append(_crop_goal(state, str(crop), int(needs[crop]), now_ms))
		var order := {"harvest": 0, "care": 1, "gather": 2, "sow": 3, "stall": 4, "wait": 5}
		candidates.sort_custom(func(a, b): return order[a.action] < order[b.action])
		if not candidates.is_empty(): goal = candidates[0]
	if goal.is_empty():
		goal = _goal(str(spec.place), L10n.text(str(stage.name)), "hammer").merged({"target": "project_" + id, "hint": L10n.text("Ready to build")})
	goal.project = id
	goal.label = L10n.format_text("%s: %s", [spec.name, goal.get("hint", goal.label)])
	return goal

static func _crop_goal(state: Dictionary, crop: String, quantity: int, now_ms: int) -> Dictionary:
	var farm_cells: Array = state.get("cells", {}).values()
	var cells: Array = farm_cells.filter(func(cell): return cell.get("crop") == crop)
	var time := now_ms if now_ms >= 0 else int(state.get("clock", {}).get("last_effective_now", 0))
	var name := CropInfo.name_of(crop)
	var goal := _goal("farm", L10n.text("Grow ") + name, "sprout").merged({"crop": crop, "action": "sow", "hint": L10n.text("Grow ") + name})
	if cells.any(func(cell): return cell.get("state") == "growing" and cell.get("ready_at") != null and int(cell.ready_at) <= time):
		return goal.merged({"action": "harvest", "hint": L10n.text("Harvest ") + name}, true)
	if cells.any(func(cell): return cell.get("state") == "sown"):
		return goal.merged({"action": "care", "hint": L10n.text("Tend ") + name}, true)
	var harvest := discovery_supply_goal(state, "produce", crop)
	if not harvest.is_empty(): return goal.merged(harvest, true)
	if crop == "H" and unlocked(state, "crop_H") and project_complete(state, "seedbeds"):
		if not state.journey.exploration.collected.has("seedbeds"):
			return goal.merged({"place": "nursery", "target": "project_seedbeds", "action": "gather", "hint": L10n.text("Gather ") + name}, true)
		if route_ready(state, "woodland"):
			return goal.merged({"place": "nursery", "target": "trail", "action": "gather", "hint": L10n.text("Start a nursery trail for chamomile")}, true)
	var growing := cells.filter(func(cell): return cell.get("state") == "growing").size()
	if growing >= quantity - available(state, crop):
		return goal.merged({"action": "wait", "hint": name + L10n.text(" growing")}, true)
	if not farm_cells.is_empty() and not farm_cells.any(func(cell): return cell.get("state") in ["wild", "cleared", "tilled"]):
		if farm_cells.any(func(cell): return cell.get("state") == "growing" and cell.get("ready_at") != null and int(cell.ready_at) <= time):
			return goal.merged({"action": "harvest", "hint": L10n.text("Harvest to make room for ") + name}, true)
		if farm_cells.any(func(cell): return cell.get("state") == "sown"):
			return goal.merged({"action": "care", "hint": L10n.text("Tend the occupied beds")}, true)
		var supplies := discovery_supply_goal(state, "produce", crop, true)
		if not supplies.is_empty(): return goal.merged(supplies, true)
		return goal.merged({"action": "wait", "hint": L10n.text("Beds full; crops growing")}, true)
	var lot: Dictionary = state.get("inventory", {}).get("seeds", {}).get(crop, {})
	if int(lot.get("bound", 0)) + int(lot.get("bought", 0)) == 0:
		var seeds := discovery_supply_goal(state, "seeds", crop)
		if not seeds.is_empty(): return goal.merged(seeds, true)
		for kind in ["produce", "seeds"]:
			var supplies := discovery_supply_goal(state, kind, crop, true)
			if not supplies.is_empty(): return goal.merged(supplies, true)
		if int(state.get("wallet", 0)) < CropInfo.seed_price(crop):
			var earnings := seed_money_goal(state, crop)
			if not earnings.is_empty(): return goal.merged(earnings, true)
		return goal.merged({"action": "stall", "hint": L10n.text("Get ") + name + L10n.text(" seeds")}, true)
	return goal

static func seed_money_goal(state: Dictionary, crop: String) -> Dictionary:
	if not JourneyRequests.available(state, "restorer"): return {}
	var spec := offer(state, "restorer")
	var goal := _resident_goal("restorer", L10n.text("Earn for ") + CropInfo.name_of(crop) + L10n.text(" seeds"), "coins")
	goal.action = "gather"
	if material(state, "wood") < int(spec.wood):
		goal = _material_goal(state, "wood").merged({"action": "gather", "hint": L10n.format_text("Wood for seed money (%d/%d)", [material(state, "wood"), int(spec.wood)])}, true)
	elif not spec.produce.keys().all(func(id): return available(state, str(id)) >= int(spec.produce[id])) \
			or not spec.dishes.keys().all(func(id): return int(state.get("inventory", {}).get("dishes", {}).get(id, 0)) >= int(spec.dishes[id])):
		goal.hint = L10n.text("Ask for timber-only work")
		goal.change_request = "restorer"
	else:
		goal.hint = L10n.format_text("Deliver wood for seed money (+%d)", int(spec.coins))
	goal.label = str(goal.hint)
	return goal

static func discovery_supply_goal(state: Dictionary, kind: String, item: String, refresh := false) -> Dictionary:
	for id in data().discoveries:
		if not discovery_available(state, str(id)) or not fact(state, "discovery_" + str(id)): continue
		var spec: Dictionary = data().discoveries[id]
		for choice_id in spec.choices:
			var choice: Dictionary = spec.choices[choice_id]
			if int(choice.get(kind, {}).get(item, 0)) <= 0: continue
			if choice.has("requires") and not unlocked(state, str(choice.requires)): continue
			if discovery_harvest_ready(state, str(id)):
				return _goal(str(spec.place), L10n.text(str(choice.name)), "compass", "harvest:%s:%s" % [id, choice_id]).merged({
					"action": "gather", "hint": L10n.text("Gather ") + L10n.text(str(choice.name))})
			if not refresh: continue
			var remaining := remaining_nodes(state, str(spec.place))
			if not remaining.is_empty():
				return resource_goal(state, remaining[0], str(remaining[0].id)).merged({
					"action": "gather", "hint": L10n.text("Explore for ") + L10n.text(str(choice.name))})
			return _goal(str(spec.place), L10n.text("Revisit ") + L10n.text(str(spec.name)), "route", "trail").merged({
				"action": "gather", "hint": L10n.text("Revisit ") + L10n.text(str(spec.name))})
	return {}

static func _material_goal(state: Dictionary, item: String) -> Dictionary:
	var harvest := discovery_supply_goal(state, "materials", item)
	if not harvest.is_empty(): return harvest
	for node in remaining_nodes(state):
		var bundle := material_bundle(state, node, item)
		if not bundle.is_empty(): return resource_goal(state, node, str(bundle.id))
	if item != "wood" and project_complete(state, "waystation") and material(state, "wood") >= 2:
		return _goal("courtyard", L10n.text("Exchange timber"), "package-check").merged({"target": "project_waystation"})
	var route: Dictionary = data().routes[{"wood": "woodland", "stone": "riverside", "fiber": "gardens"}[item]]
	return _goal(str(route.place), L10n.text(str(route.name)), "compass").merged({"target": "trail"})

static func display_items(state: Dictionary, project: String) -> Array:
	return state.get("journey", {}).get("workshop", {}).get("displays", {}).get(project, ["", "", ""])

static func material(state: Dictionary, id: String) -> int:
	return _wood(state) if id == "wood" else int(state.get("journey", {}).get("materials", {}).get(id, 0))

static func node_materials(state: Dictionary, node: Dictionary) -> Dictionary:
	var result := {"wood": int(node.wood)}
	if node.place == "courtyard": result.stone = 1
	if node.place == "bistro": result.fiber = 1
	var route := route_for(state, str(node.place))
	if route.get("place") == node.place:
		result[route.material] = int(result.get(route.material, 0)) + int(route.bonus)
	return result

static func node_bundles(state: Dictionary, node: Dictionary) -> Array:
	var bundles := [{"id": str(node.id), "node": str(node.id), "choice": "primary", "position": node.position,
		"materials": node_materials(state, node)}]
	var alternative: Dictionary = node.get("alternative", {})
	if not alternative.is_empty() and state.get("journey", {}).get("exploration", {}).get("branching_places", []).has(node.place) \
			and fact(state, str(alternative.requires)):
		bundles.append({"id": "bundle:" + str(node.id), "node": str(node.id), "choice": "alternate",
			"position": alternative.position, "materials": alternative.materials})
	return bundles

static func material_bundle(state: Dictionary, node: Dictionary, item: String) -> Dictionary:
	var best := {}
	var amount := 0
	for bundle in node_bundles(state, node):
		var offered := int(bundle.materials.get(item, 0))
		if offered > amount:
			best = bundle
			amount = offered
	return best

static func bundle_hint(state: Dictionary, place: String) -> String:
	for node in remaining_nodes(state, place):
		if node_bundles(state, node).size() > 1:
			return L10n.text("Wood or reeds") if place == "bistro" else L10n.text("Wood or stone")
	return ""

static func material_label(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in ["wood", "stone", "fiber"]:
		if int(cost.get(id, 0)) > 0: parts.append(L10n.format_text("%d %s", [int(cost[id]), "reeds" if id == "fiber" else id]))
	return " + ".join(parts)

static func project_stage(state: Dictionary, id: String) -> int:
	var result := 0
	for index in data().projects[id].stages.size():
		if fact(state, "project_%s_%d" % [id, index]): result += 1
	return result

static func project_complete(state: Dictionary, id: String) -> bool:
	return project_stage(state, id) == data().projects[id].stages.size()

static func project_ready(state: Dictionary, id: String) -> bool:
	var spec: Dictionary = data().projects[id]
	if not fact(state, str(spec.requires)) or project_complete(state, id): return false
	var stage: Dictionary = spec.stages[project_stage(state, id)]
	for item in stage.materials:
		if material(state, str(item)) < int(stage.materials[item]): return false
	for crop in stage.produce:
		if available(state, str(crop)) < int(stage.produce[crop]): return false
	for dish in stage.dishes:
		if int(state.get("inventory", {}).get("dishes", {}).get(dish, 0)) < int(stage.dishes[dish]): return false
	return true

static func goals(state: Dictionary) -> Array:
	var complete: Array = state.get("journey", {}).get("completed", [])
	var out := []
	for milestone in data().milestones:
		out.append({"id": milestone.id, "label": milestone.name, "done": complete.has(milestone.id)})
	if fact(state, "planter_crafted"):
		for id in data().discoveries:
			out.append({"id": "discovery_" + str(id), "label": L10n.text("Restore ") + L10n.text(str(data().discoveries[id].name)), "done": fact(state, "discovery_" + str(id))})
		for id in data().workshop.recipes:
			var recipe: Dictionary = data().workshop.recipes[id]
			out.append({"id": "crafted_" + str(id), "label": L10n.text("Make ") + L10n.text(str(recipe.name)), "done": fact(state, "crafted_" + str(id))})
	if fact(state, "workbench"):
		for id in data().projects:
			out.append({"id": "project_" + str(id), "label": L10n.text(str(data().projects[id].name)), "done": project_complete(state, str(id))})
		for resident in data().stories:
			for story in data().stories[resident]:
				out.append({"id": "story_" + str(story.id), "label": story.name, "done": fact(state, "story_" + str(story.id))})
	if JourneyGatherings.available(state):
		for theme in JourneyGatherings.themes():
			out.append({"id": "gathering_" + str(theme), "label": L10n.text(str(JourneyGatherings.themes()[theme].name)), "done": JourneyGatherings.progress(state).get("memories", []).has(theme)})
	return out

static func next_goal(state: Dictionary, now_ms := -1) -> Dictionary:
	var tracked := tracked_goal(state, now_ms)
	if not tracked.is_empty(): return tracked
	if not fact(state, "met_nursery"): return _resident_goal("nursery_keeper", L10n.text("Meet the nursery keeper"), "users-round")
	if unlocked(state, "bistro") and not fact(state, "met_bistro"): return _resident_goal("bistro_owner", L10n.text("Meet the bistro host"), "utensils")
	var meal := first_meal_goal(state)
	if not meal.is_empty(): return meal
	if not fact(state, "workbench"):
		if _wood(state) >= int(data().costs.repair_workbench): return _goal("nursery", L10n.text("Repair the workbench"), "hammer", "workbench")
		return _wood_goal(state, L10n.text("the workbench"), int(data().costs.repair_workbench))
	if not fact(state, "planter_crafted"):
		if _wood(state) >= int(data().costs.craft_planter): return _goal("nursery", L10n.text("Make your first planter"), "hammer", "workbench")
		return _wood_goal(state, L10n.text("your first planter"), int(data().costs.craft_planter))
	if not fact(state, "planter_placed"): return _goal("courtyard", L10n.text("Find a spot for your planter"), "house", "planter")
	if fact(state, "shared_meal") and not fact(state, "side_path"):
		if _wood(state) >= int(data().costs.clear_side_path): return _goal("nursery", L10n.text("Open the garden side path"), "route", "path")
		return _wood_goal(state, L10n.text("the garden path"), int(data().costs.clear_side_path))
	if not fact(state, "planter_planted") and available(state, "H") > 0: return _goal("courtyard", L10n.text("Bring your planter to life"), "sprout", "planter")
	for id in data().discoveries:
		if discovery_ready(state, str(id)):
			return _goal(str(data().discoveries[id].place), L10n.text("Restore ") + L10n.text(str(data().discoveries[id].name)), "hammer", "discovery_" + str(id))
	for resident in data().stories:
		var story := next_story(state, str(resident))
		if not story.is_empty() and requirements_met(state, story) and cost_ready(state, story):
			return _resident_goal(str(resident), L10n.text(str(story.name)), "message-circle")
	for id in data().projects:
		if project_ready(state, str(id)):
			var project: Dictionary = data().projects[id]
			return _goal(str(project.place), L10n.text(str(project.stages[project_stage(state, str(id))].name)), "hammer", "project_" + str(id))
	if JourneyGatherings.available(state):
		for theme in JourneyGatherings.themes():
			if not JourneyGatherings.progress(state).get("memories", []).has(theme): return JourneyGatherings.venue_goal(str(theme))
	if project_complete(state, "seedbeds") and not state.journey.exploration.collected.has("seedbeds"):
		return _goal("nursery", L10n.text("Choose a nursery basket"), "sprout", "project_seedbeds")
	for id in data().workshop.recipes:
		var recipe: Dictionary = data().workshop.recipes[id]
		if not fact(state, "crafted_" + str(id)) and requirements_met(state, recipe) and cost_ready(state, recipe):
			return _goal("nursery", L10n.text("Make ") + L10n.text(str(recipe.name)), "hammer", "workbench")
	if not fact(state, "workshop_displayed") and data().workshop.recipes.keys().any(func(id): return stock(state, str(id)) > 0):
		for id in data().projects:
			if project_complete(state, str(id)): return _goal(str(data().projects[id].place), L10n.text("Display your handmade piece"), "flower-2", "project_" + str(id))
	for id in data().discoveries:
		if discovery_harvest_ready(state, str(id)):
			return _goal(str(data().discoveries[id].place), L10n.text("Choose a harvest at ") + L10n.text(str(data().discoveries[id].name)), "sprout", "discovery_" + str(id))
	for slot in ["bistro", "nursery", "restorer"]:
		if offer_ready(state, slot) and (slot != "bistro" or unlocked(state, "bistro")):
			return _resident_goal({"nursery": "nursery_keeper", "bistro": "bistro_owner", "restorer": "restorer"}[slot], L10n.text(str(offer(state, slot).name)), "package-check")
	return _gather_goal(state)

static func needed_crop(state: Dictionary, cells: Dictionary) -> String:
	var project := str(state.get("journey", {}).get("tracked_project", ""))
	var needs := project_crop_needs(state, project)
	if not JourneyGatherings.planned(state).is_empty(): needs = JourneyGatherings.crop_needs(state)
	if not JourneyRequests.tracked(state).is_empty(): needs = JourneyRequests.crop_needs(state)
	var missing := ""
	for crop in needs:
		var planted := cells.values().filter(func(cell): return cell.get("crop") == crop and cell.get("state") in ["sown", "growing"]).size()
		if available(state, str(crop)) + planted >= int(needs[crop]): continue
		if missing.is_empty(): missing = str(crop)
		var lot: Dictionary = state.get("inventory", {}).get("seeds", {}).get(crop, {})
		if int(lot.get("bound", 0)) + int(lot.get("bought", 0)) > 0: return str(crop)
	if not missing.is_empty(): return missing
	var wanted := ["C", "L"] if unlocked(state, "kitchen") and not fact(state, "shared_meal") else (["H"] if unlocked(state, "crop_H") and not fact(state, "planter_planted") else [])
	for crop in wanted:
		if available(state, crop) > 0: continue
		if cells.values().any(func(cell): return cell.get("crop") == crop and cell.get("state") in ["sown", "growing"]): continue
		return crop
	return ""

static func first_meal_goal(state: Dictionary) -> Dictionary:
	if fact(state, "shared_meal") or not unlocked(state, "kitchen"): return {}
	var prepared := int(state.get("inventory", {}).get("dishes", {}).get("salad", 0)) > 0
	if not prepared and (available(state, "C") < 1 or available(state, "L") < 1): return {}
	if not fact(state, "met_bistro"): return _resident_goal("bistro_owner", L10n.text("Meet the bistro host"), "utensils")
	if prepared:
		return _goal("bistro", L10n.text("Share your first meal"), "utensils", "table")
	return _goal("bistro", L10n.text("Prepare a fresh salad"), "utensils", "counter")

static func farm_hint(state: Dictionary, now_ms := -1) -> String:
	var ripe := 0
	var care := 0
	var growing := false
	for cell in state.get("cells", {}).values():
		if cell.get("state") == "sown": care += 1
		if cell.get("state") != "growing": continue
		growing = true
		var ready = cell.get("ready_at")
		if now_ms >= 0 and (ready is int or ready is float) and ready > 0 and ready <= now_ms:
			ripe += 1
	if ripe > 0: return L10n.format_text("%d ready", ripe)
	if care > 0: return L10n.text("Needs care")
	return L10n.text("Growing") if growing else ""

static func _wood(state: Dictionary) -> int:
	return int(state.get("journey", {}).get("wood", 0))

static func _goal(place: String, label: String, icon: String, target := "") -> Dictionary:
	var goal := {"place": place, "label": L10n.text(label), "icon": icon}
	if not target.is_empty(): goal.target = target
	return goal

static func goal_label(goal: Dictionary) -> String:
	var destination := L10n.text(str(ResidentCast.definition(str(goal.resident)).name)) if goal.has("resident") else str({"farm": L10n.text("My farm"), "nursery": L10n.text("Nursery"), "bistro": L10n.text("Bistro"), "courtyard": L10n.text("Courtyard")}.get(goal.get("place", ""), ""))
	if goal.get("surface") == "street": destination = L10n.text("Neighbourhood") if goal.has("gathering") else L10n.text("Stone walk")
	return L10n.format_text("%s: %s", [destination, goal.label]) if not destination.is_empty() else L10n.text(str(goal.get("label", "")))

static func _resident_goal(resident: String, label: String, icon: String) -> Dictionary:
	var place: String = {"nursery_keeper": "nursery", "bistro_owner": "bistro", "restorer": "courtyard"}[resident]
	return _goal(place, label, icon).merged({"resident": resident, "target": "resident"})

static func _wood_goal(state: Dictionary, purpose: String, quantity: int) -> Dictionary:
	var goal := _material_goal(state, "wood")
	goal.label = L10n.format_text("Wood for %s (%d/%d)", [purpose, _wood(state), quantity])
	return goal

static func _gather_goal(state: Dictionary) -> Dictionary:
	var remaining := remaining_nodes(state)
	for id in data().projects:
		var project: Dictionary = data().projects[id]
		if not fact(state, str(project.requires)) or project_complete(state, str(id)): continue
		var stage: Dictionary = project.stages[project_stage(state, str(id))]
		for item in stage.materials:
			if material(state, str(item)) >= int(stage.materials[item]): continue
			for node in remaining:
				var bundle := material_bundle(state, node, str(item))
				if not bundle.is_empty():
					return resource_goal(state, node, str(bundle.id), L10n.format_text("Collect %s for %s", [material_label(bundle.materials), project.name]))
	if not remaining.is_empty(): return resource_goal(state, remaining[0], str(remaining[0].id), L10n.text("Gather neighbourhood supplies"))
	return _goal("courtyard", L10n.text("Explore another route"), "compass", "trail")

static func available(state: Dictionary, crop: String) -> int:
	return maxi(0, int(state.get("inventory", {}).get("produce", {}).get(crop, 0)) \
		- int(state.get("engineering", {}).get("reserved", {}).get(crop, 0)))

static func offer(state: Dictionary, slot: String) -> Dictionary:
	var progress: Dictionary = state.get("journey", {}).get("opportunities", {}).get(slot, {})
	var variants: Array = data().opportunities.get(slot, [])
	var index := int(progress.get("variant", -1))
	return variants[index] if index >= 0 and index < variants.size() else {}

static func offer_ready(state: Dictionary, slot: String) -> bool:
	var spec := offer(state, slot)
	if spec.is_empty() or _wood(state) < int(spec.wood): return false
	for crop in spec.produce:
		if available(state, str(crop)) < int(spec.produce[crop]): return false
	for dish in spec.dishes:
		if int(state.get("inventory", {}).get("dishes", {}).get(dish, 0)) < int(spec.dishes[dish]): return false
	return true

static func place_hint(state: Dictionary, place: String) -> String:
	if place == "bistro" and not unlocked(state, "bistro"): return L10n.text("First harvest")
	var tracked := tracked_goal(state)
	if tracked.get("place") == place: return str(tracked.hint)
	for id in data().discoveries:
		if data().discoveries[id].place != place: continue
		if discovery_ready(state, str(id)): return L10n.text("Ready to restore")
	var resident: String = {"nursery": "nursery_keeper", "bistro": "bistro_owner", "courtyard": "restorer"}.get(place, "")
	var story := next_story(state, resident)
	if not story.is_empty() and requirements_met(state, story) and cost_ready(state, story): return L10n.text("New story")
	for id in data().projects:
		if data().projects[id].place == place and project_ready(state, str(id)): return L10n.text("Ready to build")
	if street_supplies(state, place) and not remaining_nodes(state, place).is_empty():
		var stops := remaining_nodes(state, place).size()
		return L10n.count_text("Stone walk: %d stop", "Stone walk: %d stops", stops)
	for id in data().discoveries:
		if data().discoveries[id].place == place and discovery_harvest_ready(state, str(id)): return L10n.text("Harvest choice")
	var bundles := bundle_hint(state, place)
	if not bundles.is_empty(): return bundles
	var count := remaining_nodes(state, place).size()
	if count > 0: return L10n.format_text("%s %d", [{"nursery": L10n.text("Timber"), "courtyard": L10n.text("Stone"), "bistro": L10n.text("Reeds")}[place], count])
	var slot := "restorer" if place == "courtyard" else place
	if StreetCommons.available(state, slot) and offer_ready(state, slot): return L10n.text("Street work ready")
	var contribution := 0
	for spec in data().opportunities.get(slot, []): contribution += StreetCommons.count(state, str(spec.effect))
	if contribution > 0: return L10n.format_text("Street garden %d/%d", [contribution, int(data().contribution_steps) * 2])
	for id in data().projects:
		if data().projects[id].place == place and display_items(state, str(id)).any(func(item): return not str(item).is_empty()): return L10n.text("Handmade garden")
	return L10n.text("Trail ready")
