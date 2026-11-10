extends GdUnitTestSuite
## The farm's woods (SGODOT-422 0.3.5; the user 11-09): the same every time, no trunk in the yard, no crown
## over the yard on screen, the clumps off the beds that are open and their neighbours.

const FarmWoods = preload("res://scenes/p0/p0_farm_woods.gd")

func _woods() -> FarmWoods:
	var w: FarmWoods = auto_free(FarmWoods.new())
	w.build(P0Garden.blueprint())
	return w

func _trees(w: FarmWoods) -> Array:   # [asset, Transform3D] of every tree
	return w.trees_placed

func test_the_same_woods_every_build() -> void:
	var a := _trees(_woods())
	var b := _trees(_woods())
	assert_int(a.size()).is_greater(100)
	assert_str(str(a).sha256_text()).is_equal(str(b).sha256_text())

func test_no_trunk_in_the_yard_and_no_crown_over_it() -> void:
	for e in _trees(_woods()):
		var t: Transform3D = e[1]
		var p := Vector2(t.origin.x, t.origin.z)
		assert_bool(FarmWoods.OUT.has_point(p)).is_false()
		for kind in FarmWoods.HEIGHT:
			if str(e[0]).begins_with(str(kind)):
				var s := t.basis.get_scale().x
				assert_bool(FarmWoods.hides(p, float(FarmWoods.HEIGHT[kind]) * s, float(FarmWoods.RADIUS[kind]) * s)).is_false()

## Nothing in the woods collides: the walk mask and the path grid are the farm's as built without them.
func test_the_walk_mask_is_untouched() -> void:
	var bp := P0Garden.blueprint()
	var before := str(bp.masks.walkable).hash()
	var w: FarmWoods = auto_free(FarmWoods.new())
	w.build(bp)
	assert_int(str(bp.masks.walkable).hash()).is_equal(before)

func test_clumps_leave_the_open_beds_and_their_neighbours() -> void:
	var bp := P0Garden.blueprint()
	var w := _woods()
	w.fit(bp, 8)
	var at8 := w.shown_bed_clumps()
	assert_int(at8).is_greater(0)
	w.fit(bp, 40)
	assert_int(w.shown_bed_clumps()).is_less(at8)
	w.fit(bp, P0Garden.max_plots())
	assert_int(w.shown_bed_clumps()).is_equal(0)

## 上官婉儿 11-10 b: on the beds still to open only flat little flowers and grass — no stone, nothing over LOW.
func test_bed_clumps_are_low_and_stoneless() -> void:
	var w := _woods()
	for key in w.counts:
		if str(key).begins_with("bed:"): assert_bool(str(key).contains("rock")).is_false()
	for e in w._beds:   # [bed, MultiMesh, index, Transform3D] (the batches hold them on the GPU only)
		var h: float = (e[1] as MultiMesh).mesh.get_aabb().size.y
		assert_float((e[3] as Transform3D).basis.get_scale().y * h).is_less_equal(FarmWoods.LOW + 0.005)
	assert_int(w._beds.size()).is_greater(50)

## 奕星 11-09: a cell a Decorate piece stands on shows no blade or flower.
func test_no_clump_under_a_decor_piece() -> void:
	var bp := P0Garden.blueprint()
	var w := _woods()
	w.fit(bp, 8)
	var shown := w.shown_bed_clumps()
	var taken: Array = []
	for e in w._beds:
		if w._shown.get(w._beds.find(e), false): taken.append(bp.world_to_cell((e[3] as Transform3D).origin))
		if taken.size() >= 5: break
	w.fit(bp, 8, taken)
	assert_int(w.shown_bed_clumps()).is_less(shown)
	for k in w._beds.size():
		if w._shown.get(k, false): assert_bool(taken.has(bp.world_to_cell((w._beds[k][3] as Transform3D).origin))).is_false()

## 上官婉儿 11-10: no light round crown on the farm; the Lv1 opening's tall pines on the left stand.
func test_no_light_crown_behind_and_the_left_pines() -> void:
	var w := _woods()
	var left := 0
	for e in w.trees_placed:
		var o: Vector3 = (e[1] as Transform3D).origin
		assert_str(str(e[0])).is_not_equal("wild_pz_tree_20_lt")
		for lp in FarmWoods.LEFT_PINES:
			if Vector2(o.x, o.z).distance_to(Vector2(lp[1], lp[2])) < 1.05: left += 1   # the exit may move one up to 1 m
	assert_int(left).is_equal(FarmWoods.LEFT_PINES.size())

## 上官婉儿 11-10: the exit pin at (0.8, 1.0) — no trunk within EXIT_R, no crown over it on screen; the rest as before.
func test_the_exit_pin_stays_clear() -> void:
	for e in _woods().trees_placed:
		var t: Transform3D = e[1]
		var p := Vector2(t.origin.x, t.origin.z)
		for kind in FarmWoods.HEIGHT:
			if str(e[0]).begins_with(str(kind)):
				var s := t.basis.get_scale().x
				assert_bool(FarmWoods.covers_exit(p, float(FarmWoods.HEIGHT[kind]) * s, float(FarmWoods.RADIUS[kind]) * s)).is_false()

## The woods clear the exit where the farm puts it (C7, #943): one place, two constants — a move of one moves both.
func test_the_woods_clear_the_farms_exit() -> void:
	var at: Vector3 = preload("res://scenes/p0/p0_farm.gd").EXIT_AT
	assert_vector(FarmWoods.EXIT).is_equal(Vector2(at.x, at.z))

## 上官婉儿's column rule (443 190fa019), checked on what stands: in x 0.2–1.4 (± a piece's radius) z − 1.07 × h ≥ 1.45.
func test_the_exit_column_rule() -> void:
	for e in _woods().trees_placed:
		var t: Transform3D = e[1]
		for kind in FarmWoods.HEIGHT:
			if str(e[0]).begins_with(str(kind)):
				var s := t.basis.get_scale().x
				var r := float(FarmWoods.RADIUS[kind]) * s
				if t.origin.z > 1.0 and t.origin.x + r >= FarmWoods.EXIT_COL.x and t.origin.x - r <= FarmWoods.EXIT_COL.y:
					assert_float(t.origin.z - 1.07 * float(FarmWoods.HEIGHT[kind]) * s).is_greater_equal(1.45)

## The west hedge (SGODOT-371, 不知火舞 59ea8ecc ③) after four moved for the exit (371 dd50e433): still a hedge —
## next clumps 0.3–1.1 m apart, no gap over 1.2 m between them; and none on the exit's ring: 0.3 m clear of it on the
## ground, and in front of it z − 1.07 × h ≥ 1.45 (the bush is 0.6 m tall, 0.87 m across, at scale 1).
const Scenery = preload("res://scenes/p0/p0_garden_scenery.gd")
func test_the_west_hedge_stays_a_hedge_and_clears_the_exit() -> void:
	var h: Array = Scenery.WEST_HEDGE
	var exit := Vector2(P0Garden.MAP_EXIT.x, P0Garden.MAP_EXIT.z)
	for i in h.size():
		var a: Vector3 = h[i][0]
		var r := 0.4335 * float(h[i][2])
		if i + 1 < h.size():
			var b: Vector3 = h[i + 1][0]
			var d := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
			assert_float(d).override_failure_message("%s → %s" % [a, b]).is_between(0.3, 1.1)
			assert_float(d - r - 0.4335 * float(h[i + 1][2])).is_less_equal(1.2)
		var p := Vector2(a.x, a.z)
		assert_float(p.distance_to(exit) - r - 0.38).override_failure_message("%s on the ring" % p).is_greater_equal(0.3)
		if p.y > exit.y and p.x + r >= FarmWoods.EXIT_COL.x and p.x - r <= FarmWoods.EXIT_COL.y:
			assert_float(p.y - 1.07 * 0.6 * float(h[i][2])).override_failure_message("%s in front of the ring" % p).is_greater_equal(1.45)

## The same, in plain numbers (周瑜 on #945: not covers_exit against itself): no trunk within 1.2 m of the exit, and
## the exit is where these numbers say, (0.8, 1.0).
func test_the_exit_corner_in_numbers() -> void:
	var w := _woods()
	for e in w.trees_placed:
		var o: Vector3 = (e[1] as Transform3D).origin
		assert_float(Vector2(o.x, o.z).distance_to(Vector2(0.8, 1.0))).override_failure_message("%s at %s" % [e[0], o]).is_greater_equal(1.2)
	assert_vector(Vector2(P0Garden.MAP_EXIT.x, P0Garden.MAP_EXIT.z)).is_equal(Vector2(0.8, 1.0))
