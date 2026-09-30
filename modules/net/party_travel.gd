class_name PartyTravel
extends RefCounted
## Translate an authorized destination into scene arguments. Never write FarmChoice/FarmRegions here.

static func scene_path(manifest: Dictionary) -> String:
	# A legacy street ticket still binds street navigation on an older server.
	# Only the server can normalize its admission to the private farm space.
	return {"farm": AppRouter.FARM, "mine": AppRouter.ONLINE_MINE, "pond": SystemPonds.SCENE}.get(str(manifest.get("kind", "")), "")

static func scene_args(manifest: Dictionary, session: FarmSession) -> Dictionary:
	if scene_path(manifest).is_empty(): return {}
	var args := {"session": session, "online_join": {"travel_ticket": str(manifest.get("ticket", "")),
		"farm_id": str(manifest.get("farm_id", "")), "channel": int(manifest.get("channel", 1))}}
	if str(manifest.get("kind", "")) == "mine": return args
	if str(manifest.get("kind", "")) == "pond":
		# Server-only ponds ride along with the ticket; the follower may never have loaded that map cell.
		if manifest.has("pond"): SystemPonds.accept(manifest.pond)
		if manifest.get("catalog_revision") != SystemPonds.revision() or SystemPonds.location(str(manifest.get("pond_id", ""))).is_empty(): return {}
		args.pond_id = manifest.pond_id
		return args
	var choice: Dictionary = (manifest.get("snapshot", {}) as Dictionary).merged(manifest, true)
	var blueprint := FarmBlueprint.load_choice(choice)
	if blueprint == null: return {}
	args.blueprint = blueprint
	args.visitor = str(manifest.get("farm_id", "")) != session.farm_id
	args.snapshot = manifest.get("snapshot", {})
	return args

static func scene_label(scene: Variant) -> String:
	if not scene is Dictionary: return L10n.text("Offline or outside an online space")
	if scene.kind == "mine":
		return L10n.format_text("Mine floor %d · instance %s", [int(scene.floor), str(scene.room).trim_prefix("mine:").substr(0, 8)])
	if scene.kind == "pond": return L10n.text("Fishing pond") + " · " + L10n.format_text("Channel %d", int(scene.channel))
	var region := str(scene.get("region_id", ""))
	for value in FarmRegions.load_default().regions:
		if str(value.id) == region: region = L10n.text(str(value.name))
	return "%s · %s · %s" % [region, L10n.text("Farm"), L10n.format_text("Channel %d", int(scene.channel))]
