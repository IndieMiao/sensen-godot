extends GdUnitTestSuite
## P0 garden: the earlier fixed-plot spec grown to 30 beds; P0 view → CropField cells.

func test_plot_ids_and_cells_are_a_bijection_on_spaced_beds() -> void:
	var seen := {}
	for id in P0Garden.plot_count():
		var c := P0Garden.cell_of(id)
		assert_int(P0Garden.id_of(c)).is_equal(id)
		seen[c] = true
		# beds stand two cells apart, so every bed has a walkway beside it
		assert_int(P0Garden.id_of(c + Vector2i(1, 0))).is_equal(-1)
		assert_int(P0Garden.id_of(c + Vector2i(0, 1))).is_equal(-1)
	assert_int(seen.size()).is_equal(40)   # P1: all 40 laid out; the view's garden.plots shows 30 or 40

## P1 (q(59) §1.1): the client grid is the server's (content.garden.plots: the sprinkler's coverage is judged there).
## 0–29 keep their P0 cells; 30–39 are two columns right of the field, row by row.
func test_the_garden_grid_matches_the_content_table() -> void:
	var table: Array = P0Logic.content().garden.plots   # content/farm_garden.json, merged in (SGODOT-275)
	assert_array(P0Logic.content_errors).is_empty()
	assert_int(table.size()).is_equal(P0Garden.MAX_PLOTS)
	for id in table.size():
		assert_vector(P0Garden.grid_of(id)).override_failure_message("plot %d" % id).is_equal(Vector2i(int(table[id][0]), int(table[id][1])))
	for id in 30: assert_vector(P0Garden.cell_of(id)).is_equal(P0Garden.PLOT_ORIGIN + Vector2i((id % 6) * 2, (id / 6) * 2))
	assert_vector(P0Garden.cell_of(30)).is_equal(P0Garden.cell_of(5) + Vector2i(2, 0))
	assert_vector(P0Garden.cell_of(39)).is_equal(P0Garden.cell_of(29) + Vector2i(4, 0))

## At Homestead Lv1–2 the place of beds 30–39 is plain ground: walking there never steps up onto a bed (哪吒 on #215).
func test_no_bed_to_step_on_where_the_homestead_has_none_yet() -> void:
	var bp := P0Garden.blueprint()
	var at := bp.cell_to_world(P0Garden.cell_of(31))
	assert_bool(P0Garden.on_bed(bp, at, {"garden": {"plots": 30}})).is_false()
	assert_bool(P0Garden.on_bed(bp, at, {"garden": {"plots": 40}})).is_true()
	assert_bool(P0Garden.on_bed(bp, bp.cell_to_world(P0Garden.cell_of(29)), {"garden": {"plots": 30}})).is_true()

## The view's garden.plots decides how many beds the homestead has (30 before Homestead Lv3, 40 from it).
func test_plot_count_follows_the_view() -> void:
	assert_int(P0Garden.plot_count({})).is_equal(30)
	assert_int(P0Garden.plot_count({"garden": {"plots": 40}})).is_equal(40)
	assert_int(P0Garden.plot_count({"garden": {"plots": 99}})).is_equal(P0Garden.MAX_PLOTS)
	var view := {"plots": [{"id": 31, "state": "wild"}], "garden": {"plots": 30}}
	assert_bool(P0Garden.cells(view, 0).is_empty()).is_true()   # a plot the view does not have yet is not drawn
	view.garden.plots = 40
	assert_bool(P0Garden.cells(view, 0).has(P0Garden.cell_id(P0Garden.cell_of(31)))).is_true()

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
	for key in ["house", "storage", "well", "mine", "bench"]:
		assert_bool(bp.is_walkable(bp.anchor(key))).is_false()
	var rock := bp.cell_to_world(Vector2i(18, 5))
	P0Garden.block_points(bp, [rock])
	assert_bool(bp.is_walkable(Vector2i(18, 5))).is_false()

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
