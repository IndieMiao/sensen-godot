extends SceneTree
func _initialize():
	var original="res://assets/rooms/tavern/room_albedo_ao.png"
	var saved="res://output/npc-batch3/tavern-original.ctex"
	var config=ConfigFile.new()
	assert(config.load(original+".import")==OK)
	var imported: String=config.get_value("remap","path.s3tc")
	if not FileAccess.file_exists(saved):
		assert(FileAccess.get_sha256(original)=="f85631fa4db950586d580e2e3ac5ce787b7646c1fc3099e09ed2336a0a00a9ee",
			"Prepare the comparison baseline from the unchanged farm-dev atlas before applying the patch")
		assert(DirAccess.copy_absolute(ProjectSettings.globalize_path(imported),ProjectSettings.globalize_path(saved))==OK)
		assert(DirAccess.copy_absolute(ProjectSettings.globalize_path(original),ProjectSettings.globalize_path("res://output/npc-batch3/tavern-original.png"))==OK)
		FileAccess.open("res://output/npc-batch3/tavern-baseline.json",FileAccess.WRITE).store_string(JSON.stringify({
			"source_sha256":FileAccess.get_sha256(original),"imported_sha256":FileAccess.get_sha256(imported),
			"saved_imported_sha256":FileAccess.get_sha256(saved),"compression":"s3tc"
		},"\t")+"\n")
	print("TAVERN_BASELINE_READY ",FileAccess.get_sha256(saved))
	quit()
