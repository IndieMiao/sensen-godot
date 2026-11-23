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
	func set_parcel_building_highlight(gen: int, key: String) -> void: highlights.append([gen, key])
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
var wrong_farm := false
signal release
func _initialize() -> void: _run.call_deferred()
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", text)
func transport(path: String) -> Dictionary:
	paths.append(path)
	if path == "/client-manifest.json": return Fixture.manifest()
	var data: Dictionary = Fixture.farm("p-B" if wrong_farm else path.get_file().get_basename())
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
	check(controller.selection.block_id == "p-A" and native.highlights.back()[1] == "opaque", "building highlights opaque key and selects its same-point parcel")
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
	check(native.highlights.back()[1] == "shared" and native.states.is_empty(), "explicit candidate keeps the filled building highlight only")
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
	check(paths.all(func(path: String): return path == "/client-manifest.json" or path.begins_with("/farms/")), "preview never requests claims or account/gameplay endpoints")
	controller.queue_free(); await process_frame
	api.queue_free(); await process_frame
	print("DYNAMIC SELECTION ", checks - failures, "/", checks)
	quit(1 if failures else 0)
