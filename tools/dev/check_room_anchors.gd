extends SceneTree
## Checks a room's world anchors against the WP7-B naming table (SGODOT-226 / F-03 ③): name format and
## prefix, duplicates, import-hint endings, unknown modules, missing yaw_degrees / size. Run before handing
## in a scene (3D art) or a placeholder anchors file (engineering):
##   godot --headless --path . --script res://tools/dev/check_room_anchors.gd -- <layout.json> [<space>.anchors.json]
## Paths may be res:// or relative to the project. Exit code 0 = clean, 1 = problems (listed), 2 = bad usage.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("usage: -- <layout.json> [<space>.anchors.json]")
		quit(2)
		return
	var paths: Array = Array(args).map(func(p): return p if p.begins_with("res://") else "res://" + p)
	var layout := P0RoomAnchors.read_json(paths[0])
	if layout.is_empty():
		printerr("cannot read layout: " + paths[0])
		quit(2)
		return
	var external: Dictionary = P0RoomAnchors.read_json(paths[1]) if paths.size() > 1 else {}
	var modules: Array = []
	for list in [layout.get("assets", []), layout.get("instances", [])]:
		for a in list: modules.append(str(a.get("name", "")))
	var anchors := P0RoomAnchors.merge(layout, external)
	var errors := P0RoomAnchors.validate(anchors, modules)
	for e in errors: print("  ✗ " + e)
	print("%d anchors, %d problems" % [anchors.size(), errors.size()])
	quit(0 if errors.is_empty() else 1)
