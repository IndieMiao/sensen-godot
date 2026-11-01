extends SceneTree
## Check actual imported resources before their metadata is copied back to the kit.
const KIT := "res://assets/rooms/poi_hotel_lobby/"

func _initialize() -> void:
	var report := {"passed": true, "resources": []}
	var seen := {}
	var files := DirAccess.get_files_at(KIT)
	files.sort()
	for file in files:
		if not file.ends_with(".import"): continue
		var config := ConfigFile.new()
		var valid := config.load(KIT + file) == OK
		var uid := str(config.get_value("remap", "uid", ""))
		var id := ResourceUID.text_to_id(uid)
		var resource_path := KIT + file.trim_suffix(".import")
		valid = valid and uid.begins_with("uid://") and id != ResourceUID.INVALID_ID
		valid = valid and not seen.has(uid) and ResourceUID.has_id(id)
		valid = valid and ResourceLoader.get_resource_uid(resource_path) == id
		valid = valid and ResourceLoader.load(resource_path) != null
		if file.ends_with(".glb.import"):
			valid = valid and int(config.get_value("params", "gltf/texture_map_mode", -1)) == 1
		seen[uid] = true
		report.resources.append({"file": file, "uid": uid, "passed": valid})
		report.passed = report.passed and valid
	report.passed = report.passed and report.resources.size() == 20
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 1)
	FileAccess.open(args[0], FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("N1_IMPORT_UIDS ", report.passed, " count=", report.resources.size())
	quit(0 if report.passed else 1)
