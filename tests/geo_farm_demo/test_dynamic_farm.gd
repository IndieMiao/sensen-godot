extends SceneTree
const Model = preload("res://modules/dynamic_farm/farm_data.gd")
const Farm = preload("res://scenes/geo_farm_demo/farm_view.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + title)

func fixture() -> Dictionary:
	var core: Array = []
	var extension: Array = []
	var reserve: Array = []
	for y in 48:
		reserve.append([y, 0, 28])
		if y >= 4 and y < 44:
			core.append([y, 4, 20, 0])
			extension.append([y, 0, 4, 1])
			extension.append([y, 24, 4, 1])
		else:
			extension.append([y, 0, 28, 1])
	return {"schema": 4, "dataset_version": "test-dynamic-r4", "selection_unit": "parcel",
		"block_id": "p-TEST*", "parcel_id": "TEST*", "name": "Test parcel", "address": null,
		"generator_version": "fixture", "seed_hex": "a".repeat(64), "game_cell_m": 0.8,
		"source_area_m2": 232.0, "source_cell_m": 0.53,
		"source_transform": {"crs": "EPSG:32610", "rotation_deg": 25.0},
		"grid": {"width": 28, "height": 48, "origin_cell": [-4, -4]},
		"zones": {"core": {"runs": core}, "extension": {"runs": extension}},
		"capabilities": {"core": {"walk": true, "till": true, "plant": true, "arrange": true, "place": true},
			"extension": {"walk": true, "till": false, "plant": false, "arrange": false, "place": false}},
		"counts": {"core_cell_count": 800, "extension_cell_count": 544, "total_cell_count": 1344},
		"surface_palette": [{"id": 0, "color": "#D8BF8D"}, {"id": 1, "color": "#8FAD69"}, {"id": 2, "color": "#BBA882"}],
		"boundaries": {"core": [{"outer": [[4,4],[24,4],[24,44],[4,44],[4,4]], "holes": []}],
			"outer": [{"outer": [[0,0],[28,0],[28,48],[0,48],[0,0]], "holes": []}]},
		"walk_reserve": {"no_solid_decor_runs": reserve, "spawn_cell": [4,4], "entry_cell": [0,4]}}

func _run() -> void:
	var data := fixture()
	var d := Model.decode(data)
	_check(d.ok and d.cells.size() == 1344, "both RLE zones decoded")
	_check(d.counts.core == 800 and d.counts.extension == 544, "800 counts core only")
	_check(d.by_cell[Vector2i(4, 4)].zone == "core", "zone identity retained independently of surface")
	_check(d.origin == Vector2i(-4, -4), "negative origin accepted without negative run coordinates")
	_check(Model.world_position(d, Vector2i(4, 4)).is_equal_approx(Vector3(0.4, 0, -0.4)), "one origin and north-minus-Z transform")
	_check(d.block_id == "p-TEST*", "literal star ID not treated as glob")
	for action in Model.ACTIONS:
		_check(Model.permits(d, Vector2i(4,4), action), "core eligibility " + action)
		_check(Model.permits(d, Vector2i(0,0), action) == (action == "walk"), "extension eligibility " + action)
	_check(not Model.permits(d, Vector2i(-1,0), "walk"), "outside not walkable")
	_check(not Model.permits(d, Vector2i(4,4), "harvest"), "unknown command not enabled")
	var same_surface := data.duplicate(true)
	for run in same_surface.zones.extension.runs:
		run[3] = 0
	var same := Model.decode(same_surface)
	_check(same.ok and not Model.permits(same, Vector2i(0,0), "place"), "same soil color does not grant extension editing")
	var bad := data.duplicate(true)
	bad.capabilities.extension.place = true
	_check(not Model.decode(bad).ok, "extension edit permission rejected")
	bad = data.duplicate(true)
	bad.capabilities.extension.walk = "true"
	_check(not Model.decode(bad).ok, "string boolean rejected")
	bad = data.duplicate(true)
	bad.capabilities.core.erase("plant")
	_check(not Model.decode(bad).ok, "missing core permission rejected")
	bad = data.duplicate(true)
	bad.zones.core.runs[0][2] = 1000000000
	_check(not Model.decode(bad).ok, "huge run rejected before allocation")
	bad = data.duplicate(true)
	bad.zones.extension.runs[4] = [4,0,5,1]
	_check(not Model.decode(bad).ok, "cross-zone overlap rejected")
	bad = data.duplicate(true)
	bad.zones.core.runs.insert(0, bad.zones.core.runs[0].duplicate())
	_check(not Model.decode(bad).ok, "same-zone overlap rejected")
	bad = data.duplicate(true)
	bad.zones.core.runs.reverse()
	_check(not Model.decode(bad).ok, "unsorted rows rejected")
	bad = data.duplicate(true)
	bad.zones.core.runs[0][1] = 4.5
	_check(not Model.decode(bad).ok, "fractional coordinates rejected")
	bad = data.duplicate(true)
	bad.zones.extension.runs[0][3] = 8
	_check(not Model.decode(bad).ok, "legacy building surface not reinterpreted")
	bad = data.duplicate(true)
	bad.counts.total_cell_count = 800
	_check(not Model.decode(bad).ok, "wrong total rejected")
	bad = data.duplicate(true)
	bad.grid.width = 545
	_check(not Model.decode(bad).ok, "axis budget enforced")
	bad = data.duplicate(true)
	bad.walk_reserve.spawn_cell = [99,99]
	_check(not Model.decode(bad).ok, "spawn outside ground rejected")
	bad = data.duplicate(true)
	bad.walk_reserve.no_solid_decor_runs = []
	_check(not Model.decode(bad).ok, "unprotected spawn rejected")
	bad = data.duplicate(true)
	bad.boundaries.outer[0].outer[0] = [-1,0]
	_check(not Model.decode(bad).ok, "out-of-range/open contour rejected")
	bad = data.duplicate(true)
	bad.seed_hex = "G".repeat(64)
	_check(not Model.decode(bad).ok, "seed format enforced")
	bad = data.duplicate(true)
	bad.source_transform.rotation_deg = NAN
	_check(not Model.decode(bad).ok, "non-finite orientation rejected")
	bad = data.duplicate(true)
	bad.game_cell_m = 0.65
	_check(not Model.decode(bad).ok, "old gensen grid scale not silently used")
	bad = data.duplicate(true)
	bad.grid.width = 30
	bad.zones.extension.runs.append([47,29,1,1])
	bad.counts.extension_cell_count += 1
	bad.counts.total_cell_count += 1
	_check(not Model.decode(bad).ok, "isolated walk island rejected")
	bad = data.duplicate(true)
	bad.grid.width = 544
	bad.grid.height = 70
	for y in range(48, 64):
		bad.zones.extension.runs.append([y,0,544,1])
	bad.counts.extension_cell_count += 16 * 544
	bad.counts.total_cell_count += 16 * 544
	_check(not Model.decode(bad).ok, "8192 total cell budget enforced")
	var hole := data.duplicate(true)
	# Remove a full outside corner cell, retaining the occupied shape and declared counts.
	hole.zones.extension.runs[0] = [0,1,27,1]
	hole.boundaries.outer[0].outer = [[1,0],[28,0],[28,48],[0,48],[0,1],[1,1],[1,0]]
	hole.walk_reserve.no_solid_decor_runs[0] = [0,1,27]
	hole.counts.extension_cell_count -= 1
	hole.counts.total_cell_count -= 1
	var h := Model.decode(hole)
	_check(h.ok and not h.by_cell.has(Vector2i.ZERO) and not Model.permits(h, Vector2i.ZERO, "walk"), "missing cell never filled from bbox")
	var view = Farm.instantiate()
	root.add_child(view)
	_check(view.show_block(data), "r4 view accepts schema4")
	_check("Core 800" in view._stats.text and "Extension 544" in view._stats.text, "r4 separate counts shown")
	_check(view._legend.get_child_count() == 2 and view._grid._zones.size() == 1344, "two-zone legend and coverage")
	_check(not "North" in view._status.text, "rotated source not falsely labelled north-up")
	view._on_cell_selected("zone:extension")
	_check("Walk only" in view._status.text, "extension tap explains only walking")
	for size_value in [Vector2i(320,568), Vector2i(360,640), Vector2i(412,915)]:
		root.content_scale_size = size_value
		root.size = size_value
		await process_frame
		await process_frame
		_check(view._back.get_global_rect().end.y <= size_value.y, "r4 return fits " + str(size_value))
		_check(view._source.get_global_rect().end.y <= size_value.y, "r4 explanation fits " + str(size_value))
		_check(Rect2(Vector2.ZERO,view._grid.size).grow(0.01).encloses(view._grid.cell_rect(0)), "r4 core fits")
		_check(Rect2(Vector2.ZERO,view._grid.size).grow(0.01).encloses(view._grid.cell_rect(1343)), "r4 extension fits")
	view.show_error()
	_check(view._grid._zones.is_empty(), "error clears previous zone state")
	for path in OS.get_cmdline_user_args():
		if path.ends_with(".json"):
			_check(view.load_block_file(path), "real r4 sample " + path.get_file())
	print("DYNAMIC_FARM_TESTS checks=%d failures=%d" % [checks, failures])
	view.queue_free()
	await process_frame
	quit(1 if failures else 0)
