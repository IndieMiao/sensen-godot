extends Node
## Art-preview selection only. It cannot claim land or attach to the game's session.
signal changed
signal candidates_found(rows: Array)
signal farm_ready(farm: Dictionary)
signal load_diagnostic(details: Dictionary)
const Contract := preload("res://modules/dynamic_farm/map/geo_contract.gd")
const MapConfig := preload("res://modules/dynamic_farm/map/geo_map_config.gd")
const Metadata := preload("res://modules/dynamic_farm/map/parcel_metadata.gd")
const FarmData := preload("res://modules/dynamic_farm/farm_data.gd")
const PROMPT := "Tap a building to preview a farm."
const QUERY_RETRY_DELAY_MS := 600 # Default before the single automatic re-query; config query_retry_delay_ms overrides.
const QUERY_TIMEOUT_S := 8.0
# A DataSF building layer Mapbox cannot parse never loads and reports no source error (C-43 V-167): taps answer
# "loading" forever. Not ready this long after the sources are set counts as a map load error. Config
# buildings_load_timeout_ms overrides (clamped 5–300 s).
const BUILDINGS_LOAD_TIMEOUT_MS := 45000
const QUERY_FAILED := "Parcel details could not load. Tap Retry."
const MAP_FAILED := "Map details could not load. Tap Retry."
const FINDING := "Finding parcel…"
const LOADING := "Loading map details…"
## Below the selectable zoom the parcel layers are not drawn, so they do not load there (C-130 V-362): the map is not
## stuck loading, it waits for the player to zoom in.
const ZOOM_IN := "Zoom in to choose a farm."
const TOO_SMALL := "This parcel is too small to be your main farm. Please choose a larger one." # Q-56
const MIN_CORE_CELLS := 400 # C-43 default; config min_core_cells overrides (clamped 1–8192).
# Definite native answers: retrying cannot change them, so they are not failures.
const SETTLED := {"building_without_parcel": "No selectable parcel here.", "invalid_point": "No selectable parcel here.", "too_many_candidates": "Zoom in to choose a farm."}
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
var _retry_left := -1.0
var _retried := false
var _point := Vector2.ZERO
var _query_failed := false
var _map_retried := false
var _reload_left := -1.0
var _resume_tap := false
var _map_loading := false # C-94: this map is still loading (not failed); a tap now waits for it like a cold start.
var _failed_generation := -1 # Map being replaced by the automatic reload; its later signals are the same failure.
var _buildings_left := -1.0 # Countdown for the DataSF building layer of the current map; -1 when not waiting.
var _buildings_wait := false # The current DataSF map has not reported its building layer loaded; taps wait for it.
var _buildings_started := 0 # When the current map's sources were set; the wait for its building layer is logged (C-118).
var _refetch_buildings := false # C-124: after Retry or the building timeout the next setup fetches a still-loading copy again.
var _view_zoom := -1.0 # Last camera zoom reported to camera_changed or tap; -1 until known.
var _kind := ""
var _key := ""
var _options: Array = []
var _connected := false

## auto=true is the single automatic reload after a map load error; it keeps the waiting tap.
func activate(auto := false) -> void:
	if not auto: _map_retried = false; _resume_tap = false; _failed_generation = -1
	_reload_left = -1.0; _buildings_left = -1.0; _buildings_wait = false
	suspended = false; _map_loading = true
	_epoch += 1
	var epoch := _epoch
	var started := Time.get_ticks_msec()
	if api == null or bridge == null or not bridge.supports_parcels():
		_record_load("client_manifest", "bridge_unavailable", epoch, started)
		_fail("This preview needs the Android parcel map."); return
	if not _connected:
		bridge.parcel_ready.connect(_native_ready)
		bridge.parcel_query_result.connect(_query_result)
		bridge.parcel_error.connect(_native_error)
		_connected = true
	map_ready = false; busy = true; selection = {}; _options = []; _pending = -1; _retry_left = -1.0; _query_failed = false
	message = FINDING if _resume_tap else "Loading dynamic farm map…"; changed.emit()
	var pin := str(config.get("manifest_sha256", ""))
	if RegEx.create_from_string("^[0-9a-f]{64}$").search(pin) == null or not Contract.valid_dataset(config.get("dataset_version")):
		_record_load("client_manifest", "configuration_rejected", epoch, started)
		_fail("This preview service is not configured."); return
	api.base_url = str(config.get("base_url", ""))
	_record_load("client_manifest", "request", epoch, started)
	var data: Dictionary = await api.request("/client-manifest.json", pin)
	if epoch != _epoch or suspended:
		_record_load("client_manifest", "superseded", epoch, started); return
	var native := MapConfig.build(data, api.base_url, config)
	if not Contract.envelope(data, str(config.dataset_version)) or native.is_empty():
		_record_load("client_manifest", "validation_rejected", epoch, started)
		_fail("Could not load this farm map. Tap Retry."); return
	_record_load("client_manifest", "validation_accepted", epoch, started)
	manifest = data
	if generation > 0: bridge.clear_parcel_layers(generation)
	generation = MapBridge.next_parcel_generation(); style_generation = -1
	busy = false; message = FINDING if _resume_tap else _loading_text()
	if _refetch_buildings: native["refetch_buildings"] = true; _refetch_buildings = false
	bridge.set_parcel_sources(generation, JSON.stringify(native))
	if native.building_source == "datasf":
		_buildings_wait = true; _buildings_left = buildings_load_timeout(); _buildings_started = Time.get_ticks_msec()
	# C-130: after the sources, so what follows this generation (the starter zone marker) reaches native after them.
	changed.emit()

func pause() -> void:
	suspended = true; _epoch += 1; _pending = -1; _retry_left = -1.0; _query_failed = false; map_ready = false; busy = false
	_reload_left = -1.0; _resume_tap = false; _failed_generation = -1; _buildings_left = -1.0; _buildings_wait = false
	_map_loading = false; selection = {}; _options = []; _key = ""
	if api != null: api.cancel_all()
	if bridge != null:
		if generation > 0: bridge.clear_parcel_layers(generation)
		bridge.set_map_visible(false)

func _native_ready(gen: int, style: int, payload: String) -> void:
	if suspended or gen != generation or gen == _failed_generation or style < style_generation: return
	var data := _parse(payload)
	var reset := style != style_generation
	if reset:
		_pending = -1; _retry_left = -1.0; _query_failed = false; selection = {}; _options = []; _key = ""
	style_generation = style
	if data.get("buildings_source_ready") == true:
		if _buildings_wait: _record_load("buildings", "ready", _epoch, _buildings_started)
		_buildings_left = -1.0; _buildings_wait = false
	var was_ready := map_ready
	map_ready = data.get("source_ready") == true and str(data.get("error", "")).is_empty()
	_map_loading = not map_ready
	if map_ready and _resume_tap and not _buildings_wait:
		# The reloaded map (or its building layer) answers the waiting tap; a reload was that tap's one retry.
		_resume_tap = false; message = FINDING; changed.emit(); _send_query(); return
	if _querying(): message = FINDING # Native idle readiness arrives while a tap waits.
	elif not map_ready: message = _loading_text()
	# Idle readiness also follows every highlight change: it must not replace the chosen parcel's message (C-43 V-199).
	elif reset or not was_ready: message = PROMPT
	changed.emit()

func _native_error(gen: int, style: int, code: String) -> void:
	if suspended or gen != generation or style < style_generation: return
	if gen == _failed_generation: return # One outage reports per tile/source; the reload already answers it.
	var tap := _querying()
	var retry_sent := _retried and _retry_left < 0.0 # A scheduled, unsent re-query is replaced by the reload.
	map_ready = false; _pending = -1; _retry_left = -1.0; _query_failed = false; _buildings_left = -1.0
	# Native reuses a building copy still loading (C-118); one that timed out is not waited for again (C-124).
	if code == "buildings_source_timeout": _refetch_buildings = true
	# Offline tiles and service failures arrive here, not as query answers. Reload once before telling the player.
	var retry := not _map_retried and not (tap and retry_sent)
	print("DYNAMIC_MAP_ERROR ", JSON.stringify({"code":code, "tap":tap, "retry":retry}))
	if not retry: _fail(MAP_FAILED); return
	_map_retried = true; _resume_tap = tap; _retried = _retried or tap; _failed_generation = gen
	busy = true; _reload_left = retry_delay()
	message = FINDING if tap else LOADING; changed.emit()

func camera_changed(zoom := -1.0) -> void:
	if zoom >= 0.0: _view_zoom = zoom
	var waiting := _resume_tap
	_pending = -1; _retry_left = -1.0; _query_failed = false; _resume_tap = false; _options = []
	if map_ready and not busy:
		message = PROMPT; changed.emit()
	elif waiting and not busy: # C-94: a tap waiting for the loading map is cancelled; the map is still loading.
		message = _loading_text(); changed.emit()
	elif _map_loading and not busy and message != _loading_text() and message in [LOADING, ZOOM_IN]:
		message = _loading_text(); changed.emit() # Zoomed across the selectable zoom while the map loads.

## C-94: while the map is still loading ("Loading map details…") the tap waits and is sent once it is ready.
func tap(point: Vector2, zoom: float) -> void:
	if suspended or busy or not (map_ready or _map_loading): return
	_view_zoom = zoom
	if zoom < float(manifest.native_map.get("minzoom", 16)):
		message = "Zoom in to choose a farm."; changed.emit(); return
	selection = {}; _options = []; _key = ""
	bridge.set_parcel_building_highlight(generation, "")
	_point = point
	_start_query()

## Retry button: re-query the failed tap in place; otherwise reload the map and any building copy still loading.
func retry() -> void:
	if suspended or busy: return
	if _query_failed and map_ready: _start_query()
	else: _refetch_buildings = true; activate()

func _start_query() -> void:
	message = FINDING; changed.emit()
	_retried = false; _retry_left = -1.0; _query_failed = false
	# C-94: sent by _native_ready once the loading map (and its DataSF building layer) is ready. The map's own
	# automatic reload, if already used, is not given back to this tap.
	if not map_ready: _resume_tap = true; return
	_map_retried = false
	if _buildings_wait: _resume_tap = true; return # Sent once the DataSF building layer loads (C-43 V-199).
	_send_query()

func _send_query() -> void:
	_request += 1; _pending = _request; _query_left = QUERY_TIMEOUT_S
	bridge.query_parcel_at(_request, generation, _point)

func _querying() -> bool:
	return _pending >= 0 or _retry_left >= 0.0 or _resume_tap

func retry_delay() -> float:
	var raw = config.get("query_retry_delay_ms", QUERY_RETRY_DELAY_MS)
	if not (raw is int or raw is float): raw = QUERY_RETRY_DELAY_MS
	return clampf(float(raw), 0.0, 5000.0) / 1000.0

func buildings_load_timeout() -> float:
	var raw = config.get("buildings_load_timeout_ms", BUILDINGS_LOAD_TIMEOUT_MS)
	if not (raw is int or raw is float) or not is_finite(float(raw)): raw = BUILDINGS_LOAD_TIMEOUT_MS
	return clampf(float(raw), 5000.0, 300000.0) / 1000.0

func _query_result(request: int, gen: int, style: int, payload: String) -> void:
	if suspended or busy or gen != generation or style != style_generation or request != _pending: return
	_pending = -1
	var data := _parse(payload)
	var code := str(data.get("error", ""))
	if SETTLED.has(code):
		_record_query(request, code, false)
		message = SETTLED[code]; changed.emit(); return
	if not code.is_empty() or not data.get("parcel_ids") is Array or not data.get("properties") is Array:
		_query_error(request, "malformed" if code.is_empty() else code); return
	_kind = str(data.get("kind", "")); _key = str(data.get("building_key", ""))
	if _kind == "none" and data.parcel_ids.is_empty() and data.properties.is_empty() and _key.is_empty():
		_record_query(request, "ok", false)
		message = "No selectable parcel here."; changed.emit(); return
	var provider := str(config.get("building_source", "mapbox"))
	if _kind not in ["building", "parcel"] or (_kind == "building" and (_key.is_empty() or _key.length() > 512 or data.get("building_source") != provider)) or (_kind == "parcel" and not _key.is_empty()):
		_query_error(request, "contract_rejected"); return
	_record_query(request, "ok", false)
	# q(336): only a building's filled footprint selects. Open ground (the bare parcel outline) selects nothing.
	if _kind == "parcel":
		message = PROMPT; changed.emit(); return
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
		bridge.set_parcel_building_highlight(generation, _key, id)
		if int(row.core_cell_count) < min_core_cells():
			selection = {}; message = TOO_SMALL; changed.emit(); return
		selection = row.duplicate(true)
		message = "Ready to preview this farm."; changed.emit(); return

func min_core_cells() -> int:
	var raw = config.get("min_core_cells", MIN_CORE_CELLS)
	if not (raw is int or raw is float) or not is_finite(float(raw)): raw = MIN_CORE_CELLS
	return int(clampf(float(raw), 1, FarmData.MAX_CELLS)) # Clamp before int(): 1e30 must not wrap.

func open_farm() -> void:
	if suspended or not map_ready or busy or selection.is_empty(): return
	var id := str(selection.block_id)
	var epoch := _epoch
	busy = true; message = "Loading dynamic farm…"; changed.emit()
	var started := Time.get_ticks_msec()
	_record_load("farm", "request", epoch, started)
	var farm: Dictionary = await api.request(Contract.farm_path(id))
	if epoch != _epoch or suspended:
		_record_load("farm", "superseded", epoch, started); return
	busy = false
	var decoded := FarmData.decode(farm) if Contract.farm_matches(farm, id, str(manifest.dataset_version)) else {}
	if decoded.get("ok") != true:
		_record_load("farm", "validation_rejected", epoch, started)
		_fail("This farm could not load. Please try again."); return
	if decoded.counts.core < min_core_cells():
		_record_load("farm", "too_small", epoch, started)
		selection = {}; _fail(TOO_SMALL); return
	_record_load("farm", "validation_accepted", epoch, started)
	farm_ready.emit(farm)

func _record_load(resource: String, stage: String, epoch: int, started: int) -> void:
	# validation_rejected is the caller gate, not a transport-cause claim. Read the preceding HTTP outcome.
	var row := {"resource":resource, "stage":stage, "epoch":epoch, "elapsed_ms":Time.get_ticks_msec() - started}
	print("DYNAMIC_LOAD ", JSON.stringify(row))
	load_diagnostic.emit(row.duplicate(true))

func _query_error(request: int, outcome: String) -> void:
	var retry := not _retried
	_record_query(request, outcome, retry)
	# One quiet re-query before any error: native busy/loading answers are usually gone moments later.
	if retry: _retried = true; _retry_left = retry_delay(); return
	_fail(QUERY_FAILED); _query_failed = true

func _record_query(request: int, outcome: String, retry: bool) -> void:
	# Native outcome code only: no point, parcel, building key or coordinates.
	print("DYNAMIC_QUERY ", JSON.stringify({"request":request, "outcome":outcome, "attempt":2 if _retried else 1, "retry":retry}))

## While the map loads: the parcel layers load only where drawn, from the selectable zoom (C-130 V-362).
func _loading_text() -> String:
	return LOADING if _buildings_drawn() else ZOOM_IN

## The DataSF building layer is drawn, so loads, only from the selectable zoom; below it the countdown waits. The same
## holds for the parcel layers, whose native load timeout also waits (C-130 V-362).
func _buildings_drawn() -> bool:
	return _view_zoom < 0.0 or manifest.is_empty() or _view_zoom >= float(manifest.native_map.get("minzoom", 16))

func _process(delta: float) -> void:
	if _buildings_left >= 0.0 and not suspended and _buildings_drawn():
		_buildings_left -= delta
		if _buildings_left < 0.0:
			_buildings_left = -1.0; _native_error(generation, style_generation, "buildings_source_timeout"); return
	if _reload_left >= 0.0:
		_reload_left -= delta
		if _reload_left < 0.0:
			_reload_left = -1.0
			if not suspended: activate(true)
		return
	if _retry_left >= 0.0:
		_retry_left -= delta
		if _retry_left < 0.0:
			_retry_left = -1.0
			if not suspended and map_ready and not busy: _send_query()
		return
	if _pending < 0: return
	_query_left -= delta
	if _query_left <= 0:
		_record_query(_pending, "timeout", false)
		_pending = -1; _fail("The map did not respond. Tap again or Retry.")

func _fail(text: String) -> void:
	busy = false; _resume_tap = false; _map_loading = false; _reload_left = -1.0; message = text; changed.emit()

static func _parse(text: String) -> Dictionary:
	var parser := JSON.new()
	return parser.data if parser.parse(text) == OK and parser.data is Dictionary else {}

func _exit_tree() -> void:
	pause()
	if _connected and bridge != null:
		bridge.parcel_ready.disconnect(_native_ready)
		bridge.parcel_query_result.disconnect(_query_result)
		bridge.parcel_error.disconnect(_native_error)
