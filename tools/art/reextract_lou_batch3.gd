extends SceneTree
func _initialize():
	var path = "res://assets/avatar/parts_manifest.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	var baseline = FileAccess.get_file_as_string("res://output/npc-batch3/phase2-manifest.json")
	var previous = JSON.parse_string(baseline)
	assert(data.parts[-1].id == "cloth1_npc_lou")
	assert(data.parts.slice(0,-1) == previous.parts)
	FileAccess.open(path,FileAccess.WRITE).store_string(baseline)
	quit()
