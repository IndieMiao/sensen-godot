extends Node
## P0 entry point. P0_SCENE (env) or user://p0_scene picks the first world for dev runs:
## "farm" (default: the first session lands on the homestead by the first bed, WP4 A-03 / q(44)), "map",
## "pond:<pond id>", "outpost:<outpost id>". Worlds above the map are pushed on AppRouter's stack.

const MAP := "res://scenes/p0/p0_map.tscn"
const FARM := "res://scenes/p0/p0_farm.tscn"
const POND := "res://scenes/p0/p0_pond.tscn"
const OUTPOST := "res://scenes/p0/p0_outpost.tscn"

static func wanted() -> String:
	var s := OS.get_environment("P0_SCENE")
	if s == "" and FileAccess.file_exists("user://p0_scene"):
		s = FileAccess.get_file_as_string("user://p0_scene").strip_edges()
	return s if s != "" else "farm"

func _ready() -> void:
	_go.call_deferred(wanted())

func _go(target: String) -> void:
	P0Runtime.ensure().cover_launch()   # SYS-LOADING until the first answer and the first world (SGODOT-233)
	if target.begins_with("pond:"):
		AppRouter.push_instance(POND, {"pond_id": target.trim_prefix("pond:")})
	elif target.begins_with("outpost:"):
		AppRouter.push_instance(OUTPOST, {"outpost_id": target.trim_prefix("outpost:")})
	elif target == "farm" or not ResourceLoader.exists(MAP):
		get_tree().change_scene_to_file(FARM)
	else:
		get_tree().change_scene_to_file(MAP)
