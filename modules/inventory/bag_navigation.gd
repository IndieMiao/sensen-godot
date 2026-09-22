class_name BagNavigation
extends RefCounted

static func follow(panel: SessionPanel, goal: Dictionary) -> void:
	var session := panel.session
	if panel.busy or session == null or session.offline or session.has_unconfirmed_command(): return
	var mine: Dictionary = session.state.get("mine", {})
	if int(mine.get("floor", 0)) > 0:
		if not await panel.command("leave_mine", {"run": int(mine.get("run", 0)), "floor": int(mine.floor)}, ""): return
	var args := {"session": session, "target": str(goal.get("target", ""))}
	if goal.has("change_request"): args.request_timber_slot = str(goal.change_request)
	var scene := AppRouter.FARM
	if goal.has("resident"):
		scene = AppRouter.STREET
		args.target = "resident:" + str(StreetCommons.RESIDENTS.find_key(str(goal.resident)))
		args.walk_place = ""
	elif goal.get("surface") == "street" or goal.get("place") == "street":
		scene = AppRouter.STREET
		args.walk_place = str(goal.get("place", "")) if goal.get("place") != "street" else ""
	elif goal.get("place") != "farm":
		scene = AppRouter.PLACE
		args.place_id = str(goal.get("place", "nursery"))
		if not JourneyProgress.active(session.state) and goal.get("target") == "counter": args.tab = "kitchen"
	if goal.has("plant_crop"): args.plant_crop = str(goal.plant_crop)
	if goal.get("action") == "stall" and goal.has("crop"):
		args.seed_crop = str(goal.crop)
		args.target = "stall"
	if goal.has("selected_prop"):
		args.selected_prop = str(goal.selected_prop)
		args.tab = "decorations"
	# Capture the shared session and destination before disposing the current scene.
	AppRouter.return_to_farm(session)
	AppRouter.open_instance(scene, args)
