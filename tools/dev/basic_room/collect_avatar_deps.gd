extends SceneTree

var found: Dictionary = {}

func _initialize() -> void:
	for id in ["body00", "eyes00", "hairhat0", "cloth0", "shoes0"]:
		walk("res://assets/avatar/parts/" + id + ".res")
	walk("res://assets/avatar/base/base_rig.tscn")
	var f := FileAccess.open("res://output/basic-room-2026-10-06/avatar-dependencies.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(found.keys(), "  "))
	print("AVATAR_DEPENDENCIES ", found.size())
	quit()

func walk(path: String) -> void:
	if found.has(path): return
	found[path] = true
	for dependency in ResourceLoader.get_dependencies(path):
		var parts := dependency.split("::")
		walk(parts[parts.size() - 1])
