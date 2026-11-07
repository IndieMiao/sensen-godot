extends Node
## P0 entry point. P0_SCENE (env) or user://p0_scene picks the first world for dev runs:
## "farm" (default: the first session lands on the homestead by the first bed, WP4 A-03 / q(44); a new player picks a
## home first, SGODOT-303), "map",
## "pond:<pond id>", "outpost:<outpost id>", "landmark:<id>[:<point>[:<zoom>]]" (alcatraz_island, griffith_observatory: as its
## Go opens it, q(295); stood at a review point, at that zoom). Worlds above the map are pushed on AppRouter's stack.

const MAP := "res://scenes/p0/p0_map.tscn"
const FARM := "res://scenes/p0/p0_farm.tscn"
const POND := "res://scenes/p0/p0_pond.tscn"
const OUTPOST := "res://scenes/p0/p0_outpost.tscn"
const P0Clusters := preload("res://modules/p0/p0_clusters.gd")
const P0LandmarkVisit := preload("res://modules/p0/p0_landmark_visit.gd")

static func wanted() -> String:
	var s := OS.get_environment("P0_SCENE")
	if s == "" and FileAccess.file_exists("user://p0_scene"):
		s = FileAccess.get_file_as_string("user://p0_scene").strip_edges()
	return s if s != "" else "farm"

func _ready() -> void:
	_go.call_deferred(wanted())

func _go(target: String) -> void:
	var rt := P0Runtime.ensure()
	rt.cover_launch()   # SYS-LOADING until the first answer and the first world (SGODOT-233)
	if target.begins_with("pond:"):
		AppRouter.push_instance(POND, {"pond_id": target.trim_prefix("pond:")})
	elif target.begins_with("outpost:"):
		AppRouter.push_instance(OUTPOST, {"outpost_id": target.trim_prefix("outpost:")})
	elif target.begins_with("landmark:") and LandmarkScenes.region_of(target.get_slice(":", 1)) != "":
		var id := target.get_slice(":", 1)
		var region_id := LandmarkScenes.region_of(id)
		var entry := {"kind": "landmark", "id": id}
		for p in CityMapData.landmarks(region_id):
			if str(p.id) == id: entry = (p as Dictionary).merged(entry)
		var city := str(P0Clusters.region(P0Clusters.cluster_of_region(region_id)).get("name", ""))
		var args := P0LandmarkVisit.args_for(entry, city)
		# landmark:<id>:<point>[:<zoom>] — stood at a review point, at that zoom (李元芳's frame times on a phone)
		if target.get_slice_count(":") > 2: args["dev_point"] = target.get_slice(":", 2)
		if target.get_slice_count(":") > 3: args["dev_zoom"] = float(target.get_slice(":", 3))
		AppRouter.push_instance(LandmarkScenes.path_for(region_id, entry), args)
	elif target == "farm" or not ResourceLoader.exists(MAP):
		# SGODOT-303: a new save waits for its home to be picked, before any world (the server plays nothing else
		# meanwhile). The farm loads behind the cover while the first state is read.
		ResourceLoader.load_threaded_request(FARM)
		rt.when_first_view(func(v: Dictionary):
			if P0Runtime.home_pending(v): rt.pick_home(_enter_farm)
			else: _enter_farm())
	else:
		get_tree().change_scene_to_file(MAP)

func _enter_farm() -> void:
	var farm = ResourceLoader.load_threaded_get(FARM) if ResourceLoader.load_threaded_get_status(FARM) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE else null
	if farm is PackedScene: get_tree().change_scene_to_packed(farm)
	else: get_tree().change_scene_to_file(FARM)
