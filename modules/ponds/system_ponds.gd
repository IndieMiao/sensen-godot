class_name SystemPonds
extends RefCounted
## Published shared catalog: scene identity never depends on camera or local RNG.
const PATH := "res://assets/ponds/catalog.json"
const SCENE := "res://scenes/pond/pond.tscn"
const TITLES := {"crescent": "Crescent pond", "gourd": "Twin-bay pond", "meander": "Winding pond"}
## Map directory cell size, shared with the server (POND_CELL_DEG).
const CELL_DEG := 0.5
const _RECORD_KEYS := ["id", "region_id", "name", "lat", "lng", "template_id", "decoration_seed", "layout_revision", "enabled"]
static var _data: Dictionary = {}
static var _revision := ""
## Server-only ponds (added after the bundled catalog was frozen), learned from the cell directory
## or a party-travel ticket. The bundled file only has to supply the matching template.
static var _remote: Dictionary = {}

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
	return (_remote.get(id, {}) as Dictionary).duplicate(true)

static func cell_of(lat: float, lng: float) -> Vector2i:
	return Vector2i(floori(lng / CELL_DEG), floori(lat / CELL_DEG))

static func cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.y, cell.x]

## Accept one server record: a bundled pond must match field for field; a server-only pond must
## name a bundled template at the same layout revision. Returns {} when this build cannot host it.
static func accept(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	for key in _RECORD_KEYS:
		if not raw.has(key): return {}
	var id := str(raw.id)
	if not raw.enabled or not (raw.lat is float or raw.lat is int) or not (raw.lng is float or raw.lng is int): return {}
	for entry in data().locations:
		if entry.id != id: continue
		for key in _RECORD_KEYS:
			if raw.get(key) != entry.get(key): return {}
		return entry.duplicate(true)
	var spec := template(str(raw.template_id))
	if spec.is_empty() or int(raw.layout_revision) != int(spec.revision) or not RegEx.create_from_string("^pond_[a-z_]+_[0-9]{2}$").search(id): return {}
	var entry := {"kind": "pond", "category": "Fishing pond"}
	for key in _RECORD_KEYS: entry[key] = raw[key]
	entry.lat = float(raw.lat)
	entry.lng = float(raw.lng)
	entry.decoration_seed = int(raw.decoration_seed)
	entry.layout_revision = int(raw.layout_revision)
	_remote[id] = entry
	return entry.duplicate(true)

## GET /v1/ponds/cells → {"y:x": [entry, ...]} for the requested cells; {} when the directory
## is unavailable or was built for other templates (then the map shows no ponds rather than stale ones).
static func validated_cells(payload: Dictionary, keys: Array) -> Dictionary:
	if payload.get("version") != 2 or payload.get("catalog_revision") != revision() or not payload.get("available", false): return {}
	if float(payload.get("cell_deg", 0)) != CELL_DEG or not payload.get("cells") is Dictionary: return {}
	var result := {}
	for key in keys:
		var rows = payload.cells.get(key)
		if not rows is Array: return {}
		var seen := {}
		var accepted := []
		for raw in rows:
			var entry := accept(raw)
			if entry.is_empty() or seen.has(entry.id): continue
			seen[entry.id] = true
			accepted.append(entry)
		result[key] = accepted
	return result

## Legacy GET /v1/ponds?region_id= (servers without the cell directory): bundled ponds only.
static func validated_region(payload: Dictionary, region: String) -> Array:
	if payload.get("version") != 1 or payload.get("catalog_revision") != revision() or not payload.get("available", false): return []
	if not payload.get("locations") is Array: return []
	var result := []
	for raw in payload.locations:
		var entry := accept(raw)
		if not entry.is_empty() and str(entry.region_id) == region and not result.any(func(e): return e.id == entry.id): result.append(entry)
	return result

## P0's own outlines (SGODOT-374): laid over the frozen catalog's templates field by field (polygon, navigation,
## extent, art), keeping each template's id, revision and fish profile, so the server's template + layout revision 1
## still name them and catalog_revision does not move.
const P0_TEMPLATES := "res://assets/p0/p0_pond_templates.json"
static var _p0: Dictionary = {}
static var _p0_read := false

static func template(id: String) -> Dictionary:
	var spec: Dictionary = data().templates.get(id, {}).duplicate(true)
	if spec.is_empty(): return spec
	if not _p0_read:
		_p0_read = true
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(P0_TEMPLATES)) if FileAccess.file_exists(P0_TEMPLATES) else null
		_p0 = parsed.get("templates", {}) if parsed is Dictionary else {}
	spec.merge((_p0.get(id, {}) as Dictionary).duplicate(true), true)
	return spec

static func texture(id: String) -> Texture2D:
	return load("res://assets/ponds/%s.svg" % id) if TITLES.has(id) else null

static func site(entry: Dictionary) -> Dictionary:
	var spec := template(str(entry.get("template_id", "")))
	if spec.is_empty(): return {}
	return {"name": entry.name, "space": "pond", "stand": spec.navigation.spawn,
		"polygon": spec.polygon, "extent": spec.extent, "template_id": spec.id, "art": spec.get("art", ""),
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
