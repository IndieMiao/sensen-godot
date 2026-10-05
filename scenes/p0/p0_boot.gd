extends Node
## P0 entry point. P0_SCENE (env) or user://p0_scene picks the first world for dev runs:
## "map" (default), "farm", "pond:<pond id>". Worlds above the map are pushed on AppRouter's stack.

const MAP := "res://scenes/p0/p0_map.tscn"
const FARM := "res://scenes/p0/p0_farm.tscn"
const POND := "res://scenes/p0/p0_pond.tscn"

static func wanted() -> String:
	var s := OS.get_environment("P0_SCENE")
	if s == "" and FileAccess.file_exists("user://p0_scene"):
		s = FileAccess.get_file_as_string("user://p0_scene").strip_edges()
	return s if s != "" else "map"

func _ready() -> void:
	_go.call_deferred(wanted())

func _go(target: String) -> void:
	P0Runtime.ensure()
	if target.begins_with("pond:"):
		AppRouter.push_instance(POND, {"pond_id": target.trim_prefix("pond:")})
	elif target == "farm" or not ResourceLoader.exists(MAP):
		get_tree().change_scene_to_file(FARM)
	else:
		get_tree().change_scene_to_file(MAP)
