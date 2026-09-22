class_name JourneyActivityPanel
extends SessionPanel

signal arrangement_requested()
signal display_arrangement_requested(project: String)
signal display_plan_changed()
signal target_requested(target_id: String)
signal goal_requested(goal: Dictionary)
signal meal_served(dish: String)
signal terrace_served(dish: String)
signal contribution_completed(slot: String, effect: String)
signal resident_interaction_completed(resident_id: String)
signal requests_requested()

var target := ""
var place_id := ""
var _requests_expanded := false
var _request_confirmation: Dictionary = {}
var prefer_timber_only := false
const RESIDENTS := {"nursery": "nursery_keeper", "bistro": "bistro_owner", "courtyard": "restorer"}

func _render() -> void:
	if target.begins_with("street_offer:"):
		var slot := target.trim_prefix("street_offer:")
		heading(L10n.text(str(ResidentCast.definition(StreetCommons.RESIDENTS[slot]).name)))
		_offer(slot)
		return
	if target.begins_with("display:"):
		var parts := target.split(":")
		_display(str(parts[1]), int(parts[2]))
		return
	if target.begins_with("resident:"):
		_resident(target.trim_prefix("resident:"))
		return
	if target.begins_with("discovery_"):
		_discovery(target.trim_prefix("discovery_"))
		return
	if target.begins_with("project_"):
		_project(target.trim_prefix("project_"))
		return
	match target:
		"supplies": _supplies()
		"trail": _trail()
		"resident": _resident()
		"workbench": _workbench()
		"counter": _kitchen()
		"table":
			heading(L10n.text("A seat at the table"))
			if JourneyProgress.fact(state(), "shared_meal"):
				paragraph(L10n.text("The host remembers your first salad. There is always a place for you here."))
				_offer("bistro")
			else:
				paragraph(L10n.text("One freshly made salad for a meal together."))
				action("utensils", L10n.text("Share a salad"), func(): _activity("share_meal", L10n.text("Your first meal together. Chamomile seeds are in your bag.")),
					JourneyProgress.fact(state(), "met_bistro") and int(state().inventory.dishes.get("salad", 0)) > 0, true)
		"path":
			heading(L10n.text("The garden side path"))
			if JourneyProgress.fact(state(), "side_path"):
				paragraph(L10n.text("The nursery has a new entrance. More timber lies along the path."))
				action("route", L10n.text("Walk to the courtyard"), func(): destination_requested.emit("courtyard"), true, true)
			else:
				paragraph(L10n.format_text("Make a planter and share a meal with the host, then repair the path with %d wood.", int(JourneyProgress.data().costs.clear_side_path)))
				action("route", L10n.text("Open the side path"), func(): _activity("clear_side_path", L10n.text("A new path through the neighbourhood.")),
					JourneyProgress.fact(state(), "planter_crafted") and JourneyProgress.fact(state(), "shared_meal") \
					and _wood() >= int(JourneyProgress.data().costs.clear_side_path), true)
		"planter":
			heading(L10n.text("Your courtyard"))
			if DecorationLayout.unlocked(state()):
				action("move", L10n.text("Arrange your pieces"), func(): arrangement_requested.emit(), true, true)
			else: paragraph(L10n.text("A handmade planter will fit beside this path."))
			if JourneyProgress.fact(state(), "planter_placed") and not JourneyProgress.fact(state(), "planter_planted"):
				paragraph(L10n.format_text("Chamomile %d / 1", available("H")))
				action("sprout", L10n.text("Plant chamomile"), func(): _activity("plant_planter", L10n.text("Your planter is in bloom.")), available("H") > 0, true)
		"board":
			for route_id in JourneyProgress.data().routes:
				var route: Dictionary = JourneyProgress.data().routes[route_id]
				if route.has("requires") and not JourneyProgress.unlocked(state(), str(route.requires)): continue
				if route_id == "neighbourhood": continue
				var remaining := JourneyProgress.remaining_nodes(state(), str(route.place)).size()
				var label := L10n.text(str(route.name)) + (L10n.format_text(" (%d left)", remaining) if remaining > 0 else "")
				action("compass", label, func(): _next_route(str(route_id)), JourneyProgress.route_ready(state(), str(route_id)), true)
			for place in PlaceCatalog.all():
				var count := JourneyProgress.remaining_nodes(state(), str(place.id)).size()
				if PlaceCatalog.available(str(place.id), state()) and count > 0:
					paragraph(L10n.format_text("%s: %d supplies", [place.name, count]))

signal destination_requested(place: String)
signal world_action_completed(target_id: String)

func _trail() -> void:
	var route_id: String = {"nursery": "woodland", "courtyard": "riverside", "bistro": "gardens"}[place_id]
	if JourneyProgress.street_supplies(state(), place_id) and not JourneyProgress.remaining_nodes(state(), place_id).is_empty():
		heading(L10n.text(str(JourneyProgress.route_for(state(), place_id).name)))
		var stops := JourneyProgress.remaining_nodes(state(), place_id).size()
		paragraph(L10n.count_text("%d stop left: stone or timber", "%d stops left: stone or timber", stops))
		action("route", L10n.text("Continue the stone walk"), func(): destination_requested.emit("street"), true, true)
		return
	var choice := place_id == "bistro" and JourneyProgress.unlocked(state(), "crafting")
	heading(L10n.text("Bistro paths") if choice else L10n.text(str(JourneyProgress.data().routes[route_id].name)))
	paragraph(L10n.text("Reeds nearby. Stone along the streets.") if choice else {"nursery": L10n.text("Fallen timber along the nursery path."), "courtyard": L10n.text("Loose stone along the courtyard path."), "bistro": L10n.text("Fresh reeds along the bistro path.")}[place_id])
	action("route", L10n.text("Take the reed trail") if choice else L10n.text("Explore this trail"), func(): _next_route(route_id), JourneyProgress.route_ready(state(), route_id), true)
	if choice:
		action("route", L10n.text("Take the stone walk"), func(): _next_route("stone_walk"), JourneyProgress.route_ready(state(), "stone_walk"), true)

func _supplies() -> void:
	var inventory: Dictionary = state().get("inventory", {})
	heading(L10n.text("Seeds and harvest"))
	for crop in CropInfo.ORDER:
		var seeds := NextStep.seeds_of(inventory, str(crop))
		var harvest := int(inventory.get("produce", {}).get(crop, 0))
		if not JourneyProgress.crops(state()).has(crop) and seeds == 0 and harvest == 0: continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(GameUi.picture(GameUi.crop_art(str(crop)), 36))
		var label := GameUi.label(L10n.format_text("%s\n%s / %d harvested", [CropInfo.name_of(str(crop)), L10n.count_text("%d seed", "%d seeds", seeds), harvest]), 13)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		append_content(row)
		var reserved := maxi(0, harvest - available(str(crop)))
		if reserved > 0: paragraph(L10n.format_text("%d reserved", reserved))
	append_content(HSeparator.new())
	heading(L10n.text("Materials"))
	for item in JourneyProgress.materials(state()):
		paragraph(L10n.format_text("%s: %d", [L10n.material_name(str(item)), JourneyProgress.material(state(), str(item))]))
	if JourneyProgress.unlocked(state(), "kitchen"):
		append_content(HSeparator.new())
		heading(L10n.text("Meals"))
		for dish in JourneyProgress.recipes():
			var count := int(inventory.get("dishes", {}).get(dish, 0))
			if dish == "tea" and not JourneyProgress.unlocked(state(), "crop_H") and count == 0: continue
			paragraph(L10n.format_text("%s: %d", [L10n.dish_name(str(dish)), count]))
	var pieces: Array[String] = []
	for item in JourneyProgress.data().workshop.recipes:
		var count := JourneyProgress.stock(state(), str(item))
		if count > 0: pieces.append(L10n.format_text("%s: %d", [L10n.text(str(JourneyProgress.data().workshop.recipes[item].name)), count]))
	if not pieces.is_empty():
		append_content(HSeparator.new())
		heading(L10n.text("Stored pieces"))
		for piece in pieces: paragraph(piece)

func _discovery(id: String) -> void:
	var spec: Dictionary = JourneyProgress.data().discoveries[id]
	heading(L10n.text(str(spec.name)))
	if not JourneyProgress.fact(state(), "discovery_" + id):
		paragraph(str(spec.benefit))
		if not JourneyProgress.discovery_available(state(), id):
			paragraph(str(spec.hint))
			paragraph({"stone_hollow": L10n.text("Open the garden side path first."), "reed_garden": L10n.text("Place your first planter and meet the bistro host."), "kitchen_garden": L10n.text("Share your first meal and make a garden lantern.")}[id])
			return
		var recipe: Dictionary = JourneyProgress.data().workshop.recipes[spec.item]
		paragraph(L10n.format_text("%s %d/1", [recipe.name, JourneyProgress.stock(state(), str(spec.item))]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		append_content(row)
		var install := action("hammer", L10n.text("Install ") + L10n.text(str(recipe.name)), func():
			if await _workshop_command("install_journey_discovery", {"discovery": id}, L10n.text(str(spec.name)) + L10n.text(" is restored.")):
				world_action_completed.emit(target), JourneyProgress.discovery_ready(state(), id), true)
		install.text = L10n.text("Install")
		install.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		install.reparent(row)
		var tracked: bool = state().journey.get("tracked_discovery", "") == id
		var track := action("compass", L10n.text("Stop tracking") if tracked else L10n.text("Track this corner"), func():
			if await command("track_journey_discovery", {"discovery": "" if tracked else id}, ""):
				world_action_completed.emit(target))
		track.text = ""
		track.toggle_mode = true
		track.button_pressed = tracked
		track.reparent(row)
		return
	var ready := JourneyProgress.discovery_harvest_ready(state(), id)
	if not ready:
		var previous := str(state().journey.get("discovery_choices", {}).get(id, ""))
		if spec.choices.has(previous): paragraph(L10n.format_text("Gathered: %s", JourneyProgress.discovery_reward_label(spec.choices[previous])))
		var route_id: String = {"nursery": "woodland", "courtyard": "riverside", "bistro": "gardens"}[spec.place]
		var remaining := JourneyProgress.remaining_nodes(state(), str(spec.place)).size()
		if remaining > 0: paragraph(L10n.format_text("%d supplies remain on this trail.", remaining))
		action("route", L10n.format_text("Start another %s trail", spec.place), func(): _next_route(route_id), JourneyProgress.route_ready(state(), route_id), true)
		return
	paragraph(L10n.text("One harvest this trail"))
	for choice_id in spec.choices:
		var choice: Dictionary = spec.choices[choice_id]
		if choice.has("requires") and not JourneyProgress.unlocked(state(), str(choice.requires)): continue
		action("sprout", JourneyProgress.discovery_reward_label(choice), func():
			if await command("harvest_journey_discovery", {"discovery": id, "choice": choice_id, "round": int(state().journey.exploration.round)}, L10n.text(str(choice.name)) + L10n.text(" gathered.")):
				world_action_completed.emit(target), true, true)

func _project(id: String) -> void:
	var spec: Dictionary = JourneyProgress.data().projects[id]
	var title := heading(L10n.text(str(spec.name)))
	if JourneyProgress.project_complete(state(), id):
		content.add_theme_constant_override("separation", 4)
		var row := HBoxContainer.new()
		append_content(row)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.reparent(row)
		var arrange := action("move", L10n.text("Arrange handmade pieces"), func(): display_arrangement_requested.emit(id))
		arrange.text = ""
		arrange.reparent(row)
	var index := JourneyProgress.project_stage(state(), id)
	if not JourneyProgress.fact(state(), str(spec.requires)):
		paragraph({"workbench": L10n.text("Repair the workbench to start these beds."), "shared_meal": L10n.text("Share your first meal with the host."), "side_path": L10n.text("Open the garden side path to reach this supply stop.")}.get(spec.requires, L10n.text("More to discover.")))
		return
	if not JourneyProgress.project_complete(state(), id):
		var stage: Dictionary = spec.stages[index]
		var title_row := HBoxContainer.new()
		append_content(title_row)
		title_row.get_parent().move_child(title_row, 0)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.reparent(title_row)
		var tracked: bool = state().journey.get("tracked_project", "") == id
		var track := action("compass", L10n.text("Stop tracking project") if tracked else L10n.text("Track this project"), func():
			if await command("track_journey_project", {"project": "" if tracked else id}, ""):
				world_action_completed.emit(target))
		track.name = "TrackProject"
		track.text = ""
		track.toggle_mode = true
		track.button_pressed = tracked
		track.reparent(title_row)
		paragraph(str(spec.benefit))
		_cost(stage)
		action("hammer", L10n.text(str(stage.name)), func():
			if await command("build_journey_project", {"project": id, "stage": index}, L10n.text(str(stage.name))):
				world_action_completed.emit("project_" + id), JourneyProgress.project_ready(state(), id), true)
		return
	match id:
		"seedbeds":
			var ready: bool = not state().journey.exploration.collected.has("seedbeds")
			if not ready: paragraph(L10n.text("The next basket will be ready after a new nursery trail."))
			for option in [["lettuce", L10n.text("Two lettuce seeds"), "L"], ["carrots", L10n.text("Two carrot seeds"), "C"], ["flowers", L10n.text("Fresh chamomile"), "H"]]:
				if option[2] != "L" and not JourneyProgress.unlocked(state(), "crop_" + str(option[2])): continue
				action("sprout", str(option[1]), func(): _use_facility(id, str(option[0])), ready, true)
		"terrace":
			paragraph(L10n.text("The neighbours are gathering at the shaded table."))
			for dish in ["salad", "tea"]:
				action("utensils", L10n.format_text("Serve %s - %d coins", [dish, 30 if dish == "salad" else 24]), func(): _use_facility(id, dish), int(state().inventory.dishes.get(dish, 0)) > 0, true)
		"waystation":
			for item in ["stone", "fiber"]:
				action("package-check", L10n.format_text("2 wood for 2 %s", ("reeds" if item == "fiber" else item)), func(): _use_facility(id, item), _wood() >= 2)
			action("route", L10n.text("Walk to the nursery"), func(): destination_requested.emit("nursery"), true, true)

func _cost(spec: Dictionary) -> Label:
	var needs: Array[String] = []
	for item in spec.get("materials", {}): needs.append(L10n.format_text("%s %d/%d", [L10n.material_name(str(item)), JourneyProgress.material(state(), str(item)), int(spec.materials[item])]))
	for crop in spec.get("produce", {}): needs.append(L10n.format_text("%s %d/%d", [CropInfo.name_of(str(crop)), available(str(crop)), int(spec.produce[crop])]))
	for dish in spec.get("dishes", {}): needs.append(L10n.format_text("%s %d/%d", [L10n.dish_name(str(dish)), int(state().inventory.dishes.get(dish, 0)), int(spec.dishes[dish])]))
	return paragraph(" / ".join(needs))

func _workshop_command(type: String, payload: Dictionary, success: String) -> bool:
	payload.sequence = int(state().journey.get("workshop", {}).get("sequence", 0))
	var had_tea := not CharacterModel.active_buff(state(), "tea").is_empty()
	var accepted := await command(type, payload, success)
	if accepted and type == "craft_journey_item": _crafting_feedback(had_tea)
	return accepted

func _crafting_feedback(had_tea: bool) -> void:
	if not is_inside_tree() or session == null: return
	var savings := {}
	for event in session.last_command_events:
		if event.get("type") not in ["world_changed", "workshop_changed", "equipment_crafted"]: continue
		var saved = event.get("actual_saved", {})
		if not saved is Dictionary: continue
		for item in CharacterModel.BASIC_MATERIALS:
			var quantity := maxi(0, int(saved.get(item, 0)))
			if quantity > 0: savings[item] = int(savings.get(item, 0)) + quantity
	if savings.is_empty(): return
	message.text += "\n" + L10n.format_text("Saved: %s", JourneyProgress.material_label(savings))
	if had_tea:
		message.text += " / " + L10n.format_text("Tea: %d uses left", int(CharacterModel.active_buff(state(), "tea").get("remaining_uses", 0)))

func _display(project: String, slot: int) -> void:
	var items := JourneyProgress.display_items(state(), project)
	if slot < 0 or slot >= items.size(): return
	var current := str(items[slot])
	var title := heading(L10n.text(str(JourneyProgress.data().workshop.recipes[current].name)) if not current.is_empty() else L10n.text("Empty display"))
	var row := HBoxContainer.new()
	append_content(row)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.reparent(row)
	var planned_item := JourneyWorkshop.preview_item(state(), project, slot)
	if not planned_item.is_empty():
		var cancel := action("x", L10n.text("Cancel handmade plan"), func(): _plan_display(project, slot, ""))
		cancel.text = ""
		cancel.reparent(row)
		paragraph(L10n.text("Planned: ") + L10n.text(str(JourneyProgress.data().workshop.recipes[planned_item].name)))
	if not current.is_empty():
		var take := action("backpack", L10n.text("Return piece to bag"), func():
			if await _workshop_command("display_journey_item", {"project": project, "slot": slot, "item": ""}, L10n.text("Your piece is back in your bag.")):
				world_action_completed.emit(target))
		take.text = ""
		take.reparent(row)
	var has_stock := false
	for item in JourneyProgress.data().workshop.recipes:
		var amount := JourneyProgress.stock(state(), str(item))
		if amount <= 0 or item == current: continue
		has_stock = true
		action("plus", L10n.format_text("%s (%d)", [JourneyProgress.data().workshop.recipes[item].name, amount]), func():
			if await _workshop_command("display_journey_item", {"project": project, "slot": slot, "item": item}, L10n.text("Your handmade piece is in place.")):
				world_action_completed.emit(target))
	if current.is_empty():
		for item in JourneyProgress.data().workshop.recipes:
			var recipe := CharacterModel.craft_recipe(state(), JourneyProgress.data().workshop.recipes[item])
			if JourneyProgress.stock(state(), str(item)) > 0 or not JourneyProgress.requirements_met(state(), recipe): continue
			_cost(recipe)
			action("hammer", L10n.text("Plan ") + L10n.text(str(recipe.name)), func(): _plan_display(project, slot, str(item)), item != planned_item)
	elif not has_stock:
		action("hammer", L10n.text("Nursery workbench"), func(): destination_requested.emit("nursery"))

func _plan_display(project: String, slot: int, item: String) -> void:
	var success := L10n.text("Handmade plan cancelled.") if item.is_empty() else L10n.text(str(JourneyProgress.data().workshop.recipes[item].name)) + L10n.text(" planned.")
	if await _workshop_command("plan_journey_display", {"project": project, "slot": slot, "item": item}, success):
		display_plan_changed.emit()
		world_action_completed.emit(target)

func _use_facility(id: String, choice: String) -> void:
	var sequence := int(state().journey.get("facility_uses", {}).get(id, 0))
	var success := L10n.format_text("%s shared at the terrace. +%d coins", [L10n.text("Salad") if choice == "salad" else L10n.text("Tea"), 30 if choice == "salad" else 24]) if id == "terrace" else L10n.text("Ready.")
	if id == "waystation": success = L10n.format_text("-2 wood / +2 %s", "reeds" if choice == "fiber" else "stone")
	elif id == "seedbeds": success = {"lettuce": L10n.text("+2 Lettuce seeds"), "carrots": L10n.text("+2 Carrot seeds"), "flowers": L10n.text("+1 Chamomile")}.get(choice, success)
	if await command("use_journey_facility", {"project": id, "choice": choice, "sequence": sequence}, success):
		world_action_completed.emit("project_" + id)
		if id == "terrace": terrace_served.emit(choice)

func _wood() -> int:
	return int(state().get("journey", {}).get("wood", 0))

func _activity(id: String, success: String) -> void:
	var had_tea := not CharacterModel.active_buff(state(), "tea").is_empty()
	if await command("journey_action", {"action": id}, success):
		if id == "craft_planter": _crafting_feedback(had_tea)
		world_action_completed.emit(target)
		if id == "share_meal": meal_served.emit("salad")

func _next_route(id: String) -> void:
	if await command("next_exploration", {"round": int(state().journey.exploration.round), "route": id}, L10n.text("New supplies along the neighbourhood paths.")):
		if JourneyProgress.data().routes[id].get("surface") == "street": destination_requested.emit("street")
		elif JourneyProgress.data().routes[id].place == place_id: world_action_completed.emit(target)
		else: destination_requested.emit(str(JourneyProgress.data().routes[id].place))

func _resident(resident_id := "") -> void:
	var id := str(RESIDENTS[place_id]) if resident_id.is_empty() else resident_id
	heading(str(ResidentCast.definition(id).get("name", L10n.text("Neighbour"))))
	paragraph(L10n.text(str(ResidentCast.definition(id).get("profile", ""))))
	var board := action("list-checks", L10n.text("Neighbourhood requests"), func(): requests_requested.emit())
	board.name = "OpenRequestBoard"
	var resident: Dictionary = state().get("residents", {}).get(id, {})
	var opening_nursery := id == "nursery_keeper" and not JourneyProgress.fact(state(), "workbench")
	if not opening_nursery or _requests_expanded:
		paragraph(L10n.format_text("%s / %d friendship", [ResidentCast.relationship_stage(resident), int(resident.get("points", 0))]))
	var story := JourneyProgress.next_story(state(), id)
	var story_ready := not story.is_empty() and JourneyProgress.requirements_met(state(), story) and JourneyProgress.cost_ready(state(), story)
	var repeat_meal := id == "bistro_owner" and JourneyProgress.fact(state(), "shared_meal")
	var at_gathering := place_id == "street" and not JourneyGatherings.current(state()).is_empty()
	if repeat_meal and not story_ready and not at_gathering: _offer("bistro")
	var quote := L10n.text("There is good wood along the paths. We could put that old workbench back together.")
	if id == "bistro_owner": quote = L10n.text("A carrot and a lettuce make a lovely salad. Bring one to our table when it is ready.")
	if id == "restorer": quote = L10n.text("Put something you made beside the path. A little corner can feel like home.")
	for completed_story in JourneyProgress.data().stories[id]:
		if JourneyProgress.fact(state(), "story_" + str(completed_story.id)): quote = str(completed_story.quote)
	if at_gathering: quote = JourneyGatherings.resident_quote(state(), id)
	if not story.is_empty() and JourneyProgress.requirements_met(state(), story):
		paragraph(str(story.hint))
		_cost(story)
		action("message-circle", L10n.text(str(story.name)), func():
			if await command("complete_journey_story", {"resident_id": id, "story": story.id}, str(story.quote)):
				resident_interaction_completed.emit(id), JourneyProgress.cost_ready(state(), story), true)
	else:
		paragraph(quote)
	var slot: String = {"nursery_keeper": "nursery", "bistro_owner": "bistro", "restorer": "restorer"}[id]
	if id == "bistro_owner" and not JourneyProgress.fact(state(), "shared_meal"):
		if place_id != "bistro":
			action("utensils", L10n.text("Meet at the bistro"), func(): destination_requested.emit("bistro"), true, true)
		elif int(state().inventory.dishes.get("salad", 0)) > 0:
			action("utensils", L10n.text("Take a seat at the table"), func(): target_requested.emit("table"), true, true)
		else:
			var recipes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/recipes.json")).recipes
			_cost({"produce": recipes.salad.inputs})
			action("utensils", L10n.text("Visit the prep counter"), func(): target_requested.emit("counter"), true, true)
	elif opening_nursery and not at_gathering:
		if place_id == "nursery":
			action("hammer", L10n.text("Inspect the workbench"), func(): target_requested.emit("workbench"), true, true)
		else:
			action("hammer", L10n.text("Visit the nursery"), func(): destination_requested.emit("nursery"), true, true)
		if _requests_expanded: _offer(slot)
		else:
			action("message-circle", L10n.text("Anything else you need?"), func():
				_requests_expanded = true
				refresh())
	elif (not repeat_meal or story_ready) and not at_gathering:
		_offer(slot)
	if JourneyProgress.unlocked(state(), "gifts"):
		var gift_ready := JourneyProgress.gift_ready(state(), id)
		if not gift_ready: paragraph(L10n.text("Your gift is remembered. Next gift after a new trail."))
		var relationships: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/relationships.json"))
		var clues: Array = relationships.gift_clues.get(id, [])
		for crop in clues:
			if available(str(crop)) > 0:
				action("gift", L10n.format_text("Give a %s", CropInfo.name_of(str(crop))), func():
					if await command("give_gift", {"resident_id": id, "crop": crop}, L10n.text("A gift remembered.")):
						resident_interaction_completed.emit(id), gift_ready)
	if id == "restorer" and JourneyProgress.unlocked(state(), "growth") and not at_gathering:
		var economy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/economy.json"))
		for choice in ["tool", "field"]:
			var price := int(economy.growth_choice[choice].price)
			if choice == "field":
				for crop in economy.growth_choice.field.seed_basket: price += int(economy.growth_choice.field.seed_basket[crop]) * CropInfo.seed_price(str(crop))
			var owned := bool(state().tools.row_tool) if choice == "tool" else int(state().beds_unlocked) == 4
			action("shovel", L10n.format_text("%s - %d coins", [L10n.text("Row tools") if choice == "tool" else L10n.text("Another garden bed & seeds"), price]),
				func(): command("purchase_growth_choice", {"choice": choice, "transaction_id": str(Time.get_ticks_usec())}, L10n.text("Your farm has room for more.")),
				not owned and int(state().wallet) >= price)

func _offer(slot: String) -> void:
	var spec := JourneyProgress.offer(state(), slot)
	if spec.is_empty(): return
	var title := heading(L10n.text(str(spec.name)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	append_content(row)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.reparent(row)
	var sequence := int(state().journey.opportunities[slot].sequence)
	var available := JourneyRequests.available(state(), slot)
	var accepted := JourneyRequests.accepted(state(), slot)
	var tracked: bool = JourneyRequests.tracked(state()).get("slot") == slot
	var track := action("compass", L10n.text("Stop tracking request") if tracked else L10n.text("Track request"), func():
		await _track_offer(slot, sequence, not tracked), available and accepted, tracked)
	track.name = "TrackRequest_" + slot
	track.text = ""
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.reparent(row)
	paragraph(JourneyRequests.status(state(), slot))
	paragraph(L10n.text(str(spec.get("description", ""))))
	paragraph(StreetCommons.progress(state(), str(spec.effect)))
	var needs := JourneyRequests.requirements(state(), slot)
	for id in needs:
		var need_row := HBoxContainer.new()
		need_row.add_theme_constant_override("separation", 8)
		need_row.add_child(GameUi.picture(ItemCatalog.texture(str(id)), 32))
		var label := GameUi.label(L10n.format_text("%s %d/%d", [ItemCatalog.name_of(str(id)), JourneyRequests.quantity(state(), str(id)), int(needs[id])]), 13)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		need_row.add_child(label)
		append_content(need_row)
	paragraph(L10n.format_text("Reward: %d coins", int(spec.coins)))
	var previous := JourneyRequests.last_reply(state(), slot)
	if not previous.is_empty(): paragraph(L10n.text("Last delivery") + ": " + previous)
	if not available:
		paragraph(L10n.text("Share your first meal with the host first." if slot == "bistro" else "Discover more of the neighbourhood first."))
		return
	if not _request_confirmation.is_empty() and _request_confirmation.slot == slot:
		paragraph(L10n.text("Abandon this request?" if _request_confirmation.type == "abandon_opportunity" else "Replace this request?"))
		paragraph(L10n.text("Your items stay in your bag."))
		action("check", L10n.text("Confirm"), func(): _request_action(str(_request_confirmation.type), slot, int(_request_confirmation.sequence), bool(_request_confirmation.get("timber_only", false))), true, true).name = "ConfirmNpcRequestChange"
		action("x", L10n.text("Cancel"), func(): _request_confirmation.clear(); refresh()).name = "CancelNpcRequestChange"
		return
	if not accepted:
		action("check", L10n.text("Accept and track"), func(): _request_action("accept_opportunity", slot, sequence), true, true).name = "AcceptRequest_" + slot
	else:
		action("x", L10n.text("Abandon request"), func():
			_request_confirmation = {"type": "abandon_opportunity", "slot": slot, "sequence": sequence}
			refresh()).name = "AbandonRequest_" + slot
	if slot == "bistro" and place_id == "bistro" and target != "table":
		if JourneyProgress.offer_ready(state(), slot):
			action("utensils", L10n.text("Serve at the table"), func(): target_requested.emit("table"), true, true)
	else:
		action("package-check", L10n.format_text("Deliver - %d coins", int(spec.coins)), func():
			await _deliver_offer(slot, spec, sequence), JourneyProgress.offer_ready(state(), slot), true).name = "DeliverRequest_" + slot
	var goal := JourneyRequests.goal(JourneyProgress.goal_state(session), session.server_now(), slot)
	var timber_work: bool = goal.get("change_request") == slot or (prefer_timber_only and slot == "restorer" and spec.get("id") != "timber_for_repairs")
	if accepted and not JourneyProgress.offer_ready(state(), slot):
		if not goal.is_empty() and not timber_work:
			action("route", str(goal.hint), func(): goal_requested.emit(goal))
	var change := action("skip-forward", L10n.text("Request timber-only work") if timber_work else L10n.text("Another request"), func():
		if accepted:
			_request_confirmation = {"type": "decline_opportunity", "slot": slot, "sequence": sequence, "timber_only": timber_work}
			refresh()
		else: _request_action("decline_opportunity", slot, sequence, timber_work))
	change.name = "ChangeRequest_" + slot
	if slot == "restorer" and spec.get("id") != "timber_for_repairs" and not timber_work:
		action("axe", L10n.text("Request timber-only work"), func():
			if accepted:
				_request_confirmation = {"type": "decline_opportunity", "slot": slot, "sequence": sequence, "timber_only": true}
				refresh()
			else: _request_action("decline_opportunity", slot, sequence, true)).name = "TimberOnlyRequest"

func _track_offer(slot: String, sequence: int, tracking: bool) -> void:
	if await command("track_journey_opportunity", {"slot": slot, "sequence": sequence, "tracking": tracking},
			L10n.text("Request tracked.") if tracking else L10n.text("Request tracking stopped.")):
		refresh()
	elif session.last_error_code == "REQUEST_DONE": await _recover_request()

func _recover_request() -> void:
	_request_confirmation.clear()
	prefer_timber_only = false
	await _reconnect()
	if not is_inside_tree(): return
	if session.last_error_code.is_empty(): message.text = L10n.text("The request changed. Review the current offer.")
	refresh()

func _request_action(type: String, slot: String, sequence: int, timber_only := false) -> void:
	var success := {"accept_opportunity": "Request accepted and tracked.", "abandon_opportunity": "Request abandoned.", "decline_opportunity": "A different request is ready."}
	var payload := {"slot": slot, "sequence": sequence}
	if timber_only: payload.timber_only = true
	if await command(type, payload, L10n.text(str(success[type]))):
		_request_confirmation.clear()
		prefer_timber_only = false
	elif session.last_error_code == "REQUEST_DONE":
		await _recover_request()
	refresh()

func _deliver_offer(slot: String, spec: Dictionary, sequence := -1) -> void:
	var meal := slot == "bistro" and place_id == "bistro"
	var dish := str(spec.get("dishes", {}).keys()[0]) if not spec.get("dishes", {}).is_empty() else ""
	var success := L10n.format_text("%s served. +%d coins", [L10n.dish_name(dish), int(spec.coins)]) if meal else L10n.format_text("Delivered. +%d coins", int(spec.coins))
	if await command("fulfill_opportunity", {"slot": slot, "sequence": sequence if sequence >= 0 else int(state().journey.opportunities[slot].sequence)}, success):
		var completed := session.last_command_events.any(func(event): return event.get("type") == "opportunity_completed" and event.get("slot") == slot)
		if not completed:
			message.text = L10n.text("Delivery confirmed.")
			return
		var reply := JourneyRequests.last_reply(state(), slot)
		if not reply.is_empty(): message.text = reply + "\n" + success
		contribution_completed.emit(slot, str(spec.effect))
		world_action_completed.emit("table" if meal else target)
		if meal and not dish.is_empty(): meal_served.emit(dish)
	elif session.last_error_code == "REQUEST_DONE": await _recover_request()

func _workbench() -> void:
	heading(L10n.text("Neighbourhood workbench"))
	if not JourneyProgress.fact(state(), "workbench"):
		paragraph(L10n.format_text("Wood %d", _wood()))
		var cost := int(JourneyProgress.data().costs.repair_workbench)
		action("hammer", L10n.format_text("Repair - %d wood", cost), func(): _activity("repair_workbench", L10n.text("The workbench is ready.")), _wood() >= cost, true)
	else:
		var savings := CharacterModel.action_status(state(), "craft_savings")
		if not savings.is_empty(): paragraph(savings)
		if not JourneyProgress.fact(state(), "planter_crafted"):
			paragraph(L10n.format_text("Wood %d", _wood()))
			var cost := int(CharacterModel.craft_materials(state(), {"wood": int(JourneyProgress.data().costs.craft_planter)}).wood)
			action("hammer", L10n.format_text("Make a planter - %d wood", cost), func(): _activity("craft_planter", L10n.text("Your handmade planter is ready for the courtyard.")), _wood() >= cost, true)
		_equipment_recipes()
		heading(L10n.text("Handmade pieces"))
		var recipe_ids: Array = JourneyProgress.data().workshop.recipes.keys()
		if not JourneyProgress.fact(state(), "planter_crafted"):
			recipe_ids = recipe_ids.filter(func(id): return JourneyProgress.requirements_met(state(), JourneyProgress.data().workshop.recipes[id]))
		var planned_item := str(JourneyWorkshop.planned(state()).get("item", ""))
		if recipe_ids.has(planned_item):
			recipe_ids.erase(planned_item)
			recipe_ids.push_front(planned_item)
		for id in recipe_ids:
			var recipe := CharacterModel.craft_recipe(state(), JourneyProgress.data().workshop.recipes[id])
			section_card(str(id) == planned_item)
			var row := HBoxContainer.new()
			row.custom_minimum_size.y = 56
			row.add_theme_constant_override("separation", 8)
			append_content(row)
			row.add_child(GameUi.picture(ItemCatalog.texture(str(id)), 44))
			var details := VBoxContainer.new()
			details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(details)
			var label := GameUi.label(L10n.format_text("%s (%d)", [recipe.name, JourneyProgress.stock(state(), str(id))]), 14)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			details.add_child(label)
			var needs := _cost(recipe) if JourneyProgress.requirements_met(state(), recipe) else paragraph(L10n.text("Open the side path") if id == "lantern" else L10n.text("Make a garden lantern first"))
			needs.add_theme_font_size_override("font_size", 12)
			needs.reparent(details)
			var make := action("hammer", L10n.text("Make ") + L10n.text(str(recipe.name)), func():
				if await _workshop_command("craft_journey_item", {"item": id}, L10n.text("Your handmade piece is ready.")):
					if JourneyWorkshop.planned(state()).get("item") == id: world_action_completed.emit(target),
				JourneyProgress.requirements_met(state(), recipe) and JourneyProgress.cost_ready(state(), recipe), true)
			make.name = "Craft_" + str(id)
			make.text = ""
			make.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			make.reparent(row)
			var deliver := action("package-check", L10n.format_text("Deliver %s - %d coins", [recipe.name, recipe.coins]), func():
				await _workshop_command("deliver_journey_item", {"item": id}, L10n.text("A neighbour has a place for your work.")), JourneyProgress.stock(state(), str(id)) > 0)
			deliver.name = "DeliverCraft_" + str(id)
			deliver.text = L10n.format_text("%d", int(recipe.coins))
			deliver.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			deliver.reparent(row)
			for item in recipe.materials:
				if item not in ["copper_ore", "rock_salt"] or JourneyProgress.material(state(), str(item)) >= int(recipe.materials[item]): continue
				var missing_material := str(item)
				var gather := action("pickaxe", L10n.format_text("Mine for %s", L10n.material_name(missing_material)), func():
					goal_requested.emit(JourneyProgress._material_goal(state(), missing_material)))
				gather.name = "Gather_" + missing_material

func _equipment_recipes() -> void:
	heading(L10n.text("Equipment"))
	for id in CharacterModel.data().get("equipment", {}):
		var spec := CharacterModel.equipment(str(id))
		if spec.get("starter", false): continue
		section_card()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		append_content(row)
		row.add_child(GameUi.picture(ItemCatalog.texture(str(id)), 42))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		var title := GameUi.label(ItemCatalog.name_of(str(id)), 14)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(title)
		var owned := CharacterModel.owns(state(), str(id))
		var effective := CharacterModel.craft_recipe(state(), spec)
		var needs := paragraph(L10n.text("Owned")) if owned else _cost(effective)
		needs.add_theme_font_size_override("font_size", 12)
		needs.reparent(details)
		var modifiers := paragraph(CharacterModel.modifier_label(str(id)))
		modifiers.add_theme_font_size_override("font_size", 12)
		modifiers.reparent(details)
		var make := action("check" if owned else "hammer", L10n.text("Owned") if owned else L10n.text("Make ") + ItemCatalog.name_of(str(id)), _make_equipment.bind(str(id)), not owned and CharacterModel.canonical(state()) and JourneyProgress.cost_ready(state(), effective) and not session.has_unconfirmed_command(), true)
		make.name = "CraftEquipment_" + str(id)
		make.text = ""
		make.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		make.reparent(row)
		if not owned:
			for item in effective.materials:
				if JourneyProgress.material(state(), str(item)) >= int(effective.materials[item]): continue
				var missing := str(item)
				var gather := action("pickaxe" if missing == "copper_ore" else "compass", L10n.format_text("Find %s", L10n.material_name(missing)), func(): goal_requested.emit(JourneyProgress._material_goal(state(), missing)))
				gather.name = "EquipmentMaterial_" + str(id) + "_" + missing

func _make_equipment(id: String) -> void:
	if not CharacterModel.canonical(state()) or session == null or session.has_unconfirmed_command(): return
	var had_tea := not CharacterModel.active_buff(state(), "tea").is_empty()
	var accepted := await command("craft_equipment", {"item_id": id, "sequence": int(state().bag.sequence)}, L10n.text("Equipment made. It is in your bag."))
	if not is_inside_tree(): return
	if accepted: _crafting_feedback(had_tea)
	if not accepted and session.last_error_code == "BAG_CHANGED":
		await _reconnect()
		message.text = BagPanel.bag_error("BAG_CHANGED")
	elif not accepted: message.text = BagPanel.bag_error(session.last_error_code)
	refresh()

func _kitchen() -> void:
	var recipes := JourneyProgress.recipes()
	for dish in recipes:
		if dish == "tea" and not JourneyProgress.unlocked(state(), "tea"): continue
		section_card()
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 56
		row.add_theme_constant_override("separation", 8)
		row.add_child(GameUi.picture(GameUi.dish_art(dish), 52))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(details)
		var label := GameUi.label(L10n.dish_name(str(dish)), 16)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(label)
		append_content(row)
		var ingredients := HFlowContainer.new()
		ingredients.add_theme_constant_override("h_separation", 6)
		ingredients.add_theme_constant_override("v_separation", 6)
		for crop in recipes[dish].inputs:
			var qty := int(recipes[dish].inputs[crop])
			ingredients.add_child(ingredient_card(GameUi.crop_art(str(crop)), CropInfo.name_of(str(crop)), available(str(crop)), qty))
		for item in recipes[dish].get("materials", {}):
			ingredients.add_child(ingredient_card(ItemCatalog.texture(str(item)), L10n.material_name(str(item)), JourneyProgress.material(state(), str(item)), int(recipes[dish].materials[item])))
		append_content(ingredients)
		var effect := GameUi.label(CharacterModel.effect_label(str(dish)), 12, GameUi.GREEN)
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(effect)
		var prepare := action("utensils", L10n.format_text("Prepare %s", L10n.dish_name(str(dish))), func():
			if await command("cook_dish", {"recipe": dish}, L10n.text("Freshly prepared.")):
				world_action_completed.emit(target), JourneyProgress.recipe_ready(state(), str(dish)), true)
		prepare.name = "Cook_" + str(dish)
		prepare.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		prepare.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for item in recipes[dish].get("materials", {}):
			if JourneyProgress.material(state(), str(item)) >= int(recipes[dish].materials[item]): continue
			var missing_material := str(item)
			var gather := action("pickaxe", L10n.format_text("Mine for %s", L10n.material_name(missing_material)), func():
				goal_requested.emit(JourneyProgress._material_goal(state(), missing_material)))
			gather.name = "Gather_" + missing_material
