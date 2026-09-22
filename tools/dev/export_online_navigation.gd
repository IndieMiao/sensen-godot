extends Node

func _ready() -> void:
	var maps := {}
	var regions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/regions.json"))
	for region in regions.regions:
		for candidate in region.candidates:
			var source := FarmBlueprint.load_file(FarmBlueprint.asset_path(str(candidate.layout_patch_id), int(candidate.revision)))
			var key := "%s:%d" % [source.layout_patch_id, source.revision]
			maps["street:" + key] = pack(JourneyStreets.new(source, true).nav)
			maps["farm:" + key] = pack(FarmPlot.blueprint_for())
	var file := FileAccess.open("res://assets/farm/data/online_navigation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"version": 1, "maps": maps}, "\t") + "\n")
	get_tree().quit()

func pack(bp: FarmBlueprint) -> Dictionary:
	var spawn := bp.cell_to_world(bp.anchor("spawn"))
	return {"cell": bp.cell_m, "rows": bp.masks.walkable, "spawn": [spawn.x, spawn.z]}
