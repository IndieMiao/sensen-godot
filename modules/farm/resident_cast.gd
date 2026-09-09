class_name ResidentCast
extends RefCounted
## Residents use authored outfits, independent of the player's saved appearance.

const DATA_PATH := "res://assets/farm/data/residents.json"
const ORDER := ["nursery_keeper", "bistro_owner", "restorer"]
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary: _data = parsed
	return _data

static func definition(id: String) -> Dictionary:
	return data().get("residents", {}).get(id, {})

static func present(place_id: String, farm_state: Dictionary) -> Array:
	if JourneyProgress.active(farm_state):
		var resident := {"nursery": "nursery_keeper", "bistro": "bistro_owner", "courtyard": "restorer"}
		if place_id == "bistro" and JourneyProgress.project_complete(farm_state, "terrace"):
			return ["bistro_owner", "nursery_keeper"]
		return [resident[place_id]] if resident.has(place_id) and PlaceCatalog.available(place_id, farm_state) else []
	var chapter := int(farm_state.get("clock", {}).get("chapter_index", -1))
	var out := []
	for id in ORDER:
		var resident := definition(id)
		if chapter < int(resident.get("chapter", 99)): continue
		if str(resident.get("place", "")) == place_id or (chapter == 3 and place_id == "bistro" and id == "nursery_keeper") or (chapter >= 6 and place_id == "courtyard"):
			out.append(id)
	return out

static func relationship_stage(resident: Dictionary) -> String:
	var points := int(resident.get("points", 0))
	if points >= 45 and bool(resident.get("shared_event_done", false)): return "Familiar"
	if points >= 15 and resident.get("first_met_day") != null: return "Acquainted"
	return "First meeting"

static func dialogue(id: String, farm_state: Dictionary) -> Array:
	var resident := definition(id)
	var chapter := int(farm_state.get("clock", {}).get("chapter_index", 0))
	if id == "bistro_owner" and chapter == 2:
		var memories: Dictionary = farm_state.get("residents", {}).get(id, {}).get("choice_memories", {})
		var memory := str(memories.get("2", memories.get(2, "")))
		if not memory.is_empty(): return resident.get("choice_replies", {}).get(memory, []).duplicate()
	return resident.get("dialogues", {}).get(str(chapter), ["It is good to see you again."]).duplicate()

static func outfit(id: String) -> AvatarConfig:
	var config: AvatarConfig = (load("res://modules/avatar/data/slot_table.tres") as AvatarSlotTable).default_config()
	var choices: Dictionary = definition(id).get("outfit", {})
	for slot in choices: config.slots[StringName(slot)] = str(choices[slot])
	return config

static func journey_position(place_id: String, resident_id: String) -> Vector3:
	return Vector3(1.1, 0.04, 1.05) if place_id == "bistro" and resident_id == "nursery_keeper" else Vector3(0.35, 0.04, 0.25)

static func activities(place_id: String, state: Dictionary) -> Array:
	var out := []
	if place_id == "nursery" and JourneyProgress.project_complete(state, "seedbeds"):
		out.append({"resident": "nursery_keeper", "point": Vector3(-3.7, 0.04, 0.35), "facing": Vector3(-2.5, 0.6, -0.25),
			"animation": "labour_water", "seconds": 4.0, "label": "Tending seedlings"})
	if place_id == "bistro" and JourneyProgress.fact(state, "met_bistro"):
		out.append({"resident": "bistro_owner", "point": Vector3(-1.1, 0.04, 0.45), "facing": Vector3(-1.1, 0.9, -0.7),
			"animation": "labour_sow", "seconds": 4.0, "label": "Preparing the counter"})
		if JourneyProgress.project_complete(state, "terrace"):
			out.append({"resident": "nursery_keeper", "point": Vector3(3.55, 0.04, -0.65), "facing": Vector3(2, 0.96, -1.65),
				"animation": "idle", "seconds": 5.0, "label": "At the tea terrace"})
	if place_id == "courtyard" and JourneyProgress.fact(state, "planter_planted"):
		var planters := DecorationLayout.saved(state).filter(func(prop): return prop.prop_id == "planter")
		if not planters.is_empty():
			var planter := DecorationLayout.world_position(planters[0])
			out.append({"resident": "restorer", "point": planter + Vector3(0.8, 0.04, 0.65), "facing": planter,
				"animation": "labour_water", "seconds": 4.0, "label": "Tending the flowers"})
	return out

static func build(place_id: String, farm_state: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Residents"
	var residents := present(place_id, farm_state)
	for index in residents.size():
		var id := str(residents[index])
		var rig := Avatar.create_rig()
		rig.name = id
		rig.position = Vector3((index - (residents.size() - 1) * 0.5) * 1.5, 0.04, 0.25)
		rig.rotation.y = 0.5
		if JourneyProgress.active(farm_state):
			rig.position = journey_position(place_id, id)
			rig.rotation.y = PI * 0.5 if place_id == "bistro" and id == "nursery_keeper" else 0.5
		rig.scale = Vector3.ONE * 1.05
		for child in rig.get_children():
			if child is RigActivity:
				child.reduced_distance = 50
				child.sleep_distance = 80
		rig.config_applied.connect(_play_idle.bind(rig))
		root.add_child(rig)
		rig.ready.connect(func(): rig.apply_config(outfit(id)), CONNECT_ONE_SHOT)
	return root

static func _play_idle(_config: AvatarConfig, rig: AvatarRig) -> void:
	var animation := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if animation and animation.has_animation("idle"): animation.play("idle")
