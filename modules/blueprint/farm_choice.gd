class_name FarmChoice
extends RefCounted
## G0 本地记录玩家选定的蓝图。G1 起由服务端 farm_instance 取代，这里只剩缓存语义。

const PATH := "user://farm_choice.json"

static func save(layout_patch_id: String, revision: int) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"layout_patch_id": layout_patch_id, "revision": revision}))

static func load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("layout_patch_id"):
		return {}
	return {"layout_patch_id": str(parsed.layout_patch_id), "revision": int(parsed.get("revision", 1))}

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
