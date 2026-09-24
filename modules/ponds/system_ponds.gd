class_name SystemPonds
extends RefCounted
## Published shared catalog: scene identity never depends on camera or local RNG.
const PATH := "res://assets/ponds/catalog.json"
const SCENE := "res://scenes/pond/pond.tscn"
const TITLES := {"crescent": "Crescent pond", "gourd": "Twin-bay pond", "meander": "Winding pond"}
static var _data: Dictionary = {}
static var _revision := ""

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data

static func revision() -> String:
	if _revision.is_empty(): _revision = FileAccess.get_sha256(PATH)
	return _revision

static func location(id: String) -> Dictionary:
	for entry in data().locations:
		if entry.id == id and entry.enabled: return entry.duplicate(true)
	return {}

static func template(id: String) -> Dictionary:
	return data().templates.get(id, {}).duplicate(true)

static func texture(id: String) -> Texture2D:
	return load("res://assets/ponds/%s.svg" % id) if TITLES.has(id) else null

static func site(entry: Dictionary) -> Dictionary:
	var spec := template(str(entry.get("template_id", "")))
	if spec.is_empty(): return {}
	return {"name": entry.name, "space": "pond", "stand": spec.navigation.spawn,
		"polygon": spec.polygon, "extent": spec.extent, "template_id": spec.id,
		"decoration_seed": entry.decoration_seed,
		"fish_weights": FishingModel.data().sites[spec.fish_profile].fish_weights}

static func blueprint(entry: Dictionary) -> FarmBlueprint:
	var spec := template(str(entry.template_id))
	var nav: Dictionary = spec.navigation
	var bp := FarmBlueprint.new()
	bp.layout_patch_id = str(entry.id)
	bp.revision = int(spec.revision)
	bp.region_id = str(entry.region_id)
	bp.cell_m = float(nav.cell)
	bp.cell_mm = roundi(bp.cell_m * 1000)
	bp.play_area_m = float(spec.extent[1])
	bp.play_area_mm = roundi(bp.play_area_m * 1000)
	bp.grid = Vector2i(str(nav.rows[0]).length(), nav.rows.size())
	bp.masks = {"walkable": PackedStringArray(nav.rows)}
	bp.anchors = {"spawn": Vector2i(floori(float(nav.spawn[0]) / bp.cell_m), floori(-float(nav.spawn[1]) / bp.cell_m))}
	return bp

static func validated_locations(payload: Dictionary, region: String) -> Array:
	var result := []
	if payload.get("version") != 1 or payload.get("catalog_revision") != revision() or not payload.get("available", false): return result
	if not payload.get("locations") is Array: return result
	var seen := {}
	for raw in payload.locations:
		if not raw is Dictionary: continue
		var entry := location(str(raw.get("id", "")))
		if entry.is_empty() or entry.region_id != region or seen.has(entry.id): continue
		var valid := true
		for key in ["lat", "lng", "template_id", "layout_revision", "decoration_seed", "enabled"]:
			if raw.get(key) != entry.get(key): valid = false
		if valid:
			seen[entry.id] = true
			result.append(entry)
	return result
