class_name FarmChoice
extends RefCounted
## G0 本地记录玩家选定的蓝图。G1 起由服务端 farm_instance 取代，这里只剩缓存语义。

const PATH := "user://farm_choice.json"

static func save(layout_patch_id: String, revision: int, location: Dictionary = {}, farm_terrain: Dictionary = {}, region_id := "") -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("FarmChoice: 选择保存失败 err=%d path=%s" % [FileAccess.get_open_error(), PATH])
		return
	var choice := {"layout_patch_id": layout_patch_id, "revision": revision}
	if FarmPlacement.is_valid(location):
		choice["location"] = {"lat": float(location.lat), "lng": float(location.lng)}
	if not farm_terrain.is_empty():
		choice["farm_terrain"] = farm_terrain.duplicate(true)
		choice["region_id"] = region_id
	# Frozen terrain must retain the server's geometry through cache round trips.
	f.store_string(JSON.stringify(choice, "", true, true))

static func load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("layout_patch_id"):
		return {}
	var choice := {"layout_patch_id": str(parsed.layout_patch_id), "revision": int(parsed.get("revision", 1))}
	if FarmPlacement.is_valid(parsed.get("location")):
		choice["location"] = {"lat": float(parsed.location.lat), "lng": float(parsed.location.lng)}
	if parsed.get("farm_terrain") is Dictionary:
		choice["farm_terrain"] = parsed.farm_terrain.duplicate(true)
		choice["region_id"] = str(parsed.get("region_id", ""))
	return choice

static func save_choice(choice: Dictionary) -> void:
	save(str(choice.get("layout_patch_id", "")), int(choice.get("revision", choice.get("blueprint_revision", 1))),
		choice.get("location", {}), choice.get("farm_terrain", {}), str(choice.get("region_id", "")))

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
