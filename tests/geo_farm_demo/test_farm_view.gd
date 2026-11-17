extends SceneTree
## Run in an isolated project containing scenes/geo_farm_demo and this script.
const Block = preload("res://scenes/geo_farm_demo/farm_block.gd")
const Farm = preload("res://scenes/geo_farm_demo/farm_view.tscn")
var failures := 0
var checks := 0
var back_count := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + label)

func _fixture() -> Dictionary:
	var colors := ["#aab2ae", "#b9c87d", "#d5aa76", "#b7accd", "#6c9c72", "#509ac4", "#d9cdb5"]
	var materials: Array = []
	for i in 7:
		materials.append({"id": i, "name": "surface", "color": colors[i]})
	return {"schema": 1, "dataset_version": "test-only", "block_id": "0001", "name": "SF Block 0001",
		"source_area_m2": 9000.0, "inset_area_m2": 8000.0,
		"grid": {"width": 3, "height": 3, "cells": [[0, 0, 0], [1, 0, 1], [2, 0, 2],
			[0, 1, 3], [2, 1, 4], [0, 2, 5], [1, 2, 6]]}, "materials": materials}

func _run() -> void:
	var data := _fixture()
	var decoded := Block.decode(data)
	_check(decoded.ok, "schema v1 fixture accepted")
	_check(decoded.cells.size() == 7, "sparse hole stays absent; seven occupied cells")
	_check(decoded.cells[0].kind == "unknown" and decoded.cells[5].kind == "water", "unknown and water preserved")
	_check(decoded.block_id == "0001", "string block ID keeps leading zeroes")
	_check(decoded.area_m2 == 8000.0, "display inset area, not source area")
	_check(decoded.palette.water == Color("509ac4"), "server material palette used")
	_check(Block.decode(JSON.parse_string(JSON.stringify(data))).ok, "JSON floating-point integer values accepted")
	var bad := data.duplicate(true)
	bad.grid.cells.append([0, 0, 1])
	_check(not Block.decode(bad).ok, "duplicate cells rejected")
	bad = data.duplicate(true)
	bad.grid.cells[0][0] = 0.5
	_check(not Block.decode(bad).ok, "fractional coordinates rejected")
	bad = data.duplicate(true)
	bad.grid.cells[0][0] = -1
	_check(not Block.decode(bad).ok, "negative coordinates rejected")
	bad = data.duplicate(true)
	bad.grid.cells[0][1] = 3
	_check(not Block.decode(bad).ok, "outside dimensions rejected")
	bad = data.duplicate(true)
	bad.grid.cells[0][2] = 8
	_check(not Block.decode(bad).ok, "unknown material ID rejected, not relabeled")
	bad = data.duplicate(true)
	bad.materials.pop_back()
	_check(not Block.decode(bad).ok, "missing referenced palette entry rejected")
	bad = data.duplicate(true)
	bad.materials[0].color = "not-a-color"
	_check(not Block.decode(bad).ok, "malformed palette rejected")
	bad = data.duplicate(true)
	bad.inset_area_m2 = NAN
	_check(not Block.decode(bad).ok, "non-finite area rejected")
	bad = data.duplicate(true)
	bad.grid.width = 257
	_check(not Block.decode(bad).ok, "oversized grid rejected")
	bad = data.duplicate(true)
	bad.grid.cells = []
	_check(not Block.decode(bad).ok, "empty grid rejected")
	_check(not Block.decode({"schema": 2}).ok, "unsupported schema rejected")
	var view = Farm.instantiate()
	root.add_child(view)
	view.back_requested.connect(func(): back_count += 1)
	_check(view.show_block(data), "view accepts block")
	await process_frame
	await process_frame
	var grid = view._grid
	_check(grid.cell_rect(5).position.y < grid.cell_rect(0).position.y, "larger server y draws north/up")
	var tapped := InputEventMouseButton.new()
	tapped.button_index = MOUSE_BUTTON_LEFT
	tapped.pressed = true
	tapped.position = grid.cell_rect(5).get_center()
	grid._gui_input(tapped)
	_check("Water" in view._status.text, "tap reports actual water surface")
	_check(view._legend.get_child_count() == 7, "all seven present surfaces in legend")
	view._back.pressed.emit()
	_check(back_count == 1, "back emitted exactly once")
	view.show_loading("Next farm")
	_check(grid._cells.is_empty() and view._legend.get_child_count() == 0, "loading clears previous farm")
	_check(not view.show_block({}), "bad block produces error")
	_check(grid._cells.is_empty() and not view._back.disabled, "error keeps return available without stale grid")
	_check(not view.load_block_file("res://missing.json"), "missing file returns error")
	for viewport_size in [Vector2i(360, 640), Vector2i(320, 568), Vector2i(412, 915)]:
		root.content_scale_size = viewport_size
		root.size = viewport_size
		data.name = "SF Block 012345"
		view.show_block(data)
		await process_frame
		await process_frame
		_check(view._back.get_global_rect().end.y <= viewport_size.y, "back fits " + str(viewport_size))
		_check(view._grid.size.x > 0 and view._grid.size.y >= 120, "grid visible " + str(viewport_size))
		for i in grid._cells.size():
			_check(Rect2(Vector2.ZERO, grid.size).encloses(grid.cell_rect(i)), "cell fits " + str(viewport_size))
	# Generated ~800-cell fixture tests scale only, never shipped as a real block.
	var many: Array = []
	for y in 40:
		for x in 20:
			many.append([x, y, (x + y) % 7])
	data.grid = {"width": 20, "height": 40, "cells": many}
	_check(view.show_block(data) and view._grid._cells.size() == 800, "800-cell grid renders without resampling")
	for path in OS.get_cmdline_user_args():
		if path.ends_with(".json"):
			_check(view.load_block_file(path), "real generated file " + path.get_file())
	print("GEOFARM_VIEW_TESTS checks=%d failures=%d" % [checks, failures])
	view.queue_free()
	await process_frame
	quit(1 if failures else 0)
