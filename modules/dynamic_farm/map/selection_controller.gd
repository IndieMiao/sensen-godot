extends Node
## Art-preview selection only. It cannot claim land or attach to the game's session.
signal changed
signal candidates_found(rows: Array)
signal farm_ready(farm: Dictionary)
const Contract := preload("res://modules/dynamic_farm/map/geo_contract.gd")
const MapConfig := preload("res://modules/dynamic_farm/map/geo_map_config.gd")
const Metadata := preload("res://modules/dynamic_farm/map/parcel_metadata.gd")
const FarmData := preload("res://modules/dynamic_farm/farm_data.gd")
var api: Node
var bridge: MapBridge
var config: Dictionary = {}
var manifest: Dictionary = {}
var selection: Dictionary = {}
var message := "Loading dynamic farm map…"
var map_ready := false
var busy := false
var suspended := true
var generation := 0
var style_generation := -1
var _epoch := 0
var _request := 0
var _pending := -1
var _query_left := 0.0
var _kind := "parcel"
var _key := ""
var _highlighted_parcel := ""
var _options: Array = []
var _connected := false

func activate() -> void:
	_clear_parcel_selection()
	suspended = false
	_epoch += 1
	var epoch := _epoch
	if api == null or bridge == null or not bridge.supports_parcels():
		_fail("This preview needs the Android parcel map."); return
	if not _connected:
		bridge.parcel_ready.connect(_native_ready)
		bridge.parcel_query_result.connect(_query_result)
		bridge.parcel_error.connect(_native_error)
		_connected = true
	map_ready = false; busy = true; selection = {}; _options = []; _pending = -1
	message = "Loading dynamic farm map…"; changed.emit()
	var pin := str(config.get("manifest_sha256", ""))
	if RegEx.create_from_string("^[0-9a-f]{64}$").search(pin) == null or config.get("dataset_version") != Contract.DATASET:
		_fail("This preview service is not configured."); return
	api.base_url = str(config.get("base_url", ""))
	var data: Dictionary = await api.request("/client-manifest.json", pin)
	if epoch != _epoch or suspended: return
	var native := MapConfig.build(data, api.base_url, config)
	if not Contract.envelope(data) or native.is_empty():
		_fail("Could not load this farm map. Tap Retry."); return
	manifest = data
	if generation > 0: bridge.clear_parcel_layers(generation)
	generation = MapBridge.next_parcel_generation(); style_generation = -1
	busy = false; message = "Loading map details…"; changed.emit()
	bridge.set_parcel_sources(generation, JSON.stringify(native))

func pause() -> void:
	suspended = true; _epoch += 1; _pending = -1; map_ready = false; busy = false
	selection = {}; _options = []; _key = ""
	_highlighted_parcel = ""
	if api != null: api.cancel_all()
	if bridge != null:
		if generation > 0: bridge.clear_parcel_layers(generation)
		bridge.set_map_visible(false)

func _native_ready(gen: int, style: int, payload: String) -> void:
	if suspended or gen != generation or style < style_generation: return
	var data := _parse(payload)
	if style != style_generation:
		_clear_parcel_selection()
		_pending = -1; selection = {}; _options = []; _key = ""
	style_generation = style
	map_ready = data.get("source_ready") == true and str(data.get("error", "")).is_empty()
	message = "Tap a building or open ground to preview a farm." if map_ready else "Loading map details…"
	changed.emit()

func _native_error(gen: int, style: int, _code: String) -> void:
	if suspended or gen != generation or style < style_generation: return
	map_ready = false; _pending = -1
	_fail("Map details could not load. Tap Retry.")

func camera_changed() -> void:
	_pending = -1; _options = []
	if map_ready and not busy:
		message = "Tap a building or open ground to preview a farm."; changed.emit()

func tap(point: Vector2, zoom: float) -> void:
	if suspended or not map_ready or busy: return
	if zoom < float(manifest.native_map.get("minzoom", 16)):
		message = "Zoom in to choose a farm."; changed.emit(); return
	_request += 1; _pending = _request; _query_left = 8.0
	_clear_parcel_selection()
	selection = {}; _options = []; _key = ""
	bridge.set_parcel_building_highlight(generation, "")
	message = "Finding parcel…"; changed.emit()
	bridge.query_parcel_at(_request, generation, point)

func _query_result(request: int, gen: int, style: int, payload: String) -> void:
	if suspended or busy or gen != generation or style != style_generation or request != _pending: return
	_pending = -1
	var data := _parse(payload)
	if not str(data.get("error", "")).is_empty() or not data.get("parcel_ids") is Array or not data.get("properties") is Array:
		_fail("Could not check that location. Tap again."); return
	_kind = str(data.get("kind", "")); _key = str(data.get("building_key", ""))
	if _kind == "none" and data.parcel_ids.is_empty() and data.properties.is_empty() and _key.is_empty():
		message = "No selectable parcel here."; changed.emit(); return
	var provider := str(config.get("building_source", "mapbox"))
	if _kind not in ["building", "parcel"] or (_kind == "building" and (_key.is_empty() or _key.length() > 512 or data.get("building_source") != provider)) or (_kind == "parcel" and not _key.is_empty()):
		_fail("Could not check that location. Tap again."); return
	_options = []
	var seen := {}
	for raw in data.properties:
		var row := Metadata.decode(raw)
		if row.is_empty() or not data.parcel_ids.has(row.block_id) or seen.has(row.block_id): continue
		seen[row.block_id] = true; _options.append(row)
	if _options.is_empty():
		message = "No selectable parcel here."; changed.emit(); return
	message = "Choose a parcel to preview."; changed.emit()
	if _options.size() == 1: choose(str(_options[0].block_id))
	else: candidates_found.emit(_options.duplicate(true))

func choose(id: String) -> void:
	if suspended or not map_ready or busy: return
	for row in _options:
		if row.block_id != id: continue
		_clear_parcel_selection()
		selection = row.duplicate(true)
		if _kind == "parcel":
			_highlighted_parcel = id
			bridge.set_parcel_states(generation, JSON.stringify([{"block_id": id, "selected": true, "claimed": false, "own": false}]))
		bridge.set_parcel_building_highlight(generation, _key if _kind == "building" else "")
		message = "Ready to preview this farm."; changed.emit(); return

func _clear_parcel_selection() -> void:
	if not _highlighted_parcel.is_empty() and bridge != null and generation > 0:
		bridge.set_parcel_states(generation, JSON.stringify([{"block_id": _highlighted_parcel, "selected": false, "claimed": false, "own": false}]))
	_highlighted_parcel = ""

func open_farm() -> void:
	if suspended or not map_ready or busy or selection.is_empty(): return
	var id := str(selection.block_id)
	var epoch := _epoch
	busy = true; message = "Loading dynamic farm…"; changed.emit()
	var farm: Dictionary = await api.request(Contract.farm_path(id))
	if epoch != _epoch or suspended: return
	busy = false
	if not Contract.farm_matches(farm, id) or FarmData.decode(farm).get("ok") != true:
		_fail("This farm could not load. Please try again."); return
	farm_ready.emit(farm)

func _process(delta: float) -> void:
	if _pending < 0: return
	_query_left -= delta
	if _query_left <= 0:
		_pending = -1; _fail("The map did not respond. Tap again or Retry.")

func _fail(text: String) -> void:
	busy = false; message = text; changed.emit()

static func _parse(text: String) -> Dictionary:
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK and parser.data is Dictionary else {}

func _exit_tree() -> void:
	pause()
	if _connected and bridge != null:
		bridge.parcel_ready.disconnect(_native_ready)
		bridge.parcel_query_result.disconnect(_query_result)
		bridge.parcel_error.disconnect(_native_error)
