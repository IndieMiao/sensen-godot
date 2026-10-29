extends SceneTree
## Remove only this unreviewed geometry increment, preserving the earlier delivery verbatim.
func _initialize():
	var path = "res://assets/avatar/parts_manifest.json"
	var text = FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	var ids = ["hairhat41_npc_nadia_baker", "cloth1_1_npc_nadia"]
	assert(data.parts.slice(-2).map(func(p): return p.id) == ids)
	var previous = JSON.parse_string(FileAccess.get_file_as_string("res://output/npc-batch3/phase1-manifest.json"))
	assert(data.parts.slice(0, -2) == previous.parts)
	FileAccess.open(path, FileAccess.WRITE).store_string(FileAccess.get_file_as_string("res://output/npc-batch3/phase1-manifest.json"))
	quit()
