extends SceneTree
const Controller := preload("res://modules/dynamic_farm/map/selection_controller.gd")
const Api := preload("res://modules/dynamic_farm/map/geo_api.gd")
const Fixture := preload("res://tests/dynamic_farm/selection_fixtures.gd")
class Native extends MapBridge:
	var sources: Array = []
	var queries: Array = []
	var highlights: Array = []
	var states: Array = []
	var cleared: Array = []
	var visible := true
	func supports_parcels() -> bool: return true
	func set_parcel_sources(gen: int, config: String) -> void: sources.append([gen, config])
	func query_parcel_at(id: int, gen: int, point: Vector2) -> void: queries.append([id, gen, point])
	func set_parcel_building_highlight(gen: int, key: String, parcel := "") -> void: highlights.append([gen, key, parcel])
	func set_parcel_states(gen: int, batch: String) -> void: states.append([gen, JSON.parse_string(batch)])
	func clear_parcel_layers(gen: int) -> void: cleared.append(gen)
	func set_map_visible(value: bool) -> void: visible = value
var controller: Node
var native: Native
var api: Node
var checks := 0
var failures := 0
var paths: Array = []
var farms: Array = []
var options: Array = []
var hold := false
var hold_manifest := false
var wrong_farm := false
var stale_release := false
signal release
const R6 := "sf-dynamic-farm-20261124-r6"
func _initialize() -> void: _run.call_deferred()
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", text)
func transport(path: String) -> Dictionary:
	paths.append(path)
	if path == "/client-manifest.json":
		if hold_manifest: await release
		return Fixture.manifest()
	var data: Dictionary = Fixture.farm("p-B" if wrong_farm else path.get_file().get_basename())
	# An earlier release's directory (full URL, C-113) serves that release's farms.
	if path.begins_with("https://") and not stale_release: data.dataset_version = R6
	if hold: await release
	return data
func ready_signal(style := 1) -> void:
	native.parcel_ready.emit(controller.generation, style, '{"source_ready":true,"error":""}')
func reply(kind: String, rows: Array, key := "", provider := "mapbox") -> void:
	controller.tap(Vector2(.25, .6), 18)
	var request: Array = native.queries.back()
	native.parcel_query_result.emit(request[0], request[1], controller.style_generation,
		JSON.stringify({"kind":kind,"parcel_ids":rows.map(func(row: Dictionary): return row.block_id),
		"properties":rows,"building_key":key,"building_source":provider,"error":""}))
## Rows answer as a tapped building: since q(336) only a building's footprint selects (C-28).
func answer(error: String, rows: Array = []) -> void:
	var request: Array = native.queries.back()
	native.parcel_query_result.emit(request[0], request[1], controller.style_generation,
		JSON.stringify({"kind":"none" if rows.is_empty() else "building","parcel_ids":rows.map(func(row: Dictionary): return row.block_id),
		"properties":rows,"building_key":"" if rows.is_empty() else "building-1","building_source":"mapbox","error":error}))
func first_tap_retry() -> void:
	# C-27: native "loading" on a first tap re-queries once and keeps the loading hint instead of the error.
	var sent := native.queries.size()
	controller.tap(Vector2(.4, .4), 18); answer("loading")
	check(controller.message == "Finding parcel…" and controller.selection.is_empty(), "first transient failure keeps loading feedback, not the error")
	controller._process(controller.retry_delay() * .5)
	check(native.queries.size() == sent + 1, "re-query waits for the retry delay")
	controller._process(controller.retry_delay())
	check(native.queries.size() == sent + 2 and native.queries.back()[2] == Vector2(.4, .4), "single automatic re-query uses the same tapped point")
	ready_signal(controller.style_generation)
	check(controller.message == "Finding parcel…", "native idle readiness during a pending tap keeps loading feedback")
	answer("", [Fixture.metadata()])
	check(controller.selection.get("block_id") == "p-A" and not controller.message.contains("Could not check"), "first tap selects after the automatic re-query")
	controller.tap(Vector2(.4, .4), 18); answer("query_failed"); controller._process(controller.retry_delay() + .01)
	answer("building_load_failed")
	check(controller.message == Controller.QUERY_FAILED and not controller.busy, "persistent failure still reports after exactly one re-query")
	check(not controller.message.contains("Could not check"), "failure no longer uses the old could-not-check copy")
	controller._process(5.0)
	check(native.queries.size() == sent + 4, "no further automatic queries after the reported failure")
	var bootstraps := native.sources.size()
	controller.retry()
	check(native.queries.size() == sent + 5 and native.queries.back()[2] == Vector2(.4, .4) and native.sources.size() == bootstraps, "Retry re-queries the failed tap without reloading the map")
	check(controller.message == "Finding parcel…", "Retry shows loading feedback again")
	answer("", [Fixture.metadata("p-B")])
	check(controller.selection.get("block_id") == "p-B", "Retry after a reported failure selects the parcel")
	controller.tap(Vector2(.4, .4), 18); answer("", [Fixture.metadata()])
	check(controller.selection.get("block_id") == "p-A", "manual tap after a reported failure works")
	controller.tap(Vector2(.4, .4), 18); native.parcel_query_result.emit(native.queries.back()[0], controller.generation, controller.style_generation,
		JSON.stringify({"kind":"building","parcel_ids":["p-A"],"properties":[Fixture.metadata()],"building_key":"","building_source":"mapbox","error":""}))
	check(controller.message == "Finding parcel…" and native.queries.size() == sent + 7, "contract-rejected answer also waits for the one re-query")
	controller._process(controller.retry_delay() + .01)
	check(native.queries.size() == sent + 8, "contract-rejected answer re-queries once")
	controller.tap(Vector2(.4, .4), 18); answer("loading"); controller.camera_changed(); controller._process(5.0)
	check(native.queries.size() == sent + 9 and controller.message.begins_with("Tap a building"), "camera move cancels a waiting re-query")
	controller.tap(Vector2(.4, .4), 18); answer("loading"); controller.pause(); controller._process(5.0)
	check(native.queries.size() == sent + 10, "pause cancels a waiting re-query")
	await controller.activate(); ready_signal()
	controller.config.query_retry_delay_ms = 1500
	check(is_equal_approx(controller.retry_delay(), 1.5), "retry delay is configurable")
	controller.config.query_retry_delay_ms = 999999
	check(is_equal_approx(controller.retry_delay(), 5.0), "configured retry delay is bounded")
	controller.config.erase("query_retry_delay_ms")
	check(is_equal_approx(controller.retry_delay(), Controller.QUERY_RETRY_DELAY_MS / 1000.0), "missing configuration uses the default delay")
## C-124: the last map setup asked native to replace a DataSF building copy that is still loading.
func refetch() -> bool:
	return JSON.parse_string(native.sources.back()[1]).get("refetch_buildings", false) == true
func map_error(code := "parcels_source_load_failed") -> void:
	native.parcel_error.emit(controller.generation, controller.style_generation, code)
func reload() -> void:
	controller._process(controller.retry_delay() + .01)
	for i in 4: await process_frame
func map_error_retry() -> void:
	# Offline/service failures reach Godot as map load errors, not query answers (W-69 P5/P6).
	var sent := native.queries.size(); var boots := native.sources.size(); var old_generation: int = controller.generation
	controller.tap(Vector2(.3, .7), 18); answer("loading"); map_error()
	check(controller.message == "Finding parcel…" and controller.message != Controller.MAP_FAILED, "map load error during a waiting re-query keeps loading feedback")
	await reload()
	check(native.sources.size() == boots + 1 and controller.generation > old_generation, "map load error triggers one automatic map reload")
	ready_signal()
	check(native.queries.size() == sent + 2 and native.queries.back()[2] == Vector2(.3, .7) and native.queries.back()[1] == controller.generation, "reloaded map answers the interrupted tap at the same point")
	answer("", [Fixture.metadata()])
	check(controller.selection.get("block_id") == "p-A", "interrupted tap selects after the automatic reload")
	sent = native.queries.size(); boots = native.sources.size()
	controller.tap(Vector2(.3, .7), 18); map_error("building_load_failed")
	await reload(); ready_signal(); answer("query_failed")
	check(controller.message == Controller.QUERY_FAILED and native.queries.size() == sent + 2, "tap whose one retry was the reload reports after that retry fails")
	controller._process(5.0)
	check(native.queries.size() == sent + 2 and native.sources.size() == boots + 1, "no second automatic retry after the reload")
	controller.tap(Vector2(.3, .7), 18); map_error(); await reload(); map_error()
	check(controller.message == Controller.MAP_FAILED and not controller.busy, "map error after the automatic reload shows the map failure")
	boots = native.sources.size(); controller._process(5.0); for i in 4: await process_frame
	check(native.sources.size() == boots, "map failure is not reloaded again automatically")
	controller.retry(); for i in 4: await process_frame
	check(native.sources.size() == boots + 1, "Retry after a map failure reloads the map")
	ready_signal()
	controller.tap(Vector2(.3, .7), 18); answer("loading"); controller._process(controller.retry_delay() + .01); map_error()
	check(controller.message == Controller.MAP_FAILED, "map error after the tap already used its retry reports at once")
	controller.retry(); for i in 4: await process_frame
	ready_signal(); map_error(); await reload(); ready_signal()
	check(controller.map_ready and controller.message.begins_with("Tap a building"), "idle map error reloads once without a tap")
	sent = native.queries.size()
	for code in ["building_without_parcel", "invalid_point", "too_many_candidates"]:
		controller.tap(Vector2(.3, .7), 18); answer(code); controller._process(5.0)
		check(native.queries.size() == sent + 1 and controller.message == Controller.SETTLED[code], code + " is a definite answer, not retried or reported as a failure")
		sent = native.queries.size()
	controller.tap(Vector2(.3, .7), 18); answer("loading"); controller.tap(Vector2(.6, .2), 18)
	controller._process(controller.retry_delay() + .01)
	check(native.queries.size() == sent + 2 and native.queries.back()[2] == Vector2(.6, .2), "new tap during a waiting re-query replaces it")
	await burst_errors()
	controller.config.query_retry_delay_ms = null
	check(is_equal_approx(controller.retry_delay(), Controller.QUERY_RETRY_DELAY_MS / 1000.0), "non-numeric retry delay falls back to the default")
	controller.config.erase("query_retry_delay_ms")
func buildings_layer_timeout() -> void:
	# C-43 V-167: Mapbox drops a DataSF building GeoJSON it cannot parse without any source error.
	controller.config.building_source = "datasf"; controller.config.buildings_url = "https://demo.invalid/buildings.geojson"
	await controller.activate(); ready_signal()
	check(JSON.parse_string(native.sources.back()[1]).get("building_source") == "datasf", "DataSF building layer is configured")
	check(not refetch(), "a normal map setup reuses the building copy (C-118)")
	var boots := native.sources.size()
	controller._process(controller.buildings_load_timeout() - 1.0)
	check(controller.map_ready and native.sources.size() == boots, "a building layer still within its load time is not a failure")
	var sent := native.queries.size()
	controller.tap(Vector2(.3, .7), 18)
	check(native.queries.size() == sent and controller.message == "Finding parcel…", "a tap before the building layer loads waits for it instead of querying a map without buildings")
	ready_signal()
	check(native.queries.size() == sent and controller.message == "Finding parcel…", "idle readiness without the building layer keeps the tap waiting")
	controller._process(1.1)
	check(controller.message == "Finding parcel…" and controller.busy and not controller.map_ready, "a building layer that never loads counts as a map load error and reloads once, keeping the tap")
	await reload(); ready_signal()
	check(native.sources.size() == boots + 1 and native.queries.size() == sent, "the automatic reload sets the sources again and the tap still waits for buildings")
	check(refetch(), "C-124: the reload after the building timeout fetches a copy still loading again")
	controller._process(controller.buildings_load_timeout() + .1)
	check(controller.message == Controller.MAP_FAILED and not controller.busy, "still missing after the reload: the map failure with Retry, not endless loading")
	controller._process(controller.buildings_load_timeout() + .1); for i in 4: await process_frame
	check(native.sources.size() == boots + 1, "the reported failure is not reloaded again automatically")
	controller.retry(); for i in 4: await process_frame
	check(native.sources.size() == boots + 2, "Retry after the building layer failure reloads the map")
	check(refetch(), "C-124: Retry fetches a building copy still loading again")
	var waits: Array = []
	var on_load := func(row: Dictionary): if row.resource == "buildings": waits.append(row)
	controller.load_diagnostic.connect(on_load)
	native.parcel_ready.emit(controller.generation, 1, '{"source_ready":true,"buildings_source_ready":true,"error":""}')
	native.parcel_ready.emit(controller.generation, 1, '{"source_ready":true,"buildings_source_ready":true,"error":""}')
	controller.load_diagnostic.disconnect(on_load)
	# C-118: the wait for the building layer is logged once per map setup, so a reused one shows as a short wait.
	check(waits.size() == 1 and waits[0].stage == "ready" and waits[0].elapsed_ms >= 0, "the building layer's wait is logged once when it loads")
	controller._process(controller.buildings_load_timeout() + .1)
	check(controller.map_ready and controller.message == Controller.PROMPT and native.sources.size() == boots + 2, "a loaded building layer stops the countdown")
	# C-43 V-199: a tap waiting for the building layer is answered when it loads; the highlight is the chosen parcel's.
	await controller.activate(); ready_signal(); sent = native.queries.size()
	check(not refetch(), "the next pause and resume reuses the building copy again")
	controller.tap(Vector2(.2, .8), 17.5)
	check(native.queries.size() == sent, "a tap at the default zoom waits for the DataSF building layer")
	native.parcel_ready.emit(controller.generation, controller.style_generation, '{"source_ready":true,"buildings_source_ready":true,"error":""}')
	check(native.queries.size() == sent + 1 and native.queries.back()[2] == Vector2(.2, .8), "the waiting tap is sent as soon as the building layer loads")
	native.parcel_query_result.emit(native.queries.back()[0], controller.generation, controller.style_generation,
		JSON.stringify({"kind":"building","parcel_ids":["p-A"],"properties":[Fixture.metadata()],"building_key":"building-1","building_source":"datasf","error":""}))
	check(controller.selection.get("block_id") == "p-A" and native.highlights.back() == [controller.generation, "building-1", "p-A"], "first tap selects; the highlight names the parcel whose buildings form its core")
	ready_signal(controller.style_generation)
	check(controller.message == "Ready to preview this farm.", "idle readiness after the highlight keeps the ready prompt")
	controller.tap(Vector2(.2, .8), 17.5)
	check(native.queries.size() == sent + 2, "once loaded, later taps query at once")
	# Below the selectable zoom the building layer is not drawn, so it cannot load; that is not a failure.
	await controller.activate(); ready_signal(); boots = native.sources.size()
	controller.camera_changed(15.0)
	controller._process(controller.buildings_load_timeout() + 1.0)
	check(controller.map_ready and native.sources.size() == boots, "the building countdown waits while the camera is below the selectable zoom")
	controller.camera_changed(16.0)
	controller._process(controller.buildings_load_timeout() - 1.0)
	check(controller.map_ready, "back at the selectable zoom the countdown starts from where it paused")
	controller._process(1.5)
	check(not controller.map_ready and controller.busy, "a building layer still not loaded at the selectable zoom times out")
	controller.pause(); await controller.activate()
	check(refetch(), "C-124: a building timeout followed by a pause still fetches the stuck copy again on return")
	await controller.activate()
	check(not refetch(), "only the one setup after the timeout asks for a new copy")
	map_error(); await reload()
	check(not refetch(), "other map errors reload without fetching the building copy again")
	controller.config.buildings_load_timeout_ms = 1
	check(is_equal_approx(controller.buildings_load_timeout(), 5.0), "building load time has a lower bound")
	controller.config.buildings_load_timeout_ms = 1e30
	check(is_equal_approx(controller.buildings_load_timeout(), 300.0), "building load time has an upper bound")
	controller.config.buildings_load_timeout_ms = "x"
	check(is_equal_approx(controller.buildings_load_timeout(), Controller.BUILDINGS_LOAD_TIMEOUT_MS / 1000.0), "non-numeric building load time falls back to the default")
	controller.config.building_source = "mapbox"; controller.config.erase("buildings_url"); controller.config.erase("buildings_load_timeout_ms")
	await controller.activate(); ready_signal(); boots = native.sources.size()
	controller._process(Controller.BUILDINGS_LOAD_TIMEOUT_MS / 1000.0 + 1.0)
	check(controller.map_ready and native.sources.size() == boots, "Mapbox buildings have no DataSF load countdown")
func burst_errors() -> void:
	# V-47: one outage reports several map errors, and the failing map can still report ready.
	ready_signal()
	var sent := native.queries.size(); var boots := native.sources.size()
	controller.tap(Vector2(.3, .7), 18); map_error("building_load_failed"); map_error()
	check(controller.message == "Finding parcel…" and controller.busy and controller._reload_left > 0.0, "second error of the same outage does not report before the automatic reload")
	ready_signal(controller.style_generation)
	check(native.queries.size() == sent + 1, "failing map's late ready does not resume the tap on the old map")
	hold_manifest = true; var old_generation: int = controller.generation
	controller._process(controller.retry_delay() + .01); await process_frame
	check(controller.generation == old_generation and controller.busy, "reload is still fetching the manifest")
	map_error(); ready_signal(controller.style_generation)
	check(controller.message == "Finding parcel…" and native.queries.size() == sent + 1, "old map signals during the reload are ignored")
	hold_manifest = false; release.emit()
	for i in 4: await process_frame
	check(native.sources.size() == boots + 1, "burst of errors reloads the map exactly once")
	ready_signal()
	check(native.queries.size() == sent + 2 and native.queries.back()[1] == controller.generation and native.queries.back()[2] == Vector2(.3, .7), "tap resumes only on the reloaded map")
	answer("", [Fixture.metadata()])
	check(controller.selection.get("block_id") == "p-A", "tap interrupted by a burst of errors selects after the reload")
	controller.tap(Vector2(.3, .7), 18); map_error(); await reload(); map_error(); map_error()
	check(controller.message == Controller.MAP_FAILED and controller._reload_left < 0.0, "failure after the reload cancels any pending reload")
	boots = native.sources.size(); controller._process(5.0); for i in 4: await process_frame
	check(native.sources.size() == boots and controller.message == Controller.MAP_FAILED, "reported map failure stays until the player retries")
	controller.retry(); for i in 4: await process_frame
	ready_signal()
## C-113 Q-172: a home claimed on an earlier release keeps opening that release's farm (its save's cells belong to that
## grid), read from the release's own directory; everything else uses the map's release.
func earlier_release() -> void:
	hold = false
	controller.config.releases = {R6: "https://old.invalid/r6/", "sf-dynamic-farm-20261118-r9": "http://plain.invalid/r9/"}
	await controller.activate(); ready_signal()
	var current := str(controller.manifest.dataset_version)
	check(controller.home_release(R6) == R6 and controller.home_release(current) == current, "a home claimed on r6 opens in r6; one on the map's release opens in it")
	check(controller.home_release("sf-dynamic-farm-20261118-r9") == current and controller.home_release("sf-dynamic-farm-20261020-r3") == current and controller.home_release("") == current,
		"a release without an https directory, or not listed, opens in the map's release")
	reply("building", [Fixture.metadata()], "opaque")
	var opened := farms.size(); paths.clear()
	await controller.open_farm(R6)
	check(paths == ["https://old.invalid/r6/farms/p-A.json"] and farms.size() == opened + 1 and farms.back().dataset_version == R6, "the own farm of an r6 home is read from r6's directory and stays an r6 farm")
	await controller.open_farm(current)
	check(paths.back() == "/farms/p-A.json" and farms.size() == opened + 2 and farms.back().dataset_version == current, "a home claimed on the map's release opens the map's farm")
	await controller.open_farm("sf-dynamic-farm-20261020-r3")
	check(paths.back() == "/farms/p-A.json" and farms.back().dataset_version == current, "a home on an unlisted release opens the map's farm")
	stale_release = true; await controller.open_farm(R6); stale_release = false
	check(farms.size() == opened + 3 and controller.message == "This farm could not load. Please try again.", "a farm of another release cannot open as the r6 farm")
	# "My home" where the map's release has no farm for the parcel (r8 dropped a few r6 farms).
	controller.camera_changed(); paths.clear()
	await controller.select_home("p-Z", R6)
	check(paths == ["https://old.invalid/r6/farms/p-Z.json"] and controller.selection.block_id == "p-Z" and controller.selection.release == R6, "'My home' selects an r6 home from r6's farm")
	check(controller.selection.name == "424 TEST AVE" and controller.selection.core_cell_count == 800 and controller.selection.extension_cell_count == 544, "the selected home shows its r6 name and cells")
	check(native.highlights.back()[1] == "", "no building of the map's release is highlighted for it")
	await controller.open_farm(R6)
	check(farms.back().block_id == "p-Z" and farms.back().dataset_version == R6, "the selected r6 home opens its r6 farm")
	var asked := paths.size()
	await controller.select_home("p-Z", current); await controller.select_home("p-Z", "sf-dynamic-farm-20261020-r3")
	check(paths.size() == asked and controller.selection.block_id == "p-Z", "'My home' on the map's release or an unlisted one fetches nothing")
	stale_release = true; await controller.select_home("p-Z", R6); stale_release = false
	check(controller.selection.is_empty() and controller.message == "Your home could not load. Tap My home again.", "a farm of another release is not taken as the r6 home")
	hold = true; controller.select_home("p-Z", R6); await process_frame
	reply("building", [Fixture.metadata()], "opaque")
	hold = false; release.emit(); await process_frame
	check(controller.selection.block_id == "p-A" and not controller.selection.has("release"), "a tap while the home loads wins over it")

func _run() -> void:
	api = Api.new(); api.transport = transport; root.add_child(api)
	native = Native.new(); controller = Controller.new(); controller.api = api; controller.bridge = native
	controller.config = {"base_url":"https://demo.invalid", "dataset_version":Fixture.C.DATASET,"manifest_sha256":"a".repeat(64),"building_source":"mapbox"}
	controller.farm_ready.connect(func(farm: Dictionary): farms.append(farm))
	controller.candidates_found.connect(func(rows: Array): options = rows)
	root.add_child(controller)
	await controller.activate()
	check(paths == ["/client-manifest.json"] and native.sources.size() == 1, "only compact pinned manifest is requested for bootstrap")
	check(not controller.map_ready and not controller.busy, "selection waits for native source readiness")
	ready_signal()
	controller.tap(Vector2(.25, .6), 15)
	check(native.queries.is_empty(), "below display zoom does not issue a query")
	controller.tap(Vector2(.25, .6), 18)
	var old: Array = native.queries.back()
	check(old[2] == Vector2(.25, .6), "normalized viewport point passes to shared bridge unchanged")
	controller.camera_changed()
	native.parcel_query_result.emit(old[0], old[1], 1, JSON.stringify({"kind":"parcel","parcel_ids":["p-A"],"properties":[Fixture.metadata()],"building_key":""}))
	check(controller.selection.is_empty(), "camera change invalidates old hit")
	reply("building", [Fixture.metadata()], "opaque")
	check(controller.selection.block_id == "p-A" and native.highlights.back()[1] == "opaque" and native.highlights.back()[2] == "p-A", "building highlights opaque key and selects its same-point parcel")
	check(native.states.is_empty(), "building selection does not enable a parcel frame")
	check(not controller.selection.has("building_key") and not controller.selection.has("geometry"), "selection metadata stores no native building key or geometry")
	check(controller.message != "Finding parcel…", "successful hit clears pending hint")
	await controller.open_farm()
	check(farms.size() == 1 and farms[0].counts.total_cell_count == 1344, "read-only fetch emits validated complete schema4 farm")
	wrong_farm = true; await controller.open_farm()
	check(farms.size() == 1, "mismatched server parcel cannot open a preview")
	wrong_farm = false
	var fetched := paths.size()
	reply("parcel", [Fixture.metadata()])
	check(controller.selection.is_empty() and native.highlights.back()[1] == "", "q(336) open ground clears the previous building selection and selects nothing")
	check(native.states.is_empty(), "q(336) open ground never enables a rectangular parcel frame")
	check(controller.message == controller.PROMPT and not controller.busy, "open ground keeps the choose-a-building prompt")
	await controller.open_farm(); check(paths.size() == fetched and farms.size() == 1, "nothing to preview after an open-ground tap")
	options = []
	reply("parcel", [Fixture.metadata(), Fixture.metadata("p-B")])
	check(controller.selection.is_empty() and options.is_empty(), "open ground with several parcels offers no candidates")
	controller.choose("p-A"); check(controller.selection.is_empty() and native.states.is_empty(), "open-ground parcel IDs cannot be chosen afterwards")
	reply("building", [Fixture.metadata()], "foreign", "datasf")
	check(controller.selection.is_empty(), "unexpected building provider cannot select")
	reply("building", [Fixture.metadata(), Fixture.metadata("p-B")], "shared")
	check(controller.selection.is_empty() and options.size() == 2, "multiple candidates await explicit user choice")
	controller.choose("p-B"); check(controller.selection.block_id == "p-B", "explicit choice picks one canonical parcel")
	check(native.highlights.back() == [controller.generation, "shared", "p-B"] and native.states.is_empty(), "explicit candidate keeps the filled building highlight only, for the chosen parcel")
	controller.choose("p-forged"); check(controller.selection.block_id == "p-B", "choice outside current result cannot replace selection")
	ready_signal(2); check(controller.selection.is_empty(), "style reload invalidates selection and opaque keys")
	reply("building", [Fixture.metadata()], "opaque")
	hold = true; controller.open_farm(); await process_frame
	var generation: int = controller.generation
	controller.pause(); release.emit(); await process_frame
	check(farms.size() == 1 and not native.visible and native.cleared.has(generation), "suspend retires HTTP result and releases native layers")
	await controller.activate(); ready_signal()
	check(controller.generation > generation, "resume uses a new shared global generation")
	native.parcel_ready.emit(generation, 100, '{"source_ready":false}')
	check(controller.map_ready, "late readiness from old visit cannot replace current state")
	controller.tap(Vector2(.5, .5), 18); controller._process(9.0)
	check(controller._pending == -1 and controller.message.contains("did not respond"), "missing query callback expires with retry feedback")
	await first_tap_retry()
	await map_error_retry()
	await buildings_layer_timeout()
	check(paths.all(func(path: String): return path == "/client-manifest.json" or path.begins_with("/farms/")), "preview never requests claims or account/gameplay endpoints")
	await earlier_release()
	controller.queue_free(); await process_frame
	api.queue_free(); await process_frame
	print("DYNAMIC SELECTION ", checks - failures, "/", checks)
	quit(1 if failures else 0)
