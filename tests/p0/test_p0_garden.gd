extends GdUnitTestSuite
## P0 garden: the earlier fixed-plot spec on the grid of content.garden.plots (63 beds, SGODOT-355 b1); P0 view → CropField cells.

func test_plot_ids_and_cells_are_a_bijection_on_spaced_beds() -> void:
	var seen := {}
	for id in P0Garden.plot_count():
		var c := P0Garden.cell_of(id)
		assert_int(P0Garden.id_of(c)).is_equal(id)
		seen[c] = true
		# beds stand two cells apart, so every bed has a walkway beside it
		assert_int(P0Garden.id_of(c + Vector2i(1, 0))).is_equal(-1)
		assert_int(P0Garden.id_of(c + Vector2i(0, 1))).is_equal(-1)
	assert_int(seen.size()).is_equal(63)   # the whole 9 × 7 grid laid out; the view's garden.plots shows the open ones

## The client grid is the server's (content.garden.plots: sprinkler coverage and greenhouses are judged there). SGODOT-355
## b1 (不知火舞 on 哪吒's grid, 11-02): 9 × 7 beds on the yard's x 2–18 × y −1–11; the starting 2 × 4 at x 8–14 × y 9–11
## in front of the farmhouse door, then row by row out from the farmhouse, each row's middle first.
func test_the_garden_grid_matches_the_content_table() -> void:
	var table: Array = P0Logic.content().garden.plots   # content/farm_garden.json, merged in (SGODOT-275)
	assert_array(P0Logic.content_errors).is_empty()
	assert_int(table.size()).is_equal(P0Garden.max_plots())
	for id in table.size():
		assert_vector(P0Garden.grid_of(id)).override_failure_message("plot %d" % id).is_equal(Vector2i(int(table[id][0]), int(table[id][1])))
		var c := P0Garden.cell_of(id)
		assert_bool(c.x >= 2 and c.x <= 18 and c.y >= -1 and c.y <= 11).override_failure_message("plot %d at %s" % [id, c]).is_true()
	var start := range(8).map(func(i): return P0Garden.cell_of(i))
	for c in [Vector2i(8, 9), Vector2i(10, 9), Vector2i(12, 9), Vector2i(14, 9), Vector2i(8, 11), Vector2i(10, 11), Vector2i(12, 11), Vector2i(14, 11)]:
		assert_bool(start.has(c)).override_failure_message("start bed %s" % c).is_true()
	# then the rest of those two rows, and row by row out from the farmhouse: never nearer the house than the bed before
	for id in range(8, 13): assert_int(P0Garden.cell_of(id).y).is_equal(11)
	for id in range(13, table.size()): assert_int(P0Garden.cell_of(id).y).is_less_equal(P0Garden.cell_of(id - 1).y)
	assert_int(P0Garden.grid_of(-1).x).is_equal(-100)   # off the table
	assert_int(P0Garden.grid_of(63).x).is_equal(-100)

## Where the homestead has no bed yet is plain ground: walking there never steps up onto a bed (哪吒 on #215).
func test_no_bed_to_step_on_where_the_homestead_has_none_yet() -> void:
	var bp := P0Garden.blueprint()
	var at := bp.cell_to_world(P0Garden.cell_of(9))
	assert_bool(P0Garden.on_bed(bp, at, {"garden": {"plots": 8}})).is_false()
	assert_bool(P0Garden.on_bed(bp, at, {"garden": {"plots": 10}})).is_true()
	assert_bool(P0Garden.on_bed(bp, bp.cell_to_world(P0Garden.cell_of(7)), {"garden": {"plots": 8}})).is_true()

## The view's garden.plots decides how many beds are open (Homestead Lv1 8 … Lv17 41, plus the trees and sprinklers).
func test_plot_count_follows_the_view() -> void:
	assert_int(P0Garden.plot_count({"garden": {"plots": 8}})).is_equal(8)
	assert_int(P0Garden.plot_count({"garden": {"plots": 41}})).is_equal(41)
	assert_int(P0Garden.plot_count({"garden": {"plots": 99}})).is_equal(P0Garden.max_plots())
	var view := {"plots": [{"id": 9, "state": "wild"}], "garden": {"plots": 8}}
	assert_bool(P0Garden.cells(view, 0).is_empty()).is_true()   # a plot the view does not have yet is not drawn
	view.garden.plots = 10
	assert_bool(P0Garden.cells(view, 0).has(P0Garden.cell_id(P0Garden.cell_of(9)))).is_true()

func test_beds_can_be_walked_on_but_facilities_and_rocks_block() -> void:
	# 2026-10-05 device review: crops don't collide; trees (yard edge), rocks and facilities do.
	var bp := P0Garden.blueprint()
	var grid := BlueprintGrid.new(bp)
	var spawn := bp.anchor("spawn")
	assert_bool(bp.is_walkable(spawn)).is_true()
	for id in P0Garden.plot_count():
		var c := P0Garden.cell_of(id)
		assert_bool(bp.is_walkable(c)).is_true()
		assert_bool(bp.mask_has("cultivable", c)).is_true()
		assert_bool(grid.path(spawn, c).is_empty()).is_false()
		assert_bool(P0Garden.on_bed(bp, bp.cell_to_world(c))).is_true()
		assert_bool(P0Garden.on_bed(bp, bp.cell_to_world(c + Vector2i(1, 0)))).is_false()
	for key in ["house", "storage", "well", "bench"]:
		assert_bool(bp.is_walkable(bp.anchor(key))).is_false()
	var rock := bp.cell_to_world(Vector2i(17, 5))   # a walkway between two beds
	P0Garden.block_points(bp, [rock])
	assert_bool(bp.is_walkable(Vector2i(17, 5))).is_false()

func test_view_maps_to_old_cell_states() -> void:
	var view := {"crops": [{"id": "crop_radish", "grow_h": 4}], "plots": [
		{"id": 0, "state": "wild"}, {"id": 1, "state": "tilled"},
		{"id": 2, "state": "sown", "crop": "crop_radish"},
		{"id": 3, "state": "growing", "crop": "crop_radish", "ready_in": 7200000},
		{"id": 4, "state": "ready", "crop": "crop_radish"}]}
	var cells := P0Garden.cells(view, 10000000)
	assert_str(str(cells[P0Garden.cell_id(P0Garden.cell_of(0))].state)).is_equal("wild")
	assert_str(str(cells[P0Garden.cell_id(P0Garden.cell_of(2))].crop)).is_equal("R")
	var growing: Dictionary = cells[P0Garden.cell_id(P0Garden.cell_of(3))]
	assert_int(CropField.stage_of(growing, 10000000)).is_equal(1)   # halfway through a 4 h crop
	assert_int(CropField.stage_of(cells[P0Garden.cell_id(P0Garden.cell_of(4))], 10000000)).is_equal(3)

func test_every_p0_crop_has_a_plant() -> void:
	var content = JSON.parse_string(FileAccess.get_file_as_string("res://assets/p0/p0_content.json"))
	for crop in content.crops:
		var code := str(P0Garden.CROP_CODES.get(str(crop.id), ""))
		assert_str(code).is_not_empty()
		assert_bool(CropField.CROPS.has(code)).is_true()

## The sand lies under the beds open now and the walkways between (不知火舞 282 bf7c124b: one patch); the beds still to
## open stay grass (SGODOT-355 b1).
func test_the_sand_covers_the_open_beds_only() -> void:
	var bp := P0Garden.blueprint()
	var scenery: Node3D = auto_free(load("res://scenes/p0/p0_garden_scenery.gd").new())
	add_child(scenery)
	scenery.build(bp, "cottage")
	var sand: Node3D = scenery.get_node("FieldSand")
	var right_edge := func() -> float: return sand.position.x + sand.scale.x * 1.26 * 0.5
	var front_edge := func() -> float: return sand.position.z + sand.scale.z * 1.26 * 0.5   # nearest the camera
	scenery.fit_sand(bp, 8)   # Homestead Lv1: the starting 2 × 4
	var start_right := bp.cell_to_world(P0Garden.cell_of(3)).x
	assert_float(right_edge.call()).is_greater(start_right + 0.47)
	assert_float(right_edge.call()).is_less(bp.cell_to_world(P0Garden.cell_of(8)).x - 0.47)   # bed 8 (next to open) on grass
	assert_float(front_edge.call()).is_less(bp.cell_to_world(P0Garden.cell_of(18)).z - 0.47)   # the next row out too
	scenery.fit_sand(bp, P0Garden.max_plots())
	var all: Rect2 = scenery.beds_rect(bp, P0Garden.max_plots())
	assert_float(right_edge.call()).is_greater(all.end.x)
	assert_float(front_edge.call()).is_greater(all.end.y)
