class_name P0RoomAnchors
extends RefCounted
## World anchors of an indoor P0 space (WP7-B "F-03 ③" naming table, SGODOT-226). Anchors live in the art's
## layout.json `anchors` list; during the placeholder period a separate `<space>.anchors.json` with the same
## format adds or overrides them by name, so swapping in the final model only swaps the art reference.
## Entry fields: name, position [x, y, z] in layout metres (Y up), yaw_degrees (stand_ / npc_ / seat_ / sign_ /
## spawn), module (assets[].name it shows and hides with), size [w, h] (sign_ only).

const PREFIXES := ["use", "badge", "stand", "npc", "seat", "drop", "cam", "sign"]
## Anchors that face somewhere (WP7-B §3 / §4).
const FACING := ["stand", "npc", "seat", "sign", "spawn"]
## Godot treats glb node names ending in these words as import hints (WP7-B §5).
const IMPORT_HINTS := ["col", "colonly", "convcol", "navmesh", "occ", "occonly", "rigid", "vehicle", "wheel", "noimp", "loop", "cycle"]

static func read_json(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path): return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}

## The layout's anchors, then the external file's (same name replaces). A layout without a `spawn` anchor
## falls back to its legacy top-level `spawn` point (Basic Room).
static func merge(layout: Dictionary, external: Dictionary) -> Array:
	var by_name := {}
	var order: Array = []
	for list in [layout.get("anchors", []), external.get("anchors", [])]:
		for a in list:
			if not (a is Dictionary) or not a.has("name"): continue
			var name := str(a.name)
			if not by_name.has(name): order.append(name)
			by_name[name] = (a as Dictionary).duplicate(true)
	if not by_name.has("spawn") and layout.get("spawn", null) is Array:
		order.append("spawn")
		by_name["spawn"] = {"name": "spawn", "position": layout.spawn, "yaw_degrees": 180}
	return order.map(func(n): return by_name[n])

static func vec(a) -> Vector3:
	if not (a is Array) or (a as Array).size() < 3: return Vector3.ZERO
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

## "use_stove_1" → "use"; "spawn" / "exit" → themselves.
static func prefix_of(name: String) -> String:
	return name if name in ["spawn", "exit"] else name.get_slice("_", 0)

## "use_stove_1" → "stove_1".
static func object_of(name: String) -> String:
	var p := prefix_of(name)
	return "" if p == name else name.substr(p.length() + 1)

## Where a player stands to use `name`: stand_<object>, else stand_<object without its number>
## (use_stove_1 → stand_stove_1, stand_stove). "" when neither exists.
static func stand_for(name: String, names: Array) -> String:
	var obj := object_of(name)
	if obj == "": return ""
	var candidates := ["stand_" + obj]
	var parts := obj.split("_")
	if parts.size() > 1 and parts[-1].is_valid_int(): candidates.append("stand_" + "_".join(parts.slice(0, -1)))
	for c in candidates:
		if names.has(c): return c
	return ""

## Naming-table checks (WP7-B §7): format, prefix, duplicates, unknown modules, missing yaw / size.
static func validate(anchors: Array, modules: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	var format := RegEx.create_from_string("^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
	for a in anchors:
		var name := str(a.get("name", ""))
		if seen.has(name): errors.append("%s: duplicate name" % name)
		seen[name] = true
		if format.search(name) == null:
			errors.append("%s: use lower-case words joined by underscores" % name)
			continue
		var p := prefix_of(name)
		if p != name and not PREFIXES.has(p): errors.append("%s: unknown prefix %s_" % [name, p])
		if p != name and object_of(name) == "": errors.append("%s: missing object name" % name)
		var words := name.split("_")
		var last := ""
		for i in range(words.size() - 1, -1, -1):
			if not words[i].is_valid_int():
				last = words[i]
				break
		if IMPORT_HINTS.has(last): errors.append("%s: ends in the Godot import hint '%s'" % [name, last])
		if not (a.get("position", null) is Array) or (a.position as Array).size() != 3:
			errors.append("%s: position must be [x, y, z]" % name)
		if FACING.has(p) and not a.has("yaw_degrees"): errors.append("%s: needs yaw_degrees" % name)
		if p == "sign" and not (a.get("size", null) is Array): errors.append("%s: needs size [w, h]" % name)
		if a.has("module") and not modules.has(str(a.module)): errors.append("%s: unknown module %s" % [name, str(a.module)])
	return errors
