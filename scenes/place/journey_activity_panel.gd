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

var target := ""
var place_id := ""
var _requests_expanded := false
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
		content.add_child(row)
		var reserved := maxi(0, harvest - available(str(crop)))
		if reserved > 0: paragraph(L10n.format_text("%d reserved", reserved))
	content.add_child(HSeparator.new())
	heading(L10n.text("Materials"))
	paragraph(L10n.format_text("%d wood / %d stone / %d reeds", [JourneyProgress.material(state(), "wood"),
		JourneyProgress.material(state(), "stone"), JourneyProgress.material(state(), "fiber")]))
	if JourneyProgress.unlocked(state(), "kitchen"):
		content.add_child(HSeparator.new())
		heading(L10n.text("Meals"))
		for dish in JourneyProgress.recipes():
			var count := int(inventory.get("dishes", {}).get(dish, 0))
			if dish == "tea" and not JourneyProgress.unlocked(state(), "crop_H") and count == 0: continue
			paragraph(L10n.format_text("%s: %d", [L10n.text("Vegetable salad") if dish == "salad" else L10n.text("Chamomile tea"), count]))
	var pieces: Array[String] = []
	for item in JourneyProgress.data().workshop.recipes:
		var count := JourneyProgress.stock(state(), str(item))
		if count > 0: pieces.append(L10n.format_text("%s: %d", [L10n.text(str(JourneyProgress.data().workshop.recipes[item].name)), count]))
	if not pieces.is_empty():
		content.add_child(HSeparator.new())
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
		content.add_child(row)
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
		content.add_child(row)
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
		content.add_child(title_row)
		content.move_child(title_row, 0)
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
	for item in spec.get("materials", {}): needs.append(L10n.format_text("%s %d/%d", [L10n.text("Reeds") if item == "fiber" else str(item).capitalize(), JourneyProgress.material(state(), str(item)), int(spec.materials[item])]))
	for crop in spec.get("produce", {}): needs.append(L10n.format_text("%s %d/%d", [CropInfo.name_of(str(crop)), available(str(crop)), int(spec.produce[crop])]))
	for dish in spec.get("dishes", {}): needs.append(L10n.format_text("%s %d/%d", [str(dish).capitalize(), int(state().inventory.dishes.get(dish, 0)), int(spec.dishes[dish])]))
	return paragraph(" / ".join(needs))

func _workshop_command(type: String, payload: Dictionary, success: String) -> bool:
	payload.sequence = int(state().journey.get("workshop", {}).get("sequence", 0))
	return await command(type, payload, success)

func _display(project: String, slot: int) -> void:
	var items := JourneyProgress.display_items(state(), project)
	if slot < 0 or slot >= items.size(): return
	var current := str(items[slot])
	var row := HBoxContainer.new()
	content.add_child(row)
	var title := heading(L10n.text(str(JourneyProgress.data().workshop.recipes[current].name)) if not current.is_empty() else L10n.text("Empty display"))
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
			var recipe: Dictionary = JourneyProgress.data().workshop.recipes[item]
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
	if await command("journey_action", {"action": id}, success):
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	content.add_child(row)
	var title := heading(L10n.text(str(spec.name)))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.reparent(row)
	var sequence := int(state().journey.opportunities[slot].sequence)
	var tracked: bool = JourneyRequests.tracked(state()).get("slot") == slot
	var track := action("compass", L10n.text("Stop tracking request") if tracked else L10n.text("Track request"), func():
		await _track_offer(slot, sequence, not tracked), JourneyRequests.available(state(), slot), tracked)
	track.name = "TrackRequest_" + slot
	track.text = ""
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.reparent(row)
	paragraph(StreetCommons.progress(state(), str(spec.effect)))
	var needs: Array[String] = []
	if int(spec.wood) > 0: needs.append(L10n.format_text("Wood %d/%d", [_wood(), spec.wood]))
	for crop in spec.produce: needs.append(L10n.format_text("%s %d/%d", [CropInfo.name_of(str(crop)), available(str(crop)), spec.produce[crop]]))
	for dish in spec.dishes: needs.append(L10n.format_text("%s %d/%d", [str(dish).capitalize(), int(state().inventory.dishes.get(dish, 0)), spec.dishes[dish]]))
	paragraph("   ".join(needs))
	if slot == "bistro" and place_id == "bistro" and target != "table":
		if JourneyProgress.offer_ready(state(), slot):
			action("utensils", L10n.text("Serve at the table"), func(): target_requested.emit("table"), true, true)
	else:
		action("package-check", L10n.format_text("Deliver - %d coins", int(spec.coins)), func():
			await _deliver_offer(slot, spec), JourneyProgress.offer_ready(state(), slot), true)
	var goal := JourneyRequests.goal(JourneyProgress.goal_state(session), session.server_now(), slot)
	var timber_work: bool = goal.get("change_request") == slot
	if not JourneyProgress.offer_ready(state(), slot):
		if not goal.is_empty() and not timber_work:
			action("route", str(goal.hint), func(): goal_requested.emit(goal))
	var change := action("skip-forward", L10n.text("Request timber-only work") if timber_work else L10n.text("Another request"), func():
		command("decline_opportunity", {"slot": slot, "sequence": sequence}, L10n.text("A different request is ready.")))
	change.name = "ChangeRequest_" + slot

func _track_offer(slot: String, sequence: int, tracking: bool) -> void:
	if await command("track_journey_opportunity", {"slot": slot, "sequence": sequence, "tracking": tracking},
			L10n.text("Request tracked.") if tracking else L10n.text("Request tracking stopped.")):
		if tracking and not JourneyProgress.offer_ready(state(), slot):
			goal_requested.emit(JourneyRequests.goal(JourneyProgress.goal_state(session), session.server_now()))

func _deliver_offer(slot: String, spec: Dictionary) -> void:
	var meal := slot == "bistro" and place_id == "bistro"
	var success := L10n.format_text("%s served. +%d coins", [L10n.text("Tea") if spec.dishes.has("tea") else L10n.text("Salad"), int(spec.coins)]) if meal else L10n.format_text("Delivered. +%d coins", int(spec.coins))
	if await command("fulfill_opportunity", {"slot": slot, "sequence": int(state().journey.opportunities[slot].sequence)}, success):
		contribution_completed.emit(slot, str(spec.effect))
		world_action_completed.emit("table" if meal else target)
		if meal: meal_served.emit("tea" if spec.dishes.has("tea") else "salad")

func _workbench() -> void:
	heading(L10n.text("Neighbourhood workbench"))
	if not JourneyProgress.fact(state(), "workbench"):
		paragraph(L10n.format_text("Wood %d", _wood()))
		var cost := int(JourneyProgress.data().costs.repair_workbench)
		action("hammer", L10n.format_text("Repair - %d wood", cost), func(): _activity("repair_workbench", L10n.text("The workbench is ready.")), _wood() >= cost, true)
	elif not JourneyProgress.fact(state(), "planter_crafted"):
		paragraph(L10n.format_text("Wood %d", _wood()))
		var cost := int(JourneyProgress.data().costs.craft_planter)
		action("hammer", L10n.format_text("Make a planter - %d wood", cost), func(): _activity("craft_planter", L10n.text("Your handmade planter is ready for the courtyard.")), _wood() >= cost, true)
	else:
		var recipe_ids: Array = JourneyProgress.data().workshop.recipes.keys()
		var planned_item := str(JourneyWorkshop.planned(state()).get("item", ""))
		if recipe_ids.has(planned_item):
			recipe_ids.erase(planned_item)
			recipe_ids.push_front(planned_item)
		for id in recipe_ids:
			var recipe: Dictionary = JourneyProgress.data().workshop.recipes[id]
			var row := HBoxContainer.new()
			row.custom_minimum_size.y = 56
			row.add_theme_constant_override("separation", 8)
			content.add_child(row)
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

func _kitchen() -> void:
	var recipes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/recipes.json")).recipes
	for dish in ["salad", "tea"]:
		if dish == "tea" and not JourneyProgress.unlocked(state(), "tea"): continue
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 56
		row.add_theme_constant_override("separation", 8)
		row.add_child(GameUi.picture(GameUi.dish_art(dish), 40))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(details)
		var label := GameUi.label(L10n.text("Vegetable salad") if dish == "salad" else L10n.text("Chamomile tea"), 14)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(label)
		content.add_child(row)
		var ready := JourneyProgress.unlocked(state(), "kitchen")
		var ingredients: Array[String] = []
		for crop in recipes[dish].inputs:
			var qty := int(recipes[dish].inputs[crop])
			ingredients.append(L10n.format_text("%s %d/%d", [CropInfo.name_of(str(crop)), available(str(crop)), qty]))
			ready = ready and available(str(crop)) >= qty
		var needs := GameUi.label(" / ".join(ingredients), 12, GameUi.MUTED)
		needs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(needs)
		var prepare := action("utensils", L10n.format_text("Prepare %s", dish), func():
			if await command("cook_dish", {"recipe": dish}, L10n.text("Freshly prepared.")):
				world_action_completed.emit(target), ready, true)
		prepare.text = ""
		prepare.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prepare.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		prepare.reparent(row)
