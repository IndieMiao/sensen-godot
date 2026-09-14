class_name JourneyGatherings
extends RefCounted

static func themes() -> Dictionary:
	return JourneyProgress.data().gatherings.themes

static func available(state: Dictionary) -> bool:
	return JourneyProgress.active(state) and JourneyProgress.requirements_met(state, JourneyProgress.data().gatherings)

static func progress(state: Dictionary) -> Dictionary:
	return state.get("journey", {}).get("gathering", {})

static func planned(state: Dictionary) -> String:
	return str(progress(state).get("planned", ""))

static func current(state: Dictionary) -> String:
	return str(progress(state).get("current", ""))

static func resident_quote(state: Dictionary, resident: String) -> String:
	var quotes := {"garden": {
		"nursery_keeper": L10n.text("Our little seedlings have brought everyone to the same table. I saved you a cup."),
		"bistro_owner": L10n.text("Your chamomile smells lovely out here. This corner suits a slow cup of tea."),
		"restorer": L10n.text("You made that planter yourself. It belongs here among the neighbours.")},
		"lantern": {"nursery_keeper": L10n.text("Lettuce from the garden, supper under your lantern. Save me a seat next time."),
		"bistro_owner": L10n.text("You did the growing and cooking today. Let me look after the plates."),
		"restorer": L10n.text("That lantern started as timber and stone. Now we have a place to share supper.")}}
	return str(quotes.get(current(state), {}).get(resident, ""))

static func piece_ready(state: Dictionary, theme: String) -> bool:
	return current(state) == theme or JourneyProgress.stock(state, str(themes()[theme].item)) > 0

static func ready(state: Dictionary, theme: String) -> bool:
	return available(state) and piece_ready(state, theme) and int(state.get("inventory", {}).get("dishes", {}).get(themes()[theme].dish, 0)) > 0

static func crop_needs(state: Dictionary) -> Dictionary:
	var theme := planned(state)
	if theme.is_empty(): return {}
	var dish := str(themes()[theme].dish)
	if int(state.get("inventory", {}).get("dishes", {}).get(dish, 0)) > 0: return {}
	return JourneyProgress.recipes()[dish].inputs.duplicate()

static func venue_goal(theme: String, label := "") -> Dictionary:
	var spec: Dictionary = themes()[theme]
	return {"place": "street", "surface": "street", "gathering": theme, "target": "gathering:" + theme,
		"label": label if not label.is_empty() else L10n.text("Choose a neighbourhood gathering"), "hint": L10n.text("Street gathering"), "icon": spec.icon}

static func goal(state: Dictionary, now_ms := -1) -> Dictionary:
	var theme := planned(state)
	if theme.is_empty() or not available(state): return {}
	var spec: Dictionary = themes()[theme]
	var recipe: Dictionary = JourneyProgress.data().workshop.recipes[spec.item]
	var next := {}
	if not piece_ready(state, theme):
		for project in JourneyProgress.data().projects:
			var display := JourneyProgress.display_items(state, str(project))
			if display.has(spec.item):
				next = {"place": JourneyProgress.data().projects[project].place, "target": "display:%s:%d" % [project, display.find(spec.item)],
					"icon": "package-check", "hint": L10n.text("Collect your ") + L10n.text(str(recipe.name))}
				break
		if next.is_empty():
			for material in recipe.materials:
				var have := JourneyProgress.material(state, str(material))
				if have >= int(recipe.materials[material]): continue
				next = JourneyProgress._material_goal(state, str(material))
				next.hint = L10n.format_text("%s %d/%d", [L10n.text("Reeds") if material == "fiber" else str(material).capitalize(), have, int(recipe.materials[material])])
				break
		if next.is_empty(): next = {"place": "nursery", "target": "workbench", "icon": "hammer", "hint": L10n.text("Make ") + L10n.text(str(recipe.name))}
	elif int(state.get("inventory", {}).get("dishes", {}).get(spec.dish, 0)) < 1:
		var candidates := []
		for crop in crop_needs(state):
			var needed := int(crop_needs(state)[crop])
			if JourneyProgress.available(state, str(crop)) < needed:
				var crop_goal := JourneyProgress._crop_goal(state, str(crop), needed, now_ms)
				candidates.append(crop_goal)
		var order := {"harvest": 0, "care": 1, "gather": 2, "sow": 3, "stall": 4, "wait": 5}
		candidates.sort_custom(func(a, b): return order[a.action] < order[b.action])
		next = candidates[0] if not candidates.is_empty() else {"place": "bistro", "target": "counter", "icon": "utensils", "hint": L10n.format_text("Prepare %s", spec.dish)}
	else: next = venue_goal(theme, L10n.text("Host ") + L10n.text(str(spec.name))).merged({"hint": L10n.text("Ready to host")}, true)
	next.gathering = theme
	next.label = L10n.format_text("%s: %s", [spec.name, next.hint])
	return next
