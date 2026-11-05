extends SceneTree
## Validate delivered pixels against the game's own navigation and the supplied
## slot contract, independently of the Python baking implementation.
var checks: Array = []
func check(ok: bool, label: String) -> void:
	checks.append({"check":label,"passed":ok})
	if not ok: push_error(label)
func _initialize() -> void:
	var slots: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://pond_slots_v2.json"))
	var uids: Array = []
	for name in ["dry_ground_mask", "meadow_color", "crescent_layout", "gourd_layout", "meander_layout"]:
		var path: String = "res://assets/ponds/ground/" + name + ".png"
		var texture: Texture2D = load(path)
		var imported: Image = texture.get_image()
		check(imported.has_mipmaps(), name+": imported mip chain")
		imported.clear_mipmaps()
		var source := Image.load_from_file(ProjectSettings.globalize_path(path))
		imported.convert(Image.FORMAT_RGBA8)
		source.convert(Image.FORMAT_RGBA8)
		check(source.get_data() == imported.get_data(), name+": imported RGBA bytes equal PNG; no alpha-border corruption")
		check(imported.get_width() <= 2048 and imported.get_height() <= 2048, name+": <=2048")
		var cfg := ConfigFile.new()
		check(cfg.load(path+".import") == OK, name+": import sidecar")
		var uid: String = cfg.get_value("remap", "uid", "")
		check(uid.begins_with("uid://") and uid not in uids, name+": unique Godot UID")
		uids.append(uid)
		if name in ["meadow_color", "dry_ground_mask"]: continue
		var shape: String = name.trim_suffix("_layout")
		var entry: Dictionary = SystemPonds.data().locations.filter(func(e): return e.template_id == shape)[0]
		var bp := SystemPonds.blueprint(entry)
		var violations := {"navigation":0,"boundary_buffer":0,"footprint":0,"stand":0,"pebble_clearance":0}
		var ink := 0
		for j in source.get_height():
			for i in source.get_width():
				var c := source.get_pixel(i,j)
				if c.b == 0 and c.a == 0: continue
				ink += 1
				var p := Vector3(-4+(i+.5)*20/source.get_width(),0,-20+(j+.5)*24/source.get_height())
				if not bp.is_walkable(bp.world_to_cell(p)): violations.navigation += 1
				for offset in [Vector3(.15,0,0),Vector3(-.15,0,0),Vector3(0,0,.15),Vector3(0,0,-.15)]:
					if not bp.is_walkable(bp.world_to_cell(p+offset)): violations.boundary_buffer += 1
				for s in slots.shapes[shape].values():
					if abs(p.x-float(s.x)) <= .75 and abs(p.z-float(s.z)) <= .75: violations.footprint += 1
					if Vector2(p.x-float(s.stand[0]),p.z-float(s.stand[1])).length() < .28: violations.stand += 1
					if c.a > 0 and Vector2(p.x-float(s.x),p.z-float(s.z)).length() < 1.5: violations.pebble_clearance += 1
		check(ink > 100, shape+": nonempty painted path/dirt")
		for key in violations: check(violations[key] == 0, shape+": zero "+key+" violations across every painted texel")
	var passed := checks.all(func(c): return c.passed)
	var output := ProjectSettings.globalize_path("res://../map-validation.json")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":passed,"checks":checks},"\t")+"\n")
	print("WILD_GROUND_MAP_VERIFY ",passed," ",checks.size()," checks")
	quit(0 if passed else 1)
