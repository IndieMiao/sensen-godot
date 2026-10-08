class_name P0RoomPreload
extends RefCounted
## SGODOT-252: what a P0 room builds from in its _ready (its kit's art scene, the models and textures its layout
## names), so AppRouter can load them on worker threads under the scene's loading cover. The art scripts then find
## them cached instead of loading them on the main thread: a main-thread load() that waits on the worker pool
## never finished on a 1-core Android device (Coffee Shop, every launch; Godot's default pool there is one thread),
## and sometimes on 2 cores (SGODOT-227, #82).

const OUTPOST := "res://scenes/p0/p0_outpost.tscn"
const FARMHOUSE := "res://scenes/p0/rooms/p0_farmhouse.tscn"
const SHARED_PLANTS := "res://assets/rooms/_shared/plants/"
## Files the art scripts load by name besides those their layouts list (absent ones are skipped).
const KIT_EXTRAS := ["room_albedo_ao.png", "window_landscape.png", "fire_gradient.png"]
const SHARED_EXTRAS := ["room_albedo_ao.png", "material.tres"]
const EXTENSIONS := ["glb", "gltf", "png", "jpg", "tres", "res", "tscn", "scn"]

## AppRouter.preload_paths: the resources a scene opened with `args` builds from; empty for scenes that need none.
static func paths_for(scene_path: String, args: Dictionary) -> PackedStringArray:
	if scene_path == OUTPOST:
		var outpost := P0Outposts.find(str(args.get("outpost_id", "")))
		return kit_paths(str(outpost.get("art", "basic_room"))) if not outpost.is_empty() else PackedStringArray()
	if scene_path == FARMHOUSE: return kit_paths("basic_room")
	return PackedStringArray()

## A kit's art scene, every resource file its layout names (kit-relative names resolve in the kit, then in the shared
## plant library), the files its art script loads by name, and the shared plant library's atlas and material.
static func kit_paths(kit: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := "res://assets/rooms/%s/" % kit
	_add(out, "res://scenes/%s/%s_art.tscn" % [kit, kit])
	var text := FileAccess.get_file_as_string(dir + "layout.json")
	var layout = JSON.parse_string(text) if text != "" else null
	if layout is Dictionary:
		for f in _files(layout):
			if f.begins_with("res://"): _add(out, f)
			elif not _add(out, dir + f): _add(out, SHARED_PLANTS + f)
	for f in KIT_EXTRAS: _add(out, dir + f)
	for f in SHARED_EXTRAS: _add(out, SHARED_PLANTS + f)
	return out

## Adds `path` once when it is a resource the build has; false when it is not.
static func _add(out: PackedStringArray, path: String) -> bool:
	if not ResourceLoader.exists(path): return false
	if not out.has(path): out.append(path)
	return true

## Every string in the layout that names a resource file, in document order.
static func _files(v) -> PackedStringArray:
	var out := PackedStringArray()
	if v is Dictionary:
		for k in v: out.append_array(_files(v[k]))
	elif v is Array:
		for e in v: out.append_array(_files(e))
	elif v is String and str(v).get_extension().to_lower() in EXTENSIONS:
		out.append(str(v))
	return out
