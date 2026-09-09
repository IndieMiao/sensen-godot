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
	heading(str(spec.name))
	if not JourneyGatherings.available(state()): return
	if current: paragraph("The neighbours are gathered here.")
	var recipe: Dictionary = JourneyProgress.data().workshop.recipes[spec.item]
	paragraph("%s: %s\n%s: %d/1" % [recipe.name, "On the table" if current else ("In your bag" if JourneyGatherings.piece_ready(state(), theme_id) else "Needed"),
		"Chamomile tea" if spec.dish == "tea" else "Vegetable salad", int(state().get("inventory", {}).get("dishes", {}).get(spec.dish, 0))])
	if selected:
		if JourneyGatherings.ready(state(), theme_id):
			action("utensils", "Serve tea" if spec.dish == "tea" else "Serve supper", _host, true, true)
		else:
			var goal := JourneyGatherings.goal(JourneyProgress.goal_state(session), session.server_now())
			action(str(goal.icon), str(goal.hint), func(): goal_requested.emit(goal), true, true)
		action("x", "Cancel preparations", func(): _plan(""))
	else:
		action("users-round", "Prepare another meal" if current else "Prepare this gathering", func(): _plan(theme_id), true, true)
	if current:
		action("package-check", "Pack away " + str(recipe.name), _pack)
	for other in JourneyGatherings.themes():
		if other == theme_id: continue
		var alternative: Dictionary = JourneyGatherings.themes()[other]
		action(str(alternative.icon), "Visit " + str(alternative.name), func(): goal_requested.emit(JourneyGatherings.venue_goal(str(other))))
	paragraph("Neighbour contribution: %d coins" % int(spec.coins))

func _plan(value: String) -> void:
	await command("plan_journey_gathering", {"theme": value, "sequence": int(JourneyGatherings.progress(state()).get("sequence", 0))},
		"Preparations cancelled" if value.is_empty() else "Preparing " + str(JourneyGatherings.themes()[value].name))

func _host() -> void:
	var again := JourneyGatherings.current(state()) == theme_id
	if await command("host_journey_gathering", {"theme": theme_id, "sequence": int(JourneyGatherings.progress(state()).get("sequence", 0))},
		("Another meal is on the table" if again else "The neighbours are on their way") + " / +%d coins" % int(JourneyGatherings.themes()[theme_id].coins)):
		hosted.emit(theme_id)

func _pack() -> void:
	if await command("pack_journey_gathering", {"sequence": int(JourneyGatherings.progress(state()).get("sequence", 0))}, "Handmade piece returned to your bag"):
		packed.emit()
