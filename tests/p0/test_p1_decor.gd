extends GdUnitTestSuite
## Decorate (SGODOT-284): the server judges a spot with content decor.yard; it must agree with the garden the client
## draws (P0Garden), so a piece never stands on a bed, in the house or on a facility the player can see.

func _yard() -> Dictionary:
	return P0Logic.content().get("decor", {}).get("yard", {})

func _blocked(cell: Vector2i) -> bool:
	for r in _yard().get("blocked", []):
		if Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])).has_point(cell): return true
	return false

func test_every_footprint_and_plot_of_the_garden_is_off_the_yard() -> void:
	assert_bool(_yard().is_empty()).is_false()
	for key in P0Garden.FOOTPRINTS:
		var f: Rect2i = P0Garden.FOOTPRINTS[key]
		for y in range(f.position.y, f.end.y):
			for x in range(f.position.x, f.end.x):
				assert_bool(_blocked(Vector2i(x, y))).override_failure_message("%s at %d,%d" % [key, x, y]).is_true()
	for id in 40:   # P0's 30 and the two P1 columns (q(59)): the field and its walkways
		var grid := Vector2i(id % 6, id / 6) if id < 30 else Vector2i(6 + (id - 30) % 2, (id - 30) / 2)   # #215's grid_of
		var c := P0Garden.PLOT_ORIGIN + grid * 2
		assert_bool(_blocked(c)).override_failure_message("plot %d at %s" % [id, str(c)]).is_true()
	var walk: Array = _yard().get("walk", [])
	assert_that(Rect2i(int(walk[0]), int(walk[1]), int(walk[2]), int(walk[3]))).is_equal(P0Garden.WALK_RECT)
	var spawn: Vector2i = P0Garden.ANCHORS.spawn   # JSON numbers load as floats: compare as cells
	assert_bool(_yard().get("keep_clear", []).any(func(k): return Vector2i(int(k[0]), int(k[1])) == spawn)).is_true()

func test_the_catalog_and_the_stall_shelf_keeps_decor_off_until_its_page() -> void:
	var items: Dictionary = P0Logic.content().get("decor", {}).get("items", {})
	assert_int(items.size()).is_equal(11)
	assert_str(str(items.deco_bench.name)).is_equal("Wooden Bench")
	var v := {"shops": {"homestead": {"buy": [{"id": "seed_radish"}, {"id": "deco_planter"}]}}}
	var d := P0CounterDrawer.new(v, "homestead")
	assert_array(d.offers().map(func(o): return str(o.id))).is_equal(["seed_radish"])
	d.free()
