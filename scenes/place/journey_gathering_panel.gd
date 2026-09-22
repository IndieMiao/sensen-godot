class_name JourneyGatheringPanel
extends SessionPanel

signal goal_requested(goal: Dictionary)
signal hosted(theme: String)
signal packed()

var theme_id := "garden"

func _render() -> void:
	var spec: Dictionary = JourneyGatherings.themes()[theme_id]
	var selected := JourneyGatherings.planned(state()) == theme_id
	var current := JourneyGatherings.current(state()) == theme_id
	heading(L10n.text(str(spec.name)))
	if not JourneyGatherings.available(state()): return
	if current: paragraph(L10n.text("The neighbours are gathered here."))
	var recipe: Dictionary = JourneyProgress.data().workshop.recipes[spec.item]
	var requirements := HFlowContainer.new()
	requirements.add_theme_constant_override("h_separation", 8)
	requirements.add_theme_constant_override("v_separation", 8)
	append_content(requirements)
	requirements.add_child(ingredient_card(ItemCatalog.texture(str(spec.item)), L10n.text(str(recipe.name)), 1 if current or JourneyGatherings.piece_ready(state(), theme_id) else 0, 1))
	requirements.add_child(ingredient_card(GameUi.dish_art(str(spec.dish)), L10n.text("Chamomile tea") if spec.dish == "tea" else L10n.text("Vegetable salad"), int(state().get("inventory", {}).get("dishes", {}).get(spec.dish, 0)), 1))
	paragraph(L10n.format_text("%s: %s\n%s: %d/1", [recipe.name, L10n.text("On the table") if current else (L10n.text("In your bag") if JourneyGatherings.piece_ready(state(), theme_id) else L10n.text("Needed")),
		L10n.text("Chamomile tea") if spec.dish == "tea" else L10n.text("Vegetable salad"), int(state().get("inventory", {}).get("dishes", {}).get(spec.dish, 0))]))
	if selected:
		if JourneyGatherings.ready(state(), theme_id):
			action("utensils", L10n.text("Serve tea") if spec.dish == "tea" else L10n.text("Serve supper"), _host, true, true)
		else:
			var goal := JourneyGatherings.goal(JourneyProgress.goal_state(session), session.server_now())
			action(str(goal.icon), str(goal.hint), func(): goal_requested.emit(goal), true, true)
		action("x", L10n.text("Cancel preparations"), func(): _plan(""))
	else:
		action("users-round", L10n.text("Prepare another meal") if current else L10n.text("Prepare this gathering"), func(): _plan(theme_id), true, true)
	if current:
		action("package-check", L10n.text("Pack away ") + L10n.text(str(recipe.name)), _pack)
	for other in JourneyGatherings.themes():
		if other == theme_id: continue
		var alternative: Dictionary = JourneyGatherings.themes()[other]
		action(str(alternative.icon), L10n.text("Visit ") + L10n.text(str(alternative.name)), func(): goal_requested.emit(JourneyGatherings.venue_goal(str(other))))
	paragraph(L10n.format_text("Neighbour contribution: %d coins", int(spec.coins)))

func _plan(value: String) -> void:
	await command("plan_journey_gathering", {"theme": value, "sequence": int(JourneyGatherings.progress(state()).get("sequence", 0))},
		L10n.text("Preparations cancelled") if value.is_empty() else L10n.text("Preparing ") + L10n.text(str(JourneyGatherings.themes()[value].name)))

func _host() -> void:
	var again := JourneyGatherings.current(state()) == theme_id
	if await command("host_journey_gathering", {"theme": theme_id, "sequence": int(JourneyGatherings.progress(state()).get("sequence", 0))},
		(L10n.text("Another meal is on the table") if again else L10n.text("The neighbours are on their way")) + L10n.format_text(" / +%d coins", int(JourneyGatherings.themes()[theme_id].coins))):
		hosted.emit(theme_id)

func _pack() -> void:
	if await command("pack_journey_gathering", {"sequence": int(JourneyGatherings.progress(state()).get("sequence", 0))}, L10n.text("Handmade piece returned to your bag")):
		packed.emit()
