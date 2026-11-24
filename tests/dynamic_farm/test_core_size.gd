extends SceneTree
## C-43: core size and shape follow the dataset; the client only keeps its 8192-cell budget
## and a configurable too-small threshold. Local fixtures; config.json points at the hosted r5 (C-48#42).
const Controller := preload("res://modules/dynamic_farm/map/selection_controller.gd")
const Api := preload("res://modules/dynamic_farm/map/geo_api.gd")
const FarmData := preload("res://modules/dynamic_farm/farm_data.gd")
const Metadata := preload("res://modules/dynamic_farm/map/parcel_metadata.gd")
const Contract := preload("res://modules/dynamic_farm/map/geo_contract.gd")
const Fixture := preload("res://tests/dynamic_farm/selection_fixtures.gd")
const R5 := "sf-dynamic-farm-20261124-r5"
class Native extends MapBridge:
	var queries: Array = []
	var highlights: Array = []
	func supports_parcels() -> bool: return true
	func set_parcel_sources(_gen: int, _config: String) -> void: pass
	func query_parcel_at(id: int, gen: int, point: Vector2) -> void: queries.append([id, gen, point])
	func set_parcel_building_highlight(gen: int, key: String) -> void: highlights.append([gen, key])
	func clear_parcel_layers(_gen: int) -> void: pass
	func set_map_visible(_value: bool) -> void: pass
var checks := 0
var failures := 0
var controller: Node
var native: Native
var farms_by_id := {}
var opened: Array = []
func _initialize() -> void: _run.call_deferred()
func check(value: bool, text: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", text)
## Shapes in game cells (0.8 m): L-shaped small, L-shaped mid, courtyard (core with a hole), exact threshold.
func shapes() -> Dictionary:
	return {
		"p-L300": [Fixture.cells([[2,1,10,20],[12,11,10,10]]), 24, 22],
		"p-L1200": [Fixture.cells([[2,1,30,30],[32,16,20,15]]), 54, 32],
		"p-YARD3200": [Fixture.cells([[2,1,60,60]], [[22,21,20,20]]), 64, 62],
		"p-SQ400": [Fixture.cells([[2,1,20,20]]), 24, 22],
		"p-SQ399": [Fixture.cells([[2,1,20,20]], [[2,1,1,1]]), 24, 22],
	}
func meta(id: String, core: int, extension: int) -> Dictionary:
	var row := Fixture.metadata(id)
	row.cell_count = core; row.core_cell_count = core; row.extension_cell_count = extension; row.total_cell_count = core + extension
	return row
func transport(path: String) -> Dictionary:
	if path == "/client-manifest.json":
		var manifest := Fixture.manifest(); manifest.dataset_version = R5; return manifest
	return farms_by_id.get(path.get_file().get_basename(), {})
func pick(row: Dictionary) -> void:
	controller.tap(Vector2(.5, .5), 18)
	var request: Array = native.queries.back()
	native.parcel_query_result.emit(request[0], request[1], controller.style_generation, JSON.stringify({"kind":"building",
		"parcel_ids":[row.block_id], "properties":[row], "building_key":"b-" + row.block_id, "building_source":"mapbox", "error":""}))
func _run() -> void:
	# Farm decode: any shape and size within the budget, counts preserved.
	var counts := {}
	for id in shapes():
		var shape: Array = shapes()[id]
		var farm := Fixture.shaped_farm(id, shape[0], shape[1], shape[2], R5)
		farms_by_id[id] = farm
		var decoded := FarmData.decode(farm)
		check(decoded.get("ok") == true, "%s decodes (%s)" % [id, decoded.get("error", "ok")])
		if decoded.get("ok") != true: continue
		counts[id] = decoded.counts.core
		check(decoded.counts.core == shape[0].size(), "%s keeps its dataset core count %d" % [id, shape[0].size()])
		var outside := 0
		for at: Vector2i in decoded.by_cell:
			if decoded.by_cell[at].zone == "core" and not shape[0].has(at): outside += 1
		check(outside == 0 and decoded.by_cell.keys().filter(func(at): return decoded.by_cell[at].zone == "core").size() == shape[0].size(), "%s core cells are exactly the shape" % id)
	check(counts.get("p-L300", 0) < counts.get("p-L1200", 0) and counts.get("p-L1200", 0) < counts.get("p-YARD3200", 0), "core count grows with shape area (300 < 1200 < 3200)")
	var yard: Dictionary = FarmData.decode(farms_by_id["p-YARD3200"])
	check(yard.get("ok") == true and yard.by_cell[Vector2i(30, 30)].zone == "extension", "courtyard hole stays walk-only, not core")
	check(FarmData.permits(yard, Vector2i(2, 1), "till") and not FarmData.permits(yard, Vector2i(30, 30), "till"), "only shaped core cells can be tilled")
	var big := Fixture.shaped_farm("p-BIG", Fixture.cells([[2,1,88,88]]), 92, 90, R5)
	check(FarmData.decode(big).get("error") == "Dynamic farm cell budget exceeded.", "farm above the 8192-cell client budget is rejected")
	var under := Fixture.shaped_farm("p-UNDER", Fixture.cells([[2,1,86,86]]), 90, 91, R5)
	check(FarmData.decode(under).get("ok") == true and FarmData.decode(under).counts.core == 7396, "large core within the budget is accepted (7396 core)")
	# Parcel metadata: core counts outside the old 760–840 band are accepted.
	for core in [1, 300, 1200, 3200, 7000]:
		check(not Metadata.decode(meta("p-A", core, 100)).is_empty(), "metadata accepts %d core cells" % core)
	check(Metadata.decode(meta("p-A", 0, 100)).is_empty(), "metadata rejects an empty core")
	check(Metadata.decode(meta("p-A", 8100, 100)).is_empty(), "metadata rejects totals above the client budget")
	# Dataset pointer is configuration, not a pinned constant.
	check(Contract.valid_dataset(Contract.DATASET) and Contract.valid_dataset(R5), "r4 and an r5 release name are valid dataset versions")
	for bad in ["sf-dynamic-farm-r5", "sf-dynamic-farm-20261124-r5/../x", "other-20261124-r5", 5, null]:
		check(not Contract.valid_dataset(bad), "rejects dataset version %s" % str(bad))
	check(Contract.farm_matches(farms_by_id["p-L300"], "p-L300", R5) and not Contract.farm_matches(farms_by_id["p-L300"], "p-L300", Contract.DATASET), "farm must match the configured dataset version")
	# Shipped config: hosted r5 (C-48#42), client-manifest pin, DataSF buildings, and the server knows the release.
	var shipped: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://modules/dynamic_farm/map/config.json"))
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/farm/data/dynamic_farm.json"))
	check(shipped.dataset_version == R5 and shipped.manifest_sha256 == "1069a55876f36db56d28e0e60e24993153f583587d11168f2c96a919867bb295", "config.json pins the hosted r5 client-manifest")
	check(Api.valid_base(str(shipped.base_url).trim_suffix("/")) and shipped.building_source == "datasf", "config.json reads r5 over https with the DataSF buildings it was rasterized from")
	check(rules.communities.any(func(c): return shipped.dataset_version in c.datasets), "server rules register the configured dataset release")
	# Selection: threshold prompt, configurable threshold.
	var api := Api.new(); api.transport = transport; root.add_child(api)
	native = Native.new(); controller = Controller.new(); controller.api = api; controller.bridge = native
	controller.config = {"base_url":"https://demo.invalid", "dataset_version":R5, "manifest_sha256":"a".repeat(64), "building_source":"mapbox"}
	controller.farm_ready.connect(func(farm: Dictionary): opened.append(farm))
	root.add_child(controller)
	await controller.activate()
	native.parcel_ready.emit(controller.generation, 1, '{"source_ready":true,"error":""}')
	check(controller.map_ready and controller.manifest.dataset_version == R5, "configured r5 dataset bootstraps the map")
	check(controller.min_core_cells() == 400, "default minimum is 400 core cells")
	pick(meta("p-L300", 300, 228))
	check(controller.selection.is_empty() and controller.message == Controller.TOO_SMALL, "300-cell parcel shows the too-small prompt on selection")
	check(controller.message == "This parcel is too small to be your main farm. Please choose a larger one.", "too-small prompt uses the Q-56 copy")
	check(native.highlights.back()[1] == "b-p-L300", "too-small building stays highlighted so the player sees which one")
	await controller.open_farm()
	check(opened.is_empty(), "too-small parcel cannot be previewed")
	pick(meta("p-SQ399", 399, 129))
	check(controller.message == Controller.TOO_SMALL, "399 cells is below the threshold")
	pick(meta("p-SQ400", 400, 128))
	check(controller.selection.get("block_id") == "p-SQ400" and controller.message == "Ready to preview this farm.", "exactly 400 cells can be selected")
	pick(meta("p-L1200", 1200, 528))
	check(controller.selection.get("block_id") == "p-L1200", "1200-cell L-shaped parcel is selected")
	await controller.open_farm()
	check(opened.size() == 1 and opened[0].counts.core_cell_count == 1200, "L-shaped r5 farm opens with its own core count")
	pick(meta("p-L300", 500, 28))
	await controller.open_farm()
	check(opened.size() == 1 and controller.message == Controller.TOO_SMALL and controller.selection.is_empty(), "farm smaller than its metadata claimed is still stopped by the threshold")
	controller.config.min_core_cells = 250
	pick(meta("p-L300", 300, 228))
	check(controller.selection.get("block_id") == "p-L300", "configured lower threshold admits a 300-cell parcel")
	controller.config.min_core_cells = 2000
	pick(meta("p-L1200", 1200, 528))
	check(controller.selection.is_empty() and controller.message == Controller.TOO_SMALL, "configured higher threshold rejects a 1200-cell parcel")
	controller.config.min_core_cells = 999999
	check(controller.min_core_cells() == FarmData.MAX_CELLS, "configured threshold is clamped to the cell budget")
	controller.config.min_core_cells = -5
	check(controller.min_core_cells() == 1, "configured threshold is at least one cell")
	controller.config.min_core_cells = 1e30
	check(controller.min_core_cells() == FarmData.MAX_CELLS, "huge threshold is clamped before int conversion, not wrapped")
	controller.config.min_core_cells = -1e30
	check(controller.min_core_cells() == 1, "huge negative threshold clamps to one cell")
	controller.config.min_core_cells = 399.999
	check(controller.min_core_cells() == 399, "fractional threshold rounds down")
	controller.config.min_core_cells = "big"
	check(controller.min_core_cells() == Controller.MIN_CORE_CELLS, "non-numeric threshold falls back to the default")
	controller.config.erase("min_core_cells")
	controller.config.dataset_version = "sf-dynamic-farm-latest"
	await controller.activate()
	check(controller.message == "This preview service is not configured.", "malformed configured dataset version is rejected")
	controller.queue_free(); api.queue_free(); await process_frame
	print("DYNAMIC CORE SIZE ", checks - failures, "/", checks)
	quit(1 if failures else 0)
